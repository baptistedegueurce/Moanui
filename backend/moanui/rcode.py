"""« Code R équivalent » : script ggplot2 qui refait un graphique Moanui à partir de ses données agrégées.

Le script est généré à partir de la même spécification que le graphique affiché et de la fiche méthode ; les données
viennent de la même requête que l'affichage (`pipeline.chart_data`), donc des mêmes filtres et de la même recette.
Ce que ggplot2 ne sait pas faire à l'identique (plus d'un axe secondaire, 3D) est signalé dans le script.
"""

from __future__ import annotations

import csv
import io
import re
import zipfile
from datetime import datetime

from . import __version__

RAW_TYPES = {"nuage", "bulles", "boites", "violons", "histogramme", "nuage3d"}
AGG_LABEL = {"somme": "Somme", "moyenne": "Moyenne", "mediane": "Médiane", "min": "Min", "max": "Max", "nombre": "Nombre",
             "nombre_lignes": "Nombre de lignes", "nombre_distinct": "Nombre distinct", "ecart_type": "Écart-type"}
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}(T00:00:00)?$")


# --------------------------------------------------------------------------- requête et données


def chart_request(s: dict) -> dict:
    """Même requête que `dataRequest` côté navigateur (frontend/src/lib/chart.ts)."""
    filters = [c for c in s.get("filters") or [] if c.get("column") and (
        c.get("op") in ("is_null", "not_null")
        or (c.get("values") if c.get("op") in ("in", "not_in") else c.get("value") not in ("", None)))]
    t = s.get("type")
    if t in RAW_TYPES:
        cols = [c for c in (s.get("x"), s.get("y"), s.get("z"), s.get("size")) if c]
        meas = list(dict.fromkeys(c for c in cols if c != s.get("x") or t == "histogramme"))
        return {"raw": True, "x": None if t == "histogramme" else s.get("x"), "series": s.get("series"),
                "facet": s.get("facet"), "z": s.get("z"), "measures": [{"column": c, "agg": "somme"} for c in meas],
                "filters": filters, "limit": 50000}
    return {"x": s.get("x"), "series": s.get("series"), "facet": s.get("facet"), "filters": filters,
            "measures": [{"column": m.get("column"), "agg": m.get("agg")} for m in s.get("measures") or []]}


def measure_label(m: dict) -> str:
    if m.get("label"):
        return m["label"]
    if m.get("agg") == "nombre_lignes":
        return "Nombre de lignes"
    return f"{AGG_LABEL.get(m.get('agg'), m.get('agg'))} de {m.get('column')}"


def _slug(text: str) -> str:
    s = re.sub(r"[^0-9A-Za-z_]+", "_", text.lower().replace("é", "e").replace("è", "e").replace("ê", "e")
               .replace("à", "a").replace("ç", "c").replace("ô", "o").replace("û", "u").replace("î", "i")).strip("_")
    return s or "valeur"


def named_data(s: dict, data: dict) -> tuple[list[str], list[list], list[str]]:
    """Renomme m0, m1… en noms lisibles (somme_debarquement_kg…) ; renvoie (colonnes, lignes, noms des mesures)."""
    cols = list(data["columns"])
    names: list[str] = []
    if not data.get("total") and s.get("type") not in RAW_TYPES:
        used = set(cols)
        for i, m in enumerate(s.get("measures") or []):
            base = _slug(f"{m.get('agg')}_{m.get('column') or 'lignes'}") if m.get("agg") != "nombre_lignes" \
                else "nombre_lignes"
            n, k = base, 2
            while n in used:
                n, k = f"{base}_{k}", k + 1
            used.add(n)
            names.append(n)
            j = cols.index(f"m{i}")
            cols[j] = n
    return cols, data["rows"], names


def to_csv(cols: list[str], rows: list[list]) -> bytes:
    """CSV « français » (; et virgule décimale), lu par read.csv2 et par Excel."""
    buf = io.StringIO()
    w = csv.writer(buf, delimiter=";", lineterminator="\n")
    w.writerow(cols)
    for r in rows:
        w.writerow(["" if v is None else (repr(v).replace(".", ",") if isinstance(v, float) else v) for v in r])
    return ("﻿" + buf.getvalue()).encode("utf-8")


# --------------------------------------------------------------------------- génération du script


def q(name: str) -> str:
    """Nom de colonne R entre accents graves."""
    return "`" + str(name).replace("`", "") + "`"


def rs(text) -> str:
    """Chaîne R."""
    return '"' + str(text).replace("\\", "\\\\").replace('"', '\\"') + '"'


def rnum(v) -> str:
    try:
        f = float(v)
    except (TypeError, ValueError):
        return "NA"
    return repr(int(f)) if f.is_integer() else repr(f)


def _axis_cfg(s: dict, a: str) -> dict:
    c = dict((s.get("axes") or {}).get(a) or {})
    if a == "y":
        for k, old in (("title", "y_title"), ("scale", "y_scale"), ("min", "y_min"), ("max", "y_max")):
            if c.get(k) is None:
                c[k] = s.get(old)
    if a == "y2" and not c.get("title"):
        c["title"] = s.get("y2_title")
    return c


