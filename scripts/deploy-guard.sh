#!/usr/bin/env bash
# PreToolUse(Bash): during an active AI-Craftman run, block deploy/destroy/push/publish/tracker
# commands unless the human granted the matching [APPROVAL:<category>], and block tampering
# with run control files. Pure bash + grep so it works without python and fails closed.
# ponytail: pattern match on the command text, not a shell parser. It stops an agent that skips an approval,
# not one that hides a command on purpose (variables, eval, a script file). Soundness would need the harness's
# own permission prompt for these commands instead of a grants file.
input=$(cat)
# Exact command (and the shell's directory) via python; without python, match against the whole payload
# (over-blocks, never under-blocks).
out=$(printf '%s' "$input" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("cwd","")); print(d.get("agent_type","")); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null) \
  && { hookcwd=$(printf '%s' "$out" | sed -n 1p); agent=$(printf '%s' "$out" | sed -n 2p); cmd=$(printf '%s' "$out" | tail -n +3); decoded=1; } || { hookcwd=""; agent=""; cmd="$input"; decoded=0; }
# The project root: CLAUDE_PROJECT_DIR (Claude Code), else the repository that holds the hook's cwd (Codex).
root="${CLAUDE_PROJECT_DIR:-$(cd "${hookcwd:-$PWD}" 2>/dev/null && c=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && { [ "${c%/.git}" != "$c" ] && echo "${c%/.git}" || git rev-parse --show-toplevel 2>/dev/null; } || echo "${hookcwd:-$PWD}")}"
active="$root/.craftman/active-run"
[ -f "$active" ] || exit 0
run=$(cat "$active")
approvals="$root/.craftman/memory/$run/approvals.md"
[ -n "$cmd" ] || { cmd="$input"; decoded=0; }
raw=$cmd
# Match what bash will run, not how it was typed. $cmd is only matched, never executed.
# - Only when the text is still JSON (no python): undo its escapes (escaped continuation, \t, \n). On a decoded
#   command a literal \n is two ordinary characters inside an argument; turning it into a line break would cut
#   "rm -rf 'x\n' .craftman" in two and hide the target.
# - Join backslash-newline continuations (an odd number of trailing backslashes; an even number is an escaped
#   backslash and the line ends there). Tabs become spaces.
# - Quotes and backslashes are dropped: bash joins git 'push', git pu\sh and approv''als.md into the plain word.
[ "$decoded" = 1 ] || cmd=$(printf '%s' "$cmd" | sed 's/\\\\\\n//g; s/\\t/ /g' | awk '{ gsub(/\\n/, "\n"); print }')
cmd=$(printf '%s' "$cmd" \
  | awk '{ if (match($0, /\\+$/) && RLENGTH % 2 == 1) printf "%s", substr($0, 1, length($0) - 1); else print }' \
  | tr '\t' ' ' | tr -d "'\"\\\\")

block() { echo "AI-Craftman: blocked. $1" >&2; exit 2; }

