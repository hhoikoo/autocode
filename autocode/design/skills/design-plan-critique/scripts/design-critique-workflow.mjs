export const meta = {
  name: 'design-critique',
  description: 'Critique loop: generate questions, resolve via research, apply in place, cap 5',
  phases: [
    { title: 'Question', detail: "opus: generate this pass's follow-up questions", model: 'opus' },
    { title: 'Resolve', detail: 'opus: research each question (researcher-only)', model: 'opus' },
    { title: 'Apply', detail: 'sonnet: write resolutions into units + DESIGN + critique log', model: 'sonnet' },
  ],
}

// args (from the design-plan-critique --auto launcher): { homeDir, repoRoot, folder }
// The runtime may deliver args as a JSON string rather than a parsed object (mirrors impl-workflow.mjs).
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const HOME = A.homeDir
const REPO = A.repoRoot
const FOLDER = A.folder        // absolute path to the design folder
const MAX_ITERATIONS = 5

// Fail fast before any fan-out: missing paths mean args was not delivered.
if (!HOME || !REPO || !FOLDER) throw new Error('design-critique: args.homeDir/repoRoot/folder not delivered. Aborting before fan-out.')

// Agents run skills by reading the canonical body by absolute path
// (the skill catalog is not reliably visible to workflow agents).
const skill = (name) => `${HOME}/.autocode/autocode/design/skills/${name}/SKILL.md`
const follow = (path, extra) => `Read the skill at ${path} and follow it exactly. ${extra}`
const readOnly = 'You are a read-only reviewer: never edit, write, or run mutating commands. '
const CRITIQUE = skill('design-plan-critique')   // agents read this for heuristics (single-source)

const QUESTION_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    questions: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        properties: {
          id: { type: 'string' },           // stable within the pass, e.g. "Q1"
          question: { type: 'string' },
          target: { type: 'string' },        // 'DESIGN' or a unit slug
        },
        required: ['id', 'question', 'target'],
      },
    },
  },
  required: ['questions'],
}

const RESOLVE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    id: { type: 'string' },
    question: { type: 'string' },
    target: { type: 'string' },
    resolution: { type: 'string' },      // the answer to write, with its source cited
    source: { type: 'string' },          // research finding citation (every resolution cites its source)
    unresolved: { type: 'boolean' },     // true when research could not close it
    why: { type: 'string' },             // when unresolved: why research could not close it
  },
  required: ['id', 'question', 'target', 'resolution', 'source', 'unresolved', 'why'],
}

const APPLY_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: { file: { type: 'string' } },
  required: ['file'],
}

let iterations = 0
let resolvedCount = 0
const needsHumanReasons = []   // { question, why }
const filesModified = new Set()
let status = 'done'            // flips to 'cap_reached' if the cap stops an unconverged loop