def _mark(s: dict, m: dict) -> str:
    t = s.get("type")
    if t == "barres_h":
        return "barres"
    return m.get("mark") or {"lignes": "lignes", "aires": "aires"}.get(t, "barres")


def _axis(s: dict, m: dict) -> str:
    if s.get("type") == "barres_h":
        return "y"
    a = m.get("axis") or "y"
    if s.get("facet") and a in ("y3", "y4"):
        return "y" if a == "y3" else "y2"
    return a


class Script:
    def __init__(self):
        self.lines: list[str] = []
        self.notes: list[str] = []

    def add(self, *lines: str):
        self.lines.extend(lines)

    def note(self, text: str):
        self.notes.append(text)


def chart_r(s: dict, data: dict, theme: dict, csv_name: str = "graphique_donnees.csv") -> tuple[str, list[str]]:
    """Renvoie (script R, avertissements sur ce qui diffère de l'appli)."""
    cols, rows, mnames = named_data(s, data)
    t = s.get("type") or "barres"
    tpl = s.get("template") or {}
    pal = theme.get("palette") or ["#1f4e79", "#e07b39", "#3a923a", "#c03d3e", "#7f5fa8"]
    seq = theme.get("sequential") or ["#f7fbff", "#08306b"]
    chart = theme.get("chart") or {}
    colors = theme.get("colors") or {}
    sc = Script()
    x, series, facet = s.get("x"), s.get("series"), s.get("facet")
    xi = cols.index(x) if x in cols else -1
    xvals = [r[xi] for r in rows] if xi >= 0 else []
    x_is_date = bool(xvals) and all(isinstance(v, str) and ISO_DATE.match(v) for v in xvals if v is not None)
    x_is_num = bool(xvals) and all(isinstance(v, (int, float)) for v in xvals if v is not None)
    x_cat = t.startswith("barres") or t in ("combine", "chaleur") or not (x_is_num or x_is_date)

    head = [f"# {tpl.get('title') or 'Graphique'} : code R équivalent",
            f"# Généré par Moanui {__version__} le {datetime.now().strftime('%d/%m/%Y')}.",
            f"# Données : « {csv_name} », exportées avec ce script (mêmes filtres et même recette que dans l'appli).",
            "# Paquets nécessaires (une seule fois) : install.packages(c(\"ggplot2\", \"scales\"))",
            "# Le rendu est le plus proche possible de l'appli ; polices et marges peuvent différer légèrement.", ""]
    sc.add("library(ggplot2)", "library(scales)", "",
           f"donnees <- read.csv2({rs(csv_name)}, fileEncoding = \"UTF-8-BOM\", check.names = FALSE)")
    if data.get("sampled"):
        sc.note(f"Les données sont un échantillon aléatoire de {len(rows)} lignes sur {data.get('total')} (comme dans "
                "l'appli) : les formes restent valables, pas les effectifs.")
    sc.add(f"palette <- c({', '.join(rs(c) for c in pal)})",
           "nombre_fr <- label_number(big.mark = \" \", decimal.mark = \",\")", "")

    # --- types d'axe horizontal
    if x and xi >= 0 and t not in ("histogramme",):
        if x_is_date:
            sc.add(f"donnees${q(x)} <- as.Date(substr(donnees${q(x)}, 1, 10))")
        elif x_cat:
            sc.add(f"donnees${q(x)}[is.na(donnees${q(x)}) | donnees${q(x)} == \"\"] <- \"(vide)\"")
            order = f"unique(donnees${q(x)})"
            if s.get("sort") in ("valeur_desc", "valeur_asc") and mnames:
                order = (f"names(sort(tapply(donnees${q(mnames[0])}, donnees${q(x)}, sum, na.rm = TRUE), "
                         f"decreasing = {'TRUE' if s.get('sort') == 'valeur_desc' else 'FALSE'}))")
            sc.add("# ordre des catégories comme dans l'appli",
                   f"donnees${q(x)} <- factor(donnees${q(x)}, levels = {order})")
    for d in (series, facet):
        if d and d in cols:
            sc.add(f"donnees${q(d)}[is.na(donnees${q(d)}) | donnees${q(d)} == \"\"] <- \"(vide)\"")
            sc.add(f"donnees${q(d)} <- factor(donnees${q(d)}, levels = unique(donnees${q(d)}))")
    sc.add("")

    x_title = s.get("x_title") or x or ""
    layers: list[str] = []
    scales: list[str] = []
    labs = {"title": tpl.get("title"), "subtitle": tpl.get("subtitle"), "x": x_title}
    gopen = "ggplot(donnees)"

    if t == "secteurs":
        m = q(mnames[-1])
        by = f"donnees${q(facet)}" if facet else "rep(1, nrow(donnees))"
        sc.add(f"donnees$part <- donnees${m} / ave(donnees${m}, {by}, FUN = function(v) sum(v, na.rm = TRUE))")
        gopen = f"ggplot(donnees, aes(x = 2, y = {m}, fill = {q(x)}))"
        layers += ["geom_col(width = 1, colour = \"white\")",
                   ("geom_text(aes(label = percent(part, accuracy = 1)), position = position_stack(vjust = 0.5), "
                    "size = 3.5, colour = \"white\")"),
                   "coord_polar(theta = \"y\")", "xlim(0.5, 2.5)"]
        scales.append("scale_fill_manual(values = rep(palette, length.out = nlevels(donnees[[" + rs(x) + "]])))")
        labs.update({"fill": x_title, "x": None, "y": None})
    elif t == "chaleur":
        m = q(mnames[-1])
        gopen = f"ggplot(donnees, aes(x = {q(x)}, y = {q(series)}, fill = {m}))"
        layers.append("geom_tile(colour = \"white\", linewidth = 0.6)")
        scales.append(f"scale_fill_gradientn(colours = c({', '.join(rs(c) for c in seq)}), labels = nombre_fr)")
        labs.update({"y": series, "fill": measure_label((s.get("measures") or [{}])[-1])})
    elif t in ("nuage", "bulles"):
        aes = [f"x = {q(x)}", f"y = {q(s.get('y'))}"] + ([f"colour = {q(series)}"] if series else []) \
              + ([f"size = {q(s.get('size'))}"] if t == "bulles" and s.get("size") else [])
        layers.append(f"geom_point(aes({', '.join(aes)}), alpha = 0.75" + ("" if series else ", colour = palette[1]")
                      + ("" if t == "bulles" and s.get("size") else ", size = 2.5") + ")")
        if series:
            scales.append("scale_colour_manual(values = rep(palette, length.out = nlevels(donnees[[" + rs(series)
                          + "]])))")
        if t == "bulles" and s.get("size"):
            scales.append("scale_size_area(max_size = 14, labels = nombre_fr)")
            labs["size"] = s.get("size")
        labs.update({"y": s.get("y"), "colour": series})
        scales.append("scale_y_continuous(labels = nombre_fr)")
    elif t in ("boites", "violons"):
        xa = q(x) if x else "\"\""
        fill = f", fill = {q(series)}" if series else ""
        geom, extra = ("geom_boxplot", ", outlier.size = 1.2") if t == "boites" else ("geom_violin", ", trim = TRUE")
        layers.append(f"{geom}(aes(x = {xa}, y = {q(s.get('y'))}{fill})" + ("" if series else ", fill = palette[1]")
                      + f"{extra}, alpha = 0.85)")
        if t == "violons":
            grp = f", group = interaction({xa}, {q(series)})" if series else ""
            layers.append(f"geom_boxplot(aes(x = {xa}, y = {q(s.get('y'))}{grp}), "
                          "width = 0.12, outlier.shape = NA, fill = \"white\""
                          + (", position = position_dodge(width = 0.9)" if series else "") + ")")
        if series:
            scales.append("scale_fill_manual(values = rep(palette, length.out = nlevels(donnees[[" + rs(series)
                          + "]])))")
        scales.append("scale_y_continuous(labels = nombre_fr)")
        labs.update({"y": s.get("y"), "fill": series})
    elif t == "histogramme":
        fill = f", fill = {q(series)}" if series else ""
        layers.append(f"geom_histogram(aes(x = {q(x)}{fill}), bins = 30, colour = \"white\""
                      + (", position = \"identity\", alpha = 0.65" if series else ", fill = palette[1]") + ")")
        sc.note("Histogramme : 30 classes ; l'appli choisit le nombre de classes automatiquement (argument « bins »).")
        if series:
            scales.append("scale_fill_manual(values = rep(palette, length.out = nlevels(donnees[[" + rs(series)
                          + "]])))")
        scales.append("scale_y_continuous(expand = expansion(mult = c(0, 0.05)))")
        labs.update({"y": "Effectif", "fill": series})
    elif t in ("nuage3d", "surface3d"):
        return _plotly_3d(s, cols, mnames, head, sc, csv_name, pal, seq), sc.notes
    else:
        gopen = _aggregated(s, sc, layers, scales, labs, mnames, rows, cols, pal, x_cat)

    # --- repères
    _refs(s, sc, layers, x, x_cat)

    if facet:
        free = s.get("facet_scale") != "commune"
        ncol = f", ncol = {int(s['facet_cols'])}" if s.get("facet_cols") else ""
        layers.append(f"facet_wrap(vars({q(facet)}){ncol}" + (', scales = "free_y"' if free and t != "secteurs" else "")
                      + ")")
    if t == "barres_h" and not any(ly.startswith("coord_flip(") for ly in layers):
        layers.append("coord_flip()")

    cap = " · ".join(str(v) for v in (f"Source : {tpl['source']}" if tpl.get("source") else None, tpl.get("author"),
                                      datetime.now().strftime("%d/%m/%Y") if tpl.get("show_date") else None) if v)
    if cap:
        labs["caption"] = cap
    legend = {"haut": "top", "droite": "right", "bas": "bottom", "aucune": "none"}.get(s.get("legend") or "haut", "top")
    lab_txt = ", ".join(f"{k} = {rs(v) if v is not None else 'NULL'}" for k, v in labs.items() if v is not None or
                        k in ("x", "y"))
    bg, ink, grid = chart.get("background") or "#ffffff", colors.get("text") or "#1f2933", chart.get("grid") or "#e5e7eb"
    theme_txt = (f"theme_minimal(base_size = 12) +\n  theme(legend.position = {rs(legend)}, "
                 "panel.grid.minor = element_blank(),\n"
                 f"        panel.grid.major = element_line(colour = {rs(grid)}),\n"
                 f"        plot.background = element_rect(fill = {rs(bg)}, colour = NA),\n"
                 f"        text = element_text(colour = {rs(ink)}),\n"
                 "        plot.title = element_text(face = \"bold\"), plot.caption = element_text(hjust = 0))")
    if t == "secteurs":
        theme_txt = (f"theme_void(base_size = 12) +\n  theme(legend.position = {rs(legend)}, "
                     f"plot.background = element_rect(fill = {rs(bg)}, colour = NA), "
                     "plot.title = element_text(face = \"bold\"), plot.caption = element_text(hjust = 0))")
    parts = [gopen] + layers + scales + [f"labs({lab_txt})", theme_txt]
    sc.add("g <- " + " +\n  ".join(parts), "", "print(g)", "")
    w, h = int(tpl.get("width") or 1100), int(tpl.get("height") or 620)
    sc.add("# Export : mêmes dimensions que dans l'appli, en double résolution",
           f"ggsave(\"graphique.png\", g, width = {w / 100:g}, height = {h / 100:g}, dpi = 200)",
           f"# ggsave(\"graphique.svg\", g, width = {w / 100:g}, height = {h / 100:g})  # nécessite le paquet svglite")
    body = head + ([f"# Attention : {n}" for n in sc.notes] + [""] if sc.notes else []) + sc.lines
    return "\n".join(body) + "\n", sc.notes


