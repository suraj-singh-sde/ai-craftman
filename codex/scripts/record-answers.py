#!/usr/bin/env python3
"""Record the human's answers during an active AI-Craftman run.

- PostToolUse(AskUserQuestion) in Claude Code: questions in tool_input, answers keyed by question text.
- PostToolUse(request_user_input) in Codex: questions carry an id; the answers come back keyed by that id (or in order).
- UserPromptSubmit in Codex sessions without a question tool: `craftman-state ask` left the question and its options in
  the run's pending.md; the human's next message that matches an option is the answer.

Appends every answer to answers.md (audit trail: who, when, question, answer). A question whose text starts with
[APPROVAL:<category>] and whose answer starts with "Approve" adds `granted: <category>` to approvals.md, which the
deploy guard reads. Approving `budget` raises max_agent_calls by 50%.
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
    """Same lock as craftman-state and the budget hook: a file created with O_EXCL, taken over only when it is itself
    older than 5s (a crashed holder); a busy one is waited for, up to 60s."""
    lock = os.path.join(root, ".craftman", ".lock")
    if os.path.isdir(lock):   # a directory lock left by a version before 0.8.0
        try:
            os.rmdir(lock)
        except OSError:
            pass
    for _ in range(600):
        try:
            os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
            break
        except FileExistsError:
            try:
                if time.time() - os.stat(lock).st_mtime >= 5:
                    os.unlink(lock)
                    continue
            except OSError:
                pass
            time.sleep(0.1)
    try:
        yield
    finally:
        try:
            os.unlink(lock)
        except OSError:
            pass


def project_root(data):
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return env
    cwd = data.get("cwd") or os.getcwd()
    try:
        top = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=cwd, capture_output=True, text=True, timeout=5).stdout.strip()
        if top.endswith("/.git"):
            top = top[:-5]
        else:   # a bare repo or a submodule: the common dir is not "<root>/.git"
            top = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=cwd, capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        top = ""
    return top or cwd


def strings(x):
    if isinstance(x, str):
        yield x
    elif isinstance(x, dict):
        for v in x.values():
            yield from strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from strings(v)


def pairs_of(data):
    """(question, answer) pairs from a question tool's input and response, whichever shape the harness uses."""
    ti = data.get("tool_input") or {}
    resp = data.get("tool_response")
    if isinstance(resp, str):
        try:
            resp = json.loads(resp)
        except ValueError:
            resp = {"text": resp}
    questions = [q for q in ti.get("questions", []) if isinstance(q, dict)]
    # Claude Code: answers keyed by the question text, in tool_input or tool_response
    for src in (ti, resp if isinstance(resp, dict) else {}):
        a = src.get("answers")
        if isinstance(a, dict) and a and all(isinstance(k, str) and any(q.get("question") == k for q in questions) for k in a):
            return [(k, " ".join(strings(v))) for k, v in a.items()]
    # Codex: answers keyed by the question's id, each a string, a list or {"answers": [...]}
    by_id = {q.get("id"): q.get("question") or q.get("prompt") or q.get("text") or "" for q in questions if q.get("id")}
    found = []
    if isinstance(resp, dict):
        pool = resp.get("answers") if isinstance(resp.get("answers"), dict) else resp
        for qid, text in by_id.items():
            if qid in pool:
                found.append((text, " ".join(strings(pool[qid]))))
    if found:
        return found
    # last resort: the response's strings in question order
    texts = [q.get("question") or q.get("prompt") or q.get("text") or "" for q in questions]
    answers = list(strings(resp)) if resp is not None else []
    return list(zip(texts, answers)) or [(t, "<no answer recorded>") for t in texts]


def pending_pair(rundir, prompt):
    """UserPromptSubmit: the human's message answers the question craftman-state ask left behind, if it names an option."""
    path = os.path.join(rundir, "pending.md")
    if not os.path.isfile(path) or not prompt:
        return None
    meta = dict(l.split(": ", 1) for l in open(path).read().splitlines() if ": " in l)
    options = [o.strip() for o in meta.get("options", "").split("|") if o.strip()]
    said = prompt.strip().strip(".!").strip().lower()
    for o in options:
        if said == o.lower():   # exactly one option's label: a longer message is a question, not an answer
            os.unlink(path)
            return (meta.get("question", ""), o)
    return None


def record(root, rundir, pairs):
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    user = who()
    with open(os.path.join(rundir, "answers.md"), "a") as f:
        for q, a in pairs:
            f.write(f"\n### {ts} by {user}\n- question: {q}\n- answer: {a}\n")
    grants = [m.group(1) for q, a in pairs for m in [APPROVAL.match(q)] if m and str(a).strip().lower().startswith("approve")]
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


def main():
    data = json.load(sys.stdin)
    root = project_root(data)
    active = os.path.join(root, ".craftman", "active-run")
    if not os.path.isfile(active):
        return
    run = open(active).read().strip()
    rundir = os.path.join(root, ".craftman", "memory", run)
    os.makedirs(rundir, exist_ok=True)
    if data.get("hook_event_name") == "UserPromptSubmit" or ("prompt" in data and "tool_input" not in data):
        pair = pending_pair(rundir, data.get("prompt") or "")
        if pair:
            record(root, rundir, [pair])
        return
    pairs = pairs_of(data)
    if pairs:
        record(root, rundir, pairs)


if __name__ == "__main__":
    main()
