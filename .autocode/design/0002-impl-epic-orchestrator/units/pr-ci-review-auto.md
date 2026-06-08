---
depends-on: []
type: task
---

# Unattended --auto modes for pr-fix-ci and pr-review

## Summary

`pr-fix-ci` and `pr-review` today run interactively and return prose only: each stops for the user at a decision point (a missing build convention, a low-confidence comment) and reports a human-readable triage rather than a machine-readable verdict. The monitor workflow (epic decision 4) fans out one checker per in-review PR and cannot accept that: its agents cannot call `AskUserQuestion`, and it needs a typed result to branch on. This unit adds an `--auto` flag to both skills. Under `--auto` each skill suppresses every user-facing stop, applies only the actions it can take unattended, and ends with a single structured result block carrying a `needs_human` signal so the monitor surfaces only the cases that genuinely need a person. Non-`--auto` invocation keeps today's interactive behavior verbatim, preserving manual invocability (decision 11). The two skills are independent files; this unit edits both and touches no other skill (`pr-rebase` is a separate unit).

## Implementation

Edit the two real skill bodies (frontmatter lives in the shims, which already forward `$ARGUMENTS`, so no shim edit is needed):

- `autocode/pr/skills/pr-fix-ci/SKILL.md`
- `autocode/pr/skills/pr-review/SKILL.md`

Both shims (`plugins/autocode/skills/pr-fix-ci/SKILL.md:6`, `plugins/autocode/skills/pr-review/SKILL.md:6`) end with `$ARGUMENTS` is forwarded, so `--auto` reaches the body unchanged. Confirmed: no shim frontmatter update required.

Follow the existing `--auto` contract from `impl-start` (`autocode/impl/skills/impl-start/SKILL.md:16,30`): an `## Args` entry documenting `--auto` as "run unattended (no `AskUserQuestion`) and end with a structured result", and a final step that emits a structured result block in place of the human report.

### pr-fix-ci --auto

Today's body (`autocode/pr/skills/pr-fix-ci/SKILL.md:17`) reads the verify command from `$AUTOCODE_CONFIG_DIR/conventions/build.md` and, if that file is missing, stops with a user-facing "run `/autocode-setup`" message. Other halt points: a non-branch-caused failure (flaky/infra, line 25), and CI still `pending` (line 12).

Under `--auto`, replace each user-facing stop with a `needs_human` outcome rather than a prose halt:

- Missing `build.md` convention -> `needs_human: true`, `reason` naming the missing convention. Do not infer the verify command.
- Non-branch-caused failure (flaky network, infra outage) -> `needs_human: true`, `reason` describing it. Do not guess a fix.
- A verify failure the skill cannot minimally fix -> `needs_human: true`.

Preserve all existing rules under `--auto`: still verify locally before pushing, never `--no-verify`, one commit per logical fix.

Final structured result (the proposed shape from the epic research, decision 6):

```
{ pr, fixed: bool, ci: "green" | "red" | "pending", needs_human: bool, reason }
```

`ci` reflects the post-fix check rollup the skill already computes from `provider/run.sh ci pr-check-list` (`SKILL.md:12`): `green` when every bucket is `pass`/`skipping`, `pending` while running, `red` otherwise. `fixed` is true when a fix was committed and pushed this run.

### pr-review --auto

Today's body (`autocode/pr/skills/pr-review/SKILL.md:21-24`) triages each comment confidence-weighted; the 20-49 human-reviewer band replies asking for clarification (an interactive, human-facing stop), and the rules require an explanation comment before resolving any thread (line 45).

Under `--auto`, the only change is the discussion band: low-confidence items that would otherwise prompt for clarification become deferred and counted toward `needs_human` instead of opening an interactive back-and-forth. High-confidence fixes still apply and their threads still resolve; spurious items still resolve with an explanation. Concretely:

- 50-100 (human) / 70-100 (bot): fix and resolve, as today.
- 20-49 (human) / 30-69 (bot): defer. Do not block on clarification; count toward `deferred`. Leave the thread for a human; `needs_human` becomes true.
- 0-19 (human) / 0-29 (bot): resolve as spurious with the existing explanation comment.

Preserve the rule that no thread is resolved without an explanation comment, and never `--no-verify`.

Final structured result (proposed shape, decision 6):

```
{ pr, applied: int, deferred: int, needs_human: bool, reason }
```

`applied` counts comments fixed-and-resolved this run; `deferred` counts comments left for a human; `needs_human` is `deferred > 0`; `reason` summarizes the deferred set.

### Shared contract

`needs_human` is the branch signal the monitor reads (epic runtime flow step 5: each checker returns `{pr, slug, state, action_taken, merge_ready, needs_human}`); these two per-skill returns feed that aggregation. The block must be the skill's terminal output under `--auto`, machine-parseable, mirroring how `impl-start --auto` emits its block instead of the human next-step (`autocode/impl/skills/impl-start/SKILL.md:30`).

### Tests

Per the epic testing strategy: dry-run each skill with `--auto` on a scratch branch and assert the structured result block.

- `pr-fix-ci --auto`: against a PR with green CI, assert `{ ci: "green", needs_human: false }`; with the `build.md` convention forced missing, assert `needs_human: true` with a reason naming the convention; with a forced verify failure, assert `needs_human: true`.
- `pr-review --auto`: against a PR with one high-confidence and one low-confidence comment, assert the high-confidence one is in `applied`, the low-confidence one in `deferred`, and `needs_human: true`.
- Non-`--auto` regression: invoke each skill without the flag and confirm the interactive path (clarification reply, missing-convention halt message) is unchanged.

No automated harness runs full skill bodies; these are manual dry runs, the acceptance gate per the epic.
