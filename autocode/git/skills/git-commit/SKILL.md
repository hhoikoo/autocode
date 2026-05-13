# Git commit

Create a git commit for the current change set.

## Format

Read the repo's commit format from `$AUTOCODE_CONFIG_DIR/conventions/commit.md`. That file is the source of truth; do not inline the format. If it is missing, stop and tell the user to run `/autocode-setup`.

## Workflow

1. Run `bash "${CLAUDE_SKILL_DIR}/scripts/commit.sh" gather`. The `gather` subcommand prints a single JSON object to stdout with keys: `staged`, `unstaged`, `untracked`, `log_recent`, `current_branch`, `upstream`, `ahead`, `behind`.
2. Inspect the JSON. If `staged` is empty, identify and stage relevant files. Ask the user when scope spans unrelated concerns. Use `git diff --cached` or `git diff <path>` directly when you need the actual change text.
3. Draft the commit message per the convention loaded above.
4. Write the message to a temp file: `msg="$(mktemp -d -t autocode-commit)/msg.txt"` and write the drafted text into it.
5. Run `bash "${CLAUDE_SKILL_DIR}/scripts/commit.sh" commit "$msg"`. The script runs `git commit -F "$msg"`.
6. On pre-commit hook failure: read hook output, fix iteratively, re-stage, create a NEW commit. Never `--amend` after a failed commit. Never `--no-verify`.
7. If the branch tracks a remote and `ahead > 0`, run `bash "${CLAUDE_SKILL_DIR}/scripts/commit.sh" push`. If `upstream` is empty, tell the user the next step is opening a PR.

## Rules

- Never `--no-verify`.
- Never `--amend` after a hook failure. `--amend` mutates the previous commit; on failure the new commit didn't happen, so amending destroys the previous one.
- One logical change per commit.
- `$ARGUMENTS` is additional context for the message (extra rationale or scope hint).

$ARGUMENTS
