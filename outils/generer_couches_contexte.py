"""Construit les couches de contexte embarquées dans Moanui (backend/moanui/couches/).

Usage (depuis backend/) :  uv run python ../outils/generer_couches_contexte.py
Télécharge les sources ouvertes, simplifie légèrement les géométries et écrit des Parquet prêts
à servir en tuiles, plus le manifeste couches.json (nom, source, licence, date).
"""

from __future__ import annotations

import io
import json
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from datetime import date
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from moanui.engine import geo  # noqa: E402

OUT = ROOT / "backend" / "moanui" / "couches"
DELMAR = "https://services.data.shom.fr/INSPIRE/telechargement/prepackageGroup/DELMAR-PACK_DL/prepackage/DELMAR/file/DELMAR.7z"
AMP = ("https://wxs.ofb.fr/geoserver/gestion/ows?service=WFS&version=2.0.0&request=GetFeature"
       "&typeNames=gestion:ges_omon_amp_ofb_pol_3857_vue&outputFormat=application/json&srsName=EPSG:4326")
NE_LAND = "https://naciscdn.org/naturalearth/10m/physical/ne_10m_land.zip"

SHOM = {"source": "Shom, Délimitations maritimes (DELMAR)", "licence": "Licence Ouverte Etalab 2.0",
        "url": "https://www.data.gouv.fr/datasets/delimitations-maritimes"}
OFB = {"source": "OFB, Aires marines protégées françaises", "licence": "Licence Ouverte Etalab 2.0",
       "url": "https://www.data.gouv.fr/datasets/aires-marines-protegees-francaises-2"}


def fetch(url: str, dest: Path) -> Path:
    if not dest.exists():
        print("téléchargement", url)
        req = urllib.request.Request(url, headers={"User-Agent": "Moanui-generateur"})
        with urllib.request.urlopen(req, timeout=600) as r:
            dest.write_bytes(r.read())
    return dest


