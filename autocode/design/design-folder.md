# Design folder layout

Canonical structure for a design epic: one folder holding the epic plan, its independent units of work (a DAG), and the living progress log. Fixed across all autocode repos. `design-plan` creates it; the design-PR fan-out turns it into issues; `impl-start` consumes it; the progress log tracks it. Skills `@`-import this file rather than restating the layout.

## Location and naming

```
.autocode/design/<id>-<shortname>/
```

- `<id>`: zero-padded 4-digit incrementing integer (e.g. `0007`), allocated from `INDEX.md` at `design-plan` time (next id = highest in `INDEX.md` + 1). Zero-padding keeps `ls` ordered by creation. An opaque token everywhere else: tags, markers, archive path.
- `<shortname>`: kebab-case, 2-4 words, human label.
- The folder is never renamed. No issue number is ever encoded in the path; issues do not exist until the design PR merges, and the link runs issue -> folder (see Fan-out).

## INDEX.md

`.autocode/design/INDEX.md` is the durable id registry and human index. It is the source of truth for the next id; scanning `.autocode/design/` is not, because `impl-archive` moves done epics out to `.autocode/archive/`, so their numbers would otherwise be reused. Every skill that resolves an epic from `.autocode/design/` skips `INDEX.md`: it is a file, not an epic folder.

Append-only table, one row per epic ever created, oldest first:

```markdown
# Design index

| id | shortname | created | status |
|------|-------------------|------------|----------|
| 0001 | cache-key-fix | 2026-06-01 | archived |
| 0007 | design-folder-ids | 2026-06-02 | active |
```

- `design-plan` allocates the next id (highest existing + 1, zero-padded to 4 digits; `0001` when the table is empty), creates the folder, then appends a row with `status: active`. It creates `INDEX.md` on first use. `--temp` designs are throwaway and never touch it.
- `impl-archive` flips that epic's row to `status: archived` when it moves the folder. A row and its id are never removed or reused.

Uniqueness under concurrency: two branches that allocate the same id both append a row at the table tail, so the merge conflicts. The folders carry different shortnames and would merge cleanly, so `INDEX.md` is the tripwire. Resolution is to renumber the losing branch to the next free id (rename its folder, fix its `INDEX.md` row); `pr-rebase` does this automatically when the only conflict is in `INDEX.md`.

## Contents

```
.autocode/design/<id>-<shortname>/
  DESIGN.md             # epic plan; immutable after the design PR merges
  units/<slug>.md       # one per unit of work; immutable after merge
  PROGRESS.md           # epic rollup, one block per merged unit; living
  progress/<slug>.md    # per-unit detailed log; living
```

Immutable vs living: `DESIGN.md` and `units/*.md` are the spec; once the design PR merges they are not edited (corrections go through a new design PR). `PROGRESS.md` and `progress/*.md` are living, written during implementation. This split is what makes the immutable spec safe to fan out to issues while progress accrues independently.

### Single-unit (flat) designs

When the work is one PR's worth, the epic and the unit are the same thing. The design is flat: no `units/` directory. `DESIGN.md` carries the unit frontmatter (`type:`) and an `## Implementation` section, and is its own unit (slug = `<shortname>`). Fan-out then creates exactly one issue (no epic/sub-issue split), carrying the `autocode:epic=<id>` marker so discovery is identical. `progress/<shortname>.md` is the only per-unit log.

The rule everything keys on: `units/` present -> multi-unit epic; `units/` absent -> flat single issue. Use flat when the plan would otherwise produce a single unit; use multi-unit when the work splits into independently mergeable pieces.

All four are committed. Only the transient state files `.autocode/.impl-context` and `.autocode/.progress-last-sha` (written by `impl-start` and the progress hook) are gitignored.

## DESIGN.md

The epic plan. Opens with a single `# <Title>` H1: a natural-language title for the epic in sentence case (e.g. `# Native GitHub issue types`), distinct from the kebab-case `<shortname>`. It is the epic issue's title at fan-out (a flat design's single issue takes it too). The plan sections follow (conditional ones are included when they carry weight; omit rather than pad a trivial design):

- `## Summary`: one paragraph. Verbatim source for the epic issue body at fan-out, so it must stand alone.
- `## Background` (conditional): brief current-state context. A table (component / file / current behavior) when several pieces interact; a sentence or two otherwise. It frames the change; it does not re-document the codebase.
- `## Architecture`: the proposed design. Packages, interfaces, new deps (or "no architecture impact" explicitly). Include an ASCII diagram when components interact or data crosses a boundary; omit the diagram for a single-file change.
- `## Design decisions`: numbered. Each names the choice, the rationale, and the rejected alternative. One entry per non-obvious decision; obvious choices need none.
- `## Runtime flow` (conditional): numbered end-to-end walk of the behavior at runtime. Include for behavior changes; omit for pure refactors or static config.
- `## Edge cases and error handling`.
- `## Testing strategy`: categories, fakes, minimum coverage.
- `## Alternatives considered` (conditional): rejected whole-design approaches and why. Omit if there were none.
- `## Sources`: every claim cited. Unsubstantiated claims are discarded.
- `## Units`: the DAG overview. One row per unit: slug rendered as a relative link to its file (`[<slug>](units/<slug>.md)`), one-line deliverable, `depends-on`. This is the human-readable index; the authoritative dependency data lives in each unit file's frontmatter. Use relative links here, not absolute `blob` URLs: a relative link resolves at whatever ref the doc is viewed (branch, merge commit, after a rename), whereas `blob` URLs are for the design PR body, where relative links do not resolve.

## units/<slug>.md

