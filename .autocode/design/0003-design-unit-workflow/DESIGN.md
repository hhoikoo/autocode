# Design lifecycle orchestrator

## Summary

`design-plan`, `design-plan-critique`, `design-plan-iterate`, `design-plan-push`, and `design-fanout` are driven one at a time, by hand, each in the launching session, so every phase's research churn, prose authoring, and triage fills the main context window. This epic turns `/design` into a stateless, re-entrant orchestrator for the design half of the lifecycle, the mirror of the impl-epic-orchestrator (`0002-impl-epic-orchestrator`) for the impl half. Given a seed or an in-flight epic, it reconstructs the current stage from disk, the tracker, and the open PR, dispatches the next heavy phase into a background workflow or subagent so the work runs off the main context, consumes a single typed result, and advances one step: plan -> critique -> push -> (iterate on review) -> [merge, user-gated] -> fanout -> hand off to the impl orchestrator. Pre-merge thinking runs automatically; merging is the one step pinned to the main session for explicit user approval; fanout runs automatically post-merge. The original narrow scope of this folder (move the unit-author fan-out into a background workflow, give `design-unit-author` a structured `{ underspecified, file, summary }` contract, auto-derive the shortname) folds in as the plan phase's off-context mechanism. To make each phase dispatchable, `design-plan`, `design-plan-critique`, `design-plan-iterate`, and `design-fanout` gain `--auto` modes with structured returns and a `needs_human` signal, mirroring decision 6 of `0002`. Every phase skill stays individually invocable, so repositories without full automation access can still drive the pieces by hand.

## Background

The per-phase design skills already exist and each works standalone. What is missing is the layer above them: a single re-entrant command that knows where an epic is in its lifecycle and runs the next phase off-context, gating only where a human decision belongs. A second gap is the surface that layer needs: the phase skills are interactive (they call `AskUserQuestion`) and return prose, neither of which a background phase can consume.

| Phase | Skill | Current behavior | Gap for orchestration |
|---|---|---|---|
| Plan | `autocode/design/skills/design-plan/SKILL.md` | In-session: seed prompt, research fan-out, compose `DESIGN.md`, inline `design-unit-author` fan-out, interactive shortname prompt. | Heavy work + N copies of `DESIGN.md` in dispatch prompts fill context; interactive; prose return. |
| Critique | `autocode/design/skills/design-plan-critique/SKILL.md` | In-session bounded loop (cap 5): generate questions, dispatch researchers, apply edits in place; `AskUserQuestion` on arg ambiguity and on cap. | Interactive gates; prose 2-3 line return; no `needs_human` contract. |
| Iterate | `autocode/design/skills/design-plan-iterate/SKILL.md` | Triage design-PR review comments, score, apply, reply, resolve threads. No `AskUserQuestion` gates. | Returns a triage table, not machine-readable; no `--auto` contract. |
| Push | `autocode/design/skills/design-plan-push/SKILL.md` | Compose the design-PR body, commit, open a lightweight PR. Light. | Already thin; needs only a typed PR-URL return. |
| Fanout | `autocode/design/skills/design-fanout/SKILL.md` | Post-merge: create epic issue + per-unit sub-issues, idempotent by body marker; `AskUserQuestion` on arg ambiguity. | Interactive on ambiguity; prose table return. |
| Unit authoring | `autocode/design/agents/design-unit-author.md` | Inline Task fan-out; unstructured prose with in-band "underspecified" signal. | Not a typed control signal; retry bounces to the session. |
| Fanout (auto) | `.github/workflows/autocreate-design-doc-issue.yml` | Pure-shell GH Action fires on merged PR adding a new `DESIGN.md`; same issue shape as the skill. | Independent of the orchestrator; runs only on the default-branch merge event. |
| Lifecycle state | `autocode/design/design-folder.md`, `provider/issue-tracker/github/issue-epic-list.sh` | `INDEX.md` status is coarse (`active`/`archived`); fine-grained unit/epic state lives in the tracker via `issue-epic-list`. | No single "where is this epic" query; needs disk + tracker + PR reconstruction. |

## Architecture

The orchestrator runs in the main session and owns no durable state. Each turn it reconstructs the stage from three observable sources (disk, the issue tracker, the open PR), runs exactly one phase off the main context, consumes its typed result, and either advances or stops at a gate. The heavy phases (plan, critique) run as background workflows or subagents; merging is the only step pinned to the main session, because it needs explicit user approval.

