---
type: story
---

# Background workflow for design-plan unit authoring

## Summary

`design-plan` fans out its per-unit `design-unit-author` agents inline via the Task tool, inside the launching session. The authored unit prose itself stays out of context (the agent returns only a path plus a one-line summary, `design-unit-author.md:41`); what fills the window is the dispatch side and the orchestration: each inline Task prompt embeds the full `DESIGN.md` verbatim, so N units mean N copies of the epic plan in the session's tool-use history, and the underspecified-retry judgment pulls fresh research back into context. This lifts that fan-out into a background Workflow script (`author-units.mjs`), mirroring how `impl` runs its phases via `impl-workflow.mjs`: the launching session writes `DESIGN.md`, then launches the workflow and consumes a single structured result, while the parallel authoring and a bounded research-backed retry run in the background out of context. The same change gives `design-unit-author` a structured return contract (`{ underspecified, file, summary }`) so the workflow can branch on a typed result, and drops the interactive shortname prompt in favor of an auto-derived shortname. Research fan-out (step 3) stays inline: its verbatim findings must reach the planner to compose a sourced plan, and it carries no retry loop.

## Background

`design-plan` step 5 today (`autocode/design/skills/design-plan/SKILL.md:43`) dispatches one `design-unit-author` per unit in a single message, waits, and re-dispatches any unit the author reports underspecified. The author returns unstructured text with an in-band "underspecified" signal (`autocode/design/agents/design-unit-author.md:29`). The impl flow already solved the equivalent problem: `impl` is a thin launcher that sets up the worktree, then runs every phase as a background Workflow (`autocode/impl/skills/impl/scripts/impl-workflow.mjs`), keeping heavy work out of the session (`autocode/impl/CLAUDE.md`).

| Piece | Current | Target |
|---|---|---|
| Unit-author fan-out | inline Task calls in the session | background Workflow (`author-units.mjs`) |
| Underspecified retry | re-dispatch inline, judgment in session | bounded research-backed retry in the workflow; genuine gaps surface |
| `design-unit-author` return | unstructured text, in-band signal | structured `{ underspecified, file, summary }` |
| Shortname | `AskUserQuestion` prompt | auto-derived from the epic title |
| Research fan-out | inline Task calls | unchanged (stays inline) |

The shape check (`scripts/check-plugin-shape.sh`) validates SKILL/agent shims, feature-set `CLAUDE.md` presence, and shellchecks `*.sh`. It does not touch `scripts/*.mjs`; the impl precedent confirms workflow scripts live only in the real tree (`plugins/autocode/skills/impl/` carries only `SKILL.md`), referenced by absolute path resolved from `args.homeDir`. So the new script needs no shim and no CI change.

## Architecture

No new packages or deps. One new Workflow script next to its skill, one agent-contract edit, one launcher rewrite, one CLAUDE.md note. The launching session keeps every interactive and narrative step; only the unit-author fan-out crosses into the background.

```
design-plan (launching session)                         author-units.mjs (background Workflow)
--------------------------------                        -------------------------------------
seed -> rough sketch -> gaps
  |
  +-- research fan-out (INLINE Task; verbatim findings)
  |
compose epic plan + unit DAG
auto-derive <shortname>
enter worktree + branch
allocate <id> from INDEX.md
write DESIGN.md (in session)
  |
  |   Workflow(scriptPath, args:{ homeDir, workdir,
  |            folder, designText, units[] })
  +--------------------------------------------------->  phase Author: parallel(units.map(authorOne))
  |                                                         authorOne(u):
  |                                                           r1 = agent(design-unit-author,
  |                                                                schema AUTHOR_SCHEMA)   // writes units/<slug>.md
  |                                                           if !r1.underspecified -> return r1
  |                                                         phase Resolve (bounded, x1):
  |                                                           f  = agent(codebase-researcher, scoped to u)
  |                                                           r2 = agent(design-unit-author + f, schema)
  |                                                           return r2   // may still be underspecified
  |   { authored:[{slug,file,summary,underspecified}],   <- return
  +<--  underspecified:[slug], retried:[slug] }
  |
inspect return; for each still-underspecified unit:
  resolve in session (more research / tighter deliverable),
  re-launch the workflow for those units or hand-author
  |
final report
```

