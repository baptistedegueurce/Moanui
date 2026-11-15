"""Données de démonstration (exemples/donnees_demo) : chaque fichier passe dans le moteur et sert un scénario."""

from pathlib import Path

import pytest

DEMO = Path(__file__).resolve().parents[2] / "exemples" / "donnees_demo"
pytestmark = pytest.mark.skipif(not DEMO.exists(), reason="données de démonstration absentes")


def imp(client, name, **form):
    with open(DEMO / name, "rb") as f:
        r = client.post("/api/datasets/import", files={"file": (name, f, "application/octet-stream")}, data=form)
    assert r.status_code == 200, r.text
    return r.json()


def schema(client, did):
    return {c["name"]: c["type"] for c in client.get(f"/api/datasets/{did}").json()["schema"]}


def batch(client, did, steps):
    r = client.post(f"/api/datasets/{did}/steps/batch", json={"steps": [
        {"type": s["type"], "params": s["params"]} for s in steps]})
    assert r.status_code == 200, r.text
    d = client.get(f"/api/datasets/{did}").json()
    assert d["error"] is None and all(s.get("status") != "erreur" for s in d["steps"]), d["steps"]


def msgs(chk):
    return " | ".join(x["message"] for x in chk["diagnostics"])


def stat(client, did, **body):
    r = client.post(f"/api/datasets/{did}/stats", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def test_sacrois_flotte_jointures_empilement_secret(client):
    s25 = imp(client, "sacrois_2025.csv", kind="sacrois")["id"]
    s24 = imp(client, "sacrois_2024.csv", kind="sacrois")["id"]  # Windows-1252
    t23 = imp(client, "sacrois_2023_extrait_tonnes.csv")["id"]
    for did in (s25, s24):
        sc = schema(client, did)
        assert sc["date_deb"].upper().startswith("DATE") and sc["debarquement_Kg"].upper() == "DOUBLE", sc
    rows24 = client.post(f"/api/datasets/{s24}/rows", json={"limit": 3000}).json()
    assert "Démersal" not in str(rows24)  # (pas de libellé dans SACROIS) mais accents lisibles ailleurs
    prop = client.get(f"/api/datasets/{s25}/templates/sacrois").json()
    types = [s["type"] for s in prop["steps"]]
    assert {"clean_text", "date_parts", "case_when", "lookup", "gear_check", "formula", "unit_convert"} <= set(types)
    gear = next(s for s in prop["steps"] if s["type"] == "gear_check")
    inc = client.post(f"/api/datasets/{s25}/gear-inconsistencies", json=gear).json()
    assert {(i["species"], i["gear"]) for i in inc} >= {("SOL", "FPO"), ("NEP", "LHP"), ("SCE", "OTB")}, inc
    batch(client, s25, prop["steps"])
    # empilement 2024 + 2025 (+ extrait 2023 saisi en tonnes)
    chk = client.post(f"/api/datasets/{s25}/steps/check", json={
        "type": "union", "params": {"dataset_ids": [s24, t23], "source_column": "fichier"}}).json()
    assert chk["ok"] and "Unités différentes" in msgs(chk), msgs(chk)
    # jointures : flotte (Excel) et référentiel espèces (clé inconnue XXX, codes non nettoyés)
    flotte = imp(client, "flotte_navires.xlsx")["id"]
    assert "patron" in schema(client, flotte)
    esp = imp(client, "ref_especes.csv")["id"]
    raw = imp(client, "sacrois_2025.csv")["id"]
    chk = client.post(f"/api/datasets/{raw}/steps/check", json={"type": "join", "params": {
        "dataset_id": esp, "how": "left", "keys": [{"left": "esp_cod_fao", "right": "esp_cod_fao"}]}}).json()
    assert chk["ok"] and "sans correspondance" in msgs(chk), msgs(chk)
    j = {"type": "join", "params": {"dataset_id": flotte, "how": "left",
                                     "keys": [{"left": "navire_cod", "right": "navire_cod"}]}}
    assert client.post(f"/api/datasets/{s25}/steps", json=j).status_code == 200
    # secret statistique : dragueurs (3 navires, 1 port) et petits groupes
    chk = client.post(f"/api/datasets/{s25}/steps/check", json={"type": "aggregate", "params": {
        "group_by": ["esp_cod_fao", "port_cod", "date_deb_mois"],
        "aggregations": [{"column": "debarquement_Kg", "fn": "somme", "name": "kg"}],
        "secret": {"vessel_column": "navire_cod", "threshold": 3}}}).json()
    assert chk["ok"] and "Secret statistique" in msgs(chk), (chk.get("error"), str(list(schema(client, s25))))
    # doublons et sensibles
    chk = client.post(f"/api/datasets/{raw}/steps/check", json={"type": "dedupe", "params": {}}).json()
    assert chk["ok"] and chk["n_after"] < chk.get("n_before", 10 ** 9)
    assert client.get(f"/api/datasets/{flotte}/export?fmt=csv").status_code == 409  # patron, téléphone…
    # statistiques sur les marées préparées
    g = stat(client, s25, analyse="comparer_groupes", variables={"y": "cpue_kg_jdm", "groupe": "metier"})
    assert g["checks"]
    a = stat(client, s25, analyse="association", variables={"x": "metier", "y": "NS"})
    assert a["checks"]
    c = stat(client, s25, analyse="correlation", variables={"x": "longueur_m", "y": "debarquement_Kg"})
    assert c["checks"]
    r = stat(client, s25, analyse="regression", force=True, justification="essai",
             variables={"y": "debarquement_Kg", "x": ["longueur_m", "puissance_kw", "metier"]})
    assert r["checks"]
    glm = stat(client, s25, analyse="glm", variables={"y": "debarquement_Kg", "x": ["metier", "date_deb_mois"],
                                                     "effort": "duree_maree"})
    assert glm["bloque"]  # poids nuls glissés dans l'export : conseil « delta » (filtrer > 0 puis Gamma)
    assert client.post(f"/api/datasets/{s25}/steps", json={"type": "filter", "params": {
        "conditions": [{"column": "debarquement_Kg", "op": "gt", "value": 0}]}}).status_code == 200
    glm = stat(client, s25, analyse="glm", variables={"y": "debarquement_Kg", "x": ["metier", "date_deb_mois"],
                                                     "effort": "duree_maree"})
    assert glm["test"] == "gamma", [(c["nom"], c["message"]) for c in glm["checks"]]


def test_suivi_casiers_glm(client):
    did = imp(client, "suivi_casiers_homard.csv")["id"]
    res = stat(client, did, analyse="glm", variables={"y": "nb_homards", "x": ["zone", "annee"], "effort": "nb_casiers"})
    assert res["test"] == "binomiale_negative" and not res["bloque"], res["test"]
    po = stat(client, did, analyse="glm", test="poisson", variables={"y": "nb_homards", "x": ["zone"],
                                                                     "effort": "nb_casiers"})
    assert po["bloque"]  # surdispersion : blocage contournable


def test_vms_agiltech_cls_zone_et_repartition(client):
    ids = {}
    for name in ("vms_agiltech_2025.csv", "vms_cls_2025.csv"):
        did = imp(client, name)["id"]
        prop = client.get(f"/api/datasets/{did}/templates/vms").json()
        i = [s["type"] for s in prop["steps"]].index("vms_activity")
        batch(client, did, prop["steps"][:i])
        chk = client.post(f"/api/datasets/{did}/steps/check", json={
            "type": "vms_activity", "params": prop["steps"][i]["params"]}).json()
        assert "25 nœuds" in msgs(chk), msgs(chk)
        batch(client, did, prop["steps"][i:])
        ids[name] = did
    a, c = ids.values()
    chk = client.post(f"/api/datasets/{a}/steps/check", json={
        "type": "union", "params": {"dataset_ids": [c], "source_column": "fournisseur"}}).json()
    assert chk["ok"], chk
    assert client.post(f"/api/datasets/{a}/steps", json={
        "type": "union", "params": {"dataset_ids": [c], "source_column": "fournisseur"}}).status_code == 200
    # aucune position de pêche à terre ; des positions dans la zone éolienne fictive
    for layer, name in (("ctx:terres", "a_terre"),):
        r = client.post(f"/api/datasets/{a}/steps", json={"type": "zone_tag", "params": {
            "layer": layer, "lon": "lon", "lat": "lat", "name": name}})
        assert r.status_code == 200, r.text
    lay = client.post("/api/geo/layers", files=[("files", ("zone_eolienne_fictive.geojson",
                      (DEMO / "zone_eolienne_fictive.geojson").read_bytes(), "application/geo+json"))],
                      data={"name": "Zone éolienne fictive"})
    assert lay.status_code == 200, lay.text
    r = client.post(f"/api/datasets/{a}/steps", json={"type": "zone_tag", "params": {
        "layer": lay.json()["id"], "attribute": "nom", "lon": "lon", "lat": "lat", "name": "zone_eol"}})
    assert r.status_code == 200, r.text
    chk = client.post(f"/api/datasets/{a}/steps/check", json={"type": "aggregate", "params": {
        "group_by": ["activite", "a_terre", "zone_eol"], "aggregations": [{"column": "lat", "fn": "nombre", "name": "n"}]}}).json()
    assert chk["ok"], chk
    cols = [x["name"] for x in chk["preview"]["columns"]]
    rows = [dict(zip(cols, r)) for r in chk["preview"]["rows"]]
    assert not [r for r in rows if r["activite"] == "pêche" and r["a_terre"]], rows
    assert sum(r["n"] for r in rows if r["zone_eol"] and r["activite"] == "pêche") > 50, rows
    # croisement avec les captures 2025
    cap = imp(client, "sacrois_2025.csv")["id"]
    step = {"type": "vms_catch_split", "params": {
        "dataset_id": cap, "dataset_name": "sacrois_2025", "vessel": "navire", "datetime": "date_heure",
        "rect": "rectangle_ciem", "activity": "activite", "activity_value": "pêche",
        "s_vessel": "navire_cod", "s_date": "date_deb", "s_rect": "stat_rect", "s_species": "esp_cod_fao",
        "values": ["debarquement_Kg", "debarquement_euros"], "weight": "duree"}}
    chk = client.post(f"/api/datasets/{a}/steps/check", json=step).json()
    assert chk["ok"], chk
    m = msgs(chk)
    assert "non attribué" in m, m
    part = float(m.split("attribué aux positions : ")[1].split(" %")[0].replace(",", "."))
    assert 35 < part < 95, m
    print(m)


def test_couches_sig(client):
    for name, kind in (("zone_eolienne_fictive.geojson", "polygone"), ("gisements_coquille_fictifs.kml", "polygone"),
                       ("cantonnements_fictifs_L93.zip", "polygone"), ("ports_fictifs.gpkg", "point")):
        r = client.post("/api/geo/layers", files=[("files", (name, (DEMO / name).read_bytes(), "application/octet-stream"))],
                        data={"name": name})
        assert r.status_code == 200, (name, r.text)
        lay = r.json()
        assert lay["kind"] == kind and lay["n_features"] >= 2, (name, lay)
        if name.endswith(".zip"):
            assert lay["crs_source"] == "EPSG:2154"
