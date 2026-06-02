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
     - `## Summary`: one paragraph; the verbatim epic issue body at fan-out, so it must stand alone.
     - `## Background`: brief. A current-state table when several pieces interact, a sentence or two otherwise.
     - `## Architecture`: draw an ASCII diagram whenever components interact or data crosses a boundary. A wall of prose where a diagram fits is the most common failure of this skill.
     - `## Design decisions`: one numbered entry per non-obvious choice. State the decision, why, and the alternative you rejected. Obvious choices need no entry.
     - `## Runtime flow`: number the steps end to end. Include for behavior changes; skip for static config or pure refactors.
     - `## Alternatives considered`: rejected whole-design approaches and why; omit if none.
     - `## Sources`: every claim cited. Unsubstantiated claims are discarded.
     - `## Units`: table of `slug`, one-line deliverable, `depends-on`. The human-readable DAG index.
     - Borrow these qualities, do not copy any one example's literal layout: the goal is diagrams and structured rationale, not a fixed template.
   - For each unit, `units/<slug>.md`:
     - Frontmatter: `depends-on: [<slug>...]` (other slugs in this folder; `[]` if none) and `type: <issue-type>` (an issue type from the repo's `issue-types` convention at `$AUTOCODE_CONFIG_DIR/conventions/issue-types.md`, typically `task`, `story`, or `bug`).
     - `## Summary` (one paragraph; verbatim sub-issue body at fan-out).
     - `## Implementation`: deliverable, files to create/modify, public interfaces (signatures, struct types), tests that prove it. High-level. No inline code, no pseudo-code. The implementer owns logic.
   - Flat designs (single unit): omit the `## Units` section and the `units/` directory. `DESIGN.md` instead carries frontmatter `type: <issue-type>` and its own `## Implementation` section (same shape as a unit). It is its own unit, slug `<shortname>`. The conditional sections (diagram, design decisions, runtime flow) still apply, but stay lean: a one-PR design rarely needs all of them.
5. Write the folder.
   - Ask the user for `<shortname>` via `AskUserQuestion`. Kebab-case, lowercase, 2-4 words. (`<id>` is allocated from `INDEX.md` in the without-temp branch below; temp designs have no id.)
   - Multi-unit: write `DESIGN.md` plus each `units/<slug>.md`. Flat: write `DESIGN.md` only (no `units/`).
   - With `--temp`: `dir=$(mktemp -d -t autocode-design)`. Write the files under `$dir`. Stop. No worktree (the temp dir is outside the repo). Final report: print `$dir`. Suggest `/design-plan-critique $dir`.
   - Without `--temp`: the folder is a repo change, so isolate it in a worktree first. Ensure a worktree per `@~/.autocode/autocode/_config/guides/worktree.md`, then delegate `git-create-branch "docs: design <shortname>"` inside it. `repo_root=$(git rev-parse --show-toplevel)` (now the worktree). Allocate `<id>` from the index: read `$repo_root/.autocode/design/INDEX.md` (create it with the header from the design-folder spec if absent); `<id>` = highest id in the table + 1, zero-padded to 4 digits (`0001` if empty). Create `$repo_root/.autocode/design/<id>-<shortname>/` (plus `units/` when multi-unit) and write the files. Append a row to `INDEX.md`: `<id>`, `<shortname>`, today's UTC date (`date -u +%Y-%m-%d`), `active`. Final report: worktree path, branch, folder path, and `<id>`. Note the folder is uncommitted in the worktree; suggest `/design-plan-critique <id>`, or `/design-plan-push <id>` in this same session to commit and open the PR.

No issue is created here. The epic issue and per-unit sub-issues are created only when the design PR merges, by `design-fanout` or the optional GitHub Action.

## Rules

- Every unit lists the files it touches; if you cannot list files, the unit is not specific enough.
- `DESIGN.md` and every unit carry a `## Summary`; these are the verbatim issue bodies at fan-out.
- `depends-on` forms an acyclic DAG. Each unit must be independently mergeable once its dependencies are merged.
- Prefer "I don't know" over a guess. Send the gap to a researcher or the user; do not paper over it.
- Sources section is mandatory. Each claim has a citation (codebase path, URL, or user statement).
- No phase numbers in commits, code, or PR titles.

$ARGUMENTS
