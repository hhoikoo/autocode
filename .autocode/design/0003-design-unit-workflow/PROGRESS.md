# Progress: design-unit-workflow

## design-fanout-auto — 2026-06-08

Unit: #27

Added `--auto` flag support to the `design-fanout` skill. The flag enables unattended execution: strict arg resolution (no implicit most-recent default, no `AskUserQuestion` prompts), a structured result block on the success path (`needs_human`, `epic_key`, `sub_issues`), and an early-exit `needs_human: true` block when the id is absent, unknown, or ambiguous. The result block key values are typed as strings (not numbers) to match the provider contract.

Notes: Two fix commits landed after initial impl to correct the structured result block definition and key types.

## design-iterate-auto — 2026-06-08

Unit: #28

Added `--auto` flag to `design-plan-iterate` skill. The flag enables unattended execution: strict arg resolution (no `AskUserQuestion` prompts), a structured result block (`needs_human`, `design_id`, `shortname`, `iterations_run`, `open_questions_remaining`) on completion, and an early-exit `needs_human: true` block when the design id is absent or ambiguous. Critique and resolution passes run unchanged; the flag only gates interactivity and shapes the final output block.
