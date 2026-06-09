---
depends-on: []
type: task
---

# Emit a module partition section in the impl plan

## Summary

`impl-plan` writes a flat per-file plan to `.autocode/.impl-plan.md` with no module grouping, so the Execute phase has nothing to fan out across. This unit adds a new `## Module partition` section to that plan: an optional `### Foundation` group of shared types and interfaces to build first, and a `### Modules` group of file-disjoint module sets the workflow can run in parallel. The section is machine-readable and states explicitly whether the unit is partitionable at all, so the workflow's Partition agent can transcribe it into JSON without re-inferring the split. The planner already resolves every signature and data shape, so it owns the partition; this raises the bar that interfaces must be concrete enough for a module agent to implement its files without seeing sibling modules' uncommitted code.

## Implementation

Single file: `autocode/impl/skills/impl-plan/SKILL.md` (real, body-only skill). No other file changes; the workflow consumer and `impl-execute --module` flag are sibling units.

### Deliverable

`impl-plan` writes a `## Module partition` section into `.autocode/.impl-plan.md` alongside the existing per-file task list, test plan, implementation order, and out-of-scope list. The section partitions the planned files into a foundation set plus file-disjoint module groups (or declares the unit non-partitionable), formatted so the workflow's Partition agent can parse it into `{ files_total, partitionable, foundation, modules[] }` without re-deriving the grouping.

### Files to modify

`autocode/impl/skills/impl-plan/SKILL.md`:

- Workflow step 3 ("Build the mechanical plan", SKILL.md:26-31): add a sub-bullet directing the planner to decide the partition as the final step of planning, once every file, signature, and data shape is resolved. The partition is derived from the already-resolved file DAG, not inferred separately.
- Workflow step 4 ("Write the plan", SKILL.md:33): add `## Module partition` to the list of sections written to `.autocode/.impl-plan.md`.
- Workflow step 5 (`--auto` block, SKILL.md:35): note that the structured result stays as-is here (file count, out-of-scope count); the partition is read from the plan file by the workflow, not surfaced in this block. Do not expand the `--auto` block.
- Add a `## Module partition` subsection (or a Rules entry) defining the exact section shape and the partitionability bar, per below.

### Exact section shape to add

Specify in the skill that `## Module partition` is written to the plan with this structure:

- An optional `### Foundation` subsection: the shared types, interfaces, and contracts plus the files that define them. Implemented sequentially BEFORE any module, so modules can build blind against the resolved interfaces. Omit the subsection entirely when nothing is shared. Each foundation file listed explicitly.
- A `### Modules` subsection: one entry per module, each carrying a name, an explicit list of the files it owns, and a one-line scope. Files MUST be disjoint across modules and disjoint from the foundation set (every planned file belongs to at most one module, or to the foundation). A module MUST NOT be named `foundation`: that name is reserved for the `### Foundation` group, and `impl-execute --module foundation` (sibling `execute-no-commit-scope`) resolves to it, so a module called `foundation` would collide.
- A partitionability statement: emit genuine file-disjoint modules only when the work truly splits into independent pieces sharing nothing but foundation-defined interfaces. Otherwise state the unit is not partitionable (single-module / no fanout) explicitly, so the consumer reads `partitionable: false` rather than guessing from an empty list. A single module is treated as non-partitionable.

Keep the format simple and machine-readable: clear subsection headers (`### Foundation`, `### Modules`), explicit file lists, module names as headers or labeled entries. The skill instructs the planner on the format; it does not parse it.

### The bar this raises on impl-plan

State in the skill (per DESIGN Design decision 3): the partition is emitted with real modules only when the foundation and plan resolve interfaces concretely enough that a module agent implements its files without seeing sibling modules' uncommitted code. Anything two modules genuinely share goes in `### Foundation`; if the interfaces cannot be pinned down that precisely, the unit is not partitionable. This extends the existing "name signatures and data shapes concretely; do not leave them 'to be determined'" rule (SKILL.md:27) to cross-module contracts.

### Consumer context (do not implement here)

The workflow's Partition agent (sibling unit `workflow-fanout-wiring`) reads this section into `{ files_total, partitionable, foundation, modules[] }`; `impl-execute` gains `--module <name>` (sibling unit `execute-no-commit-scope`) to scope execution to one group. A plan written before this epic has no `## Module partition`, so the Partition agent returns `partitionable: false` and the single-agent path runs unchanged. This unit only emits the section; it wires nothing.

### What proves it

A generated `.autocode/.impl-plan.md` for a partitionable unit contains a well-formed `## Module partition` with a `### Modules` subsection whose file lists are disjoint and an optional `### Foundation` subsection, and a unit that does not split states `partitionable: false` (or equivalent non-partitionable wording). Verified by inspecting a generated plan, per DESIGN Testing strategy.
