#!/usr/bin/env python3
"""Build .craftman/memory/<run>/report.html: status, design and results of one run.

Usage: report.py <run-dir> <steps>   (steps = craftman-state's FULL_STEPS, "step:stage:owner" lines)
Read-only view: it never changes the run. Markdown and mermaid render in the browser;
offline, each document falls back to plain text.
"""
import html
import json
import re
import sys
from pathlib import Path

DESIGN = ["06-hld.md", "07-gov-architecture.md", "08-oversight-architecture.md",
          "08a-lld.md", "08b-gov-design.md", "09-work-plan.md"]
STATUS = ["approvals.md", "escalations.md", "answers.md"]
STEP_RE = re.compile(r"^- \[(.)\] (\S+)\s*(.*)$")
TOOK_RE = re.compile(r"took (\S+)\)")


def header(text):
    """Split an agent file's '---' header from its body."""
    m = re.match(r"^---\n(.*?)\n---\n?", text, re.S)
    if not m:
        return {}, text
    meta = dict(line.split(":", 1) for line in m.group(1).splitlines() if ":" in line)
    return {k.strip(): v.strip() for k, v in meta.items()}, text[m.end():]


def doc(run, rel):
    meta, body = header((run / rel).read_text(errors="replace"))
    return {"path": rel, "meta": meta, "body": body}


def parse_state(run, steps):
    text = (run / "state.md").read_text()
    info = dict(l.split(": ", 1) for l in text.split("\n## steps")[0].splitlines() if ": " in l)
    stage = {l.split(":")[0]: l.split(":")[1] for l in steps.splitlines() if l.count(":") >= 2}
    rows = []
    for line in text.splitlines():
        m = STEP_RE.match(line)
        if m:
            mark, step, note = m.groups()
            took = TOOK_RE.search(note)
            rows.append({"step": step, "stage": stage.get(step, ""), "note": note,
                         "state": {"x": "done", "-": "skipped"}.get(mark, "pending"),
                         "took": took.group(1) if took else ""})
    return info, rows


