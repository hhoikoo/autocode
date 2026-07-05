# Design and impl workflow cost and quality improvements

## Summary

Cut design and impl token/compaction cost and make unit PRs self-documenting and reviewable, without changing what either workflow produces. Nine units: downgrade design-workflow researcher dispatches to sonnet; add workflow-driven per-phase progress logging; fold the Partition phase into the Plan agent's structured output; replace the full re-review after each fix with a scoped verify agent plus a convergence gate that draft-PRs unconverged units; fan gapcheck out per module with a whole-diff fallback and an integration bucket; add an SVG diagram guide; add an `impl-recap` phase with a canonical unit-PR-body recipe; and extend `pr-review` to act on RECAP.md-anchored comments. Five units edit `autocode/impl/skills/impl/scripts/impl-workflow.mjs`; they run in a strict linear chain so isolated worktrees never conflict on that file.

## Background

Every improvement targets an existing, measured cost or gap in the two workflow runtimes. Current state:

| Component | File | Current behavior |
|---|---|---|
| Design research dispatch | `autocode/design/skills/design-plan/scripts/design-plan-workflow.mjs:132,240` | Read-only `codebase-researcher` runs on opus |
| Design critique resolve | `autocode/design/skills/design-plan-critique/scripts/design-critique-workflow.mjs:95` | Resolve wrapper (spawns a sonnet researcher) runs on opus |
| Design args guard | both design workflow scripts, top of file | Present via #57 (c5ffded); the unit verifies it survives rebase, no edit unless a later change drops it |
| Progress logging | `plugins/autocode/hooks/check-progress-log.sh` (Stop hook) | Orphaned under fan-out: orchestrator cwd has no `.impl-context` and HEAD does not move there |
| Partition phase | `impl-workflow.mjs:245-255` | A second sonnet agent re-reads `.impl-plan.md` to transcribe the partition the opus planner already wrote |
| Fix loop | `impl-workflow.mjs:337-348` | Re-runs the whole `reviewCycle` (Prep/Review/Challenge/Decide, ~4-5 opus agents) after every `--fix` |
| Unconverged unit | `impl/SKILL.md:42` | A PR-less `in-progress` unit classifies as `needs-recovery`; restart deletes the worktree |
| GapCheck | `impl-workflow.mjs:310-335` | One opus agent loads the whole un-partitioned diff, up to `GAP_MAX_ROUNDS` times (the reported compaction case) |
| Architecture diagrams | `design-folder.md:61` | Spec mandates a hand-drawn ASCII diagram; no SVG option |
| Unit PR body | `pr-create/SKILL.md:24-35` and `pr-hygiene.md:42-48` | Composer and hygiene each hand-roll the body from the diff, with no shared recipe |
| Recap surface | (none) | No per-unit RECAP artifact; nothing summarizes a shipped unit |
| Hygiene phase | `impl-workflow.mjs:357-362` | Runs `pr-hygiene` unconditionally regardless of what changed |

## Architecture

No new packages. Two edit-serialization chains fall out of the file layout: every unit that edits the impl workflow runtime, and every unit that edits the design-folder spec, must be linearized because units run in isolated worktrees that assume file-disjoint parallelism.

impl-workflow.mjs phase pipeline (units that touch each phase):

```
  Plan ---> Partition ---> Execute/Commit ---> GapCheck ---> reviewCycle ---> Fix loop ---> Push ---> Hygiene
   |          |                |                   |             (Prep/Rev/    |             |         |
   |     [D2 removes]          |              [E1 per-module    Chal/Decide)  [D1 verify   [A1       [D5 gates
   |    folds partition        |               fanout +          |            replaces     Recap     on changed
   |    into Plan schema]  [F1 logProgress]    integration   [F1 logProgress] re-review;   phase     files]
   |                                            bucket +                      GATE draft-  before
[F1 logProgress]                                whole-diff                    PRs if        Push]
                                                fallback]                     unconverged]
```

Two serialization chains (arrows are depends-on):

