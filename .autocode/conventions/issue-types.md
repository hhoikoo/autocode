# Issue types

Four issue types prefixed with `issue:`. Each is a GitHub label; the label is the canonical surface (the repo does not use GitHub's native issue-type beta). Stock labels (`bug`, `enhancement`, `documentation`, ...) have been removed in favor of this set.

## Types

| Type | Meaning | Provider mapping |
|---|---|---|
| `epic` | Large, multi-PR initiative grouping related sub-issues. Tracks the umbrella outcome, not a single deliverable. | GitHub label `issue:epic` |
| `story` | User-facing feature or capability deliverable in one PR. Has acceptance criteria. | GitHub label `issue:story` |
| `task` | Concrete unit of work, typically a sub-issue of an epic or story. Implementation-level. | GitHub label `issue:task` |
| `bug` | Defect or regression to fix. | GitHub label `issue:bug` |

## Selection rules

- If the work spans more than one PR or coordinates several contributors, it is an `epic`.
- If the work is a single PR delivering visible behavior to a user (CLI flag, skill, agent, workflow step), it is a `story`.
- If the work is a single PR implementing a piece of an epic or story without standalone user value, it is a `task`.
- If the work fixes broken behavior or a regression, it is a `bug` regardless of size.
- Exactly one `issue:*` label per issue. Multiple `issue:*` labels indicate the issue needs to be split.
