#!/usr/bin/env python3
"""Generate the Codex plugin (codex/) from the Claude Code sources. Usage: build-codex.py [--check]

Single source of truth: agents/*.md, commands/*.md, skills/, scripts/, bin/, templates/, .claude-plugin/plugin.json.
The output is committed; tests/run.sh fails when codex/ is stale (--check builds into a temp dir and compares).
What changes in the translation: Claude agent names become craftman-<name> custom agents (TOML), the commands become
skills with the Codex notes in front, hooks get Codex's matchers and ${PLUGIN_ROOT}, and tool names that only Claude
Code has are replaced by what Codex has (see templates/codex/notes.md).
"""
import json, re, shutil, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "codex"
TIER = {"opus": "strong", "sonnet": "mid", "haiku": "fast"}
# order matters: the command names (with the slash) go first, the generic agent prefix after
SUBS = [
    (r"/ai-craftman:craftman-init\b", "$craftman-init"), (r"/ai-craftman:craftman-resume\b", "$craftman-resume"),
    (r"/ai-craftman:craftman-status\b", "$craftman-status"), (r"/ai-craftman:craftman\b", "$craftman"),
    (r"ai-craftman:([a-z-]+)", r"craftman-\1"), (r"ai-craftman:\*", "craftman-*"), (r"`ai-craftman:`", "`craftman-`"),
    (r"\$\{CLAUDE_PLUGIN_ROOT\}", "$PR"),
    (r"\$\{user_config\.model_tier\}", "`model_tier` in `.craftman/governance.md`"),
    (r"\$\{user_config\.max_agent_calls\}", "<max_agent_calls from .craftman/governance.md>"),
    (r"`AskUserQuestion`|AskUserQuestion", "`request_user_input` (or `craftman-state ask`, see the Codex notes)"),
    (r"`SendMessage`", "a follow-up message to the agent's thread"),
    (r"a new `Agent` call", "a newly spawned agent"), (r"several `?Agent`? calls", "several agents spawned"),
    (r"`Agent` calls?", "spawn"),
    (r"`model: opus`", "your strong-tier model"), (r"`model: sonnet`", "your mid-tier model"),
    (r"`TodoWrite`|TodoWrite", "your plan"),
]


def codexify(text):
    for pat, rep in SUBS:
        text = re.sub(pat, rep, text)
    return text


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}, text
    meta, key = {}, None
    for line in m.group(1).splitlines():
        if re.match(r"^\s+-\s", line) and key:
            meta.setdefault(key, []).append(line.strip()[2:].strip())
        elif ":" in line:
            key, val = line.split(":", 1)
            key, val = key.strip(), val.strip()
            meta[key] = val if val else []
    return meta, text[m.end():]


def agent_toml(path):
    meta, body = frontmatter(path.read_text())
    name, body = meta["name"], codexify(body).strip()
    assert "'''" not in body, f"{path}: ''' in the body breaks the TOML literal string"
    skills = [s.split(":", 1)[-1] for s in meta.get("skills", [])]
    pre = ("Before you start, read these skills in full (the plugin ships them): "
           + ", ".join(f"${s}" for s in skills) + ".\n\n") if skills else ""
    tools = meta.get("tools", "")
    model = meta.get("model", "sonnet")
    lines = [
        f'name = "craftman-{name}"',
        f"description = {json.dumps(meta['description'])}",
        f'# tier: {TIER.get(model, "mid")} (Claude Code default: {model}). Set `model` here, or [agents] default_subagent_model in config.toml for the mid tier.',
        f'# model = "<your {TIER.get(model, "mid")}-tier model>"',
        f'model_reasoning_effort = "{meta.get("effort", "medium")}"',
        "",
        "developer_instructions = '''",
        pre + body,
        "'''",
    ]
    if tools and "Bash" not in tools:   # a tools line without Bash: this role never runs commands (no line = inherits all)
        lines += ["", "[features]", "shell_tool = false   # this role reads and writes files; it runs no commands"]
    return "\n".join(lines) + "\n"


def skill_md(path, notes_first):
    meta, body = frontmatter(path.read_text())
    name = path.stem
    head = f"---\nname: {name}\ndescription: {meta.get('description', name)}\n---\n\n"
    if notes_first:
        head += ("Read `references/codex-notes.md` in this skill's folder first: it says how the dispatches, the questions "
                 "to the human, the plugin root `PR` and the model tiers work in Codex. Then follow the pipeline below.\n\n")
    return head + codexify(body).lstrip()


