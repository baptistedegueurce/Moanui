"""Construit le guide utilisateur en Word et en PDF à partir de docs/guide/guide.md.

    cd backend && uv run python ../outils/construire_guide.py          -> docs/guide/Moanui-guide.docx et .pdf

Le guide n'est pas inclus dans l'exécutable : il est rédigé et construit dans le dépôt, puis diffusé à part.

Syntaxe de la source (Markdown lisible sur GitHub, avec quelques conventions) :
  <!-- preface -->…<!-- /preface -->      avant-propos placé avant la table des matières
  # Partie 1 : Titre                     page d'intercalaire
  ## 1. Titre / ### 1.1. Titre / #### 1.1.a. Titre   chapitres, sections, sous-sections
  ![Légende](images/nom.png)             figure numérotée automatiquement (« Figure n. Légende »)
  ![Légende](images/nom.png "0.6")       même chose, à 60 % de la largeur
  Tableau : légende                      ligne juste avant un tableau Markdown : tableau numéroté
  > texte                                encadré (conseil, attention)
  <!-- saut -->                          saut de page
"""

from __future__ import annotations

import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))

from moanui import __version__  # noqa: E402
from moanui.documents import DocOptions, to_docx, to_pdf  # noqa: E402

GUIDE = ROOT / "docs" / "guide"
MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre",
        "décembre"]


def optimise(path: Path, max_width: int = 2200) -> bytes:
    """Allège une capture d'écran (palette de 256 couleurs, largeur bornée), une fois pour toutes, sur le disque."""
    from PIL import Image

    with Image.open(path) as im:
        if im.mode == "P" and im.width <= max_width:
            return path.read_bytes()
        im = im.convert("RGB")
        if im.width > max_width:
            im = im.resize((max_width, round(im.height * max_width / im.width)), Image.LANCZOS)
        im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)
    return path.read_bytes()


def parse(md: str) -> tuple[list[tuple], list[tuple]]:
    preface, blocks = [], []
    cur = blocks
    fig = tab = 0
    lines = md.splitlines()
    i = 0
    para: list[str] = []
    pending_caption = ""

    def flush():
        nonlocal para
        if para:
            cur.append(("p", " ".join(x.strip() for x in para)))
            para = []

    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s == "<!-- preface -->":
            flush()
            cur = preface
        elif s == "<!-- /preface -->":
            flush()
            cur = blocks
        elif s == "<!-- saut -->":
            flush()
            cur.append(("pagebreak",))
        elif s.startswith("<!--"):
            flush()
            while "-->" not in lines[i]:
                i += 1
        elif not s:
            flush()
        elif s.startswith("# "):
            flush()
            cur.append(("part", s[2:].strip()))
        elif s.startswith("#### "):
            flush()
            cur.append(("h3", s[5:].strip()))
        elif s.startswith("### "):
            flush()
            cur.append(("h2", s[4:].strip()))
        elif s.startswith("## "):
            flush()
            cur.append(("h1", s[3:].strip()))
        elif m := re.match(r'^!\[(.+?)\]\((\S+?)(?:\s+"([\d.]+)")?\)$', s):
            flush()
            fig += 1
            path = GUIDE / m.group(2)
            if not path.exists():
                raise SystemExit(f"Image manquante : {path}")
            cur.append(("img", optimise(path), f"Figure {fig}. {m.group(1)}", float(m.group(3) or 1.0)))
        elif s.startswith("Tableau :"):
            flush()
            pending_caption = s.split(":", 1)[1].strip()
        elif s.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            i -= 1
            head, sep, body = rows[0], rows[1], rows[2:]
            align = "".join("r" if c.endswith(":") and not c.startswith(":") else "l" for c in sep)
            cap = ""
            if pending_caption:
                tab += 1
                cap = f"Tableau {tab}. {pending_caption}"
                pending_caption = ""
            cur.append(("table", head, body, cap, align))
        elif s.startswith("> "):
            flush()
            note = [s[2:]]
            while i + 1 < len(lines) and lines[i + 1].strip().startswith(">"):
                i += 1
                note.append(lines[i].strip()[1:].strip())
            cur.append(("note", " ".join(note)))
        elif re.match(r"^[-*] ", s):
            flush()
            items = []
            while i < len(lines) and re.match(r"^\s*[-*] ", lines[i]):
                items.append(re.sub(r"^\s*[-*] ", "", lines[i]).strip())
                i += 1
                while i < len(lines) and lines[i].startswith("  ") and lines[i].strip() and not re.match(r"^\s*[-*] ", lines[i]):
                    items[-1] += " " + lines[i].strip()
                    i += 1
            i -= 1
            cur.append(("ul", items))
        elif re.match(r"^\d+\. ", s):
            flush()
            items = []
            while i < len(lines) and re.match(r"^\s*\d+\. ", lines[i]):
                items.append(re.sub(r"^\s*\d+\. ", "", lines[i]).strip())
                i += 1
                while i < len(lines) and lines[i].startswith("   ") and lines[i].strip() and not re.match(r"^\s*\d+\. ", lines[i]):
                    items[-1] += " " + lines[i].strip()
                    i += 1
            i -= 1
            cur.append(("ol", items))
        else:
            para.append(s)
        i += 1
    flush()
    return preface, blocks


def main() -> None:
    md = (GUIDE / "guide.md").read_text(encoding="utf-8")
    preface, blocks = parse(md)
    today = date.today()
    version = __version__.split("-dev")[0].replace(".dev0", "")
    cover_img = GUIDE / "images" / "couverture.png"
    opts = DocOptions(
        title="Moanui : guide d'utilisation",
        cover={"title": "MOANUI", "subtitle": "Guide d'utilisation", "version": f"Version {version}",
               "date": f"{MOIS[today.month - 1].capitalize()} {today.year}", "org": "CRPMEM Bretagne",
               "author": "Rédigé par : Baptiste Degueurce",
               "image": cover_img.read_bytes() if cover_img.exists() else None},
        toc=True, figure_index=True, running_title="Moanui · Guide d'utilisation", preface=preface)
    (GUIDE / "Moanui-guide.docx").write_bytes(to_docx(blocks, opts))
    (GUIDE / "Moanui-guide.pdf").write_bytes(to_pdf(blocks, opts))
    n_fig = sum(1 for b in blocks if b[0] == "img")
    n_tab = sum(1 for b in blocks if b[0] == "table" and b[3])
    print(f"Guide construit : {n_fig} figures, {n_tab} tableaux -> {GUIDE}")


if __name__ == "__main__":
    main()
