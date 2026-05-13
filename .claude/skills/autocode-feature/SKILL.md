---
name: autocode-feature
description: Use when adding or modifying any autocode skill, agent, hook, provider script, or convention. Points you at the per-directory CLAUDE.md files and the shim authoring rules.
disable-model-invocation: false
---

# autocode-feature

Before touching anything under `autocode/`, `plugins/autocode/`, `provider/`, or `.claude/`:

1. Run `ls autocode/` and `ls plugins/autocode/` to see what is currently there.
2. Read the root `CLAUDE.md` if you have not in this session. It covers shim+source, voice, single-source-of-truth, bootstrap exceptions, and delegation policy.
3. Read `CLAUDE.md` in every directory along the path of the file you are editing. Nested `CLAUDE.md` files load automatically when you read files in their subtree; treat any missing one as a sign that one needs to be added.
4. Specifically:
   - Adding or changing a skill or agent under `autocode/<feature-set>/`: read `autocode/<feature-set>/CLAUDE.md`. If the feature-set does not exist, create the directory and a one-paragraph `CLAUDE.md` describing its scope.
   - Adding or changing settings or conventions: read `autocode/_config/CLAUDE.md` and `autocode/_config/conventions/CLAUDE.md`.
   - Adding or changing a provider script: read `provider/CLAUDE.md`.
   - Changing how shims are authored or wired in the plugin: stay within the rules below; do not duplicate logic from real files into shims.

## Shim authoring rules (summary)

Every skill and agent has two files:

| Kind | Real definition (body only) | Shim (frontmatter + read line) |
|---|---|---|
| Skill | `autocode/<feature-set>/skills/<name>/SKILL.md` | `plugins/autocode/skills/<name>/SKILL.md` |
| Agent | `autocode/<feature-set>/agents/<name>.md` | `plugins/autocode/agents/<name>.md` |

Frontmatter lives only in the shim. Real files are body-only: no `---` block, no `name`, no `description`, no `model`. Claude Code parses the shim at session start; the real file is loaded via `Read` at invocation time, where YAML frontmatter would just be noise.

The shim contains:

- Frontmatter declaring `name`, `description`, and any optional fields (`model`, `allowed-tools`, `tools`). Verify field names against the official docs (see `claude-code-guide`); do not invent fields.
- For agent shims, include `Read` in the `tools` list so the agent can fetch the real file at invocation time.
- A single body line: `Read through @~/.autocode/autocode/<feature-set>/<...>/<name>.md and execute actions according to the instructions in the file.` Forward `$ARGUMENTS` if the skill accepts arguments.

The real file contains only the body that the model executes: workflow, format, rules, examples. No frontmatter at the top.

Skill and agent names must be unique across feature-sets (the shim layer is flat). The shape check (`scripts/check-plugin-shape.sh`) enforces this, rejects real files that start with `---`, and verifies every shim has exactly one real-file counterpart.

## Bootstrap exceptions

These plugin files do **not** follow shim+source. They ship inline in the plugin tree:

- `plugins/autocode/skills/autocode-setup/`
- `plugins/autocode/skills/autocode-update/`
- `plugins/autocode/hooks/`

Reason: they must run before `~/.autocode/` exists, or they manage `~/.autocode/` themselves. Closed list; do not add to it without strong justification.

## Local-only meta-skills

Skills under `.claude/skills/` are not part of the plugin. Use them for development helpers that should never ship. This skill is an example; so is `/autocode-test`.

## Looking up Claude Code internals

Never guess Claude Code surface details (frontmatter fields, hook events, settings keys, tool names, permission syntax). Use the `claude-code-guide` agent or fetch `https://code.claude.com/docs/en/<page>` directly. See `.claude/rules/claude-code-docs.md`.

## Checklist before opening a PR

- [ ] Real file under `autocode/<feature-set>/...` carries the body only (no `---` frontmatter block). The feature-set has its own `CLAUDE.md`.
- [ ] Skill/agent name is unique across all feature-sets.
- [ ] Shim under `plugins/autocode/...` has the frontmatter (`name`, `description`, plus optional fields) and a single `@~/.autocode/...` read line as the body.
- [ ] Agent shims include `Read` in their `tools` list.
- [ ] No DCI (`` !`command` ``) in skill bodies; provider work goes through `provider/run.sh`.
- [ ] If a new file type is introduced, `.claude/rules/` path globs and `.github/workflows/ci.yml` paths cover it.
- [ ] Any Claude Code field or behavior referenced was confirmed via `claude-code-guide`.
