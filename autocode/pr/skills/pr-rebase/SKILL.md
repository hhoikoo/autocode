# PR rebase

Rebase the current branch onto its base and resolve conflicts.

## Args

- `--auto`: suppress all three `AskUserQuestion` gates; emit the structured result block instead of the prose report. Never prompts. Default (flag absent) keeps every gate and the step-8 prose report verbatim.

## Workflow

1. Resolve base: re-use the `pr-create` skill's resolve script if available, else `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
2. `git fetch origin <base>`. If `git log HEAD..origin/<base> --oneline` is empty:
   - Default: report "up to date" and stop.
   - `--auto`: emit `{ rebased: false, conflicts_resolved: 0, verify: "skip", needs_human: false, reason: "" }` and stop without pushing.
3. `git rebase origin/<base>`.
4. Conflict resolution loop, per file:
   - `git diff --name-only --diff-filter=U` gets the conflicted set.
   - Guardrail: if more than 5 files conflict in a single rebase step:
     - Default: pause and ask via `AskUserQuestion` whether to continue or abort.
     - `--auto`: `git rebase --abort`, return `{ rebased: false, needs_human: true, reason: "<n> files conflicted in one rebase step" }`.
   - Read each file. Read base log touching the file: `git log HEAD..origin/<base> -- <file>`.
   - Conflict decision tree per conflicted file:
     - `.autocode/design/INDEX.md` with same `id` on both sides: renumber this branch's design to the next free id (existing resolution below).
     - `.autocode/design/**/PROGRESS.md`: union both sides' blocks (new resolution below).
     - Anything else: per-file read + resolve, or `AskUserQuestion` / `--auto` return when intent is ambiguous.
   - **INDEX.md id collision.** Renumber this branch's design rather than merging the rows:
     - Next free id = highest id across both sides + 1, zero-padded to 4 digits.
     - `git mv .autocode/design/<old-id>-<shortname> .autocode/design/<new-id>-<shortname>`.
     - Resolve `INDEX.md` to the base rows plus this branch's row carrying the new id. `git add` the renamed folder and `INDEX.md`.
   - **PROGRESS.md conflict (backstop).** File format: one `# Progress: <shortname>` header followed by `## <slug> — <date>` blocks (see the `## PROGRESS.md` section of `design-folder.md`). This branch is triggered when `.gitattributes` lacks the `merge=union` driver for `.autocode/design/**/PROGRESS.md` (scaffolded by `/autocode-setup`): with the driver, git resolves this before the file enters the conflicted set; on repos without it git surfaces the conflict and this branch resolves it:
     - Keep the single `# Progress:` header once.
     - Concatenate all `## <slug> — <date>` blocks from both base and incoming sides.
     - Strip all conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
     - Never merge two blocks onto one slug (mirrors the INDEX.md "never two rows onto one id" principle).
     - `git add` the file.
     - Applies in both default and `--auto` modes.
   - Resolve. `git add <file>`. After all files for the step are resolved, `git rebase --continue`.
   - On incompatible conflicts where intent is ambiguous:
     - Default: ask the user via `AskUserQuestion`.
     - `--auto`: `git rebase --abort`, return `{ rebased: false, needs_human: true, reason: "<description of ambiguous conflict>" }`.
5. Verify: read the verify command from `$AUTOCODE_CONFIG_DIR/conventions/build.md` and run it.
   - Small obvious failure (lint, typo): fix and amend the relevant commit (`git commit --amend --no-edit` after re-staging). Applies in both modes.
   - Non-trivial failure:
     - Default: stop and ask the user.
     - `--auto`: leave branch unpushed, return `{ rebased: false, needs_human: true, verify: "fail", reason: "<output from failing command>" }`.
6. Push: `git push --force-with-lease`. Never `git push --force`.
7. Background hygiene. A rebase rewrites the branch and may resolve content conflicts, so the PR body can be stale. Spawn the `pr-hygiene` agent via the Task tool with `run_in_background: true`; do not wait for it. The prompt includes the rebased branch SHAs (`git log <base>..HEAD --pretty=%H`) and changed files (`git diff <base>...HEAD --name-only`). The agent self-checks for a PR and handles design PRs (recompose) vs code PRs (diff-based) on its own. Skip only if the rebase was a no-op (step 2 already stops then). Dispatches in `--auto` mode too (unless no-op).
8. Report:
   - Default: rebased branch, conflict count resolved, verify result, and that hygiene was dispatched.
   - `--auto`: emit the structured result block as final output:
     ```
     { rebased: bool,
       conflicts_resolved: int,
       verify: "pass" | "fail" | "skip",
       needs_human: bool,
       reason: string }
     ```
     - Clean rebase: `rebased: true, needs_human: false, conflicts_resolved: <n>, verify: "pass"|"skip", reason: ""`.
     - `verify: "skip"` when the step-2 no-op already stopped (no verify ran) or when `build.md` defines no verify command.

## Rules

- `--force-with-lease`, never `--force`.
- 5-file conflict guardrail.
- On an `INDEX.md` id collision, renumber this branch to the next free id (rename the folder + fix the row); never merge two rows onto one id.
- Verify before push; don't push a broken rebase.
- `--auto` suppresses all three `AskUserQuestion` gates and returns the structured result with `needs_human: true` instead of prompting. The 5-file guardrail still fires; it returns rather than prompts under `--auto`.
- A `PROGRESS.md` conflict resolves by union: keep both sides' blocks, single `# Progress:` header, no conflict markers. Mirrors the INDEX.md renumber rule (never collapse two units' blocks).

$ARGUMENTS
