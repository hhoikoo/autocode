---
depends-on: []
type: task
---

# Channel core: feature-set, shared lib, file format, and gitignore wiring

## Summary

Stand up the `autocode/comms/` feature-set and its shared bash library, the on-disk foundation every other unit builds on. The library exposes sourceable functions (no provider dispatch, no per-repo vendor) callable by both skills and plugin hooks: resolve the main-worktree `.autocode/messages/` dir from any linked worktree, resolve self-identity by matching `$TMUX_PANE` against inbox `pane:` frontmatter, append a message block to an inbox under a `mkdir` lockdir (mandatory because APFS does not honor `O_APPEND` atomicity), read unread bytes past a `.cursor` offset and advance it atomically, parse inbox frontmatter, and lazily reap dead-pane inboxes against `tmux list-panes`. The feature-set `CLAUDE.md` is the single source of truth for the file format (inbox agent-card frontmatter, `<!-- a2a-msg ... -->` block header, `---` separator, `.<agent>.cursor` sidecar, `.<agent>.lock/` lockdir) that the presence, messaging, delivery-hook, and spawn units reference. Setup and update gitignore reconciliation gains a rule scaffolding `messages/` into `<repo-root>/.autocode/.gitignore`, and a runnable assert-based self-test proves append, read-once, and concurrent-append-under-lock integrity.

## Implementation

Deliverable: the `autocode/comms/` feature-set scaffold, the shared lib, the format spec, the gitignore wiring, and one runnable check. No skills, no hooks, no shims in this unit (those are the dependent units); only the lib they all source plus its documentation.

### Files to create

```
autocode/comms/CLAUDE.md            feature-set scope doc + canonical file-format spec (body-only)
autocode/comms/lib/channel.sh       sourceable bash functions (shared by skills and hooks)
autocode/comms/lib/test-channel.sh  assert-based self-test (the one runnable check)
```

A single `channel.sh` of sourceable functions is the right split: resolve, lock/append, cursor, frontmatter, and reap all operate on one messages dir and share helpers; a second file would only add a source line. The shape check requires every `autocode/<feature-set>/` to carry a `CLAUDE.md` (`scripts/check-plugin-shape.sh:108-114`), so `autocode/comms/CLAUDE.md` is mandatory regardless.

#### `autocode/comms/CLAUDE.md`

Body-only (no frontmatter; the shape check rejects a leading `---`, `scripts/check-plugin-shape.sh:25-30,56-60`). One paragraph of feature-set scope (the file-based A2A channel, skill wrappers over a shared lib, hook delivery, no provider) followed by the canonical file-format spec transcribed from `DESIGN.md` "File format" (`DESIGN.md:47-73`). It documents, as the single source other units cite:

- Inbox `<agent>.md`: YAML agent-card frontmatter fields and meaning. `name` (unique key, equals filename stem), `description`, `tmux` (`session:window.pane` for `send-keys`), `pane` (`$TMUX_PANE`, the stable identity handle), `repo`, `task`. The A2A `skills` array and `state`/`TaskState` field are deliberately omitted in v1 (no consumer routes by skills, nothing transitions state); document them as the upgrade path, not as live fields.
- Message block: a single HTML-comment header `<!-- a2a-msg id=... from=... to=... type=... context=... task=... ts=... -->`, the fields and which are optional (`to` omitted for broadcast, `task` optional), then the body text (A2A TextPart) below it.
- Separator: blocks are delimited by a `---` line.
- `.<agent>.cursor`: byte length consumed; append-only inbox makes the offset monotonic, so unread is `tail -c +<offset+1>`.
- `.<agent>.lock/`: per-inbox `mkdir` lockdir guarding appends; atomic create, stale-PID reclaim.

#### `autocode/comms/lib/channel.sh`

Sourceable; defines functions and exits cleanly when sourced (no top-level side effects). Functions, each callable by skills and hook scripts:

