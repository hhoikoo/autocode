---
depends-on: []
type: task
---

# Make the design-plan phase orchestrator-ready

## Summary

Move the *whole* `design-plan` heavy phase off the main context into a background Workflow script (`autocode/design/skills/design-plan/scripts/design-plan-workflow.mjs`) mirroring `impl-workflow.mjs`, so the `/design` orchestrator can launch it directly and consume only a typed result (DESIGN.md decision 2, workflow-centric dispatch). The workflow owns research fan-out, `DESIGN.md` synthesis, shortname derivation, worktree + branch + `<id>` + `INDEX.md` creation, and the unit-author fan-out with a structured `design-unit-author` contract (`{ underspecified, file, summary }`) plus a bounded research-backed retry. Its agents *read the existing `design-plan` and `design-unit-author` bodies* for their heuristics, so the planning logic stays single-source and the workflow owns only the deterministic loop + fan-out scaffolding. `design-plan --auto` becomes a thin launcher over this workflow (compute `homeDir` + seed, launch, emit the structured result block); `design-plan` without `--auto` keeps its existing in-session interactive loop verbatim (the manual fallback, DESIGN.md decision 8). `design-unit-author` gains the three-field contract usable both via `schema` (in the workflow) and as inline prose (a human reading the same three fields). All changes touch `design-plan` and `design-unit-author` together, so they ship as one PR.

## Implementation

Deliverable: one new workflow script, edits to two body-only source files, and one shim description touch-up. Maps to DESIGN.md decisions 2, 6, 7 and runtime-flow step 3.

Files to create:

- `autocode/design/skills/design-plan/scripts/design-plan-workflow.mjs`: the background plan workflow, sibling to `impl-workflow.mjs` (`autocode/impl/skills/impl/scripts/impl-workflow.mjs`). Plain JS, no shim, not shape-checked (`scripts/check-plugin-shape.sh` only rejects real skill/agent files that open with `---`).

Files to modify:

- `autocode/design/skills/design-plan/SKILL.md`: add `--auto` as a thin launcher over the workflow; keep the non-`--auto` interactive path unchanged.
- `autocode/design/agents/design-unit-author.md`: replace the in-band underspecified signal (`:29`, `:39-41`) with the three-field contract usable both via `schema` and as inline prose.

Files NOT modified (note for the implementer):

- `plugins/autocode/skills/design-plan/SKILL.md`: the shim already forwards `$ARGUMENTS`, so `--auto` flows through with no edit; touch only its `description` to mention `--auto` if it lists modes (it currently does not, so it may stay verbatim).
- No shim for the `.mjs`: workflow scripts are launched by absolute path, exactly as `impl-workflow.mjs` has none (`impl/SKILL.md:22-23`).

### The workflow script

Model on `impl-workflow.mjs` exactly. Same helper shape and constraints (DESIGN.md testing strategy, "Static read against `impl-workflow.mjs`"):

- `export const meta` with `name`, `description`, and a `phases` array declaring `Research`, `Synthesize`, `Author`, `Resolve`.
- Path resolution via `args.homeDir` only: `const HOME = args.homeDir`, then a `skill`/agent-path helper that reads canonical bodies by absolute path (`${HOME}/.autocode/autocode/design/...`), mirroring `impl-workflow.mjs:19,29`. No forbidden globals; `parallel`, `agent`, `phase`, `log` are the workflow runtime's, as in the template. Unlike `impl-workflow.mjs` (where the worktree pre-exists in args because `impl-start` created it), the design plan worktree does not exist at launch: the `Synthesize` phase creates it, so the `inWt` cd-into-worktree prefix is built from the worktree path `Synthesize` returns, not from args, and is therefore only available to the `Author`/`Resolve` phases that follow `Synthesize`.
- Args from the orchestrator (and from the thin-launcher skill): `{ homeDir, repoRoot, seed }`. The workflow owns the entire heavy phase; the launcher passes only the seed and paths, mirroring how the `0002` orchestrator launches `impl-workflow.mjs` directly with light args (`impl-orchestrator-core.md:49`).

Phases, top-level sequential, with `phase('<Title>')` called only at top level (never inside a `parallel` map):

