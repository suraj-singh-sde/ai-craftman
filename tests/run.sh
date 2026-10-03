#!/usr/bin/env bash
# Self-check for craftman-state and the hook scripts. Usage: tests/run.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PROJECT_DIR="$(mktemp -d)"
export PATH="$HERE/bin:$PATH"
export CRAFTMAN_NOTIFY=off   # no desktop notifications from the self-check
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }
expect() { # expect <name> <want-exit> <script> <json>
  printf '%s' "$4" | $3 >/dev/null 2>&1; got=$?
  [ "$got" = "$2" ] && ok "$1" || bad "$1 (exit $got, want $2)"
}
G="$HERE/scripts/deploy-guard.sh"; F="python3 $HERE/scripts/file-guard.py"
B="$HERE/scripts/agent-budget.sh"; R="python3 $HERE/scripts/record-answers.py"
aj() { printf '{"tool_name":"Agent","tool_input":{"subagent_type":"ai-craftman:%s","prompt":"x"}}' "$1"; }
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
grep -qx 'active-run' "$CLAUDE_PROJECT_DIR/.craftman/.gitignore" && ok "active-run git-ignored" || bad "active-run git-ignored"

# gates need evidence on disk: a passing verdict, a human grant, or a waiver
craftman-state init r3 --max-agent-calls 500 >/dev/null; M3="$CLAUDE_PROJECT_DIR/.craftman/memory/r3"
craftman-state done gov-requirements >/dev/null 2>&1 && bad "gate without result refused" || ok "gate without result refused"
printf -- '---\nverdict: BLOCK\n---\n' > "$M3/03-gov-requirements.md"
craftman-state done gov-requirements >/dev/null 2>&1 && bad "BLOCK gate refused" || ok "BLOCK gate refused"
craftman-state skip gov-requirements "not needed" >/dev/null 2>&1 && bad "gate skip refused" || ok "gate skip refused"
printf -- '---\nverdict: PASS\n---\n' > "$M3/03-gov-requirements-2.md"
craftman-state done gov-requirements >/dev/null 2>&1 && ok "PASS gate accepted" || bad "PASS gate accepted"
printf -- '---\nverdict: BLOCK\n---\n' > "$M3/03-gov-requirements-3.md"
craftman-state done gov-requirements >/dev/null 2>&1 && bad "newer BLOCK overrides older PASS" || ok "newer BLOCK overrides older PASS"
craftman-state done approve-architecture >/dev/null 2>&1 && bad "approval without grant refused" || ok "approval without grant refused"
echo "granted: architecture | t | u" >> "$M3/approvals.md"
craftman-state done approve-architecture >/dev/null 2>&1 && ok "granted approval accepted" || bad "granted approval accepted"
printf -- '---\nverdict: NOT_READY\n---\n' > "$M3/11-qa.md"
craftman-state done qa >/dev/null 2>&1 && bad "NOT_READY qa refused" || ok "NOT_READY qa refused"
echo "granted: waiver | t | u" >> "$M3/approvals.md"; echo "granted: waiver-gov-design | t | u" >> "$M3/approvals.md"
craftman-state done qa >/dev/null 2>&1 && bad "a waiver for another gate does not pass this one" || ok "a waiver for another gate does not pass this one"
echo "granted: waiver-qa | t | u" >> "$M3/approvals.md"
craftman-state done qa >/dev/null 2>&1 && ok "waiver for this gate passes it" || bad "waiver for this gate passes it"

# a design is done only with its diagrams: the human reads the HLD and LLD as mermaid in the report
printf -- '---\nagent: architect\n---\n# HLD\nno diagram\n' > "$M3/06-hld.md"
craftman-state done architecture >/dev/null 2>&1 && bad "HLD without diagram refused" || ok "HLD without diagram refused"
printf -- '---\nagent: architect\n---\n## Components\n```mermaid\nflowchart LR\n  a["API"] --> b["DB"]\n```\n' > "$M3/06-hld.md"
craftman-state done architecture >/dev/null 2>&1 && ok "HLD with diagram accepted" || bad "HLD with diagram accepted"
craftman-state done design >/dev/null 2>&1 && bad "LLD without diagram refused" || ok "LLD without diagram refused"
# diagrams that will not render are refused (the two failures from a real run), valid shapes are not
L="python3 $HERE/scripts/report.py --lint"
printf '```mermaid\nflowchart LR\n  subgraph I1[service instance (1 proc)]\n    A --> B\n  end\n```\n' > "$M3/08a-lld.md"
craftman-state done design 2>&1 | grep -q '08a-lld.md line 3' && ok "unquoted label with parentheses refused" || bad "unquoted label with parentheses refused"
printf '```mermaid\nsequenceDiagram\n  A->>B: limit (cost 1); on error -> allow, metric\n```\n' > "$M3/x.md"; $L "$M3/x.md" >/dev/null && bad "semicolon in sequence message refused" || ok "semicolon in sequence message refused"
printf '```mermaid\nflowchart LR\n  A -->|call (x)| B\n```\n' > "$M3/x.md"; $L "$M3/x.md" >/dev/null && bad "unquoted edge label refused" || ok "unquoted edge label refused"
printf '```mermaid\nflowchart LR\n  subgraph app["service (1 proc)"]\n    A[API routers v1] -->|"POST /v1 (JWT)"| PG[(PostgreSQL 17)]\n    A --> Q{{"queue"}} & S([stadium]) & C((circle))\n  end\n  subgraph two [Plain title]\n    D{ok?} --> E[/in/]\n  end\n```\n```mermaid\nsequenceDiagram\n  A->>B: SUBSCRIBE notify:u:{sub} (queue), then live\n```\n```mermaid\nerDiagram\n  A ||--o{ B : "has"\n```\n' > "$M3/08a-lld.md"
craftman-state done design >/dev/null 2>&1 && ok "valid diagrams accepted" || bad "valid diagrams accepted"; rm -f "$M3/x.md"

