# Impl plan

Turn the authoritative design for the unit `impl-start` set up into a concrete, mechanical implementation plan, resolving every unknown so `impl-execute` can carry it out without making a single design decision. This is the reasoning phase: all the thinking happens here.

Runs after `impl-start` and before `impl-execute`. Unit-agnostic and issue-agnostic: it consumes the context `impl-start` left and the design on disk; it does not select units or touch the tracker.

Design-folder layout, `.impl-context` keys, unit DAG, and the progress lifecycle: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- `--auto`: end with a structured result pointer instead of the human report. The plan never prompts regardless.
- Optional freeform note: extra guidance or constraints to fold into the plan (context, not a scope expander).

## Workflow

1. Confirm the worktree context. `git rev-parse --abbrev-ref HEAD` must not be the repo's default branch; if it is, the worktree was never set up, so tell the user to run `/impl-start` first and stop.

2. Resolve the scope source.
   - If `.autocode/.impl-context` exists, read it (`design_id`, `shortname`, `slug`, `unit_key`, `epic_key`, `progress_log`). Locate `.autocode/design/<design_id>-<shortname>/`. `units/` present -> multi-unit; absent -> flat.
     - Multi-unit: `units/<slug>.md` is the spec (its `## Implementation` is the scope). `DESIGN.md` is cross-cutting context only (Architecture, Design decisions, Testing strategy, Edge cases).
     - Flat: `DESIGN.md` is the spec (its `## Implementation` section; slug = `<shortname>`).
     - Read `progress/<slug>.md` for prior lessons before planning.
   - If `.autocode/.impl-context` is absent (a ticket / freeform worktree), the scope source is the ticket plus this conversation. Read the ticket via `issue-view <id>` when an id is known.
   - Never pull spec content from the issue body: it carries only `## Summary`, a permalink, and a marker, not the full plan. The authoritative spec is the file on disk in the worktree.

3. Build the mechanical plan. Decide everything now so execution is pure mechanics:
   - Run the engineering-minimalism ladder (active style) over each planned piece before committing to it: does it need to exist (YAGNI), does stdlib / a native feature / an already-installed dep cover it, can it be one line. Plan the minimum that works. Record each deliberate simplification with its ceiling and upgrade path so execution emits the matching `leanness:` comment. Speculative scope stays on the out-of-scope list, never folded in. Never trade away the `Lazy is not careless` carve-outs (active style) for brevity.
   - Per file to create or modify: the exact changes and why, keyed to the spec. Name functions, types, signatures, and data shapes concretely; do not leave them "to be determined".
   - The test plan: which tests prove the unit, where they live, what they assert.
   - The implementation order, respecting within-unit dependencies.
   - Read the `CLAUDE.md` and `.claude/rules/` globs covering each changed path and bake their constraints into the plan, so execution just follows the plan rather than re-deriving conventions.
   - The module partition: as the final planning step, once every file, signature, and data shape above is resolved, partition the planned files into a foundation set plus file-disjoint module groups (or declare the unit non-partitionable). Derive it from the file DAG you just resolved, not from a separate inference pass. Shape and partitionability bar: see `## Module partition` below.
   Bound it strictly to the unit's `## Implementation` scope plus the DESIGN cross-cutting constraints. Anything the spec does not cover is out of scope: list it as such, do not fold it in. Fold the freeform note here.

4. Write the plan to `.autocode/.impl-plan.md` in the worktree: the per-file task list, the test plan, the implementation order, the `## Module partition` section, and the out-of-scope list. This file is the spec `impl-execute` consumes. Ensure `.autocode/.gitignore` ignores it (create if missing, append if absent); it is a transient artifact, not committed.

5. Report. Default: the plan path and a short summary of the task list. With `--auto`: emit a structured result block (plan path, file count, out-of-scope count, `files_total`, `partitionable`, `foundation` `{files,summary}` or null, `modules` `[{name,files,summary}]`). These partition fields mirror the plan's own `## Module partition` section: the planner emits the partition directly in this structured result, and the workflow's Plan phase consumes it from there rather than a separate agent re-reading the plan file. Next step: `/impl-execute`.

## Module partition

`## Module partition` is written into `.autocode/.impl-plan.md` so `impl-execute --module <name>` can scope execution to one group. The same partition is also returned in the `--auto` structured result, consumed by the workflow's Plan phase.

### Foundation

Optional subsection. List the shared types, interfaces, and contracts, with every defining file named explicitly. Implemented sequentially before any module so modules build against resolved interfaces without seeing each other's uncommitted code. Omit the `### Foundation` subsection entirely when nothing is shared.

### Modules

Required subsection when partitionable. One entry per module: a name, an explicit list of files it owns, and a one-line scope. Files must be disjoint across modules and disjoint from the foundation set; every planned file belongs to at most one module or to the foundation. A module must not be named `foundation` (reserved for the `### Foundation` group; `impl-execute --module foundation` resolves to it, so the name would collide).

### Partitionability bar

Emit genuine file-disjoint modules only when the work truly splits into independent pieces sharing nothing but foundation-defined interfaces. The bar: emit real modules only when the foundation and plan resolve interfaces concretely enough that a module agent implements its files without seeing sibling modules' uncommitted code. Anything two modules genuinely share goes in `### Foundation`; if interfaces cannot be pinned that precisely, the unit is not partitionable. A single module is treated as non-partitionable.

When not partitionable, state so explicitly (e.g., `partitionable: false`) so the consumer reads the flag rather than guessing from an empty list.

Format: keep it machine-readable. Use clear subsection headers (`### Foundation`, `### Modules`), explicit file lists, and module names as headers or labeled entries. The skill instructs on format; it does not parse.

## Rules

- Reasoning lives here. Resolve every ambiguity; leave nothing for `impl-execute` to decide. A plan that punts a decision to execution has failed.
- Bound to the unit's `## Implementation` scope plus DESIGN cross-cutting constraints. Out-of-scope work is surfaced in the plan, never silently folded in.
- The authoritative spec is the design file on disk, never the issue body.
- Plan only: no edits to source, no commits, no approval checkpoint.

$ARGUMENTS
