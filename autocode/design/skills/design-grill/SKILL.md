# Design grill

Interview the user about the plan in context until shared understanding. A question the codebase can answer is explored, not asked. Main-session only: `AskUserQuestion` does not exist inside subagents or Workflows.

## Args

One of:
- nothing: grill the plan/ideas already in the current context window. No file on disk required.
- `<path|id|shortname>`: a design folder (same discovery rules as `design-plan-critique`); resolutions also land in that folder's `DESIGN.md`.
- `--seed <json>`: seed questions, shape `[{ question, why }]`. This is `needs_human_reasons` verbatim from `design-critique-workflow.mjs`'s typed result. Combine with a folder arg so answers apply in place.

## Subject

- context window: the plan, decisions, and intent already discussed this session.
- design folder: discovered per `design-plan-critique` (path, or glob `.autocode/design/<id>-*` / `*-<shortname>`). Ambiguous match -> `AskUserQuestion` to disambiguate.
- seed list: `--seed` questions are the starting decision set; still triage and order them like any other.

## Workflow

1. Build the decision tree. Enumerate the open decisions; order them so an upstream decision resolves before the questions it gates. Question-generation bias: apply `design-plan-critique` SKILL step 2 heuristics (read that file at `@~/.autocode/autocode/design/skills/design-plan-critique/SKILL.md`; do not restate them here) plus grill-specific probes: unstated goals, rejected alternatives, "what breaks this", scope boundaries.
2. Triage each question. Answerable from the codebase -> dispatch `codebase-researcher` (parallel where independent) or read the source directly. Judgment call -> the user. Explore before asking; a question the repo can answer is a wasted turn.
3. Interview via `AskUserQuestion`, batched up to 4 questions per call, in dependency order. Each question: header is the decision branch; options led by the recommended answer, its description stating why it is recommended; the remaining options are the real alternatives. Free-text stays available.
4. Record.
   - folder mode: apply in place per `design-plan-critique`'s edit rules (cite `user statement` as the source; append to the `## Critique log`).
   - context mode: maintain a running `Decisions` ledger in the reply.
5. Loop 1-4. Each resolved decision may unlock downstream branches.

## Convergence

- Done: a full pass generates no new questions and nothing is deferred. Emit the shared-understanding block.
- Cap: 5 passes with questions still open -> `AskUserQuestion` whether to continue.
- User says stop at any point -> emit the block with open items marked.

## Output

Shared-understanding block:
- decisions: `question -> answer -> rationale`, one per line.
- open/deferred items.
- files modified (folder mode).

## Rules

- Never runs inside a Workflow or subagent; `AskUserQuestion` is main-session only. This is why the automated seam is the `/design` orchestrator invoking grill on-context (seeded from critique's `needs_human_reasons`), not the critique workflow calling grill.
- Explore before asking. Every question ships a recommendation as its first option. No open-ended "what do you think".
- Read-only outside the resolved design folder.

$ARGUMENTS