```
                    main session: /design orchestrator (stateless, re-entrant)
                            |                              ^
  reconstruct stage each turn                              | re-invoked on <task-notification>
        +-------------------+--------------------+         | (phase workflow completion)
        |                   |                    |         |
        v                   v                    v         |
   disk: folder?       tracker:             open design    |
   committed?          issue-epic-list      PR? (by branch |
   units/?             (epic/unit status)   / design-diff) |
        |                   |                    |         |
        +-------------------+--------------------+         |
        |  stage in { none, planned, pushed, in-review,    |
        |             merged, fanned-out }                 |
        v                                                  |
   dispatch next phase OFF-CONTEXT  ----------------------+
        |
        |  none      -> plan-phase     (bg)  -> { folder, id, units[], open_qs }
        |  planned   -> critique-phase (bg, --auto) -> { iterations, changes, needs_human }
        |  planned   -> push           (light/in-session) -> { pr_url }
        |  in-review -> iterate        (--auto) -> { applied, needs_human }  [+ wait for merge]
        |  ====================== USER-GATED MERGE (main session only) ======================
        |  merged    -> fanout         (--auto) -> { epic_key, sub_issues[] }
        |  fanned-out-> hand off: invoke `impl --from-design <id>` (the 0002 orchestrator)
        v
   surface needs_human cases; present merge-ready PR; report stage + next step
```

Heavy-phase dispatch keeps the research findings, the unit prose, and the triage noise out of the main session: the orchestrator sees only a typed result per phase. Each heavy phase is one background Workflow the main-session orchestrator launches directly (`design-plan-workflow.mjs`, `design-critique-workflow.mjs`); the plan workflow absorbs the unit-author fan-out and the critique workflow absorbs the per-iteration research and apply fan-out, each as `agent()`/`parallel()` calls inside the single workflow (no nested workflow, sidestepping the one-level nesting limit, since the orchestrator itself is a main-session skill, not a Workflow).

## Design decisions

1. **The outer orchestrator is a main-session skill, not a Workflow.** A Workflow runs to completion in the background and cannot call `AskUserQuestion`, but merging a design PR is an inherent user-gated, outward step; and a Workflow cannot nest another Workflow (the plan phase already launches a fan-out workflow). So `/design` is a thin main-session sequencer that launches each phase off-context and waits, exactly as `impl` launches `impl-workflow` (`autocode/impl/skills/impl/SKILL.md:21-26`). User-confirmed (this session): the outer layer need not be a workflow. Rejected: a pure-workflow orchestrator (cannot gate the merge, cannot nest the plan fan-out).

2. **Each heavy phase is a background Workflow the orchestrator launches directly.** Plan and critique are the context-heavy phases (research churn, unit prose, per-iteration question/research/apply). A skill invoked via the Skill tool runs *in* the main session, so invoking a phase skill inline does **not** move its work off-context; only a Workflow or a subagent runs off-context, and a subagent cannot nest the fan-outs these phases need (it can spawn neither a Workflow nor a further subagent). So each heavy phase is a background Workflow script (`design-plan-workflow.mjs`, `design-critique-workflow.mjs`) that the main-session orchestrator launches directly via the Workflow tool, consuming only a typed result, exactly as the `0002` orchestrator launches `impl-workflow.mjs` directly and bypasses the `impl` skill wrapper (research this session: `impl-orchestrator-core.md:49`, `impl-workflow.mjs:26-30` "Subagents cannot spawn subagents, so all fan-out lives here in the workflow runtime"). The workflow's agents *read the existing phase skill and agent bodies* for their heuristics, so the logic stays single-source and the workflow owns only the deterministic loop + fan-out scaffolding. The phase skills (`design-plan`, `design-plan-critique`) become thin launchers over the same workflow for the `--auto` path, and keep their in-session interactive loop for the non-`--auto` manual path (decision 8). This is the user's core requirement: drive the lifecycle without polluting the main context. Once the *whole* plan phase runs off-context, the "research must stay inline so the planner sees it" constraint dissolves: the planner is the off-context workflow now, the findings reach it there, and the main session gets only the summary. User-confirmed (this session): workflow-centric dispatch, mirroring `0002`. Rejected: invoking the `--auto` skills inline in the orchestrator's own context (the skill body runs in the main session, so synthesis, research digestion, and critique churn land in the window the design exists to keep clean); dispatching them as subagents (cannot nest the plan unit-author Workflow or the critique apply fan-out).

