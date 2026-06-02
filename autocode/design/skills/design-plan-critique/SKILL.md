# Design plan critique

Iteratively interrogate a written plan: generate follow-up questions, resolve them (research or user), and apply resolutions in place.

## Args

One of:
- `<path>`: the temp folder returned by `design-plan --temp`.
- `<id>` (the design folder zero-padded integer prefix, e.g. `0007`).
- `<feature-shortname>` (the kebab-case suffix of a `.autocode/design/*/` directory).
- nothing: defaults to the most recent `.autocode/design/*` dir (skip `INDEX.md`, the id registry, not an epic folder). On ambiguity, ask via `AskUserQuestion`.

## Discovery

- If arg looks like a path to a folder, use it.
- Else glob `.autocode/design/<id>-*` or `*-<shortname>`.
- On no match, ask the user via `AskUserQuestion`.

## Workflow

1. Read the design: `DESIGN.md` and every `units/*.md` (multi-unit) or just `DESIGN.md` (flat).
2. Generate follow-up questions per section and per unit. Bias toward: untested assumptions, interface shapes, error modes, concurrency, security, data shape, ordering invariants, and whether the unit decomposition and `depends-on` edges are right.
3. For each question, decide: ask the user, dispatch a researcher, or both (parallel where possible).
4. Apply resolutions in place to the relevant file (`DESIGN.md` or the unit file). Preserve existing structure; add a `## Critique log` at the bottom of `DESIGN.md` that lists each iteration's questions and resolutions (one line each).
   - Make the decisions (questions, resolutions, sources) in the main session. The apply may fan out: when several units change in a pass, dispatch one generic Task subagent per affected unit in parallel, each handed the exact resolutions to write into its `units/<slug>.md`. Keep `DESIGN.md` edits and the `## Critique log` in the main session (shared file, serial). Use judgement: fan out when several units change, edit inline when only one does.
5. Repeat steps 2-4 until a pass produces no new questions. Cap iterations at 5. On cap, ask the user via `AskUserQuestion` whether to continue.

## Output

Updates the design files in place. Final report is a summary of iterations and what changed (the critique log already captures detail; the report is a 2-3 line summary).

## Rules

- Edit in place. Preserve section structure.
- Every resolution cites its source (research finding, user statement). Same source rule as `design-plan`.
- Never delete sections; mark them as "(resolved)" or "(deferred)" if a question subsumes them.
- Stop at 5 iterations or when no new questions emerge, whichever comes first.

$ARGUMENTS