def build(con, name: str, src_sql: str, meta: dict, tol: float = 0.0) -> dict:
    tmp = Path(tempfile.mkdtemp()) / f"{name}.parquet"
    g = f"ST_SimplifyPreserveTopology(geom, {tol})" if tol else "geom"
    con.execute(f"COPY (SELECT * EXCLUDE (geom), {g} AS geom FROM ({src_sql})) TO '{tmp}' (FORMAT parquet)")
    staged = tmp.with_name(f"{name}_src.parquet")
    tmp.rename(staged)
    out = OUT / f"{name}.parquet"
    if out.exists():
        out.chmod(0o644)
        out.unlink()
    # import_layer lit via GDAL : on passe par un GeoJSON-Seq intermédiaire pour garder les types
    fgb = staged.with_suffix(".fgb")
    con.execute(f"COPY (SELECT * FROM '{staged}') TO '{fgb}' (FORMAT GDAL, DRIVER 'FlatGeobuf', SRS 'EPSG:4326')")
    info = geo.import_layer(con, fgb, None, out, "EPSG:4326")
    out.chmod(0o644)
    print(f"{name}: {info['n_features']} entités, {out.stat().st_size // 1024} Ko")
    return {"id": name, **meta, "kind": info["kind"], "n_features": info["n_features"], "bbox": info["bbox"],
            "columns": info["columns"], "fichier": out.name}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.gettempdir()) / "moanui_couches"
    work.mkdir(exist_ok=True)
    con = duckdb.connect()
    geo.load_spatial(con)
    today = date.today().isoformat()
    layers = []

    layers.append(build(con, "ciem_rectangles", geo.ciem_grid_sql(), {
        "nom": "Rectangles statistiques CIEM", "groupe": "Référentiels",
        "description": "Grille des rectangles statistiques CIEM (1° × 0,5°), calculée.",
        "source": "Calcul Moanui selon la définition CIEM", "licence": "", "url": "https://www.ices.dk",
        "date": today, "style": {"couleur": "#7a7a7a", "epaisseur": 0.6, "remplissage": 0, "etiquette": "rectangle"}}))

    # Shom : limites maritimes
    d7 = fetch(DELMAR, work / "DELMAR.7z")
    dest = work / "delmar"
    if not dest.exists():
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "py7zr"], check=False)
        import py7zr
        with py7zr.SevenZipFile(d7) as z:
            z.extractall(dest)
    base = dest / "DELMAR"
    keep = "nature, type, descriptio AS description, reference, territory AS territoire"
    shom = [
        ("lignes_base", "1_Lignes_base_droites/SHAPE/Lignes_base_droites_WGS84.shp", "Lignes de base droites",
         "#5b5b5b"),
        ("mer_territoriale_12m", "2_Lim_ext_mer_territoriale/SHAPE/Lim_ext_MT_WGS84.shp",
         "Limite des 12 milles (mer territoriale)", "#2a78d6"),
        ("zone_contigue_24m", "3_Lim_ext_zone_contigue/SHAPE/Lim_ext_ZC_WGS84.shp",
         "Limite des 24 milles (zone contiguë)", "#6250d6"),
        ("zee_200m", "4_Lim_ext_zone_economique_exclusive/SHAPE/Lim_ext_ZEE_WGS84.shp",
         "Limite de la ZEE (200 milles)", "#e34948"),
    ]
    for lid, rel, nom, color in shom:
        layers.append(build(con, lid, f"SELECT {keep}, geom FROM ST_Read('{base / rel}')", {
            "nom": nom, "groupe": "Limites maritimes", "description": f"{nom} (Shom).", **SHOM, "date": today,
            "style": {"couleur": color, "epaisseur": 1.5}}))
    layers.append(build(con, "delimitations", (
        f"SELECT {keep}, 'avec accord' AS statut, geom FROM ST_Read('{base / '5_Delim_avec_accord/SHAPE/Delim_accord_WGS84.shp'}') "
        f"UNION ALL BY NAME SELECT {keep}, 'sans accord' AS statut, geom FROM "
        f"ST_Read('{base / '6_Lim_sans_accord/SHAPE/Lim_sans_accord_WGS84.shp'}')"), {
        "nom": "Délimitations avec les États voisins", "groupe": "Limites maritimes",
        "description": "Délimitations avec accord et limites sans accord (Shom).", **SHOM, "date": today,
        "style": {"couleur": "#eb6834", "epaisseur": 1.5, "pointilles": True}}))

    # OFB : aires marines protégées
    amp = fetch(AMP, work / "amp.json")
    cols = ("mpa_oriname AS nom, des_desigfr AS categorie, mpa_status AS statut, mpa_statusyr AS annee, "
            "mpa_mnhnid AS id_mnhn, subloc_name AS region, country_iso3namefr AS territoire, mpa_url AS lien")
    layers.append(build(con, "aires_marines_protegees", f"SELECT {cols}, geom FROM ST_Read('{amp}')", {
        "nom": "Aires marines protégées (toutes)", "groupe": "Environnement",
        "description": "Aires marines protégées françaises (Natura 2000, parcs, réserves, OSPAR…) (OFB).",
        **OFB, "date": today, "style": {"couleur": "#1baf7a", "epaisseur": 1, "remplissage": 0.25,
                                         "etiquette": "nom"}}, tol=0.0005))
    layers.append(build(con, "natura2000_mer", f"SELECT {cols}, geom FROM ST_Read('{amp}') "
                        "WHERE des_desigfr LIKE '%N2000%'", {
        "nom": "Natura 2000 en mer", "groupe": "Environnement",
        "description": "Sites Natura 2000 (ZSC, ZPS, SIC) ayant une partie marine (OFB).",
        **OFB, "date": today, "style": {"couleur": "#008300", "epaisseur": 1, "remplissage": 0.2,
                                         "etiquette": "nom"}}, tol=0.0005))

    # Natural Earth : terres (fond de carte hors ligne)
    zpath = fetch(NE_LAND, work / "ne_10m_land.zip")
    ne = work / "ne_land"
    if not ne.exists():
        ne.mkdir()
        zipfile.ZipFile(io.BytesIO(zpath.read_bytes())).extractall(ne)
    # Atlantique Nord-Est + Méditerranée, découpé en carreaux de 1° : chaque tuile ne lit que de petits
    # morceaux de côte (les DOM utilisent le fond en ligne)
    parts = (f"SELECT ST_SimplifyPreserveTopology(ST_Intersection(geom, ST_MakeEnvelope(-35, 24, 32, 72)), 0.002) "
             f"AS geom FROM ST_Read('{ne / 'ne_10m_land.shp'}') "
             f"WHERE ST_Intersects(geom, ST_MakeEnvelope(-35, 24, 32, 72))")
    con.execute(f"CREATE OR REPLACE TEMP TABLE _land AS SELECT unnest(ST_Dump(geom)).geom AS geom FROM ({parts})")
    land = ("SELECT 'terre' AS type, ST_Intersection(l.geom, ST_MakeEnvelope(x, y, x + 1, y + 1)) AS geom FROM _land l, "
            "LATERAL (SELECT x FROM range(floor(ST_XMin(l.geom))::BIGINT, ceil(ST_XMax(l.geom))::BIGINT) r(x)) gx, "
            "LATERAL (SELECT y FROM range(floor(ST_YMin(l.geom))::BIGINT, ceil(ST_YMax(l.geom))::BIGINT) r(y)) gy "
            "WHERE ST_Intersects(l.geom, ST_MakeEnvelope(x, y, x + 1, y + 1))")
    layers.append(build(con, "terres", f"SELECT * FROM ({land}) WHERE NOT ST_IsEmpty(geom)", {
        "nom": "Terres (fond hors ligne)", "groupe": "Fond de carte",
        "description": "Terres émergées au 1/10 000 000 (Atlantique Nord-Est et Méditerranée) : fond utilisable sans internet.",
        "source": "Natural Earth", "licence": "Domaine public", "url": "https://www.naturalearthdata.com",
        "date": today, "style": {"couleur": "#d9d4c7", "epaisseur": 0.5, "remplissage": 1}}))

    manifest = {"genere_le": today, "couches": layers,
                "manquantes": [
                    {"nom": "Bande des 3 milles", "conseil": "Importer la couche « Réglementation de la pêche aux arts "
                     "traînants dans la bande des 3 milles » (OFB / CNSP) depuis data.gouv.fr."},
                    {"nom": "Zones de frayère / ZFP, gisements",
                     "conseil": "Couches propres à chaque structure : à importer (SHP, GeoPackage, GeoJSON)."}]}
    (OUT / "couches.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    print("total", sum(p.stat().st_size for p in OUT.glob("*.parquet")) // 1024, "Ko")


if __name__ == "__main__":
    main()
