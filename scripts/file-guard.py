#!/usr/bin/env python3
"""PreToolUse(Write|Edit|MultiEdit|NotebookEdit|Read|Grep|Glob|Bash, and Codex's apply_patch) during an active AI-Craftman run.

Blocks (exit 2):
- edits to run control files (state.md, approvals.md, answers.md, active-run, verify/*.md: only craftman-state writes those)
- edits to a gate's evidence file (00-triage, 01-requirements, 04-context, 09a-hidden-tests, 11a-e2e) by an agent other
  than the one that owns it (deploy-guard refuses the same through a Bash command); the orchestrator may still write a
  refused agent's output
- secrets written anywhere under .craftman/
- test-file edits by code-writer / code-optimizer (tests are the spec)
- any access to the hidden acceptance suite (.craftman/hidden), or to the craftman-state commands that unpack it,
  by a builder, reviewer or package lead: the suite is a holdout set, and code tuned to it would prove nothing
- e2e-verifier writes outside .craftman/ (it drives the app and reports; it never patches the code)

Claude Code names the running agent (agent_type); Codex does not. Under Codex the SubagentStart/Stop hooks keep
.craftman/.agents-active, and while any builder, reviewer or lead is active the hidden suite is off limits to every
tool call; the rules that need the exact agent (test-file lock, evidence ownership, e2e-verifier writes) stay
prompt-only there. Codex's apply_patch carries the whole patch in tool_input.command; its files and added lines are
checked like a Write.
"""
import json, os, re, subprocess, sys

WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit", "apply_patch"}
# case-insensitive: a Mac's file system is, so STATE.MD would be read back as state.md
CONTROL = re.compile(r"\.craftman/(active-run|\.agents-active|memory/[^/]+/((state|approvals|answers)\.md|verify/[^/]+))$", re.I)
PATCH_FILE = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$|^\*\*\* Move to: (.+)$", re.M)
# gate evidence the state machine reads (kind, size, e2e_mode, test_command, RED_CONFIRMED, PASS): one agent writes each
# file, and craftman-state's latest() reads exactly these names (name.md, name-<n>.md), nothing that merely starts alike
EVIDENCE = re.compile(r"\.craftman/memory/[^/]+/(00-triage|01-requirements|04-context|09a-hidden-tests|11a-e2e)(-\d+)?\.md$", re.I)
OWNER = {"00-triage": "triage", "01-requirements": "requirements-planner", "04-context": "enterprise-context",
         "09a-hidden-tests": "acceptance-writer", "11a-e2e": "e2e-verifier"}
SECRETS = [
    re.compile(p) for p in (
        r"AKIA[0-9A-Z]{16}",
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
        r"\bgh[pousr]_[A-Za-z0-9]{36,}",
        r"\bxox[abprs]-[A-Za-z0-9-]{10,}",
        r"\bsk-[A-Za-z0-9_-]{20,}",
        r"\bAIza[0-9A-Za-z_-]{35}",
        # keyword = value: the value must mix letters and digits, so schema fields (`password: SecretStr`)
        # and env var names (`api_key: FILE_SERVICE_API_KEY`) in design docs are not blocked
        r"(?i)\b(password|passwd|secret|api[_-]?key|token)\b\s*[:=]\s*['\"]?(?=[^\s'\"<()\[\]{}]*[0-9])(?=[^\s'\"<()\[\]{}]*[a-z])[^\s'\"<()\[\]{}]{8,}",
    )
]
TEST_FILE = re.compile(
    r"(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]+$|_test\.[a-z]+$|\.(test|spec)\.[a-z]+$|Tests?\.(java|kt|cs)$"
)
# an agent is "ai-craftman:<role>" in Claude Code and "craftman-<role>" in Codex
IMPLEMENTERS = re.compile(r"(^|:|-)(code-writer|code-optimizer)$")
BUILDERS = re.compile(r"(^|:|-)(tdd-engineer|test-writer|code-writer|code-optimizer|code-reviewer|package-lead)$")
# ponytail: a text match on the tool input. It stops a builder that names the suite's path or unpacks it; a path built
# from variables or a glob gets through. A real boundary would keep the suite outside the project.
HIDDEN = re.compile(r"\.craftman/+(\./+)*hidden|craftman-state\s+(hide|reveal|verify\s+hidden)\b")


