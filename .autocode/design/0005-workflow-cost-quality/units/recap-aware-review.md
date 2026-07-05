---
depends-on: [recap-phase-wiring]
type: task
---

# Recap-aware PR review

## Summary

Extend the existing `pr-review` skill so a reviewer comment anchored on a unit's `RECAP.md` is understood as a request against the underlying source, and so that when `pr-review` runs inside a unit worktree it delegates the apply step to `impl-execute --fix` instead of editing the tree itself. A RECAP-anchored comment (a review comment whose `path` is the unit `RECAP.md`) is resolved to the concrete source `file:line` it concerns via the RECAP's SHA-pinned blob links, then routed through the normal confidence-banded triage. In a unit worktree (detected the same way `impl-execute` does, `git rev-parse --abbrev-ref HEAD` not the default branch), fix-band findings are handed to `impl-execute --fix` as `file:line` + required change, so the monitor's `pr-review` remediation converges with the workflow's mechanical fix path (conventions, commit grouping, `git-commit` delegation). Outside a unit worktree (standalone use on the default branch) behavior is unchanged. Optionally widen the monitor trigger so COMMENTED-review and bot inline comments that leave unresolved threads also route to `pr-review`.

## Implementation

Deliverable: extend the existing `pr-review` skill (do not create a new `impl-iterate` skill). Add RECAP-anchor understanding and unit-worktree delegation to `impl-execute --fix`. Optionally widen the monitor's review trigger.

Files to modify:

- `autocode/pr/skills/pr-review/SKILL.md` (real, body-only): the primary change. No shim edit; `plugins/autocode/skills/pr-review/SKILL.md` already forwards `$ARGUMENTS` and its frontmatter needs no change.
- `autocode/impl/skills/impl/scripts/monitor-workflow.mjs` (optional): widen the review trigger at `monitor-workflow.mjs:62-70`.
- `provider/git-remote/github/pr-status.sh` (optional): expose an unresolved-thread signal the monitor can branch on.

RECAP-anchor understanding (`pr-review` Workflow step 3, after the existing fetch at `pr-review/SKILL.md:15`):

- `pr-comment-list` already returns `{ id, author, body, path, line, ... }` per comment (`pr-comment-list.sh:5-8`). A RECAP-anchored comment is a `kind:"review"` comment whose `path` basename is `RECAP.md`.
- Resolve such a comment to the source `file:line` it concerns using the RECAP's SHA-pinned source blob links (the RECAP surface, per `DESIGN.md` runtime-flow step 7 and decision 9). The exact anchor contract (path-vs-marker matching) is owned by the `impl-recap-surface` unit's `design-folder.md` recap section; consume it, do not restate it. This unit depends on `recap-phase-wiring` for that surface to exist.
- When the mapping to a concrete source `file:line` is unambiguous, feed the resolved location into the existing confidence-banded triage table (`pr-review/SKILL.md:20-34`). When ambiguous, treat it as a discussion-band comment (reply/defer under `--auto`); never guess a location to edit.

Unit-worktree delegation (`pr-review` Workflow step 4, the apply step at `pr-review/SKILL.md:36`):

- Detect the unit worktree by reusing `impl-execute`'s check: `git rev-parse --abbrev-ref HEAD` must not be the repo's default branch (`impl-execute/SKILL.md:20`).
- In a unit worktree, apply fix-band findings by delegating to `impl-execute --fix <findings>`, where each finding is a `file:line` plus the required change (`impl-execute/SKILL.md:11,38`). `impl-execute --fix` owns the minimal edit, convention-matching, and `git-commit` delegation, so `pr-review` stops editing and committing directly here.
- Reply/resolve (`pr-review/SKILL.md:37-40`) and the triage output / `--auto` terminal block (`pr-review/SKILL.md:51-59`) are unchanged; only the apply mechanism changes inside a worktree.
- Outside a unit worktree (on the default branch), keep the current inline apply + `git-commit` path unchanged.

Optional monitor-trigger widening (keep gated on A2 scope; blocking-only vs all-open-threads):

- The current `reviewDecision == "changes_requested"` branch (`monitor-workflow.mjs:64-66`) catches only a formal "Request changes"; a COMMENTED review or a bot/Copilot inline comment leaves `reviewDecision` at `review_required`/`none`, and such a PR can still reach `merge_ready` at `monitor-workflow.mjs:70-72`.
- To widen, first expose an unresolved-thread signal: either add an `unresolved_threads` count to `pr-status.sh`'s typed object (`pr-status.sh:72-84`) via the same GraphQL `reviewThreads` query `pr-thread-list.sh` already uses, or have the checker call `pr-thread-list` directly. Then add `OR unresolved_threads > 0` to the review-trigger condition and to the `merge_ready` guard.
- Interfaces touched if widening: `pr-status.sh` stdout contract gains `unresolved_threads: int`; `checkerPrompt` (`monitor-workflow.mjs:45`) branch 3c and the `merge_ready` computation (`monitor-workflow.mjs:70-72`) reference it. No `VERDICT_SCHEMA` change.

Tests that prove it (driven, per `DESIGN.md` testing strategy; workflow scripts have no unit harness):

- In a unit worktree, run `pr-review --auto` on a PR carrying a fix-band `RECAP.md`-anchored comment; confirm it resolves to the source `file:line` and delegates to `impl-execute --fix` (fix applied + committed by that path), then replies/resolves the thread.
- In a unit worktree, run `pr-review --auto` on an ordinary code-line comment; confirm it also routes through `impl-execute --fix` rather than an inline edit.
- On the default branch (standalone use), run `pr-review` and confirm the inline apply + `git-commit` path is unchanged and no `impl-execute` delegation occurs.
- Ambiguous RECAP-anchored comment: confirm it is deferred (discussion band), not applied to a guessed location.
- If widening the monitor: drive `monitor-workflow` against a PR with a COMMENTED review that left an unresolved thread and `reviewDecision != "changes_requested"`; confirm the checker fires `action_taken:"review"` and does not report `merge_ready`.