HOOKS = {
    "hooks": {
        "SessionStart": [{"hooks": [{"type": "command", "command": "bash \"${PLUGIN_ROOT}/scripts/codex-session.sh\"", "timeout": 10}]}],
        "PreToolUse": [
            {"matcher": "^Bash$", "hooks": [
                {"type": "command", "command": "bash \"${PLUGIN_ROOT}/scripts/deploy-guard.sh\"", "statusMessage": "AI-Craftman: deploy and control-file guard"},
                {"type": "command", "command": "python3 \"${PLUGIN_ROOT}/scripts/file-guard.py\""}]},
            {"matcher": "^(apply_patch|Edit|Write|MultiEdit|NotebookEdit|Read|Grep|Glob)$", "hooks": [
                {"type": "command", "command": "python3 \"${PLUGIN_ROOT}/scripts/file-guard.py\"", "statusMessage": "AI-Craftman: file guard"}]},
            {"matcher": "^(Agent|spawn_agent|send_input|resume_agent|SendMessage)$", "hooks": [
                {"type": "command", "command": "bash \"${PLUGIN_ROOT}/scripts/agent-budget.sh\"", "statusMessage": "AI-Craftman: agent budget"}]},
            {"matcher": "^request_user_input$", "hooks": [
                {"type": "command", "command": "\"${PLUGIN_ROOT}/bin/craftman-state\" notify \"A question is waiting for your answer\""}]},
        ],
        "PostToolUse": [
            {"matcher": "^request_user_input$", "hooks": [{"type": "command", "command": "python3 \"${PLUGIN_ROOT}/scripts/record-answers.py\""}]},
        ],
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "python3 \"${PLUGIN_ROOT}/scripts/record-answers.py\""}]}],
        "SubagentStart": [{"hooks": [{"type": "command", "command": "bash \"${PLUGIN_ROOT}/scripts/agents-active.sh\""}]}],
        "SubagentStop": [{"hooks": [{"type": "command", "command": "bash \"${PLUGIN_ROOT}/scripts/agents-active.sh\""}]}],
    }
}


def build(out):
    claude = json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text())
    out.mkdir(parents=True)
    (out / "plugin.json").write_text(json.dumps({
        "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
        "name": "ai-craftman", "version": claude["version"], "description": claude["description"],
        "author": claude["author"], "homepage": claude["homepage"], "repository": claude["repository"],
        "license": claude["license"], "keywords": claude["keywords"] + ["codex"],
        "extensions": {"com.openai": {
            "hooks": "./hooks/hooks.json",
            "onboardingSkill": "./skills/craftman-init/SKILL.md",
            "interface": {
                "displayName": "AI-Craftman",
                "shortDescription": "AI-SDLC pipeline: requirements, design, hidden acceptance tests, test-first engineering, verified suites, e2e, QA, DevOps.",
                "category": "Developer Tools",
                "capabilities": ["Read", "Write"],
                "defaultPrompt": ["$craftman Add password reset via email to the user service"],
            },
        }},
    }, indent=2) + "\n")
    (out / "hooks").mkdir()
    (out / "hooks" / "hooks.json").write_text(json.dumps(HOOKS, indent=2) + "\n")
    for d in ("bin", "scripts", "templates"):
        shutil.copytree(ROOT / d, out / d)
    (out / "skills").mkdir()
    for s in (ROOT / "skills").iterdir():
        if (s / "SKILL.md").is_file():
            shutil.copytree(s, out / "skills" / s.name)
    for cmd in (ROOT / "commands").glob("*.md"):
        d = out / "skills" / cmd.stem
        d.mkdir()
        (d / "SKILL.md").write_text(skill_md(cmd, notes_first=(cmd.stem == "craftman")))
        if cmd.stem == "craftman":
            (d / "references").mkdir()
            shutil.copy(ROOT / "templates" / "codex" / "notes.md", d / "references" / "codex-notes.md")
    (out / "agents").mkdir()
    for a in sorted((ROOT / "agents").glob("*.md")):
        (out / "agents" / f"craftman-{a.stem}.toml").write_text(agent_toml(a))
    (out / "README.md").write_text(
        "# AI-Craftman for Codex\n\nGenerated by `scripts/build-codex.py` from the Claude Code sources in the repository root; "
        "do not edit here. Install: `codex plugin marketplace add suraj-singh-sde/ai-craftman`, then `/plugins` in Codex, "
        "then `$craftman-init` in your project. See `skills/craftman/references/codex-notes.md` for what differs from "
        "Claude Code.\n")


def tree(base):
    return {str(p.relative_to(base)): p.read_bytes() for p in base.rglob("*") if p.is_file()}


if __name__ == "__main__":
    if "--check" in sys.argv:
        with tempfile.TemporaryDirectory() as tmp:
            fresh = Path(tmp) / "codex"
            build(fresh)
            want, have = tree(fresh), tree(OUT) if OUT.is_dir() else {}
            stale = sorted(set(want) ^ set(have) | {k for k in want if k in have and want[k] != have[k]})
            if stale:
                print("codex/ is stale, run scripts/build-codex.py:\n  " + "\n  ".join(stale))
                sys.exit(1)
            print("codex/ is up to date")
    else:
        if OUT.is_dir():
            shutil.rmtree(OUT)
        build(OUT)
        print(f"built {OUT}")
