---
depends-on: []
type: task
---

# Archive PR closes the epic on merge

## Summary

`/impl-archive` closes a completed epic's issue eagerly via a direct `issue-transition <epic> done` (step 4) before its folder-move PR merges, so an abandoned archive PR leaves a closed epic with an un-archived folder. This unit drops that direct transition and instead has the archive PR carry `Closes #<epic>` (multi-unit only), tying the epic close to the PR merge. Flat designs have no separate epic issue, so they get no `Closes` line; their single issue was already closed by its own unit PR. The result unifies the manual skill with the new `autocode-archive-design` Action: both just open a PR that closes the epic on merge.

## Implementation

Deliverable: edit the canonical body-only skill source `autocode/impl/skills/impl-archive/SKILL.md` (in the worktree; do not touch the plugin shim). Read it first, plus `autocode/design/design-folder.md` (lifecycle + markers) and `autocode/pr/skills/pr-create/SKILL.md` (issue-link interface) before editing.

Changes:

- Remove step 4 entirely. Do not call `provider/run.sh issue-tracker issue-transition <epic-key> done`. The epic is no longer closed eagerly.

- Capture the epic issue key/number during discovery (step 2). The discovery call `provider/run.sh issue-tracker issue-epic-list --epic <id>` already returns the epic row, matched by the `<!-- autocode:epic=<id> -->` body marker. Step 2 already maps markers to `{slug, key, status}` and the epic issue; make it explicit that the epic row's key is retained for the `Closes` linkage. Flat designs return a single row that is both epic and unit, with no separate epic issue, so there is no epic key to carry.

- Wire the `Closes #<epic>` into the delegated PR creation (current step 7, `pr-create --lightweight`). Verified pr-create interface: pr-create never accepts a hand-written `Closes` in the body. It links the issue in its step 6 by resolving `provider/run.sh git-remote issue-ref <issue-id>` and appending a canonical `Closes #<ref>`, where `<issue-id>` comes from `--issue <tracker-key>`. But pr-create step 6 (link the issue) is skipped under `--lightweight`. So passing `--issue` alone with `--lightweight` will not link. The implementer must reconcile this so the multi-unit archive PR actually carries `Closes #<epic>`. Pick the mechanism that fits pr-create's contract as read, not a guess:
  - Multi-unit: delegate to `pr-create --issue <epic-key>` WITHOUT `--lightweight` for the linking step to run, OR keep `--lightweight` and supply the close line via the body file pr-create accepts (verify against pr-create's `--body-file` / `--lightweight` rules: `--lightweight` skips link/reviewers/hygiene, and the PR body rule states the body never carries a hand-written close line, so prefer the `--issue` linking path over a hand-written `Closes`). State the chosen flag combination explicitly in the skill step.
  - Flat: no epic key -> delegate with no issue linkage (current lightweight behavior unchanged), no `Closes` line.

- Update surrounding prose:
  - Step 8 report: for multi-unit, say "merging the PR closes the epic" (the epic is still open until merge). Drop the current "the epic issue is closed" wording, which implied it was already closed. Flat: report only that merging archives the folder.
  - Step 6 git-commit delegation and the worktree / `git mv` / INDEX flip to `archived` / `pr-create` delegation: keep unchanged.

- Update the Rules bullet that reads "`issue-transition` tolerates an already-closed epic." There is no direct transition anymore. Restate idempotency to cover both post-merge and in-flight state, mirroring the Action's idempotency exactly (single source of truth):
  - Post-merge: the source folder is missing (already moved) OR the `<id>` row in `.autocode/design/INDEX.md` is already `archived` -> report and stop cleanly.
  - In-flight: the archive branch `chore/archive-<id>-<short>` or its PR already exists (e.g. the Action or a prior skill run opened one that has not merged) -> report and stop without recreating the branch or opening a duplicate PR. Without this, a concurrent Action dispatch plus `/impl` hand-off would race: the skill would see the folder still present and INDEX still `active`, then collide on the existing branch.
  - Keep the other Rules bullets (never archive an epic with outstanding units; completion read from the discovery call; tracker writes via `provider/run.sh issue-tracker`; delegate commit and PR creation).

- INDEX flip precision (where the skill flips the row before the `pr-create` delegation): `.autocode/design/INDEX.md` is a Markdown table (`| id | shortname | created | status |`), not frontmatter. Match the row by the `<id>` value in the first column and replace only that row's status cell `active` -> `archived`. Never a global substitution: other rows may also be `active`, and the per-epic invariant is row-scoped.

Single source of truth: this skill must stay the manual/AI counterpart of the new `autocode-archive-design` Action (separate unit); both open a PR that closes the epic on merge. Keep their behavior identical.

Out of scope (separate units): the GH Action template, the `impl`/`impl-start` completion hand-off, and the `design-folder.md` lifecycle + `autocode-setup` wiring.

Files to read: `autocode/impl/skills/impl-archive/SKILL.md` (modify), `autocode/design/design-folder.md`, `autocode/pr/skills/pr-create/SKILL.md`.

Verification: no automated harness for skill bodies. Dry-run `/impl-archive <id>` on a multi-unit epic (whose units are all closed): the archive PR body contains `Closes #<epic>` and the epic issue is NOT closed until the PR merges. Dry-run on a flat epic: the archive PR has no `Closes` line.
