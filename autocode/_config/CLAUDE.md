# _config/

Source of truth for everything `/autocode-setup` writes into a target repo and what `/autocode-update` reconciles, plus shared assets the plugin tree references via symlink.

- `settings-schema.md` documents every key that may appear in `$AUTOCODE_CONFIG_DIR/settings.json` or `$AUTOCODE_CONFIG_DIR/settings.local.json`, plus the scope rule that decides which file each key lands in. Adding a new setting starts here.
- `conventions/` holds one file per convention. Each file is instructions to Claude on how to create that convention file for a target repo, not template content. The conventions in this folder are exactly what the setup skill scaffolds; adding or removing files here changes what new repos get and what `/autocode-update` checks for.
- `output-styles/` holds plugin output styles (e.g. `concise.md`). Real files live here; `plugins/autocode/output-styles/<name>.md` is a symlink. The same files are referenced by the root `CLAUDE.md` via `@~/.autocode/autocode/_config/output-styles/<name>.md` to propagate the voice to subagents.

When adding a setting: pick a top-level namespace (this decides shared vs local scope), add a row to the matching table in `settings-schema.md`, update the relevant convention instructions if the setting interacts with a convention, and add the prompt to `plugins/autocode/skills/autocode-setup/SKILL.md` so the setup flow collects a value for it. If the namespace is new, update `plugins/autocode/skills/autocode-setup/scripts/write-settings.sh` to emit it under the correct `--scope`.

When adding a convention: drop a new instruction file in `conventions/`. The setup skill iterates the folder, so no manifest edit is needed.

When adding an output style: drop the real file under `output-styles/` and create a symlink at `plugins/autocode/output-styles/<name>.md` pointing to it. See `autocode/_config/output-styles/CLAUDE.md` for authoring rules.
