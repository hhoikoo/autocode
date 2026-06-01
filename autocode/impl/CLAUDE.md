# impl/

Implementation phase. Worktree-bound skills drive a single unit of work from an approved design to a pushed branch: `impl-start` (pick a ready unit, set up the worktree), `impl-push` (commit + PR), `impl-archive` (close out a completed epic). The `oracle` agent escalates hard, well-scoped questions to opus reasoning from inside a sonnet session. The `progress-logger` agent appends per-unit log entries during implementation.

A unit of work is one entry under `units/` of a design epic; the epic folder layout, unit DAG, issue discovery, and progress log are specified in `@~/.autocode/autocode/design/design-folder.md`.
