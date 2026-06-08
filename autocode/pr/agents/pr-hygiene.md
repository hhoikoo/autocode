# PR hygiene

Read `~/.autocode/autocode/_config/output-styles/concise.md` and follow it for all output.

## Invocation

Background-only. Spawned by `pr-create` after the PR opens. Not user-callable.

## Inputs

- Commit SHA(s) just pushed.
- Files changed by those commits.

Use these to scope the analysis. Read the full branch diff only if the PR description needs a rewrite.

## Workflow

1. Run `git show <sha> --stat` for each SHA the caller provided. This is the scoped view.
2. Check that a PR exists:
   ```bash
   provider/run.sh git-remote pr-view --json number,body
   ```
   If none, output "No PR exists" and stop.
3. Resolve the base branch dynamically:
   ```bash
   gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
   ```
4. **Design-PR check.** Apply the detection rule in `@~/.autocode/autocode/design/design-pr-body.md`: `git diff <base>...HEAD --name-only` is non-empty and every path is under `.autocode/design/`. If so, this is a design PR:
   - Documentation assessment is fixed: output **No docs needed** (the design doc is the doc).
   - PR description: recompose the body via the recipe in `@~/.autocode/autocode/design/design-pr-body.md` (it self-discovers `<folder>` from the diff), then apply it with `provider/run.sh git-remote pr-body-edit <pr-number> <path>`. Do not run the diff-based draft in step 6; a design body is never a code-diff summary. Include the applied body in the output and stop.
   - Otherwise continue to step 5.
5. **Documentation assessment** from the scoped diff. Consider:
   - New public APIs, CLI flags, config options.
   - Behavior changes to existing features.
   - Architectural shifts that affect contributors.
   - New dependencies or setup steps.
   - New or changed hooks, skills, agents.

   Internal refactors, test additions, and pure bug fixes rarely warrant doc updates. Output one of:
   - **No docs needed** with a 1-2 sentence rationale.
   - **Docs update recommended**: for each file, name the section and describe the specific change. Do not apply edits; the caller approves.
6. **PR description update**. Compare the current body against the scoped diff.
   - If current, output "PR description is current".
   - If stale: run `git diff <base>...HEAD` for the full branch diff. Draft a replacement body that reads as if the PR were freshly opened (no changelog, no patch notes). Write it to `$(mktemp -d -t autocode-pr-hygiene)/body.md`. Apply via:
     ```bash
     provider/run.sh git-remote pr-body-edit <pr-number> <path>
     ```
     Include the applied body in the output.

## Output format

```
## Documentation Assessment

<assessment>

## PR Description

<status or applied body>
```

## Rules

- Read-only on source files. The only write is the PR body via the provider script.
- Respect conventions in `.claude/rules/`.
- Scope first. Reach for the full diff only when rewriting the description.
