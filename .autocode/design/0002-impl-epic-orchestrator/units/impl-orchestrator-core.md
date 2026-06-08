---
depends-on: [pr-status-provider]
type: story
---

# Stateless re-entrant epic orchestrator for impl

## Summary

Rewrite `impl` from a one-unit launcher into the stateless, re-entrant epic orchestrator. Given a fanned-out design epic, it reconstructs all state each turn (never from its own durable storage): the issue tracker is the cross-session source of truth for done / in-review / todo, and the running set is the run ids it launched in the current session (live workflow-run tracking is session-scoped; the harness does not expose another session's runs). It reconciles each unit into done / in-review / running / needs-recovery, computes the dependency-ready set, launches a capped wave of per-unit background workflows, refills the cap as workflows finish (the harness re-invokes the main loop on completion within the session), cascades into newly-unblocked units when the user merges a unit, prunes merged units' worktrees, and invokes the existing `impl-archive` when every unit is done. The concurrency cap is a new shared setting (`impl.max-concurrent-units`, default 3). This unit owns the launch / cascade / archive layer and the cap setting; the monitoring, user-gated merge, notification, and cron layers are a separate dependent unit that extends the same files. Argument routing splits epic mode (`--from-design <id|shortname>` and flat designs) from today's single-unit launch (bare ticket / `<type>: <desc>`); the manual per-phase skills stay individually invocable.

## Implementation

Deliverable: `impl` runs an epic to completion as a self-sustaining background launch pipeline plus a user-gated merge/cascade/archive finish, holding no durable state of its own.

### Files modified

| File | Role |
|---|---|
| `autocode/impl/skills/impl/SKILL.md` | Real skill body. Replace the single-unit launcher workflow with the orchestrator: arg routing, discovery, reconciliation, ready-set computation, capped wave launch, refill-on-completion, merge-driven cascade, worktree pruning, archive trigger. Single-unit path retained as the bare-ticket branch. Leave a clear `## Monitoring` seam (named but deferred) for the monitor unit to fill. |
| `plugins/autocode/skills/impl/SKILL.md` | Shim. Update `description` frontmatter to reflect the epic orchestrator (currently describes a one-unit launcher). Body `@`-read line and `$ARGUMENTS` forwarding unchanged. |
| `autocode/impl/CLAUDE.md` | Feature-set doc. Reframe `impl` from "orchestrate one design unit" to "orchestrate an epic"; keep the per-phase-skill catalog. Leave the monitor unit room to add its workflow/skill entries. |
| `autocode/_config/settings-schema.md` | Add the `impl.*` top-level namespace (shared) to the namespace table and an `impl.max-concurrent-units` row (integer, default 3) to the shared-keys table. Adding a namespace requires documenting its scope here per the file's own authoring rules. |
| `plugins/autocode/skills/autocode-setup/scripts/write-settings.sh` | Emit `impl.max-concurrent-units` into the shared `settings.json` output. Add a `--max-concurrent-units=<n>` arg (default 3 when omitted) merged into the shared JSON alongside `provider`. |

### Orchestrator behavior (in `impl/SKILL.md`)

Arg routing, first step:
- `--from-design <id|shortname>`, or a current worktree already set up for a unit -> epic mode (the orchestrator).
- Bare `<ticket-id>` / `<type>: <description>` -> today's single-unit launch: one `impl-start` + one `impl-workflow`, no cascade, no archive. Unchanged contract.
- A flat (no `units/`) design under `--from-design` -> epic mode collapsed to a wave of one; archive still runs.

Discovery (re-run every turn, no caching):
1. Resolve the epic from `.autocode/design/INDEX.md` (active rows) and the `--from-design` selector; glob the folder.
2. `provider/run.sh issue-tracker issue-epic-list --epic <id>` -> per-unit `{key, summary, status, type, parent}` and the epic row, matched by marker. `issue-epic-list` does not return `depends-on`.
3. Read each unit's `depends-on` from `.autocode/design/<id>-<short>/units/<slug>.md` frontmatter.

Reconciliation (decision 10): classify each unit from the tracker status, an issue-key PR lookup, and this session's launched run ids ("live run" = a run id launched in the current session, not yet seen complete; the harness does not expose another session's runs). Resolve each unit's PR up front with `pr-find <issue-key>` (the `Closes`-link lookup), since the tracker status alone can lag a run that died between push and the status flip:
- `done`: sub-issue closed.
- `in-review`: an open PR exists for the sub-issue key (trust the PR, not just a possibly-stale `in-progress` status). Recover its worktree path from `git worktree list --porcelain` by matching the `/<key>/` segment of each worktree's branch (the issue key is embedded in the branch `<type>/<key>/<short>`; the shortname tail is a model-generated slug and is not reproducible), not from any stored launch output, so a fresh session can still locate it.
- running: `in-progress`, no open PR, with a live run in this session.
- needs-recovery: `in-progress`, no open PR, no live run in this session. Within the same session this is a genuine crash; on a fresh session or `--resume` it is expected (the run did not survive session exit). Offer `Workflow` `resumeFromRunId` only when the run id belongs to this session (the only case it works, same-session-only contract); otherwise restart. Restart is not a bare relaunch: `git-create-branch` hard-stops on the dead run's leftover branch and `impl-start` has no reuse path, so restart first removes the dead worktree (`git worktree remove --force <path>`), deletes the leftover branch, and transitions the sub-issue back to `todo`; the unit then re-enters the ready set and launches fresh in the next wave (partial pre-push work is discarded; note this in the surfaced choice). Never silently relaunch over a run still live in this session.

