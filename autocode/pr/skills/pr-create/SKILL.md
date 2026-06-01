# PR create

Open a pull request for the current branch.

## Args

```
[--no-review] [--lightweight]
```

## Workflow

1. Resolve base branch: `bash "${CLAUDE_SKILL_DIR}/scripts/resolve-base-branch.sh"`. The script prints the resolved base branch to stdout. Capture as `<base>`.
2. Push branch:
   - If no upstream (`git rev-parse --abbrev-ref --symbolic-full-name '@{u}'` fails): `git push -u origin HEAD`.
   - Else: `git push`.
3. Generate title from branch + last commit subject. Shape: `<type>(<ticket>): <subject>` or `<type>: <subject>`. Derive `<type>` and `<ticket>` from branch prefix per `$AUTOCODE_CONFIG_DIR/conventions/branch-naming.md` (branch is `<type>/<ticket>/<short>` or `<type>/<short>`). `<subject>` comes from `git log -1 --pretty=%s`.
4. Generate body:
   - Default (no `--lightweight`):
     - Read `.github/PULL_REQUEST_TEMPLATE.md` and `$AUTOCODE_CONFIG_DIR/conventions/pr-template.md`.
     - Inspect changes: `git diff <base>...HEAD` and `git log <base>..HEAD --oneline`. Read source files when needed for accurate section text.
     - Fill every section of the template. Empty sections get a placeholder (`(none)` or `_n/a_`); never drop a section.
     - Strip HTML comments (template instructions, not content). Copy checklist items character-for-character; only flip `[ ]` to `[x]` when satisfied.
     - When a ticket id is parseable from the branch (per `branch-naming`), add a `Closes #<ticket-id>` line so the merge auto-closes the linked issue. This is what advances a unit sub-issue to `done`.
     - Write to `body="$(mktemp -d -t autocode-pr)/body.md"`.
   - `--lightweight`:
     - Skip template. Body is a one-paragraph summary derived from commit subjects via `git log <base>..HEAD --pretty='- %s'`.
     - Write to `body="$(mktemp -d -t autocode-pr)/body.md"`.
5. Open PR: `provider/run.sh git-remote pr-create --title "<title>" --body-file "${body}" --assignee @me --base "<base>"`. Pass `--no-review` through when set. Capture the URL from stdout. Parse the PR number from the URL trailing segment.
6. Link issue when ticket id is parseable from the branch:
   - `sleep 15` to let any `pr-issue-link.yml` workflow run first.
   - `provider/run.sh git-remote pr-issue-link <pr-number> <ticket-id>` (idempotent backup).
   - Skip when `--lightweight`.
7. Request reviews unless `--no-review`:
   - Read `$AUTOCODE_CONFIG_DIR/conventions/reviewers.md`. Each line is a GitHub login; lines starting with `!` are exclusions; blank lines and `#` comments are ignored.
   - Resolve current user from `provider/run.sh git-remote current-user` `.login`.
   - Reviewer list = all non-`!` lines, minus any `!`-prefixed lines, minus the current user.
   - Empty list: skip. Otherwise: `provider/run.sh git-remote pr-review-request <pr-number> <r1> <r2> ...`.
8. Background hygiene unless `--lightweight`:
   - Spawn the `pr-hygiene` agent via the Task tool with `run_in_background: true`.
   - Prompt includes: pushed commit SHA(s) from `git log <base>..HEAD --pretty=%H` and changed files from `git diff <base>...HEAD --name-only`.
   - Do not wait for completion.
9. Report:
   - PR URL.
   - Branch name.
   - Ticket id (or `none`).
   - Reviewers requested (or `SKIPPED`).
   - Next steps: `/pr-fix-ci` if CI fails, `/pr-review` when reviews land, `/pr-rebase` if base advances.

## Rules

- Conventional-commit title shape required.
- Body fills every template section. Empty sections get a placeholder (`(none)` or `_n/a_`).
- `--lightweight` skips template, sleep+link, reviewer request, and hygiene dispatch. Explicit `--no-review` wins over implicit reviewer request.
- Never force-push or rewrite history.

$ARGUMENTS
