# Design plan push

Open a PR for a design folder (the epic plan plus its units). Merging it is what triggers fan-out into issues.

Layout: `@~/.autocode/autocode/design/design-folder.md`.

## Args

`<id>` or `<shortname>` (the design folder prefix or suffix).

`--temp` plans are refused. The user must promote the temp folder into `.autocode/design/` first.

## Discovery

- If the arg looks like a path: refuse (temp plans not supported here).
- Else glob `.autocode/design/<id>-*` or `*-<shortname>`. Resolve to one folder.
- On no match, ask the user via `AskUserQuestion`.

## Workflow

1. Locate `.autocode/design/<id>-<shortname>/`. Confirm `DESIGN.md` exists. Stop on no match.
2. Ensure a worktree + docs branch per `@~/.autocode/autocode/_config/guides/worktree.md`, then delegate to `git-create-branch "docs: design <shortname>"` (skipped if `design-plan` already created the worktree this session). Run this in the same session as `design-plan`: the design folder is uncommitted in that worktree, so on the default branch in a fresh session the glob below will not find it.
3. Stage the design folder: `git add .autocode/design/<id>-<shortname>/`.
4. Delegate to `git-commit` (forward a context note describing the design).
5. Compose the PR body to a temp file (`body="$(mktemp -d -t autocode-design-pr)/body.md"`):
   - The `DESIGN.md` `## Summary` verbatim.
   - A `Rendered design` link to the doc on the PR branch so reviewers read it formatted, not as a diff. Derive the web base from the origin remote and the current branch:
     ```
     base=$(git remote get-url origin | sed -E 's#(git@|https://)([^:/]+)[:/]#https://\2/#; s#\.git$##')
     branch=$(git rev-parse --abbrev-ref HEAD)
     ```
     Link: `$base/blob/$branch/.autocode/design/<id>-<shortname>/DESIGN.md`. Multi-unit: add one link per `units/<slug>.md` under the same path. (GitHub URL shape; the only supported host.)
   - A bullet list of the design's section headings (and unit slugs, if multi-unit).
6. Delegate to `pr-create --lightweight --body-file "$body"`. `--lightweight` skips issue linking and background `pr-hygiene` (the issues do not exist yet); `--body-file` supplies the composed body verbatim.
7. Report the PR URL. Suggest `/design-plan-iterate` once reviews land, and note that merging this PR triggers fan-out (the `design-fanout` skill or the optional Action).

## Rules

- Refuse `--temp` plans. Tell the user to promote to `.autocode/design/` first.
- Compose the design-PR body here (Summary + rendered-doc link + section headings); delegate everything else. Do not inline commit logic; `git-commit` owns it.
- The PR is text-only; never run a verify step.
- No issue is created or linked here; fan-out happens at merge.

$ARGUMENTS
