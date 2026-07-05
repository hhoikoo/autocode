---
depends-on: []
type: task
---

# Channel core: feature-set, shared CLI lib, file format, and gitignore wiring

## Summary

Stand up the `autocode/comms/` feature-set and its shared bash file `channel.sh`, the on-disk foundation every other unit builds on. Executed, it dispatches subcommands for skills (each skill step is an independent Bash call, so state cannot be sourced across steps; `git-commit`'s `commit.sh <subcommand>` is the precedent); sourced, it exposes the same functions to the plugin hook scripts (single processes, safe to source). It resolves the main-worktree `.autocode/messages/` dir from any linked worktree, resolves self-identity by matching `$TMUX_PANE` plus the tmux server pid against card frontmatter, registers/refreshes an agent card (tmp+mv), writes one message file per send into the recipient's `new/` (tmp+mv, atomic, lock-free), delivers by claiming `new/` files via rename into `cur/`, and lazily reaps dead agents. The feature-set `CLAUDE.md` is the single source of truth for the file format (agent dir layout, card fields, `<!-- a2a-msg ... -->` header, delivery-by-rename semantics, default name scheme) that the presence, messaging, delivery-hook, and spawn units reference. Setup and update gitignore reconciliation gains a `messages/` rule, the CI shellcheck glob gains the `autocode/` tree, and a runnable assert-based self-test proves send, deliver-once, concurrent-send, and concurrent-deliver integrity.

## Implementation

Deliverable: the `autocode/comms/` feature-set scaffold, the shared CLI lib, the format spec, the gitignore and CI wiring, and one runnable check. No skills, no hooks, no shims in this unit (those are the dependent units); only the lib they all use plus its documentation.

### Files to create

```
autocode/comms/CLAUDE.md            feature-set scope doc + canonical file-format spec (body-only)
autocode/comms/lib/channel.sh       subcommand CLI when executed; sourceable functions for hooks
autocode/comms/lib/test-channel.sh  assert-based self-test (the one runnable check)
```

A single `channel.sh` is the right split: resolve, register, send, deliver, and reap all operate on one messages dir and share helpers; a second file would only add a source line. The shape check requires every `autocode/<feature-set>/` to carry a `CLAUDE.md` (`scripts/check-plugin-shape.sh:103-109`), so `autocode/comms/CLAUDE.md` is mandatory regardless.

#### `autocode/comms/CLAUDE.md`

Body-only (no frontmatter; the shape check rejects a leading `---`, `scripts/check-plugin-shape.sh:24-29,58-61`). One paragraph of feature-set scope (the file-based agent channel, skill wrappers over a shared CLI lib, hook delivery, no provider) followed by the canonical file-format spec transcribed from `DESIGN.md` "File format". It documents, as the single source other units cite:

- Agent dir `<agent>/`: `card.md`, `new/`, `cur/`, `rewake.pid`. The directory name is the agent name.
- Card `card.md`: YAML frontmatter only. `name` (unique key, equals directory name), `description`, `pane` (`$TMUX_PANE`, identity handle and send-keys target), `server` (tmux server pid; guards pane-id reuse across server restarts), `task`. Display coordinates are derived at read time via `tmux display-message -p -t "$pane"`, never stored. A2A's `skills` array and `state` field are deliberately absent (no consumer; DESIGN.md decision 6).
- Message file `new/<ts>-<uuid>.md`: one message per file, filename orders delivery. A single HTML-comment header `<!-- a2a-msg id=... from=... to=... type=... context=... task=... ts=... -->` (`to` omitted for broadcast, `context`/`task` optional), then the body text.
- Delivery semantics: files in `new/` are unread; deliver claims a file by renaming it into `cur/` (atomic; exactly one concurrent claimer wins), then emits its content. Crash between claim and emit loses that message (DESIGN.md decision 4).
- Default agent name scheme: `<session_name>-<window_index>`, used by register, by auto-registration in the outbound skills, and by spawn.

#### `autocode/comms/lib/channel.sh`

Dual-mode: when executed, a case dispatcher maps `$1` to a function; when sourced, defines functions with no top-level side effects. Subcommands, each also callable as a function by hook scripts:

| Subcommand | Behavior | Source |
|---|---|---|
| `resolve-dir` | `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"` then `/.autocode/messages`; `mkdir -p`; resolves to the MAIN worktree from any linked worktree; fails with a clear message outside a git repo or when `<main-worktree>/.autocode/` is absent (v1 supports the default config-dir location only). `--path-format=absolute` needs git >=2.31; fall back to `realpath "$(git rev-parse --git-common-dir)"` | `DESIGN.md` decision 1 |
| `self` | match `$TMUX_PANE` against each card's `pane:` where `server:` equals the running tmux server pid (`tmux display-message -p '#{pid}'`); print the agent name; no-op clean (empty, success) when `$TMUX_PANE` is unset | `DESIGN.md` decision 2 |
| `register [name] [task]` | write/refresh `<name>/card.md` via write-temp-then-rename; create `new/` and `cur/`; default the name to `<session_name>-<window_index>`; re-registering the same pane (match `pane:` == `$TMUX_PANE`, same server) updates the existing card in place. Owns the card schema and the default-name scheme; presence and spawn call this, never reimplement it | `DESIGN.md` decisions 2, 9 |
| `send <agent> <text>` (and the broadcast fan-out) | compose the header (`id` from `uuidgen`, `from` self, `ts` ISO8601, `type`, optional `context`/`task`), write to a temp file in the messages dir (same filesystem so `mv` is an atomic rename), `mv` into `<agent>/new/<ts>-<uuid>.md`. No locks: concurrent senders write distinct files | `DESIGN.md` decisions 3-4 |
| `deliver [max-bytes]` | list own `new/` sorted by filename (oldest first); for each file, rename it into `cur/` (the atomic claim; a failed rename means another deliverer won, skip it), then append its content to the output, stopping before a whole file would exceed the caller's max-bytes (the inject hook passes the `additionalContext` 10000-char limit; a single over-cap file is delivered alone). Shared by inject and rewake; crash between claim and emit loses that message per the stated contract | `DESIGN.md` decision 4, Edge cases |
| `agents` | enumerate agent dirs; liveness = card `pane:` in `tmux list-panes -a -F '#{pane_id}'` AND card `server:` == running server pid; prune dead agent dirs (kill a recorded `rewake.pid` poller first); print the live set | `DESIGN.md` decision 7, Edge cases |
| `deregister` | kill the recorded poller, remove this pane's agent dir; best-effort, missing pieces are not errors | `DESIGN.md` decision 7 |

Plus an internal parse-frontmatter helper for card fields. All replaces (card, message files) are write-temp-then-rename in the messages dir so `mv` is a rename, not a copy. No lockdir, no cursor, no stale-PID reclaim: rename is the only synchronization primitive.

#### `autocode/comms/lib/test-channel.sh`

The one runnable check (repo "one check" rule). Assert-based, no framework, on a temp messages dir with `$TMUX_PANE` and the tmux liveness lookups stubbed. It:

1. Sends two messages to an agent; delivers and asserts both are returned in filename order and both files moved to `cur/`.
2. Delivers again and asserts nothing is returned (`new/` empty).
3. Runs two concurrent senders to one agent; asserts two intact, well-formed message files landed (distinct names, no interleaving possible).
4. Seeds `new/` with several messages and runs two concurrent deliverers; asserts every message was claimed exactly once across the two (union complete, intersection empty).

Matches the channel-core testing line in `DESIGN.md` Testing strategy.

### Files to modify

Gitignore wiring. A target repo must gitignore `.autocode/messages/`. The reconciliation is prose-driven in two skills (no script change); add a rule alongside the existing transient-impl-state rule, idempotent (append only when absent), targeting `<repo-root>/.autocode/.gitignore`:

- `plugins/autocode/skills/autocode-setup/SKILL.md`: Step 3 reconciliation list (`SKILL.md:71-75`, the `<repo-root>/.autocode/.gitignore` bullet at `:74`). Add `messages/` to that file under the same default-vs-relocated guard the impl-state rule already uses.
- `plugins/autocode/skills/autocode-update/SKILL.md`: the matching reconciliation bullet at `SKILL.md:54-55`. Add the same `messages/` entry.

These are plugin-native bootstrap skills (no shim/real split; `scripts/check-plugin-shape.sh:13-21`), so the edit lands directly in the plugin `SKILL.md` bodies.

CI shellcheck coverage. The shape check's shellcheck pass runs `find provider plugins/autocode .githooks scripts -type f -name '*.sh'` (`scripts/check-plugin-shape.sh:138`), which misses the `autocode/` tree entirely, so the load-bearing `channel.sh` would ship unlinted. Add `autocode` to the find roots; if the wider glob surfaces existing offenders under `autocode/*/skills/*/scripts/`, fix them, or scope the addition to `autocode/*/lib` as the fallback.

### Boundary

```
  any worktree                          MAIN worktree
  ┌───────────────────┐                 .autocode/messages/<agent>/
  │ skill: bash        │  run/source     ├── card.md        (tmp+mv)
  │  channel.sh <cmd>  │────────────────►├── new/<msg>.md   (tmp+mv in)
  │ hook: source lib   │  resolve dir    ├── cur/<msg>.md   (claim = rename)
  └───────────────────┘                  └── rewake.pid
        git rev-parse --git-common-dir -> dirname -> /.autocode/messages
```

### Tests that prove it

`autocode/comms/lib/test-channel.sh` is self-contained and exits non-zero on any failed assertion. It covers the send/deliver-once contract and the concurrency invariants (distinct files per sender, exactly-one-claimer per message), which are the load-bearing guarantees the dependent units rely on.

### Not in scope

No provider script (no per-repo vendor; `DESIGN.md` decision 8). No skills, hooks, or shims (dependent units). No lockdir or cursor machinery (rejected; `DESIGN.md` decision 3).
