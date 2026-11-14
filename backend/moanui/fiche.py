"""Modèle commun des fiches méthode : un document structuré rendu en Markdown, en HTML imprimable et en ZIP.

Structure inspirée des sections « Matériel et méthodes » des rapports scientifiques : identification,
données, méthode, résultats (avec figures), limites, références, annexe de reproductibilité.

- Markdown : figures en fichiers SVG à côté (`figures/…svg`), lisible dans n'importe quel éditeur.
- HTML : un seul fichier, figures intégrées, mise en page A4 pour « Imprimer en PDF ».
- ZIP : le Markdown, le HTML et le dossier `figures/`.
"""

from __future__ import annotations

import io
import re
import zipfile
from dataclasses import dataclass, field
from datetime import datetime
from html import escape

from .biblio import REFS, refs_md


@dataclass
class Fiche:
    title: str
    subtitle: str = ""
    meta: list[tuple[str, str]] = field(default_factory=list)
    blocks: list[tuple] = field(default_factory=list)
    refs: list[str] = field(default_factory=list)
    _n: int = 0
    _fig: int = 0
    _tab: int = 0

    # ------------------------------------------------------------------ construction
    def h(self, text: str, numbered: bool = True) -> "Fiche":
        if numbered:
            self._n += 1
            text = f"{self._n}. {text}"
        self.blocks.append(("h2", text))
        return self

    def h3(self, text: str) -> "Fiche":
        self.blocks.append(("h3", text))
        return self

    def p(self, text: str) -> "Fiche":
        if text:
            self.blocks.append(("p", text))
        return self

    def ul(self, items: list[str]) -> "Fiche":
        items = [i for i in items if i]
        if items:
            self.blocks.append(("ul", items))
        return self

    def ol(self, items: list[str]) -> "Fiche":
        if items:
            self.blocks.append(("ol", items))
        return self

    def table(self, headers: list[str], rows: list[list], caption: str = "", align: str | None = None) -> "Fiche":
        """align : une lettre par colonne, l (gauche) ou r (droite)."""
        if rows:
            self._tab += 1
            cap = f"Tableau {self._tab}. {caption}" if caption else ""
            self.blocks.append(("table", headers, [[("" if c is None else str(c)) for c in r] for r in rows], cap,
                                align or "l" * len(headers)))
        return self

    def kv(self, rows: list[tuple[str, str]]) -> "Fiche":
        rows = [(k, v) for k, v in rows if v not in (None, "")]
        if rows:
            self.blocks.append(("kv", rows))
        return self

    def fig(self, name: str, svg: str | None, caption: str) -> "Fiche":
        if svg:
            self._fig += 1
            self.blocks.append(("fig", name, svg, f"Figure {self._fig}. {caption}"))
        return self

    def note(self, text: str) -> "Fiche":
        self.blocks.append(("note", text))
        return self

    def code(self, text: str, lang: str = "") -> "Fiche":
        self.blocks.append(("code", text, lang))
        return self

    def cite(self, *keys: str) -> str:
        """Ajoute des références et renvoie l'appel de citation « (Auteur, année) »."""
        out = []
        for k in keys:
            if k in REFS:
                if k not in self.refs:
                    self.refs.append(k)
                out.append(_short(REFS[k]))
        return f"({' ; '.join(out)})" if out else ""

    # ------------------------------------------------------------------ rendus
    def markdown(self, fig_dir: str = "figures") -> str:
        L = [f"# {self.title}", ""]
        if self.subtitle:
            L += [self.subtitle, ""]
        if self.meta:
            L += ["| | |", "|---|---|"] + [f"| {k} | {_cell(v)} |" for k, v in self.meta] + [""]
        for b in self.blocks:
            t = b[0]
            if t == "h2":
                L += [f"## {b[1]}", ""]
            elif t == "h3":
                L += [f"### {b[1]}", ""]
            elif t == "p":
                L += [b[1], ""]
            elif t == "note":
                L += ["> " + b[1].replace("\n", "\n> "), ""]
            elif t == "ul":
                L += [f"- {i}" for i in b[1]] + [""]
            elif t == "ol":
                L += [f"{n}. {i}" for n, i in enumerate(b[1], 1)] + [""]
            elif t == "kv":
                L += ["| | |", "|---|---|"] + [f"| **{k}** | {_cell(v)} |" for k, v in b[1]] + [""]
            elif t == "table":
                _, hd, rows, cap, al = b
                if cap:
                    L += [f"*{cap}*", ""]
                L.append("| " + " | ".join(hd) + " |")
                L.append("|" + "|".join("---:" if a == "r" else "---" for a in al) + "|")
                L += ["| " + " | ".join(_cell(c) for c in r) + " |" for r in rows]
                L.append("")
            elif t == "fig":
                _, name, _svg, cap = b
                L += [f"![{cap}]({fig_dir}/{name}.svg)", "", f"*{cap}*", ""]
            elif t == "code":
                L += [f"```{b[2]}", b[1], "```", ""]
        if self.refs:
            L += ["## Références", ""] + refs_md(self.refs) + [""]
        L.append(f"*Fiche générée par Moanui le {datetime.now().strftime('%d/%m/%Y à %H:%M')}.*")
        return "\n".join(L)

    def figures(self) -> dict[str, str]:
        return {b[1]: b[2] for b in self.blocks if b[0] == "fig"}

    def html(self) -> str:
        H = [f"<h1>{escape(self.title)}</h1>"]
        if self.subtitle:
            H.append(f'<p class="sub">{_inline(self.subtitle)}</p>')
        if self.meta:
            H.append('<table class="meta">' + "".join(f"<tr><th>{escape(k)}</th><td>{_inline(v)}</td></tr>" for k, v in self.meta)
                     + "</table>")
        for b in self.blocks:
            t = b[0]
            if t == "h2":
                H.append(f"<h2>{escape(b[1])}</h2>")
            elif t == "h3":
                H.append(f"<h3>{escape(b[1])}</h3>")
            elif t == "p":
                H.append(f"<p>{_inline(b[1])}</p>")
            elif t == "note":
                H.append(f'<div class="note">{_inline(b[1])}</div>')
            elif t in ("ul", "ol"):
                H.append(f"<{t}>" + "".join(f"<li>{_inline(i)}</li>" for i in b[1]) + f"</{t}>")
            elif t == "kv":
                H.append('<table class="kv">' + "".join(f"<tr><th>{escape(k)}</th><td>{_inline(v)}</td></tr>" for k, v in b[1])
                         + "</table>")
            elif t == "table":
                _, hd, rows, cap, al = b
                cls = lambda i: ' class="r"' if i < len(al) and al[i] == "r" else ""  # noqa: E731
                H.append("<table class='data'>" + (f"<caption>{escape(cap)}</caption>" if cap else "")
                         + "<thead><tr>" + "".join(f"<th{cls(i)}>{escape(h)}</th>" for i, h in enumerate(hd)) + "</tr></thead><tbody>"
                         + "".join("<tr>" + "".join(f"<td{cls(i)}>{_inline(c)}</td>" for i, c in enumerate(r)) + "</tr>"
                                   for r in rows) + "</tbody></table>")
            elif t == "fig":
                _, _name, svg, cap = b
                H.append(f'<figure>{svg}<figcaption>{escape(cap)}</figcaption></figure>')
            elif t == "code":
                H.append(f"<pre><code>{escape(b[1])}</code></pre>")
        if self.refs:
            H.append("<h2>Références</h2><ul class='refs'>"
                     + "".join(f"<li>{escape(r[2:])}</li>" for r in refs_md(self.refs)) + "</ul>")
        H.append(f'<p class="foot">Fiche générée par Moanui le {datetime.now().strftime("%d/%m/%Y à %H:%M")}.</p>')
        return HTML_HEAD.replace("{title}", escape(self.title)) + "\n".join(H) + "</main></body></html>"

    def zip(self, base: str) -> bytes:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr(f"{base}.md", self.markdown())
            z.writestr(f"{base}.html", self.html())
            for name, svg in self.figures().items():
                z.writestr(f"figures/{name}.svg", svg)
        return buf.getvalue()


