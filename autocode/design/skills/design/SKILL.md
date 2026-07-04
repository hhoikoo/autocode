# Design

Stateless, re-entrant orchestrator for the design half of the lifecycle: the mirror of the impl epic orchestrator (`0002`). Each turn it reconstructs the current stage from three observable sources (disk, the tracker, the open design PR), dispatches exactly one heavy phase off the main context as a background Workflow, consumes a typed result, and either advances or stops at a gate. Phase order: plan -> critique (`--auto`) -> push -> iterate (`--auto`) -> [user-gated merge] -> fanout (`--auto`) -> hand off `impl --from-design <id>`. Pre-merge phases run auto; the merge is the single hard gate the orchestrator never crosses; fanout runs auto post-merge. Every phase skill stays individually invocable. Design-folder layout, INDEX.md, and the unit DAG: `@~/.autocode/autocode/design/design-folder.md`.

## Args

- A freeform seed (new epic description): treated as `none` stage, starts plan.
- `<id|shortname>`: resume an in-flight or completed epic. Ambiguous match -> `AskUserQuestion` before dispatching.
- `--temp`: throwaway plan only; no worktree, no id, no PR, no fanout. Refuses to advance past plan; points the user at `/design-plan-critique <dir>` for next steps.

## Workflow

### Route args

- Freeform seed with no matching folder -> stage `none` (new epic).
- `<id|shortname>` -> resume; resolve the folder (see stage reconstruction below). Ambiguous match (multiple folders or INDEX rows match) -> `AskUserQuestion` to disambiguate before dispatching.
- `--temp` -> cap at `none` -> `planned`; stop after plan.

### Reconstruct stage

Run every turn; never cache.

**Disk:** Resolve the folder via `.autocode/design/INDEX.md`, then glob `.autocode/design/<id>-*` / `*-<shortname>`. Skip the `INDEX.md` file itself when scanning. Check for `DESIGN.md` presence and `units/` presence; check whether the folder is committed on the default branch. When the main-checkout glob misses, before concluding `none` run `git worktree list` and glob `<wt>/.autocode/design/<id>-*` / `*-<shortname>` in each listed worktree: a planned-but-unpushed epic lives only uncommitted in its design worktree. A match there means stage `planned`, with that worktree as the working dir for the push phase.

**Tracker:** `provider/run.sh issue-tracker issue-epic-list --epic <id>`. Returns `[]` -> not yet fanned out. Non-empty -> fanned out.

**Open design PR:** The design branch is `docs/design-<short>` (created in the plan phase via `git-create-branch`; `design-plan-push` only re-creates it as a fresh-session fallback). To detect an open PR: call `provider/run.sh git-remote pr-find --branch docs/design-<short>` from the design worktree. A returned `state: open` is the in-review signal. As a fallback use `provider/run.sh git-remote pr-view` against a known PR number.

**INDEX.md `status` caveat:** `status` is a coarse two-state flag (`active`/`archived`; `design-folder.md` lines 30-31). It does not distinguish pre-archive stages. Fine-grained stage comes from disk + tracker + PR, not `INDEX.md`.

### Stages

- `none`: no folder matching the seed/id.
- `planned`: folder + `DESIGN.md` exist (committed or uncommitted in a design worktree); no open design PR.
- `in-review`: an open design PR exists for the folder's branch. Covers the pushed state.
- `merged`: design PR merged (folder committed on the default branch) and `issue-epic-list --epic <id>` returns `[]`.
- `fanned-out`: `issue-epic-list --epic <id>` returns non-empty.

### Dispatch and transitions

Transition table:

```
none       -> launch design-plan-workflow.mjs    (Workflow, args { homeDir, repoRoot, seed, temp })        -> { folder, id, units[], underspecified[], open_qs }
planned    -> launch design-critique-workflow.mjs (Workflow, args { homeDir, repoRoot, folder })            -> { iterations_run, files_modified, needs_human, needs_human_reasons[] }
planned    -> push           (design-plan-push; light, may stay in-session) -> { pr_url, branch }
in-review  -> iterate        (design-plan-iterate --auto) -> { applied, replied, needs_human }
=================== USER-GATED MERGE (orchestrator never merges) ===================
merged     -> fanout         (design-fanout --auto) -> { epic_key, sub_issues[] }
fanned-out -> hand off: invoke `impl --from-design <id>` (the 0002 orchestrator)
```

**`none`:** Launch `design-plan-workflow.mjs` off-context via the Workflow tool (not inline, not a subagent; the workflow can fan out research and the main session preserves the `AskUserQuestion` capability for the gate). Resolve `homeDir` (`echo "$HOME"`) and `repoRoot` (`git rev-parse --show-toplevel`); launch with `args: { homeDir, repoRoot, seed, temp }`. The script fails fast (throws, ~0 cost) if `seed`/`homeDir`/`repoRoot` arrive empty, so a dropped arg surfaces as a workflow error rather than a billed no-op run. Consume `{ folder, id, units[], underspecified[], open_qs }`. Surface any `underspecified` items or `open_qs`; on none, continue to critique.

