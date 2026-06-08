---
depends-on: []
type: task
---

# Scaffold a union merge driver for PROGRESS.md

## Summary

During a parallel epic every dependent unit's rebase touches the shared, append-only `PROGRESS.md`, so the append conflict is the one high-frequency structural collision of the whole run. Git's built-in `union` low-level merge driver resolves append conflicts by keeping both sides with no markers, so a `.gitattributes` rule binding `PROGRESS.md` to `merge=union` makes that conflict auto-resolve at the git layer and a rebase never stops on it. One caveat makes this correct only with a seed: `union` is line-based, so it resolves cleanly only when `PROGRESS.md` already exists at the merge-base. Today the file is first created by the first unit's `impl-push` (`impl-push/SKILL.md`), so if two first-wave units each create it from scratch, `union` concatenates two `# Progress: <short>` headers into a duplicate with no conflict and no stop (the skill backstop never fires because `union` suppresses the conflict). This unit therefore does two things: (1) seed the `PROGRESS.md` header at design-folder creation so it is a common ancestor before any unit branches, and (2) scaffold the `.gitattributes` `merge=union` rule into the `/autocode-setup` and `/autocode-update` flows, modeled on the existing `<repo-root>/.autocode/.gitignore` reconciliation: create-if-missing, append-the-line-if-absent, idempotent. It is the git-layer half of decision 8; the `pr-rebase-auto` unit adds the complementary skill-level backstop for repos whose setup predates the rule, and the two touch disjoint files.

## Implementation

Deliverable: a `.gitattributes` `merge=union` rule for `PROGRESS.md` scaffolded idempotently by both bootstrap-inline skills, plus a seeded `PROGRESS.md` header at design-folder creation, so any repo gets append conflicts auto-resolved at the git layer with a common-ancestor file that keeps `union` clean.

### Seed the PROGRESS.md header at design-folder creation

For `union` to resolve cleanly, `PROGRESS.md` must exist at the epic's merge-base before any unit branches. Seed it where the design folder is authored, so it rides the design PR to `main`:

- `autocode/design/skills/design-plan/` (folder authoring): when creating `.autocode/design/<id>-<short>/`, also write `.autocode/design/<id>-<short>/PROGRESS.md` containing exactly the `# Progress: <short>` header (the canonical format, `design-folder.md:125`) and nothing else. It merges to `main` with the design PR, becoming the common ancestor for every unit.
- `autocode/design/skills/design-fanout/` (backfill): when fanning out a multi-unit epic, create the same header-only `PROGRESS.md` if absent (idempotent), covering epics whose folder predates this change. Flat single-unit designs need no seed (one unit, no concurrent append), so the seed is a no-op there.
- `impl-push` is unchanged: it already creates `PROGRESS.md` if missing then appends; with the seed present it only ever appends, so its create branch becomes the backstop for repos on an older design layer.

Confirm at implementation time whether `design-fanout` commits to the base or only creates issues; if it cannot commit to `main`, the `design-plan` seed (riding the design PR) is sufficient and the fanout backfill applies only to in-worktree authoring. State the single canonical header string once and reference it from both call sites so they cannot drift.

### The rule and its location

Land one line at `<repo-root>/.gitattributes`:

```
.autocode/design/**/PROGRESS.md merge=union
```

- Repo-root `.gitattributes` is where git looks for path-attribute rules that apply across the worktree; it is the simplest correct location and matches git's own lookup. The `.autocode/design/**/PROGRESS.md` glob is anchored to the repo root (not `AUTOCODE_CONFIG_DIR`), matching the design-folder spec: `PROGRESS.md` lives at `.autocode/design/<id>-<shortname>/PROGRESS.md` (`design-folder.md:7-9,42`), always under repo-root `.autocode/`, independent of where `AUTOCODE_CONFIG_DIR` points (`design-folder.md:53`). Same anchoring rationale the existing gitignore step uses for the repo-root artifact dir.
- The repo currently has no `.gitattributes` (confirmed: no such file at the worktree root), so the rule is additive and never collides with an existing attribute line.
- `union` is a git built-in driver requiring no `[merge "..."]` config in `.git/config`; the `.gitattributes` line alone is sufficient. Nothing else (no driver registration) is scaffolded.