while (iterations < MAX_ITERATIONS) {
  iterations += 1

  // --- Question phase: one agent, reads FOLDER's DESIGN.md + units/*.md and the CRITIQUE body ---
  phase('Question')
  const q = await agent(
    `Read the design at ${FOLDER} (DESIGN.md and every units/*.md, or just DESIGN.md if no units/). ` +
      follow(CRITIQUE,
        "Apply only its question-generation heuristics (SKILL step 2: untested assumptions, interface shapes, " +
        'error modes, concurrency, security, data shape, ordering invariants, unit decomposition and depends-on edges). ' +
        "Generate this pass's follow-up questions only. Account for resolutions already in the ## Critique log so you " +
        'do not re-raise closed questions. Return [] when nothing new remains.'),
    { label: `question-i${iterations}`, phase: 'Question', model: 'opus', schema: QUESTION_SCHEMA },
  )
  if (!q.questions.length) break   // converged: status stays 'done'

  // --- Resolve phase: one agent per question, in parallel, researcher-only (never asks the user) ---
  const resolved = await parallel(q.questions.map((item) => () =>
    agent(
      readOnly +
        `Resolve this critique question against the design at ${FOLDER} and the codebase at ${REPO} by dispatching a ` +
        `codebase-researcher (read-only research only; never ask the user). ` +
        follow(CRITIQUE,
          'Apply its resolution + source-citation rules (SKILL step 3 and Rules: every resolution cites its source). ' +
          'If research cannot close the question, set unresolved=true and explain why in `why`; do not abort.') +
        `\nQuestion JSON:\n${JSON.stringify(item)}`,
      { label: `resolve-i${iterations}-${item.id}`, phase: 'Resolve', model: 'opus', schema: RESOLVE_SCHEMA },
    )))

  const usable = resolved.filter(Boolean)
  const deferred = []        // questions left open this pass (resolve null or unresolved); logged as (deferred)
  for (let i = 0; i < resolved.length; i++) {
    if (!resolved[i]) {
      needsHumanReasons.push({ question: q.questions[i].question, why: 'resolve agent failed' })
      deferred.push({ ...q.questions[i], why: 'resolve agent failed' })
    }
  }
  for (const r of usable) {
    if (r.unresolved) {
      needsHumanReasons.push({ question: r.question, why: r.why })
      deferred.push(r)
    } else resolvedCount += 1
  }
  const applicable = usable.filter((r) => !r.unresolved)

  // --- Apply phase ---
  // Per-unit resolutions: one Apply agent per affected unit slug, in parallel (writes units/<slug>.md).
  // DESIGN.md edits + the ## Critique log append: a single serial agent (shared file).
  phase('Apply')
  const byUnit = new Map()                     // slug -> resolutions[]
  const designResolutions = []                 // target === 'DESIGN'
  for (const r of applicable) {
    if (r.target === 'DESIGN') designResolutions.push(r)
    else {
      if (!byUnit.has(r.target)) byUnit.set(r.target, [])
      byUnit.get(r.target).push(r)
    }
  }

  const unitWrites = await parallel([...byUnit.entries()].map(([slug, rs]) => () =>
    agent(
      `Write these resolutions in place into ${FOLDER}/units/${slug}.md. ` +
        follow(CRITIQUE,
          'Apply its in-place edit rules (SKILL step 4 and Rules: preserve section structure; never delete sections, ' +
          "mark resolved/deferred; cite each resolution's source).") +
        `\nResolutions JSON:\n${JSON.stringify(rs)}`,
      { label: `apply-i${iterations}-${slug}`, phase: 'Apply', model: 'sonnet', schema: APPLY_SCHEMA },
    )))
  for (const w of unitWrites.filter(Boolean)) filesModified.add(w.file)

  // Serial DESIGN.md + critique-log writer (always runs: appends the ## Critique log even when only units changed).
  const designWrite = await agent(
    `In ${FOLDER}/DESIGN.md: apply any DESIGN-targeted resolutions in place, then append this iteration's block to the ` +
      `## Critique log (create the section at the bottom if absent), one line per question with its resolution. ` +
      `Log each deferred question on its own line marked "(deferred)" with its \`why\` (never drop a question). ` +
      follow(CRITIQUE,
        'Apply its in-place edit + critique-log rules (SKILL step 4: ## Critique log lists each iteration\'s questions ' +
        'and resolutions; preserve structure; never delete sections; mark unresolved questions deferred).') +
      `\nDESIGN-targeted resolutions JSON:\n${JSON.stringify(designResolutions)}` +
      `\nAll resolutions this pass (for the log) JSON:\n${JSON.stringify(applicable)}` +
      `\nDeferred questions this pass (log each as (deferred)) JSON:\n${JSON.stringify(deferred)}` +
      `\nIteration number: ${iterations}`,
    { label: `apply-design-i${iterations}`, phase: 'Apply', model: 'sonnet', schema: APPLY_SCHEMA },
  )
  if (designWrite?.file) filesModified.add(designWrite.file)

  // The cap stops an unconverged loop: any work this pass (applied or deferred) means a clean
  // no-question pass was never reached. A final pass whose resolves were all null/unresolved
  // leaves only deferred work, so it must surface here rather than report 'done'.
  if (iterations >= MAX_ITERATIONS && (applicable.length > 0 || deferred.length > 0)) status = 'cap_reached'
}

const needsHuman = needsHumanReasons.length > 0 || status === 'cap_reached'
return {
  status,                                  // 'done' | 'cap_reached'
  iterations_run: iterations,
  questions_resolved: resolvedCount,
  needs_human: needsHuman,
  needs_human_reasons: needsHumanReasons,  // [{ question, why }, ...]
  files_modified: [...filesModified],
  critique_log_path: `${FOLDER}/DESIGN.md`,
}