1. `Research` (`phase('Research')`): one `agent` per research gap inside `parallel`, each dispatching `codebase-researcher` (read-only; body at `${HOME}/.autocode/autocode/design/agents/codebase-researcher.md`). The gaps come from a prior planning `agent` that interprets the seed and lists what to research (mirrors how `design-plan` sketches a rough plan then fans out researchers today). Each call passes `{ label, phase: 'Research', schema: RESEARCH_SCHEMA }`.
2. `Synthesize` (`phase('Synthesize')`): one `agent` that reads the `design-plan` body for the `DESIGN.md` composition rules, composes `DESIGN.md` from the seed + research findings, derives the `<shortname>` (below), creates the worktree + branch via `git-create-branch`, allocates the `<id>` and appends the `INDEX.md` row, writes `DESIGN.md` into `<repoRoot>/.autocode/design/<id>-<short>/`, and computes the per-unit assignments. Returns `{ folder, id, units: [{ slug, deliverable, dependsOn, type, research }] }` via `schema`. This agent is where the previously-inline `design-plan` synthesis now runs, off the main context. Worktree + branch + `<id>` + `INDEX.md` creation is a plan-phase responsibility today (`design-plan/SKILL.md:41`; `design-plan-push` only re-creates them as a fallback in a fresh session, `design-plan-push/SKILL.md:22`), so it stays in the plan phase, now inside this workflow agent.
3. `Author` (`phase('Author')`): one `agent` per unit inside `parallel`, mirroring `impl-workflow.mjs:139-146`. Each call passes `inWt` (cd into the worktree first), the agent-body read line for `design-unit-author`, the unit assignment from `Synthesize`, the full `DESIGN.md` text, and that unit's `research`. Options: `{ label: \`author:${slug}\`, phase: 'Author', model: 'opus', schema: UNIT_SCHEMA }`.
4. `Resolve` (`phase('Resolve')`): the bounded research-backed retry (below).

CRITICAL: never call the global `phase(...)` inside a `parallel` map; declare the phase once before the map and pass `{ phase: '...' }` as the agent OPTION (the template calls `phase('...')` only at top level and passes `{ phase }` as an option inside `parallel`, `impl-workflow.mjs:139-146`). Global `phase()` mutates shared state and races concurrent units.

`UNIT_SCHEMA` (the `design-unit-author` contract, DESIGN.md decision 6):

```
{ type: 'object', additionalProperties: false,
  properties: {
    underspecified: { type: 'boolean' },
    file: { type: 'string' },
    summary: { type: 'string' } },
  required: ['underspecified', 'file', 'summary'] }
```

Bounded research-backed retry (the `Resolve` phase), cap one retry per unit:

- After the `Author` fan-out resolves, collect units whose result has `underspecified: true`.
- For each, run a second `parallel` map: first an `agent` dispatch to `codebase-researcher` scoped to that one unit's gap, then a re-`agent` of `design-unit-author` with the same assignment plus the researcher findings, again `{ schema: UNIT_SCHEMA }`.
- CRITICAL: both retry agents pass `{ phase: 'Resolve' }` as the agent OPTION (e.g. `{ label, phase: 'Resolve', model, schema }`), never a bare `phase('Resolve')` call inside the map. Same rule the template follows passing `{ phase: 'Review' }` as an option (`impl-workflow.mjs:145`); a bare `phase()` inside `parallel` races the other concurrent units' phase state.
- A unit still `underspecified` after its one retry stays in the underspecified set.

Workflow return block (consumed by the thin-launcher skill and by the orchestrator):

```
{ folder: string,                     // <repoRoot>/.autocode/design/<id>-<short>/
  id: string,                         // zero-padded 4-digit, "" for --temp
  units: [{ slug, file }],            // every unit authored; [] for flat
  underspecified: [{ slug, file }],   // those still underspecified after retry
  open_qs: [string] }                 // research gaps the workflow could not resolve
```

Flat single-unit designs skip the `Author`/`Resolve` fan-out: `Synthesize` writes `DESIGN.md` only and returns `units: []`. `--temp` plans are a single throwaway synthesis with no worktree, id, branch, or `INDEX.md` row: the workflow returns `id: ""`, `units: []`, and the orchestrator refuses to advance a `--temp` folder past plan.

### Shortname derivation (inside `Synthesize`)

DESIGN.md decision 7, replacing the interactive shortname `AskUserQuestion` (`design-plan/SKILL.md:38`):

- Derive from the `# <Title>` H1 of the composed `DESIGN.md`: kebab-case, lowercase, 2-4 keywords, strip the same filler words `git-create-branch` uses (`the`, `a`, `an`, `is`, `of`, `for`, `to`, `in`, `on`, `with`; `git-create-branch/SKILL.md:39`). This is the documented reduction reused, referenced by name, not reimplemented.
- Dedup against `INDEX.md` (`<repoRoot>/.autocode/design/INDEX.md`) and existing `.autocode/design/*` folder names: on collision append `-2`, then `-3`, etc. The `<id>`, not the shortname, is the durable token (`design-folder.md:11,13`), so a suffixed shortname is fine.

### `design-plan` skill edits (thin launcher under `--auto`)

`--auto` arg: add `--auto` to `## Args` (currently freeform-description / `--temp`, `design-plan/SKILL.md:9-10`).

