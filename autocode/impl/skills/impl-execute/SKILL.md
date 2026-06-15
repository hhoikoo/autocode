# Impl execute

Carry out the plan `impl-plan` wrote, mechanically, to "ready for review". No design decisions: every unknown was resolved during planning, so this phase just does the work and commits. Runs after `impl-plan`; hands off to `impl-critique` then `impl-push`.

Two modes: default executes the plan; `--fix` applies review findings.

Design-folder layout, `.impl-context` keys, and the progress lifecycle: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- `--fix <findings>`: apply the supplied review findings instead of the plan. Each finding is a `file:line` plus the required change (the `impl-critique-decide` output). Used by the orchestrator's fix phase.
- `--auto`: run unattended and end with a structured result block.
- `--no-commit`: suppress the `git-commit` delegation entirely. Implement and leave all changes in the working tree, unstaged and uncommitted. Report the list of files written. Because nothing commits, the Stop-hook progress logging does not fire in this agent; that is intentional: the workflow's separate Commit step owns commits and triggers logging.
- `--module <name>`: read the plan's `## Module partition` section and implement ONLY the named group's files and tasks. `foundation` is a reserved name resolving to the `### Foundation` group (the planner never emits a module literally named `foundation`; cross-ref `plan-module-partition`); any other `<name>` matches a `### Modules` entry. Without `--module`, execute the whole plan (current behavior, unchanged).
- `--no-commit` and `--module` are independent and compose with each other and with `--auto`. `impl-execute --auto --no-commit --module <name>` is the per-module fanout invocation; `--module foundation --no-commit` is the foundation pass.
- Optional freeform note (default mode): minor extra context. Never a scope expander.

## Workflow (default)

1. Confirm the worktree context. `git rev-parse --abbrev-ref HEAD` must not be the repo's default branch; if it is, stop and tell the user to run `/impl-start` first.

2. Read `.autocode/.impl-plan.md`. This is the spec for execution. If it is absent, stop and tell the user to run `/impl-plan` first; execution does not improvise a plan.

3. Execute the plan in order. Work the per-file task list as written; the plan already baked in the `CLAUDE.md` and `.claude/rules/` constraints for each path, so follow it and mirror existing patterns. Stay within the plan's scope. When `--module <name>` is set, scope execution to the named group in the plan's `## Module partition` section: `foundation` resolves to the `### Foundation` group; any other `<name>` resolves to the matching `### Modules` entry. Implement only that group's files and tasks. Without `--module`, execute the whole plan (unchanged).

4. If the plan proves wrong or incomplete, stop and surface it; do not silently redesign or widen scope. A plan gap kicks back to `impl-plan`, not a decision made here.

5. Commit at meaningful checkpoints. Delegate each commit to `git-commit` (a logical unit per commit, not one monolith, not per-file noise). Committing drives progress logging via the Stop hook + `progress-logger`; do not log progress here and do not append `PROGRESS.md` (that is `impl-push`). Under `--no-commit`, skip the `git-commit` delegation entirely: leave all changes unstaged and uncommitted in the working tree. With `--auto`, report the list of files written in the result block instead of commits. Without commits, the Stop-hook progress logging does not fire here; that is by design. Without `--no-commit`, behavior is unchanged.

6. Verify per the plan's test plan (build + the named tests). Stop at ready-for-review.

7. Report. Default: task-list status (done / deferred-with-reason) and next step (`/impl-critique`, then `/impl-push`). With `--auto`: emit a structured result block (files changed, commits, task-list status). Do not self-critique and do not open a PR.

## Workflow (--fix)

1. Confirm the worktree context (as above).
2. Parse the supplied findings: each is a `file:line` and the change it requires.
3. Apply each fix minimally, matching the surrounding code and conventions. Do not refactor beyond the finding. Commit via `git-commit` (group related fixes). Under `--no-commit`, skip the `git-commit` delegation and leave all changes unstaged and uncommitted in the working tree; report files written instead of commits. `--module` is not used by `--fix` (findings already carry `file:line`).
4. Report what was fixed and what was skipped (with reason). With `--auto`: structured result block (findings applied, skipped).

## Rules

- Mechanical. Execute the plan or the findings; do not redesign. Surface plan gaps instead of widening scope silently.
- Build minimal per the plan: emit the `leanness:` ceiling comments the plan named, and leave the plan's ONE runnable check for non-trivial logic. Do not add abstractions, scaffolding, or tests the plan did not call for.
- Delegate commits to `git-commit`; never inline commit logic. Exception: under `--no-commit`, write changes to the working tree without committing and without inlining commit logic; the workflow's Commit step owns commits and triggers progress logging.
- Do not own progress logging (the Stop hook + `progress-logger`) or the epic rollup (`impl-push`).
- `--fix` applies only the supplied findings, minimally; it is not a second implementation pass.
- Report only at the end; do not self-critique or open a PR.

$ARGUMENTS