The author agents write distinct `units/<slug>.md` files concurrently into the same worktree (parallel-safe; the existing inline fan-out already relies on this). The launching session does not receive the unit prose, only path + one-line summary + the underspecified flag per unit.

## Design decisions

1. **Move only the unit-author fan-out; leave research fan-out inline.** Two seams exist: research (step 3, before plan composition) and unit-authoring (step 5, after `DESIGN.md`). Only unit-authoring moves. Research findings are folded verbatim into the plan so the planner can write a sourced design (`design-plan` rules: every claim cited; prefer "I don't know" over a guess); the findings must enter the main context regardless of how they were gathered, so a research workflow would save little while risking distillation of the grounding the planner needs. Unit-authoring is the high-value seam: the unit files are the deliverable on disk, the session needs only a summary back, and the underspecified-retry is real multi-step orchestration. Rejected: a second research workflow (low payoff, distillation risk); one workflow straddling both seams (impossible, since in-session `DESIGN.md` authoring sits between them and the workflow runs to completion in the background before returning).

2. **One workflow, launched at the step-5 seam.** A single Workflow invocation cannot straddle the in-session `DESIGN.md` write. Since only unit-authoring moves, one script suffices, launched after `DESIGN.md` is written. Mirrors `impl`'s single `impl-workflow.mjs`.

3. **Bounded research-backed retry in the workflow, then surface.** On an underspecified unit, the workflow dispatches a `codebase-researcher` scoped to that unit's deliverable, then re-dispatches `design-unit-author` with the findings (cap: one retry per unit). Units still underspecified after the retry are returned in the structured result for the session to resolve (more research or a tighter deliverable) and re-launch or hand-author. Rationale: the common cause of underspecification is the author lacking concrete file detail it could have found; the workflow runtime can spawn researchers (subagents cannot, which is why the fan-out lives in the workflow), so it can manufacture that missing information without bouncing to the session. A genuine planning gap (the deliverable itself is wrong) cannot be fixed without session judgment, so it surfaces. Rejected: pure surface-to-session (bounces the common, auto-resolvable case back into context); blind in-workflow retry with the same inputs (adds no information, only re-rolls non-determinism); unbounded retry (can loop on an impossible unit).

4. **`design-unit-author` returns a structured contract.** `{ underspecified: boolean, file: string, summary: string }`, enforced by the workflow's `agent(..., { schema })` call (forces a StructuredOutput tool call, model retries on mismatch), exactly as `impl-workflow.mjs` enforces `FINDINGS_SCHEMA`/`DECIDE_SCHEMA`. The agent body documents the contract; the schema literal lives in the script (single consumer). The file remains the deliverable; the structured value is the control signal. The agent stays usable inline (a human caller reads the same fields from prose).

5. **Workflow agents follow agent bodies by absolute path, not `agentType`.** The script's author and researcher agents are default workflow agents told to read `~/.autocode/autocode/design/agents/<name>.md` and follow it (impl's `follow(path, extra)` convention), because the skill/agent catalog is not reliably visible to workflow agents. Paths resolve from `args.homeDir`, never env vars (unexpanded in the workflow runtime). `model: 'opus'` is set per-agent in the script for the author (matching its shim); the per-agent `model` option is safe (the frontmatter-`model: sonnet` rate-limit issue does not apply to the script option).

6. **Auto-derive the shortname; drop the prompt.** Step 5 no longer calls `AskUserQuestion` for `<shortname>`. It derives one from the epic `# <Title>`/`## Summary`: kebab-case, lowercase, 2-4 keywords, filler stripped (same reduction `git-create-branch` uses for short-names), then de-duplicated against `INDEX.md` and existing `.autocode/design/*` folders (suffix `-2`, `-3` on collision). Removes a round-trip; the title already encodes the human label. `--temp` is unaffected (it has no id and an ephemeral folder).

## Runtime flow

