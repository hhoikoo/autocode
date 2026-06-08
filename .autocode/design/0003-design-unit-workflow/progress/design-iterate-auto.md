# design-iterate-auto

Epic: 0003-design-unit-workflow  Branch: feat/28/design-iterate-auto  Started: 2026-06-08

## 2026-06-08
Added `--auto` flag to `design-plan-iterate` skill. The flag enables unattended execution: strict arg resolution (no `AskUserQuestion` prompts), a structured result block (`needs_human`, `design_id`, `shortname`, `iterations_run`, `open_questions_remaining`) on completion, and an early-exit `needs_human: true` block when the design id is absent or ambiguous. Critique and resolution passes run unchanged; the flag only gates interactivity and shapes the final output block.
