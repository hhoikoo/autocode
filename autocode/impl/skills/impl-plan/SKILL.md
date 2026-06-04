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
   - Per file to create or modify: the exact changes and why, keyed to the spec. Name functions, types, signatures, and data shapes concretely; do not leave them "to be determined".
   - The test plan: which tests prove the unit, where they live, what they assert.
   - The implementation order, respecting within-unit dependencies.
   - Read the `CLAUDE.md` and `.claude/rules/` globs covering each changed path and bake their constraints into the plan, so execution just follows the plan rather than re-deriving conventions.
   Bound it strictly to the unit's `## Implementation` scope plus the DESIGN cross-cutting constraints. Anything the spec does not cover is out of scope: list it as such, do not fold it in. Fold the freeform note here.

4. Write the plan to `.autocode/.impl-plan.md` in the worktree: the per-file task list, the test plan, the implementation order, and the out-of-scope list. This file is the spec `impl-execute` consumes. Ensure `.autocode/.gitignore` ignores it (create if missing, append if absent); it is a transient artifact, not committed.

5. Report. Default: the plan path and a short summary of the task list. With `--auto`: emit a structured result block (plan path, file count, out-of-scope count). Next step: `/impl-execute`.

## Rules

- Reasoning lives here. Resolve every ambiguity; leave nothing for `impl-execute` to decide. A plan that punts a decision to execution has failed.
- Bound to the unit's `## Implementation` scope plus DESIGN cross-cutting constraints. Out-of-scope work is surfaced in the plan, never silently folded in.
- The authoritative spec is the design file on disk, never the issue body.
- Plan only: no edits to source, no commits, no approval checkpoint.

$ARGUMENTS
