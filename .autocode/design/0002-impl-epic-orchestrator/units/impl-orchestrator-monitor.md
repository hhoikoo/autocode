---
depends-on: [impl-orchestrator-core, pr-status-provider, pr-rebase-auto, pr-ci-review-auto]
type: story
---

# Monitor workflow, user-gated merge, notifications, and opt-in cron

## Summary

The launch/cascade orchestrator (`impl-orchestrator-core`) opens unit PRs but does nothing about them once open: PRs drift out of date, CI goes red, and review comments pile up with no unattended remediation, and there is no surface to tell the user which PRs are merge-ready. This unit adds the monitoring layer. A new `monitor-workflow.mjs` background workflow (sibling of `impl-workflow.mjs`) fans out one checker agent per in-review PR; each checker reads the normalized `pr-status` provider, runs the matching `--auto` remediation skill when blocked (`pr-rebase` on conflict, `pr-fix-ci` on red CI, `pr-review` on review comments), and returns a typed per-PR verdict. The workflow never merges. The orchestrator (`impl` `SKILL.md`) gains the monitoring/merge/cron layer on top: launch the monitor on user command or an opt-in cron tick, read the typed report, surface `needs_human` cases, present merge-ready PRs, and merge only on explicit user approval (`pr-merge <pr> --admin`), handing each merge back to the core cascade. Merge-ready PRs (and every cron tick) emit a `PushNotification` so the user knows to give the merge command. Cron is off by default, offered at launch via a plain prompt or a `--watch` flag, runs remediation and notification but never merges, and is documented as a local-session-only path.

## Implementation

A new background workflow script plus an extension of the orchestrator skill and its docs. The monitor is the read/remediate half; merge stays in the main session behind user approval (DESIGN.md decisions 4, 5). This unit branches after `impl-orchestrator-core` merges, so the `SKILL.md` extension does not conflict with the core rewrite.

### Files to create

- `autocode/impl/skills/impl/scripts/monitor-workflow.mjs`: the monitoring background workflow.

### Files to modify

- `autocode/impl/skills/impl/SKILL.md`: extend the orchestrator (rewritten by `impl-orchestrator-core`) with the monitoring trigger, the typed-report read, the user-gated merge, the merge-ready notification, and the opt-in cron. Add `--watch` to `## Args`.
- `autocode/impl/CLAUDE.md`: document `monitor-workflow` alongside `impl-workflow` (the second background-workflow type), the user-gated merge, and the opt-in cron.
- `plugins/autocode/skills/impl/SKILL.md` (shim): only if the `description` needs the monitoring/`--watch` capability surfaced; the shim forwards `$ARGUMENTS`, so no arg edit is required (mirrors the sibling skill-unit findings). Confirm at implementation time; do not edit if the description already reads accurately.

```
 main session: impl orchestrator
   |  user command / cron tick
   v
 launch monitor-workflow.mjs (Workflow tool, background)
   |
   |  in-review PRs = issue-epic-list rows with an open PR (pr-find <issue-key> per unit)
   v
 parallel( one checker agent per in-review PR )
   |        each: pr-status -> branch on state
   |          conflicting           -> pr-rebase  --auto
   |          ci=failing            -> pr-fix-ci  --auto
   |          changes_requested     -> pr-review  --auto
   |          mergeable+green+approved -> merge_ready
   v
 typed report: [{ pr, slug, state, action_taken, merge_ready, needs_human, reason }]
   |
   v  (back in main session, on workflow completion)
 surface needs_human  ·  present merge-ready  ·  PushNotification
   |
   |  USER approves specific PRs
   v
 pr-merge <pr> --admin  ->  hand back to core cascade (recompute ready set, launch next wave)
```

### `monitor-workflow.mjs` shape

