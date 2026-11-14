"""Fiches méthode : structure, figures, références, absence d'émojis."""

import io
import zipfile

from conftest import upload

EMOJI = "✅⛔⚠ℹ🔥"


def _names(content: bytes) -> set[str]:
    return set(zipfile.ZipFile(io.BytesIO(content)).namelist())


def test_dataset_fiche(client):
    did = upload(client, "logbook_2023.csv")["id"]
    client.post(f"/api/datasets/{did}/steps", json={"type": "filter", "params": {
        "keep": True, "logic": "and", "conditions": [{"column": "quartier_cod", "op": "in", "values": ["BR", "LO"]}]}})
    client.post(f"/api/datasets/{did}/steps", json={"type": "fill_null", "params": {"column": "duree_maree", "method": "mediane"}})
    md = client.get(f"/api/datasets/{did}/method.md").text
    for part in ("## 1. Données sources", "## 2. Traitements appliqués", "Méthodes employées", "Données obtenues",
                 "Reproduire le traitement", "## Références", "figures/lignes_par_etape.svg", "(Little et Rubin, 2019)"):
        assert part in md, part
    assert not any(ch in md for ch in EMOJI)
    html = client.get(f"/api/datasets/{did}/method.html").text
    assert html.startswith("<!doctype html>") and "<svg" in html and "Little R. J. A." in html
    z = client.get(f"/api/datasets/{did}/method.zip")
    assert {"figures/lignes_par_etape.svg"} <= _names(z.content)
    ex = client.get(f"/api/datasets/{did}/export", params={"fmt": "csv", "confirm_sensitive": True})
    assert any(n.endswith("_methode.html") for n in _names(ex.content))


def test_chart_and_map_fiches(client):
    did = upload(client, "logbook_2023.csv")["id"]
    spec = {"type": "barres", "x": "engin_cod", "measures": [{"agg": "somme", "column": "debarquement_Kg"}],
            "template": {"title": "Débarquements par engin", "source": "SACROIS"}}
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"></svg>'
    z = client.post(f"/api/datasets/{did}/charts/method.zip", json={"name": "g", "spec": spec, "svg": svg})
    assert z.status_code == 200 and "figures/graphique.svg" in _names(z.content)
    md = zipfile.ZipFile(io.BytesIO(z.content)).read("graphique_methode.md").decode()
    assert "Cleveland et McGill, 1984" in md
    mspec = {"basemap": "horsligne", "layers": [
        {"uid": "a", "kind": "couche", "title": "Rectangles", "visible": True, "layerId": "ctx:ciem_rectangles"},
        {"uid": "b", "kind": "agregat", "title": "Effort", "visible": True, "datasetId": did,
         "agg": {"mode": "ciem", "agg": "navires", "vessel": "nom_navire", "secret": 3}}],
        "template": {"title": "Effort 2023"}}
    m = client.post("/api/geo/maps/method.md", json={"spec": mspec})
    assert m.status_code == 200, m.text
    assert "secret statistique" in m.text and "Natural Earth" in m.text and "CIEM / ICES" in m.text
