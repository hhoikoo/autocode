# CI provider contract

## Purpose

Workflow-run inspection: list PR-level checks, list recent runs for a branch, and dump the failure log for a run. Distinct provider axis from `git-remote`: a repo can use Buildkite or CircleCI on GitHub PRs. `provider.ci` defaults to the `provider.git-remote` value when unset (resolved by `provider/run.sh`). Each `provider/ci/<provider>/` directory implements the scripts below with identical args and stdout shapes. Skills call them via `provider/run.sh ci <feature> [args...]`.

## Cross-provider invariants

- Header: `#!/usr/bin/env bash` then `set -euo pipefail`.
- Required env vars use `:?` guards.
- Stdout: structured JSON via `jq`, or plain text where the script explicitly returns a log dump. Side-effect-only scripts produce no stdout.
- Stderr: human-readable progress. No ANSI colors.
- Exit codes: `0` success, `1` expected failure (bad input, missing resource), `2` unexpected failure (network, crash).
- JSON: `snake_case` keys, `[]` for empty arrays, `""` for empty strings, never `null` (except where the shape explicitly allows it).
- `run-view-failed.sh` is the one exception to the JSON-stdout rule: it emits plain text (the failed log capped at the last 200 lines).

## Shared types

### Run

```json
{
  "databaseId": <integer>,
  "headBranch": "<string>",
  "status": "<string>",
  "conclusion": "<string|empty>",
  "workflowName": "<string>",
  "createdAt": "<iso8601>",
  "url": "<string>"
}
```

### Check

```json
{
  "name": "<string>",
  "status": "<string>",
  "conclusion": "<string|empty>",
  "link": "<string>",
  "workflow": "<string>"
}
```

## Required scripts

| Script | Args | Stdout |
|---|---|---|
| `pr-check-list.sh` | `<pr>` | `Check[]` JSON |
| `run-list.sh` | `--branch <b> [--limit <n>]` | `Run[]` JSON |
| `run-view-failed.sh` | `<run-id>` | failure log, plain text, capped at last 200 lines |

### Notes

- `pr-check-list.sh` returns `[]` when no checks have run.
- `run-list.sh` default limit is `10`. Most-recent first.
- `run-view-failed.sh` returns plain text, not JSON. The cap is 200 lines from the tail of the failed step's log.
- The `provider.ci` setting falls back to `provider.git-remote` when unset; `provider/run.sh` performs the fallback so callers always invoke `provider/run.sh ci <feature>`.

## Adding a new provider

To add a new provider for `ci`:

1. Create `provider/ci/<provider>/`.
2. Implement every script in the Required table with identical args and identical stdout shape.
3. Optional scripts can be deferred until a caller needs them; a skill that calls an optional script must guard with a capability check or fail loudly.
4. Add the provider name to the supported values for `provider.ci` in `autocode/_config/settings-schema.md`.
5. Run `shellcheck` on all new scripts.
