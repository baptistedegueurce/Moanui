"""Cartographie : couches (intégrées et importées), tuiles vectorielles, carroyage, cartes enregistrées."""

from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
import threading
from collections import OrderedDict
from datetime import datetime
from pathlib import Path

import duckdb
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field

from ..db import Database, new_id, now
from ..engine import geo
from ..engine.geo_steps import SPEED_PRESETS
from ..engine.sql import RecipeError, ident, string_lit
from .deps import (
    BUILTIN_PREFIX,
    User,
    Workspace,
    active_structure,
    current_user,
    dataset_access,
    get_db,
    get_settings,
    layer_access,
    layer_source,
    require_role,
)

router = APIRouter(prefix="/api/geo", tags=["cartographie"])
MAX_UPLOAD = 1024 * 1024 * 1024
MAX_CELLS = 150_000
TILE_PROPS = 40

# --------------------------------------------------------------------------- connexions et cache des tuiles

_local = threading.local()


def _con():
    con = getattr(_local, "con", None)
    if con is None:
        con = duckdb.connect()
        geo.load_spatial(con)
        _local.con = con
    return con


class _LRU:
    def __init__(self, size: int):
        self.size, self.data, self.lock = size, OrderedDict(), threading.Lock()

    def get(self, k):
        with self.lock:
            if k in self.data:
                self.data.move_to_end(k)
                return self.data[k]
        return None

    def put(self, k, v):
        with self.lock:
            self.data[k] = v
            self.data.move_to_end(k)
            while len(self.data) > self.size:
                self.data.popitem(last=False)

    def drop(self, prefix: str):
        with self.lock:
            for k in [k for k in self.data if k[0] == prefix]:
                del self.data[k]


_tiles = _LRU(3000)
_points: dict[str, dict] = {}  # clé → {path, dataset_id, columns}


def _mvt(body: bytes) -> Response:
    return Response(body, media_type="application/vnd.mapbox-vector-tile",
                    headers={"Cache-Control": "private, max-age=600"})


def _err(e: Exception):
    raise HTTPException(400, str(e))


# --------------------------------------------------------------------------- état et couches


@router.get("/status")
def status(_: User = Depends(current_user)):
    return geo.spatial_status() | {"vitesses": SPEED_PRESETS}


def _layer_out(row: dict, user: User) -> dict:
    info = json.loads(row["info"])
    return {"id": row["id"], "nom": row["name"], "description": row["description"], "groupe": "Couches importées",
            "source": row["source_name"], "integree": False, "publique": bool(row["public"]),
            "style": json.loads(row["style"] or "{}"), "structure_id": row["structure_id"],
            "modifiable": (user.role_in(row["structure_id"]) or "lecteur") in ("analyste", "admin"),
            "created_at": row["created_at"], **{k: info.get(k) for k in
                                                ("kind", "n_features", "bbox", "columns", "geometry_types",
                                                 "crs_source", "warnings")}}


@router.get("/layers")
def list_layers(user: User = Depends(current_user), db: Database = Depends(get_db)):
    sid = active_structure(user)
    builtin = [{"id": BUILTIN_PREFIX + k, "integree": True, "modifiable": False, **{
        x: v.get(x) for x in ("nom", "description", "groupe", "source", "licence", "url", "date", "style", "kind",
                              "n_features", "bbox", "columns")}} for k, v in geo.builtin_layers().items()]
    rows = db.all("SELECT * FROM layers WHERE structure_id = ? OR public = 1 ORDER BY created_at DESC", (sid,))
    return {"couches": builtin + [_layer_out(r, user) for r in rows], "notes": geo.builtin_notes()}


@router.post("/layers/inspect")
async def inspect_layer(files: list[UploadFile] = File(...), _: User = Depends(current_user),
                        settings=Depends(get_settings)):
    tmp = Path(tempfile.mkdtemp(dir=settings.home))
    try:
        mains = geo.prepare_sources([(f.filename or "fichier", await f.read()) for f in files], tmp)
        return {"layers": geo.inspect_sources(_con(), mains)}
    except RecipeError as e:
        _err(e)
    finally:
        _rmtree(tmp)


