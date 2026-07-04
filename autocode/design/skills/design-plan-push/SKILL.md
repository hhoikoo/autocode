# Design plan push

Open a PR for a design folder (the epic plan plus its units). Merging it is what triggers fan-out into issues.

Layout: `@~/.autocode/autocode/design/design-folder.md`.

## Args

`<id>` or `<shortname>` (the design folder prefix or suffix).

`--temp` plans are refused. The user must promote the temp folder into `.autocode/design/` first.

## Discovery

- If the arg looks like a path: refuse (temp plans not supported here).
- Else glob `.autocode/design/<id>-*` or `*-<shortname>`. Resolve to one folder.
- On no match in the main checkout, run `git worktree list` and glob `<wt>/.autocode/design/<id>-*` / `*-<shortname>` in each worktree: a fresh session's design folder lives uncommitted in the plan worktree. Use that worktree as the working dir.
- On no match anywhere, ask the user via `AskUserQuestion`.

## Workflow

1. Locate `.autocode/design/<id>-<shortname>/`. Confirm `DESIGN.md` exists. Stop on no match.
2. Ensure a worktree + docs branch per `@~/.autocode/autocode/_config/guides/worktree.md`, then delegate to `git-create-branch "docs: design <shortname>"` (skipped if `design-plan` already created the worktree this session). In a fresh session the design folder is uncommitted in the plan worktree; Discovery above locates it via `git worktree list`, so operate in that worktree.
3. Stage the design folder: `git add .autocode/design/<id>-<shortname>/`.
4. Delegate to `git-commit` (forward a context note describing the design).
5. Compose the PR body per the canonical recipe in `@~/.autocode/autocode/design/design-pr-body.md`, passing `<folder>` (from step 1) and the resolved base. That recipe owns the rendered-design link and the template fill, so the body stays identical to what `pr-hygiene` recomposes on later refresh. Capture the temp path it writes as `body`.
6. Delegate to `pr-create --lightweight --body-file "$body"`. `--lightweight` skips issue linking and background `pr-hygiene` (the issues do not exist yet); `--body-file` supplies the composed body verbatim.
7. Report the PR URL. Suggest `/design-plan-iterate` once reviews land, and note that merging this PR triggers fan-out (the `design-fanout` skill or the optional Action).

## Rules

- Refuse `--temp` plans. Tell the user to promote to `.autocode/design/` first.
- Compose the design-PR body here by filling the repo PR template from the design doc (not a diff) and adding the rendered-doc link; delegate everything else. Do not inline commit logic; `git-commit` owns it.
- The PR is text-only; never run a verify step.
- No issue is created or linked here; fan-out happens at merge.

$ARGUMENTS
