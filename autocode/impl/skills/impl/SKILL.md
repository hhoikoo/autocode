# Impl

Stateless, re-entrant epic orchestrator. Holds no durable state; reconstructs all state each turn from the tracker (cross-session source of truth for done / in-review / todo) and this session's launched run ids (session-scoped running set). Given a fanned-out design epic it launches a capped wave of per-unit background workflows, refills as they finish, cascades on user merge, prunes merged worktrees, and archives when every unit is done. Bare-ticket invocations keep the single-unit launch. Per-phase skills stay individually invocable. Design-folder layout, `.impl-context` keys, and the unit DAG: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- `--from-design <id|shortname>`: epic mode. Resolves the design folder and drives the full wave/cascade/archive cycle.
- Bare `<ticket-id>` / `<type>: <description>`: single-unit launch (unchanged contract). Optional when cwd is already a set-up unit worktree (epic mode if its `.impl-context` resolves an epic; else single-unit).
- `--dims <list>`: review dimensions, forwarded to each launched `impl-workflow`.
- `--fanout <auto|off|on>`: override the `impl.fanout-mode` setting for this run, forwarded to each launched `impl-workflow`. When omitted, the setting value is used.
- `--watch`: opt in at launch to a session-scoped monitoring cron (off by default). Equivalent to accepting the plain at-launch prompt.

## Workflow

### Route args

First: classify the invocation.

- `--from-design <id|shortname>` -> epic mode.
- Cwd is an autocode worktree on a feature branch with `.autocode/.impl-context` -> epic mode when `.impl-context` resolves an epic; else single-unit.
- Bare `<ticket-id>` / `<type>: <description>` -> single-unit launch.

A flat design (no `units/`) under `--from-design` collapses to a wave of one; archive still runs when it is done.

### Single-unit branch

Retain today's contract. `impl-start` (interactive) -> capture worktree path, `slug`, `unit_key`, `design_id`. Resolve `homeDir` (`echo "$HOME"`); resolve `base` (`git symbolic-ref --short refs/remotes/origin/HEAD` with the `origin/` prefix stripped; fall back to the local default branch). Resolve `fanout`: read `impl.fanout-mode` (default `auto`) from `$AUTOCODE_CONFIG_DIR/settings.json`, overridden by `--fanout` when supplied. Launch one `Workflow` over `impl-workflow.mjs` with `args: { homeDir, worktree, slug, base, dims, fanout }`. Report the PR URL on completion. No cascade, no archive.

### Epic discovery (re-run every turn, no caching)

1. Resolve the epic from `.autocode/design/INDEX.md` active rows plus the `--from-design` selector; glob the folder `.autocode/design/<id>-<short>/`.
2. `provider/run.sh issue-tracker issue-epic-list --epic <id>` -> per-unit `{key, summary, status, type, parent}` plus the epic row, matched by marker. `issue-epic-list` does not return `depends-on`.
3. Read each unit's `depends-on` from `.autocode/design/<id>-<short>/units/<slug>.md` frontmatter.

### Reconciliation

Resolve each unit's PR up front with `provider/run.sh git-remote pr-find <issue-key>` (the `Closes`-link lookup), because tracker status can lag a run that died between push and the status flip. Classify each unit:

- `done`: sub-issue closed.
- `in-review`: an open PR exists for the sub-issue key (trust the PR over a stale `in-progress` status). Recover the worktree path from `git worktree list --porcelain` by matching the `/<key>/` segment of each branch (`<type>/<key>/<short>`; the shortname tail is a non-reproducible slug).
- `running`: `in-progress`, no open PR, with a live run id launched this session and not yet seen complete.
- `needs-recovery`: `in-progress`, no open PR, no live run this session. Surface with a restart choice. `Workflow` `resumeFromRunId` only when the run id belongs to this session (same-session-only contract); otherwise restart. Restart cleans up: `git worktree remove --force <path>`, delete the leftover branch, transition the sub-issue back to `todo`; the unit re-enters the ready set and launches fresh next wave. Never silently relaunch over a run still live this session.

### Ready set

`todo` units whose every `depends-on` slug maps to a `done` unit.

### Capped wave launch

Read `impl.max-concurrent-units` (default `3`) from `$AUTOCODE_CONFIG_DIR/settings.json`. Also read `impl.fanout-mode` (default `auto`) from the same file, overridden by the `--fanout` orchestrator arg when supplied. Slots = cap minus running count (run ids this session launched and not yet seen complete). Cap is per-session-orchestrator; two epics in one session contend on the same cap.

For each ready unit up to `slots`: `impl-start --unit <slug> --auto` capturing the structured block (worktree path, branch, slug, unit_key, epic_key, design_id), then a background `Workflow` over `impl-workflow.mjs` with `args: { homeDir, worktree, slug, base, dims, fanout }`. Record each returned run id in working context (the session-scoped running-set evidence). Report the launched wave and queued remainder; never silently truncate.

### Self-sustaining refill

Each per-unit workflow runs in the background. On completion the harness re-invokes the main loop via `<task-notification>`; on re-entry re-run discovery + reconciliation and refill empty slots from the ready set, no user input, until the cap cannot be filled (all remaining units blocked or in-flight). Refill relies on idle-loop re-invocation (the `Workflow` tool contract asserts it).

