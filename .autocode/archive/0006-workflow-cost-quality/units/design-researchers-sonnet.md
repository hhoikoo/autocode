---
depends-on: []
type: task
---

# Downgrade design-workflow researcher dispatches to sonnet

## Summary

The two design workflow runtimes dispatch read-only `codebase-researcher` work on opus, which is overkill for read-and-report research and inflates plan/critique cost. Downgrade exactly the researcher dispatches to sonnet: the two `codebase-researcher` fan-outs in `design-plan-workflow.mjs` (the Research-phase `research:<label>` dispatch and the Resolve-phase `resolve-research:<slug>` dispatch) and the Resolve wrapper in `design-critique-workflow.mjs` that spawns a researcher. Every judgment/generative dispatch (plan-gaps, synthesize, author, resolve-author, critique question) stays opus. The related `meta.phases` descriptor strings (documentation only; they do not gate dispatch) are reworded to match. The deliverable also called for restoring the dropped `args`-string `JSON.parse` guard (fix c5ffded), but at the current worktree HEAD both scripts already carry it (`design-plan-workflow.mjs:17`, `design-critique-workflow.mjs:13`, matching `impl-workflow.mjs:26`); that half is verify-only, no edit unless a rebase drops it.

## Implementation

Two files change, both under `autocode/design/`, disjoint from `impl-workflow.mjs` and from every other unit in this epic (this unit has `depends-on: []`).

`autocode/design/skills/design-plan/scripts/design-plan-workflow.mjs`:

- Line 139, dispatch `research:${gap.label}` (schema `RESEARCH_SCHEMA`): `model: 'opus'` -> `model: 'sonnet'`. This is the per-gap read-only `codebase-researcher` fan-out (`autocode/design/agents/codebase-researcher.md`).
- Line 247, dispatch `resolve-research:${unit.slug}` (schema `RESEARCH_SCHEMA`): `model: 'opus'` -> `model: 'sonnet'`. The targeted researcher inside the bounded Resolve retry.
- Line 5, `meta.phases[0]` (`{ title: 'Research', detail: 'opus: ...', model: 'opus' }`): reword the `detail`/`model` strings so they no longer claim the whole phase is opus. The Research phase now runs a mixed pair (opus `plan-gaps` decomposition + sonnet researchers). These strings are display metadata only; they do not select the model at dispatch.
- Stay opus, do NOT touch: line 129 `plan-gaps` (`GAPS_SCHEMA`, seed decomposition, judgment), line 184 `synthesize` (`SYNTH_SCHEMA`, composes DESIGN.md + partition + assignments), line 220 `author:` and line 257 `resolve-author:` (`design-unit-author`, generative).

`autocode/design/skills/design-plan-critique/scripts/design-critique-workflow.mjs`:

- Line 99, dispatch `resolve-i${iterations}-${item.id}` (schema `RESOLVE_SCHEMA`): `model: 'opus'` -> `model: 'sonnet'`. This wrapper dispatches a `codebase-researcher`; the researcher's own shim (`plugins/autocode/agents/codebase-researcher.md:4`) is already `model: sonnet`, so only the wrapper's model changes.
- Line 6, `meta.phases[1]` Resolve descriptor (`{ title: 'Resolve', detail: 'opus: research each question ...', model: 'opus' }`): reword `detail`/`model` to sonnet to match the dispatch. Documentation only.
- Stay opus, do NOT touch: line 85 `question-i` (`QUESTION_SCHEMA`, generative question authoring). Apply-phase agents (lines 139, 155) are already sonnet.

Args guard (verify-only): confirm `const A = typeof args === 'string' ? JSON.parse(args) : (args || {})` is present at the top of both scripts where `args` is first read (`design-plan-workflow.mjs:17`, `design-critique-workflow.mjs:13`). Both are present at HEAD. Add it back only if a rebase or merge drops it; do not duplicate.

No public interface changes: `meta.phases`, the schemas, and every return shape are untouched apart from the model labels. Downstream code that reads `RESEARCH_SCHEMA` / `RESOLVE_SCHEMA` output is model-agnostic.

Tests (drive the flow, no unit-test harness exists):

- Run `design-plan --auto` on a small seed; confirm the phase list still shows Research/Synthesize/Author/Resolve, the `research:*` and `resolve-research:*` dispatches now run on sonnet, and their output still validates against `RESEARCH_SCHEMA`.
- Run `design-plan-critique` on an existing design folder; confirm the `resolve-i*` dispatches run on sonnet and produce valid `RESOLVE_SCHEMA` output, and the Question phase stays opus.
- Pass `args` as a JSON string to each script; confirm the guard parses it (no crash), proving the restore/verify held.
