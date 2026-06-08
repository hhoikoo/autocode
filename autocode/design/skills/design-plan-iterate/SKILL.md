# Design plan iterate

Triage and apply review comments on a design-doc PR.

## Args

`[PR number]` (default: detect from current branch via `provider/run.sh git-remote pr-view --json number,url`).

`--auto`: run unattended (no interactive back-and-forth) and end with a structured result block instead of the human triage table. The triage rubric is unchanged; the discussion band defers rather than asking for clarification. See `### --auto behavior` and `### Structured result` under `## Workflow`.

## Differences vs pr-review

- Triage rubric weighs design clarity, scope alignment, and assumption auditing over code correctness.
- Disagreement responses cite specific plan sections (architecture, design decisions, edge cases, testing strategy) or specific units.
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

4. Apply valid edits to `DESIGN.md` or the relevant `units/*.md`. Group related edits. Triage and decisions stay in the main session; the apply may fan out, by judgement: when several units need edits, dispatch one generic Task subagent per affected unit in parallel, each handed the exact changes to write into its `units/<slug>.md`. Keep `DESIGN.md` edits in the main session (shared file, serial); edit a single unit inline rather than spawning one subagent.
5. Delegate commit to `git-commit`.
6. Reply and resolve threads:
   - `provider/run.sh git-remote pr-comment-reply <pr> <comment-id> "<text>"` for each thread that needs a reply.
   - `provider/run.sh git-remote pr-thread-list <pr>` for unresolved ids.
   - `provider/run.sh git-remote pr-thread-resolve <thread-id>...` to close them.
7. Output: without `--auto`, a triage table to the user (comment id, author, confidence, action, status); with `--auto`, the structured result block from `### Structured result` instead of the table.

### --auto behavior

Under `--auto`, the triage rubric (step 3 score tables) is unchanged; only each band's terminal action changes:

- High-confidence band (human 50-100 / bot 70-100): apply the edit, reply, and resolve the thread exactly as the interactive path. The comment id counts toward `applied`.
- Discussion band (human 20-49 / bot 30-69): do not start an interactive clarification (the "Discuss; cite specific plan section and ask for clarification" action requires a round-trip a headless caller cannot drive). Defer instead: leave the thread open for a human, count the comment id toward `skipped`, and set `needs_human: true` with one reason in `needs_human_reasons`. For the bot 30-69 row ("Optional; update if trivial, else resolve"), apply the trivial update when unambiguous (count as `applied`), else defer to `skipped` with a `needs_human` reason.
- Spurious band (human 0-19 / bot 0-29): resolve as spurious with an explanation comment, exactly as the interactive path. The id counts toward `skipped` (resolved, not deferred); does not set `needs_human`.

All `## Rules` invariants hold under `--auto`: edits land only in `DESIGN.md` / `units/*.md`, no build verify step, commit via `git-commit`, never `--no-verify`, never resolve a thread without an explanation comment.

### Structured result

Terminal output when `--auto` is active. Replaces the step-7 prose table. Scalar and list fields only, in a fenced block, no prose:

```
{
  applied: [<comment-id>, ...],
  skipped: [<comment-id>, ...],
  replied: <int>,
  threads_resolved: <int>,
  needs_human: <bool>,
  needs_human_reasons: [<string>, ...]
}
```

Field semantics:
- `applied`: comment ids whose edits were applied to `DESIGN.md` / `units/*.md` this run.
- `skipped`: comment ids not applied (spurious-resolved or deferred for a human).
- `replied`: count of threads that received a reply via `pr-comment-reply`.
- `threads_resolved`: count of threads closed via `pr-thread-resolve`.
- `needs_human`: true when any discussion-band comment was deferred.
- `needs_human_reasons`: one short reason per deferred comment, summarizing what the human must decide.

## Rules

- Disagreement is direct but respectful. Cite specific plan sections or units.
- Edits land in the design folder only (`DESIGN.md` or `units/*.md`). Never edit source code from this skill.
- No verify step (the PR is markdown).
- Never `--no-verify` on commits; delegated `git-commit` handles hook failures.
- Never resolve a thread without an explanation comment.

$ARGUMENTS
