"""Cartographie : couches vectorielles, tuiles MVT, carroyage, rectangles CIEM, VMS.

Principes :
- chaque couche importée (SHP, GeoJSON, GeoPackage, KML…) garde sa copie brute en lecture seule et
  est convertie en Parquet (WGS84) avec une géométrie pré-projetée en Web Mercator et sa boîte
  englobante : les tuiles vectorielles sont produites à la demande, seules les entités visibles sont lues ;
- tout passe par l'extension spatiale de DuckDB (GDAL, PROJ, GEOS), embarquée dans l'exécutable.
"""

from __future__ import annotations

import contextvars
import hashlib
import json
import math
import os
import shutil
import stat
import sys
import threading
import zipfile
from pathlib import Path

from .sql import RecipeError, ident, string_lit

GEO_SUFFIXES = {".shp", ".geojson", ".json", ".gpkg", ".kml", ".gml", ".fgb", ".tab", ".mif"}
SIDE_SUFFIXES = {".dbf", ".shx", ".prj", ".cpg", ".qix", ".sbn", ".sbx", ".qmd", ".xml", ".id", ".map", ".dat"}
MAX_FEATURES = 2_000_000
EXT_DIR_NAME = "duckdb_ext"

_lock = threading.Lock()
_ext_path: str | None = None


def _bundled_extension() -> Path | None:
    roots = [Path(getattr(sys, "_MEIPASS", "")) if getattr(sys, "_MEIPASS", None) else None,
             Path(__file__).resolve().parent.parent]
    for root in roots:
        if root:
            p = root / EXT_DIR_NAME / "spatial.duckdb_extension"
            if p.is_file():
                return p
    env = os.environ.get("MOANUI_SPATIAL")
    return Path(env) if env and Path(env).is_file() else None


def load_spatial(con) -> None:
    """Charge l'extension spatiale (embarquée, déjà installée, sinon téléchargée une fois)."""
    global _ext_path
    errors = []
    candidates = []
    if _ext_path:
        candidates.append(_ext_path)
    b = _bundled_extension()
    if b:
        candidates.append(str(b))
    candidates.append("spatial")
    for c in candidates:
        try:
            con.execute(f"LOAD {string_lit(c) if c != 'spatial' else 'spatial'}")
            _ext_path = c
            break
        except Exception as e:  # noqa: BLE001
            errors.append(str(e))
    else:
        with _lock:
            try:
                con.execute("INSTALL spatial")
                con.execute("LOAD spatial")
                _ext_path = "spatial"
            except Exception as e:  # noqa: BLE001
                raise RecipeError("Le module cartographique (extension spatiale DuckDB) est introuvable et n'a pas pu "
                                  "être téléchargé. Vérifiez la connexion internet ou réinstallez Moanui.") from e
    con.execute("SET geometry_always_xy = true")


def spatial_status() -> dict:
    import duckdb
    con = duckdb.connect()
    try:
        load_spatial(con)
        return {"ok": True, "source": "embarquee" if _ext_path and _ext_path != "spatial" else "installee"}
    except RecipeError as e:
        return {"ok": False, "message": str(e)}
    finally:
        con.close()


# --------------------------------------------------------------------------- import de couches


def _safe_extract(zf: zipfile.ZipFile, dest: Path) -> None:
    for info in zf.infolist():
        if info.is_dir():
            continue
        name = Path(info.filename).name  # aplatit l'arborescence, neutralise « ../ »
        if not name or name.startswith("."):
            continue
        if Path(name).suffix.lower() not in GEO_SUFFIXES | SIDE_SUFFIXES:
            continue
        if info.file_size > 2_000_000_000:
            raise RecipeError("Fichier trop volumineux dans l'archive.")
        with zf.open(info) as src, open(dest / name, "wb") as out:
            shutil.copyfileobj(src, out)


