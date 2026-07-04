export const meta = {
  name: 'monitor-prs',
  description:
    'Monitor in-review PRs for an epic: per-PR check + --auto remediation, return typed verdicts. Never merges.',
  phases: [{ title: 'Check', detail: 'sonnet: per-PR status read and one --auto remediation', model: 'sonnet' }],
}

// args (from the impl monitor launcher): { homeDir, prs, maxConcurrent }
// prs = [{ pr:int, slug:str, branch:str, worktree:str }]
// The runtime may deliver args as a JSON string rather than a parsed object.
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const HOME = A.homeDir
const PRS = Array.isArray(A.prs) ? A.prs : []
const MAX_CONCURRENT = typeof A.maxConcurrent === 'number' && A.maxConcurrent > 0
  ? A.maxConcurrent
  : 3

// Resolve skill paths. pr-rebase, pr-fix-ci, pr-review live under autocode/pr/skills/.
const prSkill = (name) => `${HOME}/.autocode/autocode/pr/skills/${name}/SKILL.md`

// Absolute path to the provider run script.
const RUN_SH = `${HOME}/.autocode/provider/run.sh`

// Per-PR worktree prefix for checker prompts.
const inWt = (wt) => `Work in the git worktree at ${wt}: cd into it before doing anything. `

// Schema for the typed verdict each checker agent returns.
const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    pr: { type: 'integer' },
    slug: { type: 'string' },
    state: { type: 'string' },
    action_taken: { type: 'string', enum: ['none', 'rebase', 'fix-ci', 'review'] },
    merge_ready: { type: 'boolean' },
    needs_human: { type: 'boolean' },
    reason: { type: 'string' },
  },
  required: ['pr', 'slug', 'state', 'action_taken', 'merge_ready', 'needs_human', 'reason'],
}

// Build the decision-tree prompt for one PR checker agent.
// All branch conditions and field names are literal so the agent decides nothing structural.
function checkerPrompt(p) {
  return (
    inWt(p.worktree) +
    `Check PR #${p.pr} (slug: ${p.slug}) and return a typed verdict. ` +
    `Run these steps in order:\n\n` +
    `1. Read status: run \`${RUN_SH} git-remote pr-status ${p.pr}\`. ` +
    `Parse stdout as JSON -> fields: state, isDraft, mergeable, ci, reviewDecision. ` +
    `On non-zero exit return: { pr:${p.pr}, slug:"${p.slug}", state:"unknown", ` +
    `action_taken:"none", merge_ready:false, needs_human:true, reason:"pr-status failed: <stderr>" }.\n\n` +
    `2. Short-circuit: if state is "merged" or "closed", OR isDraft is true, return: ` +
    `{ pr:${p.pr}, slug:"${p.slug}", state:<state>, action_taken:"none", merge_ready:false, ` +
    `needs_human:false, reason:"<merged|closed|draft>, no action" }.\n\n` +
    `3. Run exactly ONE --auto remediation for the first applicable blocked condition ` +
    `(one per pass; re-checked next pass):\n` +
    `   a. If mergeable == "conflicting": read the skill at ${prSkill('pr-rebase')} and follow it exactly ` +
    `with --auto. Consume { rebased, conflicts_resolved, verify, needs_human, reason }. ` +
    `Set action_taken:"rebase".\n` +
    `   b. Else if ci == "failing": read the skill at ${prSkill('pr-fix-ci')} and follow it exactly ` +
    `with --auto. Consume { fixed, ci, needs_human, reason }. Set action_taken:"fix-ci".\n` +
    `   c. Else if reviewDecision == "changes_requested": read the skill at ${prSkill('pr-review')} ` +
    `and follow it exactly with --auto. Consume { applied, deferred, needs_human, reason }. ` +
    `Set action_taken:"review".\n` +
    `   d. Else: action_taken:"none", needs_human:false, reason:"no blocked condition".\n\n` +
    `   For cases a-c: the chosen remediation's needs_human becomes the verdict needs_human; ` +
    `its reason becomes the verdict reason. state echoes pr-status.state.\n\n` +
    `4. Compute merge_ready: true only when ALL of: state=="open" AND isDraft==false AND ` +
    `mergeable=="mergeable" AND ci=="passing" AND reviewDecision is "approved" or "none" AND ` +
    `action_taken=="none". The workflow never merges.\n\n` +
    `5. Return the verdict object matching this schema: ` +
    JSON.stringify(VERDICT_SCHEMA)
  )
}

phase('Check')
// Fan-out is capped at MAX_CONCURRENT (mirrors impl.max-concurrent-units) to bound
// parallel agent + build concurrency as in-review PRs accumulate toward epic size.
const chunks = []
for (let i = 0; i < PRS.length; i += MAX_CONCURRENT) {
  chunks.push(PRS.slice(i, i + MAX_CONCURRENT))
}
const verdicts = []
for (const chunk of chunks) {
  const batch = await parallel(
    chunk.map(
      (p) => () =>
        agent(checkerPrompt(p), {
          label: `check:${p.slug}#${p.pr}`,
          phase: 'Check',
          model: 'sonnet',
          schema: VERDICT_SCHEMA,
        }),
    ),
  )
  verdicts.push(...batch)
}

const live = verdicts.filter(Boolean)
const tally =
  `${live.length} checked, ` +
  `${live.filter((v) => v.merge_ready).length} merge-ready, ` +
  `${live.filter((v) => v.needs_human).length} need a human`

return { verdicts: live, tally }
