---
depends-on: []
type: task
---

# Add --no-commit and --module scoping to impl-execute

## Summary

`impl-execute` gains two composable flags so the fanout workflow can drive it as a write-only, scoped agent. `--no-commit` suppresses the `git-commit` delegation entirely: the agent implements and leaves changes in the working tree (unstaged, uncommitted), reporting the list of files written so the workflow's sequential Commit step can stage and commit per group. `--module <name>` scopes execution to one group of the plan's `## Module partition` (the literal group `foundation` is a valid name), implementing only that group's files and tasks. The two compose: `impl-execute --auto --no-commit --module <name>` is the per-module fanout invocation, and `--module foundation --no-commit` is the foundation pass. With neither flag, behavior is byte-identical to today (whole plan, commits via `git-commit`), so the change is backward compatible.

## Implementation

Deliverable: two new composable flags on `impl-execute`, `--no-commit` and `--module <name>`, leaving the default (no-flag) path unchanged.

File to modify (only this file): `autocode/impl/skills/impl-execute/SKILL.md` (the real, body-only skill).

Contract changes:

- `--no-commit` (`## Args`, new entry): suppress the `git-commit` delegation entirely. Implement and leave all changes in the working tree, unstaged and uncommitted. Report the list of files written. Because nothing commits, the Stop-hook progress logging does not fire in this agent; that is intentional, since the workflow's separate Commit step owns commits and triggers logging.
- `--module <name>` (`## Args`, new entry): read the plan's `## Module partition` section and implement ONLY the named group's files and tasks. `foundation` is a reserved name that resolves to the `### Foundation` group (the planner never emits a module called `foundation`; see `plan-module-partition`); any other `<name>` matches a `### Modules` entry. Without `--module`, execute the whole plan (current behavior, unchanged).
- Composition: `--no-commit` and `--module` are independent and combine. `impl-execute --auto --no-commit --module <name>` is the fanout module-agent invocation; `--module foundation --no-commit` is the foundation pass. Both also compose with `--auto` (structured result block).
- Backward compatibility: with neither flag, the default path is byte-identical to today (whole plan, commit at checkpoints via `git-commit`).

Edits within `impl-execute/SKILL.md`:

- `## Args`: add the two flags above with their contracts.
- `## Workflow (default)`: scope step 3 to the named `## Module partition` group when `--module` is set (whole plan otherwise); make step 5 conditional on `--no-commit`. Under `--no-commit`, skip the `git-commit` delegation, leave changes in the working tree, and (under `--auto`) report the list of files written in the result block instead of commits. Note that without commits the Stop-hook progress logging does not fire here, by design.
- `## Workflow (--fix)`: `--no-commit` applies here too if the workflow uses it during the gapcheck fix loop; under `--no-commit`, skip the `git-commit` in step 3 and report files written. `--module` is not used by `--fix` (findings already carry `file:line`).
- `## Rules`: keep "Delegate commits to `git-commit`; never inline commit logic" but qualify it so `--no-commit` is the explicit exception (write-only, no commit, no inline commit logic either). Keep the rule that the skill does not own progress logging.

What proves it: a generated `.autocode/.impl-plan.md` carrying a `## Module partition` plus a manual run of `impl-execute --no-commit --module <name>` that writes only that group's files and leaves them uncommitted in the working tree; and a no-flag run whose behavior and `--auto` output are byte-identical to today.

Scope note: this unit edits `impl-execute/SKILL.md` only. The plan-side `## Module partition` format is owned by `plan-module-partition`; the workflow wiring that calls these flags is owned by `workflow-fanout-wiring`. This unit defines the contract those two consume.
