#!/usr/bin/env bash
# PreToolUse(Agent|SendMessage): count ai-craftman agent dispatches in the active run and stop at max_agent_calls.
# Also holds engineering agents back until the architecture gates have passed.
# human-liaison and memory-keeper are always allowed so the human can extend the budget.
input=$(cat)
root="${CLAUDE_PROJECT_DIR:-$PWD}"
active="$root/.craftman/active-run"
[ -f "$active" ] || exit 0
# Count new ai-craftman agents and every SendMessage continuation (continuations re-read the agent's whole context).
if ! printf '%s' "$input" | grep -Eq '"tool_name"[[:space:]]*:[[:space:]]*"SendMessage"'; then
  printf '%s' "$input" | grep -Eq '"subagent_type"[[:space:]]*:[[:space:]]*"ai-craftman:' || exit 0
fi
state="$root/.craftman/memory/$(cat "$active")/state.md"
[ -f "$state" ] || exit 0
# No code before the design: engineering agents wait until the architecture gates are done or skipped.
if printf '%s' "$input" | grep -Eq '"subagent_type"[[:space:]]*:[[:space:]]*"ai-craftman:(package-lead|tdd-engineer|test-writer|code-writer|code-optimizer)"'; then
  pending=$(sed -n -E 's/^- \[ \] (gov-architecture|approve-architecture|gov-design)( .*)?$/\1/p' "$state" | tr '\n' ' ')
  if [ -n "$pending" ]; then
    echo "AI-Craftman: blocked. Engineering agents cannot start while the architecture gates are pending: $pending. Finish them with craftman-state first." >&2
    exit 2
  fi
fi
# Parallel dispatches run this hook concurrently: take the state lock so no count is lost (stale lock taken over after ~5s).
lock="$root/.craftman/.lock"; i=0
until mkdir "$lock" 2>/dev/null; do i=$((i+1)); [ "$i" -ge 50 ] && break; sleep 0.1; done
trap 'rmdir "$lock" 2>/dev/null' EXIT
calls=$(sed -n 's/^agent_calls: //p' "$state"); calls=${calls:-0}
max=$(sed -n 's/^max_agent_calls: //p' "$state"); max=${max:-60}
if [ "$calls" -ge "$max" ] && ! printf '%s' "$input" | grep -Eq '"subagent_type"[[:space:]]*:[[:space:]]*"ai-craftman:(human-liaison|memory-keeper)"'; then
  echo "AI-Craftman: agent budget reached ($calls/$max). Ask the human through human-liaison with a question starting [APPROVAL:budget]; approval raises the limit by 50%." >&2
  exit 2
fi
tmp=$(mktemp "$state.XXXXXX")
awk -v n=$((calls+1)) 'index($0,"agent_calls: ")==1 && !d {print "agent_calls: " n; d=1; next} {print}' "$state" > "$tmp" && mv "$tmp" "$state"
exit 0
