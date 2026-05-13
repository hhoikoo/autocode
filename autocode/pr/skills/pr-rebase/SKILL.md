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
   - Resolve. `git add <file>`. After all files for the step are resolved, `git rebase --continue`.
   - On incompatible conflicts where intent is ambiguous, ask the user via `AskUserQuestion`.
5. Verify: read the verify command from `$AUTOCODE_CONFIG_DIR/conventions/build.md` and run it.
   - Small obvious failure (lint, typo): fix and amend the relevant commit (`git commit --amend --no-edit` after re-staging).
   - Non-trivial failure: stop and ask the user.
6. Push: `git push --force-with-lease`. Never `git push --force`.
7. Report: rebased branch, conflict count resolved, verify result.

## Rules

- `--force-with-lease`, never `--force`.
- 5-file conflict guardrail.
- Verify before push; don't push a broken rebase.

$ARGUMENTS
