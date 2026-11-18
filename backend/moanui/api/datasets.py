"""Jeux de données : import, recette, consultation, contrôles, exports, fiches méthode."""

from __future__ import annotations

import io
import json
import shutil
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

from .. import methods
from ..biblio import REFS
from ..fiche import _short
from ..db import Database, new_id, now
from ..engine import halieutique, pipeline, sensitivity, store
from ..engine.formula import function_help
from ..engine.recipe import CAST_TYPES, JOIN_KINDS, OPS, TRANSFORMS, describe_step, step_types
from ..engine.sql import RecipeError, ident, string_lit
from .deps import (
    structure_name,
    User,
    Workspace,
    active_structure,
    current_user,
    dataset_access,
    get_db,
    get_settings,
    raw_of,
    require_role,
    writable_dataset,
)

router = APIRouter(prefix="/api", tags=["datasets"])
MAX_UPLOAD = 1024 * 1024 * 1024  # 1 Go
XLSX_MAX_ROWS = 1_048_575


def bad(e: Exception):
    raise HTTPException(400, str(e))


class StepIn(BaseModel):
    type: str
    params: dict = {}
    comment: str = ""
    position: int | None = None  # insérer à cette position (par défaut : à la fin)


class StepPatch(BaseModel):
    params: dict | None = None
    comment: str | None = None
    enabled: bool | None = None


class ReorderIn(BaseModel):
    order: list[str]


class DatasetPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    notes: str | None = Field(default=None, max_length=50000)
    kind: str | None = None


class PageIn(BaseModel):
    offset: int = 0
    limit: int = 100
    sort: list[dict] = []
    filters: list[dict] = []
    search: str | None = None
    upto: int | None = None  # aperçu de la recette jusqu'à l'étape n


class BatchIn(BaseModel):
    steps: list[StepIn]


class ShareIn(BaseModel):
    structure_id: str


# --------------------------------------------------------------------------- métadonnées


@router.get("/meta")
def meta(_: User = Depends(current_user)):
    from .. import __version__

    return {
        "version": __version__,
        "steps": step_types(),
        "operators": OPS,
        "cast_types": {k: v[1] for k, v in CAST_TYPES.items()},
        "transforms": {k: {"label": v[0], "kind": v[1]} for k, v in TRANSFORMS.items()},
        "join_kinds": {k: v[1] for k, v in JOIN_KINDS.items()},
        "functions": function_help(),
        "units": {k: {u: halieutique.UNIT_LABELS[u] for u in v} for k, v in halieutique.UNITS.items()},
        "referentiels": {k: {"nom": r["nom"], "description": r["description"], "colonnes": r.get("colonnes", []),
                             "especes": r.get("especes")} for k, r in halieutique.referentiels().items()},
        "templates": {k: {"nom": t["nom"], "description": t["description"]} for k, t in halieutique.TEMPLATES.items()},
        "biblio": {k: {"court": _short(v), "complet": v} for k, v in REFS.items()},
    }


def _users_map(db: Database) -> dict[str, str]:
    return {u["id"]: u["display_name"] for u in db.all("SELECT id, display_name FROM users")}


def _summary(db: Database, ds: dict, user: User, mode: str | None = None) -> dict:
    raw = raw_of(db, ds)
    recipe = json.loads(ds["recipe"])
    structure = db.one("SELECT name, short_name FROM structures WHERE id = ?", (ds["structure_id"],))
    return {
        "id": ds["id"],
        "name": ds["name"],
        "description": ds["description"],
        "kind": ds["kind"],
        "structure_id": ds["structure_id"],
        "structure_name": structure["short_name"] if structure else "?",
        "source_name": raw["original_name"],
        "n_rows_raw": raw["n_rows"],
        "n_steps": len(recipe),
        "created_at": ds["created_at"],
        "updated_at": ds["updated_at"],
        "mode": mode,
        "shared_from_other": user.role_in(ds["structure_id"]) is None,
    }


