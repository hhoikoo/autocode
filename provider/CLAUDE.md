# provider/

Provider scripts wrap external systems (issue trackers, CI runners, anything provider-specific) behind a stable contract. Skills **never** call a provider script directly: they call `provider/run.sh <provider-type> <feature> [args...]`, which picks the right provider for the current repo by reading `$AUTOCODE_CONFIG_DIR/settings.json`.

## Directory shape

```
provider/
  run.sh                                      # dispatcher
  <provider-type>/<provider>/<feature>.sh     # provider script
```

- `<provider-type>`: the capability category. Current types: `issue-tracker`, `git-remote`, `ci`.
- `<provider>`: the concrete vendor, e.g. `github`, `jira`, `linear`.
- `<feature>`: a noun-verb (or noun-verb-modifier) action, e.g. `issue-create`, `pr-body-edit`, `run-view-failed`.

## Script contract

Every provider script:

- Starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Reads inputs from environment variables (preferred for structured fields) or positional arguments. Both are passed through `run.sh` unmodified.
- Required env vars use `:?` guards: `: "${ISSUE_NUMBER:?ISSUE_NUMBER required}"`.
- Emits structured output on stdout as JSON via `jq`. Side-effect-only scripts (no data return) may produce no stdout.
- Emits human-readable progress on stderr. No ANSI / colors.
- Exits `0` on success, `1` on expected failure (bad input, missing resource), `2` on unexpected failure (network, crash).

Provider scripts may shell out to the provider's CLI (`gh`, `jira`, etc.). Document any additional CLI dependency at the top of the script.

## Adding a new provider

1. Create the directory `provider/<provider-type>/<provider>/`.
2. Implement each `<feature>.sh` the skills in the repo need. The list of required features is implicit: the union of features called via `provider/run.sh <provider-type> <feature>` across all skills.
3. Add the provider name to the valid values for `provider.<provider-type>` in `autocode/_config/settings-schema.md`.
4. Run `shellcheck` on all new scripts.

## Dispatcher behavior (`run.sh`)

`run.sh <provider-type> <feature> [args...]`:

1. Errors if `AUTOCODE_CONFIG_DIR` is unset.
2. Errors if `$AUTOCODE_CONFIG_DIR/settings.json` is missing or invalid JSON.
3. Reads `.provider.<provider-type>` from `settings.json` via `jq`. When `<provider-type>` is `ci` and the value is missing or empty, falls back to `.provider.git-remote` (CI typically lives with the git remote). Errors if neither yields a value.
4. Resolves `~/.autocode/provider/<provider-type>/<provider>/<feature>.sh`. Errors if missing.
5. `exec`s the script with remaining args, inheriting the environment.
