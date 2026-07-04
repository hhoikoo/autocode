# design/

Planning and research before code lands. Skills that plan, critique, push, iterate on, and fan out design docs live here (`design-plan`, `design-plan-critique`, `design-plan-push`, `design-plan-iterate`, `design-fanout`). `design-grill` is the main-session interview skill: it walks a decision tree and asks the user batched `AskUserQuestion` rounds (each led by a recommended answer), grilling the context window, a design folder, or a `--seed` list of the critique workflow's `needs_human_reasons`; the `design` orchestrator invokes it on-context when critique returns `needs_human`. `design-unit-author` writes `units/<slug>.md` files during plan fan-out; `codebase-researcher` and `web-researcher` are read-only helpers spawned by those skills.

`design` is the stateless, re-entrant orchestrator over those per-phase skills. Given a seed or an in-flight epic it reconstructs the lifecycle stage each turn, dispatches the next heavy phase (plan, critique) into a background Workflow off the main context, and advances toward the user-gated merge and hand-off to `impl --from-design <id>`. See `skills/design/SKILL.md` for the phase order, dispatch discipline, and gating. The per-phase skills stay individually invocable for repos without full automation access.

`design-folder.md` is the canonical layout for a design epic (folder, units DAG, fan-out to issues, progress log, archive). It is a fixed spec, not a scaffolded convention; design and impl skills `@`-import it.

`design-pr-body.md` is the canonical recipe for a design-doc PR body (rendered-design link plus PR template filled from the design doc, never a code diff). `design-plan-push` composes it at creation; the `pr-hygiene` agent recomposes it on refresh. Both `@`-import it so the body never diverges.