def prepare_sources(files: list[tuple[str, bytes | Path]], dest: Path) -> list[Path]:
    """Copie les fichiers envoyés (ou le contenu d'un zip) dans dest ; renvoie les fichiers géographiques."""
    dest.mkdir(parents=True, exist_ok=True)
    for name, content in files:
        base = Path(name).name
        suffix = Path(base).suffix.lower()
        data = content.read_bytes() if isinstance(content, Path) else content
        if suffix == ".zip":
            import io
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                _safe_extract(zf, dest)
        elif suffix in GEO_SUFFIXES | SIDE_SUFFIXES:
            (dest / base).write_bytes(data)
        else:
            raise RecipeError(f"Format non pris en charge : « {base} » (attendu : SHP + DBF + SHX + PRJ, zip, "
                              "GeoJSON, GeoPackage, KML).")
    mains = sorted(p for p in dest.iterdir() if p.suffix.lower() in GEO_SUFFIXES and not
                   (p.suffix.lower() == ".xml"))
    shp = [p for p in mains if p.suffix.lower() == ".shp"]
    for s in shp:
        missing = [ext for ext in (".dbf", ".shx") if not any(
            q.stem == s.stem and q.suffix.lower() == ext for q in dest.iterdir())]
        if missing:
            raise RecipeError(f"Shapefile « {s.name} » incomplet : il manque {', '.join(missing)} "
                              "(envoyez tous les fichiers du même nom, ou un zip).")
    if not mains:
        raise RecipeError("Aucun fichier géographique trouvé (SHP, GeoJSON, GeoPackage, KML…).")
    for p in dest.iterdir():
        p.chmod(stat.S_IREAD | stat.S_IRGRP | stat.S_IROTH)
    return mains


def inspect_sources(con, mains: list[Path]) -> list[dict]:
    """Liste les couches disponibles (un GeoPackage peut en contenir plusieurs)."""
    out = []
    for m in mains:
        try:
            meta = con.execute(f"SELECT layers FROM ST_Read_Meta({string_lit(str(m))})").fetchone()[0]
        except Exception as e:  # noqa: BLE001
            raise RecipeError(f"Lecture impossible de « {m.name} » : {e}") from e
        for lay in meta:
            gf = (lay.get("geometry_fields") or [{}])
            crs = (gf[0] or {}).get("crs") if gf else None
            out.append({"file": m.name, "layer": lay["name"], "n": lay.get("feature_count"),
                        "geometry": (gf[0] or {}).get("type") if gf else None,
                        "crs": f"{crs['auth_name']}:{crs['auth_code']}" if crs and crs.get("auth_code") else None,
                        "fields": [f["name"] for f in lay.get("fields", [])]})
    return out


def _bbox_world(con, src_sql: str) -> tuple[float, float, float, float] | None:
    r = con.execute(f"SELECT min(ST_XMin(geom)), min(ST_YMin(geom)), max(ST_XMax(geom)), max(ST_YMax(geom)) "
                    f"FROM ({src_sql})").fetchone()
    return None if r[0] is None else tuple(float(x) for x in r)


