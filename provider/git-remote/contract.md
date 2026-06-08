# Git-remote provider contract

## Purpose

PR lifecycle on the git hosting side: create, view, edit body, link to issue, request review, list and reply to comments, list and resolve threads, plus per-axis identity. Each `provider/git-remote/<provider>/` directory implements the scripts below with identical args and stdout shapes. Skills call them via `provider/run.sh git-remote <feature> [args...]`.

## Cross-provider invariants

- Header: `#!/usr/bin/env bash` then `set -euo pipefail`.
- Required env vars use `:?` guards.
- Stdout: structured JSON via `jq`, plain text only where the script returns a URL or scalar value, or nothing for side-effect-only scripts.
- Stderr: human-readable progress. No ANSI colors.
- Exit codes: `0` success, `1` expected failure (bad input, missing resource), `2` unexpected failure (network, crash).
- JSON: `snake_case` keys, `[]` for empty arrays, `""` for empty strings, never `null` (except where the shape explicitly allows it, e.g. `line: <integer|null>` for PR comments without a line).
- PR identifier is provider-native as a string (GitHub PR number).
- Idempotency: `pr-issue-link.sh` is a no-op when the link is already present. `pr-review-request.sh` tolerates already-requested reviewers. `pr-thread-resolve.sh` tolerates already-resolved threads. `pr-merge.sh` is a no-op on an already-merged PR.

## Shared types

### User

```json
{
  "login": "<string>",
  "id": "<string>"
}
```

### Comment

```json
{
  "id": "<string>",
  "author": "<string>",
  "body": "<string>",
  "path": "<string|empty>",
  "line": <integer|null>,
  "created_at": "<iso8601>",
  "in_reply_to_id": "<string|empty>",
  "kind": "review|issue"
}
```

`kind` is `review` for line-anchored review comments, `issue` for general PR-thread comments. `path` is `""` and `line` is `null` for `issue` comments.

### Thread

```json
{
  "id": "<string>",
  "path": "<string>",
  "body_preview": "<string>"
}
```

`body_preview` is a short preview (first ~80 chars) of the first comment in the thread, for diagnostics.

## Required scripts

| Script | Args | Stdout |
|---|---|---|
| `pr-view.sh` | `[--json <fields>] [<pr>]` | JSON of requested fields |
| `pr-create.sh` | `--title <t> --body-file <p> [--base <b>] [--assignee <a>] [--no-review]` | PR URL on a single line |
| `pr-body-edit.sh` | `<pr> <body-file>` | none |
| `pr-merge.sh` | `<pr> [--admin] [--squash\|--merge\|--rebase]` | none |
| `pr-issue-link.sh` | `<pr> <issue-id>` | none |
| `issue-ref.sh` | `<tracker-key>` | git-remote issue number to close, or empty |
| `pr-review-request.sh` | `<pr> <reviewer>...` | none |
| `pr-comment-list.sh` | `<pr> [--kind review\|issue\|all]` | `Comment[]` JSON |
| `pr-comment-reply.sh` | `<pr> <comment-id> <text>` | none |
| `pr-thread-list.sh` | `<pr>` | `Thread[]` JSON (unresolved only) |
| `pr-thread-resolve.sh` | `<thread-id>...` | none |
| `current-user.sh` | (none) | `User` JSON |

### Notes

- `pr-view.sh` defaults to the PR for the current branch when `<pr>` is omitted. With `--json`, stdout is JSON containing the requested fields.
- `pr-create.sh` `--no-review` opens the PR without the script requesting any reviewers (no `--reviewer` passed to gh). Server-side CODEOWNERS auto-request, when the repo enables it, is outside gh's control and is not suppressed.
- `pr-issue-link.sh` is idempotent. It detects existing `close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved #N` references (case-insensitive, word-boundary anchored) and skips when present. When missing, it appends a canonical `Closes #N` line.
- `issue-ref.sh` bridges the issue-tracker key to a git-remote-native close target. A close reference only auto-closes when it names a git-remote issue number, which differs from the tracker key when the tracker is not the git remote. The GitHub implementation echoes a numeric key as-is (GitHub Issues is the tracker), and for a non-numeric key (e.g. Jira `PROJ-123`) searches for a mirrored GitHub issue, emitting its number or empty. Empty stdout with exit `0` means "nothing on this remote to close" and is not a failure; callers skip the link step.
- `pr-merge.sh` default method is `--squash`; `--admin` bypasses required reviews and checks. Idempotent: an already-merged PR exits `0` as a no-op.
- `pr-review-request.sh` tolerates reviewers already on the PR without error.
- `pr-comment-list.sh` default `--kind` is `all`. The merged list discriminates via `.kind`.
- `pr-comment-reply.sh` posts a threaded reply to a review comment. Falls back to a regular issue-style PR comment if the threaded-reply API rejects the target id.
- `pr-thread-list.sh` returns only unresolved threads. Empty array when all threads are resolved.
- `pr-thread-resolve.sh` tolerates already-resolved threads.

## Adding a new provider

To add a new provider for `git-remote`:

1. Create `provider/git-remote/<provider>/`.
2. Implement every script in the Required table with identical args and identical stdout shape.
3. Optional scripts can be deferred until a caller needs them; a skill that calls an optional script must guard with a capability check or fail loudly.
4. Add the provider name to the supported values for `provider.git-remote` in `autocode/_config/settings-schema.md`.
5. Run `shellcheck` on all new scripts.
