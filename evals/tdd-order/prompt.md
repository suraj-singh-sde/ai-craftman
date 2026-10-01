---
description: A small lite package is built test-first by tdd-engineer and then reviewed. (git is unusable inside the eval sandbox, so commits are not graded here.)
tags: [slow]
runs: 1
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Agent, TodoWrite, AskUserQuestion, Bash, Write, Edit]
append_system_prompt: "This is an unattended test. When a question would go to the human, choose the option marked (Recommended)."
---

/ai-craftman:craftman --profile lite --to engineering Short links should expire after a configurable number of days; resolving an expired link raises an error.
