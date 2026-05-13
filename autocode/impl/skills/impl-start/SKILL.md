# Impl start

Set up a worktree + feature branch for implementation work.

## Args

One of:
- `--from-design <ticket-num | shortname>`: seed from a design doc.
- `<ticket-id>` (e.g. `42`, `BA-1234`): ticket mode.
- `<type>: <description>` (e.g. `feat: add login flow`): description mode.

## Workflow

1. If `--from-design`:
   - Locate `.autocode/design/<ticket>-<short>/DESIGN.md` (glob if only one of ticket/short is provided).
   - Read the design doc into context.
   - Derive the implementation ticket from the doc body. If absent, ask the user via `AskUserQuestion` whether to delegate to `issue-create` to open one.
2. Otherwise, treat the arg as a ticket id (ticket mode) or `<type>: <description>` (description mode).
3. Use Claude Code's `EnterWorktree` tool to create a new worktree. Name follows the branch naming convention (delegate the actual branch creation to step 4). Base the worktree on the repo's default branch (commonly `main`).
4. Inside the worktree, delegate to the `git-create-branch` skill to produce the feature branch.
5. Report:
   - Worktree path.
   - Branch name.
   - Ticket id (if any).
   - Next step: hand control back to the user; they (or `impl-push` once changes exist) take over.

## Rules

- Worktree base is the repo's default branch. Epic-base detection is intentionally out of scope.
- Never branch from a dirty working tree on `main`.
- Delegate branch creation to `git-create-branch`; never duplicate that logic.

$ARGUMENTS