1. Steps 1-4 of `design-plan` run unchanged in the session: seed, rough sketch, gap identification with inline research fan-out, plan composition and unit decomposition.
2. Step 5 (non-temp): auto-derive `<shortname>` from the title; enter the worktree; `git-create-branch`; allocate `<id>` from `INDEX.md`; create `<folder>` and `<folder>/units/`; write `DESIGN.md` in the session; append the `INDEX.md` row.
3. Resolve workflow args: `homeDir` (`echo "$HOME"`), `workdir` (the worktree root for inspection; the original repo root under `--temp`), `folder` (absolute design folder), `designText` (the `DESIGN.md` just written), `units` (one entry per unit: `slug`, `deliverable`, `dependsOn`, `type`, and the verbatim research findings relevant to it).
4. Launch the Workflow with `scriptPath = <homeDir>/.autocode/autocode/design/skills/design-plan/scripts/author-units.mjs` and those `args`. The session waits; authoring and retry run in the background.
5. The workflow authors every unit in parallel; each underspecified unit gets one research-backed retry; it returns `{ authored, underspecified, retried }`.
6. The session consumes the result. If `underspecified` is empty, it proceeds to the final report (worktree, branch, folder, `<id>`; suggest `/design-plan-critique <id>` or `/design-plan-push <id>`). Otherwise it resolves each surfaced unit (more research or a tighter deliverable) and re-launches the workflow for those slugs or hand-authors them, then reports.
7. Flat single-unit designs are unchanged: `design-plan` writes `DESIGN.md` itself, no fan-out, no workflow.

## Implementation

Deliverable: `design-plan`'s unit-author fan-out runs as a background Workflow, `design-unit-author` returns a structured contract, and the shortname is auto-derived. One PR.

Files:

- `autocode/design/skills/design-plan/scripts/author-units.mjs` (new). The Workflow script. Mirrors `impl-workflow.mjs` structure:
  - `export const meta` with `name: 'author-units'`, a description, and `phases: [{ title: 'Author', model: 'opus' }, { title: 'Resolve' }]`.
  - Reads `args`: `homeDir`, `workdir`, `folder`, `designText`, `units` (array of `{ slug, deliverable, dependsOn, type, research }`). No interactive input; all args resolved by the launcher.
  - Helpers mirroring impl: `agentBody(name) => ${HOME}/.autocode/autocode/design/agents/${name}.md`, `follow(path, extra)`, `inDir = "Work in ${workdir}: cd into it before inspecting the codebase. "`.
  - `AUTHOR_SCHEMA = { type:'object', additionalProperties:false, properties:{ underspecified:{type:'boolean'}, file:{type:'string'}, summary:{type:'string'} }, required:['underspecified','file','summary'] }`.
  - `MAX_RETRY = 1`.
  - `authorOne(u)`: dispatch `design-unit-author` (read its body, `phase:'Author'`, `model:'opus'`, `schema: AUTHOR_SCHEMA`) with a prompt carrying `folder`, `workdir`, `designText` verbatim, `u`'s assignment, and `u.research` verbatim. If `!underspecified`, return `{ slug, ...result, retried:false }`. Else the bounded retry, both calls tagged with the `{ phase: 'Resolve' }` agent option (never a bare `phase('Resolve')` call): `authorOne` runs inside `parallel`, and `phase()` mutates global state shared across all concurrent units, so a bare call races other units' phase grouping. Dispatch `codebase-researcher` (`{ phase: 'Resolve' }`, its own default model; read-only by contract) scoped to `u.deliverable` plus the author's `summary` (the missing-files question), then re-dispatch the author (`{ phase: 'Resolve', model: 'opus', schema: AUTHOR_SCHEMA }`) with the extra findings appended; return the second result with `retried:true`. Mirrors `impl-workflow.mjs`, where the in-`parallel` review agents pass `{ phase: 'Review' }` as an option and no `phase()` call appears inside a `parallel` map.
  - Top level: `phase('Author')`; `const authored = (await parallel(units.map(u => () => authorOne(u)))).filter(Boolean)`; `return { authored, underspecified: authored.filter(a => a.underspecified).map(a => a.slug), retried: authored.filter(a => a.retried).map(a => a.slug) }`.
  - Plain JS only; no `Date.now()`/`Math.random()`/argless `new Date()`.
