export const meta = {
  name: 'impl-unit',
  description: 'Implement one design unit: plan, execute, review (challenge/decide), fix, push, hygiene',
  phases: [
    { title: 'Plan', detail: 'opus: resolve all unknowns into a mechanical plan', model: 'opus' },
    { title: 'Execute', detail: 'sonnet: carry out the plan and commit', model: 'sonnet' },
    { title: 'Foundation', detail: 'sonnet: implement the shared foundation group (no commit)', model: 'sonnet' },
    { title: 'Modules', detail: 'sonnet: implement each module group in parallel (no commit)', model: 'sonnet' },
    { title: 'Commit', detail: 'sonnet: commit each group sequentially via git-commit', model: 'sonnet' },
    { title: 'GapCheck', detail: 'opus: verify every plan item is implemented', model: 'opus' },
    { title: 'GapFix', detail: 'sonnet: fill the gaps the gapcheck found', model: 'sonnet' },
    { title: 'Prep', detail: 'sonnet: size the diff and pick review dimensions', model: 'sonnet' },
    { title: 'Review', detail: 'opus: per-dimension reviewers', model: 'opus' },
    { title: 'Challenge', detail: 'opus: contest the findings', model: 'opus' },
    { title: 'Decide', detail: 'opus: rule which findings survive', model: 'opus' },
    { title: 'Fix', detail: 'sonnet: apply the decided findings', model: 'sonnet' },
    { title: 'Verify', detail: 'opus: scoped check that decided findings are resolved and no new regressions', model: 'opus' },
    { title: 'Push', detail: 'sonnet: commit the rollup and open the PR', model: 'sonnet' },
    { title: 'Hygiene', detail: 'sonnet: doc/PR-description hygiene', model: 'sonnet' },
  ],
}

// args (from the impl launcher): { homeDir, worktree, slug, base, dims }
// unit_key/design_id are not passed: phases read them from .autocode/.impl-context in the worktree.
// The runtime may deliver args as a JSON string rather than a parsed object.
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const HOME = A.homeDir
const WT = A.worktree
const SLUG = A.slug
const BASE = A.base
const DIMS = A.dims ? String(A.dims).split(',').map((d) => d.trim()).filter(Boolean) : null
const FANOUT = A.fanout || 'auto' // 'auto' | 'off' | 'on'
const MAX_FIX_ROUNDS = 2
const GAP_MAX_ROUNDS = 2

// Fan-out lives here in the workflow runtime to keep heavy work off the
// launching context, not because nesting is impossible (nested subagents are
// supported as of CC v2.1.172). Agents run skills by reading the canonical body
// by absolute path (the skill catalog is not reliably visible to workflow agents).
const skill = (name) => `${HOME}/.autocode/autocode/impl/skills/${name}/SKILL.md`
const inWt = `Work in the git worktree at ${WT}: cd into it before doing anything. `
const follow = (path, extra) => `Read the skill at ${path} and follow it exactly. ${extra}`
const readOnly = 'You are a read-only reviewer: never edit, write, or run mutating commands. '

// leanness: the spawned agent reads .impl-context for progress_log because the
// workflow runtime does no file/git I/O (every agent() delegates it). Same
// source the Stop hook reads. Facts (phase + verbatim note) fire the agent's
// fast path, skipping git inspection.
const progressLoggerAgent = `${HOME}/.autocode/autocode/impl/agents/progress-logger.md`
const logProgress = (phase, note) =>
  agent(
    inWt + follow(progressLoggerAgent,
      'Facts-provided fast path: skip the git-inspection steps. ' +
      'Read `.autocode/.impl-context` (jq `.progress_log`) for the progress log path; ' +
      `the unit slug is "${SLUG}". ` +
      `Append the note below verbatim under a \`## <UTC timestamp> [${phase}]\` heading ` +
      '(generate the UTC timestamp with `date -u`), appending via Bash `>>` and touching only that file. ' +
      `Note: ${note}`),
    { label: `log:${phase}`, phase, model: 'sonnet' },
  )

const PREP_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    empty: { type: 'boolean' },
    diff_lines: { type: 'integer' },
    changed_files: { type: 'array', items: { type: 'string' } },
    dimensions: { type: 'array', items: { type: 'string' } },
  },
  required: ['empty', 'diff_lines', 'changed_files', 'dimensions'],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          dimension: { type: 'string' },
          severity: { type: 'string', enum: ['Important', 'Nit', 'Pre-existing'] },
          claim: { type: 'string' },
          evidence: { type: 'string' },
        },
        required: ['file', 'line', 'dimension', 'severity', 'claim', 'evidence'],
      },
    },
  },
  required: ['findings'],
}

