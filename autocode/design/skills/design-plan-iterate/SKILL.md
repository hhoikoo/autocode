# Design plan iterate

Triage and apply review comments on a design-doc PR.

## Args

`[PR number]` (default: detect from current branch via `provider/run.sh git-remote pr-view --json number,url`).

## Differences vs pr-review

- Triage rubric weighs design clarity, scope alignment, and assumption auditing over code correctness.
- Disagreement responses cite specific plan sections (architecture impact, edge cases, testing strategy) or specific units.
- Edits land in the design folder (`DESIGN.md` or `units/*.md`), not in source code.
- No build verify step (the PR contains markdown, not code).
- Commits go through `git-commit`.

## Workflow

1. Resolve PR (arg or `provider/run.sh git-remote pr-view --json number`).
2. Fetch comments: `provider/run.sh git-remote pr-comment-list <pr>`.
3. Triage each comment. Score each one 0-100: confidence that the comment identifies a real issue in the PLAN (not the code).

   Human reviewers (trust by default):

   | Score | Action |
   |---|---|
   | 50-100 | Update plan |
   | 20-49 | Discuss; cite specific plan section and ask for clarification |
   | 0-19 | Resolve; brief explanation |

   Bot or Copilot reviewers (skeptical):

   | Score | Action |
   |---|---|
   | 70-100 | Update plan |
   | 30-69 | Optional; update if trivial, else resolve with explanation |
   | 0-29 | Resolve as spurious |

4. Apply valid edits to `DESIGN.md` or the relevant `units/*.md`. Group related edits.
5. Delegate commit to `git-commit`.
6. Reply and resolve threads:
   - `provider/run.sh git-remote pr-comment-reply <pr> <comment-id> "<text>"` for each thread that needs a reply.
   - `provider/run.sh git-remote pr-thread-list <pr>` for unresolved ids.
   - `provider/run.sh git-remote pr-thread-resolve <thread-id>...` to close them.
7. Output a triage table to the user: comment id, author, confidence, action, status.

## Rules

- Disagreement is direct but respectful. Cite specific plan sections or units.
- Edits land in the design folder only (`DESIGN.md` or `units/*.md`). Never edit source code from this skill.
- No verify step (the PR is markdown).
- Never `--no-verify` on commits; delegated `git-commit` handles hook failures.
- Never resolve a thread without an explanation comment.

$ARGUMENTS