def _aggregated(s, sc: Script, layers, scales, labs, mnames, rows, cols, pal, x_cat) -> str:
    t = s.get("type")
    x, series = s.get("x"), s.get("series")
    measures = s.get("measures") or []
    stack = s.get("stack") or "groupe"
    axes = [_axis(s, m) for m in measures]
    if any(a in ("y3", "y4") for a in axes):
        moved = [f"« {measure_label(m)} » est tracée sur l'axe {'gauche' if a == 'y3' else 'droit'}"
                 for m, a in zip(measures, axes) if a in ("y3", "y4")]
        sc.note("ggplot2 ne gère qu'un seul axe secondaire : " + " ; ".join(moved)
                + ". Si ses valeurs sont d'un autre ordre de grandeur, faites-en un graphique à part.")
        axes = ["y" if a == "y3" else "y2" if a == "y4" else a for a in axes]
    has_y2 = "y2" in axes
    cfg_y, cfg_y2 = _axis_cfg(s, "y"), _axis_cfg(s, "y2")
    if has_y2:
        left = [q(n) for n, a in zip(mnames, axes) if a == "y"] or ["0"]
        right = [q(n) for n, a in zip(mnames, axes) if a == "y2"]
        sc.add("# axe droit : ggplot2 l'obtient par un facteur d'échelle (coef) appliqué aux mesures de droite",
               f"coef <- max(abs(c({', '.join('donnees$' + c for c in left)})), na.rm = TRUE) / "
               f"max(abs(c({', '.join('donnees$' + c for c in right)})), na.rm = TRUE)",
               "if (!is.finite(coef) || coef == 0) coef <- 1", "")
        if cfg_y.get("scale") == "log" or cfg_y2.get("scale") == "log":
            sc.note("Échelle logarithmique et axe secondaire ensemble : ggplot2 les combine mal ; l'échelle log est "
                    "appliquée à l'axe gauche seulement.")
    pos = {"groupe": "position_dodge(width = 0.9)", "empile": "position_stack()", "pourcent": "position_fill()"}[stack]
    bar_idx = [i for i, m in enumerate(measures) if _mark(s, m) == "barres"]
    long_bars = len(bar_idx) > 1

    def yexpr(i):
        return f"{q(mnames[i])} * coef" if axes[i] == "y2" else q(mnames[i])

    if long_bars:
        sc.add("# plusieurs mesures en barres : format long (une ligne par catégorie et par mesure)",
               "barres <- rbind(")
        parts = []
        for i in bar_idx:
            keep = ", ".join(f"{q(c)} = donnees${q(c)}" for c in (x, series, s.get("facet")) if c)
            val = f"donnees${q(mnames[i])}" + (" * coef" if axes[i] == "y2" else "")
            parts.append(f"  data.frame({keep}, mesure = {rs(measure_label(measures[i]))}, valeur = {val}, "
                         "check.names = FALSE)")
        sc.add(",\n".join(parts), ")",
               "barres$mesure <- factor(barres$mesure, levels = unique(barres$mesure))", "")
        fill = f"interaction({q(series)}, mesure, sep = \" · \")" if series else "mesure"
        layers.append(f"geom_col(data = barres, aes(x = {q(x)}, y = valeur, fill = {fill}), position = {pos})")
        if any(measures[i].get("show_values") or s.get("show_values") for i in bar_idx):
            vpos = "position_dodge(width = 0.9), vjust = -0.4" if stack == "groupe" else "position_stack(vjust = 0.5)"
            layers.append(f"geom_text(data = barres, aes(x = {q(x)}, y = valeur, label = nombre_fr(valeur), "
                          f"group = {fill}), position = {vpos.split(', vjust')[0]}"
                          + (", vjust = -0.4" if stack == "groupe" else "") + ", size = 3)")
        scales.append("scale_fill_manual(values = palette)")
        labs["fill"] = None
    color_maps = False
    for i, m in enumerate(measures):
        mk = _mark(s, m)
        if long_bars and i in bar_idx:
            continue
        y = yexpr(i)
        fixed = m.get("color") or pal[i % len(pal)]
        dash = ', linetype = "dashed"' if m.get("dash") else ""
        if mk == "barres":
            if series:
                layers.append(f"geom_col(aes(x = {q(x)}, y = {y}, fill = {q(series)}), position = {pos})")
                scales.append("scale_fill_manual(values = rep(palette, length.out = nlevels(donnees[[" + rs(series)
                              + "]])))")
                labs["fill"] = series
            else:
                layers.append(f"geom_col(aes(x = {q(x)}, y = {y}), fill = {rs(fixed)})")
        elif mk in ("lignes", "points", "aires"):
            if series:
                aes = f"aes(x = {q(x)}, y = {y}, colour = {q(series)}, group = {q(series)})"
                color_maps = True
                if mk == "aires":
                    apos = "position_stack()" if t == "aires" and stack != "groupe" else "position_identity()"
                    if t == "aires" and stack == "pourcent":
                        apos = "position_fill()"
                    layers.append(f"geom_area(aes(x = {q(x)}, y = {y}, fill = {q(series)}, group = {q(series)}), "
                                  f"position = {apos}, alpha = 0.8)")
                    scales.append("scale_fill_manual(values = rep(palette, length.out = nlevels(donnees[["
                                  + rs(series) + "]])))")
                    labs["fill"] = series
                else:
                    if mk == "lignes":
                        layers.append(f"geom_line({aes}, linewidth = 1{dash})")
                    layers.append(f"geom_point({aes}, size = {1.8 if mk == 'lignes' else 2.6})")
                labs["colour"] = series
            else:
                aes = f"aes(x = {q(x)}, y = {y}, group = 1)"
                if mk == "aires":
                    layers.append(f"geom_area({aes}, fill = {rs(fixed)}, alpha = 0.6)")
                else:
                    if mk == "lignes":
                        layers.append(f"geom_line({aes}, colour = {rs(fixed)}, linewidth = 1{dash})")
                    layers.append(f"geom_point({aes}, colour = {rs(fixed)}, size = {1.8 if mk == 'lignes' else 2.6})")
        if (m.get("show_values") or s.get("show_values")) and not (long_bars and i in bar_idx):
            grp = f", group = {q(series)}" if series else ""
            vpos = ("position = position_dodge(width = 0.9), vjust = -0.4" if mk == "barres" and stack == "groupe"
                    else "position = position_stack(vjust = 0.5)" if mk == "barres" else "vjust = -0.8")
            layers.append(f"geom_text(aes(x = {q(x)}, y = {y}, label = nombre_fr({q(mnames[i])}){grp}), {vpos}, size = 3)")
    if color_maps:
        scales.append("scale_colour_manual(values = rep(palette, length.out = nlevels(donnees[[" + rs(series) + "]])))")
    # dédoublonne les échelles (une seule par esthétique)
    seen, uniq = set(), []
    for sc_ in scales:
        key = sc_.split("(")[0]
        if key not in seen:
            seen.add(key)
            uniq.append(sc_)
    scales[:] = uniq

    # axe vertical
    y_lab = cfg_y.get("title") or " / ".join(measure_label(m) for m, a in zip(measures, axes) if a == "y") or None
    if stack == "pourcent" and any(_mark(s, m) in ("barres", "aires") for m in measures):
        y_args = ["labels = percent"]
    else:
        suffix = cfg_y.get("suffix")
        y_args = [f"labels = label_number(big.mark = \" \", decimal.mark = \",\", suffix = {rs(' ' + suffix)})"
                  if suffix else "labels = nombre_fr"]
    if any(_mark(s, m) == "barres" for m in measures) or t == "aires":
        y_args.append("expand = expansion(mult = c(0, 0.05))")
    if has_y2:
        y2_lab = cfg_y2.get("title") or " / ".join(measure_label(m) for m, a in zip(measures, axes) if a == "y2")
        suf2 = cfg_y2.get("suffix")
        lab2 = (f"label_number(big.mark = \" \", decimal.mark = \",\", suffix = {rs(' ' + suf2)})" if suf2
                else "nombre_fr")
        y_args.append(f"sec.axis = sec_axis(~ . / coef, name = {rs(y2_lab)}, labels = {lab2})")
    fn = "scale_y_log10" if cfg_y.get("scale") == "log" else "scale_y_continuous"
    scales.append(f"{fn}({', '.join(y_args)})")
    lo, hi = cfg_y.get("min"), cfg_y.get("max")
    if lo is not None or hi is not None:
        layers.append(f"coord_cartesian(ylim = c({rnum(lo) if lo is not None else 'NA'}, "
                      f"{rnum(hi) if hi is not None else 'NA'}))" if t != "barres_h" else
                      f"coord_flip(ylim = c({rnum(lo) if lo is not None else 'NA'}, {rnum(hi) if hi is not None else 'NA'}))")
    labs["y"] = y_lab
    if x_cat and len({r[cols.index(x)] for r in rows if x in cols}) > 8 and t != "barres_h":
        layers.append("theme(axis.text.x = element_text(angle = 45, hjust = 1))")
    return "ggplot(donnees)"