```
  impl-workflow.mjs chain (file-disjoint requirement):
    workflow-progress-logging -> plan-partition-schema -> scoped-verify-gate
        -> per-module-gapcheck -> recap-phase-wiring

  design-folder.md chain (file-disjoint requirement):
    workflow-progress-logging -> svg-diagram-guide -> impl-recap-surface

  independent:  design-researchers-sonnet
  join point:   recap-phase-wiring depends-on [per-module-gapcheck, impl-recap-surface]
  tail:         recap-aware-review depends-on [recap-phase-wiring]
```

`workflow-progress-logging` heads both chains because it edits `impl-workflow.mjs` (logging) and `design-folder.md` (mirroring the new `[<phase>]` progress-entry format). New leaf skills follow the shim convention: body-only real file under `autocode/<feature-set>/skills/<name>/SKILL.md` plus a flat frontmatter shim under `plugins/autocode/skills/<name>/SKILL.md`. Two new skills are introduced (`impl-critique-verify`, `impl-recap`); both names are globally unique. One new cross-feature-set guide (`autocode/_config/guides/svg-diagram.md`) and one new canonical recipe (`autocode/impl/impl-pr-body.md`, sibling of `design-pr-body.md`) are `@`-imported, body-only, no frontmatter.

## Design decisions

1. **Chain every impl-workflow.mjs editor linearly, not by logical grouping.** Five units edit that one file. Isolated worktrees assume file-disjoint parallelism, so any two concurrent edits to it would conflict. The chain order matches the phase pipeline data flow (`F1 -> D2 -> D1 -> E1 -> A1-wiring`) so each unit builds on the prior unit's shape. Rejected: letting logically-independent units (e.g. progress logging and the hygiene gate) run in parallel, which would corrupt the file.

2. **Fold D5 (hygiene gate) into the recap-phase-wiring unit, not a standalone unit.** The hygiene gate is a ~5-line conditional at `impl-workflow.mjs:357-362`, physically adjacent to the Push/Recap tail that recap-phase-wiring already owns. A standalone D5 would add a fourth link to the impl-workflow chain for no isolation benefit. Rejected: a separate D5 unit.

3. **Split A1 into new-files vs workflow-wiring.** `impl-recap-surface` creates all new files (the `impl-recap` skill, `impl-pr-body.md`, the `pr-hygiene` and `pr-create` edits, the `design-folder.md` recap section). `recap-phase-wiring` is the small `impl-workflow.mjs` edit that inserts the Recap phase. Only the wiring joins the impl-workflow chain; the heavy new-file work runs off the chain, gated only by the design-folder serialization. Rejected: one monolithic A1 unit that would drag all of A1 onto the impl-workflow chain.

4. **Convergence gate converts an already-opened PR to draft, rather than plumbing `--draft` through `pr-create`.** `pr-create.sh` has no `--draft` and rejects unknown args (`pr-create.sh:37`); adding it would touch `pr-create/SKILL.md`, which `impl-recap-surface` also edits (to `@`-import `impl-pr-body.md`), creating a cross-unit file conflict. Instead the gate lets the Push phase open the PR normally, then a new `provider/git-remote/github/pr-draft.sh` (wrapping `gh pr ready <n> --undo`) converts it to draft and an idempotent `gh label create needs-human --force` + `--add-label` marks it. This keeps `scoped-verify-gate` file-disjoint from `impl-recap-surface`. The unit stays in `in-review` (PR exists), never `needs-recovery`. Rejected: `--draft` through the pr-create chain (file conflict); a `needs-human` lifecycle state (triggers recovery, which deletes the worktree, `impl/SKILL.md:42`).

5. **Scoped verify emits a `decided`-compatible structure with the full reviewCycle as mandatory fallback.** The verify agent must (a) confirm each decided finding is resolved, (b) diff-scan the fix commits for new regressions outside the decided set, and (c) return a `DECIDE_SCHEMA`-shaped object so `remaining_important` / `review_tally` (`impl-workflow.mjs:193,368,369`) stay correct: `actionable[]` items keyed on `severity: 'Important'|'Nit'`, plus `dropped` and a one-line `tally`. When verify fails or reports low confidence, the workflow falls back to the full `reviewCycle`. Rejected: trusting verify with no fallback (a missed regression ships).

