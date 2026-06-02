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
| `issue-epic-list.sh` | `--epic <id> [-g <owner/repo>]` | `Issue[]` JSON |
| `issue-transition.sh` | `<key> <status>` | none |
| `current-user.sh` | (none) | `User` JSON |

`issue-create.sh` flag set is provider-defined but must accept at minimum a summary (`-s`), an issue type (`-t`), an optional body file (`-b`), zero or more labels (`-l`, repeatable), and an optional parent for sub-issue linking (`-P`). Providers document their own flag surface inside the script. The issue `type` (`-t`) is materialized onto the tracker's native typing facility when one exists (GitHub native Issue Type, Jira issue type); a provider with no native typing falls back to a `type:<x>` label.

`issue-epic-list.sh` powers design-epic discovery: given an autocode epic `<id>`, return that epic's issue plus every unit sub-issue (`Issue[]`), in one live call (no search index). The caller matches body markers client-side (`autocode:epic=<id>`, `autocode:unit=<id>/<slug>`) to assign roles and read each unit's state. Each provider resolves the set natively: GitHub finds the epic by its body marker and reads units from the sub-issue relationship (no per-epic label); a provider without a native parent/child relationship may instead carry an `autocode-epic:<id>` label on every issue of the epic and list by it. Unit rows carry `parent` = the epic key; the epic row carries `parent: ""`. Default state is `all`, so a closed (done) epic or unit is included.

`issue-transition.sh` accepts only the four-state enum values (`todo`, `in-progress`, `in-review`, `done`); the provider maps them to native state (GitHub: `autocode:in-progress` / `autocode:in-review` label for those two states, `todo` is open with no state label, `closed` for done). Idempotent.

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
