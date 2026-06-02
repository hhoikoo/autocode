---
name: autocode-update
description: Pull the latest autocode and reconcile per-repo settings and conventions. Refuses to run when ~/.autocode/ is on a non-main branch.
disable-model-invocation: true
user-invocable: true
argument-hint: "[--force]"
---

# /autocode-update

Plugin-native, like `/autocode-setup`: this skill manages `~/.autocode/` itself.

## Step 1: Pull and reconcile

Run `bash ${CLAUDE_SKILL_DIR}/scripts/update.sh`.

Behavior:

- If `~/.autocode/` is not a git checkout: error. Tell the user to run `/autocode-setup`.
- If `~/.autocode/` is not on the `main` branch: error. Tell the user this looks like a `/autocode-test` checkout and they should `git -C ~/.autocode switch main` first.
- If after fetching, local `main` is no longer an ancestor of `origin/main` (force-push or unrelated-roots case): the script exits with an `ahead/behind` count and a suggested `git -C ~/.autocode reset --hard origin/main` recovery command. `~/.autocode/` is a managed checkout; local commits are never expected. Do not narrate the divergence, speculate about its cause, inspect the local commits, or propose merge/rebase alternatives. Call `AskUserQuestion` immediately with exactly two options:
  - `Discard local and reset to origin/main` (recommended; the default for this managed checkout)
  - `Abort`

  If the user picks discard, run `git -C ~/.autocode reset --hard origin/main` and re-invoke the script. If they pick abort, stop. If the script reported a dirty working tree, surface that line verbatim and abort. Do not offer the reset until the user clears the dirt.
- Otherwise: `git pull --ff-only origin main`. Updates `~/.autocode/.last-fetch`.

The script exits non-zero on any failure; surface its stderr to the user verbatim.

## Step 1b: Plugin staleness check

The pull refreshes `~/.autocode/` only. This skill, all skill/agent frontmatter, and the inline bootstrap files (`autocode-setup`, `autocode-update` itself, the hooks) are served from the installed plugin, which updates through Claude Code's plugin channel, not this pull. So an updated `/autocode-update` description, or any other frontmatter change, now sits in the freshly-pulled `~/.autocode/` but not in the running plugin.

Detect that drift:

```
bash ${CLAUDE_SKILL_DIR}/scripts/check-plugin-drift.sh
```

It compares the installed plugin's `skills/`, `agents/`, and `hooks/` against `~/.autocode/plugins/autocode/` and prints `{"stale": <bool>, "files": [...]}`.

- `stale: false`: nothing to do.
- `stale: true`: the installed plugin is behind the pulled checkout (this includes `/autocode-update`'s own description). Name the differing files and tell the user to update the plugin through Claude Code's plugin manager, then restart the session for the changes to load. Re-reading the new body in this run does not help: the running skill and all frontmatter were parsed at session start, so the update only takes effect next session.

## Step 2: Reconcile settings

After the pull succeeds, read `~/.autocode/autocode/_config/settings-schema.md`. It declares which top-level namespaces are shared (`provider.*`, `workflow.*` -> `settings.json`) and which are local (`paths.*` -> `settings.local.json`), plus which keys are required.

Check each file under `$AUTOCODE_CONFIG_DIR/`:

1. **Required-key drift.** For every key the schema marks required, verify it exists in the file matching its scope. Report any missing required key. Offer to scaffold it now using the same prompt logic as `/autocode-setup` step 3 (ask the user, then call `write-settings.sh --scope=<scope>` and merge into the existing file via `jq` rather than overwriting).
2. **Scope migration.** Read both files; for any key whose namespace does not match the file it sits in (e.g. a `paths.*` key found in `settings.json`, or a `provider.*` key found in `settings.local.json`), move it to the correct file. Report each move. Use `jq` to delete from the wrong file and add to the right one in one pass; never lose values.
3. **Gitignore.** Verify two ignore rules, each idempotent (append the line if missing). Report only when changed.
   - `settings.local.json` in `$AUTOCODE_CONFIG_DIR/.gitignore`.
   - the transient impl state files (`.impl-context`, `.progress-last-sha`; canonical list in the design-folder spec) in `<repo-root>/.autocode/.gitignore`. Default config dir: same file. Relocated: reconcile only if `<repo-root>/.autocode/` exists; the `impl-start` backstop covers the not-yet-created case.

If `settings.local.json` does not exist and no local keys are required, leave it absent (a fresh repo with no local wiring is valid).

## Step 3: Reconcile conventions

List `~/.autocode/autocode/_config/conventions/*.md` (excluding `CLAUDE.md`). For each:

- If `$AUTOCODE_CONFIG_DIR/conventions/<name>.md` exists: report "present".
- Else: report "missing" and offer to scaffold it now using the same logic as `/autocode-setup` step 4 (read the instructions in `~/.autocode/autocode/_config/conventions/<name>.md`, inspect/ask/default, write the file).

## Step 4: `--force` content reconciliation

If the user passed `--force`, also re-read each existing convention file and check whether its content still matches the (possibly updated) instructions in `~/.autocode/autocode/_config/conventions/<name>.md`.

For each existing convention file:

1. Read the user's `$AUTOCODE_CONFIG_DIR/conventions/<name>.md`.
2. Read the shipped instructions `~/.autocode/autocode/_config/conventions/<name>.md`.
3. Decide whether the user's file still satisfies the instructions (correct sections, plausible content, no obviously stale references).
4. If it looks misaligned, report it with a one-sentence reason. **Do not edit anything automatically.** To reconcile content, the user re-runs `/autocode-setup` for that convention after deleting their file.

## Done

One terse line: commits pulled, plugin staleness flagged, settings keys migrated/scaffolded, conventions missing/scaffolded, drift flagged. Skip the "next run" note; the `SessionStart` hook handles nudging. No narration of skipped steps (e.g. do not mention that `--force` was absent).

`$ARGUMENTS`
