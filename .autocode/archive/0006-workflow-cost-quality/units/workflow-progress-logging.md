---
depends-on: []
type: task
---

# Workflow-driven per-phase progress logging

## Summary

Make impl-workflow.mjs log its own progress. Today progress logging rides a Stop hook (`plugins/autocode/hooks/check-progress-log.sh`) that fires on new commits in the standalone `impl-execute` flow, but under fan-out the orchestrator cwd has no `.impl-context` and HEAD never moves there, so per-phase progress goes unrecorded. Add a `logProgress(phase, note)` helper that makes an awaited sonnet `progress-logger` call at four milestones (Plan, Execute/Commit, GapCheck, Fix), give `progress-logger.md` a facts-provided fast path that appends a supplied note verbatim under a `## <UTC> [<phase>]` heading and skips its git-inspection steps, mirror that `[<phase>]` heading into the `design-folder.md` `progress/<slug>.md` format so the two stay single-source, and correct the stale `impl-workflow.mjs:36` comment that claims subagents cannot spawn subagents (false as of CC v2.1.172; local `claude --version` = 2.1.201, and `design-critique-workflow.mjs:89-90` already fans out). The Stop hook is kept for the standalone flow.

## Implementation

Head of both the impl-workflow.mjs chain and the design-folder.md chain (DESIGN.md `## Architecture`). Edit this file before D2/D1/E1/A1-wiring and before svg-diagram-guide/impl-recap-surface. Three files change; no new files.

### `autocode/impl/skills/impl/scripts/impl-workflow.mjs`

- Add a `logProgress(phase, note)` helper near the other prompt helpers (after `readOnly`, `impl-workflow.mjs:42`). It makes a plain **awaited** sonnet `progress-logger` call. `agent()` has no confirmed background/detach option: every in-repo `agent()` is awaited or wrapped in `parallel()` (research `agent-background-support`; confirmed at `impl-workflow.mjs` review/execute sites and `design-critique-workflow.mjs:90-99`). The call supplies `phase`, `note`, the `progress_log` path, `slug`, and the new commit SHA(s) so the fast path (below) fires. `progress_log` resolves from `.autocode/.impl-context` in the worktree (same source the Stop hook reads, `check-progress-log.sh`); the helper reads it once.
- Insert `logProgress` calls at four milestones **by name** (research `f1-milestone-insertion-points`; the plan's raw-range list is mislabeled, so key on the phase name, not the line range):
  - Plan: after the Plan agent (`impl-workflow.mjs:238-243`).
  - Execute/Commit: within the execute block (`impl-workflow.mjs:263-308`), after the fanout Commit path (`phase('Commit')`, ~283) and after the single-agent Execute path.
  - GapCheck: after the gapcheck loop (`impl-workflow.mjs:310-335`).
  - Fix: after the fix loop (`impl-workflow.mjs:337-348`).
- Correct the comment at `impl-workflow.mjs:36`. It currently reads "Subagents cannot spawn subagents, so all fan-out lives here in the workflow runtime." Rewrite to state fan-out lives in the runtime to keep heavy work off the launching context, not because nesting is impossible. Nested subagents are supported as of CC v2.1.172 and `design-critique-workflow.mjs:89-90` already fans out (research `subagent-spawn-comment-fix`). The `impl/CLAUDE.md` line "since subagents cannot spawn subagents" restates the same false claim; leave it for its owning unit, but do not propagate the wording.

`logProgress(phase, note)` signature: `phase: string` (milestone name matching the `[<phase>]` heading), `note: string` (one-line what-happened, passed verbatim to the agent). Returns the awaited `agent()` result; callers do not branch on it.

### `autocode/impl/agents/progress-logger.md`

Add a facts-provided fast-path branch. The Inputs contract already frames git work as a fallback (`progress-logger.md:13-19`: "If any is missing, derive it"). When the spawn supplies `note` + SHA(s) + `phase`, append the note verbatim under `## <UTC timestamp> [<phase>]` and skip the git-inspection Workflow steps 1-2 (`progress-logger.md:22-31`, the "Read progress_log" + "Inspect what changed" steps). Append via Bash `>>` (an Edit needs a prior Read of a file this agent otherwise never reads). The existing derive-from-git path stays as the fallback when facts are absent. Keep the append-only rule and the "touch only `progress_log`" rule.

### `autocode/design/design-folder.md`

Mirror the new `[<phase>]` heading into the `progress/<slug>.md` format block (`design-folder.md:146`, currently `## <entry timestamp>`) so `progress-logger.md:28`'s emitted heading and the design-folder spec stay single-source (research `progress-logger-fastpath-format`). The heading becomes `## <entry timestamp> [<phase>]` with `[<phase>]` optional (the git-derived fallback path emits no phase). This is the design-folder.md chain head edit.

### Boundary

```
impl-workflow.mjs  --logProgress(phase, note, facts)-->  progress-logger.md
  (4 milestones,        awaited sonnet agent()             (fast path: append
   by name)                                                 verbatim under
                                                            ## <UTC> [<phase>])
                                                                   |
                                                                   v
                                                    progress/<slug>.md heading
                                                    format mirrored in
                                                    design-folder.md:146
```

### Tests

No unit-test harness for workflow scripts (DESIGN.md `## Testing strategy`); verify by driving the flow with the `verify` skill:

- Run the impl workflow on a small unit; confirm `progress/<slug>.md` gains one entry per milestone with `## <UTC> [<phase>]` headings for Plan, Execute, GapCheck (heavy units), and Fix (when a fix round ran).
- Confirm the fast path appended the supplied note verbatim and ran no `git log`/`git diff` inspection when facts were supplied.
- Confirm the standalone `impl-execute` Stop-hook path still logs (fallback git-derive branch unaffected).
- Confirm `node --check autocode/impl/skills/impl/scripts/impl-workflow.mjs` passes and the phase list is unchanged (logging adds no `phase()` entries).