3. **Stateless, re-entrant stage reconstruction.** The orchestrator stores nothing durable; each turn it recomputes the stage from disk (does `.autocode/design/<id>-<short>/` exist; is it committed; does `units/` exist), the tracker (`issue-epic-list --epic <id>`: `[]` means not fanned out, non-empty means fanned out), and the open design PR (found by branch or by a diff touching only `.autocode/design/**`). `INDEX.md` `status` is a coarse two-state flag (`active`/`archived`, `design-folder.md:30-31`) and does not distinguish the pre-archive stages, so the fine-grained stage comes from disk + tracker + PR, not from `INDEX.md`. Mirrors `0002` decision 1 (the tracker is the single source of truth; a stored queue would drift). Rejected: a persistent orchestrator state file (needs reconciliation against the tracker regardless).

4. **Hybrid gating: auto pre-merge, hard-stop at merge, auto post-merge.** Plan, critique, push, and iterate run automatically (they are reversible, in-tree, and the design PR is itself the review artifact). The merge is the single hard gate: it is outward-facing and irreversible, and a design PR exists precisely so a human reviews and merges it. After merge, fanout runs automatically, then the orchestrator hands off. The orchestrator never merges the design PR on its own (distinct from `impl-archive`, which may self-merge its own archive PR with `--admin`). User-selected (this session): hybrid. Rejected: full-auto self-merge of the design PR (defeats the review the PR exists for); fully gated (a round-trip at every phase boundary the user does not want).

5. **`--auto` modes with structured returns and `needs_human` for the phase skills.** `design-plan`, `design-plan-critique`, `design-plan-iterate`, and `design-fanout` gain an `--auto` flag that suppresses their `AskUserQuestion` gates in favor of a structured result block carrying a `needs_human` signal. A background phase cannot call `AskUserQuestion`; the structured stop signal lets the orchestrator branch and surface only the cases that genuinely need a person (an ambiguous arg, a critique question research cannot resolve, the iteration cap reached with open questions). Directly mirrors `0002` decision 6 for `pr-rebase`/`pr-fix-ci`/`pr-review`. This is the enabler for decision 2.

6. **`design-unit-author` returns a structured contract and the plan phase runs a bounded research-backed retry.** `{ underspecified: boolean, file: string, summary: string }`, enforced by the plan-phase workflow's `agent(..., { schema })` call exactly as `impl-workflow.mjs` enforces its schemas. On an underspecified unit, the plan phase dispatches a `codebase-researcher` scoped to that unit, then re-dispatches the author with the findings (cap: one retry per unit); units still underspecified surface in the structured result. The retry's two agents pass the `{ phase: 'Resolve' }` agent option, never a bare `phase('Resolve')` call: the author runs inside `parallel`, where `phase()` mutates shared global state and races other units (Workflow tool contract; `impl-workflow.mjs:139-146` passes `{ phase: 'Review' }` as an option and never calls `phase()` inside a `parallel` map). The agent stays usable inline (a human reads the same three fields from prose). This is the original narrow scope of this folder, retained.

7. **Auto-derive the shortname; drop the prompt.** The plan phase derives `<shortname>` from the epic `# <Title>` (kebab-case, 2-4 keywords, filler stripped, the same reduction `git-create-branch` uses), de-duplicated against `INDEX.md` and existing `.autocode/design/*` folders (suffix `-2`, `-3`). The id, not the shortname, is the durable token. Removes an interactive round-trip, which a background plan phase could not make anyway.

8. **Manual fallback preserved.** The orchestrator is an automation layer over the phase skills, not a replacement. `design-plan`, `design-plan-critique`, `design-plan-iterate`, `design-plan-push`, and `design-fanout` stay individually invocable, and their interactive (non-`--auto`) behavior is unchanged. Mirrors `0002` decision 11. Rationale: in repositories where the user lacks full automation access, hand-driving the documented skills must still work.

