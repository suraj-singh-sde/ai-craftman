#!/usr/bin/env bash
# SubagentStart|SubagentStop (Codex): keep .craftman/.agents-active, one line per running AI-Craftman agent.
# Codex tool hooks do not say which agent runs a tool, so file-guard reads this file: while a builder, reviewer or
# lead is active, the hidden suite is off limits to every tool call.
input=$(cat)
read -r hookcwd event agent < <(printf '%s' "$input" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("cwd","") or ".", d.get("hook_event_name",""), d.get("agent_type","") or "-")' 2>/dev/null) || exit 0
root="${CLAUDE_PROJECT_DIR:-$(cd "$hookcwd" 2>/dev/null && c=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && { [ "${c%/.git}" != "$c" ] && echo "${c%/.git}" || git rev-parse --show-toplevel 2>/dev/null; } || echo "$hookcwd")}"
[ -f "$root/.craftman/active-run" ] || exit 0
f="$root/.craftman/.agents-active"
case "$event" in
  SubagentStart) echo "$agent" >> "$f";;
  SubagentStop) [ -f "$f" ] || exit 0; tmp=$(mktemp "$f.XXXXXX"); awk -v a="$agent" '!d && $0==a {d=1; next} {print}' "$f" > "$tmp" && mv "$tmp" "$f";;
esac
exit 0
