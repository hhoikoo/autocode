# Fanout mode for heavy impl units

## Summary

The `impl` Execute phase runs one sonnet agent that carries a unit's entire plan (`impl-workflow.mjs:180-185`). On a heavy unit that single agent fills and compacts its context window repeatedly, degrading quality. This epic adds an opt-in fanout mode: `impl-plan` partitions the plan into a foundation set plus file-disjoint module groups; the workflow runs one fresh sonnet agent per module in parallel (small context each), then a single sequential commit step (parallel agents in one worktree would race on `.git/index`); and a new read-only `impl-gapcheck` leaf verifies every plan item was implemented, looping a bounded fix pass until the spec is covered. Fanout and the gapcheck gate trigger on heaviness, computed from the plan; light units keep the current single-agent path unchanged.

## Background

The implementation phase is a background Workflow (`impl-workflow.mjs`) of per-phase agents, each with a fixed model: opus for reasoning/review, sonnet for mechanical work. Today:

| Piece | File | Current behavior |
|---|---|---|
| Plan format | `impl-plan/SKILL.md` | Flat per-file task list + test plan + order + out-of-scope, written to `.autocode/.impl-plan.md`. No module grouping. |
| Execute | `impl-workflow.mjs:180-185` | One sonnet agent runs `impl-execute --auto` over the whole plan and commits via `git-commit`. |
| Execute skill | `impl-execute/SKILL.md` | Default mode executes the plan and commits; `--fix <findings>` applies review findings. Always commits via `git-commit`. |
| Review | `impl-workflow.mjs:130-198` | `reviewCycle` fans out per-dimension reviewers (opus), challenges, decides, then `impl-execute --fix` loop capped at `MAX_FIX_ROUNDS = 2`. |
| Concurrency | `impl/SKILL.md:49` | Orchestrator reads `impl.max-concurrent-units` from `$AUTOCODE_CONFIG_DIR/settings.json`, forwards `args: { homeDir, worktree, slug, base, dims }` to the workflow. |

The fanout pattern already exists in this file (`reviewCycle` uses `parallel()` + per-leaf `agent()` calls with JSON schemas), because subagents cannot spawn subagents, so all fan-out lives in the workflow runtime. This epic applies the same shape to Execute.

## Architecture

No new dependencies. One new leaf skill (`impl-gapcheck`, real + shim), edits to two existing skills (`impl-plan`, `impl-execute`), one workflow rewrite of the Execute region (`impl-workflow.mjs`), one orchestrator edit (`impl/SKILL.md`), one settings row, one setup prompt.

Execute-phase fork (the only behavioral change):

```
                    Plan (opus) -> .autocode/.impl-plan.md
                                   (now carries ## Module partition)
                                          |
                              Partition assess (sonnet)
                          reads plan -> { files_total, heavy,
                            partitionable, foundation, modules[] }
                                          |
                    heavy = partition agent's judgment
                    fanout = heavy && partitionable && mode != off
                                          |
            +-----------------------------+-----------------------------+
            | fanout                       | heavy, not fanout           | light
            v                              v                             v
   Foundation (sonnet,             Execute (sonnet,               Execute (sonnet,
   --module foundation             --auto, single agent,          --auto, single agent,
   --no-commit)                    commits itself)                commits itself)
            |                              |                             |
   Modules (parallel sonnet,              |                             |
   one per group,                         |                             |
   --module <name> --no-commit)           |                             |
            |                              |                             |
   Commit (sonnet, sequential             |                             |
   git-commit per group)                  |                             |
            +--------------+---------------+                             |
                           v                                            |
                  GapCheck loop (heavy only)                            |
                  gapcheck (opus, read-only) -> { complete, gaps[] }    |
                  while gaps && round < GAP_MAX_ROUNDS:                  |
                    impl-execute --fix (sonnet) -> recheck              |
                           |                                            |
                           +--------------------+-----------------------+
                                                v
                          reviewCycle / Push / Hygiene (unchanged)
```

