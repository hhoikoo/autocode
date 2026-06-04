# PR create

Open a pull request for the current branch.

## Args

```
[--no-review] [--lightweight] [--body-file <path>] [--issue <tracker-key>] [--auto] [--no-pr-hygiene]
```

- `--issue <tracker-key>`: authoritative tracker key for the linked issue. Overrides branch parsing as the source for both the title pattern and the close reference. `impl-push` passes the unit's sub-issue key here.
- `--auto`: run unattended (no interactive prompts) and end with a structured result block instead of the human report.
- `--no-pr-hygiene`: skip the background `pr-hygiene` dispatch (an orchestrator runs it instead). Distinct from `--no-review`.

## Workflow

1. Resolve base branch: `bash "${CLAUDE_SKILL_DIR}/scripts/resolve-base-branch.sh"`. The script prints the resolved base branch to stdout. Capture as `<base>`.
2. Push branch:
   - If no upstream (`git rev-parse --abbrev-ref --symbolic-full-name '@{u}'` fails): `git push -u origin HEAD`.
   - Else: `git push`.
3. Resolve the issue id, then generate the title deterministically.
   - Issue id: `--issue <tracker-key>` when given; otherwise parse it from the branch per `$AUTOCODE_CONFIG_DIR/conventions/issue-id.md` (its extraction rules). May be empty (no associated issue).
   - Title structure is fixed by the convention, not improvised. Read the `## Where it appears` -> `PR title` entry of `issue-id.md`. If it specifies a pattern that carries the id and an id resolved, the title is `<type>(<id>): <subject>`. If it says `not required` (or no id resolved), the title is `<type>: <subject>`. Derive `<type>` from the branch prefix per `branch-naming.md`; take `<subject>` from `git log -1 --pretty=%s`. The model authors only `<subject>`; it never decides whether the id appears.
4. Generate body:
   - `--body-file <path>` given: use that file verbatim as `body`. Skip all generation below (template and lightweight); the caller owns the content.
   - Default (no `--lightweight`):
     - Read `.github/PULL_REQUEST_TEMPLATE.md` and `$AUTOCODE_CONFIG_DIR/conventions/pr-template.md`.
     - Inspect changes: `git diff <base>...HEAD` and `git log <base>..HEAD --oneline`. Read source files when needed for accurate section text.
     - Fill every section of the template. Empty sections get a placeholder (`(none)` or `_n/a_`); never drop a section.
     - Strip HTML comments (template instructions, not content). Copy checklist items character-for-character; only flip `[ ]` to `[x]` when satisfied.
     - Do not hand-write any issue reference (`Closes`, `Refs`, etc.). The close line is owned by step 6, which keeps it canonical and provider-correct.
     - Write to `body="$(mktemp -d -t autocode-pr)/body.md"`.
   - `--lightweight`:
     - Skip template. Body is a one-paragraph summary derived from commit subjects via `git log <base>..HEAD --pretty='- %s'`.
     - Write to `body="$(mktemp -d -t autocode-pr)/body.md"`.
5. Open PR: `provider/run.sh git-remote pr-create --title "<title>" --body-file "${body}" --assignee @me --base "<base>"`. Pass `--no-review` through when set. Capture the URL from stdout. Parse the PR number from the URL trailing segment.
6. Link the issue (skip when `--lightweight` or no issue id from step 3):
   - Resolve the git-remote close target: `ref=$(provider/run.sh git-remote issue-ref <issue-id>)`. This maps the tracker key to a git-remote-native issue number (identity for GitHub Issues; a mirrored issue for other trackers).
   - Empty `ref` means there is nothing on this remote to close (non-GitHub tracker with no mirror); skip linking and note it.
   - Otherwise `sleep 15` to let any `pr-issue-link.yml` workflow run first, then `provider/run.sh git-remote pr-issue-link <pr-number> <ref>`. The script appends the canonical `Closes #<ref>` (idempotent), so the merge auto-closes the issue and advances a unit sub-issue to `done`.
7. Request reviews unless `--no-review`:
   - Read `$AUTOCODE_CONFIG_DIR/conventions/reviewers.md`. Each line is a GitHub login; lines starting with `!` are exclusions; blank lines and `#` comments are ignored.
   - Resolve current user from `provider/run.sh git-remote current-user` `.login`.
   - Reviewer list = all non-`!` lines, minus any `!`-prefixed lines, minus the current user.
   - Empty list: skip. Otherwise: `provider/run.sh git-remote pr-review-request <pr-number> <r1> <r2> ...`.
8. Background hygiene unless `--lightweight` or `--no-pr-hygiene`:
   - Spawn the `pr-hygiene` agent via the Task tool with `run_in_background: true`.
   - Prompt includes: pushed commit SHA(s) from `git log <base>..HEAD --pretty=%H` and changed files from `git diff <base>...HEAD --name-only`.
   - Do not wait for completion.
   - When `--no-pr-hygiene` is set, do not spawn; instead include the same SHA(s) and changed-file list in the result so the caller can run hygiene itself.
9. Report:
   - Default: PR URL, branch name, issue id (or `none`), close ref (or `none`), reviewers requested (or `SKIPPED`), and next steps (`/pr-fix-ci` if CI fails, `/pr-review` when reviews land, `/pr-rebase` if base advances).
   - With `--auto`: emit a structured result block (PR URL, branch, issue id, close ref, reviewers, and `pr_hygiene: dispatched|skipped` with the SHA/file list when skipped) and omit the human next-steps.

## Rules

- Conventional-commit title shape required. The id's presence in the title is fixed by the `issue-id` convention, never improvised; the model authors only the subject.
- The PR body never carries a hand-written issue reference (`Closes`, `Refs`, etc.). The close line is owned by `pr-issue-link.sh` via the `issue-ref` resolution, keeping it canonical (`Closes #N`, never `Refs`) and provider-correct.
- Body fills every template section. Empty sections get a placeholder (`(none)` or `_n/a_`).
- `--lightweight` skips template, sleep+link, reviewer request, and hygiene dispatch. Explicit `--no-review` wins over implicit reviewer request. `--no-pr-hygiene` skips only the hygiene dispatch.
- `--body-file <path>` supplies the body verbatim, overriding both default and lightweight body generation. Compose with `--lightweight` to also skip link/reviewers/hygiene.
- Never force-push or rewrite history.

$ARGUMENTS
