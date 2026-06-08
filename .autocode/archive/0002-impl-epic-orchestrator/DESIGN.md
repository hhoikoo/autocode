# Parallel epic orchestration for impl

## Summary

`impl` today drives one design unit at a time: it sets up a worktree and launches a background workflow that carries that single unit from plan to an open PR, then stops. Re-running it starts the next unit by hand. This epic turns `impl` into a stateless, re-entrant epic-level orchestrator. Given a fanned-out design epic, it computes the dependency-ready set of units, launches a per-unit background workflow for each (capped at a configurable default of 3 concurrent), keeps the launch pipeline full as workflows finish, and runs a separate monitoring pass over the open PRs that auto-rebases, fixes CI, and triages review comments. Merging stays gated on explicit user approval; on each merge the orchestrator cascades into newly-unblocked units and, when every unit is done, triggers the existing archive flow. The orchestrator holds no durable storage of its own: the tracker's issue states are the only cross-session source of truth, and live workflow-run tracking is session-scoped (the harness does not expose another session's runs). So the orchestrator is re-entrant within a session and across `--resume`; a fresh re-entry rebuilds the unit set from the tracker and restarts any unit left `in-progress` with no live run rather than assuming it resumes. Every per-phase skill remains individually invocable, so repositories without full automation access can still drive the pieces by hand.

## Background

The per-unit machinery already exists and is unchanged by this epic. What is missing is the layer above it: launching many units in parallel, keeping a concurrency cap full, and monitoring the resulting PRs. A second gap is the surface the monitor needs: there is no single provider call for PR mergeability/CI/review state, and the remediation skills cannot run unattended.

| Component | File | Current behavior |
|---|---|---|
| `impl` launcher | `autocode/impl/skills/impl/SKILL.md` | One interactive `impl-start`, then launches one `impl-workflow`, waits, reports. One unit per invocation. |
| Per-unit workflow | `autocode/impl/skills/impl/scripts/impl-workflow.mjs` | plan -> execute -> review -> challenge -> decide -> fix -> push -> hygiene; ends at PR-open (unit -> `in-review`). |
| Unit setup | `autocode/impl/skills/impl-start/SKILL.md` | `--unit <slug> --auto` already does non-interactive per-unit setup, emits a structured block. |
| Archive | `autocode/impl/skills/impl-archive/SKILL.md` | Already verifies all units done, closes the epic, moves the folder, opens a lightweight PR, and self-merges it with `--admin`. |
| DAG + lifecycle | `autocode/design/design-folder.md` | Unit `depends-on` lives in unit-file frontmatter; `issue-epic-list` returns per-unit status; a unit is workable when all deps are `done`. |
| PR state | `provider/git-remote/github/pr-view` | Raw `gh pr view` passthrough; no normalized mergeable/CI/review contract. |
| Remediation | `pr-rebase`, `pr-fix-ci`, `pr-review` | No `--auto` mode; `AskUserQuestion` gates and prose-only returns block unattended use. |
| Conflict surface | `PROGRESS.md` | Append-only, one block per unit; every dependent unit's rebase touches it. No union merge driver scaffolded. |

## Architecture

The orchestrator runs in the main session. It owns no durable state of its own: it reconstructs everything each turn from two sources of truth, the issue tracker (unit/epic states) and the harness's workflow-run tracking (which units have a live background run). Two background-workflow types do the heavy work off the main context: the existing per-unit `impl-workflow`, and a new `monitor-workflow`. Merging is the only step pinned to the main session, because it requires explicit user approval.

```
                         main session: impl orchestrator (stateless, re-entrant)
                                 |                         ^
   reconstruct state each turn   |                         | re-invoked on <task-notification>
        +------------------------+-------------------+     | (workflow completion) or cron tick
        |                        |                   |     |
        v                        v                   v     |
  issue-epic-list          workflow-run         INDEX.md   |
  (unit/epic status)        tracking          (epic ids)   |
        |                        |                          |
        |  ready set = todo units whose deps are all done   |
        v                                                   |
  launch wave (cap=3, refill as slots free) ----------------+
        |                                   launches background
        v                                                  |
  impl-start --unit --auto  -->  impl-workflow.mjs (bg) ----+--> opens unit PR -> in-review
        |                          (plan..push..hygiene)              |
        v                                                             v
  on user command / cron:  launch monitor-workflow.mjs (bg) --> fan out one checker per in-review PR
        |                                                             |
        |                                          pr-status + --auto rebase / fix-ci / review
        v                                                             |
  read typed per-PR report  <---------------------------------------+
        |
        |  present merge-ready PRs; USER approves
        v
  gh pr merge --admin  -->  unit done  -->  cascade: recompute ready set, launch unblocked
        |
        v
  all units done  -->  impl-archive (self-merges archive PR)  -->  epic closed
```

