# branch-naming (instructions)

Capture how this repo names branches.

## Inspect

- Examine the names of recent branches in the repo. Check both remote and local refs.
- Look at any existing contributing guide, README, or `.github/` content that mentions branch naming.

## Ask

- Always present the derived branch-naming scheme (pattern, type list, slug rules) to the user and get explicit approval before writing the convention file, even when inspection or the default settled the answer.
- If the inspection turns up two or more incompatible patterns, ask the user which is current and which to discard.
- If the repo has no history (zero branches besides default), ask the user what scheme they want and offer a sensible default.

## Default

`<type>/<issue-id-or-omit>/<short-slug>` where `type` is one of `feat`, `fix`, `docs`, `refactor`, `ci`, `chore`, `release`, `test`, `deps`, `perf`. Use lowercase kebab-case for the slug. Omit `<issue-id>` when there is no tracker issue.

## Output format

```
# Branch naming

<one-paragraph summary of the scheme>

## Pattern

`<the pattern>`

## Examples

- `<example 1>`
- `<example 2>`
- `<example 3>`

## Rules

- <rule 1>
- <rule 2>
```