def _refs(s, sc: Script, layers, x, x_cat):
    for r in s.get("refs") or []:
        kind, v, col = r.get("kind"), r.get("value"), rs(r.get("color") or "#d9822b")
        lab = r.get("label") or ""
        if v in (None, "") and kind != "note":
            continue
        on_y2 = r.get("axis") in ("y2", "y4")
        if kind == "ligne_h":
            yv = rnum(v) + (" * coef" if on_y2 else "")
            layers.append(f"geom_hline(yintercept = {yv}, linetype = \"dashed\", colour = {col})")
            if lab:
                xr = "Inf" if x_cat or not x else f"max(donnees${q(x)}, na.rm = TRUE)"
                layers.append(f"annotate(\"text\", x = {xr}, y = {yv}, label = {rs(lab)}, hjust = 1.05, vjust = -0.5, "
                              f"colour = {col}, size = 3.4)")
        elif kind in ("ligne_v", "zone_v"):
            def xpos(val):
                if x_cat:
                    return f"match({rs(val)}, levels(donnees${q(x)}))"
                if isinstance(val, str) and ISO_DATE.match(val[:10]):
                    return f"as.Date({rs(val[:10])})"
                return rnum(val)
            if kind == "ligne_v":
                layers.append(f"geom_vline(xintercept = {xpos(v)}, linetype = \"dashed\", colour = {col})")
                if lab:
                    layers.append(f"annotate(\"text\", x = {xpos(v)}, y = Inf, label = {rs(lab)}, vjust = 1.5, "
                                  f"hjust = -0.05, colour = {col}, size = 3.4)")
            else:
                v2 = r.get("value2") or v
                a, b = xpos(v), xpos(v2)
                if x_cat:
                    a, b = f"{a} - 0.5", f"{b} + 0.5"
                layers.append(f"annotate(\"rect\", xmin = {a}, xmax = {b}, ymin = -Inf, ymax = Inf, fill = {col}, "
                              "alpha = 0.12)")
                if lab:
                    layers.append(f"annotate(\"text\", x = {xpos(v)}, y = Inf, label = {rs(lab)}, vjust = 1.5, "
                                  f"hjust = 0, colour = {col}, size = 3.4)")
        elif kind == "note" and lab:
            xv = rs(v) if x_cat else (f"as.Date({rs(str(v)[:10])})" if isinstance(v, str) and ISO_DATE.match(str(v)[:10])
                                       else rnum(v))
            layers.append(f"annotate(\"label\", x = {xv}, y = Inf, label = {rs(lab)}, vjust = 1.3, size = 3.2, "
                          f"colour = {col}, label.size = 0)")
    if any((r.get("kind") == "ligne_h" and r.get("axis") in ("y2", "y4")) for r in s.get("refs") or []) and \
            "coef <-" not in "\n".join(sc.lines):
        sc.add("coef <- 1  # aucune mesure sur l'axe droit : repère tracé sur l'axe gauche")


