# Impl execute

Carry out the plan `impl-plan` wrote, mechanically, to "ready for review". No design decisions: every unknown was resolved during planning, so this phase just does the work and commits. Runs after `impl-plan`; hands off to `impl-critique` then `impl-push`.

Two modes: default executes the plan; `--fix` applies review findings.

Design-folder layout, `.impl-context` keys, and the progress lifecycle: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- `--fix <findings>`: apply the supplied review findings instead of the plan. Each finding is a `file:line` plus the required change (the `impl-critique-decide` output). Used by the orchestrator's fix phase.
- `--auto`: run unattended and end with a structured result block.
- Optional freeform note (default mode): minor extra context. Never a scope expander.

## Workflow (default)

1. Confirm the worktree context. `git rev-parse --abbrev-ref HEAD` must not be the repo's default branch; if it is, stop and tell the user to run `/impl-start` first.

2. Read `.autocode/.impl-plan.md`. This is the spec for execution. If it is absent, stop and tell the user to run `/impl-plan` first; execution does not improvise a plan.

3. Execute the plan in order. Work the per-file task list as written; the plan already baked in the `CLAUDE.md` and `.claude/rules/` constraints for each path, so follow it and mirror existing patterns. Stay within the plan's scope.

4. If the plan proves wrong or incomplete, stop and surface it; do not silently redesign or widen scope. A plan gap kicks back to `impl-plan`, not a decision made here.

5. Commit at meaningful checkpoints. Delegate each commit to `git-commit` (a logical unit per commit, not one monolith, not per-file noise). Committing drives progress logging via the Stop hook + `progress-logger`; do not log progress here and do not append `PROGRESS.md` (that is `impl-push`).

6. Verify per the plan's test plan (build + the named tests). Stop at ready-for-review.

7. Report. Default: task-list status (done / deferred-with-reason) and next step (`/impl-critique`, then `/impl-push`). With `--auto`: emit a structured result block (files changed, commits, task-list status). Do not self-critique and do not open a PR.

## Workflow (--fix)

1. Confirm the worktree context (as above).
2. Parse the supplied findings: each is a `file:line` and the change it requires.
3. Apply each fix minimally, matching the surrounding code and conventions. Do not refactor beyond the finding. Commit via `git-commit` (group related fixes).
4. Report what was fixed and what was skipped (with reason). With `--auto`: structured result block (findings applied, skipped).

## Rules

- Mechanical. Execute the plan or the findings; do not redesign. Surface plan gaps instead of widening scope silently.
- Delegate commits to `git-commit`; never inline commit logic.
- Do not own progress logging (the Stop hook + `progress-logger`) or the epic rollup (`impl-push`).
- `--fix` applies only the supplied findings, minimally; it is not a second implementation pass.
- Report only at the end; do not self-critique or open a PR.

$ARGUMENTS