- `autocode/design/agents/design-unit-author.md` (edit). Replace the in-band underspecified note (line 29) and the Output section (lines 39-41) with the structured contract: report `underspecified` (boolean), `file` (the `units/<slug>.md` path written, or the intended path when underspecified), and `summary` (the one-line deliverable summary, or the reason it is underspecified and what is missing). Keep "the file is the deliverable, not the message." No frontmatter (body-only real file).
- `autocode/design/skills/design-plan/SKILL.md` (edit). Step 5:
  - Drop the `AskUserQuestion` for `<shortname>`; auto-derive it (decision 6) and state the derivation and collision rule inline.
  - Replace the inline multi-unit fan-out paragraph (line 43) with: write `DESIGN.md`, resolve the workflow args (decision 5, runtime step 3), launch the Workflow (`scriptPath` + `args`), consume `{ authored, underspecified, retried }`, and resolve any surfaced underspecified unit in-session then re-launch or hand-author.
  - Leave the `--temp` and flat branches behaving as before (flat writes `DESIGN.md` inline, no workflow; `--temp` passes `workdir` = original repo root and a `folder` outside any worktree).
- `autocode/design/CLAUDE.md` (edit). One line noting `design-plan` launches `author-units.mjs` (a background Workflow) for unit-author fan-out, mirroring impl, with the script living next to the skill under `scripts/`.

No shim changes: no new skill or agent names; the `.mjs` script is not shimmed (shape check ignores it). No CI change.

Public interface (workflow args contract):

```
args = {
  homeDir:   string,   // echo "$HOME"
  workdir:   string,   // worktree root (non-temp) | original repo root (--temp)
  folder:    string,   // absolute design folder; units written to <folder>/units/<slug>.md
  designText: string,  // full DESIGN.md text, verbatim, passed to every author
  units: [ { slug, deliverable, dependsOn: [slug...], type, research } ]
}
return = { authored: [ { slug, file, summary, underspecified, retried } ],
           underspecified: [slug...], retried: [slug...] }
```

## Edge cases and error handling

- All units well-specified: `underspecified` is empty; the session reports directly. The common path.
- A unit still underspecified after the one retry: surfaced in `underspecified`; the session resolves and re-launches for those slugs or hand-authors. Not an error.
- An author agent dies on a terminal error: `parallel` yields `null` for it; `.filter(Boolean)` drops it, and its slug is absent from `authored`. The session detects the missing slug (compare against the units it sent) and re-launches or hand-authors that one.
- The whole workflow fails (the Workflow tool errors out, not a single agent dying): the session gets no structured result, but `DESIGN.md`, the `INDEX.md` row, and the `<id>` are already written and durable in the worktree. `units/` is empty or partial. The session treats every sent slug as missing and re-launches the workflow, or hand-authors the units; no rollback of the id or the folder. The id, not the run, is the durable token.
- `--temp`: no worktree, no id, no `INDEX.md`; `workdir` = the original repo root for codebase inspection, `folder` = the temp dir. Authors still inspect the real repo for file shapes.
- Single-unit (flat) design: no workflow launched; `design-plan` writes `DESIGN.md` itself.
- Shortname collision with an `INDEX.md` row or an existing `.autocode/design/*` folder: append `-2`, `-3`. The id (not the shortname) is the durable token, so a suffixed shortname is harmless.

## Testing strategy

Markdown-and-script change, no app build. Verification:

- `scripts/check-plugin-shape.sh` passes (no new shims; real files carry no frontmatter; every feature-set has `CLAUDE.md`). This is the CI gate.
- Static read of `author-units.mjs` against `impl-workflow.mjs`: same helper shape, `args.homeDir` path resolution, `parallel` fan-out, `schema`-typed returns, no forbidden globals.
- Dry exercise: run `/design-plan` on a small multi-unit seed in a scratch repo; confirm no shortname prompt, the workflow launches after `DESIGN.md`, unit files land under `units/`, and the final report carries the structured tally. Confirm an intentionally vague unit surfaces in `underspecified` after one retry.
- Confirm `design-unit-author` still works inline (invoke it directly) and reports the three contract fields in prose.

## Alternatives considered

