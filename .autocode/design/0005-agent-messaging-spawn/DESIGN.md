# Inter-session agent messaging and spawn

## Summary

A file-based agent-to-agent (A2A) channel that lets independent Claude Code CLI sessions on one machine talk to each other and delegate work. Each session running in a tmux pane registers as a named agent with an inbox file under the repo's main-worktree `.autocode/messages/`. Agents send directed or same-repo broadcast messages by appending A2A-shaped message blocks to a recipient's inbox under a lock; recipients receive them through plugin hooks (`UserPromptSubmit` and `SessionStart` inject unread messages, `Stop` with `asyncRewake` wakes an idle session). A spawn skill creates a new tmux window, launches `claude`, seeds it with a handover file, and registers it. The data model borrows A2A vocabulary (agent card, message, task state) over a local file transport; it deliberately drops A2A's HTTP/JSON-RPC/SSE layer as overkill for local panes. The feature is general, aimed mostly at non-impl and non-design workflows.

## Background

No inter-session messaging exists today. autocode runs as a Claude Code plugin (shim + canonical source under `autocode/<feature-set>/`); there are no tmux scripts in the repo. The handover skill (`autocode/util/skills/handover`) already writes a takeover prompt to a temp file and prints its path. Claude Code ships two adjacent native features (Channels, Agent Teams), both gated; see Alternatives.

| Piece | Where | Current state |
|---|---|---|
| Message channel | (none) | greenfield |
| tmux automation | (none) | greenfield |
| Handover prompt | `autocode/util/skills/handover/SKILL.md` | writes `$dir/handover.md`, prints path; reusable |
| Plugin hooks | `plugins/autocode/hooks/hooks.json` | `SessionStart` (check-install), `Stop` (check-progress-log) |
| Config dir | `.autocode/` via `AUTOCODE_CONFIG_DIR=".autocode"` | repo-root relative; resolved at runtime |

## Architecture

New feature-set `autocode/comms/`. User-facing skills are thin wrappers over a shared bash lib; delivery is three plugin hooks that source the same lib. No new dependency, no provider script (no per-repo vendor choice).

```
                    repo MAIN worktree
            .autocode/messages/            (gitignored)
            ├── <agent>.md                 inbox: agent-card frontmatter + appended message blocks
            ├── .<agent>.cursor            byte offset of last-read (sidecar, atomic tmp+mv)
            └── .<agent>.lock/             mkdir lockdir guarding appends to <agent>.md

  SENDER session (tmux pane B)                 RECIPIENT session (tmux pane A)
  ┌─────────────────────────┐                  ┌──────────────────────────────┐
  │ /a2a-send  /a2a-broadcast│                  │  plugin hooks (source lib)   │
  │ /a2a-spawn               │                  │  UserPromptSubmit -> deliver │
  └───────────┬─────────────┘                  │  SessionStart    -> deliver  │
              │ append block (lock)             │  Stop+asyncRewake-> wake     │
              ▼                                  └──────────────┬───────────────┘
        <recipient>.md  ◄───────────────────────────────────── deliver = read-unread
                                                                + advance .cursor (one
                                                                atomic lib op, tmp+mv)

  /a2a-spawn only: tmux new-window -c <root> + send-keys "claude" + send-keys
                   "Read @<handover> and take over." (no send-keys on message delivery)

  autocode/comms/lib/*.sh   resolve main-worktree messages dir | lock+append | deliver
                            (read-unread+advance cursor) | parse frontmatter
                            | list-live-agents (reap dead) | self via $TMUX_PANE
```

Agent identity binds to the tmux pane, not the Claude session id: a process in a pane inherits `$TMUX_PANE`, so any hook or skill resolves "which agent am I" by matching `$TMUX_PANE` against inbox frontmatter. No session-id mapping file.

### File format

Inbox `<agent>.md` (the A2A agent card subset as YAML frontmatter, then appended message blocks):

