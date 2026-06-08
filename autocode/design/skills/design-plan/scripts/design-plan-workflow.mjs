export const meta = {
  name: 'design-plan',
  description: 'Plan phase off-context: research, DESIGN.md synthesis, worktree/branch/id/INDEX.md, unit-author fan-out with structured contract and bounded retry',
  phases: [
    { title: 'Research', detail: 'opus: interpret seed, fan-out codebase researchers for each gap', model: 'opus' },
    { title: 'Synthesize', detail: 'opus: compose DESIGN.md, derive shortname, create worktree/branch/id/INDEX.md, assign units', model: 'opus' },
    { title: 'Author', detail: 'opus: unit-author fan-out (one per unit)', model: 'opus' },
    { title: 'Resolve', detail: 'opus: bounded research-backed retry for underspecified units (cap one per unit)', model: 'opus' },
  ],
}

// args (from the design-plan --auto launcher or the /design orchestrator):
//   { homeDir, repoRoot, seed, temp }
// The workflow owns the entire heavy plan phase: research, synthesis, worktree creation,
// unit-author fan-out, and the bounded retry. The launcher passes paths + seed + temp.
const HOME = args.homeDir
const REPO = args.repoRoot
const SEED = String(args.seed || '')
const TEMP = Boolean(args.temp)

// Path helpers — agents read canonical bodies by absolute path;
// the skill/agent catalog is not reliably visible to workflow agents.
// Mirroring impl-workflow.mjs:19,29.
const designAgent = (name) => `${HOME}/.autocode/autocode/design/agents/${name}.md`
const designSkill = (name) => `${HOME}/.autocode/autocode/design/skills/${name}/SKILL.md`
const designFolder = `${HOME}/.autocode/autocode/design/design-folder.md`

// inWt: built from a worktree path returned by Synthesize (not from args, since the worktree
// does not exist at launch — Synthesize creates it). Available only to Author/Resolve phases.
const makeInWt = (wt) => `Work in the git worktree at ${wt}: cd into it before doing anything. `

// ── Schemas ─────────────────────────────────────────────────────────────────

// Gaps identified by the planning sub-agent in the Research phase.
const GAPS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          label: { type: 'string' },
          question: { type: 'string' },
        },
        required: ['label', 'question'],
      },
    },
  },
  required: ['gaps'],
}

// Per-gap researcher return.
const RESEARCH_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    label: { type: 'string' },
    findings: { type: 'string' },
    gaps_remaining: { type: 'array', items: { type: 'string' } },
  },
  required: ['label', 'findings', 'gaps_remaining'],
}

// Synthesize agent return: folder, id, shortname, worktree path, unit assignments, open_qs.
const SYNTH_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    folder: { type: 'string' },
    id: { type: 'string' },
    shortname: { type: 'string' },
    worktree: { type: 'string' },
    units: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          slug: { type: 'string' },
          deliverable: { type: 'string' },
          dependsOn: { type: 'array', items: { type: 'string' } },
          type: { type: 'string' },
          research: { type: 'string' },
        },
        required: ['slug', 'deliverable', 'dependsOn', 'type', 'research'],
      },
    },
    open_qs: { type: 'array', items: { type: 'string' } },
    flat: { type: 'boolean' },
  },
  required: ['folder', 'id', 'shortname', 'worktree', 'units', 'open_qs', 'flat'],
}

// design-unit-author contract (DESIGN.md decision 6).
// Usable via schema (typed object) or inline prose (same three fields).
const UNIT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    underspecified: { type: 'boolean' },
    file: { type: 'string' },
    summary: { type: 'string' },
  },
  required: ['underspecified', 'file', 'summary'],
}

// ── Phase: Research ──────────────────────────────────────────────────────────
// Interpret the seed, list research gaps, fan-out one codebase-researcher per gap.

phase('Research')

