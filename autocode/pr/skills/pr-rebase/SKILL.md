# PR rebase

Rebase the current branch onto its base and resolve conflicts.

## Args

(none; operates on the current branch)

## Workflow

1. Resolve base: re-use the `pr-create` skill's resolve script if available, else `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
2. `git fetch origin <base>`. If `git log HEAD..origin/<base> --oneline` is empty, report "up to date" and stop.
3. `git rebase origin/<base>`.
4. Conflict resolution loop, per file:
   - `git diff --name-only --diff-filter=U` gets the conflicted set.
   - Guardrail: if more than 5 files conflict in a single rebase step, pause and ask via `AskUserQuestion` whether to continue or abort.
   - Read each file. Read base log touching the file: `git log HEAD..origin/<base> -- <file>`.
   - Design id collision: if the conflicted file is `.autocode/design/INDEX.md` and the two sides claim the same `id`, renumber this branch's design rather than merging the rows. The id is opaque, encoded only in the folder name and the INDEX row, so no file contents change:
     - Next free id = highest id across both sides + 1, zero-padded to 4 digits.
     - `git mv .autocode/design/<old-id>-<shortname> .autocode/design/<new-id>-<shortname>`.
     - Resolve `INDEX.md` to the base rows plus this branch's row carrying the new id. `git add` the renamed folder and `INDEX.md`.
   - Resolve. `git add <file>`. After all files for the step are resolved, `git rebase --continue`.
   - On incompatible conflicts where intent is ambiguous, ask the user via `AskUserQuestion`.
5. Verify: read the verify command from `$AUTOCODE_CONFIG_DIR/conventions/build.md` and run it.
   - Small obvious failure (lint, typo): fix and amend the relevant commit (`git commit --amend --no-edit` after re-staging).
   - Non-trivial failure: stop and ask the user.
6. Push: `git push --force-with-lease`. Never `git push --force`.
7. Background hygiene. A rebase rewrites the branch and may resolve content conflicts, so the PR body can be stale. Spawn the `pr-hygiene` agent via the Task tool with `run_in_background: true`; do not wait for it. The prompt includes the rebased branch SHAs (`git log <base>..HEAD --pretty=%H`) and changed files (`git diff <base>...HEAD --name-only`). The agent self-checks for a PR and handles design PRs (recompose) vs code PRs (diff-based) on its own. Skip only if the rebase was a no-op (step 2 already stops then).
8. Report: rebased branch, conflict count resolved, verify result, and that hygiene was dispatched.

## Rules

- `--force-with-lease`, never `--force`.
- 5-file conflict guardrail.
- On an `INDEX.md` id collision, renumber this branch to the next free id (rename the folder + fix the row); never merge two rows onto one id.
- Verify before push; don't push a broken rebase.

$ARGUMENTS