### Setup flow (`plugins/autocode/skills/autocode-setup/SKILL.md`)

Extend the gitignore reconciliation step (currently the block at `SKILL.md:70-73`, "After writing, reconcile two ignore rules"). The reconciliation is model-driven inline prose, not a helper script (the `scripts/` dir holds only `clone.sh`, `init-config-dir.sh`, `write-settings.sh`; none touch `.gitignore`), so the `.gitattributes` rule is scaffolded the same way: an additional inline, idempotent reconcile step.

- Add reconciliation of the `.autocode/design/**/PROGRESS.md merge=union` line in `<repo-root>/.gitattributes`: create the file with the line if missing; append the line only when absent; report unchanged otherwise. Same create-if-missing / append-if-absent shape as the existing `.gitignore` rules.
- This is always the repo-root `.gitattributes`, unconditional on `AUTOCODE_CONFIG_DIR`, because `PROGRESS.md` always lives under repo-root `.autocode/`. Unlike the relocated-config-dir caveat on the `<repo-root>/.autocode/.gitignore` rule, there is no "only if the dir exists" guard: the repo root always exists.

### Update flow (`plugins/autocode/skills/autocode-update/SKILL.md`)

Extend the Gitignore reconcile step (currently step 2 item 3, `SKILL.md:53-55`) with the same `.gitattributes` line check, idempotent (append the line if missing), reporting only when changed. This keeps already-set-up repos current when they run `/autocode-update` after this change ships.

### Single source for the rule text

Both skill bodies must spell the identical glob and attribute (`.autocode/design/**/PROGRESS.md merge=union`). State it once as the canonical line and have the update flow reference the same string the setup flow writes, so the two cannot drift. Cite the design-folder `PROGRESS.md` location as the justification for the glob in both places.

### Out of scope

- The `pr-rebase` skill-level `PROGRESS.md` union resolution: owned by the `pr-rebase-auto` unit (decision 8, second half). This unit only scaffolds `.gitattributes`.
- No change to `scripts/check-plugin-shape.sh`: its allowlist gates only skill/agent shim-vs-real shape and shellchecks `*.sh`; a `.gitattributes` data file is neither a skill, an agent, nor a shell script, so no allowlist entry is needed (`check-plugin-shape.sh:13-14,90-131`).
- No change to `.github/workflows/ci.yml`: it has no `paths:` globs (runs `shape-check` on every PR and push) and the shape check does not inspect `.gitattributes`, so the new file needs no CI wiring (`ci.yml:3-25`).

### Tests that prove it

Per the design testing strategy (`DESIGN.md:110`):

- Seeded common ancestor (the supported path): start from a base that already has the seeded header-only `PROGRESS.md` (the `design-plan`/`design-fanout` seed), construct two branches that each append a distinct timestamped block under `.autocode/design/<id>-<shortname>/PROGRESS.md`, with the `.gitattributes merge=union` rule present, rebase one onto the other, and assert both blocks survive with no `<<<<<<<` conflict markers, a single `# Progress: <shortname>` header, and the rebase does not stop. The header is unchanged common-ancestor context on both sides, so `union` keeps it once.
- No-seed regression (the failure the seed prevents): with no `PROGRESS.md` at the base, two branches each create it (header + block) and rebase under `union`; assert the header appears twice. This documents why the seed is required and guards against dropping it.
- Seed idempotency: running the `design-plan`/`design-fanout` seed twice writes the header exactly once and never clobbers an existing `PROGRESS.md` with appended blocks.

Follow the existing `provider/` shell-test conventions for the harness shape.