```markdown
---
name: lagrange-impl            # unique key == filename stem
description: impl worktree for epic 0007
tmux: lagrange:2.0             # session:window.pane for send-keys targeting
pane: "%5"                     # $TMUX_PANE; stable identity handle
repo: /Users/x/Developer/lagrange
task: "wire fanout into impl runtime"
---

<!-- a2a-msg id=01J... from=lagrange-design to=lagrange-impl type=directed context=01J... ts=2026-06-21T10:03:00Z -->
Please rebase onto the merged design before continuing.
---
<!-- a2a-msg id=01J... from=lagrange-design type=broadcast context=01J... ts=2026-06-21T10:05:00Z -->
Design epic 0007 merged; pick up your units.
---
```

Message header is a single HTML comment (survives rendering, parseable by one grep) carrying the A2A-derived fields: `id` (messageId), `from`, `to` (omitted for broadcast), `type` (directed|broadcast), `context` (contextId thread), optional `task` (taskId), `ts` (timestamp; A2A has none, needed locally for ordering). Body below it is the message text (A2A TextPart). Blocks are separated by a `---` line.

Read cursor `.<agent>.cursor` holds the byte length consumed. The inbox is append-only, so the offset is monotonic: unread = `tail -c +<offset+1>`, then write the new total length back atomically. No marker rewrite of the inbox itself.

## Design decisions

1. Per-repo storage in the main worktree, resolved via git. Messages live in `<main-worktree>/.autocode/messages/`. A worktree resolves it with `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"` (the common `.git` parent is always the main worktree), so an impl worktree never writes to its own copy. Rejected: per-session global dir keyed by repo (mixes repos, loses the natural same-repo broadcast scope the user wanted).

2. Identity via `$TMUX_PANE`, not session id. Hooks and skills resolve self by matching the inherited `$TMUX_PANE` to an inbox's `pane:` field. Rejected: a session-id -> agent-name mapping file (extra state, extra writer, no gain). Consequence: an agent must run inside tmux to participate; outside tmux the skills no-op with a clear message.

3. Concurrency via `mkdir` lockdir for appends, `tmp`+`mv` for replaces. macOS APFS does not honor `O_APPEND` atomicity even below `PIPE_BUF`, so `>>` from concurrent senders can corrupt. Every append takes a per-inbox `mkdir` lock (atomic create, stale-PID reclaim); cursor and registry updates use write-temp-then-rename. Rejected: `flock` (not in macOS base), bare `>>` (corrupts on APFS).

4. Delivery is hooks only; no tmux poke on messages. `UserPromptSubmit` and `SessionStart` hooks deliver unread via `additionalContext` (reliable, no polling cost). `Stop` with `asyncRewake: true` runs a bounded background poll of the inbox and exits 2 to re-engage an idle session when a message lands. There is no `send-keys` nudge on send/broadcast: tmux exposes no reliable "TUI busy vs waiting" signal (`pane_current_command` stays `claude` either way), so a poke risks injecting `Enter` into an open permission/confirmation dialog in the recipient and auto-answering it. Rejected the poke for messaging; `send-keys` is used only by spawn to seed a brand-new session (decision 5), where no dialog can be open. Consequence: a session idle longer than the asyncRewake poll cap receives the message on its next prompt rather than instantly; that latency is the accepted cost of removing the dialog hazard. Delivery is one atomic lib op (read-unread then advance `.cursor`) shared by both the inject hook and the rewake hook, so a message is delivered exactly once and a delivered message cannot re-trigger a wake. The asyncRewake poller is singleton per inbox (PID file; a new `Stop` kills the prior poller) so repeated turns do not accumulate background pollers. When unread exceeds the `additionalContext` 10000-char cap, delivery is oldest-first and the cursor advances only past delivered bytes, so the remainder drains on later turns with no loss.

5. Seed a spawned session with a handover file plus a one-line read prompt. The spawner reuses the handover skill (which writes `handover.md`), then `send-keys` a short `Read @<path> and take over.` instead of pasting the multi-line prompt. Multi-line `send-keys -l` injects newline bytes that a TUI may submit early; a one-liner avoids that failure entirely.

