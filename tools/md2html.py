#!/usr/bin/env python3 -I
"""Tiny Markdown → HTML for the bundled user guide (headings, lists, tables, quotes, code, bold/italic)."""
import html, re, sys

def inline(t):
    t = html.escape(t)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", t)
    return t

def convert(md):
    out, lines, i = [], md.splitlines(), 0
    while i < len(lines):
        l = lines[i]
        if l.startswith("#"):
            n = len(l) - len(l.lstrip("#")); out.append(f"<h{n}>{inline(l[n:].strip())}</h{n}>")
        elif l.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip("|").split("|")]
                if not all(set(c) <= set("-: ") for c in cells): rows.append(cells)
                i += 1
            out.append("<table>" + "".join(
                "<tr>" + "".join(f"<{'th' if r == 0 else 'td'}>{inline(c)}</{'th' if r == 0 else 'td'}>" for c in row) + "</tr>"
                for r, row in enumerate(rows)) + "</table>")
            continue
        elif re.match(r"^(- |\d+\. )", l):
            tag = "ol" if l[0].isdigit() else "ul"; items = []
            while i < len(lines) and re.match(r"^(- |\d+\. )", lines[i]):
                items.append(re.sub(r"^(- |\d+\. )", "", lines[i])); i += 1
            out.append(f"<{tag}>" + "".join(f"<li>{inline(x)}</li>" for x in items) + f"</{tag}>")
            continue
        elif l.startswith(">"):
            out.append(f"<blockquote>{inline(l.lstrip('> '))}</blockquote>")
        elif l.strip():
            out.append(f"<p>{inline(l)}</p>")
        i += 1
    return "\n".join(out)

src, dst, title = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "HeadEQ"
body = convert(open(src, encoding="utf-8").read())
css = """:root{color-scheme:light dark;--fg:#1d1d1f;--bg:#fff;--muted:#6e6e73;--line:#d2d2d7;--accent:#0a84ff}
@media(prefers-color-scheme:dark){:root{--fg:#f5f5f7;--bg:#1c1c1e;--muted:#a1a1a6;--line:#3a3a3c}}
body{font:16px/1.55 -apple-system,system-ui,sans-serif;color:var(--fg);background:var(--bg);max-width:760px;margin:40px auto;padding:0 20px}
h1{font-size:2.1em;margin-bottom:.2em}h2{margin-top:1.8em;border-bottom:1px solid var(--line);padding-bottom:.2em}
table{border-collapse:collapse;width:100%}td,th{border:1px solid var(--line);padding:6px 10px;text-align:left;vertical-align:top}
th{background:color-mix(in srgb,var(--accent) 10%,transparent)}code{font:14px ui-monospace,monospace}
blockquote{margin:1em 0;padding:.6em 1em;border-left:4px solid var(--accent);color:var(--muted)}"""
open(dst, "w", encoding="utf-8").write(f"<!doctype html><html><head><meta charset=utf-8><meta name=viewport content='width=device-width'><title>{title}</title><style>{css}</style></head><body>{body}</body></html>")
