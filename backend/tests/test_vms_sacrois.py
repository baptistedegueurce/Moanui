"""Croisement VMS × captures déclarées : répartition par navire / jour / rectangle."""


def _post_csv(client, name, text):
    r = client.post("/api/datasets/import", files={"file": (name, text.encode(), "text/csv")})
    assert r.status_code == 200, r.text
    return r.json()["id"]


VMS = """navire,date_heure,lon,lat,activite
A,2023-01-02 06:00,-5.5,48.2,pêche
A,2023-01-02 07:00,-5.5,48.2,pêche
A,2023-01-02 08:00,-5.4,48.3,pêche
A,2023-01-02 09:00,-5.4,48.3,pêche
A,2023-01-02 10:00,-4.5,48.2,pêche
A,2023-01-02 11:00,-4.5,48.2,pêche
A,2023-01-02 12:00,-4.0,48.0,route
A,2023-01-03 06:00,-5.5,48.2,pêche
A,2023-01-03 07:00,-5.5,48.2,pêche
B,2023-01-02 06:00,-5.5,48.2,arrêt / lent
"""

CAPTURES = """nom_navire,date,stat_rect,esp_cod_fao,debarquement_Kg
a,02/01/2023,25E4,SOL,40
a,02/01/2023,25E5,SOL,10
a,02/01/2023,25E4,HKE,20
a,03/01/2023,26E4,SOL,6
a,04/01/2023,25E4,SOL,5
"""


def test_catch_split(client):
    vms = _post_csv(client, "vms.csv", VMS)
    cap = _post_csv(client, "captures.csv", CAPTURES)
    r = client.post(f"/api/datasets/{vms}/steps", json={"type": "ciem_rect", "params": {"lon": "lon", "lat": "lat"}})
    assert r.status_code == 200, r.text
    step = {"type": "vms_catch_split", "params": {
        "dataset_id": cap, "dataset_name": "captures", "vessel": "navire", "datetime": "date_heure",
        "rect": "rectangle_ciem", "activity": "activite", "activity_value": "pêche",
        "s_vessel": "nom_navire", "s_date": "date", "s_rect": "stat_rect", "s_species": "esp_cod_fao",
        "values": ["debarquement_Kg"], "weight": "egal"}}
    diag = client.post(f"/api/datasets/{vms}/steps/check", json=step).json()["diagnostics"]
    msgs = " | ".join(d["message"] for d in diag)
    assert "93,8 %" in msgs and "6,2 %" in msgs and "non attribué" in msgs, msgs  # 76 / 81 attribués
    r = client.post(f"/api/datasets/{vms}/steps", json=step)
    assert r.status_code == 200, r.text
    rows = client.post(f"/api/datasets/{vms}/rows", json={"offset": 0, "limit": 100}).json()
    cols = [c["name"] for c in rows["columns"]]
    recs = rows["rows"]
    get = (lambda r, c: r[c]) if isinstance(recs[0], dict) else (lambda r, c: r[cols.index(c)])
    assert abs(sum(get(r, "debarquement_Kg") for r in recs) - 76) < 1e-6
    sol_25e4 = [get(r, "debarquement_Kg") for r in recs
                if get(r, "esp_cod_fao") == "SOL" and get(r, "rectangle_ciem") == "25E4" and get(r, "date_heure").startswith("2023-01-02")]
    assert len(sol_25e4) == 4 and all(abs(v - 10) < 1e-6 for v in sol_25e4)
    # rectangle déclaré sans position : repli au niveau du jour (2 positions × 3 kg)
    day = [r for r in recs if get(r, "niveau_repartition") == "jour"]
    assert len(day) == 2 and all(abs(get(r, "debarquement_Kg") - 3) < 1e-6 for r in day)
    assert {get(r, "activite") for r in recs} == {"pêche"}
    # pondération par durée (écart entre positions), toutes positions, positions sans capture conservées
    vms2 = _post_csv(client, "vms2.csv", VMS.replace(",activite", "").replace(",pêche", "").replace(",route", "")
                     .replace(",arrêt / lent", ""))
    r = client.post(f"/api/datasets/{vms2}/steps", json={"type": "vms_activity", "params": {
        "vessel": "navire", "datetime": "date_heure", "lon": "lon", "lat": "lat", "min": 0, "max": 40}})
    assert r.status_code == 200, r.text
    step["params"].update({"dataset_id": cap, "weight": "duree", "keep_unmatched": True, "rect": "", "s_rect": "",
                           "activity": "", "s_species": ""})
    r = client.post(f"/api/datasets/{vms2}/steps", json=step)
    assert r.status_code == 200, r.text
    rows = client.post(f"/api/datasets/{vms2}/rows", json={"offset": 0, "limit": 100}).json()
    cols = [c["name"] for c in rows["columns"]]
    recs = rows["rows"]
    get = (lambda r, c: r[c]) if isinstance(recs[0], dict) else (lambda r, c: r[cols.index(c)])
    assert len(recs) == 10  # toutes les positions, y compris B sans capture
    a2 = {get(r, "date_heure")[:16].replace("T", " "): get(r, "debarquement_Kg") for r in recs if get(r, "navire") == "A"}
    # 1re position / après coupure : intervalle médian (60 min) → 70 kg / 7 positions, 6 kg / 2
    assert abs(sum(v or 0 for v in a2.values()) - 76) < 1e-6
    assert abs(a2["2023-01-02 06:00"] - 10) < 1e-6 and abs(a2["2023-01-03 06:00"] - 3) < 1e-6
