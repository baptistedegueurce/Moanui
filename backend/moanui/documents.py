"""Export des documents (fiches méthode, rapports, guide) en Word (.docx) et en PDF.

Les deux rendus partent de la même liste de blocs que `fiche.Fiche` :
  ("h1", texte) chapitre · ("h2", texte) · ("h3", texte) · ("p", texte) · ("ul", [..]) · ("ol", [..])
  ("kv", [(clé, valeur)]) · ("table", entêtes, lignes, légende, alignements) · ("fig", nom, svg, légende)
  ("img", png, légende, largeur_relative) · ("note", texte) · ("code", texte, langage)
  ("part", titre) page d'intercalaire · ("pagebreak",)
Mise en forme dans le texte : **gras**, *italique*, `code`.

Les figures SVG sont converties en PNG (resvg, polices IBM Plex embarquées : rendu identique sur tous les postes).
Aucune dépendance externe (ni Word, ni LibreOffice, ni navigateur).
"""

from __future__ import annotations

import io
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

FONTS = Path(__file__).parent / "polices"
NAVY = (0x1F, 0x38, 0x64)  # bleu marine des titres (proche du guide d'origine)
MUTED = (0x5F, 0x6B, 0x7A)
LINE = (0xDD, 0xE2, 0xE8)
SOFT = (0xF4, 0xF6, 0xF9)


@dataclass
class DocOptions:
    title: str
    subtitle: str = ""
    meta: list[tuple[str, str]] = field(default_factory=list)
    refs: list[str] = field(default_factory=list)  # références déjà mises en forme
    footer: str = ""  # ligne de pied (ex. « Fiche générée par Moanui le … »)
    cover: dict | None = None  # page de garde : title, subtitle, version, date, org, author, image (png)
    toc: bool = False  # table des matières
    figure_index: bool = False  # index des figures et tableaux en fin de document
    running_title: str = ""  # titre courant en haut des pages
    preface: list = field(default_factory=list)  # blocs placés avant la table des matières (avant-propos)


# ---------------------------------------------------------------------------------------------- utilitaires
def svg_to_png(svg: str, zoom: float = 2.0) -> bytes:
    import resvg_py

    out = resvg_py.svg_to_bytes(svg_string=svg, font_dirs=[str(FONTS)], skip_system_fonts=True,
                                font_family="IBM Plex Sans", sans_serif_family="IBM Plex Sans",
                                monospace_family="IBM Plex Mono", zoom=zoom, background="#ffffff")
    return bytes(out)


def png_size(png: bytes) -> tuple[int, int]:
    from PIL import Image

    with Image.open(io.BytesIO(png)) as im:
        return im.size


_TOKEN = re.compile(r"(\*\*.+?\*\*|`[^`]+`|(?<![\w*])\*(?!\s).+?(?<!\s)\*(?![\w*]))")


def runs(text: str) -> list[tuple[str, bool, bool, bool]]:
    """Découpe « **gras**, *italique*, `code` » en morceaux (texte, gras, italique, code)."""
    out = []
    for part in _TOKEN.split(str(text)):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**") and len(part) > 4:
            out.append((part[2:-2], True, False, False))
        elif part.startswith("`") and part.endswith("`") and len(part) > 2:
            out.append((part[1:-1], False, False, True))
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            out.append((part[1:-1], False, True, False))
        else:
            out.append((part, False, False, False))
    return out


def plain(text: str) -> str:
    return "".join(r[0] for r in runs(text))


def _figure_png(b: tuple) -> tuple[bytes, str, float]:
    if b[0] == "fig":
        return svg_to_png(b[2]), b[3], 1.0
    return b[1], b[2], (b[3] if len(b) > 3 and b[3] else 1.0)


def _captions(blocks: list[tuple]) -> tuple[list[str], list[str]]:
    figs, tabs = [], []
    for b in blocks:
        if b[0] in ("fig", "img") and (b[3] if b[0] == "fig" else b[2]):
            figs.append(b[3] if b[0] == "fig" else b[2])
        elif b[0] == "table" and b[3]:
            tabs.append(b[3])
    return figs, tabs