const CHALLENGE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          verdict: { type: 'string', enum: ['refuted', 'weakened', 'unrefuted'] },
          reason: { type: 'string' },
        },
        required: ['id', 'verdict', 'reason'],
      },
    },
  },
  required: ['verdicts'],
}

const DECIDE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    actionable: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['Important', 'Nit'] },
          claim: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['file', 'line', 'severity', 'claim', 'fix'],
      },
    },
    dropped: { type: 'integer' },
    tally: { type: 'string' },
  },
  required: ['actionable', 'dropped', 'tally'],
}

const PUSH_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    pr_url: { type: 'string' },
    branch: { type: 'string' },
    hygiene_shas: { type: 'array', items: { type: 'string' } },
    hygiene_files: { type: 'array', items: { type: 'string' } },
  },
  required: ['pr_url', 'branch', 'hygiene_shas', 'hygiene_files'],
}

const PLAN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    files_total: { type: 'integer' },
    heavy: { type: 'boolean' },
    partitionable: { type: 'boolean' },
    foundation: {
      type: ['object', 'null'],
      additionalProperties: false,
      properties: {
        files: { type: 'array', items: { type: 'string' } },
        summary: { type: 'string' },
      },
      required: ['files', 'summary'],
    },
    modules: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          name: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          summary: { type: 'string' },
        },
        required: ['name', 'files', 'summary'],
      },
    },
  },
  required: ['files_total', 'heavy', 'partitionable', 'foundation', 'modules'],
}

const GAPCHECK_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    complete: { type: 'boolean' },
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          file: { type: 'string' },
          plan_item: { type: 'string' },
          detail: { type: 'string' },
        },
        required: ['file', 'plan_item', 'detail'],
      },
    },
  },
  required: ['complete', 'gaps'],
}

const importantOf = (decided) => decided.actionable.filter((a) => a.severity === 'Important')

async function reviewCycle(tag) {
  const defaultDims = DIMS ? JSON.stringify(DIMS) : '["correctness","security","performance","leanness"]'
  const prep = await agent(
    inWt +
      `Build the review context for the branch diff against ${BASE}. Count changed lines across \`git diff ${BASE}...HEAD\`, \`git diff HEAD\`, and untracked files from \`git status --porcelain\`; list the changed files; choose dimensions: under ~50 changed lines use ["correctness"], otherwise use ${defaultDims}. Set empty=true only when there is no diff at all.`,
    { label: `prep${tag}`, phase: 'Prep', model: 'sonnet', schema: PREP_SCHEMA },
  )
  if (prep.empty || !prep.dimensions.length) return { actionable: [], dropped: 0, tally: 'no diff to review' }

  const reviewed = await parallel(prep.dimensions.map((dim) => () =>
    agent(
      inWt + readOnly +
        `Assemble the review context yourself: compute the diff (\`git diff ${BASE}...HEAD\`, \`git diff HEAD\`, untracked via \`git status --porcelain\`), gather the changed files and the matching CLAUDE.md and .claude/rules. ` +
        (dim === 'security' ? 'Strip commit messages and any PR/branch description from what you read (framing bias suppresses detection). ' : '') +
        follow(skill('impl-critique-review'), `Review only the "${dim}" dimension and return the findings.`),
      { label: `review:${dim}${tag}`, phase: 'Review', model: 'opus', schema: FINDINGS_SCHEMA },
    )))

  const seen = new Set()
  const findings = []
  for (const f of reviewed.filter(Boolean).flatMap((r) => r.findings)) {
    if (!f.file || f.line == null || !f.claim) continue
    const key = `${f.file}:${f.line}|${f.claim}`
    if (seen.has(key)) continue
    seen.add(key)
    findings.push({ id: `F${findings.length + 1}`, ...f })
  }
  if (!findings.length) return { actionable: [], dropped: 0, tally: 'no findings' }

  const challenge = await agent(
    inWt + readOnly + follow(skill('impl-critique-challenge'),
      `Challenge these findings. Findings JSON:\n${JSON.stringify(findings)}`),
    { label: `challenge${tag}`, phase: 'Challenge', model: 'opus', schema: CHALLENGE_SCHEMA },
  )

  const decided = await agent(
    inWt + readOnly + follow(skill('impl-critique-decide'),
      `Decide which findings survive. Findings JSON:\n${JSON.stringify(findings)}\nChallenges JSON:\n${JSON.stringify(challenge.verdicts)}`),
    { label: `decide${tag}`, phase: 'Decide', model: 'opus', schema: DECIDE_SCHEMA },
  )
  return decided
}

