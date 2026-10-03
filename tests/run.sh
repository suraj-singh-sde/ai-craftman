#!/usr/bin/env bash
# Self-check for craftman-state and the hook scripts. Usage: tests/run.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PROJECT_DIR="$(mktemp -d)"
export PATH="$HERE/bin:$PATH"
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }
expect() { # expect <name> <want-exit> <script> <json>
  printf '%s' "$4" | $3 >/dev/null 2>&1; got=$?
  [ "$got" = "$2" ] && ok "$1" || bad "$1 (exit $got, want $2)"
}
G="$HERE/scripts/deploy-guard.sh"; F="python3 $HERE/scripts/file-guard.py"
B="$HERE/scripts/agent-budget.sh"; R="python3 $HERE/scripts/record-answers.py"
bash_json() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }

# no active run: everything allowed
expect "no run: push allowed" 0 "$G" "$(bash_json 'git push origin main')"

# state machine
craftman-state init r1 --profile lite --skip-deploy --max-agent-calls 2 --requirement "demo" >/dev/null || bad "init"
S="$CLAUDE_PROJECT_DIR/.craftman/memory/r1/state.md"
grep -q '^- \[-\] work-plan  (skipped: lite profile)' "$S" && ok "lite skips work-plan" || bad "lite skips work-plan"
grep -q '^- \[-\] delivery  (skipped: --skip-deploy)' "$S" && ok "skip-deploy" || bad "skip-deploy"
craftman-state next | grep -q 'next: requirements' && ok "next=requirements" || bad "next=requirements"
craftman-state done requirements >/dev/null; craftman-state next | grep -q 'next: clarifications' && ok "done advances" || bad "done advances"
grep -q '^- \[x\] requirements  (done .*, took [0-9]*m[0-9]*s)' "$S" && ok "step duration recorded" || bad "step duration recorded"
grep -q '^- \[-\] security-review  (skipped: lite profile)' "$S" && ok "lite skips security-review" || bad "lite skips security-review"
grep -q '^- \[-\] design  (skipped: lite profile)' "$S" && ok "lite skips LLD" || bad "lite skips LLD"
craftman-state done nope >/dev/null 2>&1 && bad "unknown step rejected" || ok "unknown step rejected"
craftman-state init r1 >/dev/null 2>&1 && bad "duplicate init rejected" || ok "duplicate init rejected"
craftman-state init r2 --from qa --to qa >/dev/null
grep -q '^- \[-\] architecture  (skipped: before --from qa)' "$CLAUDE_PROJECT_DIR/.craftman/memory/r2/state.md" && ok "--from" || bad "--from"
grep -A2 'approve-architecture' "$CLAUDE_PROJECT_DIR/.craftman/memory/r2/state.md" | grep -q 'gov-design' && ok "LLD after HLD approval" || bad "LLD after HLD approval"
grep -q '^- \[-\] delivery  (skipped: after --to qa)' "$CLAUDE_PROJECT_DIR/.craftman/memory/r2/state.md" && ok "--to" || bad "--to"
craftman-state resume r1 >/dev/null

# deploy guard
expect "push blocked"            2 "$G" "$(bash_json 'git push -u origin craftman/r1')"
expect "terraform apply blocked" 2 "$G" "$(bash_json 'cd infra && terraform apply -auto-approve')"
expect "kubectl delete blocked"  2 "$G" "$(bash_json 'kubectl -n prod delete deploy api')"
expect "npm publish blocked"     2 "$G" "$(bash_json 'npm publish')"
expect "tests allowed"           0 "$G" "$(bash_json 'npm test')"
expect "terraform plan allowed"  0 "$G" "$(bash_json 'terraform plan')"
expect "tamper approvals blocked" 2 "$G" "$(bash_json 'echo granted: deploy >> .craftman/memory/r1/approvals.md')"
expect "craftman-state allowed"  0 "$G" "$(bash_json 'craftman-state done qa')"
expect "cat state allowed"       0 "$G" "$(bash_json 'cat .craftman/memory/r1/state.md')"

# approval recorded from human answer, then push allowed; reject does not grant
Q='[APPROVAL:git-push] Push branch craftman/r1 and open a PR?'
printf '%s' "$(python3 -c 'import json,sys; q=sys.argv[1]; print(json.dumps({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":q}],"answers":{q:"Reject"}}}))' "$Q")" | $R
expect "reject keeps block" 2 "$G" "$(bash_json 'git push')"
printf '%s' "$(python3 -c 'import json,sys; q=sys.argv[1]; print(json.dumps({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":q}],"answers":{q:"Approve"}}}))' "$Q")" | $R
expect "approve allows push" 0 "$G" "$(bash_json 'git push')"
expect "deploy still blocked" 2 "$G" "$(bash_json 'helm upgrade api ./chart')"
grep -q 'answer: Reject' "$CLAUDE_PROJECT_DIR/.craftman/memory/r1/answers.md" && ok "answers audited" || bad "answers audited"

