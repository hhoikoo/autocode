# impl/

Implementation phase. Worktree-bound skills drive a fanned-out design epic to completion; each per-unit worktree still carries one unit from design to pushed branch.

`impl` is the stateless, re-entrant epic orchestrator. Given a fanned-out epic it reconstructs unit state from the tracker each turn, computes the dependency-ready set, launches per-unit background workflows (`skills/impl/scripts/impl-workflow.mjs`, run via the Workflow tool) under a concurrency cap (`impl.max-concurrent-units`, default 3), refills as they finish, cascades on user merge, prunes merged worktrees, and triggers `impl-archive` when every unit is done. A bare ticket / `<type>: <desc>` keeps the single-unit launch. Each workflow carries its unit through plan -> execute -> review -> challenge -> decide -> fix -> push -> hygiene, each phase its own agent with a per-phase model (opus for reasoning and review, sonnet for mechanical work). The workflow does the fan-out the per-phase skills cannot, since subagents cannot spawn subagents. The heavy work stays out of the launching session. Heavy partitionable units (judged by the workflow's Partition agent from the plan, gated by `impl.fanout-mode`) fan the Execute phase into parallel per-module agents plus a single sequential commit step. Heavy units then run a bounded gapcheck loop (`impl-gapcheck`, opus, capped at `GAP_MAX_ROUNDS`) that loops an `impl-execute --fix` pass until every plan item is covered.

The `## Monitoring` section is filled by `impl-orchestrator-monitor`. The second background-workflow type is `skills/impl/scripts/monitor-workflow.mjs`: fans out one checker agent per in-review PR (via `parallel()`), each agent reads `pr-status`, runs exactly one `--auto` remediation (`pr-rebase` / `pr-fix-ci` / `pr-review`) for the first blocked condition, and returns a typed verdict (`{ pr, slug, state, action_taken, merge_ready, needs_human, reason }`). The workflow never merges.

User-gated merge: main-session only, explicit user approval required; see `skills/impl/SKILL.md` `### User-gated merge` for the merge command (no `--admin` for code PRs) and gating. On merge the cascade (`### Merge-driven cascade`) relaunches newly-unblocked units.

Opt-in cron (`--watch`): off by default; offer via a plain prompt at launch. On opt-in, `CronCreate` a session-scoped periodic tick (min 1-minute, `durable` false) whose prompt re-runs the monitor and fires a `PushNotification`. Never merges; local-session is the only supported context.

The per-phase skills are also usable on their own:
- `impl-start`: pick a DAG-ready unit, set up the worktree + branch + `.impl-context`.
- `impl-plan` (opus): turn the authoritative design into a concrete mechanical plan that resolves every unknown, written to `.autocode/.impl-plan.md`. The reasoning phase.
- `impl-execute` (sonnet): carry out the plan mechanically and commit; `--fix` applies review findings.
- `impl-push`: append the epic rollup, commit, open the PR (linking the issue), advance the sub-issue.
- `impl-archive`: close out a completed epic.

`impl-critique` is the standalone, report-only review front end. It composes three leaf skills, each run by a read-only `code-reviewer` subagent and reused by the `impl` workflow's review phase:
- `impl-critique-review`: review the diff along one dimension (safe to fan out one per dimension). Dimensions include a `leanness` over-engineering pass, run by default.
- `impl-critique-challenge`: contest the findings (refuted / weakened / unrefuted).
- `impl-critique-decide`: rule which findings survive and state the minimal fix.
- `impl-gapcheck`: read-only spec-completeness pass run by the workflow before critique. Asks "is every plan item present in the diff" (not "is the code correct"); returns `{ complete, gaps[] }`. Distinct from the quality leaves: `impl-critique` checks correctness, gapcheck checks coverage.

`impl-audit` is a standalone, report-only whole-repo over-engineering scan: the repo-wide counterpart of the `leanness` review dimension (which works on a diff). It ranks what to delete, shrink, or replace with stdlib/native equivalents and applies nothing. Not part of the per-unit workflow; invoked on demand.

The `code-reviewer` agent is the read-only sandbox that runs whichever `impl-critique-*` skill the caller names. The `progress-logger` agent appends per-unit log entries during implementation (driven by the Stop hook). The `oracle` agent escalates hard, well-scoped questions to opus reasoning; it is general-purpose and not part of the `impl` flow.

A unit of work is one entry under `units/` of a design epic; the epic folder layout, unit DAG, issue discovery, and progress log are specified in `@~/.autocode/autocode/design/design-folder.md`.
