# issue-types (instructions)

Capture what issue categories this repo uses, what each means, and which commit type each maps to.

## Inspect

- Discover the issue categories in use in the target tracker. The tracker may be GitHub, Jira, Linear, or anything else; do not assume a specific tool. Use whatever the project's setup makes available (the configured issue-tracker provider scripts, the repo's `gh` config, the user's knowledge).
- Look at a sample of recent issues to see which categories are actually used vs. which are nominal.
- For each derived issue type, also derive the commit type it maps to (used by `git-create-branch` to pick a branch prefix and by commit-authoring skills). Cross-reference the `commit.md` convention's type list.

## Ask

- Always present the derived issue-type set (names, meanings, provider mapping, commit_type) to the user and get explicit approval before writing the convention file, even when inspection or the default settled the answer.
- If categories are inconsistent (e.g. both `bug` and `defect` labels exist), ask the user which is canonical.
- If the tracker supports issue *types* distinct from labels, ask the user which surface drives behavior.
- Confirm the commit_type mapping for each issue type if the derived value is ambiguous.

## Default

Five types: `epic`, `story`, `task`, `bug`, `proposal`. Each maps to one provider concept (label, issue-type, or whatever the tracker offers). The `proposal` type is registered by the `design-plan` flow for design proposals tracked as their own tickets; its `commit_type` is `docs` so design docs commit as `docs:` rather than `feat:`.

## Output format

```
# Issue types

<one-paragraph summary>

## Types

| Type | Meaning | Provider mapping | commit_type |
|---|---|---|---|
| <type> | <what it captures> | <how the tracker represents it> | <commit type prefix> |

## Selection rules

<when to use which type; e.g. epic vs story boundaries, when to file a proposal>
```
