# PR review

Triage and apply PR review comments.

## Args

`[PR number]` (default: detect from current branch via `provider/run.sh git-remote pr-view --json number,url`).

## Workflow

1. Resolve PR:
   - If arg provided, use it.
   - Else `provider/run.sh git-remote pr-view --json number,url`; parse `.number`. If `gh pr view` fails (no PR for branch), stop with a message.
2. Fetch comments: `provider/run.sh git-remote pr-comment-list <pr>`.
3. Triage each comment. Score each one 0-100: confidence that the comment identifies a real issue.

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

4. Apply valid fixes. Group related fixes. Delegate commits to the `git-commit` skill. Never `--no-verify`.
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

$ARGUMENTS