## Design decisions

1. Stateless, re-entrant orchestrator. The orchestrator stores nothing durable of its own; it recomputes the ready set, the in-flight set, and the done set on every invocation. The done/ready/in-review distinctions come from the tracker (the only cross-session source of truth); the running set comes from the run ids the orchestrator launched in the current session, tracked in its working context, since live workflow-run tracking is session-scoped and a different session cannot enumerate another session's runs (harness research, this session). Rationale: the tracker is already the single source of truth for unit lifecycle (`design-folder.md`), and a stored queue would drift from it across sessions, crashes, and manual merges. A persistent state file would not buy cross-session resume anyway: the harness loses in-flight workflows on session exit (`resumeFromRunId` is same-session only), so the correct recovery on any fresh re-entry is to restart `in-progress` units from the tracker, not to resume a run id. Rejected alternative: a persistent orchestrator state file under `.autocode/`, which would need its own reconciliation against the tracker and still could not revive a dead run.

2. Two-loop split. The launch pipeline is self-sustaining within a session: launching a per-unit workflow is background work the harness tracks, so when one finishes the main loop is re-invoked (`<task-notification>`) and the orchestrator refills the cap. This refill depends on the harness re-invoking the idle main loop on workflow completion; the `Workflow` tool contract states this, though the public docs do not document an idle-REPL wake guarantee (the tool contract governs, as noted in Sources). The monitor/merge loop is human-paced: run on command or on an opt-in cron tick. Rationale: keeping the cap full needs no human input and should not wait for one, whereas merging requires approval and reviews/CI arrive over wall-clock time. Rejected alternative: a single pure-workflow orchestrator, which cannot gate on a user merge decision mid-run and cannot nest workflows.

3. Concurrency cap, default 3, configurable. The cap is on concurrently-running unit workflows. Rationale: each unit workflow itself fans out internally (per-dimension reviewers), so an unbounded wave multiplies fan-out and saturates the agent pool. 3 balances throughput against that. Exposed as a settings key so heavy repos can lower it. Rejected alternative: hardcoding, which gives no escape hatch on constrained machines.

4. Monitoring is its own background workflow. A monitoring pass is a `monitor-workflow` that fans out one checker per in-review PR, runs the `--auto` remediation skills as its agents, and returns a typed per-PR verdict. It never merges. Rationale: the per-PR checks are independent fan-out that should stay off the main context, mirroring `impl-workflow`; merging is the one step that must stay in the main session for approval. Rejected alternative: dispatching monitor subagents directly from the orchestrator's own context, which fills the main window with check/remediation noise.

5. Auto-remediate, gate merge. The monitor auto-runs `pr-rebase`, `pr-fix-ci`, and `pr-review` (triage) on blocked PRs; only the merge needs explicit user approval, and `gh pr merge --admin` is acceptable once approved. Rationale: rebase and CI fixes are unblockers, not outward-facing actions; merging is the irreversible, outward step. This requires adding `--auto` modes to those three skills (decision 6), since they otherwise stop for the user and return only prose.

6. `--auto` modes with structured returns for the remediation skills. `pr-rebase`, `pr-fix-ci`, and `pr-review` gain an `--auto` flag that suppresses their `AskUserQuestion` gates in favor of a structured result that includes a `needs_human` signal (e.g. a rebase whose conflict exceeds the existing 5-file guardrail, or a non-trivial verify failure, returns `needs_human` rather than prompting). Rationale: a workflow's agents cannot call `AskUserQuestion`; a structured stop signal lets the monitor branch and surface only the cases that genuinely need a person. This is the enabler that makes decision 4 feasible.

7. Normalized PR-status provider script. A new `pr-status` git-remote script returns one typed JSON object (state, mergeable, merge-state, CI rollup, review decision, draft, url), and a `pr-find` script maps a unit to its PR number. `pr-find` resolves primarily by the sub-issue key via the GitHub closing-reference link (the `Closes #<key>` in the PR body; GraphQL `closingIssuesReferences`/`closedByPullRequestsReferences`, with `gh pr list --search` as a simpler eventually-consistent fallback), not by a reconstructed branch: the branch shortname is a model-generated slug of the issue summary and is not reproducible across sessions (research finding), so the issue key is the only durable unit->PR handle. Branch-substring match on the `/<key>/` segment is a secondary path. Rationale: the provider boundary owns git-host knowledge (CLAUDE.md single-source-of-truth); scattering raw `gh pr view --json ...` parsing into the orchestrator and monitor would duplicate and leak it. Rejected alternative: inline `gh` calls in the workflow scripts; and unit->PR mapping by reconstructed branch, which the non-deterministic shortname makes unreliable cross-session.

