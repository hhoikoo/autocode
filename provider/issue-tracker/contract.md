# Issue-tracker provider contract

## Purpose

Tracker-side issue operations: view, create, identity, and future label / comment / transition flows. Each `provider/issue-tracker/<provider>/` directory implements the scripts below with identical args and stdout shapes. Skills call them via `provider/run.sh issue-tracker <feature> [args...]`.

## Cross-provider invariants

- Header: `#!/usr/bin/env bash` then `set -euo pipefail`.
- Required env vars use `:?` guards (e.g. `: "${ISSUE_KEY:?ISSUE_KEY required}"`).
- Stdout: structured JSON via `jq`, or nothing for side-effect-only scripts.
- Stderr: human-readable progress. No ANSI colors.
- Exit codes: `0` success, `1` expected failure (bad input, missing resource), `2` unexpected failure (network, crash).
- JSON: `snake_case` keys, `[]` for empty arrays, `""` for empty strings, never `null` (except where the shape explicitly allows it).
- Idempotency: mutation scripts tolerate re-runs. No duplicate labels, no error when a transition is already applied.
- `status` is the four-state enum below, not the raw provider state. Providers translate to native states (GitHub labels, Jira transitions).
- Issues with no parent emit `"parent": ""`, never `null`.
- Issue key is the provider-native identifier as a string (GitHub issue number, Jira key like `PROJ-123`).

## Shared types

### Issue

```json
{
  "key": "<string>",
  "summary": "<string>",
  "description": "<string>",
  "type": "<string>",
  "status": "todo|in-progress|in-review|done",
  "parent": "<string|empty>"
}
```

### User

```json
{
  "login": "<string>",
  "id": "<string>"
}
```

## Required scripts

| Script | Args | Stdout |
|---|---|---|
| `issue-view.sh` | `<key>` | `Issue` JSON |
| `issue-create.sh` | `<flags>` | created key on a single line |
| `issue-list.sh` | `--label <label> [--state all\|open\|closed]` | `Issue[]` JSON |
| `issue-transition.sh` | `<key> <status>` | none |
| `issue-label-ensure.sh` | `<name> [--color <hex>] [--description <text>]` | none |
| `current-user.sh` | (none) | `User` JSON |

`issue-create.sh` flag set is provider-defined but must accept at minimum a summary (`-s`), an issue type (`-t`), an optional body file (`-b`), zero or more labels (`-l`, repeatable), and an optional parent for sub-issue linking (`-P`). Providers document their own flag surface inside the script.

`issue-list.sh` powers design-epic discovery: list every issue carrying the epic tag in one live call (no search index), then match body markers client-side to resolve units and read their state. It emits the `Issue` shape per row, except `parent` is always `""` (bulk listing does not resolve per-row parents). Default `--state` is `all` so closed (done) issues are included.

`issue-transition.sh` accepts only the four-state enum values (`todo`, `in-progress`, `in-review`, `done`); the provider maps them to native state (GitHub: `autocode:<state>` label for open states, `closed` for done). Idempotent.

`issue-label-ensure.sh` creates or updates a label. Required before creating an issue with a dynamic label (e.g. an epic tag `autocode-epic:<id>`), since GitHub rejects `issue create --label X` when X does not exist. Idempotent.

## Optional scripts

Documented for future implementers. Not yet implemented. A skill that calls an optional script must guard with a capability check or fail loudly.

| Script | Args | Stdout | Needed for |
|---|---|---|---|
| `issue-edit.sh` | `<key> [flags]` | none | editing summary or body post-create |
| `issue-comment-create.sh` | `<key> [--body <text> \| --body-file <path>]` | none | skills that post comments programmatically |
| `issue-comment-edit.sh` | `<comment-id> [--body <text> \| --body-file <path>]` | none | revising prior tracker comments |
| `issue-comment-list.sh` | `<key>` | `Comment[]` JSON | reading tracker-side discussion |
| `issue-label-list.sh` | `<key>` | `string[]` JSON | inspecting current labels |
| `issue-label-add.sh` | `<key> <label>...` | none | applying labels (idempotent) |

`issue-label-add.sh` is idempotent: re-adding an existing label exits `0` with no error.

The `Comment` shape for `issue-comment-list.sh` is provider-defined for now; pin it when the first caller lands.

## Adding a new provider

To add a new provider for `issue-tracker`:

1. Create `provider/issue-tracker/<provider>/`.
2. Implement every script in the Required table with identical args and identical stdout shape.
3. Optional scripts can be deferred until a caller needs them; a skill that calls an optional script must guard with a capability check or fail loudly.
4. Add the provider name to the supported values for `provider.issue-tracker` in `autocode/_config/settings-schema.md`.
5. Run `shellcheck` on all new scripts.
