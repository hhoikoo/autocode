# Pull request body

PR descriptions follow the repo's checked-in template. Title and issue linking are handled by GitHub Actions, not by the author.

## Template

Located at `.github/PULL_REQUEST_TEMPLATE.md` in the repo. Refer to it via `@.github/PULL_REQUEST_TEMPLATE.md` when generating a PR body.

Required sections: `## Overview`, `## Problem Statement`, `## Checklist (if applicable)`. Optional sections: `## Architecture` (with a Mermaid diagram when introducing new components), `## Implementation Notes`, `## Migration Guide`, `## Breaking Changes`, `## Testing Notes`.

## Additional conventions not captured by the template

- Title format is auto-derived from the branch by `.github/workflows/pr-autofix-title.yml`. Do not hand-craft the title; name the branch correctly instead.
- Issue link (`resolves #<n>`) is auto-appended by `.github/workflows/pr-issue-link.yml` when the branch encodes an issue ID. Do not duplicate the link manually.
- For Architecture diagrams, prefer Mermaid; render in GitHub's preview before requesting review.
- Keep Problem Statement under four bullets.

## Issue linking

May reference an issue. Required when one exists for the work in flight; encode it in the branch name (`<type>/<n>/<slug>`) and the workflow handles the body. PRs without an associated issue are accepted for trivial chores, docs, and CI tweaks.
