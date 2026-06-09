# Progress: design-unit-workflow

## design-fanout-auto — 2026-06-08

Unit: #27

Added `--auto` flag support to the `design-fanout` skill. The flag enables unattended execution: strict arg resolution (no implicit most-recent default, no `AskUserQuestion` prompts), a structured result block on the success path (`needs_human`, `epic_key`, `sub_issues`), and an early-exit `needs_human: true` block when the id is absent, unknown, or ambiguous. The result block key values are typed as strings (not numbers) to match the provider contract.

Notes: Two fix commits landed after initial impl to correct the structured result block definition and key types.

## design-iterate-auto — 2026-06-08

Unit: #28

Added `--auto` flag to `design-plan-iterate` skill. The flag enables unattended execution: strict arg resolution (no `AskUserQuestion` prompts), a structured result block (`needs_human`, `design_id`, `shortname`, `iterations_run`, `open_questions_remaining`) on completion, and an early-exit `needs_human: true` block when the design id is absent or ambiguous. Critique and resolution passes run unchanged; the flag only gates interactivity and shapes the final output block.

## design-critique-auto — 2026-06-08

Unit: #26

Added `design-critique-workflow.mjs` as a background critique loop (Question / Resolve / Apply, capped at 5 iterations) and made `design-plan-critique --auto` a thin launcher over it with a structured `needs_human` return; the non-`--auto` interactive path is unchanged.

Notes: A fix round resolved two Important findings in the workflow: null resolve-results are now counted, surfaced in `needs_human_reasons`, and logged to the `## Critique log` as `(deferred)`; a total-failure final pass now reports `cap_reached` (`needs_human: true`) instead of `done`.

## design-plan-orchestrator-ready — 2026-06-08

Unit: #30

Added `design-plan-workflow.mjs` as a background workflow script that owns research fan-out, `DESIGN.md` synthesis, shortname derivation, worktree + branch + `INDEX.md` creation, and the `design-unit-author` fan-out with a bounded research-backed retry. Updated `design-plan/SKILL.md` to add `--auto` as a thin launcher over this workflow (non-`--auto` interactive path unchanged). Updated `design-unit-author.md` to replace the in-band underspecified signal with the three-field contract (`underspecified`, `file`, `summary`) usable both via `schema` and as inline prose.

Notes: Two fixes followed the initial commit to thread `--temp` end to end and route `Synthesize` worktree creation through `worktree.md`.

## design-orchestrator-core — 2026-06-09

Unit: #29

Added the stateless re-entrant `/design` orchestrator skill (`autocode/design/skills/design/SKILL.md`) with its plugin shim and a framing paragraph in `autocode/design/CLAUDE.md`. The orchestrator reconstructs the lifecycle stage each turn from disk, tracker state, and open design PRs; dispatches plan and critique phases as background Workflows off-context; gates the merge step to the user; and hands off to the impl orchestrator post-fanout. A follow-up fix replaced a direct `gh pr list` call with `provider/run.sh git-remote pr-find --branch` and gated the push transition on `status: done` from the critique contract.
