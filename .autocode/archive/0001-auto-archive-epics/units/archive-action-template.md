---
depends-on: []
type: task
---

# Archive-design GitHub Action template

## Summary

Ship a new pure-bash GitHub Action template `autocode-archive-design`, a sibling of the existing `autocreate-design-doc-issue` fan-out template, that archives a completed design epic by id. It triggers only on `workflow_dispatch` with a required `design_id` input (no on-merge sweep, explicitly rejected in the epic). It resolves the design folder, verifies completeness via the same `autocode:epic`/`autocode:unit` marker-matched `gh` queries the fan-out Action uses (every unit sub-issue closed for multi-unit, the single epic-marked issue closed for flat), and on success creates branch `chore/archive-<id>-<short>`, `git mv`s the folder from `.autocode/design/` to `.autocode/archive/`, flips the epic's `INDEX.md` row from `active` to `archived`, commits, pushes, and opens a PR. Multi-unit PRs carry `Closes #<epic>` so merging closes the epic; flat PRs do not (their single issue was already closed by its own unit PR). The Action is idempotent (skips cleanly if already archived, folder already moved, or the branch/PR already exists) and incomplete-epic-safe (reports outstanding units and aborts without moving anything). It uses `gh` directly like the fan-out Action, not `provider/run.sh`.

## Implementation

Deliverable: the `autocode-archive-design` template directory: a `workflow_dispatch` workflow, a composite action, and a pure-bash archive script, plus bash tests against fixture design folders. The no-AI counterpart of `/impl-archive`, mirroring the `design-fanout`/`autocreate-design-doc-issue` skill/Action duality.

This unit is the template files and their tests ONLY. It does NOT touch `autocode-setup` install wiring or `design-folder.md` (separate units: `lifecycle-and-setup-wiring`).

### Files to read first (study and mirror)

The implementer MUST read these before writing; the new template mirrors their shape, idioms, and `gh` queries:

- `/Users/hhkoo/.autocode/plugins/autocode/templates/autocreate-design-doc-issue/.github/workflows/autocreate-design-doc-issue.yml` (workflow header comment, `permissions` block, checkout + composite-action call shape).
- `/Users/hhkoo/.autocode/plugins/autocode/templates/autocreate-design-doc-issue/.github/actions/design-fanout/action.yml` (composite `runs:` shape, `${{ github.action_path }}/<script>` invocation, `gh api --paginate /repos/$REPO/issues?state=all` epic-by-marker query at action.yml:46-48, GraphQL `sub_issues` header + sub-issue body listing at action.yml:55-57 and :72).
- `/Users/hhkoo/.autocode/plugins/autocode/templates/autocreate-design-doc-issue/.github/actions/design-fanout/render-design-issues.sh` (id/short split idiom `base=$(basename dir); id="${base%%-*}"; short="${base#*-}"` at lines 25-27; flat-vs-multi via `[[ -d "${dir}/units" ]]` at line 60; marker strings `<!-- autocode:epic=${id} -->` line 58 and `<!-- autocode:unit=${id}/${slug} -->` line 69).
- `/Users/hhkoo/.autocode/plugins/autocode/templates/autocreate-design-doc-issue/.github/actions/design-fanout/create-design-issue.sh` (gh-direct usage, GraphQL node-id pattern, `set -euo pipefail` header).

### Files to create

Templates live beside skills' canonical sources, not as shims. Mirror the fan-out template's `.github/` sub-tree exactly.

```
plugins/autocode/templates/autocode-archive-design/
  .github/workflows/autocode-archive-design.yml
  .github/actions/design-archive/action.yml
  .github/actions/design-archive/archive-design.sh
```

A small verify/render helper `.sh` MAY be split out (e.g. `verify-epic-complete.sh`) if it keeps `archive-design.sh` readable; the implementer decides. All `.sh` files executable (`chmod +x`), each headed with `#!/usr/bin/env bash` then `set -euo pipefail` per `.claude/rules/shell-scripts-conventions.md`. Required inputs guarded with `:?`; quote all expansions; pass `shellcheck` (CI installs shellcheck and the `**/*.sh` rule covers the new scripts).

### Workflow: `autocode-archive-design.yml`

- A header comment block matching the fan-out workflow's style: what it does, install note (copy into `<repo>/.github/`), the marker discovery contract ("do not rename"), requires default `GITHUB_TOKEN`.
- Trigger: `workflow_dispatch` with a single required input `design_id` (string). No `pull_request` / auto-sweep trigger.
- `permissions:` block: `contents: write`, `pull-requests: write`, `issues: read`.
- One job: checkout the default branch with `fetch-depth: 0` (full history; the script branches, commits, pushes, opens a PR), then call the composite action `./.github/actions/design-archive`, passing `design-id`, `repo` (`github.repository`), and `github-token` (`secrets.GITHUB_TOKEN`).

### Composite action: `design-archive/action.yml`