6. **Fold the partition into the opus Plan agent; `heavy` becomes self-assessed.** The opus planner already writes the `## Module partition` section (`impl-plan/SKILL.md:31,40`); the sonnet Partition agent only re-reads and transcribes it. `plan-partition-schema` attaches `PLAN_SCHEMA` (partition + `heavy`) to the Plan call and removes the Partition phase, its schema, and its `meta.phases` entry. Tradeoff accepted: `heavy` is now judged by the author (which already holds the whole plan) instead of an independent downstream agent. The `## Module partition` section stays written to disk because `impl-execute --module` reads it (`impl-execute/SKILL.md:14`); the change is additive, not a move.

7. **Derive the gapcheck integration bucket by set complement, not a planner-authored list.** `per-module-gapcheck` assigns each module its files, then sweeps `foundation.files` plus any planned file in no module into one integration agent, computed as `all_files \ (module_files U foundation_files)` against the plan's per-file task list, asserting `|foundation| + Sum|modules| + |residual| == files_total`. A file the planner forgot to place still lands in the bucket and gets checked. Rejected: an explicit planner-authored integration list (re-introduces the drop it prevents).

8. **Size-gate per-module gapcheck on a self-computed diff count.** No `diff_lines` exists at gapcheck time (`prep.diff_lines` is produced later, inside `reviewCycle` at `impl-workflow.mjs:338`). The per-module gate computes its own count via `git diff` so small heavy units stay single-agent. Heavy-but-unpartitionable units (`partitionable:false`, `modules:[]`) keep the current whole-diff single-agent path, which the existing `if (heavy)` loop already handles. Rejected: reading a non-existent `prep.diff_lines` at gapcheck time.

9. **RECAP.md relative-path SVG is the primary surface; PR-description SVG embed only when the repo is public.** A relative-path SVG renders in the RECAP.md file view even on private repos; a PR-description raw-URL embed breaks on private repos (camo cannot auth). The recap gates a PR-description embed on `gh repo view --json isPrivate`, else blob-link only, and SHA-pins every blob URL at the recap-time HEAD (branch-ref URLs die after merge/archive). The Recap phase runs before Push so the pinned commit is an ancestor of the pushed tip. Rejected: unconditional raw-URL embed (breaks on the common private-repo case).

## Runtime flow

Impl workflow, unit run, after all nine units land:

1. **Plan** (opus): resolves unknowns, writes `.impl-plan.md` including `## Module partition`, and returns `PLAN_SCHEMA` (partition + `heavy`) directly. No separate Partition phase. `logProgress('Plan', ...)`.
2. **Execute/Commit**: unchanged; fans out per module when partitionable. `logProgress('Execute', ...)`.
3. **GapCheck** (heavy units): if partitionable with >=2 modules and the self-computed diff exceeds the size gate, one gapcheck agent per module (its files + plan items) plus one integration agent (foundation + residual files); else the whole-diff single agent. Gaps unioned before the fix loop. `logProgress('GapCheck', ...)`.
4. **reviewCycle** (round 0): Prep/Review/Challenge/Decide as today, producing `decided`.
5. **Fix loop**: while `remaining_important > 0`, apply `--fix`, then run the **scoped verify** agent instead of a full re-review: confirm decided findings resolved, diff-scan fix commits for regressions, emit a `decided`-compatible structure. On verify failure, fall back to the full `reviewCycle`. `logProgress('Fix', ...)`.
6. **Convergence check**: compute `needsHuman = remaining_important > 0 || remaining_gaps > 0`.
7. **Recap** (new, before Push): sonnet `impl-recap` builds `RECAP.md` from the diff and the now-populated `progress/<slug>.md`, SHA-pinning blob URLs at HEAD.
8. **Push**: `impl-push` commits the rollup (now including `RECAP.md`), opens the PR, links the issue.
9. **Convergence gate action**: if `needsHuman`, `pr-draft.sh` converts the PR to draft and applies the `needs-human` label + comment; the unit stays `in-review`.
10. **Hygiene**: runs `pr-hygiene` only if `push.hygiene_files` contains a docs/README/public-API file; otherwise skipped. `pr-hygiene` recomposes design or unit PR bodies from the matching canonical recipe.

