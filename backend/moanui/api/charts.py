"""Graphiques enregistrés (spécification + gabarit), et leur fiche méthode."""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

from ..db import Database, new_id, now
from .deps import User, Workspace, current_user, dataset_access, get_db, get_settings, writable_dataset

router = APIRouter(prefix="/api", tags=["charts"])


class ChartIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    spec: dict
    svg: str | None = Field(default=None, max_length=8_000_000)  # rendu du graphique, joint à la fiche


@router.get("/datasets/{did}/charts")
def list_charts(did: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    dataset_access(db, user, did)
    rows = db.all("SELECT * FROM charts WHERE dataset_id = ? ORDER BY updated_at DESC", (did,))
    return [{**r, "spec": json.loads(r["spec"])} for r in rows]


@router.post("/datasets/{did}/charts")
def create_chart(did: str, body: ChartIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    writable_dataset(db, user, did)
    cid = new_id()
    db.execute("INSERT INTO charts(id, dataset_id, name, spec, created_by, created_at, updated_at) VALUES "
               "(?,?,?,?,?,?,?)", (cid, did, body.name, json.dumps(body.spec, ensure_ascii=False), user.id, now(),
                                   now()))
    return {"id": cid}


@router.put("/charts/{cid}")
def update_chart(cid: str, body: ChartIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    c = db.one("SELECT * FROM charts WHERE id = ?", (cid,))
    if not c:
        raise HTTPException(404, "Graphique introuvable.")
    writable_dataset(db, user, c["dataset_id"])
    db.execute("UPDATE charts SET name = ?, spec = ?, updated_at = ? WHERE id = ?",
               (body.name, json.dumps(body.spec, ensure_ascii=False), now(), cid))
    return {"ok": True}


@router.delete("/charts/{cid}")
def delete_chart(cid: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    c = db.one("SELECT * FROM charts WHERE id = ?", (cid,))
    if not c:
        raise HTTPException(404, "Graphique introuvable.")
    writable_dataset(db, user, c["dataset_id"])
    db.execute("DELETE FROM charts WHERE id = ?", (cid,))
    return {"ok": True}


AGG_LABELS = {"somme": "somme", "moyenne": "moyenne", "mediane": "médiane", "min": "minimum", "max": "maximum",
              "nombre": "nombre de valeurs", "nombre_lignes": "nombre de lignes",
              "nombre_distinct": "nombre de valeurs distinctes", "ecart_type": "écart-type"}


MARKS = {"barres": "barres", "lignes": "courbe", "aires": "aire", "points": "points"}
AXIS_LABELS = {"y": "axe gauche", "y2": "axe droit", "y3": "second axe gauche", "y4": "second axe droit"}

CHART_INFO = {
    "barres": ("Barres verticales", "Les longueurs se comparent précisément à partir d'une base commune : l'axe doit partir de zéro."),
    "barres_h": ("Barres horizontales", "Adaptées aux libellés longs et aux classements ; l'axe part de zéro."),
    "lignes": ("Courbes", "Montrent une évolution : l'axe horizontal doit être ordonné (temps) et régulier."),
    "aires": ("Aires", "Montrent l'évolution d'un total et de sa composition ; seules la série du bas et le total se lisent "
                       "précisément."),
    "combine": ("Barres et courbes", "Deux axes verticaux rendent la comparaison ambiguë : chaque axe doit être clairement "
                                     "légendé et l'échelle de l'un ne doit pas suggérer une corrélation."),
    "secteurs": ("Anneau", "Les angles et surfaces se comparent mal : à réserver à quelques parts d'un même tout."),
    "chaleur": ("Carte de chaleur", "La couleur code une quantité : une échelle séquentielle perceptivement uniforme est "
                                    "nécessaire pour que les écarts de teinte reflètent les écarts de valeurs."),
    "nuage": ("Nuage de points", "Montre une relation entre deux mesures et ses exceptions ; un lien n'est pas une cause."),
    "bulles": ("Bulles", "La taille code une troisième variable ; les surfaces se comparent moins bien que les positions."),
    "boites": ("Boîtes à moustaches", "Résument une distribution par ses quartiles ; les valeurs au-delà de 1,5 fois "
                                      "l'écart interquartile apparaissent individuellement."),
    "violons": ("Violons", "Montrent la forme complète de la distribution (estimation de densité)."),
    "histogramme": ("Histogramme", "Montre la distribution d'une mesure ; la forme dépend de la largeur des classes."),
    "nuage3d": ("Nuage 3D", "La perspective déforme les positions : à réserver à l'exploration."),
    "surface3d": ("Surface 3D", "La perspective masque une partie de la surface : à réserver à l'exploration."),
}


def _chart_fiche(ds: dict, body: ChartIn, user: User):
    from ..engine.recipe import describe_condition
    from ..fiche import Fiche

    s = body.spec
    t = s.get("template") or {}
    f = Fiche(f"Fiche méthode du graphique : {t.get('title') or body.name}", t.get("subtitle") or "")
    f.meta = [("Jeu de données", f"{ds['name']} (traitements décrits dans sa propre fiche méthode)"),
              ("Auteur", t.get("author") or user.display_name), ("Source affichée", t.get("source") or "")]
    f.meta = [(k, v) for k, v in f.meta if v]
    if body.svg and body.svg.lstrip().startswith("<svg"):
        f.fig("graphique", body.svg, t.get("title") or body.name)
    kind, advice = CHART_INFO.get(s.get("type"), (s.get("type"), ""))
    f.h("Ce qui est représenté")
    enc = [("Type", kind)]
    if s.get("x"):
        enc.append(("Axe horizontal", f"« {s['x']} »"))
    axes_used = set()
    for m in s.get("measures") or []:
        ax = "y" if s.get("type") == "barres_h" else (m.get("axis") or "y")
        axes_used.add(ax)
        mark = MARKS.get(m.get("mark") or "", "")
        extra = ", ".join(x for x in (mark, AXIS_LABELS.get(ax) if ax != "y" else "") if x)
        enc.append(("Mesure", f"{AGG_LABELS.get(m.get('agg'), m.get('agg'))} de « {m.get('column') or 'lignes'} »"
                    + (f" ({extra})" if extra else "")))
    axes = s.get("axes") or {}
    for ax in sorted(axes_used):
        cfg = axes.get(ax) or {}
        title = cfg.get("title") or (s.get("y_title") if ax == "y" else s.get("y2_title") if ax == "y2" else None)
        scale = cfg.get("scale") or (s.get("y_scale") if ax == "y" else None)
        bits = [f"titre « {title} »" if title else None, "échelle logarithmique" if scale == "log" else None,
                f"unité {cfg['suffix']}" if cfg.get("suffix") else None]
        lo = cfg.get("min", s.get("y_min") if ax == "y" else None)
        hi = cfg.get("max", s.get("y_max") if ax == "y" else None)
        if lo is not None or hi is not None:
            bits.append(f"bornes {lo if lo is not None else 'auto'} à {hi if hi is not None else 'auto'}")
        if len(axes_used) > 1 or any(bits):
            enc.append((AXIS_LABELS[ax].capitalize(), ", ".join(b for b in bits if b) or "réglages automatiques"))
    for r in s.get("refs") or []:
        if r.get("value") in (None, "") and r.get("kind") != "note":
            continue
        what = {"ligne_h": f"ligne de référence à {r.get('value')}",
                "ligne_v": f"ligne verticale sur « {r.get('value')} »",
                "zone_v": f"zone de « {r.get('value')} » à « {r.get('value2') or r.get('value')} »",
                "note": f"note sur « {r.get('value')} »"}.get(r.get("kind"), "repère")
        enc.append(("Repère", what + (f" : {r['label']}" if r.get("label") else "")))
    if s.get("series"):
        enc.append(("Couleur / séries", f"« {s['series']} »"))
    if s.get("facet"):
        enc.append(("Petits multiples", f"un panneau par valeur de « {s['facet']} »"))
    if s.get("filters"):
        enc.append(("Filtres propres au graphique", " ET ".join(describe_condition(x) for x in s["filters"])))
    if s.get("y_scale") == "log" or any((c or {}).get("scale") == "log" for c in (s.get("axes") or {}).values()):
        enc.append(("Échelle logarithmique", "les écarts se lisent en rapports (× 10), pas en différences"))
    if s.get("facet") and s.get("facet_scale") == "commune":
        enc.append(("Échelle des panneaux", "commune : les hauteurs se comparent d'un panneau à l'autre"))
    f.kv(enc)
    f.h("Calcul")
    f.p("Les valeurs sont calculées sur le résultat de la recette du jeu de données (jamais sur le fichier brut modifié), "
        "après application des filtres du graphique. Chaque mesure est agrégée par modalité de l'axe horizontal"
        + (" et de la série" if s.get("series") else "") + (" et par panneau" if s.get("facet") else "") + ".")
    f.h("Choix de représentation")
    if len(axes_used) > 1:
        advice += (f" Le graphique utilise {len(axes_used)} axes verticaux : chaque axe a sa propre échelle, la position "
                   "relative des courbes ne signifie donc rien en elle-même ; les titres d'axes portent l'unité.")
    f.p(f"{advice} Ce choix suit les résultats de perception graphique : on compare mieux des positions sur une échelle "
        f"commune que des longueurs, des angles ou des surfaces {f.cite('cleveland1984')}. La palette catégorielle utilisée "
        f"est distinguable par les personnes daltoniennes et chaque élément non essentiel (fond, quadrillage) est atténué "
        f"{f.cite('crameri2020', 'wilke2019', 'tufte2001')}.")
    f.h("Lecture")
    f.p(t.get("caption") or "*À compléter par l'auteur : ce que montre le graphique, ses limites (période, couverture, "
                            "secret statistique).*")
    return f


@router.post("/datasets/{did}/charts/method.md")
def chart_method(did: str, body: ChartIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    """Fiche méthode d'un graphique : ce qui est représenté et comment c'est calculé."""
    ds, _ = dataset_access(db, user, did)
    return Response(_chart_fiche(ds, body, user).markdown(), media_type="text/markdown; charset=utf-8")


@router.post("/datasets/{did}/charts/method.zip")
def chart_method_zip(did: str, body: ChartIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    ds, _ = dataset_access(db, user, did)
    return Response(_chart_fiche(ds, body, user).zip("graphique_methode"), media_type="application/zip",
                    headers={"Content-Disposition": 'attachment; filename="graphique_methode.zip"'})


@router.post("/datasets/{did}/charts/method.{fmt}")
def chart_method_export(did: str, fmt: str, body: ChartIn, user: User = Depends(current_user),
                        db: Database = Depends(get_db)):
    """Fiche méthode du graphique en Word (docx) ou PDF."""
    ds, _ = dataset_access(db, user, did)
    return _chart_fiche(ds, body, user).response(fmt, "graphique_methode")


def _chart_r(db: Database, settings, user: User, did: str, spec: dict):
    """Données du graphique (même requête que l'affichage) + script R équivalent."""
    from ..engine import pipeline
    from ..engine.sql import RecipeError
    from ..rcode import chart_r, chart_request, named_data, to_csv
    from ..themes import default_theme

    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        try:
            data = pipeline.chart_data(ws.con, ws.plan(ds), chart_request(spec))
        except RecipeError as e:
            raise HTTPException(400, str(e)) from e
    st = db.one("SELECT theme FROM structures WHERE id = ?", (ds["structure_id"],))
    theme = json.loads(st["theme"]) if st else default_theme()
    script, notes = chart_r(spec, data, theme)
    cols, rows, _ = named_data(spec, data)
    return script, notes, to_csv(cols, rows)


@router.post("/datasets/{did}/charts/r")
def chart_r_code(did: str, body: ChartIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                 settings=Depends(get_settings)):
    """Code R équivalent (ggplot2) du graphique, à afficher et copier."""
    script, notes, _ = _chart_r(db, settings, user, did, body.spec)
    return {"script": script, "avertissements": notes}


@router.post("/datasets/{did}/charts/r.zip")
def chart_r_zip(did: str, body: ChartIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                settings=Depends(get_settings)):
    """Script R + données agrégées du graphique (CSV) dans une archive."""
    from ..rcode import chart_zip

    script, _, csv_bytes = _chart_r(db, settings, user, did, body.spec)
    return Response(chart_zip(script, csv_bytes), media_type="application/zip",
                    headers={"Content-Disposition": 'attachment; filename="graphique_R.zip"'})


@router.get("/recent")
def recent(user: User = Depends(current_user), db: Database = Depends(get_db)):
    """Derniers graphiques, analyses et cartes de la structure active (page d'accueil)."""
    from .deps import active_structure

    sid = active_structure(user)
    charts = db.all("SELECT c.id, c.name, c.dataset_id, d.name AS dataset, c.updated_at AS at, u.display_name AS who "
                    "FROM charts c JOIN datasets d ON d.id = c.dataset_id LEFT JOIN users u ON u.id = c.created_by "
                    "WHERE d.structure_id = ? ORDER BY c.updated_at DESC LIMIT 6", (sid,))
    analyses = db.all("SELECT a.id, a.titre AS name, a.dataset_id, d.name AS dataset, a.created_at AS at, "
                      "u.display_name AS who FROM analyses a JOIN datasets d ON d.id = a.dataset_id "
                      "LEFT JOIN users u ON u.id = a.created_by WHERE d.structure_id = ? "
                      "ORDER BY a.created_at DESC LIMIT 6", (sid,))
    maps = db.all("SELECT m.id, m.name, m.updated_at AS at, u.display_name AS who FROM maps m "
                  "LEFT JOIN users u ON u.id = m.created_by WHERE m.structure_id = ? ORDER BY m.updated_at DESC LIMIT 6",
                  (sid,))
    return {"graphiques": [dict(r) for r in charts], "analyses": [dict(r) for r in analyses],
            "cartes": [dict(r) for r in maps]}