def import_layer(con, source: Path, layer: str | None, out: Path, crs: str | None = None) -> dict:
    """Convertit une couche en Parquet WGS84 (+ géométrie Web Mercator et boîte englobante)."""
    args = [string_lit(str(source))]
    if layer:
        args.append(f"layer := {string_lit(layer)}")
    src = f"SELECT * FROM ST_Read({', '.join(args)})"
    cols = con.execute(f"DESCRIBE {src}").fetchall()
    geom_cols = [c[0] for c in cols if str(c[1]).upper().startswith("GEOMETRY")]
    if not geom_cols:
        raise RecipeError("La couche ne contient pas de géométrie.")
    g = geom_cols[0]
    declared = str(next(c[1] for c in cols if c[0] == g))
    found_crs = declared.split("'")[1] if "'" in declared else None
    warnings = []
    source_crs = (crs or found_crs or "").strip() or None
    n = con.execute(f"SELECT count(*) FROM ({src})").fetchone()[0]
    if n > MAX_FEATURES:
        raise RecipeError(f"Couche trop volumineuse ({n:,} entités, maximum {MAX_FEATURES:,}).".replace(",", " "))
    raw = f"SELECT * EXCLUDE ({ident(g)}), {ident(g)}::GEOMETRY AS geom FROM ({src}) WHERE {ident(g)} IS NOT NULL"
    bbox = _bbox_world(con, raw)
    if not source_crs:
        if bbox and -180.5 <= bbox[0] and bbox[2] <= 180.5 and -90.5 <= bbox[1] and bbox[3] <= 90.5:
            source_crs = "EPSG:4326"
            warnings.append("Projection absente (pas de fichier .prj) : coordonnées supposées en degrés WGS84.")
        else:
            raise RecipeError("Projection inconnue (fichier .prj absent) et coordonnées non géographiques : "
                              "indiquez le code EPSG (ex. EPSG:2154 pour le Lambert-93).")
    if source_crs.upper() in ("EPSG:4326", "OGC:CRS84", "WGS84"):
        wgs = "geom"
    else:
        wgs = f"ST_Transform(geom, {string_lit(source_crs)}, 'EPSG:4326')"
    keep = [c[0] for c in cols if c[0] != g and c[0] not in ("OGC_FID",)]
    props = ", ".join(f"{ident(c)}" for c in keep)
    invalid = 0
    step1 = (f"SELECT {props + ', ' if props else ''}{wgs} AS geom FROM ({raw})")
    con.execute(f"CREATE OR REPLACE TEMP TABLE _couche AS {step1}")
    invalid = con.execute("SELECT count(*) FROM _couche WHERE NOT ST_IsValid(geom)").fetchone()[0]
    if invalid:
        con.execute("UPDATE _couche SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom)")
        warnings.append(f"{invalid} géométrie(s) invalide(s) réparée(s) automatiquement.")
    out.parent.mkdir(parents=True, exist_ok=True)
    clip = "ST_Intersection(geom, ST_MakeEnvelope(-180, -85, 180, 85))"
    con.execute(f"""COPY (
        SELECT row_number() OVER () AS __fid, * EXCLUDE (geom), geom,
               ST_Transform(CASE WHEN ST_YMax(geom) > 85 OR ST_YMin(geom) < -85 THEN {clip} ELSE geom END,
                            'EPSG:4326', 'EPSG:3857') AS geom_m,
               ST_XMin(geom) AS __minx, ST_YMin(geom) AS __miny, ST_XMax(geom) AS __maxx, ST_YMax(geom) AS __maxy
        FROM _couche ORDER BY ST_Hilbert(geom, ST_Extent(ST_MakeEnvelope(-180, -90, 180, 90)))
    ) TO {string_lit(str(out))} (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 4096)""")
    con.execute("DROP TABLE _couche")
    out.chmod(stat.S_IREAD | stat.S_IRGRP | stat.S_IROTH)
    return layer_info(con, out) | {"crs_source": source_crs, "warnings": warnings}


def layer_info(con, path: Path) -> dict:
    p = string_lit(str(path))
    n, x0, y0, x1, y1 = con.execute(
        f"SELECT count(*), min(__minx), min(__miny), max(__maxx), max(__maxy) FROM read_parquet({p})").fetchone()
    types = [r[0] for r in con.execute(
        f"SELECT ST_GeometryType(geom)::VARCHAR t FROM read_parquet({p}) GROUP BY t ORDER BY count(*) DESC").fetchall()]
    cols = [{"name": r[0], "type": str(r[1])} for r in con.execute(f"DESCRIBE SELECT * FROM read_parquet({p})").fetchall()
            if r[0] not in ("geom", "geom_m") and not r[0].startswith("__")]
    return {"n_features": n, "bbox": [x0, y0, x1, y1] if x0 is not None else None,
            "geometry_types": types, "columns": cols, "kind": geometry_kind(types)}


def geometry_kind(types: list[str]) -> str:
    t = " ".join(types).upper()
    if "POLYGON" in t:
        return "polygone"
    if "LINE" in t:
        return "ligne"
    return "point"


# --------------------------------------------------------------------------- tuiles vectorielles


def tile_bounds_wgs84(z: int, x: int, y: int) -> tuple[float, float, float, float]:
    n = 2 ** z

    def lat(yy):
        return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * yy / n))))

    return x / n * 360 - 180, lat(y + 1), (x + 1) / n * 360 - 180, lat(y)


_MVT_INT = ("TINYINT", "SMALLINT", "INTEGER", "BIGINT", "UTINYINT", "USMALLINT", "UINTEGER")
_TYPES_CACHE: dict[str, dict[str, str]] = {}


