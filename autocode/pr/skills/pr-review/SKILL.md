# PR review

Triage and apply PR review comments.

## Args

`[PR number]` (default: detect from current branch via `provider/run.sh git-remote pr-view --json number,url`).
- `--auto`: run unattended (no `AskUserQuestion`) and end with a structured result block instead of the human report.

## Workflow

1. Resolve PR:
   - If arg provided, use it.
   - Else `provider/run.sh git-remote pr-view --json number,url`; parse `.number`. If `gh pr view` fails (no PR for branch), stop with a message.
2. Fetch comments: `provider/run.sh git-remote pr-comment-list <pr>`.
3. Triage each comment. Score each one 0-100: confidence that the comment identifies a real issue.

   A RECAP-anchored comment is a `kind:"review"` comment whose `path` basename is `RECAP.md`. Resolve it to the concrete source `file:line` before scoring:

   - The RECAP lives in the worktree at the comment's `path` (`recap/<slug>/RECAP.md`); read it locally, falling back to `git show <sha>:<path>` if not on disk. Its `## Key changes` section holds SHA-pinned blob excerpts; map the anchored `line` to the governing SHA-pinned blob URL and parse the source `path` and `#L<n>` out of it (`.../blob/<sha>/<path>#L<start>`). The anchor contract itself is owned by `autocode/design/design-folder.md` (`## recap/<slug>/`); consult it, don't restate it here.
   - Unambiguous single-blob match: use the resolved `file:line` as the comment's effective location and triage it like any other comment below.
   - Ambiguous (anchored outside `## Key changes`, no nearby blob link, or multiple candidate blobs): treat as a discussion-band comment regardless of score (defer under `--auto`, reply-for-clarification interactively). Never guess a location to edit.

   Human reviewers (trust by default):

   | Score | Action |
   |---|---|
   | 50-100 | Fix |
   | 20-49 | Discuss; reply with reasoning, ask for clarification |
   | 0-19 | Resolve; brief explanation |

   Bot or Copilot reviewers (skeptical):

   | Score | Action |
   |---|---|
   | 70-100 | Fix |
   | 30-69 | Optional; fix if trivial, else resolve with explanation |
   | 0-29 | Resolve as spurious |

   Under `--auto`, the discussion band (`20-49` human / `30-69` bot) does not reply asking for clarification: defer it. Count it toward `deferred`, leave the thread for a human, and set `needs_human`. The fix band and the spurious-resolve band are unchanged: high-confidence items still fix-and-resolve, low-confidence items still resolve with an explanation comment.

4. Apply valid fixes:
   - In a unit worktree (`git rev-parse --abbrev-ref HEAD` is not the repo's default branch): hand the fix-band findings to `impl-execute --fix`. Format each surviving finding as a `file:line` plus the required change (for a RECAP-anchored fix, the resolved source location and a change derived from the comment body). Read `@~/.autocode/autocode/impl/skills/impl-execute/SKILL.md` and follow it with `--fix`; it owns the minimal edit and the `git-commit` delegation. Do not inline-edit or commit here.
   - Outside a unit worktree (standalone use on the default branch): apply fixes inline as before. Group related fixes. Delegate commits to the `git-commit` skill. Never `--no-verify`.
5. Reply and resolve threads:
   - `provider/run.sh git-remote pr-comment-reply <pr> <comment-id> "<text>"` for each comment that needs a reply.
   - `provider/run.sh git-remote pr-thread-list <pr>` to list unresolved thread ids.
   - `provider/run.sh git-remote pr-thread-resolve <thread-id>...` for threads to close.
6. Output a triage table to the user: comment id, author, confidence, action taken, status.

## Rules

- Disagreement is direct but respectful. Cite specific code or docs.
- Bots are skeptical by default; Copilot suggestions often miss context.
- Never `--no-verify` on commits.
- Never resolve a thread without an explanation comment.
- Under `--auto`, the no-explanation-before-resolve and never-`--no-verify` rules still hold.
- In a unit worktree, apply fix-band findings only via `impl-execute --fix`; never inline-edit or commit directly there.

## Terminal step (--auto only)

Under `--auto`, emit the structured result as the skill's terminal output, replacing the step-6 triage table:

```
{ pr, applied: int, deferred: int, needs_human: bool, reason }
```

`applied`: comments fixed-and-resolved this run. `deferred`: comments left for a human. `needs_human`: `deferred > 0`. `reason` summarizes the deferred set (empty/omitted when none).

$ARGUMENTS
