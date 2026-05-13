# issue-lifecycle (instructions)

Capture how issues transition through states, including how autocode's internal state model maps to the target tracker.

## Autocode internal states

Autocode reasons about issues using four states, regardless of provider:

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

## Inspect

- Look at how issues currently progress in the target tracker. What columns or statuses exist? Which trigger automation?
- For GitHub Issues: only `open` and `closed` exist natively; the four-state model is overlaid via labels or a project board.
- For Jira: there is usually a workflow with named states; map them onto the four internal states.

## Ask

- Always present the derived provider mapping (how each of the four internal states is represented in the tracker) to the user and get explicit approval before writing the convention file, even when inspection or the default settled the answer.
- Ask the user to confirm or override the provider mapping for each of the four internal states.
- Ask whether epic tickets should be the only ones registered to a sprint (sub-issues excluded, as in the design notes).

## Default

- GitHub: `todo`, `in-progress`, `in-review` all map to `open` with an `autocode:<state>` label distinguishing them; `done` maps to `closed`.
- Jira: 1-to-1 mapping with `To Do`, `In Progress`, `In Review`, `Done`.

## Output format

```
# Issue lifecycle

<one-paragraph summary of how state is tracked>

## Internal states

(repeat the four-state model so skills can @-import this file standalone)

## Per-issue-kind transitions

| Issue kind | todo -> in-progress | in-progress -> in-review | in-review -> done |
|---|---|---|---|
| ... | ... | ... | ... |

## Provider mapping

| Internal state | Tracker representation |
|---|---|
| todo | <how this repo's tracker represents todo> |
| ... | ... |

## Notes

<anything non-obvious, e.g. sprint membership rules>
```