def _mvt_prop(col: str, typ: str) -> str:
    """ST_AsMVT n'accepte que VARCHAR, FLOAT, DOUBLE, INTEGER, BIGINT, BOOLEAN."""
    t = typ.upper()
    if t in _MVT_INT:
        return f"{ident(col)}::BIGINT"
    if t in ("FLOAT", "DOUBLE"):
        return ident(col)
    if t.startswith(("DECIMAL", "HUGEINT", "UBIGINT")):
        return f"{ident(col)}::DOUBLE"
    if t == "BOOLEAN":
        return ident(col)
    return f"CAST({ident(col)} AS VARCHAR)"


def tile_sql(table_sql: str, z: int, x: int, y: int, props: list[str] | dict[str, str], layer_name: str = "couche",
             where: str | None = None) -> str:
    """Requête produisant la tuile MVT (z/x/y) d'une source ayant geom_m et __minx…__maxy."""
    w, s, e, n = tile_bounds_wgs84(z, x, y)
    pad = (e - w) * 0.02
    res = 40075016.68 / (256 * 2 ** z)  # mètres par pixel
    tol = res * 0.5 if z < 14 else 0
    geom = f"ST_Simplify(geom_m, {tol})" if tol else "geom_m"
    fields = ", ".join([f"'geom': ST_AsMVTGeom({geom}, ST_Extent(ST_TileEnvelope({z}, {x}, {y})), 4096, 64, true)",
                        "'__fid': __fid"] + [f"{string_lit(c)}: {_mvt_prop(c, t)}" for c, t in
                                             (props.items() if isinstance(props, dict) else ((c, "VARCHAR") for c in props))])
    cond = (f"__maxx >= {w - pad} AND __minx <= {e + pad} AND __maxy >= {s - pad} AND __miny <= {n + pad}")
    if where:
        cond += f" AND ({where})"
    return (f"SELECT ST_AsMVT(t, {string_lit(layer_name)}) FROM (SELECT {{{fields}}} AS t FROM ({table_sql}) "
            f"WHERE {cond}) WHERE t.geom IS NOT NULL")


def render_tile(con, table_sql: str, z: int, x: int, y: int, props: list[str], where: str | None = None) -> bytes:
    types = _TYPES_CACHE.get(table_sql)
    if types is None:
        types = {r[0]: str(r[1]) for r in con.execute(f"DESCRIBE {table_sql}").fetchall()}
        _TYPES_CACHE[table_sql] = types
    typed = {c: types.get(c, "VARCHAR") for c in props}
    r = con.execute(tile_sql(table_sql, z, x, y, typed, where=where)).fetchone()
    return bytes(r[0]) if r and r[0] else b""


def features_geojson(con, table_sql: str, props: list[str], where: str | None = None, limit: int = 20000,
                     simplify: float = 0) -> dict:
    """GeoJSON (pour l'export ou les petites couches)."""
    g = f"ST_Simplify(geom, {simplify})" if simplify else "geom"
    sel = ", ".join([f"ST_AsGeoJSON({g}) AS __g"] + [ident(c) for c in props])
    rows = con.execute(f"SELECT {sel} FROM ({table_sql}) {'WHERE ' + where if where else ''} LIMIT {int(limit)}").fetchall()
    from .pipeline import to_json_value
    feats = [{"type": "Feature", "geometry": json.loads(r[0]) if r[0] else None,
              "properties": {c: to_json_value(v) for c, v in zip(props, r[1:])}} for r in rows]
    return {"type": "FeatureCollection", "features": feats}


# --------------------------------------------------------------------------- jeux de points (VMS…)


def points_sql(plan_sql: str, lon: str, lat: str) -> str:
    x, y = f"TRY_CAST({ident(lon)} AS DOUBLE)", f"TRY_CAST({ident(lat)} AS DOUBLE)"
    return (f"SELECT *, ST_Point({x}, {y}) AS geom, "
            f"ST_Transform(ST_Point({x}, LEAST(GREATEST({y}, -85), 85)), 'EPSG:4326', 'EPSG:3857') AS geom_m, "
            f"{x} AS __minx, {y} AS __miny, {x} AS __maxx, {y} AS __maxy, "
            f"row_number() OVER () AS __fid "
            f"FROM ({plan_sql}) WHERE {x} BETWEEN -180 AND 180 AND {y} BETWEEN -90 AND 90")


