#!/usr/bin/env bash
set -e
SRC="$(cd "$(dirname "$0")/../../examples/sample-app" && pwd)"
cp -R "$SRC"/. .
git init -q && git add -A && git -c user.email=eval@example.com -c user.name=eval commit -qm init