def _rmtree(p: Path):
    for f in p.rglob("*"):
        try:
            f.chmod(0o644)
        except OSError:
            pass
    shutil.rmtree(p, ignore_errors=True)


@router.post("/layers")
async def import_layer(files: list[UploadFile] = File(...), name: str = Form(""), description: str = Form(""),
                       file: str = Form(""), layer: str = Form(""), crs: str = Form(""),
                       user: User = Depends(current_user), db: Database = Depends(get_db),
                       settings=Depends(get_settings)):
    sid = active_structure(user)
    require_role(user, sid, "analyste")
    lid = new_id()
    folder = settings.layers_dir / lid
    payload, total = [], 0
    for f in files:
        data = await f.read()
        total += len(data)
        if total > MAX_UPLOAD:
            raise HTTPException(413, "Fichiers trop volumineux (1 Go maximum).")
        payload.append((f.filename or "fichier", data))
    try:
        mains = geo.prepare_sources(payload, folder / "source")
        main = next((m for m in mains if m.name == file), mains[0]) if file else mains[0]
        info = geo.import_layer(_con(), main, layer or None, folder / "couche.parquet", crs or None)
    except RecipeError as e:
        _rmtree(folder)
        _err(e)
    except Exception as e:  # noqa: BLE001
        _rmtree(folder)
        raise HTTPException(400, f"Import impossible : {e}") from e
    sha = hashlib.sha256(b"".join(d for _, d in sorted(payload))).hexdigest()
    info["sha256"] = sha
    info["fichiers"] = sorted(p.name for p in (folder / "source").iterdir())
    nm = (name or (layer or main.stem))[:200]
    db.execute("INSERT INTO layers(id, structure_id, name, description, source_name, info, style, public, created_by, "
               "created_at) VALUES (?,?,?,?,?,?,?,0,?,?)",
               (lid, sid, nm, description[:5000], main.name + (f" / {layer}" if layer else ""),
                json.dumps(info, default=str), json.dumps(_default_style(info["kind"])), user.id, now()))
    db.log("import_couche", user_id=user.id, structure_id=sid, layer=lid, file=main.name, n=info["n_features"])
    return _layer_out(db.one("SELECT * FROM layers WHERE id = ?", (lid,)), user)


def _default_style(kind: str) -> dict:
    return {"couleur": "#2a78d6", "epaisseur": 1.5 if kind != "point" else 1, "remplissage": 0.3 if kind == "polygone"
            else 1, "rayon": 4}


class LayerPatch(BaseModel):
    name: str | None = Field(None, max_length=200)
    description: str | None = Field(None, max_length=5000)
    style: dict | None = None
    public: bool | None = None


@router.patch("/layers/{lid}")
def patch_layer(lid: str, body: LayerPatch, user: User = Depends(current_user), db: Database = Depends(get_db)):
    row = layer_access(db, user, lid, write=True)
    if body.public is not None and not user.is_superadmin:
        raise HTTPException(403, "Seul l'administrateur général peut publier une couche pour toutes les structures.")
    for col, val in (("name", body.name), ("description", body.description),
                     ("style", json.dumps(body.style) if body.style is not None else None),
                     ("public", int(body.public) if body.public is not None else None)):
        if val is not None:
            db.execute(f"UPDATE layers SET {col} = ? WHERE id = ?", (val, lid))
    db.log("modif_couche", user_id=user.id, structure_id=row["structure_id"], layer=lid)
    return _layer_out(db.one("SELECT * FROM layers WHERE id = ?", (lid,)), user)


@router.delete("/layers/{lid}")
def delete_layer(lid: str, user: User = Depends(current_user), db: Database = Depends(get_db),
                 settings=Depends(get_settings)):
    row = layer_access(db, user, lid, write=True)
    db.execute("DELETE FROM layers WHERE id = ?", (lid,))
    _rmtree(settings.layers_dir / lid)
    _tiles.drop(lid)
    db.log("suppression_couche", user_id=user.id, structure_id=row["structure_id"], layer=lid, name=row["name"])
    return {"ok": True}