def materialize_points(con, plan_sql: str, lon: str, lat: str, cache_dir: Path) -> Path:
    """Met en cache les points d'un jeu (clé = SQL de la recette + colonnes) pour servir les tuiles."""
    key = hashlib.sha256(f"{plan_sql}|{lon}|{lat}".encode()).hexdigest()[:24]
    path = cache_dir / f"pts_{key}.parquet"
    if not path.exists():
        cache_dir.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        con.execute(f"COPY ({points_sql(plan_sql, lon, lat)} ORDER BY ST_Hilbert({ident(lon)}::DOUBLE, "
                    f"{ident(lat)}::DOUBLE, ST_Extent(ST_MakeEnvelope(-180, -90, 180, 90)))) "
                    f"TO {string_lit(str(tmp))} (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 8192)")
        os.replace(tmp, path)
        _prune_cache(cache_dir)
    return path


def _prune_cache(cache_dir: Path, keep: int = 40) -> None:
    files = sorted(cache_dir.glob("pts_*.parquet"), key=lambda p: p.stat().st_mtime, reverse=True)
    for p in files[keep:]:
        try:
            p.unlink()
        except OSError:
            pass


# --------------------------------------------------------------------------- rectangles CIEM

_LON_LETTERS = {"A": -44, "B": -40, "C": -30, "D": -20, "E": -10, "F": 0, "G": 10, "H": 20, "J": 30, "K": 40,
                "L": 50, "M": 60}


def ciem_code_sql(lon_expr: str, lat_expr: str) -> str:
    """Code du rectangle statistique CIEM (ex. 25E4) à partir de coordonnées."""
    row = f"CAST(floor(({lat_expr} - 36) * 2) + 1 AS INTEGER)"
    lonf = f"CAST(floor({lon_expr}) AS INTEGER)"
    letters = " ".join(f"WHEN {lonf} >= {v} AND {lonf} < {v + (4 if k == 'A' else 10)} THEN '{k}'"
                       for k, v in _LON_LETTERS.items())
    digit = (f"CASE WHEN {lonf} < -40 THEN {lonf} + 44 ELSE (({lonf} % 10) + 10) % 10 END")
    return (f"(CASE WHEN {lat_expr} IS NULL OR {lon_expr} IS NULL OR {lat_expr} < 36 OR {lat_expr} >= 85.5 "
            f"OR {lon_expr} < -44 OR {lon_expr} >= 70 THEN NULL "
            f"ELSE lpad({row}::VARCHAR, 2, '0') || (CASE {letters} END) || ({digit})::VARCHAR END)")


def ciem_bounds(code: str) -> tuple[float, float, float, float] | None:
    """Boîte (ouest, sud, est, nord) d'un rectangle CIEM, None si le code est invalide."""
    c = (code or "").strip().upper()
    if len(c) != 4 or not c[:2].isdigit() or c[2] not in _LON_LETTERS or not c[3].isdigit():
        return None
    row, letter, d = int(c[:2]), c[2], int(c[3])
    if letter == "A" and d > 3:
        return None
    south = 36 + (row - 1) * 0.5
    west = _LON_LETTERS[letter] + d
    return west, south, west + 1, south + 0.5


def ciem_polygon_sql(code_expr: str) -> str:
    """Expression SQL donnant le polygone d'un code de rectangle CIEM (NULL si invalide)."""
    c = f"upper(trim(CAST({code_expr} AS VARCHAR)))"
    letter = f"substr({c}, 3, 1)"
    base = "CASE " + " ".join(f"WHEN {letter} = '{k}' THEN {v}" for k, v in _LON_LETTERS.items()) + " END"
    west = f"({base} + TRY_CAST(substr({c}, 4, 1) AS INTEGER))"
    south = f"(36 + (TRY_CAST(substr({c}, 1, 2) AS INTEGER) - 1) * 0.5)"
    ok = f"regexp_full_match({c}, '[0-9]{{2}}[A-HJ-M][0-9]')"
    return (f"CASE WHEN {ok} THEN ST_MakeEnvelope({west}, {south}, {west} + 1, {south} + 0.5) END")