- Under `--auto`: the skill is a thin launcher. It resolves `homeDir` via `echo "$HOME"` and `repoRoot` via `git rev-parse --show-toplevel` (mirroring `impl/SKILL.md:18,22`), takes the seed non-interactively from `$ARGUMENTS` (a background plan phase cannot `AskUserQuestion`; the orchestrator never invokes plan with an empty seed), launches the Workflow with `scriptPath: <homeDir>/.autocode/autocode/design/skills/design-plan/scripts/design-plan-workflow.mjs` and `args: { homeDir, repoRoot, seed }`, waits, and emits the workflow's return as the structured result block below in place of the prose final report (`:45-47`). The `/design` orchestrator launches the same workflow directly and does not route through this skill (mirrors `0002`, where the orchestrator launches `impl-workflow.mjs` directly and bypasses the `impl` skill, `impl-orchestrator-core.md:49`); the `--auto` skill is the manual entry point to the same off-context phase.
- Without `--auto`: the in-session interactive path stays (the manual fallback, DESIGN.md decision 8) with one change required by decision 7: the seed `AskUserQuestion` on empty `$ARGUMENTS` (`:14`) and the inline `design-unit-author` fan-out (`:43`) are unchanged, but the interactive shortname prompt (`:38`) is dropped here too and replaced by the auto-derivation below (decision 7 drops the prompt in *both* modes; a human running the skill no longer answers it). The seed prompt is the only `AskUserQuestion` the non-`--auto` path keeps; the `--auto` workflow path drops that one too (it takes the seed from `$ARGUMENTS`).

Structured result block (DESIGN.md runtime-flow step 3), emitted in `--auto` mode:

```
{ folder: string,            // <repoRoot>/.autocode/design/<id>-<short>/
  id: string,                // zero-padded 4-digit, "" for --temp
  units: [{ slug, file }],   // from the workflow return; [] for flat
  underspecified: [{ slug, file }],  // from the workflow return
  open_qs: [string] }        // unresolved gaps from the workflow
```

The orchestrator surfaces `underspecified`/`open_qs` (DESIGN.md edge case "Plan returns `underspecified` units or `open_qs`"). `--temp` + `--auto` returns `id: ""`, `units: []`, and refuses fan-out (the temp dir has no worktree); the orchestrator refuses to advance a `--temp` folder past plan.

### `design-unit-author` agent edits

Replace the in-band underspecified signal and unstructured output (`design-unit-author.md:29,39-41`) with the three-field contract:

- `## Output`: the agent reports `underspecified` (true when it cannot name concrete files, `:29`), `file` (the `units/<slug>.md` path it wrote, or the path it would write when underspecified), and `summary` (one-line deliverable). Invoked inline by a human (the non-`--auto` plan path), it states these three fields in prose; invoked by the workflow with `{ schema: UNIT_SCHEMA }`, the runtime returns them as the typed object. Same three fields either way (DESIGN.md decision 6: "the agent stays usable inline").
- Keep the existing workflow steps (`:22-29`), the parallel-invocation note (`:5`), and all `## Rules` (`:32-37`). The retry contract is invisible to the agent: it receives a fresh prompt with the researcher findings on the re-author and authors as normal.

### Tests that prove it

Per DESIGN.md testing strategy:

- `scripts/check-plugin-shape.sh` passes: no new shim restates a definition; `design-plan-workflow.mjs` carries no frontmatter and is not a skill/agent file; the design feature-set keeps its `CLAUDE.md`.
- Static read of `design-plan-workflow.mjs` against `impl-workflow.mjs`: same helper shape, `args.homeDir` path resolution, `inWt` helper, `parallel` fan-out, `schema`-typed returns, `{ phase: '...' }` passed as options inside `parallel` (never a bare `phase()` in a map), top-level `phase()` calls only, no forbidden globals.
- `design-plan --auto` dry run on a scratch two-unit seed: assert it launches the workflow (no inline research/synthesis in the launching session) and emits the structured result block with `folder`, `id`, `units`, `underspecified`, `open_qs`; assert no `AskUserQuestion` (seed, shortname, or fan-out resolution).
- Forced underspecified unit (an intentionally vague deliverable): assert the workflow runs one `codebase-researcher` + one re-author for it, and that a unit still vague after the retry appears in `underspecified`.
- Shortname derivation: assert kebab-case 2-4 keywords from the title with filler stripped, and `-2` suffix on a forced collision against `INDEX.md`.
- Inline regression: invoke `design-unit-author` directly and confirm it reports the three contract fields in prose; run `design-plan` without `--auto` and confirm the interactive shortname path, inline fan-out, and prose report are unchanged (manual fallback, decision 8).
