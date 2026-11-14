"""Transformations de colonnes (onglet Colonnes) et fusion de colonnes."""

from conftest import upload


def _rows(client, did):
    r = client.post(f"/api/datasets/{did}/rows", json={"offset": 0, "limit": 500}).json()
    cols = [c["name"] for c in r["columns"]]
    return cols, [dict(zip(cols, x)) if not isinstance(x, dict) else x for x in r["rows"]]


def _add(client, did, type_, **params):
    r = client.post(f"/api/datasets/{did}/steps", json={"type": type_, "params": params})
    assert r.status_code == 200, r.text


def test_transform_and_coalesce(client):
    did = upload(client, "logbook_2023.csv")["id"]
    _add(client, did, "transform", columns=["port_cod", "quartier_cod"], op="minuscules")
    _add(client, did, "transform", columns=["debarquement_Kg"], op="log1p", suffix="_log")
    _add(client, did, "transform", columns=["duree_maree"], op="arrondir", digits=0)
    _add(client, did, "transform", columns=["debarquement_euros"], op="classes_quantiles", k=4, suffix="_classe")
    _add(client, did, "transform", columns=["debarquement_Kg"], op="classes_egales", k=5, suffix="_cl")
    _add(client, did, "coalesce", columns=["stat_rect", "div_ciem_cod_sipa"], name="zone")
    cols, rows = _rows(client, did)
    assert all(r["port_cod"] == r["port_cod"].lower() for r in rows)
    assert {"debarquement_Kg_log", "debarquement_euros_classe", "debarquement_Kg_cl", "zone"} <= set(cols)
    assert all(float(r["duree_maree"]).is_integer() for r in rows if r["duree_maree"] is not None)
    q = {r["debarquement_euros_classe"][:2] for r in rows if r["debarquement_euros_classe"]}
    assert q == {"Q1", "Q2", "Q3", "Q4"}
    assert len({r["debarquement_Kg_cl"] for r in rows if r["debarquement_Kg_cl"]}) == 5
    assert [r["__ligne"] for r in rows] == sorted(r["__ligne"] for r in rows)
    bad = client.post(f"/api/datasets/{did}/steps", json={"type": "transform", "params": {"columns": ["port_cod"], "op": "ln"}})
    assert bad.status_code == 400 and "numérique" in bad.json()["detail"]
