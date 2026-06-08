---
depends-on: []
type: task
---

# Unattended --auto mode for design-plan-iterate

## Summary

`design-plan-iterate` triages review comments on a design-doc PR between push and merge: it scores each comment 0-100, applies the high-confidence edits to `DESIGN.md` / `units/*.md`, delegates the commit to `git-commit`, replies to threads, and resolves them (`autocode/design/skills/design-plan-iterate/SKILL.md:1-3,19-46`). Unlike critique and fanout it already has no `AskUserQuestion` gates: it is self-contained and confidence-scored, so it is nearly orchestration-ready today. The one gap is its return: it ends by printing a prose triage table to the user (`SKILL.md:45`), which the in-review phase of the `/design` orchestrator cannot consume. This unit adds an `--auto` flag that, in place of the prose table, emits a single structured machine-readable result block carrying a `needs_human` signal so the orchestrator can apply the high-confidence triage unattended and surface only the contested or low-confidence comments to the user before the user-gated merge (epic decision 5, runtime flow step 6). Non-`--auto` invocation keeps today's interactive prose-table behavior verbatim, preserving manual invocability (epic decision 8). This unit edits one skill body and touches no sibling.

## Implementation

Edit the single real skill body; frontmatter lives in the shim, which already forwards `$ARGUMENTS` (`plugins/autocode/skills/design-plan-iterate/SKILL.md:6`), so `--auto` reaches the body with no shim change. Confirmed: no shim frontmatter update required.

File to modify:

- `autocode/design/skills/design-plan-iterate/SKILL.md`

Follow the existing `--auto` contract convention from `impl-start` (`autocode/impl/skills/impl-start/SKILL.md:16,30`): an `## Args` entry documenting `--auto` as "run unattended and end with a structured result", and a terminal step that emits the structured result block in place of the human triage table.

### --auto behavior

`design-plan-iterate` has no `AskUserQuestion` gates to suppress (epic Background table row "Iterate"; `SKILL.md` has no such call), so `--auto` is lighter here than for critique or fanout. The delta is twofold:

1. The terminal output (`SKILL.md:45`, "Output a triage table to the user") becomes a structured result block.
2. The triage's discussion band becomes a `needs_human` deferral rather than an in-tree action the orchestrator would have to interpret.

The triage rubric stays as-is (`SKILL.md:21-38`); only the mapping of each band's outcome to the unattended result changes. Mirroring `pr-review --auto` in 0002 (`.autocode/design/0002-impl-epic-orchestrator/units/pr-ci-review-auto.md:47-51`):

- High-confidence band (50-100 human / 70-100 bot): apply the edit, reply, and resolve the thread, exactly as today. Count toward `applied`.
- Discussion band (20-49 human / 30-69 bot): the human-reviewer 20-49 row today replies asking for clarification (`SKILL.md:29`), an interactive back-and-forth the orchestrator cannot drive. Under `--auto`, defer instead: do not block, count the comment toward `skipped`, leave the thread for a human, and set `needs_human: true` with a reason. The bot 30-69 "optional, update if trivial else resolve" row applies the trivial update when unambiguous, else defers to `skipped`.
- Spurious band (0-19 human / 0-29 bot): resolve as spurious with the existing explanation comment, as today. Count toward `skipped` (resolved, not deferred for a human).

Preserve every existing rule under `--auto`: edits land only in `DESIGN.md` / `units/*.md` (never source code), no build verify step, commit via `git-commit`, never `--no-verify`, and never resolve a thread without an explanation comment (`SKILL.md:48-53`).

### Structured result

Terminal block under `--auto`, mirroring the 0002 decision 6 shape and the proposed shape in the epic research:

```
{
  applied: [<comment-id>, ...],
  skipped: [<comment-id>, ...],
  replied: <int>,
  threads_resolved: <int>,
  needs_human: <bool>,
  needs_human_reasons: [<string>, ...]
}
```

- `applied`: comment ids whose edits were applied to `DESIGN.md` / `units/*.md` this run.
- `skipped`: comment ids not applied (spurious-resolved or deferred for a human).
- `replied`: count of threads that received a reply (`pr-comment-reply`, `SKILL.md:42`).
- `threads_resolved`: count of threads closed (`pr-thread-resolve`, `SKILL.md:44`).
- `needs_human`: true when any discussion-band comment was deferred (any contested / low-confidence comment the orchestrator should surface rather than auto-apply).
- `needs_human_reasons`: one short reason per deferred comment, summarizing what the human must decide.

Scalar and list fields only, in a fenced block, no prose, so the orchestrator parses it directly. This is the in-review phase's branch signal: the orchestrator applies `applied`, then surfaces `needs_human_reasons` to the user before the user-gated merge (epic runtime flow step 6). The block must be the skill's terminal output under `--auto`, replacing the prose table, mirroring how `impl-start --auto` emits its block instead of the human next-step (`autocode/impl/skills/impl-start/SKILL.md:30`).

### Tests

Per the epic testing strategy (dry-run each `--auto` skill on a scratch design and assert the structured result block, including `needs_human` on a forced low-confidence comment):

- `design-plan-iterate --auto` against a design PR with one high-confidence and one low-confidence (discussion-band) comment: assert the high-confidence id is in `applied`, the low-confidence id is in `skipped`, `needs_human: true`, and `needs_human_reasons` carries one entry.
- With only spurious comments: assert all ids in `skipped`, `needs_human: false`, and each thread resolved with an explanation (`threads_resolved` equals the comment count).
- Non-`--auto` regression: invoke without the flag and confirm the interactive path (the prose triage table, the 20-49 clarification reply) is unchanged.

No automated harness runs full skill bodies; these are manual dry runs, the acceptance gate per the epic.
