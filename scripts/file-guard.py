#!/usr/bin/env python3
"""PreToolUse(Write|Edit|MultiEdit|NotebookEdit) during an active AI-Craftman run.

Blocks (exit 2):
- edits to run control files (state.md, approvals.md, answers.md, active-run)
- secrets written anywhere under .craftman/
- test-file edits by code-writer / code-optimizer (tests are the spec)
"""
import json, os, re, sys

CONTROL = re.compile(r"\.craftman/(active-run|memory/[^/]+/(state|approvals|answers)\.md)$")
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


def block(msg):
    print(f"AI-Craftman: blocked. {msg}", file=sys.stderr)
    sys.exit(2)


def main():
    data = json.load(sys.stdin)
    root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    if not os.path.isfile(os.path.join(root, ".craftman", "active-run")):
        return
    ti = data.get("tool_input") or {}
    path = (ti.get("file_path") or ti.get("notebook_path") or "").replace("\\", "/")

    if CONTROL.search(path):
        block("Run control files change only through craftman-state or the human's recorded answers.")

    if "/.craftman/" in path or path.startswith(".craftman/"):
        text = "\n".join(
            str(x) for x in [ti.get("content"), ti.get("new_string"), ti.get("new_source")]
            + [e.get("new_string") for e in ti.get("edits") or []]
            if x
        )
        for rx in SECRETS:
            if rx.search(text):
                block(f"Possible secret in memory file {path} (pattern {rx.pattern[:30]}...). Replace it with <redacted>.")

    if IMPLEMENTERS.search(data.get("agent_type") or "") and TEST_FILE.search(path):
        block(f"{data.get('agent_type')} may not edit test files ({path}). If a test is wrong, stop with status: blocked and explain.")


if __name__ == "__main__":
    main()
