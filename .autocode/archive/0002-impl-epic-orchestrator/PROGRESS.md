# Progress: impl-epic-orchestrator

## pr-rebase-auto — 2026-06-08

Unit: #20

Added `--auto` mode to `pr-rebase` (emits a structured result block on success or no-op instead of human prompts), PROGRESS.md union resolution so rebased branches preserve rollup entries from both sides, and `--no-pr-hygiene` forwarding to `pr-create`. Fixed `pr-find.sh` crashing on non-numeric issue keys and masking spurious `gh` error output. Fixed step 2 no-op path failing to emit the structured block in `--auto` mode.

Notes: Three commits total; the fix commits address edge cases found during impl-plan review.
## progress-union-gitattributes — 2026-06-08

Unit: #22

Added `.gitattributes` rule (`.autocode/design/**/PROGRESS.md merge=union`) so concurrent unit branches append to PROGRESS.md without conflict. Updated `design-fanout` to seed PROGRESS.md before issue creation, `design-plan` to write the seed on folder creation, and both `autocode-setup` and `autocode-update` to reconcile the `gitattributes` rule idempotently. Added `scripts/test-progress-union.sh`, a self-contained bash test that verifies the union merge produces the expected conflict-free result across multiple simulated branches.

Notes: `test-progress-union.sh` uses only `git` and standard POSIX tools (no network, no `gh`); it builds throwaway repos in `mktemp -d` and exits non-zero on any failure.

## pr-status-provider — 2026-06-08

PR: TBD  Unit: #21

Added two GitHub provider scripts: `pr-find.sh` (resolves a PR URL from a branch name via the GitHub API) and `pr-status.sh` (polls a PR's merge status and CI check rollup, blocking until all checks are complete or a timeout is hit). Fixed a bug where `StatusContext` entries (commit-status API, `.state` field only) were misclassified as pending because the guard did not require `.status != null`, causing the monitor to wait indefinitely for legacy checks.

## pr-ci-review-auto — 2026-06-08

PR: TBD  Unit: #19

Added `--auto` flag to both `pr-fix-ci` and `pr-review` skills. Under `--auto`, each skill runs unattended (no `AskUserQuestion`), handles discussion-band comments by deferring them instead of prompting, and emits a structured terminal result block (`{ pr, fixed, ci, needs_human, reason }` for `pr-fix-ci`; `{ pr, applied, deferred, needs_human, reason }` for `pr-review`) so an orchestrator can branch on the outcome without parsing prose output.

## impl-orchestrator-core — 2026-06-08

PR: TBD  Unit: #17

Rewrote the `impl` skill from a single-unit launcher into a stateless, re-entrant epic orchestrator. The orchestrator reconstructs all state each turn from the tracker (done / in-review / todo) and the session's live run ids; reconciles by PR existence via `pr-find` rather than tracker status alone; launches a capped wave of per-unit background workflows under `impl.max-concurrent-units`; refills empty slots on completion; prunes merged worktrees; and triggers `impl-archive` when every unit is done. Single-unit invocations retain their existing contract unchanged. Added the `impl.max-concurrent-units` setting to `settings-schema.md` and updated `autocode/impl/CLAUDE.md` with the new epic-orchestrator entry point and routing rules.

Notes: The monitoring, merge-gating, and cron sub-units (`impl-orchestrator-monitor`, `impl-orchestrator-notify`, `impl-cron`) are separate units in this epic and depend on this one.

## impl-orchestrator-monitor — 2026-06-08

Unit: #18

Added `monitor-workflow.mjs`: fans out one checker agent per in-review PR via `parallel()`, each reads `pr-status`, runs exactly one `--auto` remediation (`pr-rebase` / `pr-fix-ci` / `pr-review`) for the first blocked condition, and returns a typed `VERDICT_SCHEMA` object. Fan-out is capped to `impl.max-concurrent-units` (chunked batches) to avoid saturating concurrency on large epics. Filled `## Monitoring` in the `impl` SKILL.md with launch steps, user-gated merge, `PushNotification`, and opt-in `--watch` cron (session-scoped, never merges). Dropped `--admin` from code-bearing unit PR merges so branch-protection gates enforce normally.

Notes: Three commits: feat adds the workflow + monitoring section; two fixes cap concurrency and drop --admin.
