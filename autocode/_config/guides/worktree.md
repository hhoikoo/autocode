# Worktree procedure

Canonical procedure for isolating repo changes in a git worktree. Any skill that
writes files into the repo or creates branches/commits ensures it is in a worktree
first, rather than mutating the working tree on the default branch. Skills
`@`-import this file instead of restating the steps.

The base for every worktree is the repo's default branch.

## Enter

Idempotent. Run before the first repo write.

1. `git rev-parse --abbrev-ref HEAD`. If already off the default branch (already in
   a worktree or feature branch), do nothing and proceed.
2. On the default branch, create the worktree:
   - Preferred: `EnterWorktree`. It creates a worktree under `.claude/worktrees/`
     off the default-branch base and switches the session cwd into it.
   - Fallback when the `EnterWorktree` tool is unavailable (degraded mode):
     `git fetch origin <default-branch>` then
     `git worktree add .claude/worktrees/<branch-slug> origin/<default-branch>`.
     The session cwd does NOT switch automatically: run later git operations with
     `git -C <path>` and write files under `<path>`.
3. Delegate to `git-create-branch` for the properly-named branch (inside the
   worktree). `EnterWorktree` leaves an auto-named branch; `git-create-branch` is
   what names it per the branch-naming convention.

## Teardown

Same-session best-effort. There is no cross-session pruning.

- Preferred: `ExitWorktree`.
  - `action: keep` while a PR is open: the work must survive for review and merge.
  - `action: remove` only for abandoned or discardable work, or a change that
    merged within this same session. `ExitWorktree` removes only worktrees it
    created this session.
- Fallback when `ExitWorktree` is unavailable: `git worktree remove <path>`. It
  refuses on uncommitted or unmerged work unless `--force`; confirm with the user
  before forcing.
- Cross-session: a worktree whose PR merges in a later session is not pruned
  automatically by same-session teardown. General skills leave it to the
  session-exit keep/remove prompt or a manual `git worktree remove`.
  Exception: the `impl` epic orchestrator tracks its worktrees via tracker
  reconciliation each turn, so pruning a merged unit's worktree is safe there and
  in scope. It uses `git worktree remove <path>` for a worktree it did not create
  this session (see `impl` `### Worktree pruning`).
