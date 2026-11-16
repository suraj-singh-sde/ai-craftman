---
description: An app with an entry point is started and driven end to end by the e2e-verifier before QA (local mode, no Docker). The eval sandbox refuses local port binding, so under `claude plugin eval` this case stops at engineering with an escalation; run it headless instead (README, Development).
tags: [slow, no-sandbox]
runs: 1
max_turns: 200
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Agent, TodoWrite, AskUserQuestion, Bash, Write, Edit]
append_system_prompt: "This is an unattended test. When a question would go to the human, choose the option marked (Recommended)."
---

/ai-craftman:craftman --profile lite --to qa Short links should expire after a configurable number of days; GET /r/<code> for an expired link answers 410 Gone with a JSON error body.
