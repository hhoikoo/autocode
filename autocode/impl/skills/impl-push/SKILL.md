# Impl push

Commit local changes and open a PR for the unit of work in progress.

When the worktree carries a unit context (`.autocode/.impl-context`, written by `impl-start`), this also records the unit in the epic rollup and advances the sub-issue. Layout and lifecycle: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- `--auto`: run unattended; forward to `pr-create` and end with a structured result block.
- `--no-pr-hygiene`: forward to `pr-create` so the background `pr-hygiene` agent is not spawned (an orchestrator runs it); the hygiene SHA/file list is surfaced in the result.
- Optional context note (rationale or extra detail). Forwarded to `git-commit`.

## Workflow

1. Check current dir is an autocode-managed worktree with a feature branch (not the repo's default branch):
   - `git rev-parse --abbrev-ref HEAD` should NOT match the default branch.
   - If on default, delegate to `git-create-branch` to branch in place, then continue. Branching in place carries the uncommitted work onto the new branch. Do not delegate to `impl-start` here: it refuses to branch from a dirty default tree, and a fresh worktree would strand the changes in the original checkout.
2. Confirm there is work to push: uncommitted changes (`git status` / `git diff`) or commits on the branch ahead of the default branch (`git diff <default-branch>...HEAD`). `impl` may have already committed the implementation at checkpoints, leaving a clean tree but commits to PR. If both are empty, stop with a note: "no changes to push".
3. If `.autocode/.impl-context` exists, read it for `design_id`, `shortname`, `slug`, `unit_key`. Append one block to the epic rollup `.autocode/design/<design_id>-<shortname>/PROGRESS.md` per the `## PROGRESS.md` format in the design-folder spec: the sub-issue ref is `#<unit_key>`; the what-shipped paragraph and `Notes:` line are drawn from `progress/<slug>.md` (omit Notes if none). Create `PROGRESS.md` with its `# Progress: <shortname>` header if it does not exist. This block is committed with the unit, so it lands on merge.
4. Delegate to `git-commit` (stages the code plus `PROGRESS.md` and `progress/<slug>.md`). Verification is owned by the repo's pre-commit hooks; this skill does not run a verify step.
5. Delegate to `pr-create`, passing `--issue <unit_key>` so the close reference is resolved authoritatively from the unit's sub-issue key rather than branch parsing. Forward `--auto` and `--no-pr-hygiene` when this skill received them. `pr-create` owns the canonical close line (via `issue-ref` + `pr-issue-link`), so on merge the sub-issue closes and the unit advances to `done`. Outside a unit context, omit `--issue`.
6. If a unit context was present, advance the sub-issue: `provider/run.sh issue-tracker issue-transition <unit_key> in-review`.
7. Final report. No autonomous post-PR loop.
   - Default: PR URL; branch; unit slug + sub-issue key (when in a unit context); static next-step suggestions (`/pr-fix-ci` if CI fails, `/pr-review` when reviews land, `/pr-rebase` if base advances, `/impl-start --from-design <design_id>` to pick the next ready unit).
   - With `--auto`: emit a structured result block (PR URL, branch, unit slug, sub-issue key, and the `pr_hygiene` status with the SHA/file list passed up from `pr-create` when skipped) and omit the human next-steps.

## Rules

- Delegate. Don't inline commit logic, don't inline PR-body generation, don't run a verify step.
- Never push with `--force` or `--force-with-lease`. Plain `git push` only (handled by `git-commit`).
- No autonomous loops after the PR opens; user dispatches the next skill.
- Outside a unit context (no `.autocode/.impl-context`), steps 3 and 6 are skipped; the skill behaves as a plain commit-and-PR.

$ARGUMENTS
