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


def test_chart_fiche_multi_axes_and_refs(client):
    did = upload(client, "logbook_2023.csv")["id"]
    spec = {"type": "combine", "x": "engin_cod", "measures": [
        {"agg": "somme", "column": "debarquement_Kg", "mark": "barres"},
        {"agg": "somme", "column": "debarquement_euros", "mark": "lignes", "axis": "y2"},
        {"agg": "moyenne", "column": "duree_maree", "mark": "points", "axis": "y3"}],
        "axes": {"y": {"suffix": "kg"}, "y3": {"title": "Durée (j)", "scale": "log"}},
        "y_title": "Débarquements", "y2_title": "Valeur (€)",
        "refs": [{"kind": "ligne_h", "value": 5000, "label": "Seuil", "axis": "y"},
                 {"kind": "zone_v", "value": "GNS", "value2": "OTB", "label": "Arts dormants"}],
        "template": {"title": "Débarquements, valeur et durée"}}
    md = client.post(f"/api/datasets/{did}/charts/method.md", json={"name": "g", "spec": spec}).text
    assert "axe droit" in md and "second axe gauche" in md and "« Durée (j) »" in md and "unité kg" in md
    assert "ligne de référence à 5000 : Seuil" in md and "zone de « GNS » à « OTB »" in md
    assert "3 axes verticaux" in md and "logarithmique" in md
    # ancien format (axe secondaire y2 + y2_title) toujours décrit
    old = {"type": "combine", "x": "engin_cod", "measures": [{"agg": "somme", "column": "debarquement_Kg"},
           {"agg": "somme", "column": "debarquement_euros", "axis": "y2", "mark": "lignes"}], "y2_title": "Valeur",
           "template": {"title": "Ancien"}}
    md = client.post(f"/api/datasets/{did}/charts/method.md", json={"name": "g", "spec": old}).text
    assert "« Valeur »" in md and "axe droit" in md
    # chart-data : le style des mesures n'est pas envoyé, mais des champs en plus ne gênent pas
    r = client.post(f"/api/datasets/{did}/chart-data", json={"x": "engin_cod", "measures": spec["measures"], "filters": []})
    assert r.status_code == 200, r.text


def test_exports_word_et_pdf(client):
    """Toutes les fiches s'exportent en Word et en PDF, figures comprises."""
    import docx

    did = upload(client, "logbook_2023.csv")["id"]
    body = {"analyse": "comparer_groupes", "variables": {"y": "debarquement_Kg", "groupe": "engin_cod"}}
    pdf = client.post(f"/api/datasets/{did}/stats/method.pdf", json=body)
    assert pdf.status_code == 200 and pdf.content[:4] == b"%PDF" and len(pdf.content) > 20000
    w = client.post(f"/api/datasets/{did}/stats/method.docx", json=body)
    assert w.status_code == 200 and w.content[:2] == b"PK"
    d = docx.Document(io.BytesIO(w.content))
    heads = [p.text for p in d.paragraphs if p.style.name.startswith("Heading")]
    assert "4. Résultats" in heads and "Références" in heads and len(d.inline_shapes) >= 1
    assert client.get(f"/api/datasets/{did}/method.pdf").content[:4] == b"%PDF"
    assert client.get(f"/api/datasets/{did}/method.docx").content[:2] == b"PK"
    spec = {"type": "barres", "x": "engin_cod", "measures": [{"agg": "somme", "column": "debarquement_Kg"}],
            "template": {"title": "Débarquements"}}
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><text x="10" y="50">Été</text></svg>'
    assert client.post(f"/api/datasets/{did}/charts/method.pdf", json={"name": "g", "spec": spec, "svg": svg}).content[:4] == b"%PDF"
    assert client.post("/api/geo/maps/method.docx", json={"spec": {"layers": [], "template": {"title": "C"}}}).content[:2] == b"PK"
    assert client.post(f"/api/datasets/{did}/stats/method.exe", json=body).status_code == 404
