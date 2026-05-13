---
paths:
  - "autocode/**"
  - "**/*.sh"
---
# Code conventions

Language-agnostic principles. See other rules in `.claude/rules/` for per-language conventions.

## Constants and configuration

- No hardcoded values. Use named constants or configuration.
- Environment-varying values come from env vars or config files, not compile-time literals.
- Group related constants in one place.

## Function signatures

- More than 2-3 positional arguments harms readability and invites argument-order bugs. Group related parameters into a config/options struct.
- Call sites should be readable without consulting the signature.

## Code organization

- Separate iteration from per-item logic; no giant multi-purpose loops.
- Extract complex conditions into named booleans or predicate functions.

## Error handling

- Catch and translate errors at package boundaries; never swallow silently.
- Error messages include the operation, the input, and why it failed. Avoid generic "operation failed" / "invalid input".
- Don't return zero values or defaults that mask failure; return an error instead.
- Match existing error-handling patterns before introducing new ones.

## Module boundaries

- Respect existing structure; don't reach into other modules' internals.
- Validate inputs at system boundaries (CLI args, env vars, external API responses). Internal code trusts validated data.
- Distinguish "can't happen" (programmer error, assert/panic OK) from "runtime user error" (return a descriptive error).
- Grep for established patterns before adding utilities. Consistency over personal preference.

## DRY

- Three occurrences = extract. Two = judgment call.
- Pick the simplest abstraction (utility function, shared constant, options struct) that removes the duplication.