Mirror `impl-workflow.mjs` (`autocode/impl/skills/impl/scripts/impl-workflow.mjs`): an exported `meta` object, the `args`-derived constants, the `skill()` / `inWt` / `follow()` / `readOnly` helpers (lines 29-32), and the `agent()` / `parallel()` / `phase()` / `log()` workflow globals. Plain JS, not TS. The runtime forbids `Date.now()`, `Math.random()`, and argless `new Date()`; resolve all paths from `args.homeDir` (research finding; the same constraints the existing script obeys). Subagents cannot spawn subagents, so all fan-out lives in this workflow runtime, as in `impl-workflow.mjs:26`.

Args from the orchestrator launcher: `{ homeDir, prs }`, where `prs` is the in-review set the orchestrator already computed, each entry `{ pr, slug, branch, worktree }`. The orchestrator owns discovery (`issue-epic-list` + `pr-find` per unit, `pr-status-provider` contract); the workflow receives the resolved list so it does not re-derive epic state off the main context. Each unit worktree persists while its PR is open (`ExitWorktree action: keep`, DESIGN.md / `worktree.md`), so `pr-rebase --auto` has a worktree to `cd` into. The orchestrator resolves `worktree` from `git worktree list --porcelain` keyed by `branch` (the worktree dir name is `EnterWorktree`-internal and not reconstructable from the slug), so the path is recovered even for PRs opened by a prior session, not read from any stored launch output. If no worktree is found for an open PR (e.g. pruned out of band), the orchestrator recreates one for that branch before launching the monitor, or the checker returns `needs_human` rather than `cd`-ing into a missing path.

Per-PR checker (fanned out via `parallel(prs.map((p) => () => agent(...)))`, mirroring `impl-workflow.mjs:139`):