9. **Hand off to the impl orchestrator at fanout; do not duplicate it.** `/design` owns the design half and stops once issues exist. The implementation half (parallel per-unit launch, monitor, cascade, archive) is owned by `0002-impl-epic-orchestrator`; `/design` invokes `impl --from-design <id>` (or, when that orchestrator is not present, suggests it and stops). Rationale: the two orchestrators meet at the fanout boundary; merging their concerns would couple the design and impl lifecycles and duplicate `0002`.

10. **Design-PR detection without an issue.** Pre-fanout there is no issue key, so the orchestrator cannot use `0002`'s issue-key `pr-find`. It detects the design PR by the design branch (`docs/design-<short>` for the epic) or, as a fallback, by an open PR whose diff touches only `.autocode/design/**` (the design-PR detection rule in `autocode/design/design-pr-body.md`). No `pr-find`/`pr-list` provider script exists today (a known gap); the orchestrator uses `provider/run.sh git-remote pr-view` from the worktree, or a direct `gh pr list --head <branch>`, and the design notes the missing provider abstraction. Rejected: reusing `0002`'s issue-key `pr-find` (no issue exists at this stage).

## Runtime flow

1. Invoke `/design <seed>` (new epic) or `/design <id|shortname>` (resume an in-flight epic). With a seed and no matching folder, the stage is `none`.
2. Reconstruct the stage:
   - `none`: no design folder for this seed/id.
   - `planned`: folder + `DESIGN.md` exist (committed or uncommitted in a worktree); no open design PR.
   - `pushed`/`in-review`: an open design PR exists for the folder's branch.
   - `merged`: the design PR merged (folder committed on the default branch) and `issue-epic-list --epic <id>` returns `[]`.
   - `fanned-out`: `issue-epic-list --epic <id>` returns a non-empty array.
3. `none` -> launch the plan workflow `design-plan-workflow.mjs` (off-context): it interprets the seed, fans out research, composes `DESIGN.md`, auto-derives the shortname, creates the worktree + branch + `<id>` + `INDEX.md` row, and authors the unit files via the bounded research-backed fan-out, returning `{ folder, id, units[], underspecified[], open_qs }`. Surface any `underspecified`/`open_qs`; otherwise continue.
4. `planned` -> launch the critique workflow `design-critique-workflow.mjs` (off-context, bounded to 5 iterations): it interrogates and edits the design in place, returning `{ iterations_run, files_modified, needs_human, needs_human_reasons[] }`. If `needs_human`, surface the open questions and stop; else continue to push.
5. `planned` (critique clean) -> run push (`design-plan-push`; light, may stay in-session): commit the folder, compose the design-PR body, open the lightweight PR, returning `{ pr_url, branch }`. Stage becomes `in-review`.
6. `in-review` -> if the PR has review comments, run iterate (`design-plan-iterate --auto`): triage and apply, returning `{ applied, replied, needs_human }`. Then present the PR for the user to review and merge. This is the hard gate: the orchestrator waits for the user to merge on the host; it never merges the design PR itself.
7. `merged` -> run fanout (`design-fanout --auto`): create the epic issue + per-unit sub-issues (idempotent), returning `{ epic_key, sub_issues[] }`.
8. `fanned-out` -> hand off: invoke `impl --from-design <id>` (the impl orchestrator) when present, else report the epic + sub-issues and suggest it. `/design`'s responsibility ends here.
9. Report the stage reached, the typed result of the phase run, and the next step.

Flat single-unit designs collapse the plan phase to a `DESIGN.md`-only write with no unit fan-out; critique, push, and fanout still run (fanout creates one issue). `--temp` plans are a single throwaway plan with no worktree, id, PR, or fanout: the orchestrator refuses to advance a `--temp` folder past plan and points the user at `/design-plan-critique <dir>`.

## Edge cases and error handling

