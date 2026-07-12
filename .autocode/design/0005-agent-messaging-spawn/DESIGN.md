# Inter-session agent messaging and spawn

## Summary

A file-based agent-to-agent channel that lets independent Claude Code CLI sessions on one machine talk to each other and delegate work. Each session running in a tmux pane registers as a named agent with a message directory under the repo's main-worktree `.autocode/messages/`. Agents send directed or same-repo broadcast messages by writing one message file per recipient into the recipient's `new/` dir (write-temp-then-rename, atomic, lock-free); recipients receive them through plugin hooks (`UserPromptSubmit` and `SessionStart` inject unread messages, `Stop` with `asyncRewake` wakes an idle session, `SessionEnd` cleans up). A spawn skill creates a new tmux window, launches `claude`, seeds it with a handover file, and registers it. Message headers carry only local fields (`id`, `from`, `to`, `type`, `ts`); the addressing model (`from`/`to`, broadcast) is our own. This is a local file channel, not the A2A protocol, and does not aim at interop. The feature is general, aimed mostly at non-impl and non-design workflows.

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

New feature-set `autocode/comms/`. User-facing skills are thin wrappers over a shared bash file that doubles as a subcommand CLI (for skills) and a sourceable function lib (for hooks). No new dependency, no provider script (no per-repo vendor choice).

```
                    repo MAIN worktree
            .autocode/messages/<agent>/    (gitignored)
            ├── card.md                    agent card frontmatter (tmp+mv rewrite)
            ├── new/<ts>-<uuid>.md         one unread message per file (tmp+mv in)
            ├── cur/<ts>-<uuid>.md         delivered (claim = rename new/ -> cur/)
            └── rewake.pid                 singleton idle-wake poller

  SENDER session (tmux pane B)                 RECIPIENT session (tmux pane A)
  ┌─────────────────────────┐                  ┌──────────────────────────────┐
  │ /comms-send  /comms-broadcast│                  │  plugin hooks (source lib)   │
  │ /comms-spawn               │                  │  UserPromptSubmit -> deliver │
  └───────────┬─────────────┘                  │  SessionStart    -> deliver  │
              │ write tmp + mv                  │  Stop+asyncRewake-> wake     │
              ▼                                  │  SessionEnd -> kill poller, │
        <recipient>/new/  ◄──────────────────── │               rm agent dir  │
                                                 └──────────────┬───────────────┘
                                                 deliver = claim each new/ file by
                                                 rename into cur/, then emit content

  /comms-spawn only: tmux new-window -c <root> + send-keys "claude" + send-keys
                   "Read @<handover> and take over." (no send-keys on message delivery)

  autocode/comms/lib/channel.sh   executed: subcommands for skills (register, send,
                                  broadcast, deliver, agents, deregister)
                                  sourced: same functions for hook scripts
```

Agent identity binds to the tmux pane plus the tmux server: a process in a pane inherits `$TMUX_PANE`, so any hook or skill resolves "which agent am I" by matching `$TMUX_PANE` against card frontmatter. Pane ids are unique only per server lifetime (they restart at `%0` after a server restart), so the card also records the server pid and liveness checks both. No session-id mapping file.

### File format

Agent card `<agent>/card.md` (YAML frontmatter only; rewritten freely via tmp+mv, never appended to):

```markdown
---
name: lagrange-impl            # unique key == directory name
description: impl worktree for epic 0007
pane: "%5"                     # $TMUX_PANE; identity handle and send-keys target
server: "1234"                 # tmux server pid; guards pane-id reuse across restarts
task: "wire fanout into impl runtime"
---
```

Display coordinates (`session:window.pane`) are derived at read time via `tmux display-message -p -t "$pane"`, never stored: window moves and renumbering would stale a stored value.

Message file `<agent>/new/<ts>-<uuid>.md`, one message per file; the filename orders delivery:

```markdown
<!-- comms-msg id=01J... from=lagrange-design to=lagrange-impl type=directed ts=2026-06-21T10:03:00Z -->
Please rebase onto the merged design before continuing.
```

The header is a single HTML comment (survives rendering, parseable by one grep) carrying `id` (message id), `from`, `to` (omitted for broadcast), `type` (directed|broadcast), `ts` (ISO8601, needed locally for ordering). The body below it is the message text. No thread-id or delegated-task field: v1 has no reader for either, so both fail the same dead-flexibility test that cut `state`/`skills` from the card in iteration 3.

