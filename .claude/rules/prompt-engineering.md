---
paths:
  - ".claude/**/*.md"
  - ".claude/**/*.json"
  - "autocode/**/*.md"
---
# Prompt engineering conventions

For agent, skill, and hook authoring under `.claude/` and `autocode/`. Frontmatter fields, hook events, and other Claude Code surface details change over time. Look them up in the official docs (see `.claude/rules/claude-code-docs.md`) rather than relying on a static catalog.

## File layout

| Type | Real definition | Shim (plugin) |
|------|-----------------|---------------|
| Skill | `autocode/<feature-set>/skills/<name>/SKILL.md` | `plugins/autocode/skills/<name>/SKILL.md` |
| Agent | `autocode/<feature-set>/agents/<name>.md` | `plugins/autocode/agents/<name>.md` |
| Local-only skill | `.claude/skills/<name>/SKILL.md` | (none) |
| Local-only agent | `.claude/agents/<name>.md` | (none) |
| Hooks | `.claude/settings.json` (repo-local dev hooks; currently none) | `plugins/autocode/hooks/hooks.json` |

Real definitions are grouped under a feature-set directory (`_config`, `design`, `git`, `impl`, `issue`, `pr`, `util`; see each `autocode/*/CLAUDE.md`). Shims under `plugins/autocode/` are flat (the plugin manifest has no feature-set concept), so skill/agent names must be unique across all feature-sets.

Frontmatter lives only in the shim. Real files at `autocode/<feature-set>/...` are body-only: no `---` block, no `name`, no `description`, no `model`. The shim carries the frontmatter Claude Code parses at session start plus a one-line body instructing the model to read the real file at `@~/.autocode/autocode/<feature-set>/<path>`. The shape check in `scripts/check-plugin-shape.sh` rejects real files that start with `---`. At install time `/autocode-setup` clones this repo to `~/.autocode/`; during development a symlink there is sufficient.

## Quality rules

- No hallucinated tools. Every tool referenced in an agent or skill must actually exist.
- No invented frontmatter fields. Verify against the official docs before adding one.
- No conflicting instructions across files. If two disagree, the more specific wins (skill > agent > rule).
- Prompts are code. Review with the same rigor as source: test, version, diff.
- For Claude Code features (frontmatter fields, tool names, hook events, etc.), use the `claude-code-guide` subagent.
- Real agent files (`autocode/<feature-set>/agents/<name>.md` and `.claude/agents/<name>.md`) must open with a line instructing the agent to read `~/.autocode/autocode/_config/output-styles/concise.md`. Subagents do not inherit the plugin's `force-for-plugin` output style, and the root CLAUDE.md `@`-import only reaches them when this repo is the project. The per-agent read line enforces the voice when the agent runs in another repo.