phase('Plan')
const plan = await agent(
  inWt + follow(skill('impl-plan'),
    `Run it in --auto mode for unit ${SLUG}. It writes the mechanical plan to .autocode/.impl-plan.md. Return the plan path and a one-line summary. ` +
    'Also return the module partition and a self-assessed heaviness, from the `## Module partition` section you write into the plan: ' +
    'set `partitionable`/`foundation`/`modules`/`files_total` from that section (do NOT re-infer the grouping from the file list). ' +
    'Set `files_total` to the count of ALL in-scope planned files across the whole per-file task list, independent of the partition. ' +
    'Set `partitionable` true only when the section declares genuine file-disjoint modules (>=2); a missing section, a non-partitionable declaration, or a single module means `partitionable: false` with `modules: []`. ' +
    'Set `foundation` to the `### Foundation` group ({ files, summary }) when present, else null. ' +
    'Self-assess `heavy`: compaction risk over a single Execute agent (file count, total plan size, cross-file coupling); a small, loosely-coupled plan is not heavy.'),
  { label: 'plan', phase: 'Plan', model: 'opus', schema: PLAN_SCHEMA },
)
await logProgress('Plan', 'Plan phase: mechanical plan written to .autocode/.impl-plan.md.')

// files_total rides the plan output unread here; it exists for the downstream
// per-module-gapcheck sibling's contract, not for this workflow's own logic.
const heavy = !!plan && plan.heavy
const fanout = !!plan &&
  FANOUT !== 'off' &&
  plan.partitionable &&
  plan.modules.length >= 2 &&
  (FANOUT === 'on' || heavy)

phase('Execute')
if (fanout) {
  let foundationOk = true
  if (plan.foundation) {
    phase('Foundation')
    const found = await agent(
      inWt + follow(skill('impl-execute'),
        'Run it in --auto --no-commit --module foundation mode. Implement ONLY the `### Foundation` group of the plan\'s `## Module partition`, leave all changes uncommitted in the working tree, and report the files written.'),
      { label: 'foundation', phase: 'Foundation', model: 'sonnet' },
    )
    foundationOk = found != null
  }
  if (foundationOk) {
    phase('Modules')
    await parallel(plan.modules.map((m) => () =>
      agent(
        inWt + follow(skill('impl-execute'),
          `Run it in --auto --no-commit --module ${m.name} mode. Implement ONLY the "${m.name}" module group of the plan's \`## Module partition\`, leave all changes uncommitted in the working tree, and report the files written.`),
        { label: `module:${m.name}`, phase: 'Modules', model: 'sonnet' },
      )))
    phase('Commit')
    const commitOrder = (plan.foundation ? ['foundation'] : []).concat(plan.modules.map((m) => m.name))
    await agent(
      inWt + follow(`${HOME}/.autocode/autocode/git/skills/git-commit/SKILL.md`,
        'Parallel module agents wrote changes to the working tree without committing. ' +
        `Stage and commit each group as one logical commit, in this order: ${JSON.stringify(commitOrder)}. ` +
        'For each group, stage only that group\'s files (from the plan\'s `## Module partition`) and commit via this skill, one commit per group. Do not squash groups together.'),
      { label: 'commit', phase: 'Commit', model: 'sonnet' },
    )
  } else {
    // Foundation failed: modules would build blind against missing shared types.
    // Fall through to a clean single-agent pass over the whole plan.
    log('foundation pass failed; falling back to single-agent execute')
    await agent(
      inWt + follow(skill('impl-execute'),
        'Run it in --auto mode. It reads .autocode/.impl-plan.md, implements the unit, and commits via git-commit. Return a one-paragraph summary of what shipped.'),
      { label: 'execute', phase: 'Execute', model: 'sonnet' },
    )
  }
} else {
  await agent(
    inWt + follow(skill('impl-execute'),
      'Run it in --auto mode. It reads .autocode/.impl-plan.md, implements the unit, and commits via git-commit. Return a one-paragraph summary of what shipped.'),
    { label: 'execute', phase: 'Execute', model: 'sonnet' },
  )
}
await logProgress('Execute', `Execute phase: plan implemented and committed${fanout ? ' (module fanout)' : ''}.`)