# parallel dispatches (one message, several Agent calls) must all be counted
c0=$(sed -n 's/^agent_calls: //p' "$M3/state.md")
for _ in $(seq 20); do aj architect | "$HERE/scripts/agent-budget.sh" & done; wait
[ "$(sed -n 's/^agent_calls: //p' "$M3/state.md")" = $((c0+20)) ] && ok "parallel dispatches all counted" || bad "parallel dispatches all counted"

# auto profile: one command records lite and skips only the pending lite steps
craftman-state init r6 --lead >/dev/null; grep -q '^lead: on' "$CLAUDE_PROJECT_DIR/.craftman/memory/r6/state.md" && grep -q '^lead: off' "$S" && ok "--lead recorded" || bad "--lead recorded"
grep -q '^tools: Agent' "$HERE/agents/package-lead.md" && ok "package lead can dispatch" || bad "package lead can dispatch"
# lite skips gates, so the switch needs evidence: sized small, before design, not against the human's --profile
craftman-state init r7 --profile full >/dev/null; printf -- '---\nsize: small\n---\n' > "$CLAUDE_PROJECT_DIR/.craftman/memory/r7/01-requirements.md"
craftman-state profile lite >/dev/null 2>&1 && bad "lite refused against the human's --profile" || ok "lite refused against the human's --profile"
craftman-state init r4 >/dev/null; S4="$CLAUDE_PROJECT_DIR/.craftman/memory/r4/state.md"
craftman-state done requirements >/dev/null
craftman-state profile lite >/dev/null 2>&1 && bad "lite refused without size: small" || ok "lite refused without size: small"
printf -- '---\nagent: requirements-planner\nsize: small\n---\n' > "$(dirname "$S4")/01-requirements.md"
craftman-state profile lite >/dev/null
grep -q '^profile: lite' "$S4" && grep -q '^- \[-\] gov-design  (skipped: lite profile)' "$S4" && grep -q '^- \[x\] requirements' "$S4" && ok "profile lite switch" || bad "profile lite switch"