def _plotly_3d(s, cols, mnames, head, sc: Script, csv_name, pal, seq) -> str:
    sc.note("ggplot2 ne fait pas de 3D : le script utilise le paquet plotly (install.packages(\"plotly\")).")
    sc.lines = [ln for ln in sc.lines if not ln.startswith("library(ggplot2)")]
    sc.add("library(plotly)", "")
    t = s.get("type")
    if t == "nuage3d":
        color = f", color = ~{q(s.get('series'))}, colors = palette" if s.get("series") else ""
        sc.add(f"p <- plot_ly(donnees, x = ~{q(s.get('x'))}, y = ~{q(s.get('y'))}, z = ~{q(s.get('z'))}{color}, "
               "type = \"scatter3d\", mode = \"markers\", marker = list(size = 3, opacity = 0.8))")
    else:
        m = q(mnames[-1])
        sc.add(f"z <- xtabs({m} ~ {q(s.get('series'))} + {q(s.get('x'))}, data = donnees)",
               f"p <- plot_ly(x = colnames(z), y = rownames(z), z = unclass(z), type = \"surface\", "
               f"colors = c({', '.join(rs(c) for c in seq)}))")
    title = (s.get("template") or {}).get("title") or ""
    sc.add(f"p <- layout(p, title = {rs(title)})", "p", "",
           "# Export : htmlwidgets::saveWidget(p, \"graphique.html\")")
    body = head + [f"# Attention : {n}" for n in sc.notes] + [""] + sc.lines
    return "\n".join(body) + "\n"