# ---------------------------------------------------------------------------------------------- Word
def _levels(blocks: list[tuple]) -> dict[str, int]:
    """h1 = chapitre si présent ; sinon h2 devient le premier niveau (fiches)."""
    deep = any(b[0] == "h1" for b in blocks)
    return {"h1": 1, "h2": 2 if deep else 1, "h3": 3 if deep else 2}


def to_docx(blocks: list[tuple], o: DocOptions) -> bytes:
    from docx import Document
    from docx.enum.section import WD_SECTION
    from docx.enum.table import WD_TABLE_ALIGNMENT
    from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
    from docx.oxml import OxmlElement
    from docx.oxml.ns import qn
    from docx.shared import Cm, Pt, RGBColor

    levels = _levels(blocks)
    doc = Document()
    sec = doc.sections[0]
    sec.page_height, sec.page_width = Cm(29.7), Cm(21.0)
    for side in ("left_margin", "right_margin"):
        setattr(sec, side, Cm(2.2))
    sec.top_margin, sec.bottom_margin = Cm(2.0), Cm(2.0)
    usable = sec.page_width - sec.left_margin - sec.right_margin

    st = doc.styles
    st["Normal"].font.name = "Calibri"
    st["Normal"].font.size = Pt(11)
    st["Normal"].paragraph_format.space_after = Pt(6)
    st["Normal"].paragraph_format.line_spacing = 1.15
    for name, size in (("Title", 26), ("Heading 1", 18), ("Heading 2", 14), ("Heading 3", 12)):
        s = st[name]
        s.font.name = "Calibri"
        s.font.size = Pt(size)
        s.font.bold = True
        s.font.color.rgb = RGBColor(*NAVY)
    cap = st["Caption"]
    cap.font.italic = True
    cap.font.size = Pt(9.5)
    cap.font.color.rgb = RGBColor(*MUTED)

    def add_runs(par, text, size=None, color=None):
        for t, bold, ital, code in runs(text):
            r = par.add_run(t)
            r.bold = bold or None
            r.italic = ital or None
            if code:
                r.font.name = "Consolas"
            if size:
                r.font.size = Pt(size)
            if color:
                r.font.color.rgb = RGBColor(*color)
        return par

    def field(par, instr: str, result: str = ""):
        r = par.add_run()
        b = OxmlElement("w:fldChar")
        b.set(qn("w:fldCharType"), "begin")
        r._r.append(b)
        r2 = par.add_run()
        it = OxmlElement("w:instrText")
        it.set(qn("xml:space"), "preserve")
        it.text = f" {instr} "
        r2._r.append(it)
        r3 = par.add_run()
        s = OxmlElement("w:fldChar")
        s.set(qn("w:fldCharType"), "separate")
        r3._r.append(s)
        par.add_run(result)
        r4 = par.add_run()
        e = OxmlElement("w:fldChar")
        e.set(qn("w:fldCharType"), "end")
        r4._r.append(e)

    def shade(cell, hexcolor: str):
        tcPr = cell._tc.get_or_add_tcPr()
        sh = OxmlElement("w:shd")
        sh.set(qn("w:val"), "clear")
        sh.set(qn("w:color"), "auto")
        sh.set(qn("w:fill"), hexcolor)
        tcPr.append(sh)

    def caption(text: str, kind: str):
        m = re.match(rf"^{kind} (\d+)[.:] ?(.*)$", text)
        par = doc.add_paragraph(style="Caption")
        if m:
            par.add_run(f"{kind} ")
            field(par, f"SEQ {kind} \\* ARABIC", m.group(1))
            par.add_run(f" : {m.group(2)}")
        else:
            par.add_run(text)
        par.paragraph_format.keep_with_next = kind == "Tableau"
        return par

    # pied de page : numéro de page
    fp = sec.footer.paragraphs[0]
    fp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    field(fp, "PAGE", "1")
    if o.running_title:
        hp = sec.header.paragraphs[0]
        hp.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        add_runs(hp, o.running_title, size=8.5, color=MUTED)

    # page de garde
    if o.cover:
        c = o.cover
        sec.different_first_page_header_footer = True
        p = doc.add_paragraph()
        r = p.add_run(c.get("title", o.title))
        r.bold, r.font.size, r.font.color.rgb = True, Pt(40), RGBColor(*NAVY)
        for line, size in ((c.get("subtitle", ""), 16), (c.get("version", ""), 16)):
            if line:
                q = doc.add_paragraph()
                rr = q.add_run(line)
                rr.bold, rr.font.size, rr.font.color.rgb = True, Pt(size), RGBColor(*NAVY)
        if c.get("image"):
            q = doc.add_paragraph()
            q.alignment = WD_ALIGN_PARAGRAPH.RIGHT
            iw, ih = png_size(c["image"])
            q.add_run().add_picture(io.BytesIO(c["image"]), height=Cm(min(11.0, 7.0 * ih / iw)))
        else:
            for _ in range(6):
                doc.add_paragraph()
        _ = WD_TABLE_ALIGNMENT
        band = doc.add_table(rows=1, cols=1)
        cell = band.rows[0].cells[0]
        shade(cell, "%02X%02X%02X" % NAVY)
        first = True
        for line, bold in ((c.get("date", ""), False), ("", False), (c.get("org", ""), True), (c.get("author", ""), True)):
            q = cell.paragraphs[0] if first else cell.add_paragraph()
            first = False
            rr = q.add_run(line)
            rr.bold, rr.font.size, rr.font.color.rgb = bold, Pt(13), RGBColor(0xFF, 0xFF, 0xFF)
        for _ in range(8):
            cell.add_paragraph()
        doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
    else:
        doc.add_paragraph(o.title, style="Title")
        if o.subtitle:
            add_runs(doc.add_paragraph(), o.subtitle, color=MUTED)
        if o.meta:
            t = doc.add_table(rows=0, cols=2)
            t.style = "Table Grid"
            for k, v in o.meta:
                cells = t.add_row().cells
                add_runs(cells[0].paragraphs[0], k, color=MUTED)
                add_runs(cells[1].paragraphs[0], v)
            doc.add_paragraph()

    def emit(blocks):
        for b in blocks:
            t = b[0]
            if t == "part":
                doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
                for _ in range(10):
                    doc.add_paragraph()
                p = doc.add_paragraph()
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                r = p.add_run(plain(b[1]))
                r.bold, r.font.size, r.font.color.rgb = True, Pt(30), RGBColor(*NAVY)
                doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
            elif t == "pagebreak":
                doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
            elif t in ("h1", "h2", "h3"):
                doc.add_heading(plain(b[1]), level=levels[t])
            elif t == "p":
                p = add_runs(doc.add_paragraph(), b[1])
                p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            elif t in ("ul", "ol"):
                style = "List Bullet" if t == "ul" else "List Number"
                for item in b[1]:
                    add_runs(doc.add_paragraph(style=style), item)
            elif t == "note":
                tb = doc.add_table(rows=1, cols=1)
                shade(tb.rows[0].cells[0], "%02X%02X%02X" % SOFT)
                add_runs(tb.rows[0].cells[0].paragraphs[0], b[1])
                doc.add_paragraph()
            elif t == "code":
                p = doc.add_paragraph()
                r = p.add_run(b[1])
                r.font.name, r.font.size = "Consolas", Pt(8.5)
            elif t == "kv":
                tb = doc.add_table(rows=0, cols=2)
                tb.style = "Table Grid"
                for k, v in b[1]:
                    cells = tb.add_row().cells
                    add_runs(cells[0].paragraphs[0], k).runs[0].bold = True
                    add_runs(cells[1].paragraphs[0], v)
                doc.add_paragraph()
            elif t == "table":
                _, hd, rows, cap_, al = b
                if cap_:
                    caption(cap_, "Tableau")
                tb = doc.add_table(rows=1, cols=len(hd))
                tb.style = "Table Grid"
                for i, h in enumerate(hd):
                    c = tb.rows[0].cells[i]
                    shade(c, "%02X%02X%02X" % SOFT)
                    rr = c.paragraphs[0].add_run(plain(h))
                    rr.bold, rr.font.size = True, Pt(9.5)
                for row in rows:
                    cells = tb.add_row().cells
                    for i, v in enumerate(row):
                        par = cells[i].paragraphs[0]
                        add_runs(par, v, size=9.5)
                        if i < len(al) and al[i] == "r":
                            par.alignment = WD_ALIGN_PARAGRAPH.RIGHT
                doc.add_paragraph()
            elif t in ("fig", "img"):
                png, cap_, rel = _figure_png(b)
                w, h = png_size(png)
                width = int(usable * rel)
                max_h = Cm(19)
                if width * h / w > max_h:
                    width = int(max_h * w / h)
                p = doc.add_paragraph()
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                p.paragraph_format.keep_with_next = True
                p.add_run().add_picture(io.BytesIO(png), width=width)
                if cap_:
                    caption(cap_, "Figure").alignment = WD_ALIGN_PARAGRAPH.CENTER


    if o.preface:
        emit(o.preface)
        doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)

    if o.toc:
        doc.add_paragraph("Table des matières", style="Heading 1")
        field(doc.add_paragraph(), 'TOC \\o "1-3" \\h \\z \\u', "Clic droit > Mettre à jour les champs pour afficher la table.")
        doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
        # Word propose de mettre à jour les champs (table des matières, index) à l'ouverture
        upd = OxmlElement("w:updateFields")
        upd.set(qn("w:val"), "true")
        doc.settings.element.append(upd)

    emit(blocks)

    if o.refs:
        doc.add_heading("Références", level=1)
        for r in o.refs:
            p = add_runs(doc.add_paragraph(), r)
            p.paragraph_format.left_indent = Cm(0.8)
            p.paragraph_format.first_line_indent = Cm(-0.8)
    if o.figure_index:
        figs, tabs = _captions(blocks)
        doc.add_heading("Index des figures et tableaux", level=1)
        if figs:
            doc.add_heading("Figures", level=2)
            field(doc.add_paragraph(), 'TOC \\h \\z \\c "Figure"', "Mettre à jour les champs pour afficher l'index.")
        if tabs:
            doc.add_heading("Tableaux", level=2)
            field(doc.add_paragraph(), 'TOC \\h \\z \\c "Tableau"', "Mettre à jour les champs pour afficher l'index.")
    if o.footer:
        add_runs(doc.add_paragraph(), f"*{o.footer}*", size=9, color=MUTED)
    _ = WD_SECTION
    buf = io.BytesIO()
    doc.save(buf)
    return buf.getvalue()