// Sub-agent: interpret the seed and list concrete research gaps.
const gapResult = await agent(
  `Read ${designSkill('design-plan')} for planning heuristics. ` +
  `The user's seed is: "${SEED}". ` +
  `Identify every assumption, unknown library/API, unknown codebase shape, and unclear deliverable boundary. ` +
  `For each gap, write a short label (kebab-case, unique) and a one-sentence research question targeting the codebase. ` +
  `Return the gaps array.`,
  { label: 'plan-gaps', phase: 'Research', model: 'opus', schema: GAPS_SCHEMA },
)

// Fan-out: one researcher per gap. Pass { phase: 'Research' } as option (never call global phase() here).
const researched = await parallel(
  gapResult.gaps.map((gap) => () =>
    agent(
      `Read ${designAgent('codebase-researcher')} and follow it. ` +
      `Research question: "${gap.question}". Label: "${gap.label}". ` +
      `Return label, verbatim findings, and any remaining gaps you could not resolve.`,
      { label: `research:${gap.label}`, phase: 'Research', model: 'opus', schema: RESEARCH_SCHEMA },
    )
  )
)

const researchSummary = researched
  .filter(Boolean)
  .map((r) => `[${r.label}]\n${r.findings}`)
  .join('\n\n')

// ── Phase: Synthesize ────────────────────────────────────────────────────────
// Compose DESIGN.md, derive shortname, create worktree + branch + id + INDEX.md,
// decide multi-unit vs flat, assign units (deliverable, depends-on, type, research snippet).
// When TEMP: write to a mktemp-d folder only; skip worktree/branch/id/INDEX entirely.

phase('Synthesize')

const synthTempInstructions = TEMP
  ? `3. This is a --temp run. Create a temp folder with \`mktemp -d -t autocode-design\`. ` +
    `Write DESIGN.md into that folder. Do NOT run git-create-branch, do NOT allocate an id, do NOT touch INDEX.md. ` +
    `Return worktree:"", id:"" in the result.\n`
  : `3. Create a worktree+branch by running git-create-branch "docs: design <shortname>" inside ${REPO}. ` +
    `Allocate <id>: read ${REPO}/.autocode/design/INDEX.md (create with the header from design-folder.md if absent); ` +
    `id = highest existing id + 1, zero-padded 4 digits (0001 if empty). ` +
    `Write DESIGN.md into ${REPO}/.autocode/design/<id>-<shortname>/DESIGN.md (create the folder). ` +
    `Append a row to INDEX.md: <id>, <shortname>, today's UTC date (date -u +%Y-%m-%d), active.\n`

const synth = await agent(
  `Read ${designSkill('design-plan')} for DESIGN.md composition rules and section guidance. ` +
  `Read ${designFolder} for folder layout, INDEX.md schema, and flat-vs-multi-unit rules. ` +
  `Seed: "${SEED}". ` +
  `Research findings:\n${researchSummary || '(no research gaps identified)'}\n\n` +
  `Tasks (do all of these):\n` +
  `1. Compose the full DESIGN.md text following the section guidance in design-plan/SKILL.md and design-folder.md.\n` +
  `2. Derive <shortname> from the # <Title> H1: kebab-case, lowercase, 2-4 keywords, strip filler (the/a/an/is/of/for/to/in/on/with). ` +
  `Dedup against ${REPO}/.autocode/design/INDEX.md rows and existing ${REPO}/.autocode/design/* folder names: on collision append -2, -3.\n` +
  synthTempInstructions +
  `4. Decide flat vs multi-unit per design-folder.md rules. ` +
  `If multi-unit, compute per-unit assignments: slug (kebab-case unique), one-line deliverable, depends-on (sibling slugs), issue type, and the relevant research snippet. ` +
  `If flat: no units array, return flat:true.\n` +
  `5. Surface any open questions research could not resolve.\n` +
  `Return the SYNTH_SCHEMA object.`,
  { label: 'synthesize', phase: 'Synthesize', model: 'opus', schema: SYNTH_SCHEMA },
)

// --temp: no worktree created; skip Author/Resolve and return immediately.
if (TEMP) {
  const remainingGapsTmp = researched
    .filter(Boolean)
    .flatMap((r) => r.gaps_remaining ?? [])
  return {
    folder: synth.folder,
    id: '',
    units: [],
    underspecified: [],
    open_qs: [...synth.open_qs, ...remainingGapsTmp],
  }
}