def chart_zip(script: str, csv_bytes: bytes, csv_name: str = "graphique_donnees.csv") -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("graphique.R", script.encode("utf-8"))
        z.writestr(csv_name, csv_bytes)
        z.writestr("LISEZMOI.txt", (
            "Code R équivalent du graphique, généré par Moanui.\n\n"
            "1. Décompressez le dossier.\n"
            "2. Ouvrez graphique.R dans RStudio, puis Session > Set Working Directory > To Source File Location.\n"
            "3. Lancez le script (Ctrl + Maj + Entrée). Il refait le graphique et l'enregistre en graphique.png.\n\n"
            "Les données du CSV sont celles du graphique (après recette et filtres), séparateur « ; » et virgule "
            "décimale : elles s'ouvrent aussi dans Excel.\n").encode())
    return buf.getvalue()


# --------------------------------------------------------------------------- statistiques

P_ADJUST = {"holm": "holm", "bonferroni": "bonferroni", "bh": "BH", "aucune": "none"}
GLM_FAMILY = {"poisson": "poisson(link = \"log\")", "quasi_poisson": "quasipoisson(link = \"log\")",
              "gamma": "Gamma(link = \"log\")", "logistique": "binomial(link = \"logit\")"}


def stat_columns(spec: dict) -> list[str]:
    v = spec.get("variables") or {}
    out: list[str] = []
    for key in ("y", "groupe", "x", "effort"):
        val = v.get(key)
        for c in (val if isinstance(val, list) else [val]):
            if c and c not in out:
                out.append(c)
    return out


