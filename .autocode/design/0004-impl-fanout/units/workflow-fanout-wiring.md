---
depends-on: [plan-module-partition, execute-no-commit-scope, gapcheck-leaf-skill]
type: task
---

# Wire fanout, sequential commit, and gapcheck into the impl workflow

## Summary

This is the integration unit for the fanout epic. It rewires the Execute region of `impl-workflow.mjs` (`impl-workflow.mjs:180-185`) into a fork: heavy, partitionable units run one fresh sonnet agent per module group in parallel (each `impl-execute --no-commit --module <name>`, small context), preceded by an optional sequential foundation pass, then a single sonnet Commit agent that stages and commits each group in dependency order; light or non-partitionable units keep today's single `impl-execute --auto` agent unchanged. A read-only opus GapCheck loop (via the `impl-gapcheck` leaf) then runs on every heavy unit, looping a bounded `impl-execute --fix` pass until every plan item is covered. The unit adds the `impl.fanout-mode` setting (`auto`|`off`|`on`), forwards it as `fanout` from the orchestrator into both workflow-launch arg objects, documents the new behavior, and adds a setup prompt. It depends on the plan partition format (`plan-module-partition`), the `--no-commit`/`--module` flags (`execute-no-commit-scope`), and the `impl-gapcheck` leaf (`gapcheck-leaf-skill`) all existing.

## Implementation

Integration only; the three siblings supply the plan section, the execute flags, and the leaf. This unit wires them into the workflow runtime and configures the setting.

### Files to modify

- `autocode/impl/skills/impl/scripts/impl-workflow.mjs` (the workflow rewrite; the bulk of this unit).
- `autocode/impl/skills/impl/SKILL.md` (read the setting; forward `fanout` in both arg objects).
- `autocode/_config/settings-schema.md` (declare `impl.fanout-mode`).
- `plugins/autocode/skills/autocode-setup/SKILL.md` (collect `impl.fanout-mode`).
- `autocode/impl/CLAUDE.md` (document fanout Execute + the gapcheck gate).

### impl-workflow.mjs

Defensive args parse, before reading fields (memory `project_workflow_args_string`: the Workflow tool may deliver `args` as a JSON string, so `args.homeDir` is `undefined`). At the top (currently `impl-workflow.mjs:17-23`), derive a parsed object, e.g. `const A = typeof args === 'string' ? JSON.parse(args) : args`, then read `homeDir`/`worktree`/`slug`/`base`/`dims` from `A`. Read the new mode: `const FANOUT = A.fanout || 'auto'` (values `auto`|`off`|`on`).

New constant alongside `MAX_FIX_ROUNDS` (`impl-workflow.mjs:24`):
- `GAP_MAX_ROUNDS = 2` (mirrors `MAX_FIX_ROUNDS`).

Heaviness is a model judgment, not a hardcoded file-count threshold: the Partition agent decides `heavy` from the whole plan (file count, total plan size, cross-file coupling, compaction risk), so no `HEAVY_FILES` constant exists.

New schemas, in the schema-const block (next to `PREP_SCHEMA` etc.), each `type: 'object'`, `additionalProperties: false`, with the listed `required`:
- `PARTITION_SCHEMA`: `{ files_total: integer, heavy: boolean, partitionable: boolean, foundation: { files: string[], summary } | null, modules: [{ name, files: string[], summary }] }`. `files_total` is the count of all in-scope planned files (plan-wide, NOT partition-derived), so the `heavy` judgment and downstream gating hold even when `partitionable: false` (no modules). `heavy` is the agent's judgment of compaction risk for the whole plan. Module `name` MUST NOT be `foundation` (reserved for the foundation group; see `plan-module-partition`).
- `GAPCHECK_SCHEMA`: `{ complete: boolean, gaps: [{ file, plan_item, detail }] }`.

