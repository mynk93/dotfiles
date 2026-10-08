#!/usr/bin/env python3
"""elih: render, lint, scaffold and acknowledge an ELIH orientation surface.

    elih.py init   <elih-dir> --feature <slug> [--name <title>]
    elih.py lint   <elih-dir>
    elih.py render <elih-dir> [-o out.html] [--no-likec4] [--png]
    elih.py ack    <elih-dir> [--date YYYY-MM-DD]
    elih.py status <elih-dir>

Source of truth is <elih-dir>/ledger.yaml plus board.md and chunks/*.md.
The HTML is a derived view. Markdown renders client-side with marked.js;
Mermaid fences become diagrams; LikeC4 views are exported to PNG when the
toolchain is available and embedded where the ledger names a view id.
"""
import argparse
import datetime as dt
import html
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("elih needs PyYAML: pip install pyyaml")

HERE = Path(__file__).resolve().parent
TEMPLATES = HERE.parent / "templates"

STAGES = ["built", "tested", "reviewed", "merged", "deployed"]
RISKS = {"high", "medium", "low"}
PILLAR_STATES = {"verified", "assumed", "needs-you", "invalidated"}
DECISION_STATES = {"assumed", "recommended", "approved", "rejected", "superseded", "needs-you"}
AUTONOMY = {"tight", "normal", "loose"}
MAX_CHUNKS = 7
PLACEHOLDER = "Filled from the ledger by chunk id."
STATE_PILL = {
    "verified": "pill--navy", "approved": "pill--navy",
    "assumed": "pill--soft", "recommended": "pill--accent",
    "needs-you": "pill--accent", "invalidated": "pill--warn",
    "rejected": "pill--warn", "superseded": "pill--soft",
}


# ----------------------------------------------------------------------------
# loading and lint
# ----------------------------------------------------------------------------

def load(src: Path) -> dict:
    return yaml.safe_load((src / "ledger.yaml").read_text())


