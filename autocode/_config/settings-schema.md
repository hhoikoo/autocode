# settings schema

Per-repo autocode settings live in two files under `$AUTOCODE_CONFIG_DIR/`:

- `settings.json` (committed): keys shared across collaborators on this repo.
- `settings.local.json` (gitignored): keys specific to one user's machine.

Each key has exactly one home. No merging, no precedence rules. Scope is determined by top-level namespace:

| Namespace | Scope | File |
|---|---|---|
| `provider.*`, `workflow.*` | shared | `settings.json` |
| `paths.*` | local | `settings.local.json` |

`/autocode-setup` writes `AUTOCODE_CONFIG_DIR` into a Claude Code settings file (`.claude/settings.json` for the in-repo default, `.claude/settings.local.json` otherwise) so readers can locate the config dir from any session.

## Shared keys (`settings.json`)

| Key | Type | Default | Description |
|---|---|---|---|
| `provider.issue-tracker` | string | (required) | Which issue-tracker provider scripts to dispatch to. Resolved by `provider/run.sh` as `provider/issue-tracker/<value>/<feature>.sh`. Supported values: `github`. |
| `provider.git-remote` | string | (required) | Which git-remote provider scripts to dispatch to. Resolved by `provider/run.sh` as `provider/git-remote/<value>/<feature>.sh`. Supported values: `github`. |
| `provider.ci` | string | value of `provider.git-remote` | Which ci provider scripts to dispatch to. Resolved by `provider/run.sh` as `provider/ci/<value>/<feature>.sh`. When unset or empty, the dispatcher falls back to `provider.git-remote`. Supported values: `github`. |
| `workflow.auto-merge-sub-issues` | bool | `false` | If true, sub-issue PRs auto-merge once required checks pass. Honored by workflow-phase skills (when they land). |

## Local keys (`settings.local.json`)

| Key | Type | Default | Description |
|---|---|---|---|
| `paths.projects-dir` | string | parent of repo root | Filesystem dir holding sibling projects. Used by `codebase-researcher` to resolve project-name args to absolute paths. Set by `/autocode-setup`. |

## Authoring rules

- Keys are kebab-case for multi-word leaves, dot-namespaced into groups.
- Strings are lowercase identifiers (`github`, not `GitHub`) so provider directory lookups are case-sensitive-stable.
- Scope is decided by top-level namespace. `paths.*` is local; everything else is shared. Adding a new top-level namespace requires picking its scope here and updating `plugins/autocode/skills/autocode-setup/scripts/write-settings.sh` to emit it into the right file.
- Path values are allowed only under `paths.*` and only when they point at directories of *other* projects (sibling repos the agent operates on). Paths to autocode's own state belong in env vars (`AUTOCODE_CONFIG_DIR`, set by Claude Code settings), not here.
- No secrets. Secrets are pulled by provider scripts from their own canonical source (e.g. `gh auth token`, env vars set outside this file).

## Validation

`provider/run.sh` reads only shared keys, so it exits non-zero with a clear message when:

- `AUTOCODE_CONFIG_DIR` is unset.
- `$AUTOCODE_CONFIG_DIR/settings.json` does not exist or is not valid JSON.
- The requested `provider.<provider-type>` key is missing.
- The resolved provider script does not exist on disk.

Readers of local keys (e.g. `codebase-researcher`) read `$AUTOCODE_CONFIG_DIR/settings.local.json`. Missing file or missing key is the reader's contract to handle (typically: fall back to a default or error with the key name).
