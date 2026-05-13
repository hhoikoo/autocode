# conventions/

Each file in this directory is instructions to Claude on how to create the corresponding convention file in a target repo. They are not templates with placeholder text; they describe what to inspect in the repo, what to ask the user, and what defaults to fall back to.

## How the setup skill uses these

`/autocode-setup` step 4 iterates `*.md` in this folder (excluding `CLAUDE.md`). For each file `<name>.md`:

1. The skill reads the instructions in `~/.autocode/autocode/_config/conventions/<name>.md`.
2. The skill follows the instructions to produce a per-repo `$AUTOCODE_CONFIG_DIR/conventions/<name>.md` file.
3. If the target file already exists, the skill skips it and reports "already configured".

## How the update skill uses these

`/autocode-update` checks that every file in this folder has a counterpart under `$AUTOCODE_CONFIG_DIR/conventions/`. Missing files are reported and the user is offered the option to scaffold them. With `--force`, the update skill also asks the model whether each existing user-side convention still aligns with the (possibly updated) instructions here.

## Authoring rules for instruction files

- Open with a one-sentence statement of what the convention captures.
- List what to inspect in the target repo, in provider-neutral terms. Do not say "run `gh label list`"; say "discover the labels in use, however the issue tracker exposes them". The model can decide which tools to use.
- List what to ask the user if inspection is ambiguous, and require a final confirmation step. Each `## Ask` section must lead with a bullet that surfaces the derived values via `AskUserQuestion` (or equivalent) and gets explicit approval before writing, even if inspection or the default produced an unambiguous answer. Repeat the bullet in each file so the rule survives when the file is read in isolation.
- Give a sensible default. The model uses the default only when neither inspection nor user input yields a value.
- End with a section labelled `## Output format` describing what the final per-repo `<name>.md` file should look like (sections, table shape, etc.). The model produces a file in that shape.

The output file is freeform markdown intended for human reading and `@`-import by skills. It is not parsed as data.
