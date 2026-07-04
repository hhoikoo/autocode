# Design plan critique

Iteratively interrogate a written plan: generate follow-up questions, resolve them (research or user), and apply resolutions in place.

## Args

One of:
- `<path>`: the temp folder returned by `design-plan --temp`.
- `<id>` (the design folder zero-padded integer prefix, e.g. `0007`).
- `<feature-shortname>` (the kebab-case suffix of a `.autocode/design/*/` directory).
- nothing: defaults to the most recent `.autocode/design/*` dir (skip `INDEX.md`, the id registry, not an epic folder). On ambiguity, ask via `AskUserQuestion` (non-`--auto`) or fail-fast with `status: error` (`--auto`).
- `--auto`: run unattended. The critique loop runs off-context via the Workflow tool, suppresses both `AskUserQuestion` gates, and ends with a structured result block instead of the prose summary.

## Discovery

- If arg looks like a path to a folder, use it.
- Else glob `.autocode/design/<id>-*` or `*-<shortname>`.
- On no match: without `--auto`, ask the user via `AskUserQuestion`; with `--auto`, emit `status: error` with a descriptive message and stop (do not launch the workflow).

## --auto launcher

When invoked with `--auto`:

1. Resolve `homeDir` via `echo "$HOME"`, `repoRoot` via `git rev-parse --show-toplevel`, and `folder` via the discovery glob above.
2. On ambiguous or unresolvable arg: emit the structured block with `status: error` and a descriptive message. No `AskUserQuestion`. Do not launch the workflow.
3. Launch the Workflow tool with `scriptPath: <homeDir>/.autocode/autocode/design/skills/design-plan-critique/scripts/design-critique-workflow.mjs` and `args: { homeDir, repoRoot, folder }`. Wait for completion.
4. Emit the workflow's return verbatim as the structured result block below. No surrounding prose.

Structured result block:

```
status: done | cap_reached | error
iterations_run: <int>
questions_resolved: <int>
needs_human: <bool>
needs_human_reasons: [{ question, why }, ...]
files_modified: [<path>, ...]
critique_log_path: <path to DESIGN.md holding the ## Critique log>
```

Field semantics:
- `status: done` = converged before the cap; `cap_reached` = stopped at 5 iterations with open questions remaining; `error` = fail-fast during discovery (other fields omitted or zeroed).
- `needs_human: true` when any question was unresolvable by research or when `cap_reached` with open questions.
- `files_modified` = DESIGN.md + any `units/*.md` edited this run.
- `critique_log_path` = the DESIGN.md holding the `## Critique log`.

## Workflow (non-`--auto`, interactive)

The `--auto` path short-circuits to the launcher above; the following steps are the non-`--auto` in-session loop, preserved unchanged.

1. Read the design: `DESIGN.md` and every `units/*.md` (multi-unit) or just `DESIGN.md` (flat).
2. Generate follow-up questions per section and per unit. Bias toward: untested assumptions, interface shapes, error modes, concurrency, security, data shape, ordering invariants, whether the unit decomposition and `depends-on` edges are right, and over-engineering (speculative scope, single-implementation abstractions, unneeded dependencies, dead flexibility).
3. For each question, decide: ask the user, dispatch a researcher, or both (parallel where possible). To ask the user, delegate to `design-grill`'s interview protocol (batched `AskUserQuestion`, dependency order, a recommended answer as each question's first option); read its body for the mechanics.
4. Apply resolutions in place to the relevant file (`DESIGN.md` or the unit file). Preserve existing structure; add a `## Critique log` at the bottom of `DESIGN.md` that lists each iteration's questions and resolutions (one line each).
   - Make the decisions (questions, resolutions, sources) in the main session. The apply may fan out: when several units change in a pass, dispatch one generic Task subagent per affected unit in parallel, each handed the exact resolutions to write into its `units/<slug>.md`. Keep `DESIGN.md` edits and the `## Critique log` in the main session (shared file, serial). Use judgement: fan out when several units change, edit inline when only one does.
5. Repeat steps 2-4 until a pass produces no new questions. Cap iterations at 5. On cap, ask the user via `AskUserQuestion` whether to continue.

## Output

Non-`--auto`: updates the design files in place. Final report is a summary of iterations and what changed (the critique log already captures detail; the report is a 2-3 line summary).

`--auto`: emits the structured result block above. No surrounding prose.

## Rules

- Edit in place. Preserve section structure.
- Every resolution cites its source (research finding, user statement). Same source rule as `design-plan`.
- Never delete sections; mark them as "(resolved)" or "(deferred)" if a question subsumes them.
- Stop at 5 iterations or when no new questions emerge, whichever comes first.
- Under `--auto`: the loop runs off-context (Workflow tool), no `AskUserQuestion` at any point, structured return only. The non-`--auto` interactive in-session loop is unchanged and is the only path that retains both `AskUserQuestion` gates.

$ARGUMENTS
