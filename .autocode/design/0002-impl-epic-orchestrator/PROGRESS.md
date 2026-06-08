# Progress: impl-epic-orchestrator

## pr-rebase-auto — 2026-06-08

Unit: #20

Added `--auto` mode to `pr-rebase` (emits a structured result block on success or no-op instead of human prompts), PROGRESS.md union resolution so rebased branches preserve rollup entries from both sides, and `--no-pr-hygiene` forwarding to `pr-create`. Fixed `pr-find.sh` crashing on non-numeric issue keys and masking spurious `gh` error output. Fixed step 2 no-op path failing to emit the structured block in `--auto` mode.

Notes: Three commits total; the fix commits address edge cases found during impl-plan review.

## pr-status-provider — 2026-06-08

PR: TBD  Unit: #21

Added two GitHub provider scripts: `pr-find.sh` (resolves a PR URL from a branch name via the GitHub API) and `pr-status.sh` (polls a PR's merge status and CI check rollup, blocking until all checks are complete or a timeout is hit). Fixed a bug where `StatusContext` entries (commit-status API, `.state` field only) were misclassified as pending because the guard did not require `.status != null`, causing the monitor to wait indefinitely for legacy checks.

## pr-ci-review-auto — 2026-06-08

PR: TBD  Unit: #19

Added `--auto` flag to both `pr-fix-ci` and `pr-review` skills. Under `--auto`, each skill runs unattended (no `AskUserQuestion`), handles discussion-band comments by deferring them instead of prompting, and emits a structured terminal result block (`{ pr, fixed, ci, needs_human, reason }` for `pr-fix-ci`; `{ pr, applied, deferred, needs_human, reason }` for `pr-review`) so an orchestrator can branch on the outcome without parsing prose output.
