# Impl

Stateless, re-entrant epic orchestrator. Holds no durable state; reconstructs all state each turn from the tracker (cross-session source of truth for done / in-review / todo) and this session's launched run ids (session-scoped running set). Given a fanned-out design epic it launches a capped wave of per-unit background workflows, refills as they finish, cascades on user merge, prunes merged worktrees, and archives when every unit is done. Bare-ticket invocations keep the single-unit launch. Per-phase skills stay individually invocable. Design-folder layout, `.impl-context` keys, and the unit DAG: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- `--from-design <id|shortname>`: epic mode. Resolves the design folder and drives the full wave/cascade/archive cycle.
- Bare `<ticket-id>` / `<type>: <description>`: single-unit launch (unchanged contract). Optional when cwd is already a set-up unit worktree (epic mode if its `.impl-context` resolves an epic; else single-unit).
- `--dims <list>`: review dimensions, forwarded to each launched `impl-workflow`.

## Workflow

### Route args

First: classify the invocation.

- `--from-design <id|shortname>` -> epic mode.
- Cwd is an autocode worktree on a feature branch with `.autocode/.impl-context` -> epic mode when `.impl-context` resolves an epic; else single-unit.
- Bare `<ticket-id>` / `<type>: <description>` -> single-unit launch.

A flat design (no `units/`) under `--from-design` collapses to a wave of one; archive still runs when it is done.

### Single-unit branch

Retain today's contract. `impl-start` (interactive) -> capture worktree path, `slug`, `unit_key`, `design_id`. Resolve `homeDir` (`echo "$HOME"`); resolve `base` (`git symbolic-ref --short refs/remotes/origin/HEAD` with the `origin/` prefix stripped; fall back to the local default branch). Launch one `Workflow` over `impl-workflow.mjs` with `args: { homeDir, worktree, slug, base, dims }`. Report the PR URL on completion. No cascade, no archive.

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

Read `impl.max-concurrent-units` (default `3`) from `$AUTOCODE_CONFIG_DIR/settings.json`. Slots = cap minus running count (run ids this session launched and not yet seen complete). Cap is per-session-orchestrator; two epics in one session contend on the same cap.

For each ready unit up to `slots`: `impl-start --unit <slug> --auto` capturing the structured block (worktree path, branch, slug, unit_key, epic_key, design_id), then a background `Workflow` over `impl-workflow.mjs` with `args: { homeDir, worktree, slug, base, dims }`. Record each returned run id in working context (the session-scoped running-set evidence). Report the launched wave and queued remainder; never silently truncate.

### Self-sustaining refill

Each per-unit workflow runs in the background. On completion the harness re-invokes the main loop via `<task-notification>`; on re-entry re-run discovery + reconciliation and refill empty slots from the ready set, no user input, until the cap cannot be filled (all remaining units blocked or in-flight). Refill relies on idle-loop re-invocation (the `Workflow` tool contract asserts it).

### Merge-driven cascade

When a unit's PR merges (unit -> `done`), in the same turn recompute the ready set over newly-unblocked units, prune each merged unit's worktree, and launch the next wave under the cap.

### Worktree pruning

Prefer `ExitWorktree`; a merged unit's worktree is typically not the current session's, so the fallback is `git worktree remove <path>` per `@~/.autocode/autocode/_config/guides/worktree.md`. `ExitWorktree` only removes worktrees it created this session; a worktree merged from another session falls to the bare-git path.

### Archive trigger

When every unit is `done`, invoke `impl-archive` passing the epic id explicitly so its multiple-active-epic `AskUserQuestion` never fires. `impl-archive` self-merges its PR and closes the epic.

## Monitoring

This unit launches and cascades but does not monitor or merge. The `impl-orchestrator-monitor` unit (depends on this) fills this section with `monitor-workflow`, the user-gated merge, notifications, and opt-in cron. This heading is the integration point.

## Rules

- Stateless and re-entrant. Reconstruct state each turn from the tracker (done / in-review / todo) and this session's run ids (running); never from durable orchestrator storage.
- Reconcile by PR existence (`pr-find <issue-key>`), not tracker status alone, before any worktree/branch deletion. Never relaunch over a run live in this session.
- Cross-session `in-progress` with no live run -> restart (clean up worktree + branch, reset sub-issue to `todo`), not resume. `resumeFromRunId` only same-session.
- Thin orchestration: launch and cascade only; the per-phase skills (`impl-start`, `impl-plan`, `impl-execute`, `impl-critique-*`, `impl-push`, `pr-rebase`, `pr-fix-ci`, `pr-review`, `impl-archive`) stay individually invocable. `impl-workflow.mjs` and per-unit phase logic are unchanged.
- Monitoring and merge are out of scope here; they belong to `impl-orchestrator-monitor`.

$ARGUMENTS
