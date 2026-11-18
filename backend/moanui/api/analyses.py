"""Statistiques guidées : catalogue, exécution avec vérification des conditions, historique, fiches."""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from .. import stats
from ..db import Database, new_id, now
from ..engine.recipe import describe_condition
from ..engine.sql import RecipeError
from ..engine import pipeline
from .deps import User, Workspace, current_user, dataset_access, get_db, get_settings

router = APIRouter(prefix="/api", tags=["statistiques"])


class StatIn(BaseModel):
    analyse: str
    variables: dict
    test: str | None = None
    filters: list[dict] = []
    force: bool = False
    justification: str | None = None
    save: bool = False
    options: dict | None = None  # mode expert : {"alpha": 0.05, "correction": "holm"}


@router.get("/stats/catalogue")
def catalogue(_: User = Depends(current_user)):
    return stats.ANALYSES


@router.get("/stats/options")
def stat_options(_: User = Depends(current_user)):
    """Réglages du mode expert."""
    return {"alphas": list(stats.ALPHAS),
            "corrections": [{"value": k, "label": v[0]} for k, v in stats.CORRECTIONS.items()]}


def _run(db, settings, user, did: str, body: StatIn) -> tuple[dict, dict, dict]:
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        if plan.error:
            raise HTTPException(400, "La recette contient une erreur : corrigez-la avant d'analyser.")
        try:
            where = pipeline._view_filters(plan.schema, body.filters, None)
            robj = stats.run(ws.con, plan, body.model_dump(), where)
            res = robj.as_dict()
        except RecipeError as e:
            raise HTTPException(400, str(e)) from e
    spec = body.model_dump()
    spec["filtres_desc"] = " ET ".join(describe_condition(f) for f in body.filters) if body.filters else ""
    if res["bloque"]:
        if body.force and not (body.justification or "").strip():
            raise HTTPException(400, "Pour passer outre une condition bloquante, indiquez une justification.")
        if not body.force:
            # résultats masqués tant que l'utilisateur n'a pas choisi : alternative ou passage en force justifié
            res["resultats"], res["interpretation"] = [], []
            res["rapport"], res["discussion"], res["resume"] = [], [], ""
            res["discussion_src"], res["resume_src"] = [], ""
            res["tableaux"] = res["tableaux"][:1]
        res["force"] = body.force
    res["_fd"] = robj.fd
    return ds, res, spec


@router.post("/datasets/{did}/stats")
def run_stat(did: str, body: StatIn, user: User = Depends(current_user), db: Database = Depends(get_db),
             settings=Depends(get_settings)):
    ds, res, spec = _run(db, settings, user, did, body)
    res.pop("_fd", None)
    if body.save and (not res["bloque"] or body.force):
        aid = new_id()
        db.execute("INSERT INTO analyses(id, dataset_id, titre, spec, resultat, created_by, created_at) VALUES (?,?,?,?,?,?,?)",
                   (aid, did, res["titre"], json.dumps(spec, ensure_ascii=False), json.dumps(res, ensure_ascii=False),
                    user.id, now()))
        res["id"] = aid
        db.log("analyse", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did, test=res["test_label"],
               force=body.force)
    return res


@router.get("/datasets/{did}/stats")
def history(did: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    dataset_access(db, user, did)
    rows = db.all("SELECT a.id, a.titre, a.spec, a.created_at, u.display_name AS auteur FROM analyses a "
                  "JOIN users u ON u.id = a.created_by WHERE dataset_id = ? ORDER BY a.created_at DESC", (did,))
    for r in rows:
        r["spec"] = json.loads(r["spec"])
    return rows


def _stat_fiche(db, settings, user, did, body):
    ds, res, spec = _run(db, settings, user, did, body)
    if res["bloque"] and not body.force:
        raise HTTPException(400, "Analyse bloquée : choisissez l'alternative proposée ou justifiez le passage en force.")
    fd = res.pop("_fd", {})
    return stats.method_fiche(res, spec, ds["name"], user.display_name, body.justification, fd)


@router.post("/datasets/{did}/stats/method.md")
def stat_method(did: str, body: StatIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                settings=Depends(get_settings)):
    return Response(_stat_fiche(db, settings, user, did, body).markdown(), media_type="text/markdown; charset=utf-8")


@router.post("/datasets/{did}/stats/method.html")
def stat_method_html(did: str, body: StatIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                     settings=Depends(get_settings)):
    return Response(_stat_fiche(db, settings, user, did, body).html(), media_type="text/html; charset=utf-8")


@router.post("/datasets/{did}/stats/method.zip")
def stat_method_zip(did: str, body: StatIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                    settings=Depends(get_settings)):
    return Response(_stat_fiche(db, settings, user, did, body).zip("analyse_methode"), media_type="application/zip",
                    headers={"Content-Disposition": 'attachment; filename="analyse_methode.zip"'})


@router.post("/datasets/{did}/stats/method.{fmt}")
def stat_method_export(did: str, fmt: str, body: StatIn, user: User = Depends(current_user),
                       db: Database = Depends(get_db), settings=Depends(get_settings)):
    """Fiche méthode statistique en Word (docx) ou PDF."""
    return _stat_fiche(db, settings, user, did, body).response(fmt, "analyse_methode")


def _stat_r(db, settings, user, did: str, body: StatIn):
    from ..engine.sql import is_numeric_type
    from ..rcode import stat_columns, stat_r, to_csv

    ds, res, _ = _run(db, settings, user, did, body)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        cols = stat_columns(body.model_dump())
        where = pipeline._view_filters(plan.schema, body.filters, None)
        try:
            data, _, n = stats.fetch(ws.con, plan.sql, plan.schema, cols, where)
        except RecipeError as e:
            raise HTTPException(400, str(e)) from e
        cat = {c for c in cols if not is_numeric_type(plan.schema[c])}
    script = stat_r(body.model_dump(), res["test"], cat, stats.clean_options(body.options))
    if res["bloque"]:
        bl = [c["nom"] for c in res["checks"] if not c["ok"] and c["niveau"] == "bloquant"]
        script = (f"# Attention : Moanui a bloqué cette analyse (condition non remplie : {', '.join(dict.fromkeys(bl))}).\n"
                  "# Le script est fourni pour vérification ; interprétez les résultats avec prudence.\n") + script
    rows = [[(v.item() if hasattr(v, "item") else v) for v in r] for r in zip(*(data[c] for c in cols))] if n else []
    return script, to_csv(cols, rows)


@router.post("/datasets/{did}/stats/r")
def stat_r_code(did: str, body: StatIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                settings=Depends(get_settings)):
    """Code R équivalent de l'analyse."""
    script, _ = _stat_r(db, settings, user, did, body)
    return {"script": script, "avertissements": []}


@router.post("/datasets/{did}/stats/r.zip")
def stat_r_zip(did: str, body: StatIn, user: User = Depends(current_user), db: Database = Depends(get_db),
               settings=Depends(get_settings)):
    from ..rcode import stat_zip

    script, csv_bytes = _stat_r(db, settings, user, did, body)
    return Response(stat_zip(script, csv_bytes), media_type="application/zip",
                    headers={"Content-Disposition": 'attachment; filename="analyse_R.zip"'})
