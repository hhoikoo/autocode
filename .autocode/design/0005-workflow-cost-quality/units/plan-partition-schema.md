---
depends-on: [workflow-progress-logging]
type: task
---

# Fold the partition into the Plan agent's structured output

## Summary

The opus Plan agent already writes the `## Module partition` section into `.autocode/.impl-plan.md`; a second sonnet Partition agent then re-reads that file only to transcribe it into a schema the workflow consumes. Delete that redundant agent: attach a `PLAN_SCHEMA` (the partition fields plus a self-assessed `heavy`) to the existing Plan call so the planner returns the partition directly, and rewire the downstream `heavy` / fanout / foundation / modules logic to read the Plan result. The `## Module partition` section stays written to disk unchanged (`impl-execute --module` reads it); this folds the transcription step into the plan, it does not move the on-disk artifact. `heavy` becomes author-self-assessed instead of an independent downstream judgment.

## Implementation

Deliverable: remove the Partition phase from the impl workflow, carrying its structured output on the Plan phase instead, and align the `impl-plan` skill's step 5 and `## Module partition` framing.

This unit is second in the `impl-workflow.mjs` serialization chain (after `workflow-progress-logging`, before `scoped-verify-gate`); it edits that file on top of the progress-logging changes and does not conflict with siblings.

Files to modify:

- `autocode/impl/skills/impl/scripts/impl-workflow.mjs`
- `autocode/impl/skills/impl-plan/SKILL.md`

### impl-workflow.mjs

Add `PLAN_SCHEMA` and attach it to the Plan call:

- Define `PLAN_SCHEMA` mirroring `PARTITION_SCHEMA` (`:138-169`): `{ files_total:int, heavy:bool, partitionable:bool, foundation:{files:string[],summary}|null, modules:[{name,files:string[],summary}] }`, same `additionalProperties:false` and `required` shape. Keep `files_total` for parity: this unit's JS never reads it, but the downstream `per-module-gapcheck` sibling asserts `|foundation| + Sum|modules| + |residual| == files_total` (DESIGN.md decision 7, edge case at DESIGN.md:99), so the field must ride the plan output for that sibling to consume.
- Change the Plan call (`:239-243`, currently no schema and its return discarded) to `const plan = await agent(...)` with `schema: PLAN_SCHEMA`. Extend the agent prompt so the planner returns the partition + `heavy` in the same call (it already resolves both while planning): instruct it to set `partitionable`/`foundation`/`modules`/`files_total` from the `## Module partition` section it just wrote, and to self-assess `heavy` (compaction risk over a single Execute agent) from the whole plan. Fold in the judgment wording currently on the Partition agent (`:250-253`).

Delete (dead after the fold):

- `PARTITION_SCHEMA` (`:138-169`).
- The `{ title: 'Partition', ... }` entry in `meta.phases` (`:6`).
- The entire Partition phase block (`:245-255`): `phase('Partition')` and the `const part = await agent(...)`.

Rewire the derived flags and fanout to read `plan.*` instead of `part.*`:

- `const heavy = !!plan && plan.heavy` (was `:256`).
- Fanout predicate (`:257-261`): `plan.partitionable`, `plan.modules.length >= 2`.
- Fanout body: foundation check (`:266`) reads `plan.foundation`; module fan-out and commit order (`:277`, `:284`) read `plan.modules`.

Only `heavy` / `partitionable` / `foundation` / `modules[].name` are JS-consumed here; `files_total` stays purely for the downstream sibling contract.

### impl-plan/SKILL.md

The `## Module partition` section MUST keep being written to `.autocode/.impl-plan.md` (HARD CONSTRAINT: `impl-execute --module` reads it, `impl-execute/SKILL.md:14`). These edits are additive framing changes, not a removal of the on-disk write:

- Step 5 Report (the `--auto` block, currently at SKILL.md:37): add the module partition to the `--auto` structured result (`partitionable`, `foundation {files,summary}|null`, `modules [{name,files,summary}]`, plus `files_total`). State that the planner emits the partition directly in its structured result and the workflow consumes it from there, rather than a separate agent re-reading the plan file. Drop the current "read from the plan file by the workflow's Partition agent, not surfaced in this block; leave the `--auto` fields unchanged" sentence.
- The `## Module partition` intro (currently SKILL.md:41): drop the "the workflow's Partition agent can read it" / "the agent only transcribes" framing. Keep that the section is written into `.autocode/.impl-plan.md` so `impl-execute --module` can scope each group, and note the same partition is also returned in the `--auto` structured result.
- Step 3's final planning step and step 4's write instruction (SKILL.md:32, :35) need no substantive change: the planner still derives and writes the section as before.

### Tests

No unit-test harness for the workflow scripts; verify by driving the flow (the `verify` skill):

- Run the impl workflow on a small heavy, partitionable unit and confirm the emitted phase list no longer contains `Partition`, `PLAN_SCHEMA` validates against the Plan agent output, and fanout still triggers (foundation + modules execute, per-group commits land).
- Run on a small non-partitionable unit and confirm `partitionable:false` / `modules:[]` yields the single-agent path and `heavy` gates the whole-diff gapcheck as before.
- Confirm `impl-plan --auto` on a unit emits the partition fields in its structured result and still writes the `## Module partition` section to `.autocode/.impl-plan.md`.