def _source(db, settings, user, lid: str) -> tuple[str, list[str], str]:
    try:
        path, cols, name = layer_source(db, settings, user, lid)
    except RecipeError as e:
        raise HTTPException(404, str(e)) from e
    return f"SELECT * FROM read_parquet({string_lit(str(path))})", cols, name


@router.get("/layers/{lid}/tiles/{z}/{x}/{y}.pbf")
def layer_tile(lid: str, z: int, x: int, y: int, user: User = Depends(current_user), db: Database = Depends(get_db),
               settings=Depends(get_settings)):
    if not (0 <= z <= 22 and 0 <= x < 2 ** z and 0 <= y < 2 ** z):
        raise HTTPException(400, "Tuile invalide.")
    table, cols, _ = _source(db, settings, user, lid)
    key = (lid, z, x, y)
    hit = _tiles.get(key)
    if hit is None:
        hit = geo.render_tile(_con(), table, z, x, y, cols[:TILE_PROPS])
        _tiles.put(key, hit)
    return _mvt(hit)


@router.get("/layers/{lid}/values/{column}")
def layer_values(lid: str, column: str, user: User = Depends(current_user), db: Database = Depends(get_db),
                 settings=Depends(get_settings)):
    """Valeurs (catégories) ou classes (quantiles) d'un attribut, pour la légende."""
    table, cols, _ = _source(db, settings, user, lid)
    if column not in cols:
        raise HTTPException(400, "Attribut inconnu.")
    return _value_summary(_con(), table, column)


def _value_summary(con, table: str, column: str) -> dict:
    c = ident(column)
    t = con.execute(f"SELECT typeof({c}) FROM ({table}) WHERE {c} IS NOT NULL LIMIT 1").fetchone()
    numeric = bool(t) and t[0].upper() in ("TINYINT", "SMALLINT", "INTEGER", "BIGINT", "HUGEINT", "FLOAT", "DOUBLE",
                                          "UTINYINT", "USMALLINT", "UINTEGER", "UBIGINT") or (t and t[0].startswith("DECIMAL"))
    if numeric:
        r = con.execute(f"SELECT min({c})::DOUBLE, max({c})::DOUBLE, "
                        f"quantile_cont({c}::DOUBLE, [0.2, 0.4, 0.6, 0.8]) FROM ({table})").fetchone()
        return {"numeric": True, "min": r[0], "max": r[1], "quantiles": r[2]}
    rows = con.execute(f"SELECT CAST({c} AS VARCHAR) v, count(*) n FROM ({table}) WHERE {c} IS NOT NULL "
                       f"GROUP BY v ORDER BY n DESC LIMIT 200").fetchall()
    return {"numeric": False, "values": [{"value": v, "n": n} for v, n in rows]}


@router.get("/layers/{lid}/export")
def export_layer(lid: str, fmt: str = "gpkg", user: User = Depends(current_user), db: Database = Depends(get_db),
                 settings=Depends(get_settings)):
    table, cols, name = _source(db, settings, user, lid)
    return _export(table, cols, name, fmt, settings, user, db, {"layer": lid})


def _safe(name: str) -> str:
    keep = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in name).strip("_")
    return keep[:60] or "couche"


def _export(table: str, cols: list[str], name: str, fmt: str, settings, user, db, log: dict):
    tmp = Path(tempfile.mkdtemp(dir=settings.home))
    try:
        out = geo.export_layer(_con(), table, cols, fmt, tmp, _safe(name))
    except RecipeError as e:
        _rmtree(tmp)
        _err(e)
    final = settings.exports_dir / f"{datetime.now():%Y%m%d_%H%M%S}_{out.name}"
    shutil.move(str(out), final)
    _rmtree(tmp)
    db.log("export_carto", user_id=user.id, fmt=fmt, **log)
    return FileResponse(final, filename=out.name, media_type="application/octet-stream")