Read state is positional, not a marker: files in `new/` are unread; delivery claims a file by renaming it into `cur/` (atomic on one filesystem; exactly one of two concurrent deliverers wins the rename), then emits its content. `cur/` doubles as cheap history; the reaper prunes the whole agent dir when the agent dies.

## Design decisions

1. Per-repo storage in the main worktree, resolved via git. Messages live in `<main-worktree>/.autocode/messages/`. A worktree resolves it with `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"` (the common `.git` parent is always the main worktree), so an impl worktree never writes to its own copy. v1 supports the default `.autocode/` config-dir location only: when `<main-worktree>/.autocode/` is absent, skills report and stop, hooks no-op. Rejected: per-session global dir keyed by repo (mixes repos, loses the natural same-repo broadcast scope the user wanted).

2. Identity via `$TMUX_PANE` plus tmux server pid, not session id. Hooks and skills resolve self by matching the inherited `$TMUX_PANE` to a card's `pane:` field, and liveness additionally requires the card's `server:` to equal the running tmux server pid, because pane ids reset after a server restart and a stale card could otherwise match a new unrelated pane. Rejected: a session-id -> agent-name mapping file (extra state, extra writer, no gain). Consequence: an agent must run inside tmux to participate; outside tmux the skills no-op with a clear message.

