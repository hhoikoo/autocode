# Design plan

Plan a non-trivial implementation as an epic: rough sketch, gap identification, parallel research, then a written plan decomposed into independent units of work (a DAG). Output is a design folder, not a single document.

Layout authority: `@~/.autocode/autocode/design/design-folder.md`. Read it; this skill produces exactly that structure.

## Args

- Freeform user description (typical), or
- `--temp` (or `--temporary`): write the folder to a temp directory instead of the repo. Same structure; for throwaway critique only.

## Workflow

1. Treat `$ARGUMENTS` as the seed. If empty, ask via `AskUserQuestion` for a one-paragraph description.
2. Rough sketch from conversation context only. No research yet. Surface what the model already thinks so gaps are easier to identify.
3. Gap identification. List every assumption, every unknown library/API, every "I'm guessing X". Decide per gap:
   - dispatch `codebase-researcher` (current repo) in background,
   - dispatch `codebase-researcher` (cross-project) in background,
   - dispatch `web-researcher` in background,
   - ask the user.
   Launch researchers in parallel (single message, multiple Task tool calls). They return verbatim findings; fold them into the plan.
4. Compose the epic plan and decompose it into units once research returns.
   - Decide multi-unit vs flat. If the work is one PR's worth, produce a flat single-unit design: `DESIGN.md` only, no `units/` (see "Flat designs" below). Otherwise decompose into independent units of work, each one PR's worth with a single clear deliverable; identify dependencies between units and confirm the graph is acyclic. A unit that depends on nothing is immediately workable.
   - `DESIGN.md` sections (multi-unit): `design-folder.md` is the authority for the section set and when each conditional one applies. Do not restate or reorder it here. Writing guidance for the sections that carry the explanation:
     - `# <Title>`: the opening H1. A natural-language epic title in sentence case (not the kebab-case `<shortname>`); the epic issue's title at fan-out.
     - `## Summary`: one paragraph; the verbatim epic issue body at fan-out, so it must stand alone.
     - `## Background`: brief. A current-state table when several pieces interact, a sentence or two otherwise.
     - `## Architecture`: draw an ASCII diagram whenever components interact or data crosses a boundary. A wall of prose where a diagram fits is the most common failure of this skill.
     - `## Design decisions`: one numbered entry per non-obvious choice. State the decision, why, and the alternative you rejected. Obvious choices need no entry.
     - `## Runtime flow`: number the steps end to end. Include for behavior changes; skip for static config or pure refactors.
     - `## Alternatives considered`: rejected whole-design approaches and why; omit if none.
     - `## Sources`: every claim cited. Unsubstantiated claims are discarded.
     - `## Units`: table of `slug` (a relative link to `units/<slug>.md`), one-line deliverable, `depends-on`. The human-readable DAG index. Relative links, not `blob` URLs: relative resolves at any ref; blob URLs are for the PR body.
     - Borrow these qualities, do not copy any one example's literal layout: the goal is diagrams and structured rationale, not a fixed template.
   - Per unit, decide only the assignment, not the prose: `slug` (kebab-case, unique in the folder), one-line deliverable, `depends-on` (sibling slugs), and `type` (an issue type from `$AUTOCODE_CONFIG_DIR/conventions/issue-types.md`, typically `task`, `story`, or `bug`). The `units/<slug>.md` file itself (`## Summary` + `## Implementation`) is authored by the `design-unit-author` agent in step 5, one instance per unit; you do not write unit files inline. The unit-file shape is in `design-folder.md`.
   - Flat designs (single unit): omit the `## Units` section and the `units/` directory. `DESIGN.md` instead carries frontmatter `type: <issue-type>` and its own `## Implementation` section (same shape as a unit). It is its own unit, slug `<shortname>`. The conditional sections (diagram, design decisions, runtime flow) still apply, but stay lean: a one-PR design rarely needs all of them.
5. Write the folder.
   - Ask the user for `<shortname>` via `AskUserQuestion`. Kebab-case, lowercase, 2-4 words. (`<id>` is allocated from `INDEX.md` in the without-temp branch below; temp designs have no id.)
   - Resolve and create the target folder `<folder>` (with a `units/` subdir when multi-unit):
     - With `--temp`: `dir=$(mktemp -d -t autocode-design)`; `<folder>=$dir`. No worktree (the temp dir is outside the repo), no id, never touch `INDEX.md`.
     - Without `--temp`: the folder is a repo change, so isolate it in a worktree first. Ensure a worktree per `@~/.autocode/autocode/_config/guides/worktree.md`, then delegate `git-create-branch "docs: design <shortname>"` inside it. `repo_root=$(git rev-parse --show-toplevel)` (now the worktree). Allocate `<id>` from the index: read `$repo_root/.autocode/design/INDEX.md` (create it with the header from the design-folder spec if absent); `<id>` = highest id in the table + 1, zero-padded to 4 digits (`0001` if empty). `<folder>=$repo_root/.autocode/design/<id>-<shortname>/`. Append a row to `INDEX.md`: `<id>`, `<shortname>`, today's UTC date (`date -u +%Y-%m-%d`), `active`.
   - Write `DESIGN.md` into `<folder>` yourself: the epic plan is your synthesis, kept on the main session so the narrative stays coherent.
   - Multi-unit: author the unit files by fan-out, not inline. Dispatch the `design-unit-author` agent (opus), one instance per unit, in a single message (parallel) via the Task tool. Each prompt carries: `<folder>` and its worktree, the full `DESIGN.md` text, that unit's assignment (`slug`, one-line deliverable, `depends-on`, `type`), and the research findings relevant to that unit. The agents write `<folder>/units/<slug>.md` concurrently into the same worktree; distinct files, so parallel-safe. Wait for all to return. If one reports its unit underspecified, resolve it (more research or a tighter deliverable) and re-dispatch that one instance.
   - Flat: write `DESIGN.md` (frontmatter `type:` plus `## Implementation`) yourself; no fan-out, the single unit is the epic.
   - Final report:
     - With `--temp`: print `$dir`. Suggest `/design-plan-critique $dir`.
     - Without `--temp`: worktree path, branch, folder path, and `<id>`. Note the folder is uncommitted in the worktree; suggest `/design-plan-critique <id>`, or `/design-plan-push <id>` in this same session to commit and open the PR.

No issue is created here. The epic issue and per-unit sub-issues are created only when the design PR merges, by `design-fanout` or the optional GitHub Action.

## Rules

- Every unit lists the files it touches; if you cannot list files, the unit is not specific enough.
- `DESIGN.md` and every unit open with a `# <Title>` H1 (natural language, sentence case) and carry a `## Summary`; the H1 is the issue title and the `## Summary` the verbatim issue body at fan-out.
- `depends-on` forms an acyclic DAG. Each unit must be independently mergeable once its dependencies are merged.
- Prefer "I don't know" over a guess. Send the gap to a researcher or the user; do not paper over it.
- Sources section is mandatory. Each claim has a citation (codebase path, URL, or user statement).
- No phase numbers in commits, code, or PR titles.

$ARGUMENTS
