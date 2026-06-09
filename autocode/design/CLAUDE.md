# design/

Planning and research before code lands. Skills that plan, critique, push, iterate on, and fan out design docs live here (`design-plan`, `design-plan-critique`, `design-plan-push`, `design-plan-iterate`, `design-fanout`). The `codebase-researcher` and `web-researcher` agents are read-only helpers spawned by those skills.

`design` is the stateless, re-entrant orchestrator over those per-phase skills. Given a seed or an in-flight epic it reconstructs the lifecycle stage each turn from disk, the tracker, and the open design PR, dispatches the next heavy phase (plan, critique) into a background Workflow off the main context, consumes a typed result, and advances: plan -> critique -> push -> iterate -> [user-gated merge] -> fanout -> hand off `impl --from-design <id>`. The merge is the single user-gated step; the orchestrator never merges the design PR. The per-phase skills stay individually invocable for repos without full automation access.

`design-folder.md` is the canonical layout for a design epic (folder, units DAG, fan-out to issues, progress log, archive). It is a fixed spec, not a scaffolded convention; design and impl skills `@`-import it.

`design-pr-body.md` is the canonical recipe for a design-doc PR body (rendered-design link plus PR template filled from the design doc, never a code diff). `design-plan-push` composes it at creation; the `pr-hygiene` agent recomposes it on refresh. Both `@`-import it so the body never diverges.