# file guard
fj() { python3 -c 'import json,sys; d={"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}; d.update({"agent_type":sys.argv[3]} if sys.argv[3] else {}); print(json.dumps(d))' "$@"; }
M="$CLAUDE_PROJECT_DIR/.craftman/memory/r1"
expect "write state.md blocked"   2 "$F" "$(fj "$M/state.md" x '')"
expect "secret in memory blocked" 2 "$F" "$(fj "$M/01-requirements.md" 'key AKIAABCDEFGHIJKLMNOP' '')"
expect "password in memory blocked" 2 "$F" "$(fj "$M/02.md" 'password: hunter2hunter2' '')"
expect "redacted allowed"         0 "$F" "$(fj "$M/02.md" 'password: <redacted>' '')"
expect "clean memory allowed"     0 "$F" "$(fj "$M/01-requirements.md" 'FR-1 users can reset' '')"
expect "code-writer test blocked" 2 "$F" "$(fj /repo/tests/test_api.py x ai-craftman:code-writer)"
expect "code-writer .spec blocked" 2 "$F" "$(fj /repo/src/api.spec.ts x ai-craftman:code-optimizer)"
expect "code-writer src allowed"  0 "$F" "$(fj /repo/src/api.py x ai-craftman:code-writer)"
expect "test-writer test allowed" 0 "$F" "$(fj /repo/tests/test_api.py x ai-craftman:test-writer)"

# agent budget (max 2 from init)
aj() { printf '{"tool_name":"Agent","tool_input":{"subagent_type":"ai-craftman:%s","prompt":"x"}}' "$1"; }
before=$(sed -n 's/^agent_calls: //p' "$S")
expect "sendmessage allowed" 0 "$B" '{"tool_name":"SendMessage","tool_input":{"to":"abc","message":"x"}}'
[ "$(sed -n 's/^agent_calls: //p' "$S")" = $((before+1)) ] && ok "sendmessage counted" || bad "sendmessage counted"
expect "agent 2 allowed" 0 "$B" "$(aj architect)"
expect "agent 3 blocked" 2 "$B" "$(aj architect)"
expect "liaison allowed over budget" 0 "$B" "$(aj human-liaison)"
expect "other plugins not counted" 0 "$B" '{"tool_input":{"subagent_type":"Explore"}}'
Q2='[APPROVAL:budget] Extend the agent budget?'
printf '%s' "$(python3 -c 'import json,sys; q=sys.argv[1]; print(json.dumps({"tool_input":{"questions":[{"question":q}],"answers":{q:"Approve"}}}))' "$Q2")" | $R
expect "budget extended" 0 "$B" "$(aj architect)"

# every agent carries the shared output contract (except memory-keeper)
for a in "$HERE"/agents/*.md; do
  [ "$(basename "$a")" = memory-keeper.md ] && continue
  grep -qF "the orchestrator writes it. Otherwise return to the orchestrator ONLY" "$a" || bad "contract in $(basename "$a")"
  [ "$(basename "$a")" = research-agent.md ] || grep -qF "[research]" "$a" || bad "research tag in $(basename "$a")"
done
ok "agents carry output contract"

# every skill an agent preloads ships with the plugin
for s in $(sed -n 's/^  - ai-craftman://p' "$HERE"/agents/*.md | sort -u); do
  [ -f "$HERE/skills/$s/SKILL.md" ] || bad "missing skill $s"
done
ok "agent skills exist"

craftman-state finish >/dev/null; [ -f "$CLAUDE_PROJECT_DIR/.craftman/active-run" ] && bad "finish clears active" || ok "finish clears active"
grep -q '^duration: [0-9]*m[0-9]*s$' "$S" && ok "run duration recorded" || bad "run duration recorded"
grep -q '^- r1 | complete |' "$CLAUDE_PROJECT_DIR/.craftman/memory/index.md" && ok "index updated" || bad "index updated"

# report: written on every state change, read-only, no document can break out of its script tag
RP="$CLAUDE_PROJECT_DIR/.craftman/memory/r1/report.html"
[ -f "$RP" ] && grep -q '"step": "requirements"' "$RP" && ok "report refreshed" || bad "report refreshed"
printf -- '---\nagent: architect\nstatus: done\n---\n</script><script>alert(1)</script>\n' > "$CLAUDE_PROJECT_DIR/.craftman/memory/r1/06-hld.md"
craftman-state report r1 >/dev/null
grep -q '"path": "06-hld.md"' "$RP" && ! grep -q '</script><script>alert' "$RP" && ok "report embeds design safely" || bad "report embeds design safely"

rm -rf "$CLAUDE_PROJECT_DIR"
[ $fail = 0 ] && echo "ALL PASSED" || { echo "FAILURES"; exit 1; }
