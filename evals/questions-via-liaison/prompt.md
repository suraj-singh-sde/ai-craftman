---
description: Ambiguous requirement produces questions authored by human-liaison, not by the orchestrator.
tags: [smoke]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, TodoWrite, AskUserQuestion, Bash, Write, Edit]
append_system_prompt: "This is an unattended test. When a question would go to the human, choose the option marked (Recommended)."
---

/ai-craftman:craftman --to requirements Make the shortener enterprise ready.
