# Issue ID

GitHub Issues numeric IDs. The bare number is the canonical identifier; the `#` prefix is presentation. `.github/workflows/pr-issue-link.yml` and `.github/workflows/pr-autofix-title.yml` both depend on these positions.

## Format

`#<n>` in human-readable contexts (PR bodies, commits). Bare `<n>` in machine-readable positions (branch segment).

## Where it appears

- Branch name: position 2 of `<type>/<n>/<slug>`, bare number, optional.
- PR title: `(#<n>)` scope, e.g. `feat(#12): Subject`. Auto-derived from the branch by the title autofix workflow.
- PR body: `resolves #<n>` trailer, auto-appended by the issue-link workflow when the branch encodes an ID.
- Commit subject: `(#<n>)` scope, same shape as the PR title.

## Extraction rules

Given a branch `feat/12/clone-step-idempotent`:

- Split on `/`. If the second segment is purely numeric, it is the issue ID.
- If the second segment is non-numeric (e.g. `feat/clone-step-idempotent`), there is no associated issue.

Given a PR title `feat(#12): Add clone-step idempotency check`:

- Match `\((#?\d+)\)` after the type. Capture digits; the `#` is optional in the regex but conventional in writing.

Given a commit subject: same rule as PR title.

Given a PR body: the `resolves #<n>` (or `closes #<n>`, `fixes #<n>`) trailer is authoritative for the issue this PR closes.

## Edge cases

- **No associated issue**: omit the segment in the branch (`feat/clone-step-idempotent`) and the scope in the title (`feat: Subject`). The autofix workflow handles this branch without falling over.
- **Multiple issues**: only one ID encoded in the branch and title. Reference additional issues in the PR body with `refs #<n>` (not `resolves`, which closes them on merge).
- **Draft PRs**: same rules; the issue-link workflow runs on `opened` regardless of draft state.
- **Cross-repo references**: out of scope here; not currently supported by the autofix tooling.
