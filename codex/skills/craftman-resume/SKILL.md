---
name: craftman-resume
description: Resume an interrupted AI-Craftman run from its last completed step.
---

1. If `$ARGUMENTS` is empty, run `craftman-state list` and ask the human which run to resume (`request_user_input` (or `craftman-state ask`, see the Codex notes), max 4 most recent unfinished runs).
2. `craftman-state resume <run-id>` (if not found: `"$PR/bin/craftman-state"`).
3. Read `.craftman/memory/<run-id>/state.md` and the memory file of the last completed step. If the last step was `engineering`-related, check `git status` and `git worktree list` for half-finished packages and `packages_done`.
4. Recreate the task list for the pending steps and continue the loop exactly as defined in `$craftman` (read `$PR/commands/craftman.md`, sections 1–3). Do not re-run completed steps.