8. `PROGRESS.md` seed at design-folder creation, plus a union merge driver and a `pr-rebase` backstop. The `union` driver is line-based, so it only resolves cleanly when `PROGRESS.md` already exists at the merge-base: today the file is first created by the first unit's `impl-push` (`impl-push/SKILL.md`), so two first-wave units each create it with a `# Progress: <short>` header and `union` concatenates them into a duplicate header with no conflict and no stop (the skill backstop never fires because the driver suppresses the conflict). Fix: seed `.autocode/design/<id>-<short>/PROGRESS.md` with its header when the design folder is created, so it merges to `main` with the design PR and is a common ancestor for every unit before any unit branches; `union` then resolves every append cleanly (research finding, this session). With the seed in place, scaffold `.gitattributes` with the built-in `union` driver for `PROGRESS.md` so the high-frequency append conflict auto-resolves at the git layer (both blocks kept, no markers, rebase never stops). Additionally teach `pr-rebase` an explicit `PROGRESS.md` union resolution, mirroring its existing `INDEX.md` special-case, so repos on an older setup without the `.gitattributes` still auto-resolve. Rationale: `PROGRESS.md` is the one structural shared write during a parallel epic; resolving it mechanically keeps the monitor's auto-rebase from burning a judgment call on every dependent unit. Rejected alternative: moving the `PROGRESS.md` append post-merge via a GitHub Action, which splits in-PR vs post-merge behavior and drops the rollup from the PR diff.

9. Opt-in cron for periodic monitoring, off by default. The launch pipeline self-sustains without cron. For hands-off monitoring while away, the orchestrator offers (a plain prompt at launch, or a `--watch` flag) to schedule a periodic monitoring tick via `CronCreate`, which runs a `monitor-workflow` and emits a `PushNotification` when PRs become merge-ready. Cron never merges. Rationale: the user wants minimal babysitting but explicit merge control; opt-in cron drives remediation and notification without ever crossing the merge gate. Rejected alternative: always-on cron (unwanted by default) or cloud Routines (lose local `gh` auth and stdio providers).

10. Failure-resistant reconciliation. "Live workflow run" means a run id this session launched and has not yet seen complete; the harness does not expose another session's runs (harness research). On each re-entry, a unit that is `in-progress` in the tracker but has no live run in this session is classified as needing recovery: within the same session this is a genuine crash; on a fresh session or `--resume` it is the expected state (the run did not survive session exit). In both cases the orchestrator surfaces the unit and offers restart, and never silently relaunches over a run still live in this session. `resumeFromRunId` is offered only for a run launched in the current session (the only case it works, per the same-session-only tool contract); a cross-session in-progress unit is restarted, not resumed. Restart is not a bare relaunch: `impl-start`/`git-create-branch` hard-stop on the dead run's leftover branch (research finding), so restart first removes the dead worktree, deletes the leftover branch, and resets the sub-issue to `todo`, then lets the normal wave relaunch it; before any deletion, reconciliation confirms by issue key that no open PR exists (a run that died after push leaves a PR and is in-review, not needs-recovery). Rationale: double-launching a unit live in this session corrupts its worktree and PR; assuming a dead cross-session run resumes would strand the unit forever; relaunching without cleanup would error on the existing branch.

11. Manual fallback preserved. The orchestrator is an automation layer over the existing phase skills, not a replacement; `impl-start`, `impl-plan`, `impl-execute`, the `impl-critique-*` skills, `impl-push`, `pr-rebase`, `pr-fix-ci`, `pr-review`, and `impl-archive` stay individually invocable. Rationale: in repositories where the user lacks the access for full automation, hand-driving the documented skills must still work.

## Runtime flow

