---
depends-on: [scoped-verify-gate]
type: task
---

# Per-module gapcheck fan-out

## Summary

Replace the single whole-plan GapCheck agent (one opus reviewer loading the entire un-partitioned diff up to `GAP_MAX_ROUNDS` times, the reported compaction case) with a parallel fan-out for heavy, partitionable units: one gapcheck agent per module scoped to that module's files and its plan item, plus exactly one integration agent that sweeps the foundation group and any planned file no module claimed. A self-computed diff-size gate keeps small heavy units on the existing single-agent path, and heavy-but-non-partitionable units keep the current whole-diff loop unchanged. Each agent returns the existing `GAPCHECK_SCHEMA` shape; the workflow unions their gaps before the fix loop, so nothing downstream changes.

## Implementation

Deliverable: fan the heavy-unit gapcheck out per module with a self-computed size gate, a whole-diff fallback for non-partitionable units, and a residual integration bucket.

### Files to modify

- `autocode/impl/skills/impl/scripts/impl-workflow.mjs`: replace the `if (heavy)` gapcheck block at `:310-335` (a single whole-diff opus agent inside a `GAP_MAX_ROUNDS` recheck loop). This unit sits in the impl-workflow serialization chain after `scoped-verify-gate` and before `recap-phase-wiring` (DESIGN.md Architecture chain). By the time this code lands, `plan-partition-schema` has renamed `PARTITION_SCHEMA` to `PLAN_SCHEMA`, removed the Partition phase, and folded the partition into the opus Plan agent's structured output (DESIGN.md decision 6), so the partition object (call it `part`) is the Plan agent's return and carries `foundation.files: string[]`, `modules[].files: string[]`, `files_total: integer`, `heavy`, and `partitionable` (research `gapcheck-modules-files`).
- `autocode/impl/skills/impl-gapcheck/SKILL.md`: light edit only. The skill currently enumerates in-scope items as "each per-file task in the plan, plus each module" (`SKILL.md:13`). Add that a caller may instead supply a bounded scope (a single module's file list plus its module item, or a foundation-plus-residual file list) and that the pass then checks coverage of exactly that supplied scope. Output shape (`GAPCHECK_SCHEMA`) is unchanged.

### Fan-out decision

Keep the outer `if (heavy)` gate at `:312` (it already handles the non-partitionable fallback: `partitionable:false`, `modules:[]` still runs the whole-diff loop, research `e1-whole-diff-fallback-condition`; DESIGN.md edge case "Heavy but non-partitionable"). Inside it, branch on a named boolean:

```
gapFanout = part.partitionable
            && part.modules.length >= 2      # same gate as Execute :259-260
            && diffLines > GAP_FANOUT_MIN_LINES
```

- `GAP_FANOUT_MIN_LINES`: a new module-level constant, sibling of `GAP_MAX_ROUNDS` (`:34`), per the no-hardcoded-values rule. The size gate exists so small heavy units (heavy from coupling, not volume) stay single-agent (DESIGN.md decision 8).
- `diffLines`: the branch diff line count, computed from the three-source pattern already used at `:199` and `:316` (`git diff BASE...HEAD`, `git diff HEAD`, untracked from `git status --porcelain`). No `diff_lines` exists at gapcheck time: `prep.diff_lines` is produced later, inside `reviewCycle` at `:338` (research `e1-size-gate-source`; DESIGN.md decision 8). The workflow runtime never shells out (it delegates all git work to agents), so a lightweight sonnet sizing agent returns `{ diff_lines }` via a minimal integer schema; this runs once, before the fan-out branch.

When `gapFanout` is false, the existing whole-diff single-agent gapcheck loop is unchanged (the fallback for both small-heavy and non-partitionable units).

### Fan-out path

When `gapFanout` is true, dispatch round 0 via `parallel(...)`, the same shape as Execute's module fan-out at `:277-282`:

- One gapcheck agent per `part.modules[m]`, read-only, running `impl-gapcheck`, scoped to `m.files` plus the `"m.name"` module plan item. Returns `GAPCHECK_SCHEMA`.
- Exactly one integration agent (unless the bucket is provably empty, below), read-only, running `impl-gapcheck`, scoped to the integration bucket.

Union every agent's `gaps` (concatenate, then de-dupe on `file` + `plan_item`, mirroring the finding de-dupe at `:213-221`) into a single round-0 gap set that feeds the existing gapfix loop.

### Integration bucket

The bucket is `foundation.files U residual_files`, where `residual_files = all_in_scope_planned_files \ (foundation.files U union(modules[].files))` (DESIGN.md decision 7; research `e1-integration-bucket`). A file the planner forgot to place in any module still lands here and gets checked.

`PLAN_SCHEMA` carries `files_total` as a count, not the member list, so the full planned-file set must be re-read from `.autocode/.impl-plan.md`. The workflow holds `foundation.files` and `modules[].files` (member lists from the schema) but not the full plan list, so the integration agent itself re-reads the plan's per-file task list, computes the set complement to enumerate `residual_files`, gapchecks `foundation.files U residual_files`, and asserts the checksum `|foundation| + Sum|modules| + |residual| == files_total` (surfacing a mismatch, e.g. a module file absent from the plan or a cross-module overlap, as a gap). The workflow passes the integration agent `files_total`, `foundation.files`, and the union of `modules[].files` so it knows what to exclude and what to check against.

```
  plan per-file task list  (files_total members)
  |
  +-- foundation.files ---------\
  +-- module A files            |  per-module gapcheck agents (one each)
  +-- module B files ----------/
  +-- <anything left over> = residual ---\  integration agent
      foundation.files U residual ------ /  (checksum asserted here)
```

Empty bucket: when `foundation` is null/empty and the workflow's arithmetic pre-check (`files_total - |union(foundation.files, modules[].files)|`, computable from the member lists it holds) yields 0 residual, skip the integration agent but still assert the module checksum so the empty bucket is proven, not assumed (DESIGN.md edge cases "Empty integration bucket", "No foundation group"). Any non-zero residual or non-empty foundation runs the integration agent.

### Recheck loop

Fan out only the round-0 coverage sweep (the compaction case). The existing gapfix + recheck loop (`GAP_MAX_ROUNDS`, `:319-332`) stays, and its recheck re-verifies only the outstanding gap items (a small, bounded set post-fix) with a single scoped agent, so rechecks never reload the whole diff. `gapRoundsUsed` and `remainingGaps` (`:333-334`, returned at `:371-372`) stay populated with the same meaning.

### Public interfaces

No new exported schema. Reuses `GAPCHECK_SCHEMA` (`:171-191`) for every module and integration agent. One new module-level constant `GAP_FANOUT_MIN_LINES`. One minimal ad-hoc integer schema for the sizing agent (defined inline where the other schemas live, `:44-191`). Return object of the workflow is unchanged.

### Tests

No unit-test harness for workflow scripts; verify by driving the flow (the `verify` skill), per DESIGN.md testing strategy:

- Heavy, partitionable unit with a large diff and >=2 modules: emitted phase log shows parallel `GapCheck` agents (one per module plus one integration), gaps union correctly, the checksum assertion passes.
- Heavy, partitionable, but small diff (under `GAP_FANOUT_MIN_LINES`): single-agent whole-diff path, no fan-out.
- Heavy but non-partitionable (`partitionable:false`, `modules:[]`): unchanged whole-diff loop runs.
- A planned file left out of every module: lands in the residual bucket and is checked.
- Foundation absent and no residual: integration agent skipped, module checksum still asserted.
- `GAPCHECK_SCHEMA` validates for every agent; `gap_rounds` / `remaining_gaps` in the workflow return stay correct after a gapfix round.
