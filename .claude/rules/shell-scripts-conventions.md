---
paths:
  - "**/*.sh"
---
# Shell script conventions

## Header

```bash
#!/usr/bin/env bash
set -euo pipefail
```

## I/O contract

- Inputs: env vars with `:?` guards for required values (`${GITHUB_TOKEN:?}`).
- Stdout: structured JSON via `jq`. Side-effect-only scripts (no data output) are exempt.
- Stderr: human-readable diagnostics and progress.
- Exit codes: `0` success, `1` expected failure (bad input, missing resource), `2` unexpected failure (network, crash).

## Behavior

- Idempotent. Running twice with the same inputs produces the same result.
- No interactive prompts; scripts run unattended.
- No color codes or ANSI escapes (output is machine-consumed).

## Naming

- Format: `<verb>-<noun>.sh` (`create-branch.sh`, `list-issues.sh`).
- Group by domain (e.g. `autocode/scripts/`, `autocode/provider/<type>/<provider>/`) or by skill (`autocode/skills/<skill>/scripts/`).

## Security

- Never log secrets or tokens.
- Validate external input (env vars, API responses) before using in commands.
- Quote variable expansions: `"${var}"`, not `$var`.

## Dependencies

Assumed: `jq`, `curl`, `git`, `gh`. Document anything else at the top of the script.

## Linting

All scripts pass `shellcheck`. Suppression directives need an explanation comment on the line above (shellcheck doesn't support inline comments after `--`):

```bash
# word splitting is intentional here
# shellcheck disable=SC2086
```