Partition assess (sonnet), inserted after the Plan agent (`impl-workflow.mjs:173-178`). One `agent()` that reads `.autocode/.impl-plan.md` (the `## Module partition` section from `plan-module-partition`) and returns `PARTITION_SCHEMA`, judging `heavy` itself. Then compute the gate:
- `heavy = part.heavy` (the agent's judgment).
- `fanout = FANOUT !== 'off' && part.partitionable && part.modules.length >= 2 && (FANOUT === 'on' || heavy)`.

Edge cases this expression already covers (per epic Edge cases): no `## Module partition` -> Partition agent returns `partitionable: false` -> single agent; only one module -> `modules.length >= 2` is false -> single agent.

Execute fork, replacing the single Execute agent at `impl-workflow.mjs:180-185`:
- `if (fanout)`:
  - Foundation agent (sonnet) only when `part.foundation` exists: `impl-execute --auto --no-commit --module foundation`. If the Foundation agent returns `null` (failed), abort fanout and fall through to the single-agent `else` path: modules cannot build blind against missing shared types without cascade-failing, so the whole plan runs through one `impl-execute --auto` agent instead (gapcheck still runs if `heavy`). Per epic Edge cases.
  - `parallel()` over `part.modules`, each a fresh sonnet `impl-execute --auto --no-commit --module <name>` (mirroring the `reviewCycle` `parallel()` + per-leaf `agent()` shape at `impl-workflow.mjs:139-146`).
  - One sequential Commit agent (sonnet) after the barrier that stages + commits each group via `git-commit`, foundation first then modules in listed order, one logical commit per group (epic Design decision 2: parallel agents share one `.git/index`, so only one agent commits). Modules are file-disjoint and share nothing but foundation interfaces, so there is no inter-module dependency order; listed order is deterministic and sufficient.
- `else`: the current single `impl-execute --auto` agent, unchanged (commits itself).

GapCheck loop, after the Execute fork and before `reviewCycle` (`impl-workflow.mjs:187-188`); runs when `heavy`, independent of `fanout` (epic Design decision 4):
- A gapcheck `agent()` (opus, read-only) via the leaf, in the `impl-critique-*` shape: `agent(inWt + readOnly + follow(skill('impl-gapcheck'), '<context + plan + diff>'), { label, phase: 'GapCheck', model: 'opus', schema: GAPCHECK_SCHEMA })`.
- `while (!gap.complete && gap.gaps.length && gapRound < GAP_MAX_ROUNDS)`: run `impl-execute --fix --auto` (sonnet) with the gaps reframed as findings (same shape as the existing fix call at `impl-workflow.mjs:192-196`), then re-run the gapcheck agent.
- Light units skip GapCheck entirely.

`meta.phases` (`impl-workflow.mjs:4-14`): add entries with models, titles matching each `phase()`/`agent()` call: Partition (sonnet), Foundation (sonnet), Modules (sonnet), Commit (sonnet), GapCheck (opus), GapFix (sonnet). Place them so the array reads in runtime order.

Result object (`impl-workflow.mjs:214-220`): add `fanout_used` (the computed `fanout` boolean), `gap_rounds` (loop count), `remaining_gaps` (gap count after the loop), alongside the existing fields. `remaining_gaps` mirrors how `remaining_important` surfaces unresolved review findings (epic Design decision 7).

### impl/SKILL.md

Read `impl.fanout-mode` (default `auto`) from `$AUTOCODE_CONFIG_DIR/settings.json`, in the same place the capped-wave launch reads `impl.max-concurrent-units` (`impl/SKILL.md:49`). Add `fanout` to BOTH workflow-launch arg objects: the single-unit launch (`impl/SKILL.md:26`) and the capped-wave launch (`impl/SKILL.md:51`), so both become `args: { homeDir, worktree, slug, base, dims, fanout }`. Should also accept an optional `--fanout <auto|off|on>` orchestrator arg overriding the setting (alongside `--dims` at `impl/SKILL.md:9`); implementer's call on exact wording.

### settings-schema.md

Add a row to the shared-keys table (`settings-schema.md:25`, beside `impl.max-concurrent-units`): `impl.fanout-mode`, type enum `auto|off|on`, default `auto`, one-line description noting it is read by the `impl` orchestrator skill and forwarded to each workflow. `impl.*` is already shared scope, so no `write-settings.sh` change is needed.

### autocode-setup/SKILL.md

Add a prompt collecting `impl.fanout-mode` to the Step 3 settings collection (`autocode-setup/SKILL.md:43-48`), as an optional shared key defaulting to `auto`. The `impl.*` namespace already maps to `settings.json`, so no `write-settings.sh` change is required.

### impl/CLAUDE.md

Document the fanout Execute path and the gapcheck gate in the orchestrator's workflow-phases paragraph (the paragraph beginning "`impl` is the stateless, re-entrant epic orchestrator", which currently lists `plan -> execute -> review -> ...`). State that heavy partitionable units fan Execute into parallel per-module agents plus a sequential commit, and that heavy units run a bounded gapcheck loop, gated by `impl.fanout-mode`.

### What proves it

Per epic Testing strategy (these are prompt/JS artifacts, not unit-testable in isolation):
- `node --check` (or equivalent) parses `impl-workflow.mjs` clean.
- Run `impl` on a heavy partitionable unit with `impl.fanout-mode: on`: the workflow view shows parallel module agents, one commit per group, and the gapcheck loop firing.
- Run a light unit: path and output are byte-identical to today (single Execute agent, no GapCheck).
- `scripts/check-plugin-shape.sh` passes (no shim/real shape regression from the SKILL/schema edits).
