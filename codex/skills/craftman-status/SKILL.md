---
name: craftman-status
description: Show AI-Craftman runs, or the state, approvals and next step of one run.
---

Run `craftman-state list` (if not found: `"$PR/bin/craftman-state" list`).

- If `$ARGUMENTS` names a run (or a run is active and no argument was given), also run `craftman-state status $ARGUMENTS`.
- If that run has an `escalations.md` with entries, show them.

Report compactly:
- a runs table: id, status, date, requirement
- for the selected run: steps done, skipped and pending; next step; approvals granted; agent calls used against the budget; escalations

End with the report path from `craftman-state report <run-id>` (status, HLD/LLD with diagrams, and results in a browser).

Do not start or change anything.
