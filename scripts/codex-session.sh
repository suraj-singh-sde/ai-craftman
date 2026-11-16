#!/usr/bin/env bash
# SessionStart (Codex): record where the plugin is installed, so the skills can find bin/craftman-state and the
# templates (${PLUGIN_ROOT} is set for hook commands only, never for the model's shell).
input=$(cat)
[ -n "${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}" ] || exit 0
pr="${PLUGIN_ROOT:-$CLAUDE_PLUGIN_ROOT}"
hookcwd=$(printf '%s' "$input" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)
mkdir -p "$HOME/.codex" 2>/dev/null && printf '%s\n' "$pr" > "$HOME/.codex/ai-craftman.root"
root="$(cd "${hookcwd:-.}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "${hookcwd:-.}")"
[ -d "$root/.craftman" ] && printf '%s\n' "$pr" > "$root/.craftman/.plugin-root"
exit 0
