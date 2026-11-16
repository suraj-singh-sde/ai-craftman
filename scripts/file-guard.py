#!/usr/bin/env python3
"""PreToolUse(Write|Edit|MultiEdit|NotebookEdit|Read|Grep|Glob|Bash) during an active AI-Craftman run.

Blocks (exit 2):
- edits to run control files (state.md, approvals.md, answers.md, active-run, verify/*.md: only craftman-state writes those)
- edits to a gate's evidence file (00-triage, 04-context, 09a-hidden-tests, 11a-e2e) by an agent other than the one that
  owns it, through a write tool or a Bash redirect; the orchestrator may still write a refused agent's output
- secrets written anywhere under .craftman/
- test-file edits by code-writer / code-optimizer (tests are the spec)
- any access to the hidden acceptance suite (.craftman/hidden), or to the craftman-state commands that unpack it,
  by a builder, reviewer or package lead: the suite is a holdout set, and code tuned to it would prove nothing
- e2e-verifier writes outside .craftman/ (it drives the app and reports; it never patches the code)
"""
import json, os, re, sys

WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
CONTROL = re.compile(r"\.craftman/(active-run|memory/[^/]+/((state|approvals|answers)\.md|verify/[^/]+))$")
# gate evidence the state machine reads (kind, e2e_mode, test_command, RED_CONFIRMED, PASS): one agent writes each file
EVIDENCE = re.compile(r"\.craftman/memory/[^/]+/(00-triage|04-context|09a-hidden-tests|11a-e2e)(-\d+)?\.md")
OWNER = {"00-triage": "triage", "04-context": "enterprise-context", "09a-hidden-tests": "acceptance-writer", "11a-e2e": "e2e-verifier"}
# a Bash command that can write a named file (reads such as cat and grep pass); harmless redirects are removed first
WRITES = re.compile(r"(>|\btee |sed -i|perl -i|\bcp |\bmv |\brm |\bln |truncate|\bdd )")
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
IMPLEMENTERS = re.compile(r"(^|:)(code-writer|code-optimizer)$")
BUILDERS = re.compile(r"(^|:)(tdd-engineer|test-writer|code-writer|code-optimizer|code-reviewer|package-lead)$")
# ponytail: a text match on the tool input. It stops a builder that names the suite's path or unpacks it; a path built
# from variables or a glob gets through. A real boundary would keep the suite outside the project.
HIDDEN = re.compile(r"\.craftman/+(\./+)*hidden|craftman-state\s+(hide|reveal|verify\s+hidden)\b")


def block(msg):
    print(f"AI-Craftman: blocked. {msg}", file=sys.stderr)
    sys.exit(2)


def foreign_evidence(agent, text):
    """The evidence file named in text that this agent does not own, or None."""
    m = EVIDENCE.search(text)
    return m.group(1) if m and agent and not agent.endswith(OWNER[m.group(1)]) else None


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
    root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    if not os.path.isfile(os.path.join(root, ".craftman", "active-run")):
        return
    ti = data.get("tool_input") or {}
    agent = data.get("agent_type") or ""

    if BUILDERS.search(agent) and any(HIDDEN.search(s) for s in strings(ti)):
        block(f"{agent} may not touch the hidden acceptance suite. A failing acceptance test reaches you as its name "
              "and a one-line reason; fix the behavior the acceptance criterion names.")

    if data.get("tool_name") == "Bash":
        cmd = re.sub(r"\d?>&[\d-]|\d?>\s*/dev/null", " ", ti.get("command") or "")
        name = foreign_evidence(agent, cmd)
        if name and WRITES.search(cmd):
            block(f"{name}.md is gate evidence written by {OWNER[name]}; {agent} may read it, not change it.")
        return
    if data.get("tool_name") not in WRITE_TOOLS:
        return
    # ".." is collapsed first, so ".craftman/memory/r/../../src/app.py" is seen as the source file it is
    path = os.path.normpath((ti.get("file_path") or ti.get("notebook_path") or "").replace("\\", "/"))
    in_craftman = "/.craftman/" in path or path.startswith(".craftman/")

    if CONTROL.search(path):
        block("Run control files change only through craftman-state or the human's recorded answers.")

    name = foreign_evidence(agent, path)
    if name:
        block(f"{name}.md is gate evidence written by {OWNER[name]}; {agent} may read it, not change it.")

    if agent.endswith("e2e-verifier") and not in_craftman:
        block(f"e2e-verifier writes only its evidence under .craftman/ ({path} is not). It drives the app and reports "
              "defects; engineering changes the code.")

    if in_craftman:
        text = "\n".join(
            str(x) for x in [ti.get("content"), ti.get("new_string"), ti.get("new_source")]
            + [e.get("new_string") for e in ti.get("edits") or []]
            if x
        )
        for rx in SECRETS:
            if rx.search(text):
                block(f"Possible secret in memory file {path} (pattern {rx.pattern[:30]}...). Replace it with <redacted>.")

    if IMPLEMENTERS.search(agent) and TEST_FILE.search(path):
        block(f"{agent} may not edit test files ({path}). If a test is wrong, stop with status: blocked and explain.")


if __name__ == "__main__":
    main()
