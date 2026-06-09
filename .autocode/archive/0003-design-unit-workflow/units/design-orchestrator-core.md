---
depends-on: [design-plan-orchestrator-ready, design-critique-auto, design-iterate-auto, design-fanout-auto]
type: story
---

# The /design lifecycle orchestrator

## Summary

A new `/design` skill: a thin, stateless, re-entrant main-session sequencer for the design half of the lifecycle, the mirror of the impl-epic-orchestrator (`0002`). Given a seed or an in-flight epic, each turn it reconstructs the lifecycle stage from three observable sources (disk, the issue tracker, the open design PR), dispatches exactly one phase off the main context, consumes a single typed result, and either advances or stops at a gate. The phase order is plan -> critique (`--auto`) -> push -> iterate (`--auto`) -> [user-gated merge] -> fanout (`--auto`) -> hand off `impl --from-design <id>`. Pre-merge phases run automatically; the merge is the single hard gate the orchestrator never crosses (it never merges the design PR); fanout runs automatically post-merge. Every phase skill stays individually invocable for repos without full automation access. This is the keystone unit: it consumes the `--auto` typed-return contracts the four sibling units add and wires them into the re-entrant loop.

## Implementation

Deliverable: the `design` skill (the `/design` command), a thin main-session sequencer that owns no durable state and delegates all heavy work to the off-context phase skills.

Files to create:

- `autocode/design/skills/design/SKILL.md` (real file, body-only, no frontmatter; `.claude/rules/prompt-engineering.md` "Frontmatter lives only in the shim").
- `plugins/autocode/skills/design/SKILL.md` (shim: frontmatter + a one-line `@~/.autocode/autocode/design/skills/design/SKILL.md` read line, mirroring `plugins/autocode/skills/impl/SKILL.md:1-6`). Skill name `design` is globally unique across feature-sets (`.claude/rules/prompt-engineering.md` file-layout table).

Files to modify:

- `autocode/design/CLAUDE.md`: add `design` as the orchestrator entry, framed as the automation layer over the per-phase skills (mirrors `autocode/impl/CLAUDE.md` describing `impl` as the orchestrator over its per-phase skills).

No provider script, workflow script, or settings key is added by this unit. The plan and critique phases are background Workflow scripts (`design-plan-workflow.mjs`, `design-critique-workflow.mjs`) the sibling units add; this skill (a main-session skill, not a Workflow) launches them directly via the Workflow tool and consumes only their typed results, mirroring how the `0002` orchestrator launches `impl-workflow.mjs` directly and bypasses the `impl` skill wrapper (`impl-orchestrator-core.md:49`). Launching from a main-session skill keeps the single permitted Workflow nesting level for the phase workflow's own fan-out (DESIGN.md decisions 1, 2).

Skill body shape (mirror `autocode/impl/skills/impl/SKILL.md`: intent paragraph, `## Args`, `## Workflow`, `## Rules`, trailing `$ARGUMENTS`):

Args:
- A seed (new epic) or an `<id|shortname>` selector (resume), per DESIGN.md runtime-flow step 1.
- `--temp`: throwaway plan, no worktree/id/PR/fanout; refuse to advance past plan (DESIGN.md runtime flow, `--temp` paragraph).

Stage reconstruction (DESIGN.md decision 3, runtime-flow step 2), each turn, from:
- Disk: resolve the folder via `.autocode/design/INDEX.md` then `.autocode/design/<id>-*` / `*-<shortname>` (the glob-then-INDEX pattern in `design-plan-push/SKILL.md:14-17`); check `DESIGN.md` and `units/` presence and whether the folder is committed.
- Tracker: `provider/run.sh issue-tracker issue-epic-list --epic <id>` returns `[]` when not yet fanned out, non-empty when fanned out (`issue-epic-list.sh:13-15,94-97`).
- Open design PR: detected by the design branch `docs/design-<short>` (created in the plan phase via `git-create-branch`, `design-plan/SKILL.md:41`; `design-plan-push/SKILL.md:22` only re-creates it as a fallback in a fresh session) or, as a fallback, by an open PR whose diff touches only `.autocode/design/**` (`design-pr-body.md:9-13`). No `pr-find`/`pr-list` provider script exists (`provider/git-remote/github/pr-view.sh` is a raw passthrough; DESIGN.md decision 10); use `provider/run.sh git-remote pr-view` from the worktree or a direct `gh pr list --head <branch>`. Note the missing provider abstraction in the skill body.

Stage set and transitions (DESIGN.md architecture diagram, runtime-flow steps 3-8):

```
  none       -> launch design-plan-workflow.mjs    (Workflow) -> { folder, id, units[], underspecified[], open_qs }
  planned    -> launch design-critique-workflow.mjs (Workflow) -> { iterations_run, files_modified, needs_human, needs_human_reasons[] }
  planned    -> push           (design-plan-push; light, may stay in-session) -> { pr_url, branch }
  in-review  -> iterate        (design-plan-iterate --auto) -> { applied, replied, needs_human }
  =================== USER-GATED MERGE (orchestrator never merges) ===================
  merged     -> fanout         (design-fanout --auto) -> { epic_key, sub_issues[] }
  fanned-out -> hand off: invoke `impl --from-design <id>` (the 0002 orchestrator)
```