# spin-down: services reports only what was started during the run (docker faked, so the check is the same everywhere)
STUB="$(mktemp -d)"; printf '#!/bin/sh\n[ "$1" = ps ] && cat "%s/ps"\n' "$STUB" > "$STUB/docker"; chmod +x "$STUB/docker"
echo "container aaa111 redis:7 old" > "$STUB/ps"
PATH="$STUB:$PATH" craftman-state init r5 >/dev/null
printf 'container aaa111 redis:7 old\ncontainer bbb222 postgres:17 new\n' > "$STUB/ps"
out=$(PATH="$STUB:$PATH" craftman-state services)
echo "$out" | grep -q 'container bbb222 postgres:17' && ! echo "$out" | grep -q aaa111 && ok "services lists only what the run started" || bad "services lists only what the run started"
echo "container aaa111 redis:7 old" > "$STUB/ps"
PATH="$STUB:$PATH" craftman-state services | grep -q 'nothing left running' && ok "services clean after spin-down" || bad "services clean after spin-down"
PATH="$STUB:$PATH" craftman-state finish aborted | grep -q 'services: nothing left running' && ok "finish reports services" || bad "finish reports services"
rm -rf "$STUB"
craftman-state resume r1 >/dev/null
craftman-state escalate "docker is down" >/dev/null && craftman-state notify "x" && grep -q 'docker is down' "$CLAUDE_PROJECT_DIR/.craftman/memory/r1/escalations.md" && ok "escalate logs and notifies" || bad "escalate logs and notifies"
grep -q '"matcher": "AskUserQuestion"' "$HERE/hooks/hooks.json" && [ "$(grep -c 'craftman-state\\" notify' "$HERE/hooks/hooks.json")" = 1 ] && ok "question hook notifies" || bad "question hook notifies"

# deploy guard
expect "push blocked"            2 "$G" "$(bash_json 'git push -u origin craftman/r1')"
expect "terraform apply blocked" 2 "$G" "$(bash_json 'cd infra && terraform apply -auto-approve')"
expect "kubectl delete blocked"  2 "$G" "$(bash_json 'kubectl -n prod delete deploy api')"
expect "npm publish blocked"     2 "$G" "$(bash_json 'npm publish')"
expect "line continuation blocked" 2 "$G" "$(bash_json "$(printf 'git \\\npush origin main')")"
expect "tab-separated push blocked" 2 "$G" "$(bash_json "$(printf 'git\tpush origin main')")"
expect "continued terraform apply blocked" 2 "$G" "$(bash_json "$(printf 'terraform \\\napply -auto-approve')")"
expect "tests allowed"           0 "$G" "$(bash_json 'npm test')"
expect "terraform plan allowed"  0 "$G" "$(bash_json 'terraform plan')"
expect "tamper approvals blocked" 2 "$G" "$(bash_json 'echo granted: deploy >> .craftman/memory/r1/approvals.md')"
expect "craftman-state allowed"  0 "$G" "$(bash_json 'craftman-state done qa')"
expect "cat state allowed"       0 "$G" "$(bash_json 'cat .craftman/memory/r1/state.md')"
expect "read with 2>&1 allowed"  0 "$G" "$(bash_json 'grep -c x .craftman/memory/r1/state.md 2>&1 | head -1')"
expect "prefix tamper blocked"   2 "$G" "$(bash_json 'craftman-state next; echo granted: deploy >> .craftman/memory/r1/approvals.md')"
expect "newline tamper blocked"  2 "$G" "$(bash_json "$(printf 'craftman-state next\necho granted: deploy >> .craftman/memory/r1/approvals.md')")"
expect "plain state note allowed" 0 "$G" "$(bash_json 'craftman-state done qa "READY, see answers.md, python lint clean"')"
# quotes are not interpreted by the guard: a second parser that disagrees with bash is a bypass
expect "mixed quotes cannot hide a write" 2 "$G" "$(bash_json "craftman-state done x 'a \"' ; echo granted: deploy >> .craftman/memory/r1/approvals.md ; echo '\" b'")"
expect "escaped quotes cannot hide a write" 2 "$G" "$(bash_json 'craftman-state done x \" ; echo granted: deploy >> .craftman/memory/r1/approvals.md ; \"')"
expect "code in state note blocked" 2 "$G" "$(bash_json 'craftman-state done qa "$(echo granted: deploy >> .craftman/memory/r1/approvals.md)"')"
expect "write through >&<digits>file blocked" 2 "$G" "$(bash_json 'cd .craftman/memory && echo granted: deploy >&20261003-demo/approvals.md')"
expect "glob on a control file blocked" 2 "$G" "$(bash_json 'echo granted: deploy >> .craftman/memory/r1/approval?.md')"
expect "glob from inside the run folder blocked" 2 "$G" "$(python3 -c 'import json,sys; print(json.dumps({"cwd":sys.argv[1],"tool_input":{"command":"echo granted: deploy >> approv*"}}))' "$CLAUDE_PROJECT_DIR/.craftman/memory/r1")"
expect "globbed test file elsewhere allowed" 0 "$G" "$(bash_json 'python -m pytest tests/test_state*.py > out.txt')"
expect "rm .craftman blocked"    2 "$G" "$(bash_json 'rm -rf .craftman')"
expect "rm worktree allowed"     0 "$G" "$(bash_json 'rm -rf .craftman/worktrees/WP-1')"
expect "rm through worktrees/.. blocked" 2 "$G" "$(bash_json 'rm -rf .craftman/worktrees/../memory')"
expect "mv .craftman blocked"    2 "$G" "$(bash_json 'mv .craftman /tmp/gone')"
expect "find -delete blocked"    2 "$G" "$(bash_json 'find .craftman -name active-run -delete')"
expect "git clean -x blocked"    2 "$G" "$(bash_json 'git clean -fdx')"
expect "git clean -fd allowed"   0 "$G" "$(bash_json 'git clean -fd src')"

# approval recorded from human answer, then push allowed; reject does not grant
Q='[APPROVAL:git-push] Push branch craftman/r1 and open a PR?'
printf '%s' "$(python3 -c 'import json,sys; q=sys.argv[1]; print(json.dumps({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":q}],"answers":{q:"Reject"}}}))' "$Q")" | $R
expect "reject keeps block" 2 "$G" "$(bash_json 'git push')"
printf '%s' "$(python3 -c 'import json,sys; q=sys.argv[1]; print(json.dumps({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":q}],"answers":{q:"Approve"}}}))' "$Q")" | $R
expect "approve allows push" 0 "$G" "$(bash_json 'git push')"
expect "deploy still blocked" 2 "$G" "$(bash_json 'helm upgrade api ./chart')"
expect "force push still blocked" 2 "$G" "$(bash_json 'git push --force origin main')"
expect "branch delete still blocked" 2 "$G" "$(bash_json 'git push origin :main')"
expect "force flag cluster blocked" 2 "$G" "$(bash_json 'git push -fu origin main')"
expect "quoted +refspec blocked" 2 "$G" "$(bash_json 'git push origin "+main"')"
expect "quoted :refspec blocked" 2 "$G" "$(bash_json "git push origin ':main'")"
expect "push --prune blocked" 2 "$G" "$(bash_json 'git push --prune origin')"
expect "plain push with -u allowed" 0 "$G" "$(bash_json 'git push -u origin craftman/r1 --follow-tags')"
# a forced push has its own approval: neither a push grant nor an infrastructure destroy grant covers it
A1="$CLAUDE_PROJECT_DIR/.craftman/memory/r1/approvals.md"; cp "$A1" "$A1.bak"
echo "granted: destroy | t | u" >> "$A1"
expect "destroy grant does not cover force push" 2 "$G" "$(bash_json 'git push --force origin main')"
cp "$A1.bak" "$A1"; echo "granted: force-push | t | u" >> "$A1"
expect "force-push grant allows force push" 0 "$G" "$(bash_json 'git push --force origin main')"
expect "force-push grant does not cover destroy" 2 "$G" "$(bash_json 'terraform destroy -auto-approve')"
mv "$A1.bak" "$A1"
grep -q 'answer: Reject' "$CLAUDE_PROJECT_DIR/.craftman/memory/r1/answers.md" && ok "answers audited" || bad "answers audited"