## Edge cases and error handling

- **Heavy but non-partitionable** (`partitionable:false`, `modules:[]`, `heavy:true`): no fanout; the existing whole-diff gapcheck loop (gated on `heavy` alone) is the fallback. Verified against `impl-workflow.mjs:256-261,312-335`.
- **No foundation group**: integration bucket = residual files only; may still be non-empty from unpartitioned wiring files.
- **Empty integration bucket** (no foundation, no residual): skip the integration agent but still assert `Sum module files == files_total` so the empty bucket is proven, not assumed.
- **Verify agent unavailable / low confidence**: mandatory full `reviewCycle` fallback keeps `remaining_important` correct.
- **`needs-human` label absent**: create idempotently at point of use (`gh label create needs-human --force >/dev/null 2>&1 || true`), following the repo's inline-create pattern; no central label registry.
- **Private repo recap**: relative-path SVG in RECAP.md renders; PR-description embed is suppressed (`isPrivate:true`), blob-link only.
- **`args` delivered as a JSON string** to a design workflow: restored `const A = typeof args === 'string' ? JSON.parse(args) : (args || {})` guard prevents a crash (matches `impl-workflow.mjs:26`).
- **Recap references only committed paths**: RECAP.md cannot SHA-pin itself or PROGRESS.md (finalized in the Push commit); it pins only already-shipped source blobs at the captured HEAD.
- **Non-partitionable plan predates `## Module partition`**: Plan agent returns `partitionable:false`; single-agent path throughout.

## Testing strategy

