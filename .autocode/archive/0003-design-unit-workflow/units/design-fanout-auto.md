---
depends-on: []
type: task
---

# design-fanout --auto with a structured epic + sub-issue return

## Summary

`design-fanout` gains an `--auto` flag that suppresses its one `AskUserQuestion` gate (the ambiguous id/shortname match) in favor of a structured result block carrying the epic key, every sub-issue's key and created-or-existing status, and a `needs_human` signal, so the `/design` orchestrator can fan a merged design folder out unattended and branch only when the arg is genuinely ambiguous. Under `--auto` the id is required and a multi-folder match returns `needs_human: true` instead of prompting; the structured block replaces the prose role/number/created-or-existing table. The idempotent body-marker creation, the GitHub-permalink bodies, the epic + per-unit sub-issue shape, and the `provider/run.sh issue-tracker` write path are unchanged, so the issues this skill emits stay byte-identical to both its own interactive mode and the pure-shell GitHub Action. All interactive behavior is preserved when `--auto` is absent.

## Implementation

Deliverable: edit one source file, the canonical body-only skill. The shim and the provider scripts need no change.

Files to modify:

- `autocode/design/skills/design-fanout/SKILL.md` (the real, body-only skill; args at `:9`, idempotency at `:20`, creation at `:25-30`, report at `:31`, preconditions at `:39`): add the `--auto` arg, the suppressed ambiguity gate, and the structured return.

Files NOT modified (note for the implementer):

- `plugins/autocode/skills/design-fanout/SKILL.md` already forwards `$ARGUMENTS` (verified: shim body is `Read through @~/.autocode/...design-fanout/SKILL.md ... $ARGUMENTS is forwarded.`), so `--auto` flows through with no edit. Its `description` carries no mode list and stays accurate; leave it.
- `provider/issue-tracker/github/issue-epic-list.sh`: the idempotency call (`issue-epic-list --epic <id>`, `design-fanout/SKILL.md:20`) and its `Issue[]` contract (`key`, `summary`, `description`, `type`, `status`, `parent`; `issue-epic-list.sh:53-84`) already return everything `--auto` needs. The structured result reads `key` and matches `description` markers; no provider change.

### `--auto` mode

Add `--auto` to the `## Args` section (currently `<id | shortname>` defaulting to the most recent folder, with `AskUserQuestion` on ambiguity; `design-fanout/SKILL.md:9`). Default (flag absent) keeps the `AskUserQuestion` disambiguation and the prose report verbatim (DESIGN.md decision 8, manual fallback preserved; the GH Action and the interactive skill must keep producing the identical issue shape, DESIGN.md decision 5 alternatives).

When `--auto` is set:

| Current behavior (`SKILL.md` line) | Default | `--auto` |
|---|---|---|
| Arg defaults to most recent folder (`:9`) | implicit most-recent | id required; absent or unresolvable arg returns `needs_human: true`, `reason` naming the missing/unknown id (no implicit most-recent under automation, per DESIGN.md decision 5: an ambiguous arg is the canonical `needs_human` case) |
| Ambiguous id/shortname match (`:9`) | `AskUserQuestion` to disambiguate | no prompt; return `needs_human: true`, `reason` naming the candidate folders |
| Final report (`:31`) | prose table role/number/created-or-existing | the structured result block below, in place of the table |

The idempotency check (`:20`), the permalink base (`:19`), the body-file construction (`:21`), and every `provider/run.sh issue-tracker issue-create` call (`:26-30`) are unchanged in both modes. `--auto` changes only how the arg ambiguity is handled and how the result is reported; it never alters the issues created.

Structured result (the contract `design-orchestrator-core` consumes, per DESIGN.md decision 5 and runtime-flow step 7):

```
{ epic_key: string,
  epic_status: "created" | "existing",
  sub_issues: [ { slug: string, key: string, status: "created" | "existing" } ],
  needs_human: bool,
  reason: string }
```

- `epic_key`: the epic (or flat) issue number, as a string, matching the `key` field of `issue-epic-list` (`issue-epic-list.sh:56`).
- `epic_status` / per-unit `status`: `"existing"` when the body marker was already present and creation was skipped (`design-fanout/SKILL.md:20`), `"created"` otherwise.
- `sub_issues`: one entry per `units/<slug>.md`, in folder order; `[]` for a flat design (the single issue is reported only as `epic_key`, since the flat issue is both epic and unit, `design-folder.md:49`).
- On a clean fan-out: `needs_human: false`, `reason: ""`.
- On an ambiguous or unresolvable arg: `needs_human: true`, `epic_key: ""`, `sub_issues: []`, `reason` naming the problem; no issues are created (the skill stops before the idempotency call).

The skill emits this block as its final output in `--auto` mode in place of the step-4 prose table. The "run only after the design PR merged" precondition (`:39`) is unchanged: under `--auto` the orchestrator only reaches fanout at the `merged` stage (DESIGN.md runtime-flow step 7).

### Idempotency under partial fan-out

No new logic; the structured return surfaces the existing idempotency (`design-fanout/SKILL.md:20-21`, DESIGN.md edge case). When the GH Action already fanned out on merge, every marker is present, so `issue-epic-list` returns the full set: `epic_status` and every `sub_issues[].status` come back `"existing"` and nothing is created. A partial fan-out (some markers present, some absent) reports the pre-existing ones as `"existing"` and the freshly created ones as `"created"` in the same block.

### Rules section

Extend `## Rules` (`design-fanout/SKILL.md:33-39`): state that `--auto` suppresses the ambiguity `AskUserQuestion` (id required; ambiguous or unresolvable arg returns `needs_human: true` and creates nothing) and emits the structured result instead of the prose table. The all-writes-through-`provider/run.sh`, idempotent, no-issue-numbers-written-back, and merged-only-precondition rules are unchanged.

### Tests that prove it

Per DESIGN.md testing strategy (dry-run each `--auto` skill on a scratch design, assert the structured block including `needs_human` on a forced ambiguous arg):

- Multi-unit scratch design, `--auto` with an explicit id, no issues yet: assert the block has `epic_status: "created"`, one `sub_issues` entry per unit with `status: "created"`, `needs_human: false`, and that the created issues carry the same markers and bodies as the interactive mode (shape parity, DESIGN.md decision 5).
- Re-run the same fan-out with `--auto`: assert `epic_status: "existing"` and every `sub_issues[].status: "existing"`, zero new issues (idempotency).
- Partial fan-out (epic exists, one unit missing) with `--auto`: assert mixed `"existing"` / `"created"` statuses.
- Forced ambiguous arg (two folders matching the shortname) with `--auto`: assert `needs_human: true`, `epic_key: ""`, `sub_issues: []`, a `reason` naming the candidates, and that no `AskUserQuestion` fires and no issue is created.
- Missing/unknown id with `--auto`: assert `needs_human: true`, `reason` naming the id, no issues created.
- Flat single-unit design with `--auto`: assert one `epic_key`, `sub_issues: []`, `needs_human: false`.
- Default mode (no `--auto`): the ambiguity gate still prompts and the prose table is unchanged (regression guard for decision 8 manual fallback).
