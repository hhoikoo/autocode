# impl/

Implementation phase. Worktree-bound skills drive a fanned-out design epic to completion; each per-unit worktree still carries one unit from design to pushed branch.

`impl` is the stateless, re-entrant epic orchestrator. Given a fanned-out epic it reconstructs unit state from the tracker each turn, computes the dependency-ready set, launches per-unit background workflows (`skills/impl/scripts/impl-workflow.mjs`, run via the Workflow tool) under a concurrency cap (`impl.max-concurrent-units`, default 3), refills as they finish, cascades on user merge, prunes merged worktrees, and triggers `impl-archive` when every unit is done. A bare ticket / `<type>: <desc>` keeps the single-unit launch. Each workflow carries its unit through plan -> execute -> review -> challenge -> decide -> fix -> push -> hygiene, each phase its own agent with a per-phase model (opus for reasoning and review, sonnet for mechanical work). The workflow does the fan-out the per-phase skills cannot, since subagents cannot spawn subagents. The heavy work stays out of the launching session. The `## Monitoring` seam is filled by the `impl-orchestrator-monitor` unit (room for its workflow/skill entries).

The per-phase skills are also usable on their own:
- `impl-start`: pick a DAG-ready unit, set up the worktree + branch + `.impl-context`.
- `impl-plan` (opus): turn the authoritative design into a concrete mechanical plan that resolves every unknown, written to `.autocode/.impl-plan.md`. The reasoning phase.
- `impl-execute` (sonnet): carry out the plan mechanically and commit; `--fix` applies review findings.
- `impl-push`: append the epic rollup, commit, open the PR (linking the issue), advance the sub-issue.
- `impl-archive`: close out a completed epic.

`impl-critique` is the standalone, report-only review front end. It composes three leaf skills, each run by a read-only `code-reviewer` subagent and reused by the `impl` workflow's review phase:
- `impl-critique-review`: review the diff along one dimension (safe to fan out one per dimension).
- `impl-critique-challenge`: contest the findings (refuted / weakened / unrefuted).
- `impl-critique-decide`: rule which findings survive and state the minimal fix.

The `code-reviewer` agent is the read-only sandbox that runs whichever `impl-critique-*` skill the caller names. The `progress-logger` agent appends per-unit log entries during implementation (driven by the Stop hook). The `oracle` agent escalates hard, well-scoped questions to opus reasoning; it is general-purpose and not part of the `impl` flow.

A unit of work is one entry under `units/` of a design epic; the epic folder layout, unit DAG, issue discovery, and progress log are specified in `@~/.autocode/autocode/design/design-folder.md`.
