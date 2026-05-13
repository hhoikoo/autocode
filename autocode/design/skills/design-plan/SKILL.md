# Design plan

Plan a non-trivial implementation: rough sketch, gap identification, parallel research, then a written plan.

## Args

- Freeform user description (typical), or
- `--temp` (or `--temporary`): write the plan to a temp directory and skip proposal ticket creation.

## Workflow

1. Treat `$ARGUMENTS` as the seed. If empty, ask via `AskUserQuestion` for a one-paragraph description.
2. Rough sketch from conversation context only. No research yet. The point is to surface what the model already thinks so gaps are easier to identify.
3. Gap identification. List every assumption, every unknown library/API, every "I'm guessing X". Decide per gap:
   - dispatch `codebase-researcher` (current repo) in background,
   - dispatch `codebase-researcher` (cross-project) in background,
   - dispatch `web-researcher` in background,
   - ask the user.
   Launch researchers in parallel (single message, multiple Task tool calls). The researchers return verbatim findings; you fold them into the plan.
4. Compose plan once research returns. Sections:
   - `## Executive summary` (one paragraph).
   - `## Architecture impact` (packages, interfaces, new deps; or "no architecture impact" explicitly).
   - `## Implementation steps`. Each step: deliverable, files to create/modify, public interfaces (signatures, struct types), tests that prove it. High-level. No inline code, no pseudo-code. The implementer owns logic.
   - `## Edge cases and error handling`.
   - `## Testing strategy` (categories, fakes, minimum coverage).
   - `## Sources`. Every claim cited. Unsubstantiated claims are discarded.
5. Branch on `--temp`:

   With `--temp`:
   - `dir=$(mktemp -d -t autocode-design); plan_path="$dir/DESIGN.md"`. Write plan to that file.
   - Stop. No proposal issue. No design directory in the repo.
   - Final report: print `<plan_path>`. Suggest `/design-plan-critique <plan_path>`.

   Without `--temp`:
   - Ask the user for `<feature-shortname>` via `AskUserQuestion`. Kebab-case, lowercase, 2-4 words.
   - `repo_root=$(git rev-parse --show-toplevel)`. Create `$repo_root/.autocode/design/unsubmitted-<shortname>/` and write `DESIGN.md` there.
   - Delegate to `issue-create` with type `proposal`. Capture the issue number.
   - Rename `unsubmitted-<shortname>/` to `<ticket-num>-<shortname>/`.
   - Final report: plan path and proposal ticket id. Suggest `/design-plan-critique <ticket-num>` or `/design-plan-push <ticket-num>`.

## Rules

- The proposal issue is for SUBMITTING the proposal itself. The implementation issue is created later (manually or by `impl-start`).
- No phase numbers in commits, code, or PR titles.
- Prefer "I don't know" over a guess. Send the gap to a researcher or the user; do not paper over it.
- Every implementation step lists files; if you cannot list files, the plan is not specific enough.
- Sources section is mandatory. Each claim has a citation (codebase path, URL, or user statement).

$ARGUMENTS
