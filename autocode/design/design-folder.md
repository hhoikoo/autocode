# Design folder layout

Canonical structure for a design epic: one folder holding the epic plan, its independent units of work (a DAG), and the living progress log. Fixed across all autocode repos. `design-plan` creates it; the design-PR fan-out turns it into issues; `impl-start` consumes it; the progress log tracks it. Skills `@`-import this file rather than restating the layout.

## Location and naming

```
.autocode/design/<id>-<shortname>/
```

- `<id>`: UTC timestamp, `date -u +%Y%m%dT%H%M%SZ` (e.g. `20260601T143022Z`). Lexicographically sortable so `ls` orders epics by creation. Generated once at `design-plan` time and used as the folder name immediately (it depends on nothing external).
- `<shortname>`: kebab-case, 2-4 words, human label.
- The folder is never renamed. No issue number is ever encoded in the path; issues do not exist until the design PR merges, and the link runs issue -> folder (see Fan-out).

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

When the work is one PR's worth, the epic and the unit are the same thing. The design is flat: no `units/` directory. `DESIGN.md` carries the unit frontmatter (`type:`) and an `## Implementation` section, and is its own unit (slug = `<shortname>`). Fan-out then creates exactly one issue (no epic/sub-issue split), still tagged `autocode-epic:<id>` so discovery is identical. `progress/<shortname>.md` is the only per-unit log.

The rule everything keys on: `units/` present -> multi-unit epic; `units/` absent -> flat single issue. Use flat when the plan would otherwise produce a single unit; use multi-unit when the work splits into independently mergeable pieces.

All four are committed. Only the transient state files `.autocode/.impl-context` and `.autocode/.progress-last-sha` (written by `impl-start` and the progress hook) are gitignored.

## DESIGN.md

The epic plan. Sections:

- `## Summary`: one paragraph. Verbatim source for the epic issue body at fan-out, so it must stand alone.
- `## Architecture impact`, `## Edge cases and error handling`, `## Testing strategy`, `## Sources`: as in the `design-plan` flow.
- `## Units`: the DAG overview. One row per unit: slug, one-line deliverable, `depends-on`. This is the human-readable index; the authoritative dependency data lives in each unit file's frontmatter.

## units/<slug>.md

One independent unit of work. The filename stem is the unit `<slug>` (kebab-case, unique within the folder). Frontmatter:

```yaml
---
depends-on: [<slug>, ...]   # other unit slugs in this folder; [] if none
type: <issue-type>          # one of the repo's issue types, e.g. task, story, bug
---
```

Body sections:

- `## Summary`: one paragraph. Verbatim source for the sub-issue body at fan-out.
- `## Implementation`: deliverable, files to create/modify, public interfaces, tests that prove it. High-level; the implementer owns logic.

A unit is a single PR's worth of work. Dependencies between units in the same folder are expected and fine; a unit with `depends-on: []` is immediately workable. The DAG must be acyclic.

## Fan-out to issues

On design-PR merge (mechanically by the GH Action, or via the `design-fanout` skill), each design folder becomes:

- One epic issue: title from `<shortname>`, body = `DESIGN.md` `## Summary` + a link to `DESIGN.md` at the merge commit + the epic marker. Issue type `epic`.
- One sub-issue per unit: title from the unit, body = the unit's `## Summary` + a link to `units/<slug>.md` at the merge commit + the unit marker. Issue type from the unit's `type` frontmatter. Linked as a sub-issue of the epic.

No issue number is written back into any file. The link is one-directional (issue -> folder) via the body link and the markers below.

### Tags and markers

Every issue of an epic carries:

- Epic tag `autocode-epic:<id>` (a tracker label or equivalent). Applied to the epic issue and every unit sub-issue. List-filterable in one live call, so discovery never depends on a search index.
- Body marker, in an HTML comment so it survives rendering and is never shown:
  - epic: `<!-- autocode:epic=<id> -->`
  - unit: `<!-- autocode:unit=<id>/<slug> -->`

### Discovery

To find the issue for a given unit, or to read the state of an epic's units, list issues by the epic tag and match markers:

```
list issues with tag autocode-epic:<id>, state=all   # one live provider call
-> epic = the body with autocode:epic=<id>
-> unit = the body with autocode:unit=<id>/<slug>
-> each unit's done-state = that issue's state (see issue-lifecycle)
```

`impl-start` uses this to compute the DAG-ready set (a unit is workable when every slug in its `depends-on` has a closed/done sub-issue) and to find the sub-issue to link a unit PR to.

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
