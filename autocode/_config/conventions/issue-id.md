# issue-id (instructions)

Capture how issue IDs are written and how to extract them from context (branch names, PR titles, commit subjects).

## Why this matters

Skills regularly need to find the issue ID for the work in flight. Without a clear convention they guess from branch names or PR bodies and get it wrong. This file pins down the answer.

## Inspect

- Look at recent branch names: do they encode an issue ID? In what position? What numeric or alphanumeric format?
- Look at recent commits and PR titles for issue references.
- Look at the issue-tracker provider: do issue IDs have a project prefix (e.g. `PROJ-123`)? Are they pure numbers (e.g. GitHub's `#123`)?

## Ask

- Always present the derived ID format and the positions in which it appears (branch, PR title, PR body, commit subject) to the user and get explicit approval before writing the convention file, even when inspection or the default settled the answer.
- If multiple ID styles appear in history (e.g. both `PROJ-123` and `#456`), ask the user which is the autocode-driving ID.
- If the repo uses one tracker but PRs sometimes reference another, ask the user which to treat as authoritative.

## Default

GitHub Issues numeric IDs. Reference as `#<n>` in PR bodies. Encode in branch names at position 2 of `type/<id>/slug`.

## Output format

```
# Issue ID

<one-paragraph summary>

## Format

`<format>` (e.g. `#<n>` or `PROJ-<n>`)

## Where it appears

- Branch name: <pattern, with the ID's position>
- PR title: <pattern, or "not required">
- PR body: <pattern, or "not required">
- Commit subject: <pattern, or "not required">

## Extraction rules

<how a skill should derive the issue ID from a given branch / PR / commit, with examples>

## Edge cases

<rules for: no associated issue, multiple issues, draft PRs, etc.>
```