# ---------------------------------------------------------------------------------------------- PDF
def to_pdf(blocks: list[tuple], o: DocOptions) -> bytes:
    from fpdf import FPDF
    from fpdf.fonts import FontFace

    class PDF(FPDF):
        def header(self):
            if self.page_no() == 1 and o.cover:
                return
            if o.running_title:
                y = self.get_y()
                self.set_y(7)  # dans la marge haute : ne chevauche jamais le contenu
                self.set_font("Plex", "", 8)
                self.set_text_color(*MUTED)
                self.cell(0, 6, o.running_title, align="R")
                self.set_xy(self.l_margin, max(y, self.t_margin))

        def footer(self):
            if self.page_no() == 1 and o.cover:
                return
            self.set_y(-13)
            self.set_font("Plex", "", 8.5)
            self.set_text_color(*MUTED)
            self.cell(0, 6, str(self.page_no()), align="R")

    levels = _levels(blocks)
    pdf = PDF(format="A4")
    pdf.set_margins(20, 18, 20)
    pdf.set_auto_page_break(True, margin=18)
    pdf.add_font("Plex", "", str(FONTS / "IBMPlexSans-Regular.ttf"))
    pdf.add_font("Plex", "B", str(FONTS / "IBMPlexSans-Bold.ttf"))
    pdf.add_font("Plex", "I", str(FONTS / "IBMPlexSans-Italic.ttf"))
    pdf.add_font("Plex", "BI", str(FONTS / "IBMPlexSans-BoldItalic.ttf"))
    pdf.add_font("Mono", "", str(FONTS / "IBMPlexMono-Regular.ttf"))
    pdf.set_title(o.title)
    pdf.set_creator("Moanui")
    W = pdf.epw
    INK = (0x1C, 0x24, 0x30)

    def write_runs(text: str, size: float = 10.5, lh: float = 5.4, color=INK, base_style: str = ""):
        pdf.set_text_color(*color)
        for t, bold, ital, code in runs(text):
            if code:
                pdf.set_font("Mono", "", size - 1)
            else:
                style = "".join(sorted(set(base_style + ("B" if bold else "") + ("I" if ital else "")), key="BI".index))
                pdf.set_font("Plex", style, size)
            pdf.write(lh, t)

    def para(text: str, size=10.5, color=INK, indent: float = 0, style: str = "", after: float = 2.6, align="L"):
        if indent:
            pdf.set_left_margin(pdf.l_margin + indent)
            pdf.set_x(pdf.l_margin)
        if align == "J" and not any(r[1] or r[2] or r[3] for r in runs(text)):
            pdf.set_font("Plex", style, size)
            pdf.set_text_color(*color)
            pdf.multi_cell(0, size * 0.52, plain(text), align="J", new_x="LMARGIN", new_y="NEXT")
        else:
            write_runs(text, size, size * 0.52, color, style)
            pdf.ln(size * 0.52)
        if indent:
            pdf.set_left_margin(pdf.l_margin - indent)
        pdf.ln(after)

    def heading(text: str, level: int):
        size = {1: 17, 2: 13.5, 3: 11.5}[level]
        need = {1: 30, 2: 22, 3: 16}[level]
        if pdf.get_y() + need > pdf.h - pdf.b_margin:
            pdf.add_page()
        pdf.ln({1: 4, 2: 3, 3: 1.5}[level])
        if o.toc:
            pdf.start_section(plain(text), level=level - 1)
        pdf.set_font("Plex", "B", size)
        pdf.set_text_color(*NAVY)
        pdf.multi_cell(0, size * 0.5, plain(text), new_x="LMARGIN", new_y="NEXT")
        if level <= 2:
            pdf.set_draw_color(*LINE)
            pdf.line(pdf.l_margin, pdf.get_y() + 1, pdf.l_margin + W, pdf.get_y() + 1)
            pdf.ln(3)
        else:
            pdf.ln(1.5)

    def caption(text: str, center: bool = False):
        pdf.set_font("Plex", "I", 9)
        pdf.set_text_color(*MUTED)
        pdf.multi_cell(0, 4.6, plain(text), align="C" if center else "L", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(3)

    def table(headers, rows, align, kv=False):
        pdf.set_font("Plex", "", 9)
        pdf.set_text_color(*INK)
        pdf.set_draw_color(*LINE)
        ncol = len(headers) if headers else 2
        # largeurs proportionnelles au contenu (bornées)
        lens = [max([len(plain(str(h))) for h in ([headers[i]] if headers else [])] + [len(plain(str(r[i]))) for r in rows] + [3])
                for i in range(ncol)]
        lens = [min(max(x, 4), 60) for x in lens]
        heading_style = FontFace(emphasis="BOLD", fill_color=SOFT, color=INK)
        with pdf.table(col_widths=lens, width=W, line_height=4.6, text_align=tuple("RIGHT" if a == "r" else "LEFT" for a in align[:ncol]) if align else "LEFT",
                       first_row_as_headings=not kv, headings_style=heading_style, borders_layout="HORIZONTAL_LINES",
                       padding=(1.2, 1.6), repeat_headings=1) as tb:
            if headers and not kv:
                r_ = tb.row()
                for h in headers:
                    r_.cell(plain(str(h)))
            for row in rows:
                r_ = tb.row()
                for i, v in enumerate(row):
                    if kv and i == 0:
                        r_.cell(plain(str(v)), style=FontFace(emphasis="BOLD", color=MUTED))
                    else:
                        r_.cell(plain(str(v)))
        pdf.ln(4)

    # ------------------------------------------------------------------ page de garde
    pdf.add_page()
    if o.cover:
        c = o.cover
        pdf.set_fill_color(*NAVY)
        pdf.rect(0, 170, 115, 127, style="F")
        if c.get("image"):
            iw, ih = png_size(c["image"])
            w = 95
            pdf.image(io.BytesIO(c["image"]), x=pdf.w - w, y=0, w=w, h=min(170, w * ih / iw))
        pdf.set_xy(20, 40)
        pdf.set_font("Plex", "B", 44)
        pdf.set_text_color(*NAVY)
        pdf.cell(0, 18, c.get("title", o.title), new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Plex", "B", 16)
        for line in (c.get("subtitle", ""), c.get("version", "")):
            if line:
                pdf.cell(0, 9, line, new_x="LMARGIN", new_y="NEXT")
        pdf.set_xy(20, 185)
        pdf.set_text_color(255, 255, 255)
        pdf.set_font("Plex", "I", 12)
        pdf.cell(90, 8, c.get("date", ""), new_x="LMARGIN", new_y="NEXT")
        pdf.ln(10)
        pdf.set_font("Plex", "B", 12)
        for line in (c.get("org", ""), c.get("author", "")):
            if line:
                pdf.cell(90, 7, line, new_x="LMARGIN", new_y="NEXT")
        pdf.add_page()
    else:
        pdf.set_font("Plex", "B", 19)
        pdf.set_text_color(*INK)
        pdf.multi_cell(0, 9, o.title, new_x="LMARGIN", new_y="NEXT")
        if o.subtitle:
            para(o.subtitle, 11, MUTED)
        if o.meta:
            table([], [[k, v] for k, v in o.meta], "ll", kv=True)

    def emit(blocks):
        for b in blocks:
            t = b[0]
            if t == "part":
                pdf.add_page()
                if o.toc:
                    pdf.start_section(plain(b[1]), level=0)
                pdf.set_y(pdf.h / 2 - 25)
                pdf.set_font("Plex", "B", 32)
                pdf.set_text_color(*NAVY)
                pdf.multi_cell(0, 15, plain(b[1]), align="C", new_x="LMARGIN", new_y="NEXT")
                pdf.add_page()
            elif t == "pagebreak":
                pdf.add_page()
            elif t in ("h1", "h2", "h3"):
                heading(b[1], levels[t])
            elif t == "p":
                para(b[1], align="J")
            elif t in ("ul", "ol"):
                for n, item in enumerate(b[1], 1):
                    mark = "•" if t == "ul" else f"{n}."
                    pdf.set_font("Plex", "", 10.5)
                    pdf.set_text_color(*INK)
                    x0 = pdf.l_margin
                    pdf.set_x(x0 + 2)
                    pdf.cell(5, 5.4, mark)
                    pdf.set_left_margin(x0 + 7)
                    write_runs(item)
                    pdf.ln(5.4)
                    pdf.set_left_margin(x0)
                    pdf.ln(1)
                pdf.ln(1.5)
            elif t == "note":
                y0 = pdf.get_y()
                pdf.set_fill_color(*SOFT)
                pdf.set_font("Plex", "", 10)
                pdf.set_text_color(*INK)
                pdf.set_x(pdf.l_margin + 3)
                pdf.multi_cell(W - 3, 5.2, plain(b[1]), fill=True, padding=2, new_x="LMARGIN", new_y="NEXT")
                pdf.set_draw_color(*NAVY)
                pdf.set_line_width(0.8)
                pdf.line(pdf.l_margin + 1, y0, pdf.l_margin + 1, pdf.get_y())
                pdf.set_line_width(0.2)
                pdf.ln(3)
            elif t == "code":
                pdf.set_font("Mono", "", 8)
                pdf.set_fill_color(*SOFT)
                pdf.set_text_color(*INK)
                pdf.multi_cell(0, 4, b[1], fill=True, padding=2, new_x="LMARGIN", new_y="NEXT")
                pdf.ln(3)
            elif t == "kv":
                table([], [[k, v] for k, v in b[1]], "ll", kv=True)
            elif t == "table":
                _, hd, rows, cap_, al = b
                if cap_:
                    if pdf.get_y() + 25 > pdf.h - pdf.b_margin:
                        pdf.add_page()
                    caption(cap_)
                table(hd, rows, al)
            elif t in ("fig", "img"):
                png, cap_, rel = _figure_png(b)
                iw, ih = png_size(png)
                w = W * rel
                h = w * ih / iw
                max_h = pdf.h - pdf.t_margin - pdf.b_margin - 20
                if h > max_h:
                    h = max_h
                    w = h * iw / ih
                if pdf.get_y() + h + 12 > pdf.h - pdf.b_margin:
                    pdf.add_page()
                pdf.image(io.BytesIO(png), x=pdf.l_margin + (W - w) / 2, w=w, h=h)
                pdf.ln(2)
                if cap_:
                    caption(cap_, center=True)


    if o.preface:
        emit(o.preface)
        pdf.add_page()

    if o.toc:
        def render_toc(p, outline):
            p.set_x(p.l_margin)
            p.set_font("Plex", "B", 17)
            p.set_text_color(*NAVY)
            p.cell(0, 10, "Table des matières", new_x="LMARGIN", new_y="NEXT")
            p.ln(3)
            for s in outline:
                lvl = s.level
                p.set_font("Plex", "B" if lvl == 0 else "", 10.5 if lvl == 0 else 9.5)
                p.set_text_color(*INK)
                link = p.add_link(page=s.page_number)
                label = ("    " * lvl) + s.name
                num = str(s.page_number)
                lw, nw = p.get_string_width(label), p.get_string_width(num)
                dots = "." * max(2, int((W - lw - nw - 4) / max(p.get_string_width("."), 0.1)))
                p.cell(W - nw - 2, 6 if lvl == 0 else 5.2, f"{label} {dots}", link=link)
                p.cell(nw + 2, 6 if lvl == 0 else 5.2, num, align="R", link=link, new_x="LMARGIN", new_y="NEXT")

        n_sec = sum(1 for b in blocks if b[0] in ("h1", "h2", "h3", "part")) + (3 if o.figure_index else 0) + (1 if o.refs else 0)
        pdf.insert_toc_placeholder(render_toc, pages=max(1, (n_sec + 39) // 40))
        pdf.add_page()

    emit(blocks)

    if o.refs:
        heading("Références", 1)
        for r in o.refs:
            pdf.set_left_margin(pdf.l_margin + 6)
            pdf.set_x(pdf.l_margin - 6)
            write_runs(r, 9.5, 4.8)
            pdf.ln(4.8)
            pdf.set_left_margin(pdf.l_margin - 6)
            pdf.ln(1.5)
    if o.figure_index:
        figs, tabs = _captions(blocks)
        heading("Index des figures et tableaux", 1)
        for title, items in (("Figures", figs), ("Tableaux", tabs)):
            if items:
                heading(title, 2)
                for it in items:
                    para(it, 9.5, after=1)
    if o.footer:
        pdf.ln(4)
        para(f"*{o.footer}*", 9, MUTED)
    return bytes(pdf.output())


def stamp() -> str:
    return datetime.now().strftime("%d/%m/%Y à %H:%M")
