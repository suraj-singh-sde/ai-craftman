---
description: The acceptance suite is written before the code, packed away, never named in a builder's prompt, run by craftman-state itself before engineering is marked done, and moved into the repository by QA. (git is unusable inside the eval sandbox, so commits are not graded here.)
tags: [slow]
runs: 1
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Agent, TodoWrite, AskUserQuestion, Bash, Write, Edit]
append_system_prompt: "This is an unattended test. When a question would go to the human, choose the option marked (Recommended)."
---

/ai-craftman:craftman --profile lite --to qa Short links should expire after a configurable number of days; resolving an expired link raises an error.
