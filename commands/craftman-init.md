---
description: Set up AI-Craftman in this project (.craftman/ with governance policy, enterprise context and sources templates).
---

# AI-Craftman init

Set up `.craftman/` in the current project. Never overwrite a file that already exists; report it as kept.

1. Create:
   - `.craftman/governance.md` from `${CLAUDE_PLUGIN_ROOT}/templates/governance.md`
   - `.craftman/context/enterprise.md` from `${CLAUDE_PLUGIN_ROOT}/templates/enterprise.md`
   - `.craftman/context/sources.md` from `${CLAUDE_PLUGIN_ROOT}/templates/sources.md`
   - `.craftman/context/flows/` (empty)
   - `.craftman/memory/`
   - `.craftman/.gitignore` from `${CLAUDE_PLUGIN_ROOT}/templates/craftman.gitignore`
   Copy with `cp -n` so existing files are kept.
2. Check the tools the hooks and pipeline rely on, and report each one as present or missing:
   - `python3`: without it, human answers are not recorded, so approvals can never be granted.
   - `git`
   - `gh`: used for PRs and issues.
3. Ask the human (AskUserQuestion) for the autonomy level to write into `.craftman/governance.md`:
   - `medium` (recommended): risk-based approvals
   - `low`: approve every gate
   - `high`: approve only deploy, push, destroy and waivers
4. Tell the human which files to edit next:
   - `governance.md`: their policies
   - `context/sources.md`: other repos, docs, Jira/Confluence spaces
   - Commit `.craftman/` except `worktrees/`. Per-run memory is optional to commit.
