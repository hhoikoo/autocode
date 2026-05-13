# Branch naming

Branches are named `<type>/<issue-id-or-omit>/<short-slug>`. The pattern is enforced by `.github/workflows/pr-autofix-title.yml`, which derives PR titles from this shape.

## Pattern

`<type>/<issue-number-or-omit>/<short-slug>`

- `type`: one of `feat`, `fix`, `docs`, `refactor`, `ci`, `chore`, `release`, `test`, `deps`, `perf`.
- `issue-number`: the bare numeric GitHub issue ID, no `#`. Omit the segment when there is no tracker issue.
- `short-slug`: lowercase kebab-case description of the change.

## Examples

- `feat/12/clone-step-idempotent`
- `fix/47/clobber-existing-settings`
- `refactor/provider-dispatcher-paths`

## Rules

- Use only lowercase letters, digits, and hyphens in the slug.
- Keep the slug under ~40 characters; longer slugs harm tab completion and PR title legibility.
- When an issue exists, always include the ID. The PR title autofix and issue-link workflows both depend on it.
- Stick to the listed `type` values. The autofix regex rejects anything else and leaves the title unchanged.
