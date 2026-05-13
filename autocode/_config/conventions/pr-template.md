# pr-template (instructions)

Capture how this repo structures pull request descriptions.

## Inspect

- Look for `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, or templates under `.github/PULL_REQUEST_TEMPLATE/`.
- Look at recent merged PRs' descriptions to confirm the template is followed, and to spot conventions the template does not capture (e.g. always including a test plan, always linking an issue).

## Ask

- Always present the derived PR-body conventions (which template to reference, additional rules, issue-linking policy) to the user and get explicit approval before writing the convention file, even when inspection or the default settled the answer.
- If a template exists, confirm it is current and ask what is regularly added that the template misses.
- If no template exists, ask the user what sections they want.

## Default

A Summary section (1-3 bullets focused on the why) followed by a Test plan section (a markdown checklist of testing steps).

## Output format

This convention file should reference the repo's actual template rather than duplicate it. The output:

```
# Pull request body

<one-paragraph summary of how PR bodies are structured in this repo>

## Template

Located at `<path>` in the repo. Refer to it via `@<path>` when generating a PR body.

## Additional conventions not captured by the template

- <convention 1>
- <convention 2>

## Issue linking

<rule: must reference an issue / may reference an issue / etc.>
```