def _short(ref: str) -> str:
    """« Holm S. (1979). … » → « Holm, 1979 » ; deux auteurs « A et B », plus « A et al. »."""
    m = re.match(r"^(.*?)\((\d{4}[a-z]?)\)", ref)
    if not m:
        d = re.match(r"^(.*?\d{4}(?:/\d+)?)", ref)  # textes réglementaires : « Loi n° 51-711 du 7 juin 1951 »
        return d.group(1) if d else ref.split(".")[0]
    authors, year = m.group(1).strip().rstrip(","), m.group(2)
    parts = re.split(r",\s(?=[A-ZÀ-Ý][A-Za-zà-ÿ'\-]+(?: [A-ZÀ-Ý][A-Za-zà-ÿ'\-]+)? [A-Z]\.)", authors)
    names = []
    for a in parts:
        m2 = re.match(r"^(.+?) [A-Z]\.", a.strip())
        names.append((m2.group(1) if m2 else a.strip().split(" ")[0]).rstrip(","))
    if "et al" in authors or len(names) > 2:
        return f"{names[0]} et al., {year}"
    if len(names) == 2:
        return f"{names[0]} et {names[1]}, {year}"
    return f"{names[0]}, {year}"


def _cell(v) -> str:
    return str(v).replace("|", "\\|").replace("\n", " ")