1. Invoke `impl --from-design <id|shortname>` (epic mode). The orchestrator reads `INDEX.md` to resolve the epic and calls `issue-epic-list --epic <id>` for per-unit `{slug, status}`; it reads each unit file's `depends-on` from the design folder.
2. Reconcile: for each unit, resolve its PR by sub-issue key (`pr-find <key>`, the `Closes`-link lookup) and classify: done (sub-issue closed), in-review (an open PR exists, even if the tracker status still reads `in-progress` from a run that died between push and the status flip), running (a run id launched this session, not yet complete), or needs-recovery (`in-progress`, no open PR, no live run in this session). The PR-existence check by issue key, not the tracker status alone, is what prevents deleting a branch out from under a live PR. Surface needs-recovery units with a restart choice (resume only when the run id belongs to this session). Worktree paths are recovered from `git worktree list --porcelain` by matching the `/<key>/` segment of each worktree's branch (the issue key is embedded in the branch; the shortname tail is a non-reproducible slug), not from any stored launch output, so a fresh session can still locate them.

   Restart of a needs-recovery unit (decision 10): a unit that died before `impl-push` has no PR but may hold a worktree, a branch, and partial commits; `git-create-branch` hard-stops on an existing branch and `impl-start` has no reuse path (research finding). So restart first cleans up: remove the dead worktree (`git worktree remove --force`), delete the leftover branch, and transition the sub-issue back to `todo`; the unit then re-enters the ready set and launches fresh in the next wave. The partial work is discarded (the unit never reached review); note this in the surfaced choice.
3. Compute the ready set: `todo` units whose `depends-on` are all `done`. Launch units up to the cap (default 3) minus the running count: `impl-start --unit <slug> --auto`, then the `impl-workflow` for each. Report the wave and what is queued.
4. Each per-unit workflow runs to an open PR and exits; its completion re-invokes the orchestrator, which refills the cap with the next queued ready unit. This repeats with no user input until the cap cannot be filled (all remaining units blocked or in-flight).
5. Monitoring (on user command, or an opt-in cron tick): launch `monitor-workflow`. It fans out one checker per in-review PR; each reads `pr-status`, and if blocked runs the matching `--auto` remediation (`pr-rebase` on conflict, `pr-fix-ci` on red CI, `pr-review` on review comments), returning `{pr, slug, state, action_taken, merge_ready, needs_human}`.
6. The orchestrator reads the report, surfaces `needs_human` cases, and presents merge-ready PRs. On cron, it emits a `PushNotification` instead of blocking.
7. The user approves specific PRs; the orchestrator merges them (`gh pr merge --admin` allowed). Each merge flips a unit to `done`.
8. Cascade in the same turn: recompute the ready set (newly-unblocked units), prune the merged units' worktrees, and launch the next wave under the cap. Merging unit A may put sibling B's PR into conflict; the next monitoring pass auto-rebases it.
9. When every unit is `done`, the orchestrator invokes `impl-archive` with the epic id (so its multiple-epic prompt never fires); archive self-merges its PR and closes the epic.

Flat single-unit designs collapse this to a wave of one with no cascade; archive still runs. Bare ticket / `type: desc` invocations keep today's single-unit launch behavior, with monitoring applicable to the one PR but no cascade.

## Edge cases and error handling

- Empty ready set with units remaining: report which units are blocked on which unfinished deps; do nothing else.
- Cap smaller than the ready set: launch up to the cap, report the queued remainder; refill is automatic on workflow completion. Log what was queued (no silent truncation).
- Crashed/abandoned unit (in-progress, no live run): surface and offer resume/restart; never auto-relaunch.
- `pr-rebase --auto` hitting the >5-file conflict guardrail or a non-trivial verify failure: return `needs_human`; the orchestrator surfaces it rather than the workflow stalling.
- `monitor-workflow` over zero in-review PRs: returns an empty report; the orchestrator reports nothing actionable.
- Cron tick in a headless context that lacks `gh` auth or stdio providers: the monitor pass fails fast and notifies; document that local-session cron is the supported path.
- Single-unit / flat epic and the bare-ticket path: no cascade, no epic close beyond the one unit; archive handles flat.

## Testing strategy

- Provider scripts (`pr-status`, `pr-find`): unit-level shell tests with mocked `gh` output (fixture JSON), asserting the normalized shape and the unit->PR mapping; follow the existing `provider/` test conventions.
- `--auto` skill modes: dry-run each skill with `--auto` on a scratch branch and assert the structured result block (including `needs_human` on a forced large conflict and a forced verify failure).
- `.gitattributes` union driver: construct two branches each appending a distinct `PROGRESS.md` block, rebase one onto the other, assert both blocks survive with no conflict markers.
- Orchestrator skills: validated by `scripts/check-plugin-shape.sh` (shim/source shape) plus a manual end-to-end dry run on a small two-unit epic (one dependent), exercising launch, cascade, and archive. No automated harness exists for full skill runs; the dry run is the acceptance gate.
- `monitor-workflow`: exercised in the same dry run with one PR needing a rebase and one merge-ready, asserting the typed verdicts and that no merge happens without approval.

