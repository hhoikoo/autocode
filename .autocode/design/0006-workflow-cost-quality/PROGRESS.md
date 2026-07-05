# Progress: workflow-cost-quality

## design-researchers-sonnet — 2026-07-05

Unit: #64
Downgraded the read-only `codebase-researcher` dispatches in the two design workflow runtimes from opus to sonnet: the `research:<label>` and `resolve-research:<slug>` fan-outs in `design-plan-workflow.mjs`, and the `resolve-i<n>-<id>` researcher wrapper in `design-critique-workflow.mjs`. Every judgment/generative dispatch (plan-gaps, synthesize, author, resolve-author, critique question) stays opus. Reworded the `meta.phases` descriptor strings to match; no schema or interface changes.
## workflow-progress-logging — 2026-07-05

Unit: #72
Added a `logProgress` helper to the workflow runtime that spawns `progress-logger` directly after Plan, Execute, GapCheck (heavy units), and Fix (when a round ran), so progress is recorded even when a phase's Stop hook never fires under module fan-out. `progress-logger` gained a facts-provided fast path (phase + verbatim note) that skips git inspection and appends via Bash `>>`; the git-derived fallback used by standalone `impl-execute` is unchanged. `design-folder.md` documents the optional `[<phase>]` heading suffix.