- `none` with an ambiguous id/shortname match: the orchestrator (main session) may `AskUserQuestion` to disambiguate before dispatching; the dispatched phases never do.
- Plan returns `underspecified` units or `open_qs`: surface them; the user resolves (more research or a tighter deliverable) and re-invokes `/design <id>`, which re-enters at the `planned` stage.
- Critique returns `needs_human`: surface the unresolved questions; stop. Re-invoking `/design <id>` re-runs critique (idempotent: it appends to the Critique log) or proceeds to push once the user clears the questions.
- Design PR has unresolved or contested review comments: iterate applies the high-confidence ones and surfaces the rest; the merge gate stays the user's.
- Merge gate: the orchestrator never merges the design PR. It waits; on re-invocation after the user merges, it detects `merged` and runs fanout.
- Fanout is partially complete (some issues exist): `design-fanout` is idempotent by body marker (`design-fanout/SKILL.md:20-21`); re-running creates only the missing issues. The GH Action (`autocreate-design-doc-issue.yml`) may have already fanned out on merge; the orchestrator detects `fanned-out` via `issue-epic-list` and skips straight to hand-off.
- The impl orchestrator (`0002`) is not merged/available: hand-off degrades to reporting the epic + sub-issues and suggesting `impl --from-design <id>`; no failure.
- `--temp`: no worktree, id, PR, or fanout; the orchestrator runs only the plan phase and stops.
- Flat single-unit design: no unit fan-out in plan; fanout creates a single issue with no sub-issues; no impl-orchestrator cascade (one unit).

## Testing strategy

Markdown-and-script change, no app build. Verification:

- `scripts/check-plugin-shape.sh` passes (no new shims that restate definitions; real files carry no frontmatter; every feature-set has `CLAUDE.md`; `*.sh` shellcheck clean). This is the CI gate.
- `--auto` skill modes: dry-run each of `design-plan`, `design-plan-critique`, `design-plan-iterate`, `design-fanout` with `--auto` on a scratch design and assert the structured result block, including `needs_human` on a forced ambiguous arg and (critique) an intentionally vague unit that survives the cap.
- Static read of any new workflow script against `impl-workflow.mjs`: same helper shape, `args.homeDir` path resolution, `parallel` fan-out, `schema`-typed returns, `{ phase }` option inside `parallel` (never a bare `phase()`), no forbidden globals.
- Orchestrator skill: validated by `scripts/check-plugin-shape.sh` plus a manual end-to-end dry run on a small two-unit seed, exercising stage reconstruction at each point (`none` -> `planned` -> `in-review` -> `merged` -> `fanned-out`), the merge gate (the orchestrator stops and does not merge), and the hand-off call. No automated harness exists for full skill runs; the dry run is the acceptance gate.
- Confirm `design-unit-author` still works inline (invoke it directly) and reports the three contract fields in prose; confirm every phase skill's non-`--auto` interactive path is unchanged (manual fallback).

## Alternatives considered

- **Pure-workflow orchestrator** (no main-session loop): rejected; a workflow cannot gate the user merge, cannot nest the plan fan-out, and cannot `AskUserQuestion` to disambiguate (decision 1).
- **One mega-skill that runs every phase inline in the launching session**: rejected; it fills the main context with exactly the research/prose/triage noise this epic exists to remove (decision 2).
- **A non-re-entrant `/design-all` that chains the phases once, top to bottom**: rejected; it cannot resume a half-finished epic (e.g. after the user merges out of band, or after a `needs_human` stop), and the merge gate forces a resume boundary regardless (decision 3).
- **Keep the narrow original scope** (only move the unit-author fan-out to a background workflow): superseded; the user asked for the full orchestrator, and the fan-out is one phase of it. The original work is retained as decision 6 and folded into the plan unit.
- **Move `design-fanout` entirely into the orchestrator**: rejected; the GH Action and the standalone skill must keep producing the identical issue shape for the manual path, so fanout stays a skill the orchestrator invokes (decisions 8, 9).

## Sources

