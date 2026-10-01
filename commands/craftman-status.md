---
description: Show AI-Craftman runs, or the state, approvals and next step of one run.
argument-hint: "[run-id]"
allowed-tools: Bash(craftman-state:*), Read
---

Run `craftman-state list` (if not found: `"${CLAUDE_PLUGIN_ROOT}/bin/craftman-state" list`).

- If `$ARGUMENTS` names a run (or a run is active and no argument was given), also run `craftman-state status $ARGUMENTS`.
- If that run has an `escalations.md` with entries, show them.

Report compactly:
- a runs table: id, status, date, requirement
- for the selected run: steps done, skipped and pending; next step; approvals granted; agent calls used against the budget; escalations

Do not start or change anything.