Workflow scripts have no unit-test harness; verification is by driving the affected flow (the `verify` skill) and by reading structured output. Per unit: run the impl workflow on a small unit and confirm (a) the removed/added phases appear in the emitted phase list, (b) structured schemas validate (`PLAN_SCHEMA`, verify's `DECIDE_SCHEMA` shape, `GAPCHECK_SCHEMA`), (c) `remaining_important` / `review_tally` stay correct after a fix round, (d) an unconverged unit yields a draft PR with the `needs-human` label and stays `in-review`, (e) RECAP.md renders in the file view. Design-workflow units: run `design-plan --auto` and `design-plan-critique` and confirm the sonnet dispatches still produce valid `RESEARCH_SCHEMA`/`RESOLVE_SCHEMA` output and the `args`-string guard survives a string payload. SVG guide: validate the template with `python3 -c 'import xml.dom.minidom'` or the Node tag-balance check, never `xmllint`.

## Alternatives considered

- **Merge Challenge + Decide (D4)**: cut. Saves one already-cheap call and breaks the adversarial 3-leaf separation.
- **Script-side context-size preflight (E3)**: cut. Workflow scripts never load diffs (agents compute their own); a script-side preflight cannot see sizes. Size-gating is folded into the per-module gapcheck via a self-computed count.
- **Per-module dimension-reviewer split** (E1's original scope): deferred. 3 dims x N modules multiplies opus runs and loses cross-module interaction findings; revisit only after the scoped verify makes re-review rounds rare.
- **Autonomy hook, aspect-level arbiter, codex second opinion, critique focus hint, synthesize reorder**: deferred as their own follow-ups; out of scope for this epic.

## Sources

- `autocode/impl/skills/impl/scripts/impl-workflow.mjs:6,26,36,193,238-243,245-255,256-261,310-335,337-348,349-362,368,369` (phase pipeline, args guard, partition, gapcheck, fix loop, Push/Hygiene tail, return fields) -- confirmed in the worktree.
- `autocode/design/skills/design-plan/scripts/design-plan-workflow.mjs:122,132,177,213,240,250` (researcher vs synthesis/author sites) -- research finding `d3-researcher-vs-synthesis-sites`.
- `autocode/design/skills/design-plan-critique/scripts/design-critique-workflow.mjs:6,86-96,95` (Resolve wrapper opus; researcher already sonnet) -- research finding `d3-critique-wrapper-model`.
- `autocode/impl/skills/impl-plan/SKILL.md:31,36,40` (planner owns the partition; step 5 edit) -- research finding `impl-plan-step5-edit`.
- `impl-workflow.mjs` `PARTITION_SCHEMA:138-169`, `DECIDE_SCHEMA:101-124`, `PREP_SCHEMA:49`, `GAPCHECK_SCHEMA:171-191`, `PUSH_SCHEMA:132-135` -- research findings `plan-structured-output-schema`, `decide-schema-shape`, `gapcheck-modules-files`, `e1-size-gate-source`, `e1-integration-bucket`, `d5-hygiene-file-classification`.
- `provider/git-remote/github/pr-create.sh:37,56-71`, `pr-status.sh:46,80-83`, `provider/git-remote/contract.md:63` (no `--draft`; `isDraft` readable not settable) -- research finding `convergence-gate-draft-pr`.
- `provider/issue-tracker/github/issue-transition.sh:56` (idempotent `gh label create --force` pattern) -- research finding `needs-human-label`.
- `autocode/design/design-pr-body.md:1-53`, `autocode/pr/agents/pr-hygiene.md:28-31,42-48`, `autocode/pr/skills/pr-create/SKILL.md:24-35,61`, `autocode/impl/skills/impl-push/SKILL.md:20,21,29` (canonical recipe pattern; composer vs hygiene) -- research findings `impl-pr-body-recipe-mirror`, `unit-pr-body-composer`.
- `autocode/design/design-folder.md:42,45,53,61,137-150`, `autocode/_config/guides/CLAUDE.md:3-7` (recap section anchors; SVG diagram line; guide convention) -- research findings `design-folder-recap-edit`, `design-folder-svg-line`, `svg-validation-runtime`.
- `autocode/impl/agents/progress-logger.md:13-31,42-45`, `plugins/autocode/hooks/check-progress-log.sh:46-49` (append format; Stop-hook orphaning) -- research findings `progress-logger-fastpath-format`, `agent-background-support`, `f1-milestone-insertion-points`.
- `autocode/pr/skills/pr-review/SKILL.md:15,20-34,39`, `autocode/impl/skills/impl/scripts/monitor-workflow.mjs:55-70`, `provider/git-remote/github/pr-status.sh:72-84` (review triage; monitor trigger) -- research findings `a2-worktree-detection`, `a2-monitor-trigger-widen`.
- `https://code.claude.com/docs/en/sub-agents` "Spawn nested subagents" (v2.1.172 gate; local `claude --version` = 2.1.201) -- research finding `subagent-spawn-comment-fix`.

## Units

| unit | deliverable | depends-on |
|---|---|---|
| [design-researchers-sonnet](units/design-researchers-sonnet.md) | Downgrade design-workflow researcher/resolve dispatches to sonnet (args guard already present; verify-only) | (none) |
| [workflow-progress-logging](units/workflow-progress-logging.md) | Add per-phase `logProgress` calls, a progress-logger fast path, and correct the stale subagent comment | (none) |
| [svg-diagram-guide](units/svg-diagram-guide.md) | Add `_config/guides/svg-diagram.md` and point the design-folder Architecture bullet at it | workflow-progress-logging |
| [plan-partition-schema](units/plan-partition-schema.md) | Fold the Partition phase into the opus Plan agent's structured output | workflow-progress-logging |
| [scoped-verify-gate](units/scoped-verify-gate.md) | Replace the fix-loop re-review with a scoped verify agent and add the draft-PR convergence gate | plan-partition-schema |
| [per-module-gapcheck](units/per-module-gapcheck.md) | Fan gapcheck out per module with a size gate, whole-diff fallback, and integration bucket | scoped-verify-gate |
| [impl-recap-surface](units/impl-recap-surface.md) | Add the `impl-recap` skill, canonical `impl-pr-body.md`, pr-hygiene/pr-create wiring, and the design-folder recap section | svg-diagram-guide |
| [recap-phase-wiring](units/recap-phase-wiring.md) | Insert the Recap phase before Push and gate the Hygiene phase on changed files | per-module-gapcheck, impl-recap-surface |
| [recap-aware-review](units/recap-aware-review.md) | Extend `pr-review` to act on RECAP.md-anchored comments and delegate to `impl-execute --fix` | recap-phase-wiring |
