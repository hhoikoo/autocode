# Progress: design-unit-workflow

## design-fanout-auto — 2026-06-08

Unit: #27

Added `--auto` flag support to the `design-fanout` skill. The flag enables unattended execution: strict arg resolution (no implicit most-recent default, no `AskUserQuestion` prompts), a structured result block on the success path (`needs_human`, `epic_key`, `sub_issues`), and an early-exit `needs_human: true` block when the id is absent, unknown, or ambiguous. The result block key values are typed as strings (not numbers) to match the provider contract.

Notes: Two fix commits landed after initial impl to correct the structured result block definition and key types.
