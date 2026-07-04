# autocode

A Claude Code plugin: opinionated skills, subagents, hooks, and provider scripts for everyday coding work (issues, branches, PRs, reviews).

## Writing voice

@~/.autocode/autocode/_config/output-styles/concise.md

All output must comply with this style.

## Delegation policy

**STRICT.** If a skill or agent exists for the task, delegate. Never inline. Don't approximate conventions from memory.

## Feature development

For any new skill, agent, hook, provider script, or convention: load `/autocode-feature` first.

## Discovery

Each directory documents itself via its own `CLAUDE.md`. Keep details next to the code.

| What you need | Where to look |
|---|---|
| Coding rules (path-scoped) | `.claude/rules/` |
| What a feature-set contains | `autocode/<feature-set>/CLAUDE.md` |
| Settings schema, conventions, output styles | `autocode/_config/CLAUDE.md` |
| Provider dispatcher, provider authoring | `provider/CLAUDE.md` |
| Local-only meta-skills | `.claude/skills/` |
| This repo's own runtime instance (dogfood) | `.autocode/`: convention instances derived from `autocode/_config/conventions/`, shared `settings.json`, and `archive/` of completed design epics |
| Plugin manifest | `plugins/autocode/.claude-plugin/plugin.json` |
| Marketplace entry | `.claude-plugin/marketplace.json` |
| CI pipeline | `.github/workflows/*.yml` |
| Repo-init entry point | `Makefile` (`make init`) |

## Verify before assuming

Don't guess from training data when a source exists.

- **Library APIs, tool flags**: read source or docs.
- **Claude Code internals**: `claude-code-guide` agent or `https://code.claude.com/docs/en/`. See `.claude/rules/claude-code-docs.md`.
- **Versions, config values**: read the canonical file; never hardcode.
- **External projects**: web-search or `gh` first.

## Single source of truth

Reference the canonical source at runtime. Don't duplicate structure: two files that must stay in sync will diverge. (Code duplication is a judgment call.)

| What | Canonical location |
|---|---|
| Issue tracking | GitHub Issues |
| PR structure | `.github/PULL_REQUEST_TEMPLATE.md` |
| Labels | GitHub (managed via `gh label`) |
| Skill / agent definitions | `autocode/<feature-set>/skills/<name>/`, `autocode/<feature-set>/agents/<name>.md` |
| Provider scripts | `provider/<provider-type>/<provider>/<feature>.sh` |
| Plugin shims | `plugins/autocode/...` (point at canonical via `@~/.autocode/...`) |
| Settings schema | `autocode/_config/settings-schema.md` |
| Per-convention instructions | `autocode/_config/conventions/<name>.md` |
| Output styles | `autocode/_config/output-styles/<name>.md` (plugin path is a symlink) |
| Plugin version | `plugins/autocode/.claude-plugin/plugin.json` (`version`) |
| CI pipeline | `.github/workflows/*.yml` |

Anti-patterns: shims that restate the real definition; agents that copy a skill's workflow instead of invoking the skill; local config that duplicates a definition (derived convention instances under `$AUTOCODE_CONFIG_DIR` / `.autocode/` are expected outputs of `autocode/_config/conventions/`, not duplication).

## Plugin layout

`plugins/autocode/` is a shim over real definitions under `autocode/<feature-set>/`. Shims are flat (the plugin manifest has no feature-set concept); skill and agent names must be globally unique.

Frontmatter lives only in the shim (Claude Code parses it at session start). The real file is body-only, loaded via `Read` at invocation. One source for metadata, no parity drift.

`/autocode-setup` clones this repo to `~/.autocode/`. Shims reference real files via `@~/.autocode/<path-in-repo>`; env vars do not expand in `@`-references.

```
autocode/<feature-set>/skills/<name>/SKILL.md   # real skill, body only (no frontmatter)
autocode/<feature-set>/agents/<name>.md         # real agent, body only (no frontmatter)
plugins/autocode/skills/<name>/SKILL.md         # shim: frontmatter + @~/.autocode/... read line
plugins/autocode/agents/<name>.md               # shim
provider/<provider-type>/<provider>/<feature>.sh  # provider scripts; called via provider/run.sh
```

## Bootstrap exceptions

Three plugin files ship inline (not as shims) because they run before `~/.autocode/` exists or manage it themselves:

- `plugins/autocode/skills/autocode-setup/`: clones `~/.autocode/`.
- `plugins/autocode/skills/autocode-update/`: pulls into `~/.autocode/`.
- `plugins/autocode/hooks/check-install.sh`: runs on every `SessionStart`, including before setup.

`scripts/check-plugin-shape.sh` allowlists them.
