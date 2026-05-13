# Issue lifecycle

GitHub Issues natively expose only `open` and `closed`. The autocode four-state model is not yet overlaid on this repo. Provider mapping below is **planned but deferred**: `state:*` labels will be created when the first SDLC skill that depends on them lands. Until then, treat every open issue as `todo` and rely on PR existence to infer `in-progress` / `in-review`.

## Internal states

- `todo`: work not started.
- `in-progress`: work started; worktree or branch created.
- `in-review`: work done; PR open.
- `done`: PR merged into the relevant target branch.

## Per-issue-kind transitions

| Issue kind | todo -> in-progress | in-progress -> in-review | in-review -> done |
|---|---|---|---|
| Proposal | Worktree / branch created for the proposal document | Proposal document PR opened | Proposal document PR merged |
| Epic | First sub-issue starts | Final epic-level PR opened | Epic-level PR merged |
| Sub-issue | Sub-issue work scheduled on a worktree | Sub-issue PR review created | Sub-issue PR merged into the epic branch |

## Provider mapping

Planned scheme, deferred until an SDLC skill needs it:

| Internal state | Tracker representation |
|---|---|
| todo | `open` + `state:todo` label |
| in-progress | `open` + `state:in-progress` label |
| in-review | `open` + `state:in-review` label |
| done | `closed` (no state label) |

Until the labels are created, derive state from PR existence:

- Issue open, no linked PR: `todo`.
- Issue open, linked PR draft or open: `in-progress` or `in-review` (PR draft status disambiguates).
- Issue closed: `done`.

## Notes

- Sprint membership: only epic tickets are registered to a sprint; sub-issues are excluded. Confirm again when sprint tooling is wired up.
- When the `state:*` labels are created, also add them to the autocode label setup so new repos inherit them.
