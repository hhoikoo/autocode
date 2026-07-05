# Progress: workflow-cost-quality

## design-researchers-sonnet — 2026-07-05

Unit: #64
Downgraded the read-only `codebase-researcher` dispatches in the two design workflow runtimes from opus to sonnet: the `research:<label>` and `resolve-research:<slug>` fan-outs in `design-plan-workflow.mjs`, and the `resolve-i<n>-<id>` researcher wrapper in `design-critique-workflow.mjs`. Every judgment/generative dispatch (plan-gaps, synthesize, author, resolve-author, critique question) stays opus. Reworded the `meta.phases` descriptor strings to match; no schema or interface changes.
