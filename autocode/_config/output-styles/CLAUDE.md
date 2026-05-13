# output-styles/

Plugin output styles. Each file here is the canonical source for a Claude Code output style users can select via `/config` -> Output Style.

Real files live here. Two symlinks reference them:

- `plugins/autocode/output-styles/<name>.md` for the plugin's `force-for-plugin` loader.
- `.claude/output-styles/<name>.md` so contributors can select the style during local dev when the plugin is disabled.

The root `CLAUDE.md` also `@`-imports `concise.md` directly from this directory so the writing voice reaches every subagent at session start (the import expands into subagent context; `force-for-plugin` does not).

## Authoring rules

- Frontmatter fields (per Claude Code docs): `name`, `description`, `keep-coding-instructions`, `force-for-plugin`. Verify the current set at `https://code.claude.com/docs/en/output-styles` before adding others.
- Set `keep-coding-instructions: true` unless the style explicitly redefines the assistant's role away from coding. Without it, Claude Code's coding system prompt is dropped and the harness loses guidance for tests, file edits, etc.
- Use `force-for-plugin: true` to apply the style automatically whenever the plugin is enabled. Overrides the user's `outputStyle` setting; if multiple enabled plugins set this, the first one loaded wins.
- ASCII only in style body. Claude reads the style every session, so AI-tell vocabulary inside it shows up in output.

## Adding a new style

1. Drop the real file at `autocode/_config/output-styles/<name>.md`.
2. Create the plugin symlink: `ln -s ../../../autocode/_config/output-styles/<name>.md plugins/autocode/output-styles/<name>.md`.
3. If contributors need to select it manually during dev, create `.claude/output-styles/<name>.md` symlinked the same way (`../../autocode/_config/output-styles/<name>.md`).
4. If the style should be the default voice for all agents in this repo, add an `@`-import line for it to the root `CLAUDE.md`.