1. Read `pr-status` for the PR via `provider/run.sh git-remote pr-status <pr>` (the `pr-status-provider` unit's typed object: `state`, `mergeable`, `ci`, `reviewDecision`, `isDraft`, ...).
2. Short-circuit on `state` `merged`/`closed` (already gone) and on `isDraft` (not ready): no action, not merge-ready.
3. Branch on the first applicable blocked condition and run exactly that one `--auto` remediation as the checker's action this pass (re-checked next pass; one remediation per checker keeps the verdict unambiguous):
   - `mergeable == "conflicting"` -> `pr-rebase --auto` in the unit worktree; consume its `{ rebased, conflicts_resolved, verify, needs_human, reason }` (`pr-rebase-auto` contract).
   - `ci == "failing"` -> `pr-fix-ci --auto`; consume its `{ pr, fixed, ci, needs_human, reason }` (`pr-ci-review-auto` contract).
   - `reviewDecision == "changes_requested"` -> `pr-review --auto`; consume its `{ pr, applied, deferred, needs_human, reason }` (`pr-ci-review-auto` contract).
4. Compute `merge_ready`: `state == "open"`, not draft, `mergeable == "mergeable"`, `ci == "passing"`, `reviewDecision` in `{approved, none}`, and no remediation was needed this pass. The workflow never merges (DESIGN.md decision 4).
5. Return the typed verdict via a JSON `schema` on the `agent()` call (mirror how `impl-workflow.mjs` pins `PREP_SCHEMA` / `FINDINGS_SCHEMA` etc., lines 34-126):

   ```
   { pr: int, slug: string, state: string,
     action_taken: "none" | "rebase" | "fix-ci" | "review",
     merge_ready: bool, needs_human: bool, reason: string }
   ```

   `needs_human` is the OR of the chosen remediation's `needs_human` (a >5-file conflict, a non-trivial verify failure, a missing build convention, a deferred low-confidence review comment); `reason` carries that skill's reason. A checker that errors out (e.g. `pr-status` non-zero) returns `needs_human: true` with the failure in `reason` rather than throwing, so one bad PR does not sink the batch (`impl-workflow.mjs:150` filters falsy results; match that resilience).

The workflow returns the array of verdicts (and a short tally) as its final value. Over zero in-review PRs it returns an empty report (DESIGN.md edge case); the orchestrator reports nothing actionable.

### Orchestrator extension (`SKILL.md`)

Layer onto the core orchestrator (does not re-specify launch/cascade, owned by `impl-orchestrator-core`):

- Trigger: monitoring runs on an explicit user command (e.g. the user asks to check the PRs) or an opt-in cron tick, not automatically on every turn (DESIGN.md decision 2: the merge loop is human-paced).
- Launch: compute the in-review set (`issue-epic-list` rows whose unit PR is open, via `pr-find <issue-key>` per unit, the `Closes`-link lookup, not a reconstructed branch), read each open PR's head branch from the `pr-find`/`pr-status` result, map it to a `worktree` via `git worktree list --porcelain` on the `/<key>/` segment, and launch `monitor-workflow.mjs` through the Workflow tool with `args { homeDir, prs }`. The workflow runs background; its completion re-invokes the orchestrator (same mechanism as `impl-workflow`).
- Read the report: surface every `needs_human` verdict with its `reason` (the cases a person must handle); list `merge_ready` PRs.
- User-gated merge: present the merge-ready PRs and wait for explicit approval. Only on approval, merge the named PRs via `provider/run.sh git-remote pr-merge <pr> --admin` (`pr-merge.sh` exists and takes `--admin`). Never merge without approval; the workflow never merges (DESIGN.md decision 5).
- Hand back to the core cascade: each merge flips its unit to `done`; the orchestrator recomputes the ready set and launches the next wave (logic owned by `impl-orchestrator-core`; this unit invokes it, does not duplicate it).
- Notifications: emit a `PushNotification` when PRs become merge-ready, and on every cron tick, so the user knows to give the merge command. Keep the message under 200 chars, one line, lead with the actionable fact (e.g. `2 PRs merge-ready: <slug>, <slug>`). The tool is Anthropic-hosted desktop/phone (Remote Control); a "not sent" result is expected on Bedrock/Vertex/Foundry and is non-fatal (verified tool contract this session). Do not block on it.

### Opt-in cron (`--watch`)

- Off by default; the launch pipeline self-sustains without it (DESIGN.md decision 9).
- Offer at launch via a plain prompt (NOT `AskUserQuestion`), or accept a `--watch` flag on `impl`. On opt-in, schedule a periodic monitoring tick with `CronCreate` (verified this session): session-scoped (in-memory, `durable` left default false), standard 5-field cron, fires only while the REPL is idle, min 1-minute period. Pick an off-`:00`/`:30` minute when the period allows. The cron prompt re-launches `monitor-workflow` (remediation + `PushNotification`) and never crosses the merge gate.
- Tell the user the recurring cron auto-expires after 7 days (tool contract), that it is session-scoped (it stops when the session exits and is restored only on `--resume`/`--continue` within the 7-day window, per harness research), and that it fires only while the session is open and idle between turns with no catch-up for missed fires. Provide the `CronCreate` job id so it can be cancelled via `CronDelete`.
- Document that local-session cron is the supported path: headless contexts and cloud Routines lose local `gh` auth and the stdio providers, so a tick there fails fast (the monitor pass surfaces the failure and notifies); do not schedule a Routine for this (DESIGN.md decision 9, edge case).

### Tests that prove it

Per DESIGN.md testing strategy (the `monitor-workflow` row and the orchestrator dry run):

- `check-plugin-shape.sh` passes (shim/source shape unchanged for the skill; the workflow script is not a shim).
- Manual end-to-end dry run on the small two-unit epic from the core unit's gate, extended so one PR needs a rebase and one is merge-ready: assert the monitor returns the two typed verdicts (`action_taken: "rebase"` for the first, `merge_ready: true` for the second), and that no merge happens without explicit approval.
- After approving the merge-ready PR, assert `pr-merge --admin` runs and the cascade launches the now-unblocked dependent unit (exercises the hand-back to core).
- Cron opt-in: assert the plain-prompt offer (not `AskUserQuestion`), that declining schedules nothing, and that accepting creates exactly one session-scoped `CronCreate` job whose prompt runs the monitor and never merges.
- Notification: assert a `PushNotification` fires when a PR becomes merge-ready and on a cron tick; a "not sent" result does not abort the flow.

No automated harness runs full workflow/skill bodies; the dry run is the acceptance gate (DESIGN.md testing strategy).
</content>
</invoke>
