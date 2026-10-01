---
description: Pipeline starts with state init and the requirements planner, and stops at --to.
tags: [smoke]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, TodoWrite, AskUserQuestion, Bash, Write, Edit]
append_system_prompt: "This is an unattended test. When a question would go to the human, choose the option marked (Recommended)."
---

/ai-craftman:craftman --profile lite --to requirements --skip-deploy Short links should expire after a configurable number of days; resolving an expired link raises an error.