- `using: 'composite'`, `name` + `description` like the fan-out action.
- Inputs: `design-id` (required), `repo` (required), `github-token` (required).
- Steps run `archive-design.sh` via `${{ github.action_path }}/archive-design.sh`, with `GH_TOKEN: ${{ inputs.github-token }}`, `REPO: ${{ inputs.repo }}`, `DESIGN_ID: ${{ inputs.design-id }}` in `env`. Side-effect script; human-readable progress to stderr/stdout; no `$GITHUB_OUTPUT` contract required.

### Script: `archive-design.sh`

Inputs via env: `GH_TOKEN`, `REPO`, `DESIGN_ID` (all `:?`-guarded). Behavior, in order:

1. Resolve folder: glob `.autocode/design/${DESIGN_ID}-*` -> exactly one folder. Derive `id`/`short` with the render-design-issues.sh idiom (`base=$(basename dir); id="${base%%-*}"; short="${base#*-}"`).
2. Idempotent skip (report + exit 0) if ANY of: the `.autocode/design/INDEX.md` `<id>` row's status column is already `archived` (it is a Markdown table column `| id | shortname | created | status |`, not a `status:` frontmatter field); the source folder is missing (already moved); `.autocode/archive/<id>-<short>` already exists.
3. Flat vs multi: `units/` dir present -> multi; absent -> flat (`[[ -d "${dir}/units" ]]`).
4. Completeness via the SAME marker-matched `gh` queries the fan-out action uses:
   - Find the epic by `<!-- autocode:epic=<id> -->` body marker via `gh api --paginate /repos/$REPO/issues?state=all` (filter out PRs, `select(.pull_request | not)`).
   - If no epic-marked issue exists (not fanned out): report and exit (non-fatal).
   - Multi: list units via the GraphQL `sub_issues` feature header on the epic, match each by `<!-- autocode:unit=<id>/<slug> -->`; every unit sub-issue must be CLOSED.
   - Flat: the single epic-marked issue must be CLOSED.
   - If not all closed: print outstanding units (`slug` + `state`) and exit non-zero / non-fatal report; do NOT archive.
5. Archive (only when complete): configure git identity (github-actions bot); create branch `chore/archive-<id>-<short>`; if that branch or its PR already exists, report and exit without duplicating (PR idempotency); `mkdir -p .autocode/archive`; `git mv .autocode/design/<id>-<short> .autocode/archive/<id>-<short>`; flip the INDEX row (Markdown table column, not frontmatter): match the row by the `<id>` value in the first column and replace only that row's status cell `active` -> `archived`, never a global substitution (other rows may also be `active`); the row and id stay, never removed; commit with a `chore:` message noting the epic is complete; push the branch.
6. Open the PR with `gh pr create`. Multi-unit: PR body MUST contain `Closes #<epic-number>` so merging closes the epic; body notes it is a folder move. Flat: no `Closes` line; body notes the folder move only.

Constraints: markers `<!-- autocode:epic=<id> -->` / `<!-- autocode:unit=<id>/<slug> -->` are the discovery contract, do NOT rename. The Action uses `gh` directly (GitHub-specific, like the fan-out action); it does NOT go through `provider/run.sh` (that is for skills).

### Public interfaces (contract surface)

- Workflow input: `design_id` (string, required).
- Composite action inputs: `design-id`, `repo`, `github-token`.
- Script env contract: `GH_TOKEN`, `REPO`, `DESIGN_ID`.
- Branch name: `chore/archive-<id>-<short>`. Archive path: `.autocode/archive/<id>-<short>`.
- PR body marker line (multi only): `Closes #<epic-number>`.

### Tests that prove it

No bats or shared test harness exists in the repo (`find` for `*.bats` and `test*` dirs returns nothing; CI runs only `scripts/check-plugin-shape.sh` + shellcheck per `.github/workflows/ci.yml`). The fan-out template ships no tests to mirror, so add standalone bash test scripts (executable, `set -euo pipefail`, shellcheck-clean) that drive `archive-design.sh` against fixtures with a stubbed `gh`.

Stub `gh` (a shell function or a `PATH`-shimmed script) returns canned `issues?state=all` JSON and canned `sub_issues` GraphQL JSON per scenario; stub `git push`/`gh pr create` to capture (not perform) their args so the PR body is assertable. Build fixture design folders under a temp dir: a flat folder (`DESIGN.md`, no `units/`) and a multi folder (`DESIGN.md` + `units/<slug>.md`), each with a seeded `.autocode/design/INDEX.md` row.

Assert:

- Multi, all units closed -> `git mv` to `.autocode/archive/<id>-<short>` happened, `INDEX.md` row flipped `active` -> `archived`, PR body contains `Closes #<epic>`.
- Flat, epic issue closed -> `git mv` + INDEX flip happened, PR body contains NO `Closes` line.
- Multi, one unit open -> abort: prints the outstanding unit (`slug` + `state`), no `git mv`, INDEX unchanged.
- Idempotent: INDEX row already `archived`, OR `.autocode/archive/<id>-<short>` already exists -> skip with exit 0, no duplicate move/PR.
- Not fanned out: epic marker absent from `issues?state=all` -> report + exit, no move.

Place the test script(s) inside the template directory (e.g. `plugins/autocode/templates/autocode-archive-design/.github/actions/design-archive/archive-design.test.sh`) so they ship and shellcheck with the script they exercise.