## Design decisions

1. **`impl-plan` owns the partition; a thin workflow agent only transcribes it.** The planner already resolves every signature and data shape and knows the file DAG, so it decides the foundation/module split and writes it into `## Module partition`. The workflow's Partition agent reads that section into JSON for `parallel()`; it does not re-infer groups from the file list. Rejected: a workflow-side prep agent that infers grouping from changed files. It would have to re-derive dependencies the planner already knows, and would split modules that secretly share an interface.

2. **Modules write only; one sequential agent commits.** Parallel agents share one worktree and one `.git/index`; concurrent `git add`/`git commit` corrupt the index. So module agents run `impl-execute --no-commit` (working-tree writes only) and a dedicated Commit agent runs after the barrier, calling `git-commit` once per module group, foundation first then modules in listed order. Modules are file-disjoint and share nothing but foundation interfaces, so there is no inter-module dependency order to respect; listed order is deterministic and sufficient. A single agent committing serially is race-free and preserves logical per-module commits (and each commit still fires the Stop-hook progress logging). Rejected: each module commits itself (index race); one monolithic commit of the whole join (loses logical granularity and progress-log resolution).

3. **Foundation pass runs before fanout.** A module may need a type or interface another module defines, but a parallel sibling cannot see uncommitted work. Modules build blind against the plan's resolved signatures; anything genuinely shared (types, contracts, interfaces) goes in an optional `### Foundation` group implemented sequentially first. This raises the bar on `impl-plan`: the partition is only emitted when interfaces are concrete enough that modules compile without seeing each other. Rejected: no foundation, rely solely on the plan spec. Works for leaf modules but breaks the moment two modules share a new type.

4. **Heaviness gates both fanout and gapcheck; judged by the model from the plan, not a hardcoded threshold or per-unit config.** The Partition agent judges `heavy` from the whole plan (file count, total plan size, cross-file coupling, compaction risk) and returns it as a `heavy` boolean; there is no `HEAVY_FILES` constant. `files_total` is still returned as a plan-wide signal (count of all in-scope planned files, independent of the partition) so heaviness holds even when `partitionable: false`. Heavy + partitionable + mode-on -> fanout. Heavy + not partitionable -> single agent but still gapchecked (this is the user's exact pain case: a big unit that compacts, where the completeness net matters most). Light -> current path, no gapcheck overhead. Rejected: a fixed file-count threshold (a 7-file unit with deep coupling compacts harder than a 20-file unit of independent stubs; the model reads the plan and judges directly). Rejected: a per-unit fanout flag in the design folder (the planner's partition already encodes suitability; a separate flag would drift).

5. **`impl.fanout-mode` setting: `auto` (default) | `off` | `on`.** `auto` fans out heavy partitionable units; `off` forces the single-agent path always; `on` fans out any partitionable unit regardless of the file threshold. The orchestrator reads it and forwards `fanout` in the workflow args, mirroring how `impl.max-concurrent-units` and `dims` already flow. Gapcheck is independent of this setting (it gates on heaviness, not fanout), so turning fanout off still protects heavy units. Rejected: a hardcoded always-on threshold with no override (users on constrained machines or with non-partitionable codebases need the escape hatch).

6. **GapCheck is a new leaf, not part of `impl-critique`.** `impl-critique` answers "is this code correct/secure/fast"; gapcheck answers "is every plan item present". Different question, different prompt, different schema (`{ complete, gaps[] }`). It is read-only and run by the workflow exactly like the `impl-critique-*` leaves (path via `skill()`, `follow()`, a JSON schema). Rejected: adding a "completeness" dimension to `impl-critique-review` (conflates a spec-coverage check with a quality review and would run on every unit, not just heavy ones).