### Merge-driven cascade

When a unit's PR merges (unit -> `done`), in the same turn recompute the ready set over newly-unblocked units, prune each merged unit's worktree, and launch the next wave under the cap.

### Worktree pruning

Prefer `ExitWorktree`; a merged unit's worktree is typically not the current session's, so the fallback is `git worktree remove <path>` per `@~/.autocode/autocode/_config/guides/worktree.md`. `ExitWorktree` only removes worktrees it created this session; a worktree merged from another session falls to the bare-git path.

### Archive trigger

When every unit is `done`, invoke `impl-archive` passing the epic id explicitly so its multiple-active-epic `AskUserQuestion` never fires. `impl-archive` self-merges its PR and closes the epic.

## Monitoring

### Trigger

Monitoring runs on explicit user command (user asks to check the PRs) or an opt-in cron tick; never automatically every turn (merge loop is human-paced).

### Launch the monitor

1. Compute the in-review set: reuse Reconciliation's `in-review` units (`pr-find <issue-key>` -> open PR). For each, read the PR's head branch via `gh pr view <pr> --json headRefName`. Map `branch` -> `worktree` from `git worktree list --porcelain` by matching the `/<key>/` segment (same recovery as Reconciliation).
2. If an in-review PR has no worktree (pruned out of band): let the checker return `needs_human` rather than cd into a missing path; the verdict surfaces it for the user.
3. Resolve `homeDir` (`echo "$HOME"`).
4. Launch `monitor-workflow.mjs` via the `Workflow` tool, background, `args: { homeDir, prs, maxConcurrent }` where each `prs` entry is `{ pr, slug, branch, worktree }` and `maxConcurrent` is the same `impl.max-concurrent-units` value (default `3`) used by the wave launcher. Its completion re-invokes the orchestrator (same `<task-notification>` mechanism as `impl-workflow`).

### Read the report

On completion, read `{ verdicts, tally }`. Surface every `needs_human` verdict with its `reason` (cases a person must handle). List `merge_ready` PRs.

### User-gated merge

Present merge-ready PRs; wait for explicit approval. Only on approval, merge each named PR via `provider/run.sh git-remote pr-merge <pr>`. Never merge without approval; the workflow never merges. Do not pass `--admin`; let server-side branch-protection gates (required reviews, CI checks) enforce normally and fail loudly if unmet. Reserve `--admin` only for the pure folder-move archive PR in `impl-archive`.

### Hand back to the cascade

Each merge flips its unit to `done`; recompute the ready set and launch the next wave (logic owned by `### Merge-driven cascade`; invoke it, do not duplicate).

### Notifications

Emit a `PushNotification` when PRs become merge-ready and on every cron tick. One line, <200 chars, lead with the actionable fact (e.g. `2 PRs merge-ready: <slug>, <slug>`). A "not sent" result (Bedrock/Vertex/Foundry) is expected and non-fatal; do not block on it.

### Opt-in cron (--watch)

Off by default; the launch pipeline self-sustains without it. Offer at launch via a plain prompt (NOT `AskUserQuestion`), or accept `--watch`. On opt-in: `CronCreate` a periodic tick, session-scoped (`durable` default false), standard 5-field cron, min 1-minute period, pick an off-`:00`/`:30` minute when the period allows. The cron prompt re-launches `monitor-workflow` (remediation + `PushNotification`); it never crosses the merge gate.

Tell the user: auto-expires after 7 days; session-scoped (stops on session exit, restored only on `--resume`/`--continue` within 7 days); fires only while the session is open and idle between turns, no catch-up for missed fires. Provide the `CronCreate` job id for `CronDelete`.

Local-session cron is the only supported path: headless/cloud Routines lose local `gh` auth and stdio providers, so a tick there fails fast (the monitor pass surfaces the failure and notifies); do not schedule a Routine.

## Rules

- Stateless and re-entrant. Reconstruct state each turn from the tracker (done / in-review / todo) and this session's run ids (running); never from durable orchestrator storage.
- Reconcile by PR existence (`pr-find <issue-key>`), not tracker status alone, before any worktree/branch deletion. Never relaunch over a run live in this session.
- Cross-session `in-progress` with no live run -> restart (clean up worktree + branch, reset sub-issue to `todo`), not resume. `resumeFromRunId` only same-session.
- Thin orchestration: launch and cascade only; the per-phase skills (`impl-start`, `impl-plan`, `impl-execute`, `impl-critique-*`, `impl-push`, `pr-rebase`, `pr-fix-ci`, `pr-review`, `impl-archive`) stay individually invocable. `impl-workflow.mjs` and per-unit phase logic are unchanged.
- Monitoring runs on user command or opt-in cron only, never automatically every turn.
- The monitor workflow never merges; merge is main-session and user-gated (`pr-merge <pr>` only after explicit approval; no `--admin` for code-bearing PRs).
- Cron is opt-in, session-scoped, never merges; local-session is the only supported cron context.

$ARGUMENTS