def ciem_grid_sql(west: float = -44, south: float = 36, east: float = 70, north: float = 85.5) -> str:
    """Grille complète des rectangles CIEM sur une emprise."""
    return (f"SELECT code AS rectangle, geom FROM (SELECT {ciem_code_sql('lon + 0.5', 'lat + 0.25')} AS code, "
            f"ST_MakeEnvelope(lon, lat, lon + 1, lat + 0.5) AS geom "
            f"FROM range({int(west)}, {int(east)}) r1(lon), "
            f"(SELECT {south} + i * 0.5 AS lat FROM range(0, {int((north - south) * 2)}) r2(i))) WHERE code IS NOT NULL")


# --------------------------------------------------------------------------- carroyage


def grid_sql(plan_sql: str, lon: str, lat: str, cell: float, value: str | None, agg: str,
             vessel: str | None = None, secret: int = 0) -> str:
    """Agrège des points dans une grille régulière (taille de maille en degrés)."""
    if not (0.001 <= cell <= 5):
        raise RecipeError("Taille de maille invalide (entre 0,001° et 5°).")
    x, y = f"TRY_CAST({ident(lon)} AS DOUBLE)", f"TRY_CAST({ident(lat)} AS DOUBLE)"
    aggs = {"nombre": "count(*)", "somme": "sum({v})", "moyenne": "avg({v})", "max": "max({v})",
            "navires": "count(DISTINCT {n})"}
    if agg not in aggs:
        raise RecipeError("Agrégation inconnue.")
    if agg in ("somme", "moyenne", "max") and not value:
        raise RecipeError("Choisissez la colonne à agréger.")
    if agg == "navires" and not vessel:
        raise RecipeError("Choisissez la colonne navire.")
    expr = aggs[agg].format(v=f"TRY_CAST({ident(value)} AS DOUBLE)" if value else "NULL",
                            n=ident(vessel) if vessel else "NULL")
    nav = f"count(DISTINCT {ident(vessel)})" if vessel else "NULL::BIGINT"
    inner = (f"SELECT floor({x} / {cell})::BIGINT AS gx, floor({y} / {cell})::BIGINT AS gy, {expr} AS valeur, "
             f"count(*) AS n_points, {nav} AS n_navires FROM ({plan_sql}) "
             f"WHERE {x} BETWEEN -180 AND 180 AND {y} BETWEEN -90 AND 90 GROUP BY ALL")
    masked = (f"CASE WHEN {secret} > 0 AND n_navires IS NOT NULL AND n_navires < {secret} THEN NULL ELSE valeur END"
              if secret else "valeur")
    return (f"SELECT gx || '_' || gy AS maille, {masked} AS valeur, n_points, n_navires, "
            f"{'(n_navires IS NOT NULL AND n_navires < ' + str(secret) + ')' if secret else 'false'} AS secret, "
            f"ST_MakeEnvelope(gx * {cell}, gy * {cell}, (gx + 1) * {cell}, (gy + 1) * {cell}) AS geom "
            f"FROM ({inner})")


def rect_sql(plan_sql: str, code_col: str, value: str | None, agg: str, vessel: str | None = None,
             secret: int = 0) -> str:
    """Agrège un jeu par rectangle CIEM (colonne de codes) pour une carte choroplèthe."""
    aggs = {"nombre": "count(*)", "somme": "sum({v})", "moyenne": "avg({v})", "max": "max({v})",
            "navires": "count(DISTINCT {n})"}
    if agg not in aggs:
        raise RecipeError("Agrégation inconnue.")
    if agg in ("somme", "moyenne", "max") and not value:
        raise RecipeError("Choisissez la colonne à agréger.")
    expr = aggs[agg].format(v=f"TRY_CAST({ident(value)} AS DOUBLE)" if value else "NULL",
                            n=ident(vessel) if vessel else "NULL")
    nav = f"count(DISTINCT {ident(vessel)})" if vessel else "NULL::BIGINT"
    code = f"upper(trim(CAST({ident(code_col)} AS VARCHAR)))"
    masked = (f"CASE WHEN n_navires IS NOT NULL AND n_navires < {secret} THEN NULL ELSE valeur END"
              if secret else "valeur")
    return (f"SELECT rectangle, {masked} AS valeur, n_lignes, n_navires, "
            f"{'(n_navires IS NOT NULL AND n_navires < ' + str(secret) + ')' if secret else 'false'} AS secret, "
            f"{ciem_polygon_sql('rectangle')} AS geom FROM (SELECT {code} AS rectangle, {expr} AS valeur, "
            f"count(*) AS n_lignes, {nav} AS n_navires FROM ({plan_sql}) GROUP BY ALL) WHERE rectangle IS NOT NULL")


