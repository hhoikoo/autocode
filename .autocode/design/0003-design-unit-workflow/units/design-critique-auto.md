---
depends-on: []
type: task
---

# Add an --auto mode to design-plan-critique

## Summary

`design-plan-critique` is an interactive in-session loop: it calls `AskUserQuestion` on argument ambiguity during discovery and again when the 5-iteration cap is reached, and it returns a 2-3 line prose summary. A background phase cannot answer an `AskUserQuestion` prompt, and a skill invoked inline runs in the main session, so neither the gates nor the loop's question/research/apply churn can move off-context by an inline invocation alone (DESIGN.md decision 2). Move the critique loop off the main context into a background Workflow script (`autocode/design/skills/design-plan-critique/scripts/design-critique-workflow.mjs`) whose agents read the existing `design-plan-critique` body for the critique heuristics (single-source), and add an `--auto` flag that makes `design-plan-critique` a thin launcher over that workflow, ending with a structured result block carrying a `needs_human` signal. Under `--auto` an ambiguous argument is a fail-fast error instead of a prompt; every per-iteration question resolves via a researcher only (the loop never asks the user mid-pass); hitting the cap stops and returns `needs_human: true` rather than prompting; and any question research cannot resolve becomes a `needs_human` entry. The in-place edits to `DESIGN.md`, `units/*.md`, and the `## Critique log` are unchanged. The default (non-`--auto`) interactive in-session loop is untouched, preserving the manual fallback (DESIGN.md decision 8).

## Implementation

Deliverable: one new workflow script plus an `--auto` thin-launcher path on `design-plan-critique`, mirroring `0002` decision 6 (the `--auto` + `needs_human` pattern) and the workflow-centric dispatch the plan phase uses (`design-plan-workflow.mjs`).

Files to create:

- `autocode/design/skills/design-plan-critique/scripts/design-critique-workflow.mjs`: the background critique loop, sibling to `impl-workflow.mjs` and `design-plan-workflow.mjs`. Plain JS, no shim, not shape-checked.

Files to modify:

- `autocode/design/skills/design-plan-critique/SKILL.md` (body-only real skill; no frontmatter per the layout rule): add `--auto` as a thin launcher over the workflow; keep the non-`--auto` interactive loop verbatim. No shim change unless the shim's `description` needs the `--auto` mention; the shim at `plugins/autocode/skills/design-plan-critique/SKILL.md` carries frontmatter only and forwards `$ARGUMENTS`, so confirm whether its `description` should note `--auto`.

### The workflow script

Model on `impl-workflow.mjs` / `design-plan-workflow.mjs`. The workflow owns only the deterministic loop + fan-out scaffolding; its agents read the `design-plan-critique` body for the actual question-generation, resolution, and apply heuristics, so the critique logic stays single-source (the workflow does not restate it).

- `export const meta` with `name`, `description`, and a `phases` array (`Question`, `Resolve`, `Apply`), one group per loop concern.
- Path resolution via `args.homeDir`; args from the launcher: `{ homeDir, repoRoot, folder }` (the resolved design folder; the workflow reads `DESIGN.md` + `units/*.md` from it).
- The loop, bounded to 5 iterations (`SKILL.md:26,37`), each iteration:
  1. `Question`: one `agent` reads the design + the `design-plan-critique` body and emits this pass's follow-up questions via `schema` (`SKILL.md:22`).
  2. `Resolve`: one `agent` per question inside `parallel`, each dispatching a `codebase-researcher` (researcher-only; never asks the user mid-loop). A question the researcher cannot resolve is returned with an `unresolved` flag and collected into `needs_human_reasons`; it does not abort the loop. Pass `{ phase: 'Resolve' }` as the agent option, never a bare `phase()` inside the map.
  3. `Apply`: one `agent` per affected unit inside `parallel` writes the resolutions into `units/<slug>.md` (the existing apply fan-out, `SKILL.md:25`); the `DESIGN.md` edits and the `## Critique log` append are done by a single serial `agent` (shared file, `SKILL.md:24`). Pass `{ phase: 'Apply' }` as the option.
  4. Stop when a pass produces no new questions (converged) or at 5 iterations (cap).

