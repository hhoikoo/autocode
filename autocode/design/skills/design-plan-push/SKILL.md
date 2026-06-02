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
5. Compose the PR body to a temp file (`body="$(mktemp -d -t autocode-design-pr)/body.md"`) by filling the repo's checked-in PR template, so a design PR reads like every other PR:
   - Open the body with the `Rendered design` link(s) at the very top, before any template section, so a reviewer's first click opens the formatted doc instead of a diff. Derive base + branch:
     ```
     base=$(git remote get-url origin | sed -E 's#(git@|https://)([^:/]+)[:/]#https://\2/#; s#\.git$##')
     branch=$(git rev-parse --abbrev-ref HEAD)
     ```
     Link: `$base/blob/$branch/.autocode/design/<id>-<shortname>/DESIGN.md` (add one per `units/<slug>.md`, multi-unit). The branch ref keeps the link current as commits land during review; after merge the branch is gone, but fan-out writes the permanent link to `DESIGN.md` at the merge commit. (GitHub URL shape; the only supported host.)
   - Below the link, fill the template skeleton (`@.github/PULL_REQUEST_TEMPLATE.md`; the `pr-template` convention is the pointer). Strip its HTML comments. Fill its sections from the design doc, not from a code diff:
     - `## Overview`: the `DESIGN.md` `## Summary`.
     - `## Problem Statement`: the design's motivation (from `## Summary` / `## Background`); keep under four bullets.
     - `## Architecture`: the `DESIGN.md` architecture diagram if it has one (the rendered-doc link is already at the top).
     - `## Checklist`: copy items verbatim; check `Documentation added or modified appropriately` (the design doc is the doc), leave the issue-mention item unchecked (no issue exists pre-fan-out), and mark the test-case item n/a (the PR is text).
6. Delegate to `pr-create --lightweight --body-file "$body"`. `--lightweight` skips issue linking and background `pr-hygiene` (the issues do not exist yet); `--body-file` supplies the composed body verbatim.
7. Report the PR URL. Suggest `/design-plan-iterate` once reviews land, and note that merging this PR triggers fan-out (the `design-fanout` skill or the optional Action).

## Rules

- Refuse `--temp` plans. Tell the user to promote to `.autocode/design/` first.
- Compose the design-PR body here by filling the repo PR template from the design doc (not a diff) and adding the rendered-doc link; delegate everything else. Do not inline commit logic; `git-commit` owns it.
- The PR is text-only; never run a verify step.
- No issue is created or linked here; fan-out happens at merge.

$ARGUMENTS