| Function | Behavior | Source |
|---|---|---|
| resolve messages dir | `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"` then `/.autocode/messages`; `mkdir -p`; resolves to the MAIN worktree from any linked worktree; fails with a clear message outside a git repo. `--path-format=absolute` needs git >=2.31; fall back to `realpath "$(git rev-parse --git-common-dir)"` when the flag is unsupported | `DESIGN.md` Design decision 1 |
| resolve self | match `$TMUX_PANE` against each inbox's `pane:` frontmatter; print the agent name; no-op clean (empty, success) when `$TMUX_PANE` is unset | `DESIGN.md` Design decision 2 |
| append block | take the `.<agent>.lock/` lockdir via `mkdir` (atomic); reclaim a stale lock whose holder PID is gone (`kill -0`) with a bounded randomized-backoff retry so only one reclaimer wins; write the block; release. Never bare `>>` (APFS `O_APPEND` is not atomic) | `DESIGN.md` Design decision 3 |
| deliver (read unread + advance cursor) | one atomic op, the single delivery path for both hooks: read bytes after the stored `.<agent>.cursor` offset (`tail -c +N`) capped at the caller's max-bytes (the inject hook passes the `additionalContext` 10000-char limit), oldest-first; advance the cursor only past the bytes actually returned by writing the new offset to `.cursor.tmp.$$` in the same dir then `mv` (atomic replace), so an over-cap backlog drains across turns with no loss; if the stored offset exceeds file size (manual edit), reset to 0 and re-deliver | `DESIGN.md` Design decision 4, Edge cases |
| parse frontmatter | extract named fields from an inbox's YAML frontmatter block | `DESIGN.md:49-61` |
| list live agents | enumerate `*.md` inboxes; check each `pane:` against `tmux list-panes -a -F '#{pane_id}'`; prune dead inboxes plus their `.cursor`/`.lock`/`.rewake.pid` sidecars; return the live set. Lazy reaper, no daemon | `DESIGN.md` Design decision 7, Edge cases |

The lock holder records its PID in the lockdir so a stale lock (holder gone) is reclaimable; a `leanness:` comment names the bounded-spin ceiling. The cursor temp file lives in the messages dir (same filesystem) so `mv` is a rename, not a copy.

#### `autocode/comms/lib/test-channel.sh`

The one runnable check (repo "one check" rule). Assert-based, no framework, on a temp messages dir with `$TMUX_PANE` stubbed and no real tmux. It:

1. Appends two blocks to an inbox; reads unread and asserts both are returned.
2. Reads again and asserts none returned (cursor advanced once).
3. Runs two concurrent appenders under the lock; asserts no interleaving and the correct final block count.

Matches the channel-core testing line in `DESIGN.md:130`.

### Files to modify (gitignore wiring)

A target repo must gitignore `.autocode/messages/`. The reconciliation is prose-driven in two skills (no script change); add a rule alongside the existing transient-impl-state rule, idempotent (append only when absent), targeting `<repo-root>/.autocode/.gitignore`:

- `plugins/autocode/skills/autocode-setup/SKILL.md`: Step 3 reconciliation list (`SKILL.md:71-75`, the `<repo-root>/.autocode/.gitignore` bullet at `:74`). Add `messages/` to that file under the same default-vs-relocated guard the impl-state rule already uses (relocated config dir: reconcile only if `<repo-root>/.autocode/` exists; otherwise leave to a backstop).
- `plugins/autocode/skills/autocode-update/SKILL.md`: the matching reconciliation bullet at `SKILL.md:54-55` (the `<repo-root>/.autocode/.gitignore` rule at `:55`). Add the same `messages/` entry.

These are plugin-native bootstrap skills (no shim/real split; `scripts/check-plugin-shape.sh:13-21`), so the edit lands directly in the plugin `SKILL.md` bodies.

### Boundary

```
  any worktree                          MAIN worktree
  ┌───────────────────┐                 .autocode/messages/
  │ skill / hook       │  source         ├── <agent>.md      (frontmatter + blocks)
  │  sources channel.sh│────────────────►├── .<agent>.cursor (tmp+mv)
  └───────────────────┘  resolve dir     └── .<agent>.lock/  (mkdir, PID-stamped)
        git rev-parse --git-common-dir -> dirname -> /.autocode/messages
```

### Tests that prove it

`autocode/comms/lib/test-channel.sh` is self-contained and exits non-zero on any failed assertion. It covers the append/read-once contract and the concurrency invariant (lock serializes appends, no corruption, exact block count), which are the load-bearing guarantees the dependent units rely on.

### Not in scope

No provider script (no per-repo vendor; `DESIGN.md:91`). No skills, hooks, or shims (dependent units). No CI shellcheck wiring change is required: CI runs only the shape check today (`.github/workflows/ci.yml:16-25`), which already mandates the feature-set `CLAUDE.md`.
