---
depends-on: [archive-action-template]
type: task
---

# Lifecycle doc and setup wiring for the archive Action

## Summary

`design-folder.md` promises "`impl-archive` (manual) or the GH Action moves it," but no archive GH Action existed, so the doc named vapor. This unit lands the doc to match the now-shipped `autocode-archive-design` Action and the `/impl` hand-off, and makes `/autocode-setup` install the new template. The lifecycle section's Done-semantics bullets name the `autocode-archive-design` Action (triggered by `workflow_dispatch` with a `design_id` input) and the impl-driven hand-off (`/impl` detects a fully-merged epic on its next `--from-design <id>` run, outcome `epic_complete`, and hands off to `/impl-archive`). The epic transition table's `in-progress -> done` row reflects that the epic now closes via the archive PR's `Closes #<epic>` on merge, not a direct transition. `autocode-setup` Step 6 extends its optional-Action install to also offer and copy the `autocode-archive-design` template (workflow + `design-archive` composite action) into the repo `.github/`, same AskUserQuestion gate (default no). Canonical Action behavior stays in the template and the `/impl-archive` skill; the doc carries only the trigger and one or two sentences.

## Implementation

Depends on `archive-action-template`: the setup step installs the template that unit creates, and the doc references the Action it defines. Read these first: `~/.autocode/autocode/design/design-folder.md`, `~/.autocode/plugins/autocode/skills/autocode-setup/SKILL.md`, and the existing fan-out template under `~/.autocode/plugins/autocode/templates/autocreate-design-doc-issue/` (install-shape reference). The archive template's file paths come from the `archive-action-template` unit; reference them as `plugins/autocode/templates/autocode-archive-design/.github/{workflows/autocode-archive-design.yml, actions/design-archive/...}`.

Files to modify:

- `~/.autocode/autocode/design/design-folder.md` (worktree: `autocode/design/design-folder.md`)
- `~/.autocode/plugins/autocode/skills/autocode-setup/SKILL.md` (worktree: `plugins/autocode/skills/autocode-setup/SKILL.md`). Bootstrap-exception plugin-native skill, not a shim. Edit it directly.

### design-folder.md (`## Lifecycle`)

Done semantics, the Epic-done bullet. Current text:

> Epic done: the whole folder is moved to `.autocode/archive/<id>-<shortname>/`. Location is the epic-level source of truth. `impl-archive` (manual) or the GH Action moves it once every unit is done and closes the epic.

Update so "the GH Action" names the shipped `autocode-archive-design` Action (triggered by `workflow_dispatch` with a `design_id` input). Also document the impl-driven hand-off: `/impl` detects a fully-merged epic on its next `--from-design <id>` run (`impl-start` outcome `epic_complete`) and hands off to `/impl-archive`. One or two sentences plus the trigger; do not restate the Action's internals (canonical behavior lives in the template and the `/impl-archive` skill).

Epic transition table, the `in-progress -> done` row. Current trigger: "every unit is `done`; `impl-archive` (or the GH Action) closes the epic." Clarify the epic now closes via the archive PR's `Closes #<epic>` on merge, not a direct transition. Keep wording tight; do not duplicate DESIGN.md.

### autocode-setup SKILL.md (Step 6)

Step 6 currently offers only the fan-out template and copies `plugins/autocode/templates/autocreate-design-doc-issue/` into the repo `.github/`. Extend it to also offer and install the archive template. The implementer decides whether one prompt covers both Actions or a paired second AskUserQuestion option; keep the same gate (default no).

Copy from `~/.autocode/plugins/autocode/templates/autocode-archive-design/`, preserving relative paths (`mkdir -p` each destination; keep `.sh` files executable):

- workflow `.github/workflows/autocode-archive-design.yml` -> `<repo-root>/.github/workflows/`
- composite action dir `.github/actions/design-archive/` -> `<repo-root>/.github/actions/design-archive/`

Frame the archive Action: "On `workflow_dispatch` with a design id, archive a completed epic (move its folder to `.autocode/archive/`, flip INDEX, and for multi-unit close the epic via the PR). Without it, run `/impl-archive <id>` manually (or it runs automatically next time you `/impl` a fully-merged epic)."

Preserve existing behavior: if a destination file exists, show a diff and ask before overwriting.

### autocode-update reconciliation (flag, not a hard deliverable)

Finding: `autocode-update` has no template-copy logic. It pulls `~/.autocode`. A repo set up before this template existed will not auto-receive it (same gap as the fan-out template today). Recommend either a one-line note in `autocode-update` pointing users to re-run `/autocode-setup` for new templates, or leaving it to a setup re-run. Keep out of the hard deliverable unless trivial.

### Verification

No automated harness for skill or doc bodies. Manual: re-run `/autocode-setup` in a test repo, confirm both templates are offered and installed under `.github/` (workflow + composite action dir, `.sh` executable); read the updated `design-folder.md` lifecycle section for correctness. Out of scope: Action internals (`archive-action-template` unit) and the `/impl`, `impl-start`, `/impl-archive` skill changes (separate units).