@router.get("/datasets")
def list_datasets(user: User = Depends(current_user), db: Database = Depends(get_db)):
    sid = active_structure(user)
    own = db.all("SELECT * FROM datasets WHERE structure_id = ? ORDER BY updated_at DESC", (sid,))
    shared = db.all("SELECT d.* FROM datasets d JOIN dataset_shares s ON s.dataset_id = d.id "
                    "WHERE s.structure_id = ? AND d.structure_id <> ? ORDER BY d.updated_at DESC", (sid, sid))
    mode = "ecriture" if user.role_in(sid) in ("admin", "analyste") else "lecture"
    return [_summary(db, d, user, mode) for d in own] + [_summary(db, d, user, "lecture") for d in shared]


# --------------------------------------------------------------------------- import


@router.post("/datasets/inspect")
async def inspect_upload(file: UploadFile = File(...), _: User = Depends(current_user)):
    """Avant import d'un classeur Excel : liste des feuilles."""
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in (".xlsx", ".xlsm"):
        return {"sheets": []}
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        shutil.copyfileobj(file.file, tmp)
    try:
        return {"sheets": store.list_sheets(Path(tmp.name))}
    except Exception as e:
        raise HTTPException(400, f"Classeur illisible : {e}") from e
    finally:
        Path(tmp.name).unlink(missing_ok=True)


@router.post("/datasets/import")
async def import_dataset(
    file: UploadFile = File(...),
    name: str = Form(""),
    description: str = Form(""),
    kind: str = Form("generique"),
    options: str = Form("{}"),
    user: User = Depends(current_user),
    db: Database = Depends(get_db),
    settings=Depends(get_settings),
):
    sid = active_structure(user)
    require_role(user, sid, "analyste")
    try:
        opts = json.loads(options or "{}")
    except json.JSONDecodeError as e:
        raise HTTPException(400, "Options d'import invalides.") from e
    original = Path(file.filename or "fichier").name
    suffix = Path(original).suffix.lower()
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False, dir=settings.home) as tmp:
        size = 0
        while chunk := await file.read(1 << 20):
            size += len(chunk)
            if size > MAX_UPLOAD:
                Path(tmp.name).unlink(missing_ok=True)
                raise HTTPException(413, "Fichier trop volumineux (1 Go maximum).")
            tmp.write(chunk)
    try:
        info = store.import_file(Path(tmp.name), original, settings.raw_dir, opts)
    except RecipeError as e:
        bad(e)
    finally:
        Path(tmp.name).unlink(missing_ok=True)

    if not db.one("SELECT id FROM raw_files WHERE id = ?", (info["raw_id"],)):
        db.execute("INSERT INTO raw_files(id, sha256, columns, import_report, original_name, format, size_bytes, "
                   "n_rows, import_options, imported_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                   (info["raw_id"], info["sha256"], json.dumps(info["schema"]), json.dumps(info["report"]),
                    original, info["format"], info["size_bytes"], info["n_rows"], json.dumps(info["options"]),
                    now()))
    sens = sensitivity.detect(list(info["schema"]))
    did = new_id()
    db.execute("INSERT INTO datasets(id, structure_id, name, description, kind, raw_id, recipe, sensitive_columns, "
               "created_by, created_at, updated_at) VALUES (?,?,?,?,?,?,'[]',?,?,?,?)",
               (did, sid, (name or Path(original).stem)[:200], description[:5000], kind, info["raw_id"],
                json.dumps(sens), user.id, now(), now()))
    db.log("import", user_id=user.id, structure_id=sid, dataset_id=did, file=original, sha256=info["sha256"],
           rows=info["n_rows"])
    return {"id": did, "report": info["report"], "n_rows": info["n_rows"], "sensitive": sens}


