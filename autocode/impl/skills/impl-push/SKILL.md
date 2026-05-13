# Impl push

Commit local changes and open a PR.

## Args

Optional context note (rationale or extra detail). Forwarded to `git-commit` as `$ARGUMENTS`.

## Workflow

1. Check current dir is an autocode-managed worktree with a feature branch (not the repo's default branch):
   - `git rev-parse --abbrev-ref HEAD` should NOT match the default branch.
   - If on default, delegate to `impl-start` to create a worktree+branch, then continue.
2. Run `git status` and `git diff` to confirm uncommitted changes exist. If clean, stop with a note: "no changes to push".
3. Delegate to `git-commit` skill. Verification is owned by the repo's pre-commit hooks; this skill does not run a verify step.
4. Delegate to `pr-create` skill.
5. Final report. No autonomous post-PR loop. Print:
   - PR URL.
   - Branch.
   - Static next-step suggestions:
     - `/pr-fix-ci` if CI fails.
     - `/pr-review` when reviews land.
     - `/pr-rebase` if base advances.

## Rules

- Delegate. Don't inline commit logic, don't inline PR-body generation, don't run a verify step.
- Never push with `--force` or `--force-with-lease`. Plain `git push` only (handled by `git-commit`).
- No autonomous loops after the PR opens; user dispatches the next skill.

$ARGUMENTS
