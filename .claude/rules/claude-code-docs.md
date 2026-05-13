---
paths:
  - ".claude/**"
  - "CLAUDE.md"
  - "**/CLAUDE.md"
  - "autocode/**/*.md"
---
# Claude Code documentation

Never guess Claude Code surface details (frontmatter fields, hook events, settings keys, tool names, permission syntax). They change between releases. Look them up.

## How to look up

1. **`claude-code-guide` subagent** (via `Task`): preferred for specific questions. It has docs access and can answer authoritatively.
2. **`WebFetch` directly** against `https://code.claude.com/docs/en/<page>`. Common pages:
   - `skills`, `sub-agents`, `hooks`, `mcp`, `plugins`: per-feature reference.
   - `memory`: CLAUDE.md, MEMORY.md, modular rules, path frontmatter.
   - `settings`, `permissions`: config files and rule syntax.
   - `cli-reference`, `interactive-mode`: CLI flags and slash commands.
   - `best-practices`, `common-workflows`, `features-overview`: guidance.
3. **`WebSearch`** with `site:code.claude.com/docs/en/` for anything not above.

The fetched page is the source of truth. Don't paraphrase from training data.
