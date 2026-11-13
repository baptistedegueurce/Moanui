import io
import os
import stat
import zipfile

from conftest import PASSWORD, upload


def test_setup_once_and_login(client):
    assert client.get("/api/setup/status").json() == {"needs_setup": False}
    r = client.post("/api/setup", json={"username": "xx", "display_name": "x", "password": PASSWORD,
                                        "structure_name": "Autre", "structure_short_name": "A"})
    assert r.status_code == 409
    client.post("/api/auth/logout")
    assert client.get("/api/auth/me").status_code == 401
    assert client.post("/api/auth/login", json={"username": "admin", "password": "faux"}).status_code == 401
    assert client.post("/api/auth/login", json={"username": "ADMIN", "password": PASSWORD}).status_code == 200
    me = client.get("/api/auth/me").json()
    assert me["is_superadmin"] and me["structures"][0]["role"] == "admin"


def test_import_keeps_raw_untouched(client, tmp_path):
    res = upload(client, "inner_marees.csv")
    cols = {c["name"]: c for c in res["report"]["columns"]}
    # « 2023-13-20 » : la colonne reste en texte, avec un avertissement
    assert cols["date_maree"]["type"] == "texte"
    assert cols["date_maree"]["warning"]["examples"] == ["2023-13-20"]
    raw_files = [p for p in (tmp_path / "home" / "raw").rglob("*") if p.is_file()]
    assert raw_files and all(not (p.stat().st_mode & stat.S_IWUSR) for p in raw_files)
    d = client.get(f"/api/datasets/{res['id']}").json()
    assert client.get(f"/api/datasets/{res['id']}/integrity").json()["ok"]
    assert d["raw"]["n_rows"] == 25


def test_recipe_edit_cells_then_cast(client):
    did = upload(client, "inner_marees.csv")["id"]
    rows = client.post(f"/api/datasets/{did}/rows", json={"filters": [
        {"column": "date_maree", "op": "eq", "value": "2023-13-20"}]}).json()
    row_id = rows["rows"][0][0]
    r = client.post(f"/api/datasets/{did}/steps", json={
        "type": "edit_cells", "comment": "mois 13 impossible : saisie 2023-12-20 d'après le carnet",
        "params": {"edits": [{"row": row_id, "column": "date_maree", "value": "2023-12-20", "old": "2023-13-20"}]}})
    assert r.status_code == 200, r.text
    r = client.post(f"/api/datasets/{did}/steps", json={"type": "cast", "params": {"column": "date_maree", "to": "date"}})
    assert r.status_code == 200, r.text
    d = client.get(f"/api/datasets/{did}").json()
    assert {"name": "date_maree", "type": "DATE"} in d["schema"]
    assert [s.get("n_rows") for s in d["steps"]] == [25, 25, 25]
    md = client.get(f"/api/datasets/{did}/method.md").text
    assert "mois 13 impossible" in md and "SHA-256" in md and "ancienne valeur" in md


def test_invalid_step_rejected(client):
    did = upload(client, "inner_marees.csv")["id"]
    r = client.post(f"/api/datasets/{did}/steps", json={"type": "formula",
                                                        "params": {"name": "x", "expression": "[inconnue] * 2"}})
    assert r.status_code == 400 and "inconnue" in r.json()["detail"]
    r = client.post(f"/api/datasets/{did}/steps", json={"type": "formula",
                                                        "params": {"name": "x", "expression": "1; DROP TABLE x"}})
    assert r.status_code == 400


def test_union_detects_unit_problem(client):
    a = upload(client, "rbind_annee_2021.csv")["id"]
    b = upload(client, "rbind_annee_2022.csv")["id"]
    c = upload(client, "rbind_annee_2023.csv")["id"]
    chk = client.post(f"/api/datasets/{a}/steps/check", json={
        "type": "union", "params": {"dataset_ids": [b, c], "source_column": "fichier"}}).json()
    assert chk["ok"] and chk["n_after"] == 210
    msgs = " ".join(x["message"] for x in chk["diagnostics"])
    assert "Unités différentes" in msgs and "source" in msgs


