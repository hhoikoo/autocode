# build (instructions)

Capture the command(s) to run locally to verify the working tree builds and tests pass. Used by `pr-fix-ci` and `pr-rebase`.

## Inspect

- Look for `package.json` `scripts` (`build`, `test`, `lint`, `check`, `verify`, `ci`).
- Look for `Makefile` targets (`make test`, `make check`, `make ci`).
- Look for `justfile` recipes.
- Look for `pyproject.toml` test config (`pytest`, `tox`, `nox`, `hatch`) and any `[tool.*]` sections that define a verification entry point.
- Look for `pre-commit` config (`.pre-commit-config.yaml`).
- Look at CI workflows under `.github/workflows/` to identify the canonical verification pipeline; mirror locally what CI runs.

## Ask

- Always present the derived command(s) to the user and get explicit approval before writing the convention file, even when inspection or the default settled the answer.
- Ask whether the repo has separate lint / test / build commands or a single bundled command. If separate, capture each; if bundled, capture the one.
- Ask about timing expectations and known flaky steps so they land in the Notes section.

## Default

No default. If neither inspection nor the user supplies a value, prompt the user before writing.

## Output format

````
# Build and verify

<one-paragraph summary>

## Verify command

```bash
<command>
```

## Notes

<any caveats, timing expectations, common failure modes>
````
