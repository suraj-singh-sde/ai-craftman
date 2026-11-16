#!/usr/bin/env bash
# PreToolUse(Agent|SendMessage): count ai-craftman agent dispatches in the active run and stop at max_agent_calls.
# Also holds engineering agents back until the architecture gates have passed.
# human-liaison and memory-keeper are always allowed so the human can extend the budget.
input=$(cat)
hookcwd=$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)
root="${CLAUDE_PROJECT_DIR:-$(cd "${hookcwd:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "${hookcwd:-$PWD}")}"
active="$root/.craftman/active-run"
[ -f "$active" ] || exit 0
# Count new ai-craftman agents and every continuation (a continuation re-reads the agent's whole context).
# Claude Code: Agent with subagent_type "ai-craftman:<name>", SendMessage. Codex: spawn_agent (also matched as Agent)
# with an agent field naming "craftman-<name>", send_input / resume_agent.
if ! printf '%s' "$input" | grep -Eq '"tool_name"[[:space:]]*:[[:space:]]*"(SendMessage|send_input|resume_agent)"'; then
  printf '%s' "$input" | grep -Eq '"(subagent_type|agent_type|agent|role|name|profile)"[[:space:]]*:[[:space:]]*"(ai-craftman:|craftman-)' || exit 0
fi
state="$root/.craftman/memory/$(cat "$active")/state.md"
[ -f "$state" ] || exit 0
# No code (and no acceptance suite) before the design: these agents wait until the architecture gates are done or skipped.
if printf '%s' "$input" | grep -Eq '"(subagent_type|agent_type|agent|role|name|profile)"[[:space:]]*:[[:space:]]*"(ai-craftman:|craftman-)(package-lead|tdd-engineer|test-writer|code-writer|code-optimizer|acceptance-writer|e2e-verifier)"'; then
  pending=$(sed -n -E 's/^- \[ \] (gov-architecture|approve-architecture|gov-design)( .*)?$/\1/p' "$state" | tr '\n' ' ')
  if [ -n "$pending" ]; then
    echo "AI-Craftman: blocked. Engineering agents cannot start while the architecture gates are pending: $pending. Finish them with craftman-state first." >&2
    exit 2
  fi
fi
# Parallel dispatches run this hook concurrently: take the state lock so no count is lost. The lock is a file the shell
# itself creates with O_EXCL (noclobber), not a directory from mkdir(1): on a runner with uutils coreutils (Ubuntu's new
# default) mkdir returned success to two hooks for the same directory, both read the same count, and one was lost.
# A lock is taken over only when it is itself older than 5s (a crashed holder), never because this waiter has queued
# for 5s: forty dispatches on a slow runner queue for longer, and a waiter that gave up would lose its count.
lock="$root/.craftman/.lock"; i=0
[ ! -d "$lock" ] || rmdir "$lock" 2>/dev/null   # a directory lock left by a version before 0.8.0
until ( set -C; : > "$lock" ) 2>/dev/null; do
  age=$(( $(date +%s) - $(date -r "$lock" +%s 2>/dev/null || date +%s) ))   # date -r: file mtime on BSD and GNU alike
  [ "$age" -lt 5 ] || { rm -f "$lock"; continue; }
  i=$((i+1)); [ "$i" -ge 600 ] && break; sleep 0.1
done
trap 'rm -f "$lock"' EXIT
calls=$(sed -n 's/^agent_calls: //p' "$state"); calls=${calls:-0}
max=$(sed -n 's/^max_agent_calls: //p' "$state"); max=${max:-60}
if [ "$calls" -ge "$max" ] && ! printf '%s' "$input" | grep -Eq '"(subagent_type|agent_type|agent|role|name|profile)"[[:space:]]*:[[:space:]]*"(ai-craftman:|craftman-)(human-liaison|memory-keeper)"'; then
  echo "AI-Craftman: agent budget reached ($calls/$max). Ask the human through human-liaison with a question starting [APPROVAL:budget]; approval raises the limit by 50%." >&2
  exit 2
fi
tmp=$(mktemp "$state.XXXXXX")
awk -v n=$((calls+1)) 'index($0,"agent_calls: ")==1 && !d {print "agent_calls: " n; d=1; next} {print}' "$state" > "$tmp" && mv "$tmp" "$state"
exit 0