7. **GapCheck runs opus, fix runs sonnet.** A fresh-context sonnet checker would share the blind spots of the sonnet that just compacted; the value is an independent reasoning pass over the spec, so gapcheck is opus (matching the review phase). The fix is mechanical, so it reuses `impl-execute --fix` on sonnet. The loop caps at `GAP_MAX_ROUNDS = 2`, mirroring `MAX_FIX_ROUNDS`; remaining gaps surface in the workflow result like `remaining_important`.

## Runtime flow

1. Plan (opus, unchanged trigger): `impl-plan --auto` writes `.autocode/.impl-plan.md` including the new `## Module partition` section.
2. Partition assess (sonnet, new): an agent reads the plan and returns `{ files_total, heavy, partitionable, foundation, modules[] }`, judging `heavy` itself. The workflow computes `fanout` from `heavy`, `partitionable`, module count, and `fanout-mode`.
3a. Fanout path: Foundation agent (`impl-execute --auto --no-commit --module foundation`) if a foundation group exists (on its failure, fall back to 3b over the whole plan); then `parallel()` over modules, each `impl-execute --auto --no-commit --module <name>`; then the Commit agent commits each group sequentially via `git-commit`, foundation first then modules in listed order.
3b. Non-fanout path: the current single `impl-execute --auto` agent (commits itself).
4. GapCheck loop (heavy only): gapcheck agent returns `{ complete, gaps[] }`; while gaps remain and `round < GAP_MAX_ROUNDS`, run `impl-execute --fix --auto` with the gaps as findings, then re-check.
5. `reviewCycle`, Push, Hygiene proceed unchanged.

## Edge cases and error handling

