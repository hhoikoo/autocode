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

## Step 2: Reconcile settings

After the pull succeeds, read `~/.autocode/autocode/_config/settings-schema.md`. It declares which top-level namespaces are shared (`provider.*`, `workflow.*` -> `settings.json`) and which are local (`paths.*` -> `settings.local.json`), plus which keys are required.

Check each file under `$AUTOCODE_CONFIG_DIR/`:

1. **Required-key drift.** For every key the schema marks required, verify it exists in the file matching its scope. Report any missing required key. Offer to scaffold it now using the same prompt logic as `/autocode-setup` step 3 (ask the user, then call `write-settings.sh --scope=<scope>` and merge into the existing file via `jq` rather than overwriting).
2. **Scope migration.** Read both files; for any key whose namespace does not match the file it sits in (e.g. a `paths.*` key found in `settings.json`, or a `provider.*` key found in `settings.local.json`), move it to the correct file. Report each move. Use `jq` to delete from the wrong file and add to the right one in one pass; never lose values.
3. **Gitignore.** Verify `$AUTOCODE_CONFIG_DIR/.gitignore` exists and contains a `settings.local.json` line. If missing or absent, append it. Report only when changed.

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

One terse line: commits pulled, settings keys migrated/scaffolded, conventions missing/scaffolded, drift flagged. Skip the "next run" note; the `SessionStart` hook handles nudging. No narration of skipped steps (e.g. do not mention that `--force` was absent).

`$ARGUMENTS`
