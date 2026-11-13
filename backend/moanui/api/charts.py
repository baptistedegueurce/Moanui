"""Graphiques enregistrés (spécification + gabarit), et leur fiche méthode."""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

from ..db import Database, new_id, now
from .deps import User, current_user, dataset_access, get_db, writable_dataset

router = APIRouter(prefix="/api", tags=["charts"])


class ChartIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    spec: dict


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


@router.post("/datasets/{did}/charts/method.md")
def chart_method(did: str, body: ChartIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    """Fiche méthode d'un graphique : ce qui est représenté et comment c'est calculé."""
    ds, _ = dataset_access(db, user, did)
    s = body.spec
    t = s.get("template") or {}
    L = [f"# Fiche méthode du graphique : {t.get('title') or body.name}", ""]
    L.append(f"- **Jeu de données** : {ds['name']} (voir sa fiche méthode pour les traitements)")
    L.append(f"- **Auteur** : {t.get('author') or user.display_name}")
    if t.get("source"):
        L.append(f"- **Source affichée** : {t['source']}")
    L += ["", "## Ce qui est représenté", ""]
    L.append(f"- **Type** : {s.get('type')}")
    if s.get("x"):
        L.append(f"- **Axe horizontal** : « {s['x']} »")
    for m in s.get("measures") or []:
        axis = " (axe secondaire)" if m.get("axis") == "y2" else ""
        L.append(f"- **Mesure** : {AGG_LABELS.get(m.get('agg'), m.get('agg'))} de « {m.get('column') or 'lignes'} »"
                 f"{axis}")
    if s.get("series"):
        L.append(f"- **Couleur / séries** : « {s['series']} »")
    if s.get("facet"):
        L.append(f"- **Petits multiples** : un panneau par valeur de « {s['facet']} »")
    if s.get("filters"):
        from ..engine.recipe import describe_condition

        L.append("- **Filtres propres au graphique** : " + " ET ".join(describe_condition(f) for f in s["filters"]))
    if s.get("y_scale") == "log":
        L.append("- **Échelle verticale logarithmique** : les écarts se lisent en rapports (×10), pas en différences.")
    L += ["", "## Lecture", "", t.get("caption") or "_À compléter : que montre ce graphique, quelles limites ?_", ""]
    return Response("\n".join(L), media_type="text/markdown; charset=utf-8")
