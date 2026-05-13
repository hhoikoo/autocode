# commit (instructions)

Capture how this repo writes commits.

## Inspect

- Look at recent commit messages on the default branch. Look at enough to identify a consistent style (subject prefix, scope syntax, casing, line-wrap behavior).
- Look at any commit-message hooks, lint config (`commitlint`, etc.), or contributor docs.

## Ask

- Always present the derived commit style (subject pattern, body rules, examples) to the user and get explicit approval before writing the convention file, even when inspection or the default settled the answer.
- If commit style is inconsistent across recent history, ask the user which way is current.
- If the user wants Conventional Commits but the history does not match, confirm before writing that convention.

## Default

Conventional Commits: `<type>(<scope>): <subject>` where `type` is one of `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`, `deps`, `release`. Subject in imperative mood, lowercase first letter, no trailing period, under 72 chars. Body separated by a blank line, no manual line wrapping.

## Output format

```
# Commit messages

<one-paragraph summary of the style>

## Subject

`<pattern>`

- <constraint 1>
- <constraint 2>

## Body

<rules for the body, including line-wrap behavior, what to include, what to omit>

## Examples

- `<good example 1>`
- `<good example 2>`
```
