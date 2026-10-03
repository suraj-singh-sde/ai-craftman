---
name: root-cause-debugging
description: Find and fix the root cause of a failing test, error or wrong output instead of patching the symptom. Use when a test fails, a review or QA finding needs a fix, or behavior is wrong.
license: MIT
---

# Root-cause debugging

**Reproduce, explain, then fix once where every caller routes through.**

1. **Reproduce.** Run the single failing test or command and read the full error and stack trace. No fix before a reproduction you can rerun.
2. **Explain.** State the cause in one sentence: which line, which input, why. If you can't, add a focused log or assertion and rerun; don't guess.
3. **Find every path.** Grep the callers of the function you will change. Fix it in the shared place, not only on the path the failure names.
4. **Fix minimally.** Change only what the cause needs. No unrelated refactors in the same change.
5. **Prove it.** Rerun the failing test, then the package's fast test command, formatter, linter and type checker.

## Never
- Edit, skip, loosen or delete a test to make it pass. A wrong test is a finding for whoever owns the tests, with the reason.
- Catch and ignore the error, add a retry or a sleep, or special-case the failing input to hide it.
- Rerun a flaky or hanging test in a loop until it passes, or wait on it with an unbounded poll. Run tests with a timeout: a hang or a flake is a failure to explain (shared state, timing, ports, a dead service), not noise.
- Try more than three fixes for the same failure without a new explanation. After three, stop and report what you tried as `status: blocked`.
