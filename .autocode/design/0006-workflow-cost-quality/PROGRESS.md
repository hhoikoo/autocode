# Progress: workflow-cost-quality

## design-researchers-sonnet — 2026-07-05

Unit: #64
Downgraded the read-only `codebase-researcher` dispatches in the two design workflow runtimes from opus to sonnet: the `research:<label>` and `resolve-research:<slug>` fan-outs in `design-plan-workflow.mjs`, and the `resolve-i<n>-<id>` researcher wrapper in `design-critique-workflow.mjs`. Every judgment/generative dispatch (plan-gaps, synthesize, author, resolve-author, critique question) stays opus. Reworded the `meta.phases` descriptor strings to match; no schema or interface changes.
## workflow-progress-logging — 2026-07-05

Unit: #72
Added a `logProgress` helper to the workflow runtime that spawns `progress-logger` directly after Plan, Execute, GapCheck (heavy units), and Fix (when a round ran), so progress is recorded even when a phase's Stop hook never fires under module fan-out. `progress-logger` gained a facts-provided fast path (phase + verbatim note) that skips git inspection and appends via Bash `>>`; the git-derived fallback used by standalone `impl-execute` is unchanged. `design-folder.md` documents the optional `[<phase>]` heading suffix.

## plan-partition-schema — 2026-07-05

Unit: #67
Deleted the redundant sonnet Partition phase from `impl-workflow.mjs`: renamed `PARTITION_SCHEMA` to `PLAN_SCHEMA` and attached it to the existing Plan call, so the opus planner returns `files_total`/`heavy`/`partitionable`/`foundation`/`modules` directly instead of a second agent re-reading `.autocode/.impl-plan.md` to transcribe the same fields. Downstream `heavy`/fanout/foundation/modules logic now reads `plan.*` instead of `part.*`; the `## Module partition` section still lands on disk unchanged for `impl-execute --module` to consume. `impl-plan/SKILL.md`'s `--auto` result and Module partition intro updated to match.
## svg-diagram-guide — 2026-07-05

Unit: #71
Added `autocode/_config/guides/svg-diagram.md`: a fixed copy-and-edit SVG skeleton (explicit viewBox, one reusable `<marker>` arrowhead, four named style classes, rounded-rect boxes, manual grid coordinates) plus a python3 well-formedness check with a dependency-free Node tag-balance fallback, no `xmllint`. `design-folder.md`'s Architecture diagram bullet now points at the guide as an SVG alternative to ASCII, and `guides/CLAUDE.md` lists it.

## scoped-verify-gate — 2026-07-05

Unit: #70
Added `impl-critique-verify` (opus, read-only): after a `--fix` round it confirms the just-applied findings are resolved and diff-scans for regressions, replacing the full `reviewCycle` re-run that previously followed every fix round. `impl-workflow.mjs` wires the new phase in and falls back to the full `reviewCycle` on a low-confidence decline; a `needs_human` flag now threads out of the workflow return for the caller to act on. Added `provider/git-remote/github/pr-draft.sh` (`gh pr ready --undo`) plus its `git-remote` contract entry for a future consumer to convert a PR to draft, then fixed it to stop swallowing genuine `gh` failures (e.g. a closed PR) that its stderr-grep special case had been masking as idempotent no-ops.