One independent unit of work. The filename stem is the unit `<slug>` (kebab-case, unique within the folder). Frontmatter:

```yaml
---
depends-on: [<slug>, ...]   # other unit slugs in this folder; [] if none
type: <issue-type>          # one of the repo's issue types, e.g. task, story, bug
---
```

After the frontmatter, a single `# <Title>` H1: the unit's natural-language title in sentence case, the sub-issue's title at fan-out (distinct from the kebab-case `<slug>`).

Body sections:

- `## Summary`: one paragraph. Verbatim source for the sub-issue body at fan-out.
- `## Implementation`: deliverable, files to create/modify, public interfaces, tests that prove it. High-level; the implementer owns logic.

A unit is a single PR's worth of work. Dependencies between units in the same folder are expected and fine; a unit with `depends-on: []` is immediately workable. The DAG must be acyclic.

## Fan-out to issues

On design-PR merge (mechanically by the GH Action, or via the `design-fanout` skill), each design folder becomes:

- One epic issue: title from the `# <Title>` H1 of `DESIGN.md` (falling back to `<shortname>` if absent), body = `DESIGN.md` `## Summary` + a link to `DESIGN.md` at the merge commit + the epic marker. Issue type `epic`.
- One sub-issue per unit: title from the unit file's `# <Title>` H1 (falling back to `<slug>` if absent), body = the unit's `## Summary` + a link to `units/<slug>.md` at the merge commit + the unit marker. Issue type from the unit's `type` frontmatter. Linked as a sub-issue of the epic.

No issue number is written back into any file. The link is one-directional (issue -> folder) via the body link and the markers below.

### Markers

Every issue of an epic carries a body marker, in an HTML comment so it survives rendering and is never shown:

- epic: `<!-- autocode:epic=<id> -->`
- unit: `<!-- autocode:unit=<id>/<slug> -->`

The marker is the durable issue -> folder link and the unit's slug identity; issue numbers are never written back. How an epic's issues are grouped is the provider's concern: GitHub links each unit as a native sub-issue of the epic and applies no per-epic label; a provider with no native parent/child relationship carries an `autocode-epic:<id>` label on every issue of the epic instead. The markers are identical either way, so discovery and slug mapping are provider-independent.

### Discovery

To find the issue for a given unit, or read the state of an epic's units, ask the provider for the epic's issues and match markers:

```
provider issue-epic-list --epic <id>   # one live call; epic + every unit, state=all
-> epic = the row whose body has autocode:epic=<id>
-> unit = the row whose body has autocode:unit=<id>/<slug>
-> each unit's done-state = that row's status (see issue-lifecycle)
```

The provider resolves the set natively (GitHub: epic found by marker, units from the sub-issue relationship). `impl-start` uses it to compute the DAG-ready set (a unit is workable when every slug in its `depends-on` is a closed/done sub-issue) and to find the sub-issue to link a unit PR to. A flat design returns a single row that is both epic and unit.

## PROGRESS.md

Epic-level rollup, one block appended per merged unit. Written by the unit's PR at merge time (the `impl-push` path appends in-PR; the optional GH Action appends post-merge). Format:

```markdown
# Progress: <shortname>

## <slug> — <merge date>

PR: <url>  Unit: <sub-issue ref>
<one-paragraph what-shipped>
Notes: <issues hit, follow-ups, gotchas worth knowing> (omit if none)
```

A new session that finds an in-flight block from an abandoned session marks it with a `---` rule and starts a fresh block below; no concurrency coordination beyond that.

## progress/<slug>.md

Per-unit detailed log, owned solely by that unit's worktree (no cross-file writes, so parallel units never contend). `impl-start` seeds the header; the `progress-logger` agent appends entries as work proceeds. Format:

```markdown
# <slug>

Epic: <id>-<shortname>  Branch: <branch>  Started: <date>

## <entry timestamp>
<what was attempted, what worked, what failed, troubleshooting steps>
```

Entries capture lessons for any agent that later continues this unit or a sibling unit in the same epic. Written for both completed and abandoned units.

## Lifecycle

States are the four-state model from the `issue-lifecycle` convention (`todo`, `in-progress`, `in-review`, `done`); the convention maps them to the tracker (GitHub: open + `autocode:<state>` label for the open states, `closed` for `done`).

Unit sub-issue:

| Transition | Trigger |
|---|---|
| (created) -> `todo` | fan-out creates the sub-issue |
| `todo` -> `in-progress` | `impl-start` picks the unit (`issue-transition <unit> in-progress`) |
| `in-progress` -> `in-review` | `impl-push` opens the unit PR (`issue-transition <unit> in-review`); PR body carries `Closes #<unit>` |
| `in-review` -> `done` | the unit PR merges; the tracker auto-closes the sub-issue via the `Closes` link |

Epic issue (multi-unit only): no aggregate epic PR exists, so the epic has no `in-review`.

| Transition | Trigger |
|---|---|
| (created) -> `todo` | fan-out creates the epic |
| `todo` -> `in-progress` | the first unit moves to `in-progress` (`impl-start` flips the epic if still `todo`) |
| `in-progress` -> `done` | every unit is `done`; `impl-archive` (or the GH Action) closes the epic |

Flat single-unit design: one issue, no epic/unit split. It runs the unit row directly (`todo` -> `in-progress` -> `in-review` -> `done`).

Done semantics:

- Unit done: its sub-issue is closed (and a `PROGRESS.md` block exists). Read from the discovery call; low-level, per-unit visibility.
- Epic done: the whole folder is moved to `.autocode/archive/<id>-<shortname>/`. Location is the epic-level source of truth. `impl-archive` (manual) or the GH Action moves it once every unit is done and closes the epic.