The apply-phase fan-out moving into the workflow is what makes critique off-context: a subagent cannot spawn the per-unit apply subagents, but a Workflow's `parallel` can, exactly as `design-plan-workflow.mjs` runs its author fan-out.

### `design-plan-critique` skill edits (thin launcher under `--auto`)

- Under `--auto`: resolve `homeDir` (`echo "$HOME"`), `repoRoot` (`git rev-parse --show-toplevel`), and the design `folder` (the existing discovery glob, `SKILL.md:13-17`). An ambiguous or unresolvable arg is a fail-fast error (no `AskUserQuestion`), because there is no design to critique yet. Launch the Workflow with `args: { homeDir, repoRoot, folder }`, wait, and emit the structured result block below in place of the prose summary (`SKILL.md:30`). The `/design` orchestrator launches the same workflow directly and does not route through this skill.
- Without `--auto`: the existing interactive in-session loop is unchanged, including both `AskUserQuestion` gates (arg ambiguity `SKILL.md:11,17`; cap `SKILL.md:26`) and the 2-3 line prose summary (`SKILL.md:30`). This is the only place those gates survive (the manual fallback, DESIGN.md decision 8).

### Structured return

The `--auto` launcher emits the workflow's return verbatim. Scalar and list fields only, in a single fenced block, no surrounding prose, matching the `impl-start --auto` block convention (`autocode/impl/skills/impl-start/SKILL.md:16,30`):

```
status: done | cap_reached | error
iterations_run: <int>
questions_resolved: <int>
needs_human: <bool>
needs_human_reasons: [{ question, why }, ...]
files_modified: [<path>, ...]
critique_log_path: <path to DESIGN.md holding the ## Critique log>
```

Field semantics:

- `status: done` -> the loop converged (a pass produced no new questions) before the cap.
- `status: cap_reached` -> stopped at 5 iterations (`SKILL.md:26,37`); implies `needs_human: true` when open questions remain.
- `status: error` -> fail-fast on an ambiguous/unresolvable arg during discovery (the launcher never reaches the workflow); other result fields omitted or zeroed.
- `needs_human: true` when any unresolved-by-research question exists or the cap was reached with open questions. `needs_human_reasons` pairs each surfaced question with why research could not close it.
- `files_modified` lists the `DESIGN.md` and `units/*.md` paths the workflow edited this run (`SKILL.md:24-25`).
- `critique_log_path` points at the `DESIGN.md` that holds the appended `## Critique log` (`SKILL.md:24`).

Unchanged behavior to preserve in both modes: the loop structure (generate questions -> resolve -> apply in place + append `## Critique log` -> repeat, cap 5; `SKILL.md:21-26`), the in-place edit and source-citation rules (`SKILL.md:34-36`), and the cap value of 5 (`SKILL.md:26,37`).

### Tests that prove it

Markdown-and-script change; verification per the epic testing strategy (`DESIGN.md` testing strategy):

- `scripts/check-plugin-shape.sh` passes (real skill body-only, no frontmatter; `design-critique-workflow.mjs` carries no frontmatter and is not a skill/agent file; shim unchanged or description-only).
- Static read of `design-critique-workflow.mjs` against `impl-workflow.mjs`: same helper shape, `args.homeDir` path resolution, `parallel` fan-out, `schema`-typed returns, `{ phase: '...' }` passed as options inside `parallel` (never a bare `phase()` in a map), no forbidden globals; the loop is bounded to 5 iterations.
- Dry-run `design-plan-critique --auto` on a scratch design: assert it launches the workflow (no in-session question/research/apply churn in the launching session) and the structured block parses with all listed fields and no surrounding prose.
- Force an ambiguous arg under `--auto`: assert `status: error` and a descriptive error message, no `AskUserQuestion`, no workflow launched.
- Seed an intentionally vague unit that research cannot resolve and that survives 5 iterations: assert `status: cap_reached`, `needs_human: true`, and a matching `needs_human_reasons` entry.
- Run the non-`--auto` path unchanged: assert it still runs the in-session loop, prompts on ambiguity/cap, and returns the 2-3 line prose summary (manual fallback intact, DESIGN.md decision 8).
