#!/usr/bin/env python3
"""PostToolUse(AskUserQuestion) during an active AI-Craftman run.

Appends every human answer to answers.md (audit trail: who, when, question, answer).
A question whose text starts with [APPROVAL:<category>] and whose answer starts with
"Approve" adds `granted: <category>` to approvals.md, which the deploy guard reads.
Approving `budget` raises max_agent_calls by 50%.
"""
import contextlib, datetime, getpass, json, os, re, subprocess, sys, time

APPROVAL = re.compile(r"^\s*\[APPROVAL:([a-z-]+)\]")


def who():
    try:
        name = subprocess.run(["git", "config", "user.name"], capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        name = ""
    return name or getpass.getuser()


@contextlib.contextmanager
def state_lock(root):
    """Same lock as craftman-state and the budget hook; a stale lock is taken over after ~5s."""
    lock = os.path.join(root, ".craftman", ".lock")
    for _ in range(50):
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            time.sleep(0.1)
    try:
        yield
    finally:
        try:
            os.rmdir(lock)
        except OSError:
            pass


def answers_of(data):
    for src in (data.get("tool_input") or {}, data.get("tool_response") or {}):
        if isinstance(src, dict) and isinstance(src.get("answers"), dict) and src["answers"]:
            return src["answers"]
    return {}


def main():
    data = json.load(sys.stdin)
    root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    active = os.path.join(root, ".craftman", "active-run")
    if not os.path.isfile(active):
        return
    run = open(active).read().strip()
    rundir = os.path.join(root, ".craftman", "memory", run)
    os.makedirs(rundir, exist_ok=True)
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    user = who()
    answers = answers_of(data)
    questions = [q.get("question", "") for q in (data.get("tool_input") or {}).get("questions", [])]

    with open(os.path.join(rundir, "answers.md"), "a") as f:
        for q in questions or answers.keys():
            f.write(f"\n### {ts} by {user}\n- question: {q}\n- answer: {answers.get(q, '<no answer recorded>')}\n")

    grants = []
    for q, a in answers.items():
        m = APPROVAL.match(q)
        if m and str(a).strip().lower().startswith("approve"):
            grants.append(m.group(1))
    if not grants:
        return
    with open(os.path.join(rundir, "approvals.md"), "a") as f:
        for c in grants:
            f.write(f"granted: {c} | {ts} | {user}\n")
    if "budget" in grants:
        state = os.path.join(rundir, "state.md")
        if os.path.isfile(state):
            with state_lock(root):
                s = open(state).read()
                m = re.search(r"^max_agent_calls: (\d+)$", s, re.M)
                if m:
                    new = int(int(m.group(1)) * 1.5) + 1
                    with open(state + ".tmp", "w") as f:
                        f.write(s[: m.start(1)] + str(new) + s[m.end(1):])
                    os.replace(state + ".tmp", state)


if __name__ == "__main__":
    main()