def stat_r(spec: dict, test: str, cat: set[str], opts: dict, csv_name: str = "analyse_donnees.csv") -> str:
    """Script R qui refait l'analyse (mêmes données, même test, même seuil et même correction)."""
    v = spec.get("variables") or {}
    kind = spec.get("analyse")
    a = opts.get("alpha", 0.05)
    padj = P_ADJUST.get(opts.get("correction") or "holm", "holm")
    L = [f"# Analyse statistique : code R équivalent ({test})",
         f"# Généré par Moanui {__version__} le {datetime.now().strftime('%d/%m/%Y')}.",
         f"# Données : « {csv_name} » (lignes complètes pour les variables de l'analyse, après recette et filtres).",
         f"# Seuil de significativité : {a:g} (bilatéral).",
         "# Les résultats doivent être identiques à ceux de Moanui, aux arrondis près ; les intervalles obtenus par",
         "# bootstrap peuvent différer légèrement (autre générateur aléatoire).", "",
         f"d <- read.csv2({rs(csv_name)}, fileEncoding = \"UTF-8-BOM\", check.names = FALSE)"]
    for c in stat_columns(spec):
        if c in cat:
            L.append(f"d${q(c)} <- factor(d${q(c)})")
    L.append("")
    y, g, x = v.get("y"), v.get("groupe"), v.get("x")
    if kind == "comparer_groupes":
        f = f"{q(y)} ~ {q(g)}"
        L.append(f"# Résumé par groupe\naggregate({f}, data = d, FUN = function(v) c(n = length(v), moyenne = mean(v), "
                 "mediane = median(v), ecart_type = sd(v)))")
        L.append(f"boxplot({f}, data = d)")
        L.append("\n# Conditions : normalité par groupe et égalité des variances (Brown-Forsythe = Levene sur médianes)")
        L.append(f"tapply(d${q(y)}, d${q(g)}, function(v) if (length(v) >= 3 && length(v) <= 5000) shapiro.test(v)$p.value else NA)")
        L.append(f"# car::leveneTest({f}, data = d, center = median)  # nécessite le paquet car")
        L.append("")
        if test == "t_welch":
            L += [f"t.test({f}, data = d, var.equal = FALSE, conf.level = {1 - a:g})",
                  "# d de Cohen (écart-type commun)",
                  f"gr <- split(d${q(y)}, d${q(g)})",
                  "sp <- sqrt(((length(gr[[1]]) - 1) * var(gr[[1]]) + (length(gr[[2]]) - 1) * var(gr[[2]])) / "
                  "(length(gr[[1]]) + length(gr[[2]]) - 2))",
                  "(mean(gr[[1]]) - mean(gr[[2]])) / sp"]
        elif test == "mann_whitney":
            L += [f"wilcox.test({f}, data = d, exact = FALSE, conf.int = TRUE)",
                  "# corrélation rang-bisériale (Kerby) : 2U / (n1 n2) - 1",
                  f"gr <- split(d${q(y)}, d${q(g)})",
                  f"U <- wilcox.test({f}, data = d, exact = FALSE)$statistic",
                  "2 * U / (length(gr[[1]]) * length(gr[[2]])) - 1"]
        else:
            if test == "anova":
                L += [f"m <- aov({f}, data = d)", "summary(m)", "# η² = SC effet / SC totale",
                      "sc <- summary(m)[[1]][[\"Sum Sq\"]]; sc[1] / sum(sc)"]
            elif test == "welch_anova":
                L += [f"oneway.test({f}, data = d, var.equal = FALSE)"]
            else:
                L += [f"k <- kruskal.test({f}, data = d)", "k", "# ε² = H / (n - 1)",
                      "unname(k$statistic) / (nrow(d) - 1)"]
            pw = (f"pairwise.wilcox.test(d${q(y)}, d${q(g)}, p.adjust.method = {rs(padj)}, exact = FALSE)"
                  if test == "kruskal" else
                  f"pairwise.t.test(d${q(y)}, d${q(g)}, p.adjust.method = {rs(padj)}, pool.sd = FALSE)")
            L += ["", f"# Comparaisons deux à deux (si le test global est significatif au seuil {a:g})", pw]
    elif kind == "association":
        L += [f"tab <- table(d${q(x)}, d${q(y)})", "tab"]
        if test == "fisher":
            L += ["fisher.test(tab)"]
        else:
            L += ["ch <- chisq.test(tab, correct = FALSE)", "ch",
                  "ch$expected  # effectifs attendus (condition : au moins 5 dans 80 % des cases)",
                  "ch$stdres    # résidus : |valeur| > 2 = combinaison plus ou moins fréquente qu'attendu",
                  "# V de Cramér", "sqrt(unname(ch$statistic) / (sum(tab) * (min(dim(tab)) - 1)))"]
    elif kind == "correlation":
        method = "spearman" if test == "spearman" else "pearson"
        L += [f"plot(d${q(x)}, d${q(y)})",
              f"cor.test(d${q(x)}, d${q(y)}, method = {rs(method)}"
              + (", exact = FALSE" if method == "spearman" else f", conf.level = {1 - a:g}") + ")"]
    elif kind == "regression":
        xs = x if isinstance(x, list) else [x]
        L += [f"m <- lm({q(y)} ~ {' + '.join(q(c) for c in xs)}, data = d)", "summary(m)",
              f"confint(m, level = {1 - a:g})", "plot(fitted(m), resid(m)); abline(h = 0, lty = 3)  # résidus"]
    elif kind == "glm":
        xs = x if isinstance(x, list) else [x]
        eff = v.get("effort")
        rhs = " + ".join(q(c) for c in xs) + (f" + offset(log({q(eff)}))" if eff else "")
        if test == "binomiale_negative":
            L += ["library(MASS)  # glm.nb", f"m <- glm.nb({q(y)} ~ {rhs}, data = d)"]
        else:
            L += [f"m <- glm({q(y)} ~ {rhs}, family = {GLM_FAMILY.get(test, 'poisson()')}, data = d)"]
        L += ["summary(m)",
              "# Effet de chaque facteur (test du rapport de vraisemblance ; F pour quasi-Poisson et Gamma)",
              f"drop1(m, test = {rs('F' if test in ('quasi_poisson', 'gamma') else 'Chisq')})",
              "# Effets en multiplicateurs (exp des coefficients) et intervalles de Wald",
              f"exp(cbind(estimation = coef(m), confint.default(m, level = {1 - a:g})))",
              "# Part de déviance expliquée", "1 - m$deviance / m$null.deviance"]
    return "\n".join(L) + "\n"


def stat_zip(script: str, csv_bytes: bytes, csv_name: str = "analyse_donnees.csv") -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("analyse.R", script.encode("utf-8"))
        z.writestr(csv_name, csv_bytes)
        z.writestr("LISEZMOI.txt", (
            "Code R équivalent de l'analyse, généré par Moanui.\n\n"
            "Ouvrez analyse.R dans RStudio (Session > Set Working Directory > To Source File Location), puis lancez-le "
            "ligne par ligne (Ctrl + Entrée) pour voir chaque résultat. Le CSV contient les lignes utilisées par "
            "l'analyse (séparateur « ; », virgule décimale).\n").encode("utf-8"))
    return buf.getvalue()