**`planned` -> critique:** Launch `design-critique-workflow.mjs` off-context via the Workflow tool (bounded to 5 iterations) with `args: { homeDir, repoRoot, folder }` (`folder` is the absolute design-folder path). The script fails fast if any arrive empty. Consume `{ status, iterations_run, files_modified, needs_human, needs_human_reasons[] }`. Gate the push transition on `status`: only `status: done` with `needs_human: false` advances to push. On `status: error` or `status: cap_reached`, surface the result and stop. On `needs_human: true`, surface `needs_human_reasons[]` and stop; re-invocation re-runs critique (idempotent).

**`planned` (critique clean) -> push:** Run `design-plan-push` (light phase, may stay in-session). Consume `{ pr_url, branch }`. Stage becomes `in-review`.

**`in-review` -> iterate:** If the PR has open review comments, run `design-plan-iterate --auto`. Consume `{ applied, replied, needs_human }`. After iterate (or if no comments), present the PR and stop at the merge gate.

**Merge gate:** Present the merge-ready PR URL. The orchestrator never merges the design PR (distinct from `impl-archive` which may self-merge with `--admin`). On re-invocation after the user merges, stage reconstructs to `merged`.

**`merged` -> fanout:** Run `design-fanout --auto`. Consume `{ epic_key, sub_issues[] }`. Idempotent: if the GH Action (`autocreate-design-doc-issue.yml`) already fanned out the epic, `issue-epic-list` reports `fanned-out` and the orchestrator skips straight to hand-off.

**`fanned-out` -> hand off:** Invoke `impl --from-design <id>` when the impl orchestrator is present. When absent, report the epic key + sub-issues and suggest the invocation; `/design`'s responsibility ends here.

### Dispatch discipline

The orchestrator is a main-session skill, not a Workflow, because it must `AskUserQuestion` (disambiguation) and gate the merge. A Workflow could do neither and cannot nest the plan fan-out's own parallel research.

Heavy phases (plan, critique) are background Workflow scripts launched directly via the Workflow tool. Consume only the typed result. Never invoke a phase skill inline (runs in the main session, pollutes the context the design exists to keep clean). Never run a phase as a subagent (a subagent cannot nest the phase workflow's own fan-out). Mirror `impl/SKILL.md` launching `impl-workflow.mjs` directly.

### Cross-unit contracts

Typed `--auto` returns consumed by this orchestrator:

- `design-plan-orchestrator-ready`: `{ folder, id, units[], underspecified[], open_qs }`.
- `design-critique-auto`: `{ status, iterations_run, files_modified, needs_human, needs_human_reasons[] }`. `status` is one of `done | error | cap_reached`.
- `design-iterate-auto`: `{ applied, replied, needs_human }`.
- `design-fanout-auto`: `{ epic_key, sub_issues[] }`.

These workflow scripts and `--auto` modes are authored by their respective sibling units; this skill only consumes them.

### Edge cases

- **Ambiguous id/shortname:** Multiple folders or INDEX rows match -> `AskUserQuestion` before dispatching.
- **Plan returns `underspecified`/`open_qs`:** Surface them; user re-invokes `/design <id>` to re-enter at `planned`.
- **Critique `needs_human` or error:** Surface `needs_human_reasons[]` (or `status: error`/`cap_reached` details) and stop; re-invoke re-runs critique (idempotent) or proceeds if issues are resolved.
- **Contested review comments:** Iterate applies high-confidence ones, surfaces the rest; merge gate remains the user's.
- **Fanout already done by the GH Action:** `issue-epic-list` returns non-empty -> skip `design-fanout`, proceed straight to hand-off (`design-fanout` is idempotent by body marker).
- **`--temp`:** Run only the plan phase and stop; point the user at `/design-plan-critique <dir>` for next steps.
- **Flat single-unit design:** No unit fan-out in plan; fanout creates one issue; no impl cascade needed beyond hand-off.

### Manual fallback

`design-plan`, `design-plan-critique`, `design-plan-iterate`, `design-plan-push`, and `design-fanout` remain individually invocable with unchanged interactive behavior. This skill is an automation layer, not a replacement for them.

## Rules

- Stateless and re-entrant: reconstruct the stage each turn from disk + tracker + open design PR; store nothing durable.
- Off-context dispatch: heavy phases (plan, critique) run as background Workflows launched directly via the Workflow tool; never inline a phase skill, never run a phase as a subagent.
- The orchestrator never merges the design PR. The merge is the single user-gated hard stop.
- Hybrid gating: plan/critique/push/iterate run auto; hard-stop at merge; fanout runs auto post-merge. On `needs_human` from critique or iterate, surface reasons and stop.
- Hand-off boundary: at `fanned-out`, invoke `impl --from-design <id>` (or suggest it when absent); `/design` owns only the design half.
- Manual fallback: every phase skill stays individually invocable; this skill adds no provider, no workflow script, no settings key.
- `--temp`: no worktree, no id, no PR, no fanout; refuse to advance past plan.

$ARGUMENTS