def _inline(text: str) -> str:
    """Mise en forme minimale : **gras**, *italique*, `code`."""
    s = escape(str(text))
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return s


HTML_HEAD = """<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title><style>
@page { size: A4; margin: 18mm 16mm; }
:root { --ink:#1c2430; --muted:#5f6b7a; --line:#dde2e8; --soft:#f6f7f9; --accent:#2f4858; }
* { box-sizing: border-box; }
body { margin:0; background:#fff; color:var(--ink); font: 14px/1.55 'IBM Plex Sans','Segoe UI',Arial,sans-serif; }
main { max-width: 820px; margin: 0 auto; padding: 32px 28px 48px; }
h1 { font-size: 24px; line-height:1.25; margin: 0 0 4px; font-weight: 600; }
.sub { color: var(--muted); margin: 0 0 18px; }
h2 { font-size: 17px; font-weight: 600; margin: 28px 0 10px; padding-bottom: 4px; border-bottom: 1px solid var(--line); color: var(--accent); }
h3 { font-size: 14.5px; font-weight: 600; margin: 18px 0 6px; }
p { margin: 0 0 10px; }
ul, ol { margin: 0 0 12px; padding-left: 22px; } li { margin: 2px 0; }
table { border-collapse: collapse; width: 100%; margin: 6px 0 14px; font-size: 13px; }
th, td { text-align: left; padding: 5px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
thead th { font-weight: 600; border-bottom: 1.5px solid var(--ink); }
td.r, th.r { text-align: right; font-variant-numeric: tabular-nums; }
caption { caption-side: top; text-align: left; font-size: 12.5px; color: var(--muted); padding-bottom: 4px; font-style: italic; }
table.meta, table.kv { width: auto; min-width: 60%; }
table.meta th, table.kv th { color: var(--muted); font-weight: 500; padding-right: 24px; white-space: nowrap; }
figure { margin: 10px 0 18px; page-break-inside: avoid; }
figure svg { max-width: 100%; height: auto; display: block; border: 1px solid var(--line); }
figcaption { font-size: 12.5px; color: var(--muted); margin-top: 6px; font-style: italic; }
.note { border-left: 3px solid var(--accent); background: var(--soft); padding: 8px 12px; margin: 8px 0 14px; }
pre { background: var(--soft); padding: 10px; font: 11.5px/1.45 'IBM Plex Mono',Consolas,monospace; white-space: pre-wrap; word-break: break-word; }
code { font-family: 'IBM Plex Mono',Consolas,monospace; font-size: 0.92em; }
.refs li { margin: 4px 0; padding-left: 0; }
.foot { color: var(--muted); font-size: 12px; margin-top: 28px; }
@media print { main { padding: 0; } h2 { page-break-after: avoid; } }
</style></head><body><main>
"""