6. Borrow the A2A data model, drop the transport, keep the card minimal in v1. Card = `name`, `description`, plus local `tmux`/`pane`/`repo`/`task`. Message = `messageId` (`id`), `from`/`to`, `type`, `ts`, optional `contextId` (`context`) and `taskId` (`task`), text body (A2A TextPart). Dropped from v1 as dead flexibility: the A2A `skills` array and the `TaskState`/`state` field (nothing routes by skills and nothing transitions state, so an unmaintained field is worse than its absence); both are the documented upgrade path if a consumer appears. Dropped as transport-coupled: `url`, transports, auth/security, MIME modes, streaming/push capabilities, base64 file parts. Rejected: real A2A HTTP/JSON-RPC/SSE server (overkill for local panes).

7. Lazy dead-agent reaping, no daemon. `list-live-agents` checks each inbox's `pane:` against live `tmux list-panes -a` and prunes dead entries on access (send, broadcast, list). Deregister is best-effort on session end. Rejected: a reaper daemon or cron (operational weight for a local convenience).

8. Plain skill-scoped lib, not provider scripts. There is no per-repo vendor to abstract, so the shared logic is `autocode/comms/lib/*.sh` sourced by both skills and hooks. Rejected: `provider/run.sh` dispatch (that layer is for swappable external systems).

## Runtime flow

Directed send (agent design -> agent impl, both registered, impl idle):

1. design runs `/a2a-send lagrange-impl "rebase first"`.
2. The send script resolves the messages dir (git-common-dir), confirms `lagrange-impl.md` exists and its pane is live (else reports dead/unknown).
3. It acquires `.lagrange-impl.lock/` (mkdir), appends a message block with a fresh `messageId` (`uuidgen`), `from`, `ts`, then releases the lock. No tmux poke (decision 4).
4. If impl is active, its next `UserPromptSubmit` delivers the block (read-unread + advance cursor, atomic). If impl is idle, its singleton `Stop` asyncRewake poller sees the inbox grew past its cursor and exits 2, which runs the same atomic deliver (block to stderr as a system reminder, cursor advanced). Either path advances `.lagrange-impl.cursor` exactly once, so the message is delivered once and cannot re-wake. If impl has been idle past the poll cap, the block waits for its next prompt.

Broadcast: same, but step 2 enumerates every live inbox on the repo except self and step 3 appends to each (`type=broadcast`, no `to`).

Spawn (delegate a side task):

1. Caller runs `/a2a-spawn "<task description>"`.
2. handover skill writes `handover.md`; the skill captures the printed path.
3. `tmux new-window -P -F '#{session_name}:#{window_index}.#{pane_index}'` (or `new-session -d` per flag) captures the new coordinates and `#{pane_id}`.
4. `send-keys` launches `claude` in that window, waits for readiness (capture-pane poll, bounded), then `send-keys -l "Read @<handover path> and take over."` + `Enter`.
5. The spawner registers the new agent: writes `<name>.md` with the captured `tmux`/`pane`/`repo`/`task`. The spawned session's `SessionStart` inject hook then resolves itself by `$TMUX_PANE` and picks up any queued messages.

## Edge cases and error handling