# file guard
fj() { python3 -c 'import json,sys; d={"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}; d.update({"agent_type":sys.argv[3]} if sys.argv[3] else {}); print(json.dumps(d))' "$@"; }
M="$CLAUDE_PROJECT_DIR/.craftman/memory/r1"
expect "write state.md blocked"   2 "$F" "$(fj "$M/state.md" x '')"
expect "secret in memory blocked" 2 "$F" "$(fj "$M/01-requirements.md" 'key AKIAABCDEFGHIJKLMNOP' '')"
expect "password in memory blocked" 2 "$F" "$(fj "$M/02.md" 'password: hunter2hunter2' '')"
expect "redacted allowed"         0 "$F" "$(fj "$M/02.md" 'password: <redacted>' '')"
expect "clean memory allowed"     0 "$F" "$(fj "$M/01-requirements.md" 'FR-1 users can reset' '')"
expect "schema field not a secret" 0 "$F" "$(fj "$M/08a-lld.md" 'password: SecretStr' '')"
expect "env var name not a secret" 0 "$F" "$(fj "$M/08a-lld.md" 'api_key: configured via FILE_SERVICE_API_KEY' '')"
expect "code-writer test blocked" 2 "$F" "$(fj /repo/tests/test_api.py x ai-craftman:code-writer)"
expect "code-writer .spec blocked" 2 "$F" "$(fj /repo/src/api.spec.ts x ai-craftman:code-optimizer)"
expect "code-writer src allowed"  0 "$F" "$(fj /repo/src/api.py x ai-craftman:code-writer)"
expect "test-writer test allowed" 0 "$F" "$(fj /repo/tests/test_api.py x ai-craftman:test-writer)"

# agent budget (max 2 from init)
expect "engineer blocked before design gates" 2 "$B" "$(aj tdd-engineer)"
expect "package lead blocked before design gates" 2 "$B" "$(aj package-lead)"
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

# every agent that can run commands must stop what it starts
for a in $(grep -l '^tools: .*Bash' "$HERE"/agents/*.md); do
  grep -qF "Stop everything you start." "$a" || bad "services rule in $(basename "$a")"
done
ok "bash agents carry the spin-down rule"

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
V=$(sed -n 's/.*craftmanVersion("\([0-9a-f]*\)").*/\1/p' "$(dirname "$RP")/report-version.js")
[ -n "$V" ] && grep -q "\"version\": \"$V\"" "$RP" && ok "report version file matches page" || bad "report version file matches page"

rm -rf "$CLAUDE_PROJECT_DIR"
[ $fail = 0 ] && echo "ALL PASSED" || { echo "FAILURES"; exit 1; }