def block(msg):
    print(f"AI-Craftman: blocked. {msg}", file=sys.stderr)
    sys.exit(2)


def foreign_evidence(agent, path):
    """The evidence file this path names that the agent does not own, or None."""
    m = EVIDENCE.search(path)
    name = m.group(1).lower() if m else None
    return name if name and agent and not agent.endswith(OWNER[name]) else None


def project_root(data):
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return env
    cwd = data.get("cwd") or os.getcwd()
    try:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=cwd, capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        top = ""
    return top or cwd


def writes_of(ti):
    """(path, added text) pairs a write tool touches: one for Write/Edit, one per file for an apply_patch command."""
    if ti.get("command") and not ti.get("file_path"):
        text = ti["command"]
        if "*** Begin Patch" in text or PATCH_FILE.search(text):
            added = "\n".join(l[1:] for l in text.splitlines() if l.startswith("+"))
            return [(p1 or p2, added) for p1, p2 in PATCH_FILE.findall(text)]
        return []
    content = "\n".join(
        str(x) for x in [ti.get("content"), ti.get("new_string"), ti.get("new_source")]
        + [e.get("new_string") for e in ti.get("edits") or []]
        if x
    )
    return [(ti.get("file_path") or ti.get("notebook_path") or "", content)]


def strings(x):
    """Every string in a tool input, however nested (file_path, pattern, command, edits[].new_string...)."""
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for v in x.values():
            yield from strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from strings(v)


def main():
    data = json.load(sys.stdin)
    root = project_root(data)
    if not os.path.isfile(os.path.join(root, ".craftman", "active-run")):
        return
    ti = data.get("tool_input") or {}
    agent = data.get("agent_type") or ""
    try:   # Codex: no agent in the payload; the SubagentStart/Stop hooks keep the list of running agents
        active = open(os.path.join(root, ".craftman", ".agents-active")).read().split()
    except OSError:
        active = []
    builder_active = bool(BUILDERS.search(agent)) or (not agent and any(BUILDERS.search(a) for a in active))

    if builder_active and any(HIDDEN.search(s) for s in strings(ti)):
        block(f"{agent or 'a builder is active, so this call'} may not touch the hidden acceptance suite. A failing "
              "acceptance test reaches the builder as its name and a one-line reason; fix the behavior the acceptance "
              "criterion names.")

    if data.get("tool_name") not in WRITE_TOOLS:
        return
    for path, text in writes_of(ti):
        # ".." is collapsed first, so ".craftman/memory/r/../../src/app.py" is seen as the source file it is
        path = os.path.normpath(path.replace("\\", "/"))
        in_craftman = "/.craftman/" in path or path.startswith(".craftman/")

        if CONTROL.search(path):
            block("Run control files change only through craftman-state or the human's recorded answers.")

        name = foreign_evidence(agent, path)
        if name:
            block(f"{name}.md is gate evidence written by {OWNER[name]}; {agent} may read it, not change it.")

        if agent.endswith("e2e-verifier") and not in_craftman:
            block(f"e2e-verifier writes only its evidence under .craftman/ ({path} is not). It drives the app and "
                  "reports defects; engineering changes the code.")

        if in_craftman:
            for rx in SECRETS:
                if rx.search(text):
                    block(f"Possible secret in memory file {path} (pattern {rx.pattern[:30]}...). Replace it with <redacted>.")

        if IMPLEMENTERS.search(agent) and TEST_FILE.search(path):
            block(f"{agent} may not edit test files ({path}). If a test is wrong, stop with status: blocked and explain.")


if __name__ == "__main__":
    main()
