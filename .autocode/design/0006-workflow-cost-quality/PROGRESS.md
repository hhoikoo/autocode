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
## impl-recap-surface — 2026-07-05

Unit: #65
Added the `impl-recap` skill (sonnet): builds a per-unit `recap/<slug>/RECAP.md` from the branch diff and `progress/<slug>.md` (Headline + Narrative model-authored, Data/contract + File tree + Key changes + Remaining mechanical), plus `autocode/impl/impl-pr-body.md`, the canonical recipe for a unit code PR body that both `pr-create` and the `pr-hygiene` refresh agent `@`-import so the body never diverges. Extended `design-folder.md` with the living `recap/<slug>/` layout. Fixed `pr-hygiene`'s unit-PR detection to key solely on a committed `recap/<slug>/RECAP.md`, dropping the `progress/<slug>.md` fallback that matched every unit PR and recomposed bodies from a link to a RECAP.md that doesn't exist yet.
Notes: the Recap-phase invocation itself (wiring it into `impl-workflow.mjs`) is out of scope here; tracked as `recap-phase-wiring`.

## per-module-gapcheck — 2026-07-05

Unit: #66
Heavy, partitionable units with a large diff now size the diff first (sonnet agent), then run one `impl-gapcheck` agent per module plus a residual integration bucket in parallel, union and de-dupe the gaps, and feed the result into the existing gapfix + recheck loop unchanged. Small-heavy and non-partitionable units keep the single whole-diff agent. `impl-gapcheck/SKILL.md` documents the caller-supplied bounded scope this relies on.

## recap-phase-wiring — 2026-07-05

Unit: #69
Wired the Recap phase into `impl-workflow.mjs`: a sonnet `impl-recap` dispatch now runs after Verify and before Push, building `recap/<slug>/RECAP.md` with SHA-pinned blob links at a self-captured HEAD. Added a converge gate that holds the just-opened PR in draft with a `needs-human` label and a marking comment when important findings or gaps remain unresolved after the fix loop. Hygiene now runs conditionally: a markdown/README predicate (`isHygieneRelevant`) checks `push.hygiene_files` and skips the `pr-hygiene` dispatch entirely when no doc-relevant path changed, logging the skip instead. `impl-push/SKILL.md`'s commit step now names the `recap/<slug>/` artifacts explicitly alongside `PROGRESS.md` and `progress/<slug>.md`.

## recap-aware-review — 2026-07-05

Unit: #68
Made `pr-review` resolve RECAP.md-anchored review comments to the concrete source `file:line` via the RECAP's SHA-pinned blob links in `## Key changes` before triage, falling back to discussion-band treatment when the anchor is ambiguous (outside `## Key changes`, no nearby blob link, or multiple candidate blobs). In a unit worktree, fix-band findings now go to `impl-execute --fix` instead of being edited and committed inline, so the minimal-edit and commit conventions stay owned by `impl-execute`; standalone use on the default branch is unchanged.