const inWt = makeInWt(synth.worktree)

// ── Phase: Author ────────────────────────────────────────────────────────────
// Fan-out design-unit-author for each unit. Flat designs skip.
// CRITICAL: pass { phase: 'Author' } as agent option; never call global phase() inside a parallel map.

phase('Author')

let unitResults = []
if (!synth.flat && synth.units.length > 0) {
  unitResults = await parallel(
    synth.units.map((unit) => () =>
      agent(
        inWt +
        `Read ${designAgent('design-unit-author')} and follow it exactly. ` +
        `Design folder: ${synth.folder}. The full DESIGN.md is at ${synth.folder}/DESIGN.md (read it). ` +
        `Unit assignment: slug=${unit.slug}, deliverable="${unit.deliverable}", ` +
        `depends-on=[${unit.dependsOn.join(', ')}], type=${unit.type}. ` +
        `Research findings for this unit:\n${unit.research || '(none)'}`,
        { label: `author:${unit.slug}`, phase: 'Author', model: 'opus', schema: UNIT_SCHEMA },
      )
    )
  )
}

// ── Phase: Resolve ───────────────────────────────────────────────────────────
// Bounded research-backed retry for underspecified units (cap: one retry per unit).
// CRITICAL: pass { phase: 'Resolve' } as agent option; never call global phase() inside a parallel map.

phase('Resolve')

const underspecifiedIdxs = synth.units
  .map((unit, i) => ({ unit, i }))
  .filter(({ i }) => unitResults[i]?.underspecified === true)

let resolvedResults = []
if (underspecifiedIdxs.length > 0) {
  resolvedResults = await parallel(
    underspecifiedIdxs.map(({ unit, i }) => async () => {
      // First: targeted researcher for the gap
      const reResearch = await agent(
        inWt +
        `Read ${designAgent('codebase-researcher')} and follow it. ` +
        `Research the specific gap that makes unit "${unit.slug}" underspecified. ` +
        `Deliverable: "${unit.deliverable}". ` +
        `Focus on which concrete files exist and what interfaces they expose.`,
        { label: `resolve-research:${unit.slug}`, phase: 'Resolve', model: 'opus', schema: RESEARCH_SCHEMA },
      )
      // Then: re-author with additional findings
      return agent(
        inWt +
        `Read ${designAgent('design-unit-author')} and follow it exactly. ` +
        `Design folder: ${synth.folder}. The full DESIGN.md is at ${synth.folder}/DESIGN.md (read it). ` +
        `Unit assignment: slug=${unit.slug}, deliverable="${unit.deliverable}", ` +
        `depends-on=[${unit.dependsOn.join(', ')}], type=${unit.type}. ` +
        `Additional research findings:\n${reResearch.findings}`,
        { label: `resolve-author:${unit.slug}`, phase: 'Resolve', model: 'opus', schema: UNIT_SCHEMA },
      )
    })
  )
}

// Merge: resolved result overwrites the original for retried units.
const resultMap = new Map(synth.units.map((unit, i) => [unit.slug, unitResults[i] ?? null]))
underspecifiedIdxs.forEach(({ unit }, ri) => {
  if (resolvedResults[ri]) resultMap.set(unit.slug, resolvedResults[ri])
})

const allUnits = synth.units.map((unit) => ({
  slug: unit.slug,
  file: resultMap.get(unit.slug)?.file ?? '',
}))

const finalUnderspecified = synth.units
  .filter((unit) => resultMap.get(unit.slug)?.underspecified === true)
  .map((unit) => ({ slug: unit.slug, file: resultMap.get(unit.slug)?.file ?? '' }))

// Collect open_qs from Synthesize + any remaining gaps from Research
const remainingGaps = researched
  .filter(Boolean)
  .flatMap((r) => r.gaps_remaining ?? [])

return {
  folder: synth.folder,
  id: synth.id,
  units: allUnits,
  underspecified: finalUnderspecified,
  open_qs: [...synth.open_qs, ...remainingGaps],
}
