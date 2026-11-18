"""Code R équivalent des graphiques : un script par type, exécuté avec Rscript quand R est installé."""

import io
import shutil
import subprocess
import zipfile

import pytest
from conftest import upload

K, E, D = "debarquement_Kg", "debarquement_euros", "duree_maree"
TPL = {"title": "Essai", "subtitle": "Sous-titre", "source": "SACROIS fictif", "author": "Équipe", "show_date": True,
       "width": 900, "height": 500}

SPECS = {
    "barres": {"type": "barres", "x": "engin_cod", "series": "quartier_cod", "stack": "empile",
               "measures": [{"agg": "somme", "column": K}], "sort": "valeur_desc", "show_values": True},
    "barres_h": {"type": "barres_h", "x": "esp_cod_fao", "measures": [{"agg": "somme", "column": K}],
                 "axes": {"y": {"min": 0, "max": 200000}}},
    "pourcent": {"type": "barres", "x": "engin_cod", "series": "quartier_cod", "stack": "pourcent",
                 "measures": [{"agg": "nombre_lignes"}]},
    "lignes": {"type": "lignes", "x": "date", "series": "quartier_cod", "measures": [{"agg": "somme", "column": K}],
               "refs": [{"kind": "ligne_h", "value": 5000, "label": "Seuil"},
                        {"kind": "ligne_v", "value": "2023-01-05", "label": "Fermeture"}]},
    "aires": {"type": "aires", "x": "date", "series": "engin_cod", "stack": "empile",
              "measures": [{"agg": "somme", "column": K}]},
    "combine": {"type": "combine", "x": "engin_cod", "measures": [
        {"agg": "somme", "column": K, "mark": "barres"},
        {"agg": "somme", "column": E, "mark": "barres"},
        {"agg": "moyenne", "column": D, "mark": "lignes", "axis": "y2", "dash": True},
        {"agg": "max", "column": D, "mark": "points", "axis": "y3"}],
        "axes": {"y": {"title": "Volumes", "suffix": "kg"}, "y2": {"title": "Durée (j)"}},
        "refs": [{"kind": "zone_v", "value": "GNS", "value2": "OTB", "label": "Arts"},
                 {"kind": "note", "value": "OTB", "label": "Chalut"}], "legend": "bas"},
    "secteurs": {"type": "secteurs", "x": "quartier_cod", "measures": [{"agg": "somme", "column": E}]},
    "chaleur": {"type": "chaleur", "x": "engin_cod", "series": "quartier_cod",
                "measures": [{"agg": "moyenne", "column": K}]},
    "nuage": {"type": "nuage", "x": K, "y": E, "series": "quartier_cod", "measures": []},
    "bulles": {"type": "bulles", "x": K, "y": E, "size": D, "measures": []},
    "boites": {"type": "boites", "x": "engin_cod", "y": K, "measures": []},
    "violons": {"type": "violons", "x": "quartier_cod", "y": K, "series": "engin_cod", "measures": []},
    "histogramme": {"type": "histogramme", "x": D, "series": "quartier_cod", "measures": []},
    "facettes": {"type": "barres", "x": "engin_cod", "facet": "quartier_cod", "facet_cols": 2,
                 "measures": [{"agg": "somme", "column": K}], "y_scale": "log"},
    "nuage3d": {"type": "nuage3d", "x": K, "y": E, "z": D, "measures": []},
}


@pytest.fixture
def did(client):
    return upload(client, "logbook_2023.csv")["id"]


@pytest.mark.parametrize("name", list(SPECS))
def test_script_par_type(client, did, name, tmp_path):
    spec = {**SPECS[name], "filters": [], "template": TPL}
    r = client.post(f"/api/datasets/{did}/charts/r", json={"name": name, "spec": spec})
    assert r.status_code == 200, r.text
    script = r.json()["script"]
    assert "read.csv2(\"graphique_donnees.csv\"" in script
    if name != "nuage3d":
        assert "library(ggplot2)" in script and "ggsave(\"graphique.png\"" in script
    if name == "combine":
        assert "sec_axis(~ . / coef" in script and "un seul axe secondaire" in script
        assert "geom_col(data = barres" in script and "linetype = \"dashed\"" in script
    if name == "lignes":
        assert "as.Date(" in script and "geom_hline(yintercept = 5000" in script
    if name == "pourcent":
        assert "position_fill()" in script and "labels = percent" in script
    if name == "facettes":
        assert "facet_wrap(vars(`quartier_cod`), ncol = 2, scales = \"free_y\")" in script and "scale_y_log10" in script
    z = client.post(f"/api/datasets/{did}/charts/r.zip", json={"name": name, "spec": spec})
    assert z.status_code == 200
    zf = zipfile.ZipFile(io.BytesIO(z.content))
    assert set(zf.namelist()) == {"graphique.R", "graphique_donnees.csv", "LISEZMOI.txt"}
    csv_text = zf.read("graphique_donnees.csv").decode("utf-8-sig")
    head = csv_text.splitlines()[0]
    if name in ("barres", "barres_h", "facettes"):
        assert "somme_debarquement_kg" in head
    if not shutil.which("Rscript") or name == "nuage3d":
        return
    zf.extractall(tmp_path)
    run = subprocess.run(["Rscript", "graphique.R"], cwd=tmp_path, capture_output=True, text=True, timeout=180)
    assert run.returncode == 0, run.stderr[-3000:]
    png = tmp_path / "graphique.png"
    assert png.exists() and png.stat().st_size > 5000


def test_csv_identique_aux_donnees_du_graphique(client, did):
    """Le CSV exporté contient exactement les valeurs que l'appli affiche (même requête)."""
    spec = {**SPECS["barres"], "filters": [{"column": "quartier_cod", "op": "in", "values": ["BR"]}], "template": TPL}
    shown = client.post(f"/api/datasets/{did}/chart-data", json={
        "x": "engin_cod", "series": "quartier_cod", "measures": [{"agg": "somme", "column": K}],
        "filters": spec["filters"]}).json()
    z = client.post(f"/api/datasets/{did}/charts/r.zip", json={"name": "g", "spec": spec})
    lines = zipfile.ZipFile(io.BytesIO(z.content)).read("graphique_donnees.csv").decode("utf-8-sig").splitlines()
    assert len(lines) - 1 == len(shown["rows"])
    assert all(";BR;" in ln for ln in lines[1:])