def build(run, steps):
    info, rows = parse_state(run, steps)
    files = sorted(str(p.relative_to(run)) for p in run.rglob("*.md"))
    pick = lambda names: [doc(run, n) for n in names if n in files]
    results = [f for f in files if f not in DESIGN + STATUS + ["state.md"]]
    data = {"info": info, "steps": rows, "status": pick(STATUS), "design": pick(DESIGN),
            "results": [doc(run, f) for f in results]}
    # "</" is escaped so no document can close the script tag it is embedded in
    blob = json.dumps(data).replace("</", "<\\/")
    title = html.escape(f"AI-Craftman · {info.get('run', run.name)}")
    return PAGE.replace("{{TITLE}}", title).replace("{{DATA}}", blob)


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{TITLE}}</title>
<style>
:root{--bg:#f7f7f5;--card:#fff;--fg:#1d1d1b;--muted:#6b6b66;--line:#e2e2dd;--ok:#1f7a3f;--warn:#a15c00;--bad:#b42318;--info:#2453a6}
@media (prefers-color-scheme:dark){:root{--bg:#161615;--card:#1f1f1d;--fg:#ececea;--muted:#9a9a94;--line:#34342f;--ok:#5cc07f;--warn:#e0a24a;--bad:#f07a6e;--info:#7fa6f0}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,sans-serif}
header{padding:20px 16px 0;max-width:1100px;margin:auto}h1{margin:0 0 4px;font-size:22px}
.sub{color:var(--muted);font-size:13px}.kpis{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:8px 12px;min-width:110px}
.kpi b{display:block;font-size:17px}.kpi span{color:var(--muted);font-size:12px}
.bar{height:6px;background:var(--line);border-radius:3px;overflow:hidden}.bar i{display:block;height:100%;background:var(--ok)}
nav{display:flex;gap:4px;border-bottom:1px solid var(--line);margin-top:14px;overflow-x:auto}
nav button{background:none;border:0;border-bottom:2px solid transparent;padding:8px 12px;color:var(--muted);font:inherit;cursor:pointer}
nav button.on{color:var(--fg);border-color:var(--fg)}main{max-width:1100px;margin:auto;padding:16px}
section{display:none}section.on{display:block}
.card{background:var(--card);border:1px solid var(--line);border-radius:8px;margin-bottom:12px}
.card>summary{padding:10px 14px;cursor:pointer;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.card>summary code{font-weight:600}.body{padding:0 16px 14px;overflow-x:auto;border-top:1px solid var(--line)}
.pill{font-size:11px;padding:1px 8px;border-radius:10px;border:1px solid currentColor;white-space:nowrap}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}.info{color:var(--info)}.muted{color:var(--muted)}
table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--muted);font-weight:500}pre{background:var(--bg);padding:10px;border-radius:6px;overflow-x:auto;white-space:pre-wrap}
.body pre code{white-space:pre}.mermaid{background:#fff;border-radius:6px;padding:8px;overflow-x:auto}
.empty{color:var(--muted);padding:20px 0}.tablewrap{overflow-x:auto}
</style></head><body>
<header><h1 id="h"></h1><div class="sub" id="sub"></div><div class="kpis" id="kpis"></div><div class="bar"><i id="prog"></i></div>
<nav id="tabs"></nav></header><main id="main"></main>
<script id="data" type="application/json">{{DATA}}</script>
<script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js" integrity="sha384-/TQbtLCAerC3jgaim+N78RZSDYV7ryeoBCVqTuzRrFec2akfBkHS7ACQ3PQhvMVi" crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/dompurify@3.4.16/dist/purify.min.js" integrity="sha384-a7SzOxErzJ3ZpQz0zJ32d67dSitNzPcbfybc/ykU9KJhMgZkwqfSxlhhdJRS+XGL" crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.min.js" integrity="sha384-EOXBFmc3gx5mb+vn0vPvvGqACToJD24hhacX5Yx+8NUUQrHIle/Qi5Bg9o3zKwW2" crossorigin="anonymous"></script>
<script>
const D = JSON.parse(document.getElementById('data').textContent), I = D.info;
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const tone = v => /^(APPROVED|PASS|GREEN|READY|ANSWERED|done|complete)/i.test(v) ? 'ok'
  : /(CHANGES|BLOCK|NOT_READY|blocked|aborted|FAIL)/i.test(v) ? 'bad'
  : /(needs_input|PARTIAL|APPROVAL_REQUIRED|in_progress|pending)/i.test(v) ? 'warn' : 'info';
const pill = v => v ? `<span class="pill ${tone(v)}">${esc(v)}</span>` : '';
// Agent output is untrusted (research pages, repo content): rendered markdown is always sanitized.
const md = t => (window.marked && window.DOMPurify) ? DOMPurify.sanitize(marked.parse(t)) : `<pre>${esc(t)}</pre>`;

function card(d, open) {
  const m = d.meta, q = +m.open_questions ? pill(m.open_questions + ' open questions') : '';
  return `<details class="card"${open ? ' open' : ''}><summary><code>${esc(d.path)}</code>
    ${m.agent ? `<span class="muted">${esc(m.agent)}</span>` : ''}${pill(m.status)}${m.verdict && m.verdict !== 'n/a' ? pill(m.verdict) : ''}${q}</summary>
    <div class="body">${md(d.body)}</div></details>`;
}
const list = (docs, empty) => docs.length ? docs.map((d, i) => card(d, i === 0)).join('') : `<p class="empty">${empty}</p>`;

const done = D.steps.filter(s => s.state === 'done').length, skipped = D.steps.filter(s => s.state === 'skipped').length;
const total = D.steps.length - skipped, next = D.steps.find(s => s.state === 'pending');
document.getElementById('h').textContent = I.run || 'run';
document.getElementById('sub').textContent = I.requirement || '';
document.getElementById('kpis').innerHTML = [
  ['Status', pill(I.status)], ['Progress', `${done} / ${total}`], ['Next', esc(next ? next.step : 'none')],
  ['Profile', esc(I.profile)], ['Duration', esc(I.duration || 'running')], ['Agent calls', `${esc(I.agent_calls)} / ${esc(I.max_agent_calls)}`],
  ['Branch', esc(I.branch || '–')], ['Packages done', esc(I.packages_done || '–')]
].map(([k, v]) => `<div class="kpi"><span>${k}</span><b>${v}</b></div>`).join('');
document.getElementById('prog').style.width = (total ? 100 * done / total : 0) + '%';

const slow = D.steps.filter(s => s.took).map(s => {
  const m = s.took.match(/(?:(\d+)h)?(\d+)m(?:(\d+)s)?/); return [s, m ? (+m[1]||0)*3600 + (+m[2]||0)*60 + (+m[3]||0) : 0];
}).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([s]) => `${esc(s.step)} (${esc(s.took)})`).join(', ');
const steps = `<div class="tablewrap"><table><tr><th>Step</th><th>Stage</th><th>State</th><th>Took</th><th>Note</th></tr>${
  D.steps.map(s => `<tr><td>${esc(s.step)}</td><td class="muted">${esc(s.stage)}</td><td>${pill(s.state)}</td><td>${esc(s.took)}</td>
  <td class="muted">${esc(s.note.replace(/\(done [^)]*\)|\(skipped: ([^)]*)\)/, '$1'))}</td></tr>`).join('')}</table></div>
  ${slow ? `<p class="muted">Slowest steps: ${slow}</p>` : ''}`;

const tabs = {
  Status: steps + list(D.status, ''),
  Design: list(D.design, 'No design documents yet. The HLD appears after the architecture step.'),
  Results: list(D.results, 'No results yet.'),
};
let draw = () => {};
if (window.mermaid) {
  mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' });
  draw = root => mermaid.run({ nodes: [...root.querySelectorAll('details[open] .mermaid:not([data-processed])')] }).catch(() => {});
}
const nav = document.getElementById('tabs'), main = document.getElementById('main');
let saved; try { saved = localStorage.getItem('craftman-tab'); } catch (e) {}
Object.entries(tabs).forEach(([name, html], i) => {
  const b = document.createElement('button'), s = document.createElement('section');
  b.textContent = name; s.innerHTML = html; nav.append(b); main.append(s);
  s.querySelectorAll('code.language-mermaid').forEach(c => {
    const d = document.createElement('div'); d.className = 'mermaid'; d.textContent = c.textContent; c.parentElement.replaceWith(d);
  });
  s.querySelectorAll('details').forEach(d => d.addEventListener('toggle', () => d.open && d.offsetParent && draw(d.parentElement)));
  b.onclick = () => { nav.querySelectorAll('button').forEach(x => x.classList.remove('on'));
    main.querySelectorAll('section').forEach(x => x.classList.remove('on'));
    b.classList.add('on'); s.classList.add('on'); draw(s); try { localStorage.setItem('craftman-tab', name); } catch (e) {} };
  if (name === saved || (!saved && i === 0)) b.click();
});

// keep a running pipeline's page current
if (I.status === 'in_progress') setTimeout(() => location.reload(), 30000);
</script></body></html>
"""

if __name__ == "__main__":
    run_dir = Path(sys.argv[1])
    out = run_dir / "report.html"
    out.write_text(build(run_dir, sys.argv[2] if len(sys.argv) > 2 else ""))
    print(out)
