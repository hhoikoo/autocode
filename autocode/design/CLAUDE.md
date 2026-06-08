# design/

Planning and research before code lands. Skills that plan, critique, push, iterate on, and fan out design docs live here (`design-plan`, `design-plan-critique`, `design-plan-push`, `design-plan-iterate`, `design-fanout`). The `codebase-researcher` and `web-researcher` agents are read-only helpers spawned by those skills.

`design-folder.md` is the canonical layout for a design epic (folder, units DAG, fan-out to issues, progress log, archive). It is a fixed spec, not a scaffolded convention; design and impl skills `@`-import it.

`design-pr-body.md` is the canonical recipe for a design-doc PR body (rendered-design link plus PR template filled from the design doc, never a code diff). `design-plan-push` composes it at creation; the `pr-hygiene` agent recomposes it on refresh. Both `@`-import it so the body never diverges.
