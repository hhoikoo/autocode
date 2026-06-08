# Impl archive

Close out a completed design epic: verify every unit is done, close the epic issue, and move the folder to `.autocode/archive/`. The folder location is the epic-level source of truth for done.

Layout, discovery, and lifecycle: `@~/.autocode/autocode/design/design-folder.md`.

## Args

`<id | shortname>` (the design folder prefix or suffix). Default: ask via `AskUserQuestion` if more than one active epic exists.

## Workflow

1. Locate `.autocode/design/<id>-<short>/` (glob on either half). Derive `<id>`, `<short>`. Multi-unit if `units/` exists; flat otherwise.
2. Discover issues: `provider/run.sh issue-tracker issue-epic-list --epic <id>`. Map markers to `{slug, key, status}` and the epic issue.
3. Verify completion:
   - Multi-unit: every unit's status must be `done`. Flat: the single issue must be `done`.
   - If any unit is not `done`, report the outstanding units (slug + status) and stop. Do not archive a partially-done epic.
4. Close the epic (multi-unit only): `provider/run.sh issue-tracker issue-transition <epic-key> done`. (Flat designs have no separate epic; the single issue is already closed.)
5. Move the folder. Ensure a worktree per `@~/.autocode/autocode/_config/guides/worktree.md` + `git-create-branch "chore: archive design <short>"` first. Then:
   - `mkdir -p .autocode/archive`
   - `git mv .autocode/design/<id>-<short> .autocode/archive/<id>-<short>` (if the source no longer exists, it is already archived; report and stop).
   - In `.autocode/design/INDEX.md`, flip this epic's row to `status: archived`. The row and its id stay; never removed or reused.
6. Delegate to `git-commit` (a `chore` commit; note that the epic is complete).
7. Delegate to `pr-create --lightweight` (the change is a folder move, not code). Capture the PR number from its result.
8. Auto-merge: `provider/run.sh git-remote pr-merge <pr-number> --admin`. A folder move needs no review, and `--admin` bypasses required checks. The script is a no-op if the PR is already merged.
9. Report the PR URL, that it was merged (archiving the folder), and that the epic issue is closed.

## Rules

- Never archive an epic with outstanding units. Completion is read from the discovery call, not assumed.
- All tracker writes go through `provider/run.sh issue-tracker ...`.
- Idempotent: re-running on an already-archived epic detects the missing source folder and stops cleanly; `issue-transition` tolerates an already-closed epic.
- Delegate commit and PR creation; do not inline them.
- Auto-merge the archive PR with `--admin`: it is a pure folder move and warrants no review.

$ARGUMENTS