- `autocode/design/skills/design-plan/SKILL.md:14-49` — current plan workflow; inline unit fan-out (`:43`), interactive shortname (`:38`), `INDEX.md` `active` row (`:41`). Read this session.
- `autocode/design/skills/design-plan-critique/SKILL.md:11-12,21-26,37` — critique loop, the two `AskUserQuestion` gates (arg ambiguity, cap), the 5-iteration cap, the 2-3 line prose return. Research this session.
- `autocode/design/skills/design-plan-iterate/SKILL.md:1-2,6,19-46` — design-PR comment triage between push and merge; no `AskUserQuestion` gates; outputs a triage table (not machine-readable). Research this session.
- `autocode/design/skills/design-plan-push/SKILL.md` — lightweight design-PR open; composes the body from `design-pr-body.md`; the design folder is uncommitted in the worktree until this runs. Read prior turns.
- `autocode/design/skills/design-fanout/SKILL.md:9,13-31,39` — post-merge epic + sub-issue creation, idempotent by body marker, `AskUserQuestion` on arg ambiguity, prose table return, "run only after the design PR merged". Research this session.
- `.github/workflows/autocreate-design-doc-issue.yml:24-107` and `.github/actions/design-fanout/action.yml:61-81` — the pure-shell GH Action that fans out on a merged PR adding a new `DESIGN.md`; same issue shape as the skill. Research this session.
- `autocode/design/agents/design-unit-author.md:29,39-41` — current in-band underspecified signal and unstructured output, replaced by the structured contract. Read this session.
- `autocode/design/agents/codebase-researcher.md:71` — read-only researcher used in the plan-phase retry. Read this session.
- `autocode/design/design-folder.md:7-9,18-31,73-78,111-119,152-179` — folder layout, `INDEX.md` schema and the `active`/`archived` two-state status, unit frontmatter and DAG, `issue-epic-list` discovery, four-state lifecycle, epic-done = folder moved. Research this session.
- `provider/issue-tracker/github/issue-epic-list.sh:13-15,53-84,88-110` — `[]` means not yet fanned out; non-empty means fanned out; per-unit `{key,summary,type,status,parent}` with status mapping. Research this session.
- `provider/git-remote/github/pr-view.sh:8` — raw `gh pr view` passthrough; no `pr-find`/`pr-list` provider script exists (design-PR detection gap). Research this session.
- `autocode/design/design-pr-body.md` — design-PR detection rule (diff touches only `.autocode/design/**`); used for branchless PR detection. Read prior turns.
- `autocode/impl/skills/impl/SKILL.md:21-26`, `autocode/impl/skills/impl/scripts/impl-workflow.mjs`, `autocode/impl/CLAUDE.md` — thin-launcher pattern, the Workflow call contract, `args.homeDir` path resolution, `parallel` fan-out, `{ phase }` option inside `parallel`, schema-typed returns, plain-JS constraints. Read this session.
- `.autocode/design/0002-impl-epic-orchestrator/DESIGN.md` — the impl-half orchestrator this epic mirrors: stateless re-entrancy (decision 1), `--auto`+`needs_human` modes (decision 6), manual fallback (decision 11), user-gated merge, hand-off boundary. Read this session.
- `autocode/impl/skills/impl-archive/SKILL.md:22` — `impl-archive` flips `INDEX.md` to `archived` and may self-merge its own PR with `--admin` (contrast: `/design` never self-merges the design PR). Research this session.
- `git-create-branch/SKILL.md:34,39` — the kebab short-name reduction reused for shortname derivation; branch shortname is a non-reproducible slug. Read this session.
- Claude Code `Workflow` tool contract (this session's tool definition) — the outer orchestrator cannot be a workflow (no `AskUserQuestion`, one-level nesting); the `{ phase }` option avoids the global `phase()` race inside `parallel`.
- User decisions (this session): rescope this folder into the design orchestrator mirroring `0002`; outer layer need not be a workflow; phases run off the main context; hybrid autonomy (auto pre-merge, user-gated merge, auto fanout); also drop the interactive shortname prompt.
- `impl-orchestrator-core.md:49`, `impl-workflow.mjs:26-30,30,139-146` — the `0002` orchestrator launches `impl-workflow.mjs` directly (bypassing the `impl` skill), all fan-out lives in the workflow ("Subagents cannot spawn subagents"), the `inWt` helper, and `{ phase }` passed as an option inside `parallel`. Researched this critique session; grounds decision 2's workflow-centric dispatch.
- `design-plan/SKILL.md:38,41,43`, `design-plan-push/SKILL.md:22` — worktree + branch + `<id>` + `INDEX.md` creation is a plan-phase responsibility today (`design-plan` delegates `git-create-branch` inside the worktree); `design-plan-push` only re-creates them as a fresh-session fallback. Researched this critique session.
- `impl` SKILL.md:9, `0002` DESIGN.md:84 — the hand-off entry interface `impl --from-design <id|shortname>` is the real `0002` epic-mode entry point. Researched this critique session; confirms decision 9 / runtime-flow step 8.
- User decision (this critique session): workflow-centric off-context dispatch (each heavy phase is a background Workflow the orchestrator launches directly; the `--auto` phase skills are thin launchers over the same workflow; non-`--auto` interactive paths unchanged).

## Critique log

Iteration 1 (this session):

- Q: How does the orchestrator run plan and critique "off-context" when a skill invoked via the Skill tool runs *in* the main session, and a subagent cannot nest the fan-outs these phases need? -> Researched `0002`'s dispatch (`impl-orchestrator-core.md:49`, `impl-workflow.mjs:26-30`): the main-session orchestrator launches `impl-workflow.mjs` directly. User chose workflow-centric: each heavy phase is a background Workflow (`design-plan-workflow.mjs`, `design-critique-workflow.mjs`) the orchestrator launches directly; the `--auto` skills become thin launchers; non-`--auto` interactive paths unchanged. Applied to decision 2, the architecture prose, the unit table, runtime steps 3-4, and both phase units.
- Q: Does `design-critique-auto` deliver an off-context mechanism? -> No; it added only an `--auto` flag to an in-session loop. Resolved: added `design-critique-workflow.mjs` owning the loop + apply fan-out; its agents read the `design-plan-critique` body so heuristics stay single-source.
- Q: Is "create worktree + branch" a plan-phase or push-phase responsibility (units disagreed)? -> Plan-phase (`design-plan/SKILL.md:41`; push is a fallback, `design-plan-push/SKILL.md:22`). Fixed the misleading "branch `design-plan-push` creates" parenthetical in `design-orchestrator-core` and moved worktree/branch/id/`INDEX.md` creation into the plan workflow's `Synthesize` phase.
- Q: Is the hand-off `impl --from-design <id>` a real `0002` interface? -> Yes (`impl` SKILL.md:9, `0002` DESIGN.md:84; also accepts `<shortname>`). No change; noted in Sources.
- Q: Does `codebase-researcher` exist at the cited path? -> Yes (`autocode/design/agents/codebase-researcher.md`). No change.

Iteration 2 (consistency pass over the revised design):

- Q: Does the revised plan unit keep the interactive shortname prompt in non-`--auto` mode, contradicting decision 7 (drop the prompt in *both* modes)? -> Yes, a self-introduced contradiction. Fixed: non-`--auto` auto-derives the shortname too; the seed prompt is the only `AskUserQuestion` the non-`--auto` path keeps.
- Q: The plan workflow has no `args.worktree` (unlike `impl-workflow.mjs`), since `Synthesize` creates the worktree mid-run; how does `inWt` get the path? -> Clarified in the plan unit: `inWt` is built from the worktree path `Synthesize` returns and is available only to the `Author`/`Resolve` phases after it.
- No new design-level questions; the revised design is internally consistent. Loop converged.

## Units

| Unit | Deliverable | depends-on |
|---|---|---|
| [design-plan-orchestrator-ready](units/design-plan-orchestrator-ready.md) | `design-plan-workflow.mjs`: the whole plan phase off-context (research, `DESIGN.md` synthesis, worktree/branch/id/`INDEX.md`, unit-author fan-out with the structured `design-unit-author` contract + bounded research-backed retry); `design-plan --auto` becomes a thin launcher over it with a structured return + auto-derived shortname | none |
| [design-critique-auto](units/design-critique-auto.md) | `design-critique-workflow.mjs`: the critique loop off-context (question generation, researcher fan-out, apply fan-out, cap 5); `design-plan-critique --auto` becomes a thin launcher over it with a structured return + `needs_human` signal; non-`--auto` keeps its in-session interactive loop | none |
| [design-iterate-auto](units/design-iterate-auto.md) | `design-plan-iterate --auto` with a structured machine-readable return | none |
| [design-fanout-auto](units/design-fanout-auto.md) | `design-fanout --auto` with a structured return (epic key + sub-issue keys), suppressing the ambiguity gate | none |
| [design-orchestrator-core](units/design-orchestrator-core.md) | The `/design` orchestrator skill: re-entrant stage reconstruction, off-context phase dispatch, hybrid gates with the user-gated merge, hand-off to the impl orchestrator, manual fallback | design-plan-orchestrator-ready, design-critique-auto, design-iterate-auto, design-fanout-auto |
