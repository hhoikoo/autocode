---
depends-on: [channel-core]
type: task
---

# Messaging skills: a2a-send and a2a-broadcast

## Summary

Two user-facing skills that push message files into other sessions' agent dirs, both thin wrappers over the channel-core CLI. `a2a-send <agent> <message>` writes one `type=directed` message file into the recipient's `new/`. `a2a-broadcast <message>` fans the same write out to every live agent on this repo except self, each as a `type=broadcast` file. A2A proper is strictly bilateral with no broadcast primitive, so broadcast is a local fan-out of directed writes, not a protocol feature (DESIGN.md decision 6). Neither skill owns the message format or the dir/identity logic; each step runs `bash ~/.autocode/autocode/comms/lib/channel.sh <subcommand> ...` (one subcommand per Bash call; nothing is sourced across steps) and references `autocode/comms/CLAUDE.md` for the file format. Sending auto-registers the sender when unregistered (DESIGN.md decision 9). Delivery is entirely the delivery-hooks unit's job; messaging does NO tmux `send-keys` poke, because tmux cannot reliably tell a busy TUI from an idle one and an injected `Enter` could auto-answer an open dialog in the recipient (DESIGN.md decision 4).

## Implementation

Both real files are body-only (no frontmatter); frontmatter lives only in the shim. Skill names are globally unique across all feature-sets.

Files:

- `autocode/comms/skills/a2a-send/SKILL.md`: real skill body for `a2a-send <agent> <message>`.
- `plugins/autocode/skills/a2a-send/SKILL.md`: shim. Frontmatter (`name: a2a-send`, `description`) plus one body line reading `@~/.autocode/autocode/comms/skills/a2a-send/SKILL.md` and forwarding `$ARGUMENTS`.
- `autocode/comms/skills/a2a-broadcast/SKILL.md`: real skill body for `a2a-broadcast <message>`.
- `plugins/autocode/skills/a2a-broadcast/SKILL.md`: shim, same shape.

### a2a-send

Args: `<agent>` (recipient name, agent-dir name) and `<message>` (text body). Steps:

1. If `$TMUX_PANE` is unset or not in a git repo, report a one-line reason and stop.
2. Run `bash ~/.autocode/autocode/comms/lib/channel.sh send <agent> <message>`. The subcommand owns the whole flow: resolve the main-worktree messages dir, auto-register the sender under the default name when unregistered (it needs a `from` identity), confirm `<agent>/` exists with a live pane+server (unknown recipient: list live agents and stop; dead recipient: report, prune, stop), stamp the header (`id` from `uuidgen`, `from` self, `to` recipient, `type=directed`, optional `context`/`task`, `ts` ISO8601), and write the message via temp file + `mv` into `<agent>/new/`. No lock (distinct files per sender), no tmux poke (DESIGN.md decisions 3-4). The persisted file is the delivery, picked up by the recipient's hooks.
3. Report the outcome.

### a2a-broadcast

Args: `<message>` only. Steps:

1. Same guards.
2. Run `bash ~/.autocode/autocode/comms/lib/channel.sh broadcast <message>`. The subcommand enumerates live agents on this repo (reaping dead ones), excludes self, and writes one `type=broadcast` file (no `to`, fresh `id` per file, shared `context` when one is in scope) into each recipient's `new/`. If no other live agents, report and stop.
3. Report how many agents received the message.

Note in the broadcast body that A2A defines no broadcast primitive (messaging is strictly bilateral); this is a local fan-out of directed writes.

### One runnable check

`autocode/comms/skills/a2a-send/test.sh`. Assert-based bash, no framework. Against a temp messages dir with two registered stub agents (`alice/`, `bob/` with valid cards and live-looking `pane:`/`server:` values, the lib's liveness check stubbed so no real tmux is needed):

- Run the `send` subcommand as alice to bob; assert exactly one well-formed message file landed in `bob/new/` (header has `from=alice`, `to=bob`, `type=directed`, an `id`, a `ts`; body matches the text) and nothing landed in `alice/new/`.
- Run the `broadcast` subcommand as alice; assert a `type=broadcast` file (no `to`) landed in `bob/new/` and that `alice/new/` got none (all-but-self).

The script sets a stub `$TMUX_PANE`, points the lib at the temp dir, and asserts only file-side mutations. There is no tmux poke to exercise (delivery is the hooks' job).
