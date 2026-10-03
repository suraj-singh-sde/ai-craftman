---
name: handoff-check
description: Check your own work the way the reviewer will before handing it off. Use when a work package's tests or code are finished and about to be returned for review.
license: MIT
---

# Hand-off check

**Before you return `GREEN` or `RED_CONFIRMED`, find what the reviewer would find.** A fix round costs two or three agent calls and a second review. This check costs a few minutes. Every item below was a blocking review finding in a real run.

## 1. Prove it
Run these and put the last line of each in your output: the package's tests, the full fast suite, the formatter check, the linter, the type checker.
- Run the linter and formatter again after the last file is created. Results change when a module that was missing appears (import order).
- Anything red: fix it, or return `BLOCKED` with the output. Never report `GREEN` with a failing test, even one you believe is wrong.

## 2. Read your diff once as the reviewer
`git diff` in `workdir`. For each function you changed:
- **Failure.** What happens when each call it makes fails or times out (connection reset, timeout, malformed reply, full disk)? Is the error translated to a domain error? Can a caller with no credentials cause a 500?
- **Cleanup.** If it fails or is cancelled half way, what is left behind: an open transaction, a held lock, a registered subscriber, a temp file? Register inside the `try` whose `finally` removes it.
- **Concurrency.** Is anything awaited, or any I/O done, while a lock is held? Between reading shared state and using it, can another task change it? Can an event arrive between "subscribe" and "read current state" and be lost or delivered twice?
- **Boundaries.** Does the framework catch what you raise here and turn it into something else (middleware, body readers, background tasks)? Check the real response, not the exception.
- **Secrets.** Can a secret or user data reach a log line or an error message (query parameters, connection strings, tokens, headers)?
- **Design.** Does the behavior match the LLD where it names this function (startup jobs, limits, status codes)? A deliberate difference goes under deviations.

## 3. Tests can fail for the right reason
- Each test fails when the behavior is removed. Assert the exact status and error code, never a set (`in (400, 413)`) or a substring of a message.
- The input reaches the server. HTTP clients reject illegal header values and non-ASCII text before sending; use a value the client accepts and the server rejects.
- Helpers keep explicit empty values: `x if x is not None else default`, not `x or default`.
- No test asserts the placeholder behavior of another package's stub.

List what you checked and what you fixed under `## Hand-off check` in your output.