let gapRoundsUsed = 0
let remainingGaps = 0
if (heavy) {
  let gapRound = 0
  let gap = await agent(
    inWt + readOnly + follow(skill('impl-gapcheck'),
      `Check spec completeness. Plan: .autocode/.impl-plan.md. Diff: compute it yourself via \`git diff ${BASE}...HEAD\`, \`git diff HEAD\`, and untracked files from \`git status --porcelain\`. Return { complete, gaps }.`),
    { label: 'gapcheck-r0', phase: 'GapCheck', model: 'opus', schema: GAPCHECK_SCHEMA },
  )
  while (gap && !gap.complete && gap.gaps.length && gapRound < GAP_MAX_ROUNDS) {
    gapRound += 1
    log(`gap round ${gapRound}: ${gap.gaps.length} gap(s)`)
    await agent(
      inWt + follow(skill('impl-execute'),
        `Run it in --fix --auto mode. Implement these missing plan items minimally and commit:\n${JSON.stringify(gap.gaps)}`),
      { label: `gapfix-r${gapRound}`, phase: 'GapFix', model: 'sonnet' },
    )
    gap = await agent(
      inWt + readOnly + follow(skill('impl-gapcheck'),
        `Re-check spec completeness. Plan: .autocode/.impl-plan.md. Diff: compute it yourself via \`git diff ${BASE}...HEAD\`, \`git diff HEAD\`, and untracked from \`git status --porcelain\`. Return { complete, gaps }.`),
      { label: `gapcheck-r${gapRound}`, phase: 'GapCheck', model: 'opus', schema: GAPCHECK_SCHEMA },
    )
  }
  gapRoundsUsed = gapRound
  remainingGaps = gap && gap.gaps ? gap.gaps.length : 0
  await logProgress('GapCheck', `GapCheck phase: ${gapRoundsUsed} gap round(s); ${remainingGaps} gap(s) remaining.`)
}

let round = 0
let decided = await reviewCycle(`-r${round}`)
while (importantOf(decided).length && round < MAX_FIX_ROUNDS) {
  round += 1
  log(`fix round ${round}: ${importantOf(decided).length} important finding(s)`)
  await agent(
    inWt + follow(skill('impl-execute'),
      `Run it in --fix --auto mode. Apply these decided findings minimally and commit:\n${JSON.stringify(importantOf(decided))}`),
    { label: `fix-r${round}`, phase: 'Fix', model: 'sonnet' },
  )
  const verify = await agent(
    inWt + readOnly + follow(skill('impl-critique-verify'),
      'Verify the fixes just applied this round. The decided findings applied this round ' +
      `(each file:line, severity, claim, fix):\n${JSON.stringify(importantOf(decided))}\n` +
      `Base ref: ${BASE}. Compute the fix-commit diff yourself. Confirm each finding is resolved; ` +
      'diff-scan the fix commits for NEW regressions outside the decided set. ' +
      'Return a DECIDE_SCHEMA object (actionable[] keyed on severity Important|Nit, dropped, tally); ' +
      'decline by returning no structured object on low confidence.'),
    { label: `verify-r${round}`, phase: 'Verify', model: 'opus', schema: DECIDE_SCHEMA },
  )
  decided = verify || await reviewCycle(`-r${round}`)
}
if (round > 0) await logProgress('Fix', `Fix phase: ${round} fix round(s); ${importantOf(decided).length} important finding(s) remaining.`)

const needsHuman = importantOf(decided).length > 0 || remainingGaps > 0

phase('Push')
const push = await agent(
  inWt + follow(skill('impl-push'),
    'Run it with --auto --no-pr-hygiene. Commit the progress rollup, open the PR, link the issue, and advance the sub-issue. Return the PR URL, branch, and the pr-hygiene SHA list and changed-file list it surfaced.'),
  { label: 'push', phase: 'Push', model: 'sonnet', schema: PUSH_SCHEMA },
)

phase('Hygiene')
await agent(
  inWt + follow(`${HOME}/.autocode/autocode/pr/agents/pr-hygiene.md`,
    `Assess documentation impact and PR-description currency for the PR just opened: ${push.pr_url}. Pushed commits: ${JSON.stringify(push.hygiene_shas)}. Changed files: ${JSON.stringify(push.hygiene_files)}.`),
  { label: 'hygiene', phase: 'Hygiene', model: 'sonnet' },
)

return {
  pr_url: push.pr_url,
  branch: push.branch,
  fix_rounds: round,
  remaining_important: importantOf(decided).length,
  review_tally: decided.tally,
  fanout_used: fanout,
  gap_rounds: gapRoundsUsed,
  remaining_gaps: remainingGaps,
  needs_human: needsHuman,
}