- **Plan emits no partition / `partitionable: false`.** Single-agent Execute; gapcheck still runs if heavy. Backward compatible with plans written before this epic (no `## Module partition` -> Partition agent returns `partitionable: false`).
- **Only one module.** Not worth fanout; treat as non-partitionable, single agent.
- **No foundation group.** Skip the foundation pass; go straight to parallel modules.
- **Foundation agent fails (returns null).** Abort fanout and fall back to the single-agent Execute path (one `impl-execute --auto` over the whole plan): modules building blind against missing shared types would cascade-fail, so a clean single-agent pass is safer than a partial fanout. Gapcheck still runs when heavy.
- **A module named `foundation`.** The planner never emits one (`plan-module-partition` reserves the name) and `impl-execute --module foundation` resolves to the foundation group; the partition format forbids the collision at the source.
- **A module agent fails (returns null).** The Commit agent commits whatever landed; gapcheck catches the missing files as gaps and the fix loop fills them. A persistent gap after `GAP_MAX_ROUNDS` is reported, not silently dropped.
- **Gapcheck false-negative (reports complete but isn't).** `reviewCycle` (correctness dimension) is the backstop, unchanged.
- **`args` delivered as a JSON string** (known issue, `[[project_workflow_args_string]]`): the workflow edit parses args defensively at the top so the new `fanout` field and existing fields read correctly.

## Testing strategy

These are prompt/skill artifacts and a JS workflow script, not unit-testable in isolation; verification is by shape-check and a live heavy-unit run.

- `scripts/check-plugin-shape.sh` must pass for the new `impl-gapcheck` skill + shim (real file body-only, unique name, shim frontmatter + read line).
- CI path globs and `.github/workflows/ci.yml` cover the new skill directory.
- Manual: run `impl` on a heavy partitionable unit with `impl.fanout-mode: on`; confirm parallel module agents in the workflow view, one commit per group, gapcheck loop fires. Run a light unit; confirm the path and output are byte-identical to today.
- `impl-plan` change verified by inspecting a generated `.impl-plan.md` for a well-formed `## Module partition`.

## Alternatives considered

- **Per-module worktrees instead of write-only + single commit.** Isolating each module in its own worktree removes the index race but explodes setup cost and needs a merge step back into the unit branch; the shared-worktree write-only approach is simpler and the sequential Commit agent already serializes safely.
- **Make fanout the default (not opt-in).** Rejected per the original ask: opt-in via `impl.fanout-mode`, default `auto` so it only triggers on genuinely heavy, partitionable units.

## Sources

- `autocode/impl/skills/impl/scripts/impl-workflow.mjs:130-220`: `reviewCycle`, the Execute/Fix region, `MAX_FIX_ROUNDS`, per-phase models, schema pattern.
- `autocode/impl/skills/impl-execute/SKILL.md:11-44`: default vs `--fix`, commit-via-`git-commit` contract, `--auto` output.
- `autocode/impl/skills/impl-plan/SKILL.md:27-35`: current plan output format and `--auto` block.
- `autocode/impl/skills/impl/SKILL.md:26,49,51`: arg assembly, settings read, capped-wave launch.
- `autocode/_config/settings-schema.md:25`: `impl.max-concurrent-units` declaration pattern.
- `autocode/impl/skills/impl-critique-{review,challenge,decide}/SKILL.md` and their shims: leaf-skill body + shim shape.
- `scripts/check-plugin-shape.sh`: shim/real shape rules.
- `autocode/design/design-folder.md`: `.impl-context`, progress lifecycle.
- User statement (2026-06-09): heavy units compacted repeatedly under the single Execute agent; wants opt-in fanout + a spec-completeness check loop.

## Units

| unit | deliverable | depends-on |
|---|---|---|
| [plan-module-partition](units/plan-module-partition.md) | `impl-plan` emits a `## Module partition` section (foundation + file-disjoint modules) | none |
| [execute-no-commit-scope](units/execute-no-commit-scope.md) | `impl-execute` gains `--no-commit` and `--module <name>` scoping | none |
| [gapcheck-leaf-skill](units/gapcheck-leaf-skill.md) | new read-only `impl-gapcheck` leaf skill (real + shim + CLAUDE.md) | none |
| [workflow-fanout-wiring](units/workflow-fanout-wiring.md) | wire fanout + commit + gapcheck loop into `impl-workflow.mjs`; `impl.fanout-mode` setting | plan-module-partition, execute-no-commit-scope, gapcheck-leaf-skill |

## Critique log

### Iteration 1

- Q: `HEAVY_FILES` is referenced as the heaviness threshold but never given a value. What value? -> Resolved (user, 2026-06-09): no constant; the Partition agent judges `heavy` from the whole plan (compaction risk, coupling), returning a `heavy` boolean. Decision 4, architecture diagram, runtime flow, and `PARTITION_SCHEMA` (workflow-fanout-wiring) updated; `HEAVY_FILES` constant removed.
- Q: Commit agent commits "in dependency order", but modules are file-disjoint with no inter-module edges in `PARTITION_SCHEMA`. Contradiction? -> Resolved (reasoning from design invariants): modules share nothing but foundation interfaces, so no inter-module order exists; commit order is foundation first then modules in listed order. Decision 2, architecture commit step, runtime flow, and workflow unit updated.
- Q: `files_total` semantics, given `heavy` must hold when `partitionable: false` (no modules)? -> Resolved (reasoning): `files_total` is the count of all in-scope planned files (plan-wide, not partition-derived). Stated in decision 4 and `PARTITION_SCHEMA`.
- Q: Foundation agent failure is unhandled; modules would build blind against missing shared types. -> Resolved (user, 2026-06-09): on Foundation `null`, abort fanout and fall back to the single-agent Execute path over the whole plan (gapcheck still runs if heavy). Added to edge cases, runtime flow, and workflow unit.
- Q: `--module foundation` is reserved for the foundation group; a module named `foundation` would collide. -> Resolved (reasoning): planner must never name a module `foundation`; forbidden at the partition source. Added to plan-module-partition, execute-no-commit-scope, `PARTITION_SCHEMA`, and edge cases.

### Iteration 2

- No new questions. Cross-file consistency verified (`files_total` plan-wide, `foundation` reserved, foundation-fallback). The sonnet Partition agent judging `heavy` does not conflict with decision 7 (it runs fresh on a small plan doc, no compaction blind spot). Converged.
</content>
</invoke>
