#!/usr/bin/env bash
# PreToolUse(Bash): during an active AI-Craftman run, block deploy/destroy/push/publish/tracker
# commands unless the human granted the matching [APPROVAL:<category>], and block tampering
# with run control files. Pure bash + grep so it works without python and fails closed.
# ponytail: pattern match on raw JSON, not a shell parser; raises the bar, not a sandbox.
input=$(cat)
root="${CLAUDE_PROJECT_DIR:-$PWD}"
active="$root/.craftman/active-run"
[ -f "$active" ] || exit 0
run=$(cat "$active")
approvals="$root/.craftman/memory/$run/approvals.md"

# Exact command via python; without python, match against the whole payload (over-blocks, never under-blocks).
cmd=$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null) || cmd="$input"
[ -n "$cmd" ] || cmd="$input"

block() { echo "AI-Craftman: blocked. $1" >&2; exit 2; }

# Control files are written only by craftman-state and the hooks.
# One line, with harmless redirects (2>&1, >/dev/null) removed, so reads are not mistaken for writes.
bare=$(printf '%s' "$cmd" | tr '\n' ';' | sed -E 's/[0-9]?>&[0-9-]//g; s#[0-9&]?>[[:space:]]*/dev/null##g')
# The only exemption is a lone craftman-state call: nothing chained, piped or redirected after it.
# Its quoted note may say anything, unless the quotes can run code ($ or a backtick inside double quotes).
if printf '%s' "$bare" | grep -Eq '(state|approvals|answers)\.md|active-run' \
   && printf '%s' "$bare" | grep -Eq '(>|tee |sed -i|perl -i|python|node |ruby |cp |mv |rm |truncate|dd )' \
   && ! printf '%s' "$bare" | sed -E 's/"[^"$`]*"//g; s/'"'[^']*'"'//g' | grep -Eq '^[[:space:]]*craftman-state [^;&|`$>]*$'; then
  block "Run control files (state.md, approvals.md, answers.md, active-run) may only change through craftman-state or the human's answers."
fi
# Deleting .craftman (worktrees aside) would erase the audit trail and switch these guards off.
if printf '%s' "$bare" | sed 's#\.craftman/worktrees##g' | grep -Eq '(^|[;&|[:space:]])rm [^;&|]*\.craftman'; then
  block "Run memory under .craftman/ may not be deleted during a run. Finish the run first (craftman-state finish)."
fi

category=""
# A git-push grant covers a plain push only: forced pushes and remote branch deletes count as destroy.
if printf '%s' "$cmd" | grep -Eq '(terraform|tofu|pulumi)[^|;&]* destroy|kubectl[^|;&]* delete|helm[^|;&]* uninstall|aws cloudformation delete-stack|git[^|;&]* push[^|;&]*( --force| -f( |$)| --delete| -d( |$)| --mirror| \+[A-Za-z]| :[A-Za-z])'; then category=destroy
elif printf '%s' "$cmd" | grep -Eq '(terraform|tofu)[^|;&]* apply|pulumi[^|;&]* up|kubectl[^|;&]* (apply|create|replace|patch|rollout|scale|set) |helm[^|;&]* (install|upgrade|rollback)|(cdk|sam|serverless|sls|eb|fly|firebase|wrangler)[^|;&]* (deploy|publish)|aws cloudformation (deploy|create-stack|update-stack)|aws ecs update-service|aws lambda update-function|gcloud[^|;&]* deploy|az[^|;&]* deployment|az webapp deploy|vercel[^|;&]*--prod|netlify deploy[^|;&]*--prod|ansible-playbook|docker[^|;&]* push|git push heroku'; then category=deploy
elif printf '%s' "$cmd" | grep -Eq '(npm|yarn|pnpm) publish|twine upload|cargo publish|gem push|mvn[^|;&]* deploy|gradle[^|;&]* publish|gh release create'; then category=publish
elif printf '%s' "$cmd" | grep -Eq 'git[^|;&]* push|gh pr create'; then category=git-push
elif printf '%s' "$cmd" | grep -Eq 'gh issue create|jira[^|;&]* create'; then category=tracker
fi
[ -z "$category" ] && exit 0

if [ -f "$approvals" ] && grep -Eq "^granted: $category( |$)" "$approvals"; then exit 0; fi
block "'$category' command needs human approval for run $run. Ask through human-liaison with a question starting [APPROVAL:$category]; the answer is recorded automatically. Command: ${cmd:0:200}"
