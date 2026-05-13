# reviewers (instructions)

Capture the list of GitHub logins eligible to be auto-requested as reviewers, plus any explicit exclusions.

## Inspect

- Examine recent merged PRs to see who actually reviewed (approvers, commenters with substantive review activity). Weight recency.
- Look for a `CODEOWNERS` file (root, `.github/`, or `docs/`).
- Identify active maintainers from recent commit activity on the default branch.
- Cross-reference against the repo's contributor list to filter out drive-by contributors.

## Ask

- Always present the derived reviewer list (and any candidates for exclusion) to the user and get explicit approval before writing the convention file, even when inspection or the default settled the answer.
- Ask whether anyone in the candidate list should be excluded (people who should never be auto-requested: alumni, bots, the user themselves).
- Ask whether `CODEOWNERS` already covers the review-routing needs, in which case this file may stay empty.

## Default

Empty list. The user opts in by adding lines; an empty file means autocode does not auto-request reviewers.

## Output format

One GitHub login per line. Lines prefixed with `!` are exclusions (never auto-request). Blank lines and lines beginning with `#` are ignored.

```
# Reviewers

# Default reviewers (auto-requested on PR open)
alice
bob
carol

# Exclusions
!dave
```
