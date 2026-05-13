---
name: autocode-setup
description: First-time autocode setup in a target repo. Clones autocode to ~/.autocode/, picks the per-repo config dir, writes settings.json and settings.local.json, and scaffolds conventions. Idempotent.
disable-model-invocation: true
user-invocable: true
---

# /autocode-setup

This skill is plugin-native (it bootstraps `~/.autocode/`, so it cannot defer to a file inside `~/.autocode/`). Scripts live next to this `SKILL.md` and are invoked via `${CLAUDE_SKILL_DIR}/scripts/<name>.sh`.

Run each step in order. Each is idempotent: detect prior state, skip or diff, never destroy without explicit user confirmation.

## Step 1: Clone

Run `bash ${CLAUDE_SKILL_DIR}/scripts/clone.sh`.

- Exit `0` with stderr `already-installed`: `~/.autocode/` is already a git checkout. Skip.
- Exit non-zero: surface the stderr message to the user and stop. The most common cause is `~/.autocode/` existing but not being a git checkout; the message will direct the user to delete it and re-run.

## Step 2: Choose the per-repo config directory

Ask the user where to store autocode config for the current repo. Default is `<repo-root>/.autocode/`. Two paths produce different downstream behavior:

- Default (`<repo-root>/.autocode/`): `AUTOCODE_CONFIG_DIR` is written into `.claude/settings.json` (committed). All collaborators on this repo inherit the autocode wiring.
- Any other path: `AUTOCODE_CONFIG_DIR` is written into `.claude/settings.local.json` (uncommitted, per-user).

Once the path is decided, run:

```
bash ${CLAUDE_SKILL_DIR}/scripts/init-config-dir.sh "<chosen-path>"
```

The script creates the directory and writes `AUTOCODE_CONFIG_DIR` into the correct Claude Code settings file under the `env` block (preserving other keys via `jq`). It exits non-zero if the settings file already sets `AUTOCODE_CONFIG_DIR` to a different value; ask the user how to proceed.

## Step 3: Write settings files

Read `~/.autocode/autocode/_config/settings-schema.md` first; it is the source of truth for which keys exist, which namespace each belongs to, and the shared-vs-local split. Each key lands in exactly one file:

- Shared keys (`provider.*`, `workflow.*`) -> `$AUTOCODE_CONFIG_DIR/settings.json` (committed).
- Local keys (`paths.*`) -> `$AUTOCODE_CONFIG_DIR/settings.local.json` (gitignored).

Collect a value for every required key, plus any optional key whose default the user should override. Currently that means asking via `AskUserQuestion`:

- `provider.issue-tracker` (required, shared): default `github`.
- `provider.git-remote` (required, shared): default `github`.
- `provider.ci` (optional, shared): default is the same value as `provider.git-remote`. When the user accepts the default, omit `--ci=` from the script invocation so `provider/run.sh` falls back to `provider.git-remote` at dispatch time.
- `workflow.auto-merge-sub-issues` (shared): leave unset unless the user asks for it.
- `paths.projects-dir` (required, local): default is the parent of the repo root (`dirname "$repo_root"`); surface that default in the prompt. Accept absolute paths or `~/`-prefixed paths; resolve `~` to the user's home before writing.

Build each file's JSON via the helper, one scope at a time:

```
bash ${CLAUDE_SKILL_DIR}/scripts/write-settings.sh --scope=shared \
  --issue-tracker=<value> \
  --git-remote=<value> \
  [--ci=<value>] \
  [--auto-merge-sub-issues=true]

bash ${CLAUDE_SKILL_DIR}/scripts/write-settings.sh --scope=local \
  --projects-dir=<resolved-path>
```

For each invocation, capture stdout and:

1. If the target file (`settings.json` or `settings.local.json`) does not exist, write the captured JSON.
2. If it exists and matches what the script produced, report "<filename> unchanged" and move on.
3. If it exists and differs, show the user a unified diff (old vs new), ask whether to overwrite, and only write on confirmation.

Use the Write tool to persist. The script already pretty-prints with two-space indent.

After writing, ensure `$AUTOCODE_CONFIG_DIR/.gitignore` contains a `settings.local.json` line. Create the file with that single line if missing; if present, append the line only when absent.

## Step 4: Scaffold conventions

Discover the convention instruction files at `~/.autocode/autocode/_config/conventions/*.md` (excluding `CLAUDE.md`). For each one, in order:

1. If `$AUTOCODE_CONFIG_DIR/conventions/<name>.md` already exists, skip and report "already configured".
2. Otherwise, read the instructions in `~/.autocode/autocode/_config/conventions/<name>.md`. Read `~/.autocode/autocode/_config/conventions/CLAUDE.md` once for the authoring rules.
3. Follow the instructions: inspect the repo, ask the user where the instructions say to ask, fall back to the default when neither yields a value.
4. Write the result to `$AUTOCODE_CONFIG_DIR/conventions/<name>.md`.

`mkdir -p "$AUTOCODE_CONFIG_DIR/conventions"` if it does not exist.

## Step 5: Project-level voice import

Ask the user (via `AskUserQuestion`, default yes) whether to import the autocode writing voice into the project's `CLAUDE.md`. Frame: "The voice is applied to the main agent automatically by the plugin, but subagents do not inherit it. Importing it into `CLAUDE.md` propagates the voice to every subagent loading the file." If the user declines, skip this step.

If the user agrees, edit `<repo-root>/CLAUDE.md` to include the voice import.

The block to land is:

```
## Writing voice

@~/.autocode/autocode/_config/output-styles/concise.md

All output must comply with this style.
```

Rules:

- If `CLAUDE.md` does not exist, create it with the block as the only content.
- If the file already contains the import line `@~/.autocode/autocode/_config/output-styles/concise.md` anywhere, report "already configured" and do nothing.
- If the file has an existing `## Writing voice` section that points at a different path, show the user the conflict and ask before changing it.
- Otherwise insert the block at a sensible spot: after any YAML/TOML front-matter and any leading top-level title, before the first content section. Do not blindly prepend if the file opens with a `# Title` heading or front-matter.

Use Read + Edit (or Write for the create-from-scratch case). Do not call out to a script.

## Done

After all five steps, summarize what was written and what was skipped, and tell the user:

- They can run `/autocode-update` periodically to pull the latest autocode and reconcile conventions.
- They can re-run `/autocode-setup` safely; each step skips when already complete.
