# Design fanout

Turn a merged design folder into tracker issues: an epic plus one sub-issue per unit (or a single issue for a flat design). The manual, Claude-driven counterpart of the optional GitHub Action. Run after the design PR merges.

Layout, markers, and labels: `@~/.autocode/autocode/design/design-folder.md`. This skill produces exactly the tags and markers it specifies, so `impl-start` discovery works identically whether issues were created here or by the Action.

## Args

- `<id | shortname>`: the design folder prefix or suffix. Default: the most recent folder under `.autocode/design/`. On ambiguity, ask via `AskUserQuestion`.
- `--auto`: run unattended (no `AskUserQuestion`); the id is required (no implicit most-recent); an absent, unknown, or ambiguous arg returns `needs_human: true` and creates nothing; the final report is the structured result block (below) in place of the step-4 prose table. Interactive behavior is unchanged when `--auto` is absent.

## Discovery

- Glob `.autocode/design/<id>-*` or `*-<shortname>`. Resolve to one folder; read its `DESIGN.md` and any `units/*.md`.
- Derive `<id>` and `<shortname>` from the folder name.
- Multi-unit if `units/` exists and is non-empty; flat otherwise.
- Under `--auto`, resolution is strict. If the arg is absent, matches no folder, or matches more than one folder, do not prompt and do not glob a default; stop before the step-1 permalink base and step-2 idempotency call and emit `{ needs_human: true, epic_key: "", sub_issues: [], reason: <names the missing/unknown id or the candidate folders> }`. Default mode keeps the most-recent default and the `AskUserQuestion` disambiguation verbatim.

   Success-path structured result block (emitted by step 4 under `--auto`):
   `{ needs_human: false, epic_key: <key>, sub_issues: [{ slug: <slug>, key: <key>, status: "created" | "existing" }], reason: "" }`

## Workflow

1. Build the permalink base. `sha=$(git log -1 --format=%H -- <folder>)` (the commit that last touched the folder, i.e. the merge). `repo_url=$(gh repo view --json url --jq .url)`. A file's link is `<repo_url>/blob/<sha>/<repo-relative-path>`. (Permalink shape is GitHub-specific; acceptable while `git-remote` is GitHub.)
2. Idempotency check. `provider/run.sh issue-tracker issue-epic-list --epic <id>` returns the epic plus any units already created (`[]` if the design has not been fanned out). Parse each row's `description` for markers (`autocode:epic=<id>`, `autocode:unit=<id>/<slug>`). Skip creating anything whose marker is already present; report it as existing.
3. Backfill seed (multi-unit only). Before the issue-creation loop, check whether `<folder>/PROGRESS.md` exists. If absent, create it with exactly the line `# Progress: <shortname>` (the canonical header; format authority: the `## PROGRESS.md` section of `design-folder.md`; same string that `design-plan` seeds at folder creation). If it already exists, leave it untouched (idempotent: never clobber a `PROGRESS.md` that already carries appended blocks). Skip for flat designs (one unit, no concurrent append; seed is inert).

4. Create issues. For each issue, build a body temp file: the source file's `## Summary` paragraph, then a blank line, then `Design: <permalink>`, then a blank line, then the HTML-comment marker. Write it with the Write tool, then call the provider.

   The issue title (`-s`) is the source file's `# <Title>` H1: `DESIGN.md`'s for the epic/flat issue (fall back to `<shortname>`), the unit file's for each unit (fall back to `<slug>`).

   Multi-unit:
   - Epic (if its marker is absent): body from `DESIGN.md` `## Summary` + `DESIGN.md` permalink + `<!-- autocode:epic=<id> -->`. `provider/run.sh issue-tracker issue-create -t epic -s "<DESIGN.md H1>" -b "<body>"`. Capture the epic number.
   - Each unit `units/<slug>.md` (if its marker is absent): body from the unit's `## Summary` + the unit file permalink + `<!-- autocode:unit=<id>/<slug> -->`. `provider/run.sh issue-tracker issue-create -t <unit.type> -s "<unit H1>" -b "<body>" -P <epic-number>`. The `-P` link makes it a native sub-issue of the epic; no per-epic label is applied.

   Flat (no `units/`):
   - One issue (if `autocode:epic=<id>` marker absent): body from `DESIGN.md` `## Summary` + permalink + `<!-- autocode:epic=<id> -->`. `provider/run.sh issue-tracker issue-create -t <DESIGN.type> -s "<DESIGN.md H1>" -b "<body>"`. No parent. This issue is both epic and unit.
5. Report. Default: a table of each issue's role (epic / unit slug), number, and created-or-existing. With `--auto`: emit the success structured result block (`needs_human: false`, `epic_key`, `sub_issues`) in place of the table.

## Rules

- All tracker writes go through `provider/run.sh issue-tracker ...`. Never call `gh issue` directly. (`gh repo view` for the permalink base is the only direct `gh` read.)
- Idempotent. Re-running creates only the issues whose markers are missing; never duplicates.
- The unit issue `type` comes from the unit file's `type:` frontmatter; the epic is always type `epic`; a flat design's single issue takes `DESIGN.md`'s `type:` frontmatter.
- Do not write issue numbers back into any file. The link runs issue -> folder via the permalink and markers.
- Run only after the design PR merged; the permalink must point at a commit on the default branch.

$ARGUMENTS