# --------------------------------------------------------------------------- jeux de données sur la carte


class PointsIn(BaseModel):
    lon: str
    lat: str


@router.post("/datasets/{did}/points")
def dataset_points(did: str, body: PointsIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                   settings=Depends(get_settings)):
    """Prépare l'affichage des positions d'un jeu (VMS…) en tuiles vectorielles."""
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        if plan.error:
            raise HTTPException(400, f"La recette contient une erreur (étape {plan.error['index']}).")
        for c in (body.lon, body.lat):
            if c not in plan.schema:
                raise HTTPException(400, f"Colonne « {c} » inconnue.")
        geo.load_spatial(ws.con)
        try:
            path = geo.materialize_points(ws.con, plan.sql, body.lon, body.lat, settings.cache_dir)
        except Exception as e:  # noqa: BLE001
            raise HTTPException(400, f"Positions illisibles : {e}") from e
    key = path.stem
    con = _con()
    n, x0, y0, x1, y1 = con.execute(f"SELECT count(*), min(__minx), min(__miny), max(__maxx), max(__maxy) "
                                    f"FROM read_parquet({string_lit(str(path))})").fetchone()
    cols = [c for c in plan.schema if not c.startswith("__")][:TILE_PROPS]
    _points[key] = {"path": path, "dataset_id": did, "columns": cols}
    with Workspace(db, settings, user) as ws:
        total = ws.con.execute(f"SELECT count(*) FROM ({ws.plan(ds).sql})").fetchone()[0]
    return {"key": key, "n": n, "bbox": [x0, y0, x1, y1] if x0 is not None else None, "columns": cols,
            "ignored": total - n}


@router.get("/points/{key}/tiles/{z}/{x}/{y}.pbf")
def points_tile(key: str, z: int, x: int, y: int, user: User = Depends(current_user), db: Database = Depends(get_db)):
    meta = _points.get(key)
    if not meta or not meta["path"].exists():
        raise HTTPException(404, "Couche de positions expirée : rouvrez la carte.")
    dataset_access(db, user, meta["dataset_id"])
    k = (key, z, x, y)
    hit = _tiles.get(k)
    if hit is None:
        hit = geo.render_tile(_con(), f"SELECT * FROM read_parquet({string_lit(str(meta['path']))})", z, x, y,
                              meta["columns"])
        _tiles.put(k, hit)
    return _mvt(hit)