Ready set: `todo` units whose every `depends-on` slug maps to a `done` unit.

Capped wave launch:
- Read `impl.max-concurrent-units` (default 3) from the shared settings via the config dir.
- Slots = cap minus running count, where running count is the run ids this session launched and not yet seen complete. The cap is per-session-orchestrator: if one session drives two epics, their running units share the one cap (contend); this matches the session-scoped run tracking and is acceptable.
- Launch up to `slots` ready units; for each: `impl-start --unit <slug> --auto` (capture the structured block: worktree path, branch, slug, unit_key, epic_key, design_id), then a background `Workflow` over `impl-workflow.mjs` with `args: { homeDir, worktree, slug, base, dims }` exactly as the current launcher does (`homeDir` from `echo "$HOME"`; `base` = default branch via `git symbolic-ref --short refs/remotes/origin/HEAD` stripped of `origin/`). The per-unit `impl-workflow` is unchanged by this unit.
- Report the launched wave and the queued remainder; never silently truncate.

Self-sustaining refill (decision 2): each per-unit workflow returns a run id immediately and runs in the background; record that run id in working context (it is the running-set evidence and is session-scoped). On its completion the harness re-invokes the main loop via `<task-notification>` within the session (the refill relies on this idle-loop re-invocation; the `Workflow` tool contract asserts it, the public docs do not document an idle-REPL wake guarantee). On re-entry the orchestrator re-runs discovery + reconciliation and refills empty slots from the ready set, with no user input, until the cap cannot be filled (all remaining units blocked or in-flight).

Merge-driven cascade (the merge gate itself is the monitor unit's; this unit owns the post-merge cascade it triggers): when a unit's PR merges (unit -> `done`), in the same turn recompute the ready set over newly-unblocked units, prune each merged unit's worktree, and launch the next wave under the cap.

Worktree pruning: prefer the worktree tool (`ExitWorktree`); a merged unit's worktree is typically not the current session's, so the tool-unavailable fallback is `git worktree remove <path>` per `autocode/_config/guides/worktree.md`. Note the nuance in the skill: `ExitWorktree` only removes worktrees it created this session, so a worktree merged from another session falls to the bare-git path.

Archive trigger: when every unit is `done`, invoke `impl-archive` passing the epic id explicitly so its multiple-active-epic `AskUserQuestion` never fires. `impl-archive` already self-merges its PR and closes the epic; no change there.

### Monitoring seam (deferred to the dependent unit)

This unit launches and cascades but does not monitor or merge. Name a `## Monitoring` section in `impl/SKILL.md` as the integration point and stop there: the `impl-orchestrator-monitor` unit (depends on this) adds `monitor-workflow`, the user-gated merge, notifications, and opt-in cron. Because that unit branches after this one merges, the two never edit `impl/SKILL.md` or `impl/CLAUDE.md` in parallel.

### Settings key

`impl.max-concurrent-units`: integer, default 3, shared (`settings.json`). New top-level namespace `impl.*` -> shared. Two edits required and both in scope here:
- `settings-schema.md`: add the namespace-scope row and the key row.
- `write-settings.sh`: accept `--max-concurrent-units=<n>` (default 3) and emit `{"impl": {"max-concurrent-units": n}}` into the shared object.

### Tests

- `scripts/check-plugin-shape.sh`: shim/source shape for `impl/SKILL.md` (real body-only, shim frontmatter-only) stays green.
- `write-settings.sh`: shell test asserting `--scope=shared` output includes `impl.max-concurrent-units` defaulting to 3 and honoring an explicit `--max-concurrent-units`, alongside the existing `provider` assertions.
- Manual end-to-end dry run on a small two-unit epic (one dependent): assert the first wave launches under the cap, the dependent stays queued, refill fires on the first workflow's completion, a merge cascades into the dependent, the merged worktree is pruned, and archive runs once both units are done. No automated harness exists for full skill runs; this dry run is the acceptance gate.

### Out of scope

`monitor-workflow`, the `pr-status`/`pr-find` provider scripts, the `--auto` remediation modes, the user-gated merge mechanics, `PushNotification`, and cron: all owned by sibling units. This unit consumes `pr-find <issue-key>` for reconciliation (hence the `pr-status-provider` dependency) but does not build it. It leaves the merge step as the seam the monitor unit fills.