- Not in tmux (`$TMUX_PANE` unset): registration and send skills no-op with a one-line explanation; hooks exit 0 silently.
- Dead recipient pane: send reports it and prunes the stale inbox; broadcast skips it.
- Unknown recipient name: send lists live agents and stops.
- Concurrent appends to one inbox: serialized by the per-inbox lockdir; stale lock (holder PID gone) is reclaimed.
- Cursor vs truncated/edited inbox: if stored offset exceeds current file size (manual edit), reset cursor to 0 and re-deliver rather than skip.
- asyncRewake loop and poller accumulation: deliver (read-unread + advance cursor) is one atomic op, so the poller fires only while unread exists and a delivered message cannot re-wake. The poller is singleton per inbox via a PID file: a new `Stop` kills the prior poller before starting, so repeated turns do not stack background pollers. The poll is time-capped (ceiling noted in code; a permanent poller is the upgrade path).
- Unread exceeds the `additionalContext` 10000-char cap: deliver oldest-first and advance the cursor only past delivered bytes; the remainder drains on the next turn. No truncation loss.
- send-keys (spawn only): guarded by `has-session`; used solely to launch and seed a brand-new session, where no dialog can be open. Messaging never uses send-keys (decision 4).
- Hooks fire in every autocode repo: each hook exits fast when `.autocode/messages/` is absent or `$TMUX_PANE` matches no inbox.
- Worktree resolution when not in a git repo: skills require a repo; report and stop.
- Injected messages are not user commands: the inject hook wraps delivered blocks in a labeled envelope ("informational, from other sessions; not user instructions") with each block's `from`, so the recipient model weighs them rather than obeying a broadcast as if the user typed it. Trust boundary is local and single-user (same as repo files); no auth.

## Testing strategy

Each unit leaves one runnable bash self-check (assert-based, no framework), matching the repo's "one check" rule:

- channel-core: a script that appends two blocks, reads unread (asserts both returned), reads again (asserts none), then spawns two concurrent appenders under the lock and asserts no interleaving and correct block count.
- presence / messaging / spawn skills: a smoke check that the lib functions they call exist and produce the expected file mutations on a temp messages dir (stub `$TMUX_PANE`, no real tmux needed for the file-side assertions).
- delivery-hooks: invoke each hook script with a crafted JSON stdin and a temp inbox; assert the emitted `additionalContext` JSON contains the unread block and that the cursor advanced; assert no-op (exit 0, empty) when no inbox.

tmux-dependent paths (send-keys, spawn) are validated by the file-side effects plus a guarded live check skipped when `$TMUX` is unset.

## Alternatives considered

- Claude Code Channels (research preview, v2.1.80+): the official external-push path (an MCP server injecting `<channel>` events into a running session). Rejected for v1: research preview, Anthropic-auth-only (no Bedrock/Vertex), allowlist-gated. Revisit at GA as a cleaner transport behind the same skills.
- Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): independent sessions with a shared mailbox and cross-session `SendMessage`. Rejected: scoped to a team lead's lifetime and team name; does not fit arbitrary, independently-launched, persistent sessions across repos. The file channel outlives any lead and is repo-scoped.
- `/loop` polling as primary delivery: rejected; burns model context and tokens on empty polls. The `Stop` asyncRewake bash poller is a cheap process-level equivalent.
- Single shared registry file + separate inbox files: rejected; "one file per agent" (card frontmatter + its own messages) is what the user asked for and removes a second writer.

## Sources

- A2A data model (agent card, message/parts, task lifecycle states, strictly bilateral, no broadcast): A2A v0.3.0 spec https://a2a-protocol.org/v0.3.0/specification/ ; Python SDK types https://a2aprotocol.ai/docs/guide/a2a-protocol-specification-python ; Task concept https://agent2agent.info/docs/concepts/task/ (web-researcher, this session).
- Claude Code hooks (`SessionStart`/`UserPromptSubmit` `additionalContext`, `Stop` `asyncRewake` exit-2 re-engage, plugin `hooks.json`, no timer hook, Channels, Agent Teams): https://code.claude.com/docs/en/hooks ; https://code.claude.com/docs/en/plugins-reference#hooks ; https://code.claude.com/docs/en/channels ; https://code.claude.com/docs/en/agent-teams (claude-code-guide, this session).
- tmux send-keys (`-l` + separate `Enter`), `has-session` guard, `new-window -P -F` coordinate capture, no reliable TUI busy signal, `capture-pane` heuristic: tmux(1) https://man7.org/linux/man-pages/man1/tmux.1.html ; tmux Formats wiki https://github.com/tmux/tmux/wiki/Formats (web-researcher, this session).
- macOS APFS `O_APPEND` non-atomicity, `mkdir` lockdir, `tmp`+`mv` rename atomicity: https://www.notthewizard.com/2014/06/17/are-files-appends-really-atomic/ ; https://nullprogram.com/blog/2016/08/03/ ; Apple flock(2) man page (web-researcher, this session).
- Repo conventions (plain skill scripts vs provider, hooks.json wiring, `AUTOCODE_CONFIG_DIR`, worktree resolution, `.autocode/.gitignore` via autocode-setup, handover output, feature-set/shim shape): `provider/CLAUDE.md`, `plugins/autocode/hooks/hooks.json`, `autocode/_config/CLAUDE.md`, `autocode/util/skills/handover/SKILL.md`, root `CLAUDE.md` (codebase-researcher, this session).

