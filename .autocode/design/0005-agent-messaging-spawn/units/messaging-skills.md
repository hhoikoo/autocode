---
depends-on: [channel-core]
type: task
---

# Messaging skills: a2a-send and a2a-broadcast

## Summary

Two user-facing skills that push A2A message blocks into other sessions' inboxes, both thin wrappers over the channel-core lib. `a2a-send <agent> <message>` appends a `type=directed` block to one recipient's inbox under its lock. `a2a-broadcast <message>` fans the same append out to every live agent on this repo except self, each as a `type=broadcast` block. A2A is strictly bilateral with no native broadcast, so broadcast is our local extension: a fan-out of directed appends, not a protocol feature. Neither skill owns the message-block format or the dir/lock/identity logic; they call the lib and reference `autocode/comms/CLAUDE.md` for the block format. Delivery is entirely the delivery-hooks unit's job (the recipient's hooks read each inbox); messaging does NO tmux `send-keys` poke, because tmux cannot reliably tell a busy TUI from an idle one and an injected `Enter` could auto-answer an open dialog in the recipient (DESIGN.md Design decision 4).

## Implementation

Both real files are body-only (no frontmatter); frontmatter lives only in the shim. Both source the channel-core lib and reference `autocode/comms/CLAUDE.md` for the exact message-block header and separator format rather than restating it. Skill names are globally unique across all feature-sets.

Files:

- `autocode/comms/skills/a2a-send/SKILL.md`: real skill body for `a2a-send <agent> <message>`.
- `plugins/autocode/skills/a2a-send/SKILL.md`: shim. Frontmatter (`name: a2a-send`, `description`) plus one body line reading `@~/.autocode/autocode/comms/skills/a2a-send/SKILL.md` and forwarding `$ARGUMENTS`.
- `autocode/comms/skills/a2a-broadcast/SKILL.md`: real skill body for `a2a-broadcast <message>`.
- `plugins/autocode/skills/a2a-broadcast/SKILL.md`: shim. Frontmatter (`name: a2a-broadcast`, `description`) plus one body line reading `@~/.autocode/autocode/comms/skills/a2a-broadcast/SKILL.md` and forwarding `$ARGUMENTS`.

### a2a-send

Args: `<agent>` (recipient name, inbox stem) and `<message>` (text body, A2A TextPart). Steps:

1. Source the channel-core lib. Resolve the main-worktree messages dir via the lib (git-common-dir resolution). If not in a git repo or not in tmux (`$TMUX_PANE` unset), report a one-line reason and stop.
2. Resolve sender identity (`from`) via the lib's self-by-`$TMUX_PANE` lookup.
3. Confirm `<agent>.md` exists and its `pane:` is live (lib's live check). If the inbox is unknown, list live agents and stop. If the pane is dead, report it, prune the stale inbox (lib reaper), and stop.
4. Acquire the per-inbox lockdir (`.<agent>.lock/`, lib mkdir lock) and append one message block. Header fields, A2A-derived: `id` from `uuidgen`, `from` self, `to` recipient, `type=directed`, optional `context` (carry the caller's contextId when one is in scope), optional `task` (taskId when delegating), `ts` ISO8601. Body is `<message>`. Release the lock. That is the whole skill: the persisted block is the delivery, picked up by the recipient's hooks. No tmux poke (DESIGN.md Design decision 4).

### a2a-broadcast

Args: `<message>` only. Steps:

1. Source the lib, resolve the messages dir, resolve self, same in-tmux/in-repo guards as a2a-send.
2. Enumerate live agents on this repo via the lib (reaper prunes dead inboxes), excluding self. If none, report and stop.
3. For each remaining inbox, acquire its lock and append one block with `type=broadcast` and no `to` field (fresh `id` per block from `uuidgen`, `from`, optional shared `context`, `ts`); release the lock. No poke (DESIGN.md Design decision 4).
4. Report how many inboxes received the block.

Note in the broadcast body that A2A defines no broadcast primitive (messaging is strictly bilateral); this skill is autocode's local fan-out of directed appends.

### One runnable check

`autocode/comms/skills/a2a-send/test.sh`. Assert-based bash, no framework. Against a temp messages dir with two registered stub inboxes (`alice.md`, `bob.md` with valid card frontmatter and live-looking `pane:` values, with the lib's live check stubbed so no real tmux is needed):

- Run `a2a-send bob "<text>"` as alice; assert exactly one well-formed block landed in `bob.md` (header has `from=alice`, `to=bob`, `type=directed`, an `id`, a `ts`; body matches `<text>`) and nothing landed in `alice.md`.
- Run `a2a-broadcast "<text>"` as alice; assert a `type=broadcast` block (no `to`) landed in `bob.md` and that `alice.md` got none (all-but-self).

The script sets a stub `$TMUX_PANE`, points the lib at the temp dir, and asserts only file-side mutations. There is no tmux poke to exercise (delivery is the hooks' job).