def lint(src: Path) -> list:
    """Return a list of (level, message). level is 'error' or 'warn'."""
    out = []
    err = lambda m: out.append(("error", m))
    warn = lambda m: out.append(("warn", m))
    try:
        L = load(src)
    except Exception as e:  # noqa: BLE001
        return [("error", f"ledger.yaml does not parse: {e}")]

    F = L.get("feature") or {}
    for k in ("name", "slug", "goal", "done_when", "artifact_to_review", "branch"):
        if not F.get(k):
            err(f"feature.{k} is missing")
    if F.get("autonomy", "normal") not in AUTONOMY:
        err(f"feature.autonomy must be one of {sorted(AUTONOMY)}")

    M = L.get("metaphor") or {}
    if not M.get("chosen"):
        warn("metaphor.chosen is empty; chunk names must come from one metaphor")

    chunks = L.get("chunks") or []
    if not 1 <= len(chunks) <= MAX_CHUNKS:
        err(f"chunks: {len(chunks)} given; need 1 to {MAX_CHUNKS}")
    ids, orders = set(), set()
    for c in chunks:
        cid = c.get("id", "?")
        if cid in ids:
            err(f"chunk id duplicated: {cid}")
        ids.add(cid)
        if c.get("stage") not in STAGES:
            err(f"chunk {cid}: stage must be one of {STAGES}")
        if c.get("risk") not in RISKS:
            err(f"chunk {cid}: risk must be one of {sorted(RISKS)}")
        if c.get("review_order") in orders:
            err(f"chunk {cid}: review_order {c.get('review_order')} is not unique")
        orders.add(c.get("review_order"))
        if re.match(r"^[A-Z]+-?\d+$", str(c.get("name", ""))):
            err(f"chunk {cid}: name '{c.get('name')}' is an abstract id, use the metaphor")
        page = src / "chunks" / f"{cid}.md"
        if not page.exists():
            err(f"chunk {cid}: chunks/{cid}.md is missing")
        else:
            text = page.read_text()
            for h in ("## What it does", "## Why this way", "## How it works", "## States",
                      "## Traceability", "## Decisions and assumptions on this chunk",
                      "## Review entry points"):
                if h not in text:
                    err(f"chunk {cid}: section '{h}' is missing")
            if PLACEHOLDER not in text:
                warn(f"chunk {cid}: placeholder line '{PLACEHOLDER}' is missing; ledger rows will not be injected")

    pillars = L.get("pillars") or []
    if not 1 <= len(pillars) <= 6:
        warn(f"pillars: {len(pillars)} given; three to six is the intent")
    for p in pillars:
        if p.get("state") not in PILLAR_STATES:
            err(f"pillar {p.get('id')}: state must be one of {sorted(PILLAR_STATES)}")
        if p.get("chunk") not in ids:
            err(f"pillar {p.get('id')}: chunk '{p.get('chunk')}' is not a chunk id")

    seen_prefixes = set()
    for d in L.get("decisions") or []:
        if d.get("state") not in DECISION_STATES:
            err(f"decision {d.get('id')}: state must be one of {sorted(DECISION_STATES)}")
        if d.get("chunk") not in ids:
            err(f"decision {d.get('id')}: chunk '{d.get('chunk')}' is not a chunk id")
        m = re.match(r"^([A-Za-z]+)-\d+$", str(d.get("id", "")))
        if not m:
            err(f"decision id '{d.get('id')}' must look like D-12 or C-3")
        else:
            seen_prefixes.add(m.group(1))
    if len(seen_prefixes - {"D", "C"}) > 0:
        warn(f"decision id prefixes beyond D and C: {sorted(seen_prefixes - {'D', 'C'})}. New namespaces are what elih exists to stop")

    for b in L.get("blockers") or []:
        if b.get("chunk") not in ids:
            err(f"blocker {b.get('id')}: chunk '{b.get('chunk')}' is not a chunk id")
        if not b.get("owner"):
            err(f"blocker {b.get('id')}: owner is missing")

    # Truncated values: the classic ' #123' YAML comment trap.
    raw = (src / "ledger.yaml").read_text().splitlines()
    for n, line in enumerate(raw, 1):
        s = line.strip()
        if s.startswith("#") or ":" not in s:
            continue
        val = s.split(":", 1)[1].strip()
        before = val.split(" #", 1)[0].strip().lower()
        if val and " #" in val and not val.startswith(("'", '"', ">", "|", "[", "{")) \
                and before not in {"null", "~", "true", "false", ""} and not re.match(r"^-?\d+(\.\d+)?$", before):
            warn(f"ledger.yaml:{n}: unquoted value contains ' #'; everything after it is a YAML comment")

    board = src / "board.md"
    if not board.exists():
        err("board.md is missing")
    else:
        secs = [t for t, _ in split_sections(board.read_text())]
        if not any(t.lower().startswith("context") for t in secs):
            warn("board.md has no '## Context' section")
        if len([t for t in secs if not t.lower().startswith("context")]) < 2:
            warn("board.md has fewer than two passes; the stepper needs today plus one per chunk")

    # Staleness: status_date older than the last commit touching the repo.
    try:
        last = subprocess.run(["git", "-C", str(src), "log", "-1", "--format=%cs"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
        if last and str(F.get("status_date", "")) < last:
            warn(f"feature.status_date {F.get('status_date')} is older than the last commit ({last}); run the per-run update")
    except Exception:  # noqa: BLE001
        pass
    return out


# ----------------------------------------------------------------------------
# rendering helpers
# ----------------------------------------------------------------------------

def esc(s):
    return html.escape(str(s if s is not None else ""))


def pill(text, cls="pill--soft"):
    return f'<span class="pill {cls}">{esc(text)}</span>'


def stage_bar(stage):
    idx = STAGES.index(stage)
    return '<div class="stage-bar">' + "".join(
        f'<span class="stg {"done" if i <= idx else ""}" title="{s}">{s}</span>'
        for i, s in enumerate(STAGES)) + "</div>"


def split_sections(md):
    out, title, buf = [], None, []
    for line in md.splitlines():
        if line.startswith("## "):
            if title is not None:
                out.append((title, "\n".join(buf)))
            title, buf = line[3:].strip(), []
        elif line.startswith("# "):
            continue
        else:
            buf.append(line)
    if title is not None:
        out.append((title, "\n".join(buf)))
    return out


def md_block(md):
    safe = md.replace("</script>", "<\\/script>")
    return f'<div class="md"><script type="text/markdown">{safe}</script></div>'


def view_block(views_dir: Path, view_id, caption):
    """A LikeC4 view: the exported PNG when present, else its generated Mermaid, else None."""
    if not view_id:
        return None
    png = views_dir / f"{view_id}.png"
    if png.exists():
        return (f'<figure class="view"><img src="{esc(png.resolve())}" alt="{esc(caption)}">'
                f'<figcaption>{esc(caption)} (LikeC4 view <code class="inline">{esc(view_id)}</code>)</figcaption></figure>')
    mmd = views_dir / f"{view_id}.mmd"
    if mmd.exists():
        body = re.sub(r"^---\n.*?\n---\n", "", mmd.read_text(), count=1, flags=re.S)
        return md_block(f"```mermaid\n{body}\n```\n\n_{caption} (LikeC4 view `{view_id}`)_")
    return None


def chunk_ledger_md(L, cid):
    rows = []
    for p in L.get("pillars") or []:
        if p["chunk"] == cid:
            rows.append(f'| Pillar {p["id"]} | {p["statement"]} | **{p["state"]}** | {p.get("evidence", "")} |')
    for d in L.get("decisions") or []:
        if d["chunk"] == cid:
            rows.append(f'| {d["id"]} | {d["summary"]} | **{d["state"]}** | {d.get("by", "")} |')
    for b in L.get("blockers") or []:
        if b["chunk"] == cid:
            rows.append(f'| Blocker {b["id"]} | {b["what"]} | **owner: {b["owner"]}** | |')
    if not rows:
        return "_Nothing recorded for this chunk._"
    return "| Id | Statement | State | Evidence / by |\n|---|---|---|---|\n" + "\n".join(rows)


def blocked_on_you(L):
    by_id = {c["id"]: c["name"] for c in L["chunks"]}
    rows = []
    for p in L.get("pillars") or []:
        if p["state"] in ("needs-you", "invalidated"):
            rows.append((p["state"], "Pillar " + p["id"], p["statement"], p["chunk"], by_id[p["chunk"]]))
    for d in L.get("decisions") or []:
        if d["state"] in ("needs-you", "recommended"):
            rows.append((d["state"], d["id"], d["summary"], d["chunk"], by_id[d["chunk"]]))
    for b in L.get("blockers") or []:
        if str(b["owner"]).startswith("you"):
            rows.append(("blocker", "Blocker " + b["id"], b["what"], b["chunk"], by_id[b["chunk"]]))
    order = {"invalidated": 0, "needs-you": 1, "blocker": 2, "recommended": 3}
    return sorted(rows, key=lambda r: order.get(r[0], 9))


def changes_since_ack(L):
    ack = L["feature"].get("last_ack")
    rows = L.get("changelog") or []
    if ack:
        rows = [c for c in rows if str(c["date"]) > str(ack)]
    return ack, rows


# ----------------------------------------------------------------------------
# tabs
# ----------------------------------------------------------------------------

def board_tab(L, board_md, views_dir):
    F, M = L["feature"], L.get("metaphor") or {}
    chunks = L["chunks"]
    need = blocked_on_you(L)
    need_rows = "".join(
        f'<tr class="st-{esc(st)}"><td><code class="inline">{esc(i)}</code></td><td>{esc(t)}</td>'
        f'<td><a href="#" data-tab="{esc(cid)}">{esc(cname)}</a></td></tr>'
        for st, i, t, cid, cname in need) or '<tr><td colspan="3" class="muted">Nothing. Keep going.</td></tr>'

    ack, changes = changes_since_ack(L)
    since_hdr = f"Since you last acknowledged ({ack})" if ack else "Never acknowledged. Everything so far"
    since = "".join(f'<li><strong>{esc(c["date"])}</strong> {esc(c["what"])}</li>' for c in changes) or '<li class="muted">Nothing new.</li>'

    grid = ""
    for c in sorted(chunks, key=lambda c: c["review_order"]):
        grid += f'''
        <a class="chunk-card risk-{c["risk"]}" href="#" data-tab="{c["id"]}">
          <div class="chunk-card__top"><h3>{esc(c["name"])}</h3>{pill("risk " + c["risk"])}</div>
          <p>{esc(c["one_liner"])}</p>
          {stage_bar(c["stage"])}
          <div class="chunk-card__note">{esc(c.get("stage_note", ""))}</div>
        </a>'''

    pillars = "".join(
        f'<tr><td><code class="inline">{esc(p["id"])}</code></td><td>{esc(p["statement"])}</td>'
        f'<td>{pill(p["state"], STATE_PILL.get(p["state"], "pill--soft"))}</td><td class="muted">{esc(p.get("evidence", ""))}</td></tr>'
        for p in L.get("pillars") or [])

    review = "".join(
        f'<tr><td>{c["review_order"]}</td><td><a href="#" data-tab="{c["id"]}">{esc(c["name"])}</a></td>'
        f'<td>{esc(c.get("risk_why", ""))}</td><td class="muted">{esc(c.get("size", ""))}</td></tr>'
        for c in sorted(chunks, key=lambda c: c["review_order"]))

    done = "".join(f"<li>{esc(d)}</li>" for d in F.get("done_when") or [])

    secs = split_sections(board_md)
    passes = [(t, b) for t, b in secs if not t.lower().startswith("context")]
    context = [(t, b) for t, b in secs if t.lower().startswith("context")]
    panes = "".join(f'<div class="pane" data-i="{i}"><h3>{esc(t)}</h3>{md_block(b)}</div>' for i, (t, b) in enumerate(passes))
    dots = "".join(f'<button class="dot" data-i="{i}" title="{esc(t)}"></button>' for i, (t, _) in enumerate(passes))
    ctx = view_block(views_dir, F.get("context_view"), "Who talks to whom") or (md_block(context[0][1]) if context else "")
    site = views_dir.parent / "site" / "index.html"
    site_link = f'<p class="muted">Interactive model: <a href="{esc(site.resolve())}">LikeC4 site</a></p>' if site.exists() else ""
    autonomy = F.get("autonomy", "normal")

    return f'''
    <section class="hero card">
      <div class="hero__meta">{pill("status " + str(F.get("status_date", "")), "pill--navy")} {pill("metaphor: " + str(M.get("chosen", "")), "pill--accent")} {pill("branch " + str(F.get("branch", "")) + " @ " + str(F.get("head", "")))} {pill("autonomy " + autonomy)}</div>
      <h1>{esc(F["name"])}: <span class="hl">where we are</span></h1>
      <p class="lead">{esc(F["goal"])}</p>
      <p><strong>The one thing to review:</strong> <a href="{esc(F["artifact_to_review"])}">{esc(F["artifact_to_review"])}</a>{(" &middot; epic <a href=%s>epic</a>" % esc(F["epic"])) if F.get("epic") else ""}</p>
    </section>
    <div class="grid-2">
      <section class="card">
        <h2>🙋 Blocked on <span class="hl">you</span></h2>
        <table class="tbl"><thead><tr><th>Id</th><th>What</th><th>Chunk</th></tr></thead><tbody>{need_rows}</tbody></table>
      </section>
      <section class="card">
        <h2>🕒 {esc(since_hdr)}</h2>
        <ul class="since">{since}</ul>
        <p class="muted">Mark read with <code class="inline">elih ack</code>. Entries older than your ack leave this list.</p>
      </section>
    </div>
    <h2>📦 The chunks, in <span class="hl">review order</span></h2>
    <p class="muted">Stage bar: built → tested → reviewed → merged → deployed. Click a chunk for its page.</p>
    <div class="chunk-grid">{grid}</div>
    <h2>🏛️ Pillars: assumptions that <span class="hl">stop everything</span> if false</h2>
    <section class="card"><table class="tbl"><thead><tr><th>Id</th><th>Pillar</th><th>State</th><th>Evidence</th></tr></thead><tbody>{pillars}</tbody></table></section>
    <h2>🧭 The flow, revealed <span class="hl">one chunk at a time</span></h2>
    <section class="card stepper">
      <div class="stepper__nav"><button class="btn" id="prev">← Back</button><div class="dots">{dots}</div><button class="btn" id="next">Next →</button></div>
      <div class="legend"><span class="sw new"></span> new in this pass <span class="sw earlier"></span> added earlier <span class="sw existing"></span> unchanged <span class="sw legacy"></span> legacy, stays until retired</div>
      {panes}
    </section>
    <h2>🗺️ Context: who talks to <span class="hl">whom</span></h2>
    <section class="card">{ctx}{site_link}</section>
    <h2>🔍 How to <span class="hl">review</span></h2>
    <section class="card"><table class="tbl"><thead><tr><th>#</th><th>Chunk</th><th>What to look for</th><th>Size</th></tr></thead><tbody>{review}</tbody></table></section>
    <h2>🏁 Done <span class="hl">when</span></h2>
    <section class="card"><ol>{done}</ol></section>
    '''


def chunk_tab(L, c, md, views_dir):
    md = md.replace(PLACEHOLDER, chunk_ledger_md(L, c["id"]))
    paths = "".join(f'<li><code class="inline">{esc(p)}</code></li>' for p in c.get("paths") or [])
    where = view_block(views_dir, c.get("context_view"), f'{c["name"]}: where it sits') or ""
    return f'''
    <section class="hero card">
      <div class="hero__meta">{pill("review order " + str(c["review_order"]), "pill--navy")} {pill("risk " + c["risk"], "pill--accent")} {pill(c.get("size", ""))}</div>
      <h1>{esc(c["name"])}</h1>
      <p class="lead">{esc(c["one_liner"])}</p>
      {stage_bar(c["stage"])}
      <p class="muted">{esc(c.get("stage_note", ""))}</p>
      <details><summary>Paths ({len(c.get("paths") or [])})</summary><ul class="paths">{paths}</ul></details>
    </section>
    {('<section class="card">' + where + '</section>') if where else ''}
    <section class="card">{md_block(md)}</section>
    '''


def ledger_tab(L):
    by_id = {c["id"]: c["name"] for c in L["chunks"]}
    dec = "".join(
        f'<tr><td><code class="inline">{esc(d["id"])}</code></td><td>{esc(by_id[d["chunk"]])}</td><td>{esc(d["summary"])}</td>'
        f'<td>{pill(d["state"], STATE_PILL.get(d["state"], "pill--soft"))}</td><td class="muted">{esc(d.get("by", ""))}</td></tr>'
        for d in L.get("decisions") or [])
    blk = "".join(
        f'<tr><td><code class="inline">{esc(b["id"])}</code></td><td>{esc(by_id[b["chunk"]])}</td><td>{esc(b["what"])}</td><td>{esc(b["owner"])}</td></tr>'
        for b in L.get("blockers") or [])
    chg = "".join(f'<li><strong>{esc(c["date"])}</strong> {esc(c["what"])}</li>' for c in L.get("changelog") or [])
    M = L.get("metaphor") or {}
    alts = "".join(f"<li>{esc(a)}</li>" for a in M.get("alternatives_considered") or [])
    return f'''
    <section class="hero card"><h1>Ledger: every <span class="hl">decision</span>, pillar and blocker</h1>
    <p class="lead">States: <strong>approved</strong> you said yes · <strong>recommended</strong> the agent proposed, you have not answered · <strong>assumed</strong> the agent chose and moved on, reversible · <strong>needs-you</strong> cannot proceed past one run without you.</p></section>
    <h2>Decisions and choices</h2>
    <section class="card"><table class="tbl"><thead><tr><th>Id</th><th>Chunk</th><th>Summary</th><th>State</th><th>By</th></tr></thead><tbody>{dec}</tbody></table></section>
    <h2>Blockers</h2>
    <section class="card"><table class="tbl"><thead><tr><th>Id</th><th>Chunk</th><th>What</th><th>Owner</th></tr></thead><tbody>{blk}</tbody></table></section>
    <h2>Changelog</h2>
    <section class="card"><ul>{chg}</ul></section>
    <h2>Metaphor</h2>
    <section class="card"><p><strong>{esc(M.get("chosen", ""))}.</strong> {esc(M.get("rationale", ""))}</p><p class="muted">Also considered:</p><ul>{alts}</ul></section>
    '''


CSS = r'''
    :root{--brand-orange:#EC792B;--brand-navy:#003D67;--bg:#FAF7F2;--surface:#FFF;--surface-2:#F2EDE3;--border:#E8E2D5;--ink:#003D67;--ink-muted:#6B6A66;--orange-soft:#FDF1E7;--orange-hover:#D86919;--font-display:'Montserrat',system-ui,sans-serif;--font-body:'Nunito Sans',system-ui,sans-serif;--shadow-card:0 1px 2px rgba(20,20,19,.04),0 8px 24px rgba(20,20,19,.05)}
    *{box-sizing:border-box}html,body{overflow-x:hidden}
    body{margin:0;background:var(--bg);color:var(--ink);font:400 1rem/1.6 var(--font-body);-webkit-font-smoothing:antialiased}
    a{color:var(--brand-orange);text-decoration:none}a:hover{color:var(--orange-hover);text-decoration:underline}
    h1,h2{font-family:var(--font-display);font-weight:800;letter-spacing:-.01em;margin:0 0 .4em}h3,h4{font-weight:700;margin:0 0 .4em}
    h1{font-size:2rem;line-height:1.2}h2{font-size:1.4rem;line-height:1.25;margin-top:2.25rem}h3{font-size:1.1rem;margin-top:1.5rem}
    .hl{color:var(--brand-orange)}
    header.brand{padding:1.25rem 0;display:flex;align-items:center;justify-content:space-between;gap:1rem;flex-wrap:wrap}
    .page{max-width:1100px;margin:0 auto;padding:1.25rem 1.1rem 4rem}@media(min-width:768px){.page{padding:1.75rem 2rem 5rem}}
    .card{background:var(--surface);border:1px solid var(--border);border-radius:16px;box-shadow:var(--shadow-card);padding:1.25rem;margin:1rem 0}
    @media(min-width:768px){.card{padding:1.75rem}}
    .pill{display:inline-flex;align-items:center;gap:.35em;padding:.3em .7em;border-radius:999px;font-size:.78rem;font-weight:600;line-height:1;margin-right:.35rem}
    .pill--soft{background:var(--surface);color:var(--ink);border:1px solid var(--border)}.pill--accent{background:var(--orange-soft);color:var(--orange-hover);border:1px solid var(--brand-orange)}
    .pill--navy{background:var(--brand-navy);color:#fff;border:1px solid var(--brand-navy)}.pill--warn{background:#F3D9CC;color:#8A3B1E;border:1px solid #D86919}
    code.inline{background:var(--surface-2);border:1px solid var(--border);padding:.1em .4em;border-radius:6px;font-size:.85em;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
    .md code:not(.hljs){background:var(--surface-2);border:1px solid var(--border);padding:.1em .4em;border-radius:6px;font-size:.85em;font-family:ui-monospace,Menlo,monospace}
    .md pre code{background:transparent;border:0;padding:1rem 1.25rem;font-size:.85rem;color:#E8E6DE}
    .grid-2{display:grid;grid-template-columns:1fr;gap:1rem}@media(min-width:800px){.grid-2{grid-template-columns:1fr 1fr}}
    .muted{color:var(--ink-muted);font-size:.9rem}.lead{font-size:1.05rem}
    .tbl{width:100%;border-collapse:collapse;font-size:.92rem}.tbl th{text-align:left;font-weight:700;border-bottom:2px solid var(--border);padding:.5rem .6rem;white-space:nowrap}.tbl td{border-bottom:1px solid var(--border);padding:.5rem .6rem;vertical-align:top}
    .tbl tr.st-invalidated td{background:#F3D9CC}
    .md table{width:100%;border-collapse:collapse;font-size:.92rem;margin:.75rem 0}.md th{text-align:left;border-bottom:2px solid var(--border);padding:.45rem .6rem}.md td{border-bottom:1px solid var(--border);padding:.45rem .6rem;vertical-align:top}
    .md h2{font-size:1.2rem;margin-top:1.75rem;padding-top:1rem;border-top:1px solid var(--border)}.md h2:first-child{border-top:0;margin-top:0;padding-top:0}
    .md .mermaid{display:flex;justify-content:center;background:var(--bg);border-radius:12px;padding:.75rem;margin:.75rem 0}
    .md pre{background:#1B1B1A;border-radius:12px;overflow-x:auto}
    figure.view{margin:0;text-align:center}figure.view img{max-width:100%;border-radius:12px;border:1px solid var(--border)}figure.view figcaption{font-size:.85rem;color:var(--ink-muted);margin-top:.4rem}
    nav.tabs{display:flex;gap:.4rem;flex-wrap:wrap;position:sticky;top:0;background:var(--bg);padding:.6rem 0;z-index:5;border-bottom:1px solid var(--border)}
    nav.tabs button{font:600 .9rem var(--font-body);border:1px solid var(--border);background:var(--surface);color:var(--ink);padding:.45rem .9rem;border-radius:999px;cursor:pointer}
    nav.tabs button.active{background:var(--brand-navy);color:#fff;border-color:var(--brand-navy)}nav.tabs button .n{color:var(--ink-muted);font-size:.75rem;margin-right:.3rem}nav.tabs button.active .n{color:#fff9}
    .tab{display:none}.tab.active{display:block}
    .prerender{display:block!important;position:absolute!important;left:-20000px;top:0;width:1036px}
    .hero .hero__meta{margin-bottom:.75rem}
    .chunk-grid{display:grid;grid-template-columns:1fr;gap:1rem}@media(min-width:720px){.chunk-grid{grid-template-columns:1fr 1fr}}@media(min-width:1000px){.chunk-grid{grid-template-columns:1fr 1fr 1fr}}
    .chunk-card{display:block;background:var(--surface);border:1px solid var(--border);border-left-width:5px;border-radius:16px;box-shadow:var(--shadow-card);padding:1.1rem 1.25rem;color:var(--ink)}
    .chunk-card:hover{text-decoration:none;border-color:var(--brand-orange)}.chunk-card h3{margin:0;font-size:1.05rem}.chunk-card p{font-size:.92rem;margin:.5rem 0}
    .chunk-card__top{display:flex;justify-content:space-between;align-items:center;gap:.5rem}.chunk-card__note{font-size:.8rem;color:var(--ink-muted);margin-top:.5rem}
    .risk-high{border-left-color:var(--orange-hover)}.risk-medium{border-left-color:var(--brand-orange)}.risk-low{border-left-color:var(--border)}
    .stage-bar{display:flex;gap:3px;margin-top:.5rem}.stg{flex:1;text-align:center;font-size:.68rem;text-transform:uppercase;letter-spacing:.04em;padding:.25rem 0;background:var(--surface-2);color:var(--ink-muted);border-radius:4px}.stg.done{background:var(--brand-navy);color:#fff}
    .stepper .pane{display:none}.stepper .pane.active{display:block}.stepper__nav{display:flex;align-items:center;justify-content:space-between;gap:1rem;margin-bottom:.5rem}
    .btn{font:600 .9rem var(--font-body);border:1px solid var(--brand-navy);background:var(--surface);color:var(--brand-navy);padding:.4rem .9rem;border-radius:999px;cursor:pointer}.btn:hover{background:var(--brand-navy);color:#fff}
    .dots{display:flex;gap:.4rem}.dot{width:12px;height:12px;border-radius:50%;border:1px solid var(--brand-navy);background:var(--surface);cursor:pointer;padding:0}.dot.active{background:var(--brand-orange);border-color:var(--brand-orange)}
    .legend{font-size:.8rem;color:var(--ink-muted);margin:.25rem 0 .5rem;display:flex;gap:.5rem;flex-wrap:wrap;align-items:center}.sw{display:inline-block;width:14px;height:14px;border-radius:3px;border:1px solid #003D67;margin-left:.5rem}
    .sw.new{background:#FDF1E7;border-color:#EC792B;border-width:2px}.sw.earlier{background:#F2EDE3}.sw.existing{background:#fff}.sw.legacy{background:#fff;border-style:dashed;border-color:#6B6A66}
    ul.since li{margin:.3rem 0}ul.paths{columns:2;font-size:.85rem}details summary{cursor:pointer;color:var(--brand-orange);font-weight:600}
    footer{margin-top:3.5rem;padding-top:1.25rem;border-top:1px solid var(--border);color:var(--ink-muted);font-size:.875rem}
'''

JS = r'''
    marked.setOptions({gfm:true, breaks:false});
    mermaid.initialize({startOnLoad:false, theme:'base', securityLevel:'loose', themeVariables:{fontFamily:"'Nunito Sans',system-ui,sans-serif",primaryColor:'#FDF1E7',primaryTextColor:'#003D67',primaryBorderColor:'#EC792B',lineColor:'#003D67',secondaryColor:'#F2EDE3',tertiaryColor:'#FFFFFF',noteBkgColor:'#FDF1E7',noteBorderColor:'#EC792B'}, flowchart:{useMaxWidth:true, htmlLabels:true}, sequence:{useMaxWidth:true}});
    document.querySelectorAll('.md').forEach(box => {
      const src = box.querySelector('script[type="text/markdown"]').textContent;
      box.innerHTML = marked.parse(src);
      box.querySelectorAll('pre code.language-mermaid').forEach(code => {
        const d = document.createElement('div'); d.className = 'mermaid'; d.textContent = code.textContent; code.parentElement.replaceWith(d);
      });
      box.querySelectorAll('pre code').forEach(el => hljs.highlightElement(el));
    });
    // Pre-render every diagram once, off-screen but laid out, so tab or stepper
    // switching can never hide a diagram mid-render.
    async function prerenderAll(){
      const hidden = [...document.querySelectorAll('.tab, .stepper .pane')];
      hidden.forEach(el => el.classList.add('prerender'));
      try { await mermaid.run({ nodes: [...document.querySelectorAll('.mermaid')] }); }
      finally { hidden.forEach(el => el.classList.remove('prerender')); }
    }
    const tabs = document.querySelectorAll('.tab'), btns = document.querySelectorAll('nav.tabs button');
    function show(id){
      if (!document.getElementById('tab-' + id)) id = 'board';
      tabs.forEach(t => t.classList.toggle('active', t.id === 'tab-' + id));
      btns.forEach(b => b.classList.toggle('active', b.dataset.tab === id));
      history.replaceState(null, '', '#' + id);
      window.scrollTo({top:0});
    }
    btns.forEach(b => b.addEventListener('click', () => show(b.dataset.tab)));
    document.querySelectorAll('[data-tab]:not(nav button)').forEach(a => a.addEventListener('click', e => { e.preventDefault(); show(a.dataset.tab); }));
    const panes = document.querySelectorAll('.stepper .pane'), dots = document.querySelectorAll('.stepper .dot'); let cur = 0;
    function go(i){ cur = Math.max(0, Math.min(panes.length-1, i)); panes.forEach((p,k)=>p.classList.toggle('active',k===cur)); dots.forEach((d,k)=>d.classList.toggle('active',k===cur)); }
    document.getElementById('prev').onclick = () => go(cur-1); document.getElementById('next').onclick = () => go(cur+1);
    dots.forEach(d => d.onclick = () => go(+d.dataset.i));
    document.addEventListener('keydown', e => { if (e.key === 'ArrowRight') go(cur+1); if (e.key === 'ArrowLeft') go(cur-1); });
    go(0);
    show((location.hash || '#board').slice(1));
    prerenderAll();
'''


def render(src: Path, out: Path, use_likec4: bool = True, png: bool = False) -> Path:
    L = load(src)
    F = L["feature"]
    F["status_date"] = dt.date.today().isoformat()
    set_feature_field(src, "status_date", F["status_date"])
    head = git_head(src)
    if head:
        F["head"] = head
        set_feature_field(src, "head", head)

    views_dir = src / "out" / "views"
    if use_likec4 and (src / "model.c4").exists():
        export_likec4(src, views_dir, png=png)

    board_md = (src / "board.md").read_text()
    chunk_tabs, nav = [], ['<button data-tab="board"><span class="n">L0</span>Board</button>']
    for c in L["chunks"]:
        md = (src / "chunks" / f'{c["id"]}.md').read_text()
        chunk_tabs.append(f'<div class="tab" id="tab-{c["id"]}">{chunk_tab(L, c, md, views_dir)}</div>')
        nav.append(f'<button data-tab="{c["id"]}"><span class="n">{c["review_order"]}</span>{esc(c["name"])}</button>')
    nav.append('<button data-tab="ledger"><span class="n">L1</span>Ledger</button>')

    page = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ELIH: {esc(F["name"])}</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@800&family=Nunito+Sans:wght@400;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11/styles/github-dark.min.css">
<style>{CSS}</style></head>
<body><div class="page">
<header class="brand"><strong>ELIH</strong><span class="muted">explain like I'm human · generated {esc(F["status_date"])} from <code class="inline">{esc(src.name)}/</code></span></header>
<nav class="tabs">{"".join(nav)}</nav>
<div class="tab" id="tab-board">{board_tab(L, board_md, views_dir)}</div>
{"".join(chunk_tabs)}
<div class="tab" id="tab-ledger">{ledger_tab(L)}</div>
<footer>Source: <code class="inline">ledger.yaml</code>, <code class="inline">board.md</code>, <code class="inline">chunks/*.md</code> on branch {esc(F.get("branch", ""))}. Reviewing: <a href="{esc(F["artifact_to_review"])}">{esc(F["artifact_to_review"])}</a>. This HTML is regenerated every run and is never the source of truth.</footer>
</div>
<script src="https://cdn.jsdelivr.net/npm/marked@12/marked.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11/highlight.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>{JS}</script>
</body></html>'''
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)
    return out


def set_feature_field(src: Path, key: str, value: str):
    """Rewrite one `feature.<key>:` line in place, keeping comments and quoting elsewhere."""
    path = src / "ledger.yaml"
    text = path.read_text()
    pat = re.compile(rf"^(\s+{re.escape(key)}:)[^\n]*$", re.M)
    if not pat.search(text):
        sys.exit(f"ledger.yaml has no feature.{key} line to update")
    path.write_text(pat.sub(lambda m: f"{m.group(1)} {value}", text, count=1))


def git_head(src: Path):
    try:
        return subprocess.run(["git", "-C", str(src), "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True, timeout=5).stdout.strip() or None
    except Exception:  # noqa: BLE001
        return None


def export_likec4(src: Path, views_dir: Path, png: bool = False):
    """Generate the model's views. Mermaid needs no browser; PNG needs Playwright's Chromium."""
    if not shutil.which("npx"):
        print("likec4: npx not found; using the Mermaid blocks in board.md and chunk pages", file=sys.stderr)
        return
    views_dir.mkdir(parents=True, exist_ok=True)
    cmd = ["npx", "--yes", "likec4"] + (["export", "png"] if png else ["gen", "mermaid"]) + ["-o", str(views_dir), str(src)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        hint = " Run `npx playwright install chromium` for PNG export." if png and "playwright" in (r.stderr + r.stdout).lower() else ""
        print(f"likec4 {' '.join(cmd[3:5])} failed; falling back to the Mermaid blocks in the source.{hint}\n{r.stderr[-600:]}", file=sys.stderr)


# ----------------------------------------------------------------------------
# init, ack, status
# ----------------------------------------------------------------------------

def init(dest: Path, slug: str, name: str):
    if (dest / "ledger.yaml").exists():
        sys.exit(f"{dest}/ledger.yaml already exists; refusing to overwrite")
    (dest / "chunks").mkdir(parents=True, exist_ok=True)
    today = dt.date.today().isoformat()
    sub = lambda s: s.replace("{{SLUG}}", slug).replace("{{NAME}}", name or slug).replace("{{TODAY}}", today)
    (dest / "ledger.yaml").write_text(sub((TEMPLATES / "ledger.yaml").read_text()))
    (dest / "board.md").write_text((TEMPLATES / "board.md").read_text())
    (dest / "chunks" / "first-chunk.md").write_text((TEMPLATES / "chunk.md").read_text())
    (dest / "model.c4").write_text((TEMPLATES / "model.c4").read_text())
    gi = dest / ".gitignore"
    gi.write_text("out/\n")
    print(f"scaffolded {dest}. Fill ledger.yaml (metaphor, chunks, pillars), board.md, chunks/*.md; then `elih.py lint`.")


def ack(src: Path, date: str):
    set_feature_field(src, "last_ack", date)
    print(f"acknowledged through {date}")


def status(src: Path) -> str:
    L = load(src)
    F = L["feature"]
    lines = [f"# {F['name']} — status {F.get('status_date')} @ {F.get('head')}", "",
             f"Review: {F['artifact_to_review']}", "", "## Blocked on you"]
    need = blocked_on_you(L)
    lines += [f"- [{st}] {i}: {t} ({cname})" for st, i, t, _, cname in need] or ["- nothing"]
    ack_date, changes = changes_since_ack(L)
    lines += ["", f"## Since {'ack ' + ack_date if ack_date else 'the start'}"]
    lines += [f"- {c['date']} {c['what']}" for c in changes] or ["- nothing new"]
    lines += ["", "## Chunks (review order)"]
    for c in sorted(L["chunks"], key=lambda c: c["review_order"]):
        lines.append(f"- {c['review_order']}. {c['name']} [{c['stage']}, risk {c['risk']}]: {c.get('stage_note', '')}")
    lines += ["", "## Pillars"]
    lines += [f"- {p['id']} [{p['state']}] {p['statement']}" for p in L.get("pillars") or []]
    return "\n".join(lines)


# ----------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(prog="elih.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("init"); p.add_argument("dir"); p.add_argument("--feature", required=True); p.add_argument("--name", default="")
    p = sp.add_parser("lint"); p.add_argument("dir")
    p = sp.add_parser("render"); p.add_argument("dir"); p.add_argument("-o", "--out"); p.add_argument("--no-likec4", action="store_true"); p.add_argument("--png", action="store_true", help="export LikeC4 views as PNG (needs Playwright Chromium) instead of Mermaid")
    p = sp.add_parser("ack"); p.add_argument("dir"); p.add_argument("--date", default=dt.date.today().isoformat())
    p = sp.add_parser("status"); p.add_argument("dir")
    a = ap.parse_args(argv)
    src = Path(a.dir).resolve()

    if a.cmd == "init":
        init(src, a.feature, a.name)
        return 0
    if a.cmd == "lint":
        findings = lint(src)
        for level, msg in findings:
            print(f"{level}: {msg}")
        errors = [f for f in findings if f[0] == "error"]
        print(f"{len(errors)} error(s), {len(findings) - len(errors)} warning(s)")
        return 1 if errors else 0
    if a.cmd == "render":
        errors = [m for lvl, m in lint(src) if lvl == "error"]
        if errors:
            print("\n".join("error: " + e for e in errors)); return 1
        out = Path(a.out) if a.out else src / "out" / "index.html"
        path = render(src, out, use_likec4=not a.no_likec4, png=a.png)
        print(path)
        return 0
    if a.cmd == "ack":
        ack(src, a.date)
        return 0
    if a.cmd == "status":
        print(status(src))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
