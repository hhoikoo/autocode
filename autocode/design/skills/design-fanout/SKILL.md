# Design fanout

Turn a merged design folder into tracker issues: an epic plus one sub-issue per unit (or a single issue for a flat design). The manual, Claude-driven counterpart of the optional GitHub Action. Run after the design PR merges.

Layout, markers, and labels: `@~/.autocode/autocode/design/design-folder.md`. This skill produces exactly the tags and markers it specifies, so `impl-start` discovery works identically whether issues were created here or by the Action.

## Args

`<id | shortname>` (the design folder prefix or suffix). Default: the most recent folder under `.autocode/design/`. On ambiguity, ask via `AskUserQuestion`.

## Discovery

- Glob `.autocode/design/<id>-*` or `*-<shortname>`. Resolve to one folder; read its `DESIGN.md` and any `units/*.md`.
- Derive `<id>` and `<shortname>` from the folder name.
- Multi-unit if `units/` exists and is non-empty; flat otherwise.

## Workflow

1. Build the permalink base. `sha=$(git log -1 --format=%H -- <folder>)` (the commit that last touched the folder, i.e. the merge). `repo_url=$(gh repo view --json url --jq .url)`. A file's link is `<repo_url>/blob/<sha>/<repo-relative-path>`. (Permalink shape is GitHub-specific; acceptable while `git-remote` is GitHub.)
2. Ensure the epic tag exists: `provider/run.sh issue-tracker issue-label-ensure "autocode-epic:<id>" --description "autocode design epic <id>"`.
3. Idempotency check. `provider/run.sh issue-tracker issue-list --label "autocode-epic:<id>" --state all`. Parse the returned `description` of each issue for existing markers (`autocode:epic=<id>`, `autocode:unit=<id>/<slug>`). Skip creating anything whose marker is already present; report it as existing.
4. Create issues. For each issue, build a body temp file: the source file's `## Summary` paragraph, then a blank line, then `Design: <permalink>`, then a blank line, then the HTML-comment marker. Write it with the Write tool, then call the provider.

   Multi-unit:
   - Epic (if its marker is absent): body from `DESIGN.md` `## Summary` + `DESIGN.md` permalink + `<!-- autocode:epic=<id> -->`. `provider/run.sh issue-tracker issue-create -t epic -s "<shortname>" -b "<body>" -l "autocode-epic:<id>"`. Capture the epic number.
   - Each unit `units/<slug>.md` (if its marker is absent): body from the unit's `## Summary` + the unit file permalink + `<!-- autocode:unit=<id>/<slug> -->`. `provider/run.sh issue-tracker issue-create -t <unit.type> -s "<slug>" -b "<body>" -l "autocode-epic:<id>" -P <epic-number>`.

   Flat (no `units/`):
   - One issue (if `autocode:epic=<id>` marker absent): body from `DESIGN.md` `## Summary` + permalink + `<!-- autocode:epic=<id> -->`. `provider/run.sh issue-tracker issue-create -t <DESIGN.type> -s "<shortname>" -b "<body>" -l "autocode-epic:<id>"`. No parent. This issue is both epic and unit.
5. Report a table: each issue's role (epic / unit slug), number, and created-or-existing.

## Rules

- All tracker writes go through `provider/run.sh issue-tracker ...`. Never call `gh issue` directly. (`gh repo view` for the permalink base is the only direct `gh` read.)
- Idempotent. Re-running creates only the issues whose markers are missing; never duplicates.
- The unit issue `type` comes from the unit file's `type:` frontmatter; the epic is always type `epic`; a flat design's single issue takes `DESIGN.md`'s `type:` frontmatter.
- Do not write issue numbers back into any file. The link runs issue -> folder via the permalink and markers.
- Run only after the design PR merged; the permalink must point at a commit on the default branch.

$ARGUMENTS