@router.get("/points/{key}/values/{column}")
def points_values(key: str, column: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    meta = _points.get(key)
    if not meta:
        raise HTTPException(404, "Couche de positions expirée : rouvrez la carte.")
    dataset_access(db, user, meta["dataset_id"])
    if column not in meta["columns"]:
        raise HTTPException(400, "Colonne inconnue.")
    return _value_summary(_con(), f"SELECT * FROM read_parquet({string_lit(str(meta['path']))})", column)


class AggIn(BaseModel):
    mode: str = "grille"  # grille | ciem
    lon: str | None = None
    lat: str | None = None
    cell: float = 0.05
    rect_column: str | None = None
    value: str | None = None
    agg: str = "nombre"
    vessel: str | None = None
    secret: int = 0
    filters: list[dict] = []


def _agg_sql(con, plan, body: AggIn) -> str:
    from ..engine.pipeline import _view_filters
    base = plan.sql
    if body.filters:
        where = _view_filters(plan.schema, body.filters, None)
        if where:
            base = f"SELECT * FROM ({plan.sql}) WHERE {where}"
    for c in (body.lon, body.lat, body.rect_column, body.value, body.vessel):
        if c and c not in plan.schema:
            raise RecipeError(f"Colonne « {c} » inconnue.")
    if body.secret and not body.vessel:
        raise RecipeError("Le secret statistique nécessite la colonne navire.")
    if body.mode == "ciem":
        if not body.rect_column:
            raise RecipeError("Choisissez la colonne des rectangles CIEM.")
        return geo.rect_sql(base, body.rect_column, body.value, body.agg, body.vessel, body.secret)
    if not (body.lon and body.lat):
        raise RecipeError("Choisissez les colonnes longitude et latitude.")
    return geo.grid_sql(base, body.lon, body.lat, body.cell, body.value, body.agg, body.vessel, body.secret)


@router.post("/datasets/{did}/aggregate")
def dataset_aggregate(did: str, body: AggIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                      settings=Depends(get_settings)):
    """Carroyage ou rectangles CIEM : GeoJSON des mailles + résumé pour la légende."""
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        if plan.error:
            raise HTTPException(400, f"La recette contient une erreur (étape {plan.error['index']}).")
        geo.load_spatial(ws.con)
        try:
            sql = _agg_sql(ws.con, plan, body)
            n = ws.con.execute(f"SELECT count(*) FROM ({sql})").fetchone()[0]
            if n > MAX_CELLS:
                raise RecipeError(f"{n:,} mailles : trop pour l'affichage. Agrandissez la maille ou filtrez."
                                  .replace(",", " "))
            props = ["maille" if body.mode != "ciem" else "rectangle", "valeur",
                     "n_points" if body.mode != "ciem" else "n_lignes", "n_navires", "secret"]
            fc = geo.features_geojson(ws.con, sql, props, limit=MAX_CELLS)
            r = ws.con.execute(f"SELECT min(valeur)::DOUBLE, max(valeur)::DOUBLE, sum(valeur)::DOUBLE, "
                               f"quantile_cont(valeur::DOUBLE, [0.2, 0.4, 0.6, 0.8]), count(*) FILTER (secret), "
                               f"min(ST_XMin(geom)), min(ST_YMin(geom)), max(ST_XMax(geom)), max(ST_YMax(geom)) "
                               f"FROM ({sql})").fetchone()
        except RecipeError as e:
            _err(e)
        except duckdb.Error as e:
            raise HTTPException(400, f"Calcul impossible : {e}") from e
    return {"geojson": fc, "n": n, "min": r[0], "max": r[1], "total": r[2], "quantiles": r[3], "masquees": r[4],
            "bbox": [r[5], r[6], r[7], r[8]] if r[5] is not None else None}


@router.post("/datasets/{did}/aggregate/export")
def dataset_aggregate_export(did: str, body: AggIn, fmt: str = "gpkg", user: User = Depends(current_user),
                             db: Database = Depends(get_db), settings=Depends(get_settings)):
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        geo.load_spatial(ws.con)
        try:
            sql = _agg_sql(ws.con, plan, body)
        except RecipeError as e:
            _err(e)
        cols = [r[0] for r in ws.con.execute(f"DESCRIBE {sql}").fetchall() if r[0] != "geom"]
        tmp_parquet = settings.cache_dir / f"agg_{new_id()}.parquet"
        ws.con.execute(f"COPY ({sql}) TO {string_lit(str(tmp_parquet))} (FORMAT parquet)")
    try:
        return _export(f"SELECT * FROM read_parquet({string_lit(str(tmp_parquet))})", cols,
                       f"{ds['name']}_{'rectangles' if body.mode == 'ciem' else 'carroyage'}", fmt, settings, user, db,
                       {"dataset_id": did})
    finally:
        tmp_parquet.unlink(missing_ok=True)


# --------------------------------------------------------------------------- cartes enregistrées


class MapIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    spec: dict


def _map_out(row: dict) -> dict:
    return {"id": row["id"], "name": row["name"], "spec": json.loads(row["spec"]), "created_by": row["created_by"],
            "created_at": row["created_at"], "updated_at": row["updated_at"]}


@router.get("/maps")
def list_maps(user: User = Depends(current_user), db: Database = Depends(get_db)):
    sid = active_structure(user)
    return [_map_out(r) for r in db.all("SELECT * FROM maps WHERE structure_id = ? ORDER BY updated_at DESC", (sid,))]


@router.post("/maps")
def create_map(body: MapIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    sid = active_structure(user)
    require_role(user, sid, "analyste")
    mid = new_id()
    db.execute("INSERT INTO maps(id, structure_id, name, spec, created_by, created_at, updated_at) VALUES (?,?,?,?,?,?,?)",
               (mid, sid, body.name, json.dumps(body.spec), user.id, now(), now()))
    db.log("carte", user_id=user.id, structure_id=sid, map=mid)
    return _map_out(db.one("SELECT * FROM maps WHERE id = ?", (mid,)))


def _writable_map(db, user, mid) -> dict:
    row = db.one("SELECT * FROM maps WHERE id = ?", (mid,))
    if not row or user.role_in(row["structure_id"]) is None:
        raise HTTPException(404, "Carte introuvable.")
    require_role(user, row["structure_id"], "analyste")
    return row


@router.put("/maps/{mid}")
def update_map(mid: str, body: MapIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    _writable_map(db, user, mid)
    db.execute("UPDATE maps SET name = ?, spec = ?, updated_at = ? WHERE id = ?",
               (body.name, json.dumps(body.spec), now(), mid))
    return _map_out(db.one("SELECT * FROM maps WHERE id = ?", (mid,)))


@router.delete("/maps/{mid}")
def delete_map(mid: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    _writable_map(db, user, mid)
    db.execute("DELETE FROM maps WHERE id = ?", (mid,))
    return {"ok": True}


# --------------------------------------------------------------------------- fiche méthode d'une carte

class MapMethodIn(BaseModel):
    name: str = Field("carte", max_length=200)
    spec: dict
    png: str | None = Field(default=None, max_length=30_000_000)  # rendu de la carte (data:image/png;base64,…)


AGG_FR = {"nombre": "nombre de positions", "somme": "somme", "moyenne": "moyenne", "max": "maximum",
          "navires": "nombre de navires distincts"}


def _map_fiche(db: Database, user: User, body: MapMethodIn):
    from ..fiche import Fiche

    s = body.spec
    t = s.get("template") or {}
    f = Fiche(f"Fiche méthode de la carte : {t.get('title') or body.name}", t.get("subtitle") or "")
    f.meta = [(k, v) for k, v in [("Auteur", t.get("author") or user.display_name), ("Source affichée", t.get("source") or ""),
                                  ("Date", datetime.now().strftime("%d/%m/%Y"))] if v]
    if body.png and body.png.startswith("data:image/png;base64,"):
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 '
               f'{int(t.get("width") or 1600)} {int(t.get("height") or 1000)}"><image width="100%" height="100%" '
               f'href="{body.png}"/></svg>')
        f.fig("carte", svg, t.get("title") or body.name)
    layers = [x for x in s.get("layers") or [] if x.get("visible", True)]
    f.h("Couches représentées")
    rows, refs, has_secret, has_vms = [], [], False, False
    builtin = geo.builtin_layers()
    for lay in layers:
        kind = lay.get("kind")
        if kind == "couche":
            lid = lay.get("layerId") or ""
            if lid.startswith(BUILTIN_PREFIX):
                meta = builtin.get(lid[len(BUILTIN_PREFIX):], {})
                src = f"{meta.get('source', '')}" + (f" ({meta['licence']})" if meta.get("licence") not in (None, "", "—", "–") else "")
                refs += {"ciem_rectangles": ["ices_rect"], "terres": ["naturalearth"]}.get(meta.get("id", ""), [])
                if "Shom" in src:
                    refs.append("shom_delmar")
                if "OFB" in src:
                    refs.append("ofb_amp")
                what = "couche de contexte intégrée"
            else:
                row = db.one("SELECT name, description, source_name FROM layers WHERE id = ?", (lid,))
                src = (row["description"] or row["source_name"]) if row else "couche importée"
                what = "couche importée (reprojetée en WGS84)"
            rows.append([lay.get("title", ""), what, src])
        elif kind == "points":
            ds = db.one("SELECT name FROM datasets WHERE id = ?", (lay.get("datasetId"),))
            has_vms = True
            rows.append([lay.get("title", ""), "positions", f"jeu « {ds['name'] if ds else '?'} », colonnes "
                                                            f"« {lay.get('lon')} » / « {lay.get('lat')} » (degrés WGS84)"])
        elif kind == "agregat":
            a = lay.get("agg") or {}
            ds = db.one("SELECT name FROM datasets WHERE id = ?", (lay.get("datasetId"),))
            how = (f"carroyage de {a.get('cell')}° " if a.get("mode") == "grille" else "rectangles statistiques CIEM ")
            val = AGG_FR.get(a.get("agg"), a.get("agg"))
            if a.get("value") and a.get("agg") not in ("nombre", "navires"):
                val += f" de « {a['value']} »"
            sec = ""
            if a.get("vessel") and int(a.get("secret") or 0) > 1:
                has_secret = True
                sec = f" ; mailles de moins de {a['secret']} navires masquées (secret statistique)"
            if a.get("mode") == "ciem":
                refs.append("ices_rect")
            rows.append([lay.get("title", ""), how.strip(), f"jeu « {ds['name'] if ds else '?'} » : {val} par maille{sec}"])
    f.table(["Couche", "Nature", "Source et calcul"], rows, "Couches visibles, de haut en bas.")
    f.h("Projection et fond de carte")
    base = {"ign": "Plan IGN (Géoplateforme, IGN)", "osm": "OpenStreetMap (contributeurs OpenStreetMap, ODbL)",
            "horsligne": "terres émergées Natural Earth (domaine public), fond hors ligne", "aucun": "aucun"}.get(
        s.get("basemap"), s.get("basemap"))
    if s.get("basemap") == "horsligne":
        refs.append("naturalearth")
    f.p(f"Données stockées en coordonnées géographiques WGS84 (EPSG:4326), affichées en projection Web Mercator "
        f"(EPSG:3857). Les surfaces sont exagérées vers les hautes latitudes : à l'échelle de la Manche et du golfe de "
        f"Gascogne, l'écart reste modéré mais les mailles en degrés n'ont pas toutes la même surface. Fond : {base}.")
    f.h("Méthodes")
    paras = []
    if any(x.get("kind") == "agregat" for x in layers):
        paras.append("Les valeurs agrégées par maille sont représentées par une couleur ; les classes et la palette "
                     "séquentielle choisies conditionnent fortement la lecture : une même donnée peut paraître homogène "
                     f"ou contrastée selon les bornes des classes {f.cite('brewer2003', 'monmonier2018')}.")
    if has_vms:
        paras.append("Les positions VMS sont des points échantillonnés (en général toutes les heures ou plus) : leur densité "
                     "dépend de la fréquence d'émission et de la vitesse ; l'effort de pêche se représente plutôt par le "
                     f"nombre de positions en pêche par maille, après identification de l'activité {f.cite('lee2010', 'hintzen2012')}.")
    if has_secret:
        paras.append("Les mailles comptant trop peu de navires sont masquées pour respecter le secret statistique "
                     f"{f.cite('loi1951', 'reg223')}.")
    f.ul(paras or ["Représentation de couches de référence, sans calcul."])
    if refs:
        f.cite(*refs)
    return f


@router.post("/maps/method.zip")
def map_method_zip(body: MapMethodIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    return Response(_map_fiche(db, user, body).zip("carte_methode"), media_type="application/zip",
                    headers={"Content-Disposition": 'attachment; filename="carte_methode.zip"'})


@router.post("/maps/method.md")
def map_method_md(body: MapMethodIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    return Response(_map_fiche(db, user, body).markdown(), media_type="text/markdown; charset=utf-8")


@router.post("/maps/method.{fmt}")
def map_method_export(fmt: str, body: MapMethodIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    """Fiche méthode de la carte en Word (docx) ou PDF."""
    return _map_fiche(db, user, body).response(fmt, "carte_methode")
