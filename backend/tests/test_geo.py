"""Cartographie : couches intégrées et importées, tuiles, VMS, carroyage, exports."""

import io
import zipfile

import duckdb

from moanui.engine import geo

from conftest import upload


def _shp_zip(tmp_path) -> bytes:
    con = duckdb.connect()
    geo.load_spatial(con)
    out = tmp_path / "zones.shp"
    # deux carrés en Lambert-93 autour de Brest / Lorient
    con.execute(f"""COPY (SELECT * FROM (VALUES
        ('Zone A', ST_Transform(ST_MakeEnvelope(-6, 47, -3, 49), 'EPSG:4326', 'EPSG:2154')),
        ('Zone B', ST_Transform(ST_MakeEnvelope(-3, 47, 0, 49), 'EPSG:4326', 'EPSG:2154'))) t(nom, geom))
        TO '{out}' (FORMAT GDAL, DRIVER 'ESRI Shapefile', SRS 'EPSG:2154')""")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for p in tmp_path.iterdir():
            if p.stem == "zones":
                z.write(p, f"dossier/{p.name}")
    return buf.getvalue()


def test_builtin_layers_and_tiles(client):
    r = client.get("/api/geo/layers").json()
    ids = {c["id"] for c in r["couches"]}
    assert {"ctx:ciem_rectangles", "ctx:mer_territoriale_12m", "ctx:zee_200m", "ctx:natura2000_mer"} <= ids
    t = client.get("/api/geo/layers/ctx:terres/tiles/5/15/11.pbf")
    assert t.status_code == 200 and len(t.content) > 100
    assert client.get("/api/geo/layers/ctx:inconnue/tiles/0/0/0.pbf").status_code == 404


def test_import_shapefile_lambert93(client, tmp_path):
    r = client.post("/api/geo/layers", files=[("files", ("zones.zip", _shp_zip(tmp_path), "application/zip"))],
                    data={"name": "Zones test"})
    assert r.status_code == 200, r.text
    lay = r.json()
    assert lay["n_features"] == 2 and lay["kind"] == "polygone" and lay["crs_source"] == "EPSG:2154"
    assert abs(lay["bbox"][0] + 6) < 1e-6 and abs(lay["bbox"][3] - 49) < 1e-6  # reprojeté en WGS84
    assert client.get(f"/api/geo/layers/{lay['id']}/values/nom").json()["values"][0]["n"] == 1
    assert len(client.get(f"/api/geo/layers/{lay['id']}/tiles/6/30/22.pbf").content) > 50
    ex = client.get(f"/api/geo/layers/{lay['id']}/export", params={"fmt": "gpkg"})
    assert ex.status_code == 200 and ex.content[:15] == b"SQLite format 3"
    # shapefile incomplet refusé
    bad = client.post("/api/geo/layers", files=[("files", ("x.shp", b"123", "application/octet-stream"))])
    assert bad.status_code == 400 and "incomplet" in bad.json()["detail"]
    assert client.delete(f"/api/geo/layers/{lay['id']}").json()["ok"]


def test_vms_template_activity_zone_and_grid(client, tmp_path):
    for name in ("vms_cls_2023.csv", "vms_agiltech_2023.csv"):
        did = upload(client, name)["id"]
        prop = client.get(f"/api/datasets/{did}/templates/vms").json()
        types = [s["type"] for s in prop["steps"]]
        assert types[0] == "rename" and "vms_activity" in types and "ciem_rect" in types
        assert ("unit_convert" in types) == (name.startswith("vms_cls"))
        r = client.post(f"/api/datasets/{did}/steps/batch", json={"steps": [
            {"type": s["type"], "params": s["params"]} for s in prop["steps"]]})
        assert r.status_code == 200, r.text
        # zone : rectangle CIEM retrouvé par jointure spatiale = rectangle calculé
        r = client.post(f"/api/datasets/{did}/steps", json={"type": "zone_tag", "params": {
            "layer": "ctx:ciem_rectangles", "attribute": "rectangle", "lon": "lon", "lat": "lat", "name": "rect_spatial"}})
        assert r.status_code == 200, r.text
        d = client.get(f"/api/datasets/{did}").json()
        assert all(s.get("status") != "erreur" for s in d["steps"]), d["steps"]
        rows = client.post(f"/api/datasets/{did}/rows", json={"offset": 0, "limit": 300}).json()
        cols = [c["name"] for c in rows["columns"]]
        recs = rows["rows"]
        get = (lambda r, c: r[c]) if isinstance(recs[0], dict) else (lambda r, c: r[cols.index(c)])
        assert max(get(r, "vitesse_nds") or 0 for r in recs) <= 12
        assert {get(r, "activite") for r in recs} <= {"pêche", "route", "arrêt / lent", None}
        ok = [r for r in recs if get(r, "rectangle_ciem")]
        assert ok and all(get(r, "rectangle_ciem") == get(r, "rect_spatial") for r in ok)

        pts = client.post(f"/api/geo/datasets/{did}/points", json={"lon": "lon", "lat": "lat"}).json()
        assert pts["n"] > 1000 and pts["ignored"] == 0
        assert client.get(f"/api/geo/points/{pts['key']}/tiles/4/7/5.pbf").status_code == 200

        g = client.post(f"/api/geo/datasets/{did}/aggregate", json={
            "mode": "grille", "lon": "lon", "lat": "lat", "cell": 0.5, "agg": "navires", "vessel": "navire",
            "secret": 3}).json()
        assert g["n"] > 0 and g["masquees"] == g["n"]  # 1 ou 2 navires : tout est masqué
        c = client.post(f"/api/geo/datasets/{did}/aggregate", json={
            "mode": "ciem", "rect_column": "rectangle_ciem", "agg": "nombre"}).json()
        assert c["total"] == pts["n"]  # chaque position compte dans un rectangle
        ex = client.post(f"/api/geo/datasets/{did}/aggregate/export", params={"fmt": "shp"},
                         json={"mode": "ciem", "rect_column": "rectangle_ciem", "agg": "nombre"})
        assert ex.status_code == 200
        assert any(n.endswith(".shp") for n in zipfile.ZipFile(io.BytesIO(ex.content)).namelist())


def test_ciem_codes():
    assert geo.ciem_bounds("25E4") == (-6, 48.0, -5, 48.5)
    assert geo.ciem_bounds("28F1") == (1, 49.5, 2, 50.0)
    assert geo.ciem_bounds("25I4") is None
    con = duckdb.connect()
    got = con.execute(f"SELECT {geo.ciem_code_sql('-5.5', '48.2')}, {geo.ciem_code_sql('1.5', '49.7')}, "
                      f"{geo.ciem_code_sql('-10.5', '36.1')}").fetchone()
    assert got == ("25E4", "28F1", "01D9")


def test_maps_crud(client):
    m = client.post("/api/geo/maps", json={"name": "Carte 1", "spec": {"couches": []}}).json()
    assert client.get("/api/geo/maps").json()[0]["id"] == m["id"]
    assert client.put(f"/api/geo/maps/{m['id']}", json={"name": "Carte 2", "spec": {}}).json()["name"] == "Carte 2"
    assert client.delete(f"/api/geo/maps/{m['id']}").json()["ok"]