@router.post("/datasets/{did}/duplicate")
def duplicate(did: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    """Copie de travail (même fichier brut, recette recopiée) : utile pour essayer sans risque
    ou pour reprendre un jeu partagé par une autre structure."""
    ds, _ = dataset_access(db, user, did)
    sid = active_structure(user)
    require_role(user, sid, "analyste")
    nid = new_id()
    db.execute("INSERT INTO datasets(id, structure_id, name, description, kind, raw_id, recipe, notes, "
               "sensitive_columns, created_by, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
               (nid, sid, f"{ds['name']} (copie)"[:200], ds["description"], ds["kind"], ds["raw_id"], ds["recipe"],
                ds["notes"], ds["sensitive_columns"], user.id, now(), now()))
    db.log("copie", user_id=user.id, structure_id=sid, dataset_id=nid, source=did)
    return {"id": nid}


@router.delete("/datasets/{did}")
def delete_dataset(did: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    ds = writable_dataset(db, user, did)
    used = [d["name"] for d in db.all("SELECT name, recipe FROM datasets WHERE id <> ?", (did,))
            if did in d["recipe"]]
    if used:
        raise HTTPException(409, f"Ce jeu est utilisé (jointure ou empilement) par : {', '.join(used)}.")
    db.execute("DELETE FROM datasets WHERE id = ?", (did,))
    db.log("suppression_jeu", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did, name=ds["name"])
    return {"ok": True, "message": "Jeu supprimé. Le fichier brut est conservé dans l'espace de travail."}


@router.patch("/datasets/{did}")
def patch_dataset(did: str, body: DatasetPatch, user: User = Depends(current_user), db: Database = Depends(get_db)):
    ds = writable_dataset(db, user, did)
    db.execute("UPDATE datasets SET name = ?, description = ?, notes = ?, kind = ?, updated_at = ? WHERE id = ?",
               (body.name or ds["name"], ds["description"] if body.description is None else body.description,
                ds["notes"] if body.notes is None else body.notes, body.kind or ds["kind"], now(), did))
    return {"ok": True}


# --------------------------------------------------------------------------- consultation


@router.get("/datasets/{did}")
def get_dataset(did: str, user: User = Depends(current_user), db: Database = Depends(get_db),
                settings=Depends(get_settings)):
    ds, mode = dataset_access(db, user, did)
    raw = raw_of(db, ds)
    users = _users_map(db)
    recipe = json.loads(ds["recipe"])
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        pipeline.step_counts(ws.con, plan)
    by_id = {s["id"]: s for s in recipe}
    steps = []
    for st in plan.steps:
        s = by_id.get(st.get("id"), {})
        steps.append({**st, "type": s.get("type"), "params": s.get("params"), "comment": s.get("comment", ""),
                      "author": users.get(s.get("author")), "at": s.get("at")})
    shares = db.all("SELECT s.structure_id, st.name FROM dataset_shares s JOIN structures st ON st.id = s.structure_id "
                    "WHERE s.dataset_id = ?", (did,))
    return {
        **_summary(db, ds, user, mode),
        "notes": ds["notes"],
        "raw": {"name": raw["original_name"], "sha256": raw["sha256"], "size_bytes": raw["size_bytes"],
                "n_rows": raw["n_rows"], "imported_at": raw["imported_at"],
                "report": json.loads(raw["import_report"])},
        "created_by": users.get(ds["created_by"]),
        "schema": [{"name": c, "type": t} for c, t in plan.schema.items()],
        "steps": steps,
        "error": plan.error,
        "sensitive": sensitivity.detect(list(plan.schema)),
        "shares": shares,
    }


@router.post("/datasets/{did}/rows")
def rows(did: str, body: PageIn, user: User = Depends(current_user), db: Database = Depends(get_db),
         settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds, upto=body.upto)
        try:
            return pipeline.page(ws.con, plan, body.offset, body.limit, body.sort, body.filters, body.search)
        except RecipeError as e:
            bad(e)


@router.get("/datasets/{did}/profile")
def profile(did: str, user: User = Depends(current_user), db: Database = Depends(get_db),
            settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        res = pipeline.profile(ws.con, plan)
        res["warnings"] += consistency_checks(ws.con, plan)
        return res


def consistency_checks(con, plan) -> list[dict]:
    """Contrôles métier génériques : un code doit avoir un seul libellé, un identifiant un seul nom…"""
    out = []
    cols = list(plan.schema)
    src = f"({plan.sql})"
    pairs = []
    for c in cols:
        low = c.lower()
        for suf_code, suf_lib in (("_cod", "_lib"), ("_code", "_libelle"), ("_cod", "_lib_fao_francais")):
            if low.endswith(suf_code):
                stem = c[: -len(suf_code)]
                for d in cols:
                    if d.lower() == (stem + suf_lib).lower():
                        pairs.append((c, d))
    for code, lib in pairs:
        n = con.execute(f"SELECT count(*) FROM (SELECT {ident(code)} FROM {src} WHERE {ident(code)} IS NOT NULL "
                        f"GROUP BY 1 HAVING count(DISTINCT {ident(lib)}) > 1)").fetchone()[0]
        if n:
            ex = con.execute(f"SELECT {ident(code)}, list(DISTINCT {ident(lib)}) FROM {src} GROUP BY 1 "
                             f"HAVING count(DISTINCT {ident(lib)}) > 1 LIMIT 3").fetchall()
            exs = "; ".join(f"{a} → {', '.join(map(str, b))}" for a, b in ex)
            out.append({"niveau": "attention", "colonne": code,
                        "message": f"{n} code(s) de « {code} » ont plusieurs libellés dans « {lib} » ({exs})."})
    # identifiant de navire vs nom
    idc = next((c for c in cols if c.lower() in ("cfr_cod", "navs_cod", "cfr", "navire_cod")), None)
    namec = next((c for c in cols if c.lower() in ("nom_navire", "navire_nom", "nom_nav")), None)
    if idc and namec:
        n = con.execute(f"SELECT count(*) FROM (SELECT {ident(namec)} FROM {src} GROUP BY 1 "
                        f"HAVING count(DISTINCT {ident(idc)}) > 1)").fetchone()[0]
        if n:
            out.append({"niveau": "info", "colonne": namec,
                        "message": f"{n} nom(s) de navire correspondent à plusieurs identifiants « {idc} » : "
                                   f"utilisez « {idc} » (et non le nom) pour compter ou regrouper les navires."})
    # année de référence vs dates
    yearc = next((c for c in cols if c.lower() in ("an_ref", "annee", "année", "year")), None)
    if yearc and pipeline.is_numeric_type(plan.schema[yearc]):
        for d, t in plan.schema.items():
            if t.upper().startswith(("DATE", "TIMESTAMP")):
                n = con.execute(f"SELECT count_if(year({ident(d)}) <> {ident(yearc)}) FROM {src}").fetchone()[0]
                if n:
                    out.append({"niveau": "attention", "colonne": d,
                                "message": f"{n} ligne(s) où l'année de « {d} » diffère de « {yearc} »."})
    # dates dans le futur
    for d, t in plan.schema.items():
        if t.upper().startswith(("DATE", "TIMESTAMP")):
            n = con.execute(f"SELECT count_if(CAST({ident(d)} AS DATE) > current_date) FROM {src}").fetchone()[0]
            if n:
                out.append({"niveau": "attention", "colonne": d, "message": f"{n} date(s) dans le futur."})
    return out


@router.get("/datasets/{did}/values/{column}")
def values(did: str, column: str, search: str | None = None, limit: int = 500, user: User = Depends(current_user),
           db: Database = Depends(get_db), settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        try:
            return pipeline.unique_values(ws.con, ws.plan(ds), column, search, limit)
        except RecipeError as e:
            bad(e)


@router.post("/datasets/{did}/chart-data")
def chart_data(did: str, spec: dict, user: User = Depends(current_user), db: Database = Depends(get_db),
               settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        try:
            return pipeline.chart_data(ws.con, ws.plan(ds), spec)
        except RecipeError as e:
            bad(e)


# --------------------------------------------------------------------------- recette


def _save_recipe(db: Database, did: str, recipe: list[dict]) -> None:
    db.execute("UPDATE datasets SET recipe = ?, updated_at = ? WHERE id = ?",
               (json.dumps(recipe, ensure_ascii=False), now(), did))


def _enrich(db: Database, step: dict) -> None:
    """Mémorise les noms des jeux associés pour des fiches méthode lisibles."""
    p = step.get("params") or {}
    if step.get("type") == "join" and p.get("dataset_id"):
        d = db.one("SELECT name FROM datasets WHERE id = ?", (p["dataset_id"],))
        p["dataset_name"] = d["name"] if d else p["dataset_id"]
    if step.get("type") == "union":
        names = []
        for i in p.get("dataset_ids") or []:
            d = db.one("SELECT name FROM datasets WHERE id = ?", (i,))
            names.append(d["name"] if d else i)
        p["dataset_names"] = names


@router.post("/datasets/{did}/steps/check")
def check_step(did: str, body: StepIn, user: User = Depends(current_user), db: Database = Depends(get_db),
               settings=Depends(get_settings)):
    """Valide une étape sans l'enregistrer : erreurs, diagnostics et aperçu."""
    ds, _ = dataset_access(db, user, did)
    step = {"id": "apercu", "type": body.type, "params": body.params}
    _enrich(db, step)
    recipe = json.loads(ds["recipe"])
    pos = len(recipe) if body.position is None else max(0, min(body.position, len(recipe)))
    with Workspace(db, settings, user) as ws:
        try:
            before = ws.plan(ds, recipe=recipe[:pos])
            if before.error:
                raise RecipeError(f"Étape {before.error['index']} en erreur : {before.error['message']}")
            schema = ws.check(ds, recipe[:pos], step)
            diag = ws.diagnose(ds, before, step)
            after = ws.plan(ds, recipe=recipe[:pos] + [step])
            n_before = ws.con.execute(f"SELECT count(*) FROM ({before.sql})").fetchone()[0]
            n_after = ws.con.execute(f"SELECT count(*) FROM ({after.sql})").fetchone()[0]
            preview = pipeline.page(ws.con, after, 0, 20)
        except RecipeError as e:
            return {"ok": False, "error": str(e)}
    return {"ok": True, "description": describe_step(step), "schema": schema, "diagnostics": diag,
            "n_before": n_before, "n_after": n_after, "preview": preview}


@router.post("/datasets/{did}/steps")
def add_step(did: str, body: StepIn, user: User = Depends(current_user), db: Database = Depends(get_db),
             settings=Depends(get_settings)):
    ds = writable_dataset(db, user, did)
    recipe = json.loads(ds["recipe"])
    step = {"id": new_id()[:12], "type": body.type, "params": body.params, "comment": body.comment[:2000],
            "enabled": True, "author": user.id, "at": now()}
    _enrich(db, step)
    pos = len(recipe) if body.position is None else max(0, min(body.position, len(recipe)))
    with Workspace(db, settings, user) as ws:
        try:
            ws.check(ds, recipe[:pos], step)
            new_recipe = recipe[:pos] + [step] + recipe[pos:]
            after = ws.plan(ds, recipe=new_recipe)
        except RecipeError as e:
            bad(e)
    _save_recipe(db, did, new_recipe)
    db.log("etape_ajoutee", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did,
           step=describe_step(step))
    return {"id": step["id"], "description": describe_step(step), "downstream_error": after.error}


@router.get("/datasets/{did}/templates/{tid}")
def template_proposal(did: str, tid: str, user: User = Depends(current_user), db: Database = Depends(get_db),
                      settings=Depends(get_settings)):
    """Étapes proposées par un modèle de traitement, adaptées aux colonnes du jeu."""
    ds, _ = dataset_access(db, user, did)
    t = halieutique.TEMPLATES.get(tid)
    if not t:
        raise HTTPException(404, "Modèle inconnu.")
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
    if plan.error:
        raise HTTPException(400, "Corrigez d'abord l'étape en erreur de la recette.")
    steps = t["build"](plan.schema)
    for st in steps:
        st["description"] = describe_step(st)
    return {"nom": t["nom"], "description": t["description"], "steps": steps}


@router.post("/datasets/{did}/steps/batch")
def add_steps(did: str, body: BatchIn, user: User = Depends(current_user), db: Database = Depends(get_db),
              settings=Depends(get_settings)):
    """Ajoute plusieurs étapes d'un coup (modèle de traitement) : tout ou rien."""
    ds = writable_dataset(db, user, did)
    recipe = json.loads(ds["recipe"])
    new_recipe = list(recipe)
    with Workspace(db, settings, user) as ws:
        for i, b in enumerate(body.steps, start=1):
            step = {"id": new_id()[:12], "type": b.type, "params": b.params, "comment": b.comment[:2000],
                    "enabled": True, "author": user.id, "at": now()}
            _enrich(db, step)
            try:
                ws.check(ds, new_recipe, step)
            except RecipeError as e:
                raise HTTPException(400, f"Étape {i} ({describe_step(step)}) : {e}") from e
            new_recipe.append(step)
    _save_recipe(db, did, new_recipe)
    db.log("etapes_ajoutees", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did,
           n=len(body.steps))
    return {"ok": True, "n": len(body.steps)}


@router.post("/datasets/{did}/gear-inconsistencies")
def gear_inconsistencies(did: str, body: StepIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                         settings=Depends(get_settings)):
    """Liste des combinaisons navire / espèce / engin incohérentes (pour validation et corrections)."""
    ds, _ = dataset_access(db, user, did)
    recipe = json.loads(ds["recipe"])
    pos = len(recipe) if body.position is None else max(0, min(body.position, len(recipe)))
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds, recipe=recipe[:pos])
        try:
            return halieutique.gear_inconsistencies(ws.con, plan.sql, body.params, plan.schema, limit=5000)
        except RecipeError as e:
            bad(e)


@router.patch("/datasets/{did}/steps/{step_id}")
def patch_step(did: str, step_id: str, body: StepPatch, user: User = Depends(current_user),
               db: Database = Depends(get_db), settings=Depends(get_settings)):
    ds = writable_dataset(db, user, did)
    recipe = json.loads(ds["recipe"])
    idx = next((i for i, s in enumerate(recipe) if s["id"] == step_id), None)
    if idx is None:
        raise HTTPException(404, "Étape introuvable.")
    s = dict(recipe[idx])
    if body.params is not None:
        s["params"] = body.params
        _enrich(db, s)
        s["edited_by"], s["edited_at"] = user.id, now()
    if body.comment is not None:
        s["comment"] = body.comment[:2000]
    if body.enabled is not None:
        s["enabled"] = body.enabled
    if body.params is not None:
        with Workspace(db, settings, user) as ws:
            try:
                ws.check(ds, recipe[:idx], s)
            except RecipeError as e:
                bad(e)
    recipe[idx] = s
    _save_recipe(db, did, recipe)
    db.log("etape_modifiee", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did,
           step=describe_step(s), enabled=s.get("enabled", True))
    return {"ok": True}


@router.delete("/datasets/{did}/steps/{step_id}")
def delete_step(did: str, step_id: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    ds = writable_dataset(db, user, did)
    recipe = json.loads(ds["recipe"])
    s = next((x for x in recipe if x["id"] == step_id), None)
    if not s:
        raise HTTPException(404, "Étape introuvable.")
    _save_recipe(db, did, [x for x in recipe if x["id"] != step_id])
    db.log("etape_supprimee", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did,
           step=describe_step(s), removed=s)
    return {"ok": True}


@router.post("/datasets/{did}/steps/reorder")
def reorder(did: str, body: ReorderIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    ds = writable_dataset(db, user, did)
    recipe = json.loads(ds["recipe"])
    by_id = {s["id"]: s for s in recipe}
    if sorted(body.order) != sorted(by_id):
        raise HTTPException(400, "L'ordre fourni ne correspond pas aux étapes.")
    _save_recipe(db, did, [by_id[i] for i in body.order])
    db.log("etapes_reordonnees", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did)
    return {"ok": True}


# --------------------------------------------------------------------------- partage


@router.post("/datasets/{did}/shares")
def share(did: str, body: ShareIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    ds = writable_dataset(db, user, did)
    require_role(user, ds["structure_id"], "admin")
    if body.structure_id == ds["structure_id"]:
        raise HTTPException(400, "Le jeu appartient déjà à cette structure.")
    if not db.one("SELECT id FROM structures WHERE id = ?", (body.structure_id,)):
        raise HTTPException(404, "Structure introuvable.")
    db.execute("INSERT OR IGNORE INTO dataset_shares(dataset_id, structure_id, shared_by, shared_at) "
               "VALUES (?,?,?,?)", (did, body.structure_id, user.id, now()))
    db.log("partage", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did, to=body.structure_id)
    return {"ok": True}


@router.delete("/datasets/{did}/shares/{sid}")
def unshare(did: str, sid: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    ds = writable_dataset(db, user, did)
    require_role(user, ds["structure_id"], "admin")
    db.execute("DELETE FROM dataset_shares WHERE dataset_id = ? AND structure_id = ?", (did, sid))
    db.log("partage_retire", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did, to=sid)
    return {"ok": True}


@router.get("/structures")
def structures_directory(_: User = Depends(current_user), db: Database = Depends(get_db)):
    """Annuaire minimal (pour choisir avec qui partager)."""
    return db.all("SELECT id, name, short_name FROM structures ORDER BY name")


# --------------------------------------------------------------------------- fiches méthode et exports


def _method_md(db, settings, user, ds, purpose=None) -> tuple[object, object]:
    """Fiche méthode du jeu (objet Fiche) et plan de la recette."""
    raw = raw_of(db, ds)
    structure = db.one("SELECT * FROM structures WHERE id = ?", (ds["structure_id"],))
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        pipeline.step_counts(ws.con, plan)
        prof = None
        if not plan.error:
            try:
                prof = pipeline.profile(ws.con, plan)
            except Exception:  # noqa: BLE001 - la fiche reste utile sans le profil
                prof = None
    fiche = methods.dataset_method(ds, raw, structure, _users_map(db), plan, sensitivity.detect(list(plan.schema)),
                                   user.display_name, purpose, prof)
    return fiche, plan


@router.get("/datasets/{did}/method.md")
def method_md(did: str, user: User = Depends(current_user), db: Database = Depends(get_db),
              settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    fiche, _ = _method_md(db, settings, user, ds)
    return Response(fiche.markdown(), media_type="text/markdown; charset=utf-8")


@router.get("/datasets/{did}/method.html")
def method_html(did: str, user: User = Depends(current_user), db: Database = Depends(get_db),
                settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    fiche, _ = _method_md(db, settings, user, ds)
    return Response(fiche.html(), media_type="text/html; charset=utf-8")


@router.get("/datasets/{did}/method.zip")
def method_zip(did: str, user: User = Depends(current_user), db: Database = Depends(get_db),
               settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    fiche, _ = _method_md(db, settings, user, ds)
    base = f"{_safe_filename(ds['name'])}_methode"
    return Response(fiche.zip(base), media_type="application/zip",
                    headers={"Content-Disposition": f'attachment; filename="{base}.zip"'})


@router.get("/datasets/{did}/method.{fmt}")
def method_export(did: str, fmt: str, user: User = Depends(current_user), db: Database = Depends(get_db),
                  settings=Depends(get_settings)):
    """Fiche méthode du jeu en Word (docx) ou PDF."""
    ds, _ = dataset_access(db, user, did)
    fiche, _ = _method_md(db, settings, user, ds)
    return fiche.response(fmt, f"{_safe_filename(ds['name'])}_methode", org=structure_name(db, user))


def _safe_filename(name: str) -> str:
    keep = "".join(ch if ch.isalnum() or ch in "-_ " else "_" for ch in name).strip().replace(" ", "_")
    return keep[:80] or "donnees"


@router.get("/datasets/{did}/export")
def export(did: str, fmt: str = "csv", confirm_sensitive: bool = False, include_row_id: bool = False,
           user: User = Depends(current_user), db: Database = Depends(get_db), settings=Depends(get_settings)):
    """Export du résultat (jamais du brut modifié) + fiche méthode, dans un ZIP."""
    if fmt not in ("csv", "xlsx", "parquet"):
        raise HTTPException(400, "Format d'export inconnu (csv, xlsx ou parquet).")
    ds, _ = dataset_access(db, user, did)
    fiche, plan = _method_md(db, settings, user, ds)
    if plan.error:
        raise HTTPException(400, f"La recette contient une erreur (étape {plan.error['index']}) : corrigez-la avant "
                                 "d'exporter.")
    recipe = json.loads(ds["recipe"])
    anon = {c for s in recipe if s.get("enabled", True) and s["type"] == "anonymize"
            for c in s["params"].get("columns", [])}
    exposed = [s for s in sensitivity.detect(list(plan.schema)) if s["column"] not in anon]
    if exposed and not confirm_sensitive:
        raise HTTPException(409, detail={"code": "donnees_sensibles", "columns": exposed,
                                         "message": "Cet export contient des colonnes sensibles non anonymisées."})
    cols = [c for c in plan.schema if include_row_id or not c.startswith("__")]
    select = ", ".join(ident(c) for c in cols)
    base = _safe_filename(ds["name"])
    stamp = datetime.now().strftime("%Y%m%d_%H%M")
    tmpdir = Path(tempfile.mkdtemp(dir=settings.home))
    try:
        data_path = tmpdir / f"{base}.{fmt}"
        with Workspace(db, settings, user) as ws:
            con = ws.con
            q = f"SELECT {select} FROM ({plan.sql})"
            if fmt == "csv":
                raw_csv = tmpdir / "brut.csv"
                con.execute(f"COPY ({q}) TO {string_lit(str(raw_csv))} (HEADER, DELIMITER ';')")
                with open(data_path, "wb") as out, open(raw_csv, "rb") as inp:
                    out.write(b"\xef\xbb\xbf")  # BOM : Excel ouvre correctement les accents
                    shutil.copyfileobj(inp, out)
            elif fmt == "parquet":
                con.execute(f"COPY ({q}) TO {string_lit(str(data_path))} (FORMAT parquet)")
            else:
                n = con.execute(f"SELECT count(*) FROM ({q})").fetchone()[0]
                if n > XLSX_MAX_ROWS:
                    raise HTTPException(400, f"{n} lignes : trop pour Excel (1 048 575 max). Exportez en CSV.")
                from openpyxl import Workbook

                wb = Workbook(write_only=True)
                sheet = wb.create_sheet("donnees")
                sheet.append(cols)
                cur = con.execute(q)
                while batch := cur.fetchmany(5000):
                    for r in batch:
                        sheet.append(list(r))
                wb.save(data_path)
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(data_path, data_path.name)
            z.writestr(f"{base}_methode.md", fiche.markdown())
            z.writestr(f"{base}_methode.html", fiche.html())
            for fname, svg in fiche.figures().items():
                z.writestr(f"figures/{fname}.svg", svg)
        db.log("export", user_id=user.id, structure_id=ds["structure_id"], dataset_id=did, fmt=fmt,
               sensitive_confirmed=bool(exposed))
        buf.seek(0)
        return StreamingResponse(buf, media_type="application/zip", headers={
            "Content-Disposition": f'attachment; filename="{base}_{stamp}.zip"'})
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


@router.get("/datasets/{did}/integrity")
def integrity(did: str, user: User = Depends(current_user), db: Database = Depends(get_db),
              settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    raw = raw_of(db, ds)
    ok = store.verify_integrity(settings.raw_dir, raw["sha256"])
    return {"ok": ok, "sha256": raw["sha256"],
            "message": "Le fichier brut est intact." if ok else
            "Le fichier brut a été modifié ou supprimé hors de Moanui."}