def test_join_diagnostics_and_cycle(client):
    log = upload(client, "left_logbook_marees.csv")["id"]
    ports = upload(client, "left_ref_ports.csv")["id"]
    step = {"type": "join", "params": {"dataset_id": ports, "how": "left",
                                       "keys": [{"left": "port_cod", "right": "port_cod"}]}}
    chk = client.post(f"/api/datasets/{log}/steps/check", json=step).json()
    assert chk["ok"] and chk["n_after"] == 20
    assert any("sans correspondance" in d["message"] for d in chk["diagnostics"])
    assert client.post(f"/api/datasets/{log}/steps", json=step).status_code == 200
    back = {"type": "join", "params": {"dataset_id": log, "how": "left",
                                       "keys": [{"left": "port_cod", "right": "port_cod"}]}}
    r = client.post(f"/api/datasets/{ports}/steps", json=back)
    assert r.status_code == 400 and "circulaire" in r.json()["detail"]


def test_export_requires_confirmation_for_sensitive(client):
    did = upload(client, "left_logbook_marees.csv")["id"]
    r = client.get(f"/api/datasets/{did}/export?fmt=csv")
    assert r.status_code == 409
    client.post(f"/api/datasets/{did}/steps", json={"type": "anonymize", "params": {"columns": ["nom_navire"]}})
    r = client.get(f"/api/datasets/{did}/export?fmt=xlsx")
    assert r.status_code == 200, r.text
    z = zipfile.ZipFile(io.BytesIO(r.content))
    names = z.namelist()
    assert any(n.endswith(".xlsx") for n in names) and any(n.endswith("_methode.md") for n in names)


def test_roles_and_sharing(client):
    me = client.get("/api/auth/me").json()
    sid1 = me["structures"][0]["id"]
    sid2 = client.post("/api/admin/structures", json={"name": "Autre structure", "short_name": "AS"}).json()["id"]
    client.post("/api/admin/users", json={"username": "lect", "display_name": "Lecteur", "password": PASSWORD,
                                          "memberships": [{"structure_id": sid2, "role": "analyste"}]})
    did = upload(client, "left_ref_ports.csv")["id"]
    client.post("/api/auth/logout")
    client.post("/api/auth/login", json={"username": "lect", "password": PASSWORD})
    assert client.get(f"/api/datasets/{did}").status_code == 404  # cloisonnement
    client.post("/api/auth/logout")
    client.post("/api/auth/login", json={"username": "admin", "password": PASSWORD})
    client.post("/api/auth/active-structure", json={"structure_id": sid1})
    assert client.post(f"/api/datasets/{did}/shares", json={"structure_id": sid2}).status_code == 200
    client.post("/api/auth/logout")
    client.post("/api/auth/login", json={"username": "lect", "password": PASSWORD})
    d = client.get(f"/api/datasets/{did}").json()
    assert d["mode"] == "lecture"
    r = client.post(f"/api/datasets/{did}/steps", json={"type": "sort", "params": {"by": [{"column": "port_cod"}]}})
    assert r.status_code == 403
    assert client.post(f"/api/datasets/{did}/duplicate").status_code == 200


def test_theme_validation(client):
    sid = client.get("/api/auth/me").json()["structures"][0]["id"]
    r = client.patch(f"/api/structures/{sid}", json={"theme": {"colors": {"primary": "red"}}})
    assert r.status_code == 400
    r = client.patch(f"/api/structures/{sid}", json={"theme": {"colors": {"primary": "#112233"}}})
    assert r.status_code == 200 and r.json()["theme"]["colors"]["primary"] == "#112233"
    svg = b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
    r = client.post(f"/api/structures/{sid}/logo", files={"file": ("l.svg", svg, "image/svg+xml")})
    assert r.status_code == 400


def test_profile_consistency_checks(client):
    did = upload(client, "vms_cls_2023.csv")["id"]
    p = client.get(f"/api/datasets/{did}/profile").json()
    assert p["n_rows"] == 3000
    assert os.environ.get("X") is None