# --------------------------------------------------------------------------- export


EXPORT_DRIVERS = {"geojson": ("GeoJSON", ".geojson"), "gpkg": ("GPKG", ".gpkg"), "shp": ("ESRI Shapefile", ".shp")}


def export_layer(con, table_sql: str, props: list[str], fmt: str, dest_dir: Path, name: str) -> Path:
    """Écrit la couche (WGS84) dans le format demandé ; renvoie le fichier (zip pour le SHP)."""
    if fmt not in EXPORT_DRIVERS:
        raise RecipeError("Format d'export inconnu (geojson, gpkg, shp).")
    driver, ext = EXPORT_DRIVERS[fmt]
    dest_dir.mkdir(parents=True, exist_ok=True)
    target = dest_dir / f"{name}{ext}"
    types = {r[0]: str(r[1]).upper() for r in con.execute(f"DESCRIBE {table_sql}").fetchall()}

    def col(c):
        t = types.get(c, "VARCHAR")
        if t.startswith(("DECIMAL", "HUGEINT", "UBIGINT")):
            return f"{ident(c)}::DOUBLE AS {ident(c)}"
        if t in ("NULL", '"NULL"') or t.startswith(("STRUCT", "LIST", "MAP")) or t.endswith("[]"):
            return f"CAST({ident(c)} AS VARCHAR) AS {ident(c)}"
        return ident(c)

    cols = ", ".join([col(c) for c in props] + ["geom"])
    opts = f"FORMAT GDAL, DRIVER {string_lit(driver)}, SRS 'EPSG:4326'"
    if fmt == "shp":
        opts += ", LAYER_CREATION_OPTIONS 'ENCODING=UTF-8'"
    con.execute(f"COPY (SELECT {cols} FROM ({table_sql})) TO {string_lit(str(target))} ({opts})")
    if fmt != "shp":
        return target
    zpath = dest_dir / f"{name}_shp.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in dest_dir.iterdir():
            if p.stem == name and p.suffix.lower() in {".shp", ".shx", ".dbf", ".prj", ".cpg"}:
                zf.write(p, p.name)
    return zpath


# --------------------------------------------------------------------------- couches intégrées

BUILTIN_DIR = Path(__file__).resolve().parent.parent / "couches"


def builtin_layers() -> dict[str, dict]:
    """Couches de contexte embarquées (manifeste couches.json)."""
    global _BUILTIN
    if _BUILTIN is None:
        f = BUILTIN_DIR / "couches.json"
        data = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {"couches": []}
        _BUILTIN = {c["id"]: c for c in data["couches"] if (BUILTIN_DIR / c["fichier"]).exists()}
        _BUILTIN_EXTRA.update({k: v for k, v in data.items() if k != "couches"})
    return _BUILTIN


def builtin_notes() -> dict:
    builtin_layers()
    return _BUILTIN_EXTRA


_BUILTIN: dict | None = None
_BUILTIN_EXTRA: dict = {}


# --------------------------------------------------------------------------- résolution des couches dans les recettes

LAYER_RESOLVER: contextvars.ContextVar = contextvars.ContextVar("moanui_layer_resolver", default=None)


def resolve_layer(layer_id: str) -> tuple[Path, list[str], str]:
    """(chemin Parquet, colonnes attributaires, nom) d'une couche accessible."""
    r = LAYER_RESOLVER.get()
    if r is None:
        raise RecipeError("Couches cartographiques indisponibles dans ce contexte.")
    return r(layer_id)