Stage definitions (DESIGN.md runtime-flow step 2):
- `none`: no folder for the seed/id.
- `planned`: folder + `DESIGN.md` exist (committed or uncommitted in a worktree); no open design PR.
- `in-review` (covers `pushed`): an open design PR exists for the folder's branch.
- `merged`: the design PR merged (folder committed on the default branch) and `issue-epic-list --epic <id>` returns `[]`.
- `fanned-out`: `issue-epic-list --epic <id>` returns non-empty.

`INDEX.md` `status` is a coarse two-state flag (`active`/`archived`, `design-folder.md:30-31`, set `active` by `design-plan`, `archived` by `impl-archive`); it does not distinguish the pre-archive stages, so the fine-grained stage comes from disk + tracker + PR, not from `INDEX.md` (DESIGN.md decision 3).

Cross-unit contracts consumed (the typed `--auto` returns the four sibling units deliver, per DESIGN.md architecture diagram and runtime flow):
- `design-plan-orchestrator-ready`: plan phase returns `{ folder, id, units[], underspecified[], open_qs }`.
- `design-critique-auto`: `--auto` returns `{ iterations_run, files_modified, needs_human, needs_human_reasons[] }`.
- `design-iterate-auto`: `--auto` returns `{ applied, replied, needs_human }`.
- `design-fanout-auto`: `--auto` returns `{ epic_key, sub_issues[] }`.

Gating and dispatch rules (DESIGN.md decisions 1, 2, 4):
- The orchestrator is a main-session skill, not a Workflow: it can `AskUserQuestion` to disambiguate an id/shortname (DESIGN.md edge case 1) and it gates the merge; a Workflow could do neither and cannot nest the plan fan-out (decision 1, mirrors `impl/SKILL.md:21-26`).
- Heavy phases (plan, critique) are background Workflow scripts the orchestrator launches directly via the Workflow tool; it consumes only the typed result (decision 2). It never invokes the `--auto` phase skills inline (a skill runs in the main session, so its synthesis/critique churn would pollute the context the design exists to keep clean) nor as subagents (a subagent cannot nest the phase workflow's own fan-out).
- Hybrid gating: plan/critique/push/iterate auto; hard-stop at the merge; fanout auto post-merge (decision 4). On a `needs_human` result from critique or iterate, surface the reasons and stop; otherwise advance.
- Merge gate: present the merge-ready PR and stop; the orchestrator never merges the design PR (distinct from `impl-archive`, which may self-merge with `--admin`; DESIGN.md decision 4). On re-invocation after the user merges, the stage reconstructs to `merged`.

Hand-off (DESIGN.md decision 9, runtime-flow step 8): at `fanned-out`, invoke `impl --from-design <id>` (the `0002` orchestrator) when present; when absent, report the epic + sub-issues and suggest it, no failure. `/design`'s responsibility ends here.

Manual fallback (DESIGN.md decision 8): the skill body states that `design-plan`, `design-plan-critique`, `design-plan-iterate`, `design-plan-push`, and `design-fanout` remain individually invocable with unchanged interactive behavior; the orchestrator is an automation layer, not a replacement.

Edge cases the body must cover (DESIGN.md "Edge cases and error handling"):
- Ambiguous id/shortname: `AskUserQuestion` to disambiguate before dispatching (main session only).
- Plan returns `underspecified`/`open_qs`: surface; user re-invokes `/design <id>` to re-enter at `planned`.
- Critique `needs_human`: surface unresolved questions, stop; re-invoke re-runs critique (idempotent) or proceeds.
- Contested review comments: iterate applies high-confidence ones, surfaces the rest; merge gate stays the user's.
- Fanout partially complete or already done by the GH Action (`autocreate-design-doc-issue.yml`): `issue-epic-list` reports `fanned-out`; skip straight to hand-off (`design-fanout` is idempotent by body marker).
- `--temp`: run only the plan phase and stop; point the user at `/design-plan-critique <dir>`.
- Flat single-unit design: no unit fan-out in plan; fanout creates one issue; no impl cascade.

Tests that prove it (DESIGN.md "Testing strategy"):
- `scripts/check-plugin-shape.sh` passes: the shim carries frontmatter and the `@`-read line, the real file is body-only (no leading `---`), `autocode/design/` keeps its `CLAUDE.md`. This is the CI gate.
- Manual end-to-end dry run on a small two-unit seed, exercising stage reconstruction at each point (`none` -> `planned` -> `in-review` -> `merged` -> `fanned-out`), confirming the merge gate stops without merging and the hand-off call fires. No automated harness exists for full skill runs; the dry run is the acceptance gate.
- Confirm each phase skill's non-`--auto` interactive path is unchanged (manual fallback), by invoking one directly.