3. Concurrency via one-file-per-message and tmp+rename; no locks. Every write (message files, card) is write-temp-then-rename on the same filesystem, which is atomic; concurrent senders write distinct files (timestamp+uuid names), so there is no shared append target to corrupt and no lock to hold, reclaim, or leak. Rejected: a single append-only inbox per agent with a byte-offset cursor and a `mkdir` lockdir. That is the mbox model Maildir was designed to replace: it needed cursor initialization past the frontmatter, broke its own monotonic-offset invariant whenever the card was rewritten, required stale-PID lock reclaim (a known-fragile idiom), left the deliver/cursor-advance path unlocked against the background poller, and rested on `O_APPEND` atomicity that APFS may not honor. Both surveyed precedents (mcp_agent_mail, Claude Code agent teams' mailbox) use per-message files. Rejected: `flock` (the flock(1) CLI is not in macOS base; the flock(2) syscall exists but bash needs the CLI).

4. Delivery is hooks only; no tmux poke on messages. `UserPromptSubmit` and `SessionStart` hooks deliver unread via `additionalContext` (reliable, no polling cost). Deliver = claim each `new/` file oldest-first by renaming it into `cur/`, then emit its content; the rename is the single atomic claim point shared by the inject and rewake paths, so concurrent hook runs cannot double-deliver a message. The contract is stated, not assumed: each message is claimed exactly once; a crash between claim and emit loses that message (a millisecond window, accepted and documented). Inject caps one injection at the 10000-char `additionalContext` limit by whole messages; the remainder stays in `new/` and drains on later turns with no loss (a single over-cap message is delivered alone and relies on the harness's documented overflow-to-file handling). `Stop` with `asyncRewake: true` runs a background poll of `new/` and exits 2 to re-engage an idle session when a message lands; the poller is singleton per agent (`rewake.pid`; a new `Stop` kills the prior poller). asyncRewake hooks default to a 60s timeout (max 86400s), so the hooks.json entry sets an explicit `timeout` (28800s, 8h) and the poll window equals it; a session idle past that window receives the message on its next prompt. 8h covers a session left idle across a working day (the delegate-then-walk-away workflow), and each `Stop` resets the poller, so the window only binds on a session that gets no further turns; the value is a one-number change (max 86400s). Known cosmetic issue: rewake stderr renders visibly in the recipient terminal (claude-code #44872); accepted. There is no `send-keys` nudge on send/broadcast: tmux exposes no reliable "TUI busy vs waiting" signal (`pane_current_command` stays `claude` whether the pane is idle-at-prompt, mid-tool, or showing a Yes/No dialog), so a poke risks landing `Enter` in an open permission dialog, whose pre-selected default a bare `Enter` accepts, auto-approving a pending tool call. This was evaluated directly: Anthropic's own agent-teams tried `tmux send-keys` to wake idle teammates and it failed (claude-code #24108); a general external-injection request was closed with nothing shipped (#27441); and capture-pane scraping, the only state signal available, is version-fragile (it silently broke a shipped orchestrator when a Claude Code point release changed a dialog's default option, awslabs/cli-agent-orchestrator #119). Re-arming the poller from inside the recipient on idle was also evaluated and rejected: the `Notification`/`idle_prompt` event fires once, ~60s after `Stop`, on a hardcoded timer, and no recurring "still idle" event exists, so it gives no meaningful extension over the already-running `Stop` poller. `send-keys` is used only by spawn to seed a brand-new session (decision 5), where no dialog can be open.

5. Seed a spawned session with a handover file plus a one-line read prompt. The spawner runs the handover skill inline (skills compose in-context, not as subprocesses: the same session executes handover's steps and therefore has the written `handover.md` path in context), then `send-keys` a short `Read @<path> and take over.` instead of pasting the multi-line prompt. Multi-line `send-keys -l` injects newline bytes that a TUI may submit early; a one-liner avoids that failure entirely.

6. Not the A2A protocol; a local file channel. The message id is a plain `uuidgen` value and the card is a local name tag (name, description, pane, server, task); no A2A field names, AgentCard shape, or `role`/`contextId`/`taskId` semantics are used. A2A (v1.0.1 at time of writing) is an HTTP/JSON-RPC protocol for remote agent interop, strictly bilateral with no broadcast, whose Message carries no `from`/`to`/timestamp (direction is a two-value `role` enum) and whose AgentCard requires `skills`, an endpoint, and `capabilities`; it fits neither local tmux panes nor the same-repo broadcast scope this design wants. The user-facing skills use the `comms-` prefix, matching the `comms/` feature-set. Rejected: a real A2A server (overkill for local panes); borrowing A2A field names as decoration (earlier drafts did; the borrowed `context`/`task` never gained a reader and were cut, leaving nothing meaningfully A2A-shaped).

7. Lazy dead-agent reaping plus a `SessionEnd` cleanup hook, no daemon. `list-live-agents` checks each card's `pane:` against live `tmux list-panes -a` and its `server:` against the running server pid, pruning dead agent dirs on access (send, broadcast, list). A `SessionEnd` hook kills the session's recorded rewake poller and removes its agent dir (the hook is cleanup-only by contract: exit codes ignored, keep it to kill+rm; messages queued for a dead agent are moot). This also covers the case pane-liveness cannot see: `claude` exited but the pane's shell lives on. Rejected: a reaper daemon or cron (operational weight for a local convenience).

8. One shared bash file: a CLI for skills, sourceable for hooks. `autocode/comms/lib/channel.sh` dispatches subcommands when executed (`bash channel.sh send|broadcast|register|deregister|deliver|agents ...`) and defines the same functions when sourced. Skills invoke one subcommand per step because each skill step runs as an independent Bash call with no persisted shell state; `git-commit`'s `commit.sh <subcommand>` is the repo precedent. Hook scripts are single processes, so they source it. Skills and hooks both reference the canonical copy at `~/.autocode/autocode/comms/lib/channel.sh` (absolute path; `@`-reference env vars do not expand). Rejected: `provider/run.sh` dispatch (that layer is for swappable external systems); a source-only lib (skill steps cannot share sourced state across Bash calls).

9. Receiving is opt-in; sending auto-registers. A session receives messages only after its agent dir exists, via explicit `/comms-register` or by being spawned; that keeps the per-prompt hooks a fast no-op by default. Outbound skills (`comms-send`, `comms-broadcast`, `comms-spawn`) auto-register the sender under the default name when unregistered, since they need a `from` identity anyway. The default-name scheme (`<session_name>-<window_index>`) is defined once, in channel-core.

## Runtime flow

Directed send (agent design -> agent impl, both registered, impl idle):

1. design runs `/comms-send lagrange-impl "rebase first"`.
2. The send subcommand resolves the messages dir (git-common-dir), auto-registers the sender if needed, and confirms `lagrange-impl/` exists with a live pane+server (else reports dead/unknown).
3. It composes a message block with a fresh `id` (`uuidgen`), `from`, `ts`, writes it to a temp file, and `mv`s it into `lagrange-impl/new/`. No lock, no tmux poke (decision 4).
4. If impl is active, its next `UserPromptSubmit` delivers (claim by rename into `cur/`, emit). If impl is idle, its singleton `Stop` asyncRewake poller sees the file in `new/`, claims it the same way, and exits 2 with the content on stderr. The rename is the single claim point, so the message is delivered once and a delivered message cannot re-trigger a wake. If impl has been idle past the poller's timeout, the file waits in `new/` for its next prompt.

Broadcast: same, but step 2 enumerates every live agent dir on the repo except self and step 3 writes one file per recipient (`type=broadcast`, no `to`).

Spawn (delegate a side task):

1. Caller runs `/comms-spawn "<task description>"`.
2. The skill runs the handover skill inline, forwarding the task description; handover writes `handover.md` and prints its path, which is now in context.
3. `tmux new-window -P -F '#{pane_id}'` (or `new-session -d` per flag) captures the new pane id; the server pid comes from `tmux display-message -p '#{pid}'`.
4. `send-keys` launches `claude` in that pane, waits for readiness (bounded `capture-pane` poll, ANSI-stripped before matching), then `send-keys -l "Read @<handover path> and take over."` + `Enter`.
5. The spawner registers the new agent via the lib register subcommand: writes `<name>/card.md` with the captured `pane`, `server`, and `task`. The spawned session's `SessionStart` inject hook then resolves itself by `$TMUX_PANE` and drains any queued messages.

## Edge cases and error handling

- Not in tmux (`$TMUX_PANE` unset): registration and send skills no-op with a one-line explanation; hooks exit 0 silently.
- Dead recipient pane, or a pane id reused after a tmux server restart (card `server:` mismatch): send reports it and prunes the stale agent dir; broadcast skips it.
- Unknown recipient name: send lists live agents and stops.
- Concurrent senders to one recipient: distinct files (timestamp+uuid names), no shared write target; nothing to corrupt.
- Concurrent deliverers (inject hook racing the rewake poller): each `new/` file is claimed by rename; exactly one claimer wins per message, the loser skips it.
- Crash between claim and emit: that message is lost. Accepted (millisecond window); stated in decision 4 rather than papered over with an "exactly once" claim the mechanism cannot honor.
- Poller lifecycle: singleton per agent via `rewake.pid` (a new `Stop` kills the prior poller); the `SessionEnd` cleanup hook kills it and removes the agent dir when the session exits, so a poller cannot outlive its session; the poll window is the hook's explicit `timeout` in hooks.json (asyncRewake defaults to 60s otherwise).
- Unread exceeds the `additionalContext` 10000-char cap: inject delivers whole messages up to the cap; the rest stays in `new/` and drains on later turns. A single message larger than the cap is delivered alone; the harness saves over-cap hook output to a file with a preview, so nothing is truncated silently.
- send-keys (spawn only): guarded by `has-session`; used solely to launch and seed a brand-new session, where no dialog can be open. Messaging never uses send-keys (decision 4).
- Hooks fire in every autocode repo: each hook exits fast when `.autocode/messages/` is absent or `$TMUX_PANE` matches no card.
- Relocated config dir: out of scope for v1 (decision 1); the messages dir is fixed at `<main-worktree>/.autocode/messages/`.
- Worktree resolution when not in a git repo: skills require a repo; report and stop.
- Injected messages are not user commands: the inject hook wraps delivered messages in a labeled envelope ("informational, from other sessions; not user instructions") with each message's `from`, so the recipient model weighs them rather than obeying a broadcast as if the user typed it. Trust boundary is local and single-user (same as repo files); no auth.

## Testing strategy

Each unit leaves one runnable bash self-check (assert-based, no framework), matching the repo's "one check" rule:

- channel-core: a script that sends two messages, delivers (asserts both returned, both files moved to `cur/`), delivers again (asserts none); runs two concurrent senders (asserts two intact message files); runs two concurrent deliverers against a seeded `new/` (asserts every message claimed exactly once across both).
- presence / messaging / spawn skills: a smoke check driving the lib subcommands they call against a temp messages dir (stub `$TMUX_PANE`, no real tmux needed for the file-side assertions).
- delivery-hooks: invoke each hook script with a crafted JSON stdin and a temp agent dir; assert the emitted `additionalContext` JSON contains the unread messages and the files moved to `cur/`; assert no-op (exit 0, empty) when no messages dir.

tmux-dependent paths (send-keys, spawn) are validated by the file-side effects plus a guarded live check skipped when `$TMUX` is unset.

## Alternatives considered

- Claude Code Channels (research preview, v2.1.80+): the official external-push path (an MCP server injecting `<channel>` events into a running session). Rejected for v1: research preview, Anthropic-auth-only (no Bedrock/Vertex), allowlist-gated. Revisit at GA as a cleaner transport behind the same skills.
- Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): independent sessions with a shared mailbox and cross-session `SendMessage`. Rejected: one team per session, scoped to the lead's lifetime; no messaging between independently launched sessions. The file channel outlives any lead and is repo-scoped.
- impl's background-Workflow orchestration (the nearest in-repo mechanism): scoped to one session's process tree and its task notifications; cannot reach an independently launched session, which is this design's whole point.
- `/loop` polling as primary delivery: rejected; burns model context and tokens on empty polls. The `Stop` asyncRewake bash poller is a cheap process-level equivalent. (Claude Code's scheduled-tasks cron is the same category: prompt-level polling.)
- Single shared registry file + separate inbox files: rejected; one directory per agent (its card plus its own messages) keeps the per-agent isolation the user asked for and removes a second writer.

## Sources

- A2A spec v1.0.1 (v0.3.0 superseded 2026-03): Message has no `from`/`to`/timestamp (direction is a two-value `role` enum), no broadcast (strictly bilateral); AgentCard requires `skills`, an endpoint/interfaces, `capabilities`. https://a2a-protocol.org/latest/specification/ ; normative `spec/a2a.proto` in https://github.com/a2aproject/A2A (web-researcher, this session).
- Claude Code hooks: `SessionStart`/`UserPromptSubmit` `additionalContext` capped at 10000 chars per hook output with overflow-to-file fallback; `Stop` `asyncRewake` exit-2 wake, `timeout` default 60s / max 86400s; `SessionEnd` exists, cleanup-only, exit codes ignored; hook `timeout` unit is seconds; plugin hooks fire in every repo the plugin is enabled in. https://code.claude.com/docs/en/hooks ; https://code.claude.com/docs/en/plugins-reference#hooks ; https://code.claude.com/docs/en/channels ; https://code.claude.com/docs/en/agent-teams . Known issues: #44872 (rewake stderr rendered visibly), #29343/#26242 (injected Enter auto-answers prompts) (claude-code-guide + web-researcher, this session).
- One-file-per-message delivery (write to tmp, rename into place; read state by rename; no locks) and the mbox single-file+lock model it replaces: Maildir, https://cr.yp.to/proto/maildir.html ; https://doc.dovecot.org/2.3/admin_manual/mailbox_formats/maildir/ . Precedents using per-message files for agent mail: https://github.com/Dicklesworthstone/mcp_agent_mail ; Claude Code agent-teams mailbox (web-researcher, this session).
- Consumption-marker timing (commit after processing = at-least-once default; commit before = at-most-once): Confluent Kafka consumer docs, https://docs.confluent.io/platform/current/clients/consumer.html (web-researcher, this session).
- tmux: `send-keys -l` + separate `Enter`, `has-session` guard, `new-window -P -F` capture, pane ids unique per server lifetime (reset on server restart), no reliable TUI busy signal, ANSI-strip `capture-pane` output before matching: tmux(1) https://man7.org/linux/man-pages/man1/tmux.1.html ; https://github.com/tmux/tmux/wiki/Formats (web-researcher, this session).
- Cross-pane wake via `tmux send-keys` (evaluated, rejected as a message-wake mechanism): no tmux format distinguishes idle-at-prompt vs busy vs open-dialog (`pane_current_command` is the foreground process name only); permission dialogs have a pre-selected default that a bare `Enter` accepts; capture-pane scraping is the only signal and is version-fragile. Agent-teams' own `tmux send-keys` wake failed (https://github.com/anthropics/claude-code/issues/24108); external-injection request closed unshipped (https://github.com/anthropics/claude-code/issues/27441); point-release dialog change broke a shipped orchestrator (https://github.com/awslabs/cli-agent-orchestrator/issues/119). `Notification`/`idle_prompt` fires once on a hardcoded ~60s timer with no recurring idle event (https://github.com/anthropics/claude-code/issues/13922, #32634), so on-idle re-arm adds nothing; `asyncRewake` is a generic command-hook field usable beyond `Stop`. https://code.claude.com/docs/en/hooks (web-researcher + claude-code-guide, this session).
- macOS: flock(1) CLI absent from base (the flock(2) syscall exists; bash needs the CLI); rename(2) atomicity on one filesystem; APFS `O_APPEND` atomicity unverified (the commonly cited 2014 test predates APFS), moot under per-message files (web-researcher, this session).
- Repo conventions (plain skill scripts vs provider, `commit.sh <subcommand>` per-step CLI precedent, hooks.json wiring, `AUTOCODE_CONFIG_DIR`, `.autocode/.gitignore` via autocode-setup, handover output, feature-set/shim shape): `provider/CLAUDE.md`, `plugins/autocode/hooks/hooks.json`, `autocode/_config/CLAUDE.md`, `autocode/git/skills/git-commit/SKILL.md`, `autocode/util/skills/handover/SKILL.md`, root `CLAUDE.md` (codebase-researcher, this session).

## Units

| unit | deliverable | depends-on |
|---|---|---|
| [channel-core](units/channel-core.md) | `autocode/comms/` feature-set, shared bash CLI+lib (resolve dir, self via `$TMUX_PANE`+server, register card, write message file, deliver via rename claim, live-agent reap, deregister), file-format spec, gitignore wiring, shellcheck CI coverage | none |
| [presence-skills](units/presence-skills.md) | `/comms-register`, `/comms-deregister`, `/comms-agents` skills + shims | channel-core |
| [messaging-skills](units/messaging-skills.md) | `/comms-send`, `/comms-broadcast` skills + shims (write message files, stamp header fields, auto-register sender) | channel-core |
| [delivery-hooks](units/delivery-hooks.md) | plugin hooks for inject (`UserPromptSubmit`/`SessionStart`), idle wake (`Stop` asyncRewake), cleanup (`SessionEnd`), `hooks.json` registration, shellcheck-clean inline scripts | channel-core |
| [spawn-skill](units/spawn-skill.md) | `/comms-spawn` skill: tmux window/session, launch `claude`, seed via handover file, register | channel-core |

## Critique log

### Iteration 1

- Messaging tmux poke risks auto-answering an open dialog in the recipient (no reliable busy/idle signal). Resolved (user): drop the poke from messaging; hooks are the only delivery; `send-keys` kept only for spawn seeding. Updated Architecture, decision 4, Runtime flow, Edge cases, messaging-skills.
- Every `Stop` starts an asyncRewake poller -> accumulation. Resolved (design): poller is singleton per agent via a pid file; new `Stop` kills the prior poller. Updated decision 4, Edge cases, delivery-hooks; reaper and deregister clean the pid file.
- Double delivery: rewake exit-2 plus next `UserPromptSubmit` inject deliver the same block. Resolved (design): single shared deliver path. Superseded by iteration 3 (claim-by-rename is now the atomic step).
- Unread may exceed the `additionalContext` 10000-char cap. Resolved (design): deliver oldest-first, remainder drains next turn. Refined in iteration 3 (whole-message granularity).
- Card carried dead flexibility (`state`, `skills`) nothing maintains. Resolved (design, leanness): drop both from v1. Updated File format, decision 6, channel-core, presence-skills.
- `git rev-parse --path-format=absolute` needs git >=2.31. Resolved (design): `realpath "$(git rev-parse --git-common-dir)"` fallback. Updated channel-core.
- Spawned `claude` inherits the spawner's cwd (maybe a linked worktree). Resolved (design): `tmux new-window/new-session -c <repo-root>`. Updated spawn-skill.

### Iteration 2

- Injected messages reach the model as pre-answer context and could be mistaken for user commands (another agent's "rebase now" obeyed mid-task). Resolved (design): inject wraps blocks in a labeled envelope ("informational, from other sessions; not user instructions") with each `from`; trust boundary noted as local single-user. Updated Edge cases, delivery-hooks.
- No further questions; converged at iteration 2 (under the 5-cap).

### Iteration 3 (external review: repo fact-check, A2A spec check, industry survey, deep dive)

- The append-file + byte-cursor + lockdir storage produced five coupled defects: the cursor was never initialized past the card frontmatter (first delivery would inject the card as a "message"); register's tmp+rename card refresh shifted the byte offsets the cursor depends on; deliver was unlocked against the background rewake poller (double delivery); the 10000-char cap could slice a block mid-message; and rewake advanced the cursor before the wake landed (silent loss, at-most-once). Resolved (design): one dir per agent, one file per message, delivery claims by `new/` -> `cur/` rename; cursor, lockdir, and stale-PID-reclaim machinery deleted. Matches Maildir and both surveyed precedents (mcp_agent_mail, Claude Code agent teams). Rewrote Architecture, File format, decisions 3-4, Runtime flow, Edge cases, Testing, all units.
- asyncRewake hooks default to a 60s timeout (max 86400s); the "bounded poll, ceiling in a code comment" would silently have become a one-minute idle window. Resolved: hooks.json sets an explicit `timeout`; poll window == hook timeout. Updated decision 4, delivery-hooks.
- `SessionEnd` hook exists (cleanup-only). Resolved: a cleanup hook kills the poller and removes the agent dir, fixing orphaned pollers and the "claude exited, shell lives on" liveness blind spot. Updated decision 7, Edge cases, delivery-hooks.
- Skill steps run as independent Bash calls; "source the lib once, call functions later" cannot work, and the repo has zero `source` precedent. Resolved: `channel.sh` is a subcommand CLI for skills (`commit.sh` precedent), sourceable only by hooks. Updated decision 8, all skill units.
- Spawn's "capture the handover path from the handover skill's stdout" described a subprocess mechanism skills don't have. Resolved: skills compose inline; the path is in context. Updated decision 5, Runtime flow, spawn-skill.
- "A2A-shaped" overstated: the spec (now v1.0.1; the cited v0.3.0 is superseded) has no `from`/`to`, no broadcast, no Message timestamp, and requires card `skills`+endpoint. Resolved: reframed as loosely borrowed field names, no interop claim. Updated Summary, decision 6, Sources.
- Registration UX was unstated (nothing delivers to an unregistered session). Resolved: receiving is opt-in, outbound skills auto-register the sender, one default-name scheme owned by channel-core (spawn and register previously disagreed). New decision 9.
- Pane-id reuse after a tmux server restart could make a stale card match a new unrelated pane. Resolved: card stores the server pid; liveness = pane AND server match. Updated decision 2, File format, Edge cases.
- Stored `tmux:` coords went stale on window moves; `repo:` had no reader; `comms-agents` printed a `state` field decision 6 had dropped; the Units table still said "best-effort poke". Resolved: coords derived at read time, `repo`/`state` dropped, table fixed.
- CI shellcheck globs miss the `autocode/` tree, so the load-bearing lib would ship unlinted despite channel-core claiming otherwise. Resolved: channel-core adds `autocode` to the shape-check find roots.
- The APFS `O_APPEND` citation predates APFS and may have measured pipe atomicity. Moot under per-message files; decision 3 now rests on rename atomicity.

### Iteration 4 (user grill: naming, dead fields, spawn scope, idle-wake)

- Skill prefix `a2a-` contradicted the `comms/` feature-set and implied A2A-protocol conformance decision 6 disclaims. Resolved (user): rename every user-facing skill and the hook scripts and the message marker to `comms-*` / `comms-msg`. Renamed across DESIGN.md and all units.
- Message header still carried `context` (thread id) and `task` (delegated-task id) with no v1 reader, the same dead-flexibility the iteration-3 `state`/`skills` cut removed. Resolved (user): drop both; header is `id`/`from`/`to`/`type`/`ts`. Updated File format, decisions 4/6, channel-core, messaging-skills.
- A2A framing was now vestigial (the only borrowed field left, `id`, is a plain uuid). Resolved: decision 6 rewritten from "borrow A2A field names" to "not the A2A protocol; a local file channel"; Summary and Sources trimmed accordingly.
- Spawn completion semantics were unstated. Resolved (user): fire-and-forget for v1; the spawned agent is addressable, so the spawner polls via `comms-send`/`comms-agents`. Auto report-back is out of scope. New "Not in scope" note in spawn-skill.
- Reconsidered `tmux send-keys` as a message-wake complement to the hooks (user request). Resolved (research + user): reject. No tmux signal separates idle/busy/dialog; a bare `Enter` accepts a permission dialog's default; agent-teams' own send-keys wake failed (#24108), an external-injection request shipped nothing (#27441), and the only state signal (capture-pane) is version-fragile (broke #119 on a point release). On-idle re-arm is also a dead end: `idle_prompt` fires once, ~60s after `Stop`, with no recurring idle event. Kept hooks as the sole delivery; corrected decision 4's stale #29343/#26242 citations and added a Sources bullet.
- Idle-wake window: the `Stop` asyncRewake `timeout` of 3600s (1h) bound exactly the delegate-then-walk-away workflow (a peer message to a session idle past 1h queued silently until the next prompt). Resolved (user): raise to 28800s (8h); each `Stop` resets the poller and the cost is one cheap sleep+stat loop, so the window only binds on a session that gets no further turns. Updated decision 4, delivery-hooks.
