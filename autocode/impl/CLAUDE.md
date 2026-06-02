# impl/

Implementation phase. Worktree-bound skills drive a single unit of work from an approved design to a pushed branch: `impl-start` (pick a ready unit, set up the worktree), `impl-push` (commit + PR), `impl-archive` (close out a completed epic). `impl-critique` reviews the working-tree + branch diff before push by fanning out parallel dimension reviewers and adversarially verifying their findings (report only). The `oracle` agent escalates hard, well-scoped questions to opus reasoning from inside a sonnet session. The `code-reviewer` agent is the read-only reviewer/verifier `impl-critique` dispatches in parallel. The `progress-logger` agent appends per-unit log entries during implementation.

A unit of work is one entry under `units/` of a design epic; the epic folder layout, unit DAG, issue discovery, and progress log are specified in `@~/.autocode/autocode/design/design-folder.md`.
