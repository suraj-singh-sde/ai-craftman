#!/usr/bin/env bash
set -e
SRC="$(cd "$(dirname "$0")/../../examples/sample-app" && pwd)"
cp -R "$SRC"/. .
git init -q && git add -A && git -c user.email=eval@example.com -c user.name=eval commit -qm init
mkdir -p .craftman/memory/evalrun
echo evalrun > .craftman/active-run
printf 'run: evalrun\nagent_calls: 0\nmax_agent_calls: 60\n' > .craftman/memory/evalrun/state.md
echo "# approvals (evalrun)" > .craftman/memory/evalrun/approvals.md
