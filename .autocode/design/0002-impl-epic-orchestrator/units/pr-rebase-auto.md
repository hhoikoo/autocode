---
depends-on: []
type: task
---

# pr-rebase --auto with structured return and PROGRESS.md union resolution

## Summary

`pr-rebase` gains an `--auto` flag that suppresses its three `AskUserQuestion` gates (the >5-file conflict guardrail, the ambiguous-conflict pause, and the non-trivial verify failure) in favor of a single structured result carrying a `needs_human` signal, so the epic monitor can auto-rebase unattended and branch on the cases that genuinely need a person. It also adds an explicit `PROGRESS.md` union resolution that mirrors the existing `.autocode/design/INDEX.md` id-collision special-case: when the conflicted file is a `.autocode/design/**/PROGRESS.md`, the rebase keeps both sides' appended blocks (no markers, single `# Progress:` header) as a skill-level backstop for repos whose `.gitattributes` lacks the `merge=union` driver. All interactive behavior is preserved when `--auto` is absent; `--force-with-lease` and verify-before-push are unchanged.

## Implementation

Deliverable: edit one source file, the canonical skill body. The shim needs no change.

Files to modify:

- `autocode/pr/skills/pr-rebase/SKILL.md` (the real, body-only skill at `autocode/pr/skills/pr-rebase/SKILL.md:1`): add the `--auto` arg, the suppressed-gate branches, the structured return, and the `PROGRESS.md` union resolution step.

Files NOT modified (note for the implementer):

- `plugins/autocode/skills/pr-rebase/SKILL.md` (`plugins/autocode/skills/pr-rebase/SKILL.md:6`) already forwards `$ARGUMENTS`, so `--auto` flows through with no edit. Its `description` (line 3) carries no mode list and stays accurate, so leave it. The shim is unchanged.

### `--auto` mode

Add `--auto` to the `## Args` section (currently `(none; operates on the current branch)`, `autocode/pr/skills/pr-rebase/SKILL.md:6`). Default (flag absent) keeps every current `AskUserQuestion` gate and the prose report verbatim (decision 11, manual fallback preserved).

When `--auto` is set, the three existing human gates become structured `needs_human` returns instead of prompts:

| Current gate (`SKILL.md` line) | Default behavior | `--auto` behavior |
|---|---|---|
| >5 files conflict in one rebase step (`:16`) | `AskUserQuestion` continue/abort | `git rebase --abort`, return `needs_human: true` with `reason` naming the file count |
| Ambiguous/incompatible conflict, intent unclear (`:23`) | `AskUserQuestion` | `git rebase --abort`, return `needs_human: true` with `reason` |
| Non-trivial verify failure (`:26`) | stop and ask | leave the branch unpushed, return `needs_human: true`, `verify: "fail"`, `reason` from the failing command |

The small-obvious-failure auto-fix path (lint/typo amend, `:25`) and the trivial-conflict resolutions stay automatic in both modes. Verify-before-push and `--force-with-lease` (`:27`, `:33`) are unchanged: `--auto` never pushes a branch that failed verify or needs a human.

Structured result (the contract `impl-orchestrator-monitor` consumes, per DESIGN.md decision 6 and runtime-flow step 5):

```
{ rebased: bool,
  conflicts_resolved: int,
  verify: "pass" | "fail" | "skip",
  needs_human: bool,
  reason: string }
```

`verify: "skip"` covers the up-to-date no-op (`:13`, rebase did nothing) and the case where `build.md` defines no verify command. On a clean rebase: `rebased: true, needs_human: false`, `reason: ""`. The skill emits this block as its final output in `--auto` mode in place of the step-8 prose report; background hygiene (`:28`) still dispatches unless the rebase was a no-op.

### PROGRESS.md union resolution

Add a conflict-resolution branch alongside the existing INDEX.md special-case (`autocode/pr/skills/pr-rebase/SKILL.md:18-22`), inside the per-file loop (step 4). It applies in both default and `--auto` modes.

Trigger: the conflicted file matches `.autocode/design/**/PROGRESS.md`.

Resolution: union the two sides' appended blocks. The file format is a single `# Progress: <shortname>` header followed by one `## <slug> — <date>` block per merged unit (`design-folder.md:122-135`). Keep the single header once; concatenate base-side and incoming-side unit blocks with no conflict markers; `git add` the file. This never merges two blocks onto one slug the way INDEX.md never merges two rows onto one id (the stated principle, research finding); distinct units append distinct blocks, so the union is the correct merge.

This is the skill-level backstop for the `.gitattributes merge=union` driver scaffolded by the `progress-union-gitattributes` sibling unit (DESIGN.md decision 8): on a repo whose `.gitattributes` predates that scaffolding, git surfaces the conflict and this branch resolves it; on a current repo the driver resolves it before the file ever enters the conflicted set, so this branch is a no-op.

```
conflicted file
  ├─ .autocode/design/INDEX.md + same id  -> renumber losing branch (existing)
  ├─ .autocode/design/**/PROGRESS.md      -> union both sides' blocks (new)
  └─ anything else                        -> existing per-file resolution / gates
```

### Rules section

Extend `## Rules` (`autocode/pr/skills/pr-rebase/SKILL.md:32-36`): state that `--auto` suppresses all three `AskUserQuestion` gates and returns the structured result with `needs_human` instead, and that a `PROGRESS.md` conflict resolves by union (keep both blocks, single header), mirroring the INDEX.md renumber rule. The existing `--force-with-lease`-never-`--force`, 5-file-guardrail, and verify-before-push rules are unchanged in wording; the guardrail still fires, it just returns rather than prompts under `--auto`.

### Tests that prove it

Per DESIGN.md testing strategy (`--auto` skill modes, and the union construction):

- Forced large conflict on a scratch branch with `--auto`: assert the structured block has `needs_human: true`, `rebased: false`, and a `reason` naming the file count; assert no push and no `AskUserQuestion`.
- Forced verify failure with `--auto`: assert `verify: "fail"`, `needs_human: true`, branch unpushed.
- Clean rebase with `--auto`: assert `rebased: true, needs_human: false, verify: "pass"|"skip"`.
- Up-to-date no-op with `--auto`: assert `verify: "skip"`, no push.
- Two branches each appending a distinct `PROGRESS.md` block, rebase one onto the other on a repo with no `merge=union` `.gitattributes`: assert both blocks survive, single `# Progress:` header, zero conflict markers.
- Default mode (no `--auto`): the three gates still prompt; the prose report is unchanged (regression guard for decision 11).