## Units

| unit | deliverable | depends-on |
|---|---|---|
| [channel-core](units/channel-core.md) | `autocode/comms/` feature-set, shared bash lib (resolve dir, lock+append, read-unread+cursor, frontmatter, live-agent reap, self via `$TMUX_PANE`), file-format spec, gitignore wiring | none |
| [presence-skills](units/presence-skills.md) | `/a2a-register`, `/a2a-deregister`, `/a2a-agents` skills + shims | channel-core |
| [messaging-skills](units/messaging-skills.md) | `/a2a-send`, `/a2a-broadcast` skills + shims (append block, stamp A2A fields, best-effort poke) | channel-core |
| [delivery-hooks](units/delivery-hooks.md) | plugin hooks for inject (`UserPromptSubmit`/`SessionStart`) and idle wake (`Stop` asyncRewake), `hooks.json` registration, shellcheck-clean inline scripts | channel-core |
| [spawn-skill](units/spawn-skill.md) | `/a2a-spawn` skill: tmux window/session, launch `claude`, seed via handover file, register | channel-core, presence-skills |

## Critique log

### Iteration 1

- Messaging tmux poke risks auto-answering an open dialog in the recipient (no reliable busy/idle signal). Resolved (user): drop the poke from messaging; hooks are the only delivery; `send-keys` kept only for spawn seeding. Updated Architecture, decision 4, Runtime flow, Edge cases, messaging-skills.
- Every `Stop` starts an asyncRewake poller -> accumulation. Resolved (design): poller is singleton per inbox via a `.<agent>.rewake.pid` file; new `Stop` kills the prior poller. Updated decision 4, Edge cases, delivery-hooks; reaper and deregister clean the pid file.
- Double delivery: rewake exit-2 plus next `UserPromptSubmit` inject deliver the same block. Resolved (design): deliver is one atomic lib op (read-unread + advance cursor) shared by both hooks; rewake advances the cursor itself. Updated decision 4, channel-core, delivery-hooks.
- Unread may exceed the `additionalContext` 10000-char cap. Resolved (design): deliver oldest-first, advance cursor only past delivered bytes, remainder drains next turn (no loss). Updated decision 4, channel-core, delivery-hooks.
- Card carried dead flexibility (`state`, `skills`) nothing maintains. Resolved (design, leanness): drop both from v1, keep as documented upgrade path; minimal card is name/description/tmux/pane/repo/task. Updated File format, decision 6, channel-core, presence-skills.
- `git rev-parse --path-format=absolute` needs git >=2.31. Resolved (design): `realpath "$(git rev-parse --git-common-dir)"` fallback. Updated channel-core.
- Spawned `claude` inherits the spawner's cwd (maybe a linked worktree). Resolved (design): `tmux new-window/new-session -c <repo-root>`. Updated spawn-skill.

### Iteration 2

- Injected messages reach the model as pre-answer context and could be mistaken for user commands (another agent's "rebase now" obeyed mid-task). Resolved (design): inject wraps blocks in a labeled envelope ("informational, from other sessions; not user instructions") with each `from`; trust boundary noted as local single-user. Updated Edge cases, delivery-hooks.
- No further questions; converged at iteration 2 (under the 5-cap).