# Control files are written only by craftman-state and the hooks (verify/*.md hold the test runs the engineering gate reads).
# One line, with harmless redirects (2>&1, >/dev/null) removed, so reads are not mistaken for writes.
# Only a complete redirect is removed: ">&2" followed by more text is a file name (">&2026-run/approvals.md" writes it).
bare=$(printf '%s' "$cmd" | tr '\n' ';' | sed -E 's/[0-9]?>&[0-9-]([[:space:];|&)]|$)/ \1/g; s#[0-9&]?>[[:space:]]*/dev/null([[:space:];|&)]|$)# \1#g')
# The only exemption is a lone craftman-state call, decided on the command exactly as typed: a single line made of
# harmless characters only (an allowlist: no newline ; & | ` $ < > # or backslash, so nothing can follow the call).
lone=0
case "$raw" in *"
"*) ;; *) printf '%s' "$raw" | grep -Eq "^[[:space:]]*craftman-state [A-Za-z0-9 _.,:=/@%+()!?*~'\"{}-]*\$" && lone=1;; esac
# A control file is named in full, case-insensitively (a Mac's file system is). Where the command or the shell's
# directory is inside .craftman (worktrees aside), no write may use a glob at all (tee 0* from the run folder would
# overwrite the evidence files); elsewhere test_state*.py is just a test file.
names='(state|approvals|answers|pending)\.md|active-run|\.agents-active|verify/[^ ;|&]+'
writes='(>|tee |sed -i|perl -i|python|node |ruby |cp |mv |rm |ln |truncate|dd )'
ctx="$hookcwd $bare"   # a worktree path does not count, unless ".." can lead back out of it
printf '%s' "$ctx" | grep -q '\.\.' || ctx=$(printf '%s' "$ctx" | sed 's#\.craftman/worktrees##g')
if [ "$lone" = 0 ] && printf '%s' "$bare" | grep -Eqi "$names" && printf '%s' "$bare" | grep -Eq "$writes"; then
  block "Run control files (state.md, approvals.md, answers.md, active-run, verify/) may only change through craftman-state or the human's answers."
fi
if [ "$lone" = 0 ] && printf '%s' "$ctx" | grep -q '\.craftman' && printf '%s' "$bare" | grep -Eq "$writes" && printf '%s' "$bare" | grep -q '[*?[{]'; then
  block "A command that can write inside .craftman/ must name its files: no globs there (the run's control and evidence files sit next to each other)."
fi
# Gate evidence (the headers and verdicts the state machine reads) has one writer each. Another agent's command that can
# write it is refused; the orchestrator (no agent type) may write a refused agent's output. The full name,
# case-insensitively; a glob is already refused above.
if [ -n "$agent" ] && [ "$lone" = 0 ] && printf '%s' "$bare" | grep -Eq "$writes"; then
  for pair in 00-triage:triage 01-requirements:requirements-planner 04-context:enterprise-context 09a-hidden-tests:acceptance-writer 11a-e2e:e2e-verifier; do
    file=${pair%%:*}; owner=${pair#*:}
    case "$agent" in *"$owner") continue;; esac
    printf '%s' "$bare" | grep -Eqi "$file(-[0-9]+)?\.md" && block "$file.md is gate evidence written by $owner; $agent may read it, not change it."
  done
fi
# Deleting or moving .craftman would erase the audit trail and switch these guards off (so would git clean -x:
# active-run is git-ignored). One worktree folder may be removed, but never through a path with "..".
tgt=$bare
printf '%s' "$bare" | grep -q '\.\.' || tgt=$(printf '%s' "$bare" | sed -E 's#\.craftman/worktrees/[A-Za-z0-9_.-]+##g')
if printf '%s' "$tgt" | grep -Eq '(^|[;&|[:space:]])(rm|rmdir|unlink|mv|shred)[[:space:]][^;&|]*\.craftman|find[^;&|]*\.craftman[^;&|]*-(delete|exec)|git[^;&|]* clean[^;&|]* -[A-Za-z]*[xX]'; then
  block "Run memory under .craftman/ may not be deleted or moved during a run. Finish the run first (craftman-state finish)."
fi

# A command may touch several categories (git push --force; terraform destroy): each one needs its own grant.
# A forced push needs force-push in addition to git-push, so neither a push grant nor an infrastructure destroy
# grant covers it:
# long flags and git's abbreviations of them (--del, --mir), short flag clusters (-fu), +ref / :ref refspecs.
force='git[^|;&]* push[^|;&]*([[:space:]]--(for[a-z-]*|de[a-z]*|mi[a-z]*|pru[a-z]*)|[[:space:]]-[A-Za-z0-9]*[fd][A-Za-z0-9]*([[:space:]]|$)|[[:space:]][+:][^[:space:]])'
need=""
has() { printf '%s' "$cmd" | grep -Eq "$1"; }
# "git stash push" is caught too, on purpose: telling it apart from "git -C stash push" (a real push from a
# folder named stash) needs git's option grammar. Over-block; plain "git stash" does the same and passes.
has 'git[^|;&]* push|gh pr create' && need="$need git-push"
has "$force" && need="$need force-push"   # on top of git-push, never instead of it
has '(terraform|tofu|pulumi)[^|;&]* destroy|kubectl[^|;&]* delete|helm[^|;&]* uninstall|aws cloudformation delete-stack' && need="$need destroy"
has '(terraform|tofu)[^|;&]* apply|pulumi[^|;&]* up|kubectl[^|;&]* (apply|create|replace|patch|rollout|scale|set) |helm[^|;&]* (install|upgrade|rollback)|(cdk|sam|serverless|sls|eb|fly|firebase|wrangler)[^|;&]* (deploy|publish)|aws cloudformation (deploy|create-stack|update-stack)|aws ecs update-service|aws lambda update-function|gcloud[^|;&]* deploy|az[^|;&]* deployment|az webapp deploy|vercel[^|;&]*--prod|netlify deploy[^|;&]*--prod|ansible-playbook|docker[^|;&]* push|git push heroku' && need="$need deploy"
has '(npm|yarn|pnpm) publish|twine upload|cargo publish|gem push|mvn[^|;&]* deploy|gradle[^|;&]* publish|gh release create' && need="$need publish"
has 'gh issue create|jira[^|;&]* create' && need="$need tracker"

for category in $need; do
  if [ -f "$approvals" ] && grep -Eq "^granted: $category( |\$)" "$approvals"; then continue; fi
  block "'$category' command needs human approval for run $run. Ask through human-liaison with a question starting [APPROVAL:$category]; the answer is recorded automatically. Command: ${cmd:0:200}"
done
exit 0
