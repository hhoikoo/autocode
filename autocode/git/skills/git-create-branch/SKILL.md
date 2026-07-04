# Git create branch

Resolve a branch name from a ticket id or freeform `type: description`, then create and check out the branch from the repo's default base.

## Naming convention

Read the repo's branch-naming scheme (allowed types and the branch pattern) from `$AUTOCODE_CONFIG_DIR/conventions/branch-naming.md`. That file is the source of truth; do not inline the type list or pattern. If it is missing, stop and tell the user to run `/autocode-setup`.

## Args

`$ARGUMENTS` is either:

- A ticket id (`BA-1234`, `42`, `#42`). Provider lookup derives type and short-name.
- A `<type>: <description>` string (`feat: add login flow`).

If `$ARGUMENTS` matches `[A-Z]+-\d+` or is purely numeric (with optional `#` prefix), use ticket mode. Otherwise description mode.

## Workflow

### 1. Check current branch

- Run `git branch --show-current`.
- On the repo's default branch (`main`):
  1. `git fetch origin main`.
  2. If `git log HEAD..origin/main --oneline` is non-empty: stash if working tree is dirty, `git merge --ff-only origin/main`, pop stash if stashed.
  3. Proceed.
- Off default: ask the user via `AskUserQuestion` whether to (a) branch from the current branch, (b) switch to `main` first, or (c) switch to a different branch they name.

### 2. Resolve type and short-name

Ticket mode:

1. Fetch ticket details: `bash ~/.autocode/provider/run.sh issue-tracker issue-view <id>`. Parse the returned JSON for `type` and `summary`.
2. Read commit_type mapping from `$AUTOCODE_CONFIG_DIR/conventions/issue-types.md`.
3. Map the ticket's issue type to a commit_type via that file, constrained to the allowed types from the branch-naming convention. If the mapping is ambiguous (e.g. `task` could be `feat` or `chore`), ask the user via `AskUserQuestion`.
4. Extract 2-4 keywords from `summary` for the short-name.

Description mode:

1. Parse the type prefix before the first `:`. Validate it against the allowed types from the branch-naming convention; reject an unknown prefix.
2. Extract 2-4 keywords from the description for the short-name.

Both modes: short-name is kebab-case lowercase. Strip filler words (`the`, `a`, `an`, `is`, `of`, `for`, `to`, `in`, `on`, `with`).

### 3. Branch name

Build the name from the pattern in the branch-naming convention, substituting `type`, the ticket `id` (omitted in description mode), and the kebab-case `short` slug. Default pattern `<type>/<id-or-omit>/<short>` yields `feat/42/add-login` or `feat/BA-1234/add-login` in ticket mode, `feat/add-login` in description mode.

### 4. Create and check out

Run `git checkout -b <branch>` against the base resolved in step 1. If the command fails (e.g. branch already exists), surface the error and stop. Never overwrite.

### 5. Report

Print the branch name on one line.

## Rules

- Base is the repo's default branch. Epic-base detection is out of scope.
- Never overwrite an existing branch.

$ARGUMENTS
