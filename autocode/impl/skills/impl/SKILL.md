# Impl

Implement the unit of work that `impl-start` set up, from the approved design through to "ready for review", then hand off to `/impl-critique`. Runs strictly between `impl-start` (which created the worktree, branch, and context) and `impl-critique` (which reviews). Unit-agnostic and issue-agnostic: it consumes the context `impl-start` left and the design on disk; it does not select units or touch the tracker.

Thin and steerable, not a one-shot. It loads the authoritative spec, turns it into a concrete per-file task list, implements against that scope (not beyond it), commits at meaningful checkpoints, and stops for review. It does not self-judge the result and does not own progress logging.

Design-folder layout, `.impl-context` keys, unit DAG, and the progress lifecycle: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- `--auto`: skip the task-list approval checkpoint and run start-to-finish. Default is to present the task list and wait for approval before editing.
- Optional freeform note: extra guidance or constraints to fold into the plan (context, not a scope expander).

## Workflow

1. Confirm the worktree context. `git rev-parse --abbrev-ref HEAD` must not be the repo's default branch; if it is, the worktree was never set up, so tell the user to run `/impl-start` first and stop.

2. Resolve the scope source.
   - If `.autocode/.impl-context` exists, read it (`design_id`, `shortname`, `slug`, `unit_key`, `epic_key`, `progress_log`). Locate `.autocode/design/<design_id>-<shortname>/`. `units/` present -> multi-unit; absent -> flat.
     - Multi-unit: `units/<slug>.md` is the spec to implement against (its `## Implementation` is the scope). `DESIGN.md` is cross-cutting context only (Architecture, Design decisions, Testing strategy, Edge cases).
     - Flat: `DESIGN.md` is the spec (its `## Implementation` section; slug = `<shortname>`).
     - Read `progress/<slug>.md` for prior lessons before planning.
   - If `.autocode/.impl-context` is absent (a ticket / freeform worktree from `impl-start`), the scope source is the ticket plus this conversation. Read the ticket via `issue-view <id>` when an id is known. No design folder, no progress log.
   - Never pull spec content from the issue body: it carries only `## Summary`, a permalink, and a marker, not the full plan. The authoritative spec is the file on disk in the worktree.

3. Build the task list. Turn the spec into a concrete, ordered plan before editing:
   - Per file to create or modify: what changes and why, keyed to the spec.
   - The test plan: which tests prove the unit, where they live.
   - The implementation order, respecting within-unit dependencies.
   Bound it strictly to the unit's `## Implementation` scope plus the DESIGN cross-cutting constraints. Anything the spec does not cover is out of scope: list it as such, do not silently fold it in. Fold the freeform note in here.

4. Checkpoint. Unless `--auto`, present the task list and stop; do not edit until the user approves or adjusts it. With `--auto`, skip the pause and proceed.

5. Implement against scope. Work the task list in order. Match the surrounding code: read the `CLAUDE.md` and `.claude/rules/` globs covering each changed path and follow them; mirror existing patterns over inventing new ones. Stay within the approved scope. If implementation reveals the scope must change, stop and surface it rather than widening silently.

6. Commit at meaningful checkpoints. Delegate each commit to `git-commit` (a logical unit of work per commit, not one monolith, not per-file noise). Committing also drives progress logging: the Stop hook nudges the `progress-logger` agent after a new commit lands. Do not run progress logging here and do not append `PROGRESS.md`; those belong to the hook and `impl-push`.

7. Stop at ready-for-review. When the task list is done and the unit builds and tests per the spec's test plan, stop and report:
   - Unit slug + sub-issue key (when in a unit context).
   - Task-list status (done / deferred-with-reason).
   - Next step: `/impl-critique` to review, then `/impl-push`.
   Do not self-critique and do not open a PR.

## Rules

- Run between `impl-start` and `impl-critique`. Do not select units, transition issues, or open PRs; those belong to `impl-start`, `impl-push`, and the hooks.
- The authoritative spec is the design file on disk, never the issue body.
- Implement to the unit's scope. Out-of-scope work is surfaced, not silently done.
- Delegate commits to `git-commit`; never inline commit logic.
- Do not own progress logging (the Stop hook + `progress-logger`) or the epic rollup (`impl-push`). Just commit at checkpoints.
- Report only at the end; the user dispatches `/impl-critique` next.

$ARGUMENTS