## Alternatives considered

- Pure-workflow orchestrator (no main-session loop): rejected because a workflow cannot pause for a user merge decision or nest further workflows, and merging must stay user-gated.
- Storing orchestrator state in a file: rejected; the tracker is already authoritative and a file would need reconciliation against it regardless (decision 1).
- Driving the remediation skills as-is, escalating on their existing prompts: rejected because unattended/cron runs would stall at any `AskUserQuestion`, and the skills return no machine-readable verdict to branch on (decisions 4, 6).

## Sources

- `autocode/impl/skills/impl/SKILL.md`, `autocode/impl/skills/impl/scripts/impl-workflow.mjs`, `autocode/impl/CLAUDE.md`: current launcher and per-unit workflow shape, the launch-call contract, and the in-workflow fan-out pattern. Read this session.
- `autocode/impl/skills/impl-start/SKILL.md`: `--unit <slug> --auto` non-interactive setup and its structured result block. Read this session.
- `autocode/impl/skills/impl-archive/SKILL.md`: archive already self-merges with `--admin` (step 8) and prompts only on multiple active epics. Read this session.
- `autocode/design/design-folder.md`: unit DAG, `depends-on` in unit frontmatter, `issue-epic-list` discovery, lifecycle states, `PROGRESS.md` format and shared-append nature. Read this session.
- `provider/run.sh`, `provider/git-remote/github/*`, `provider/issue-tracker/github/*`, `provider/ci/github/*`: the provider surface; `pr-view` is a raw passthrough with no normalized contract, and no PR-status/PR-find/PR-approval call exists (gaps confirmed). Read this session.
- `autocode/pr/skills/{pr-rebase,pr-fix-ci,pr-review}/SKILL.md`: no `--auto` mode; `pr-rebase` has 3 `AskUserQuestion` gates and the `INDEX.md` id-collision special-case to mirror for `PROGRESS.md`; prose-only returns. Read this session.
- `autocode/_config/guides/worktree.md`: worktree creation already prefers `EnterWorktree` with a bare-git fallback; teardown via `ExitWorktree`. Read this session.
- `autocode/_config/settings-schema.md`, `autocode/_config/conventions/issue-types.md`: settings key authoring rules and the `epic`/`story`/`task`/`bug` type set. Read this session.
- Claude Code `Workflow` and `ScheduleWakeup` tool contracts (this session's tool definitions): background workflows return a run id immediately and re-invoke the main loop on completion ("when harness-tracked work finishes, you are re-invoked automatically"); `CronCreate` schedules session-scoped ticks; `PushNotification` sends desktop/phone alerts; `EnterWorktree`/`ExitWorktree` change session cwd and are the preferred worktree primitives. The public docs at code.claude.com describe a synchronous workflow model that does not match this harness; the tool contract governs.
- Harness cross-session semantics (`claude-code-guide`, this session, citing `code.claude.com/docs/en/{workflows,scheduled-tasks,tools-reference,sub-agents,interactive-mode}`): workflow-run tracking and `TaskList` are session-scoped; `resumeFromRunId` is same-session only ("the next session starts the workflow fresh"); in-flight workflows are lost on session exit; `CronCreate` tasks are session-scoped, restored on `--resume`/`--continue` within a 7-day auto-expiry, and fire only while the session is open and idle between turns; no documented guarantee wakes a closed/detached REPL on background completion. This bounds the re-entrancy claim to within-session + `--resume` and drives the restart-not-resume reconciliation (decisions 1, 10).
- `impl-push/SKILL.md` (this session): `PROGRESS.md` is first created by the first unit's `impl-push`, not seeded at fan-out or design time; nothing earlier creates it. This is why concurrent first-wave units collide on the header under a line-based `union` driver, and why decision 8 seeds the header at design-folder creation.
- `EnterWorktree`/`git worktree` (this session): a unit's worktree directory name is set by the tool and is not reconstructable from the slug alone; the durable mapping from a unit branch to its worktree path is `git worktree list --porcelain`, used for stateless recovery of in-review units' worktrees.
- User decisions (this session): concurrency cap default 3 and configurable; auto-remediate with user-gated merge and `--admin` allowed; opt-in cron only; failure-resistant reconciliation; worktree-tool over bare git; manual invocability preserved; design layer out of scope (owned separately).

## Units

| Unit | Deliverable | depends-on |
|---|---|---|
| [pr-status-provider](units/pr-status-provider.md) | Normalized `pr-status` and `pr-find` git-remote provider scripts | none |
| [pr-rebase-auto](units/pr-rebase-auto.md) | `pr-rebase --auto` with structured `needs_human` return, plus the `PROGRESS.md` union resolution | none |
| [pr-ci-review-auto](units/pr-ci-review-auto.md) | `--auto` modes with structured returns for `pr-fix-ci` and `pr-review` | none |
| [progress-union-gitattributes](units/progress-union-gitattributes.md) | `.gitattributes` `PROGRESS.md merge=union` scaffolding in setup + update, plus seeding the `PROGRESS.md` header at design-folder creation so `union` has a common ancestor | none |
| [impl-orchestrator-core](units/impl-orchestrator-core.md) | `impl` rewritten as the stateless re-entrant launch/cascade/archive orchestrator with the concurrency-cap setting | pr-status-provider |
| [impl-orchestrator-monitor](units/impl-orchestrator-monitor.md) | `monitor-workflow` plus orchestrator monitoring, user-gated merge, notifications, and opt-in cron | impl-orchestrator-core, pr-status-provider, pr-rebase-auto, pr-ci-review-auto |

## Critique log

### Iteration 1

- Q: Does cross-session re-entrancy hold given the harness? A: No. Workflow-run tracking and `TaskList` are session-scoped, `resumeFromRunId` is same-session only, in-flight workflows die on session exit (harness research). Re-scoped decision 1 to within-session + `--resume`; "live run" = a run id launched this session; cross-session in-progress units restart from the tracker, not resume. No durable state needed (it would not revive a dead run).
- Q: Can a running workflow be mapped back to its unit/epic? A: No harness handle (`meta.name` is the static `impl-unit`; codebase research). The orchestrator tracks the run ids it launched this session in working context; the cap counts those. Noted as a per-session-orchestrator cap (concurrent epics in one session contend).
- Q: Crashed-unit recovery via `resumeFromRunId`? A: Only valid same-session; offer restart otherwise (decision 10 rewritten).
- Q: Worktree path recovery for in-review units without stored state? A: `git worktree list --porcelain` keyed by the unit branch (deterministic from issue key); `EnterWorktree` dir name is tool-internal and not reconstructable from the slug (research). Added to runtime-flow step 2 and the orchestrator/monitor units.
- Q: Does the `PROGRESS.md union` driver resolve the first-creation collision? A: No. `impl-push` creates the file (not seeded at fan-out), so two first-wave units each write the header and `union` duplicates it silently (research). Resolution (user decision): seed the `# Progress:` header at design-folder creation so it is a common ancestor; decision 8 and the `progress-union-gitattributes` unit updated; the unit test claim corrected.
- Q: Refill loop depends on idle-REPL wake on workflow completion? A: Tool contract asserts it; public docs do not document an idle-wake guarantee. Tool contract governs (noted in decision 2 and Sources).

### Iteration 2

- Q: Can the orchestrator reconstruct a unit's branch from `issue-epic-list` to find its PR cross-session? A: No. The branch `<short>` is a model-generated slug of the issue summary (`git-create-branch/SKILL.md:34`), not reproducible and divergent if the title is edited; the unit slug is not used in the branch (research). Resolution: `pr-find` keyed by sub-issue key via the `Closes` link (GraphQL `closing/closedBy...References`), branch as secondary; worktree recovery matches the `/<key>/` branch segment (the issue key is embedded). Decision 7, pr-status-provider unit, core/monitor reconciliation updated.
- Q: Is "restart in-progress units" safe over a dead run's leftovers? A: No. A unit dies before `impl-push` so it holds a branch + worktree + partial commits; `git-create-branch` hard-stops on the existing branch and `impl-start` has no reuse path (research). Resolution: restart cleans up first (remove worktree, delete branch, reset sub-issue to `todo`) then relaunches via the normal wave; before any deletion, reconciliation confirms by issue key that no open PR exists (a run that died after push is in-review, not needs-recovery). Decision 10 and runtime-flow step 2 updated.
- DAG change: reconciliation's issue-key PR check makes `impl-orchestrator-core` depend on `pr-status-provider` (was none). Units table and frontmatter updated; no cycle (`pr-status-provider` is a leaf).