- **Multi-unit decomposition of this epic** (split into agent-contract, workflow-script, launcher units). Rejected: the script, the contract it consumes, and the launcher that feeds it are tightly coupled and only coherent reviewed together (does the launcher pass what the script expects? does the schema match the author's contract?). Splitting would merge dead code (a workflow nothing invokes) ahead of its wiring and make review harder. Flat single-unit fits the modest, cohesive scope.
- **Move research fan-out too** (one or two extra workflows). Rejected: see decision 1.
- **Move `design-plan-critique` and `design-plan-iterate` into workflows.** Deferred, out of scope. `critique`'s loop interleaves `AskUserQuestion` user-asks with research dispatch every iteration (`design-plan-critique/SKILL.md:20-26`); not a clean fan-out without restructuring to pre-collect questions. `iterate`'s only fan-out is the apply step (one subagent per affected unit, often one), with triage staying in-session; a workflow there is low payoff for a second script and schema. Both stay in-skill and individually user-invocable. Revisit if either grows a real multi-round fan-out.

## Sources

- `autocode/design/skills/design-plan/SKILL.md:14-49` — current workflow; step 5 inline fan-out (`:43`) and shortname prompt (`:38`).
- `autocode/design/agents/design-unit-author.md:29,39-41` — current in-band underspecified signal and unstructured output.
- `autocode/design/agents/codebase-researcher.md` — researcher contract used in the retry.
- `autocode/impl/skills/impl/scripts/impl-workflow.mjs` — workflow-script template: `meta`, `args.homeDir`, `follow`, `parallel`, schema-typed `agent` returns, plain-JS constraints.
- `autocode/impl/skills/impl/SKILL.md:21-26` — how a thin launcher resolves args and calls the Workflow tool (`scriptPath` + `args`).
- `autocode/impl/CLAUDE.md` — "the workflow does the fan-out the per-phase skills cannot (subagents cannot spawn subagents); heavy work stays out of the launching session."
- `autocode/design/design-folder.md:47-51,70-88` — flat-vs-multi rule; unit-file shape.
- `scripts/check-plugin-shape.sh:31-124` — shape check covers shims, feature-set `CLAUDE.md`, and `*.sh`; not `*.mjs`. `plugins/autocode/skills/impl/` (only `SKILL.md`) confirms workflow scripts are not shimmed.
- `autocode/_config/guides/worktree.md` — `EnterWorktree` then `git-create-branch`; the fan-out writes into the same worktree.
- `autocode/_config/conventions/issue-types.md` — `story` = single-PR user-visible deliverable (the `/design-plan` behavior change).
- `git-create-branch/SKILL.md:39` — kebab short-name reduction reused for shortname derivation.
- User decision (this session): also drop the interactive shortname prompt; auto-pick a reasonable one.

## Critique log

Iteration 1:
- Q: Does `phase('Resolve')` called inside the `parallel(units.map(...))` map (Implementation `authorOne`) race other concurrent units? A: Yes. The Workflow contract states `phase()` mutates global state and warns to use the `{ phase }` agent option inside `parallel`/`pipeline`; `impl-workflow.mjs` confirms the pattern (in-`parallel` review agents pass `{ phase: 'Review' }`, no bare `phase()` inside a map). Rewrote `authorOne` to tag both Resolve calls with the `{ phase: 'Resolve' }` option. Source: Workflow tool contract; `impl-workflow.mjs:139-146`.
- Q: Is the stated problem (unit prose fills context) accurate? A: No. `design-unit-author.md:41` returns only path + one-line summary, so prose never enters context today. The real cost is N inline Task prompts each embedding full `DESIGN.md` plus the in-session retry research. Reframed the Summary. Source: `design-unit-author.md:41`; `design-plan/SKILL.md:43`.
- Q: What model and read-only posture for the Resolve-phase agents? A: Re-dispatched author pinned `model: 'opus'` + `schema: AUTHOR_SCHEMA` (matches the Author phase); `codebase-researcher` runs at its own default and is read-only by its own contract (`codebase-researcher.md:71`). Folded into the `authorOne` spec. Source: `codebase-researcher.md:71`.
- Q: Is whole-workflow failure (Workflow tool error, distinct from a single agent dying) handled? A: It was not. Added an edge case: `DESIGN.md`/`INDEX.md` row/`<id>` are already durable; the session re-launches or hand-authors, no id rollback. Source: existing edge-case list; the id-as-durable-token rule (decision 6, edge cases).
</content>
</invoke>
