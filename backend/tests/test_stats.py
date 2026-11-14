from conftest import upload


def _run(client, did, **body):
    r = client.post(f"/api/datasets/{did}/stats", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def test_compare_groups_blocks_then_alternative(client):
    did = upload(client, "logbook_2023.csv")["id"]
    res = _run(client, did, analyse="comparer_groupes", variables={"y": "debarquement_Kg", "groupe": "engin_cod"})
    assert res["test"] in ("anova", "welch_anova", "kruskal")
    assert res["checks"] and res["interpretation"]
    forced = _run(client, did, analyse="comparer_groupes", test="anova",
                  variables={"y": "debarquement_euros", "groupe": "quartier_cod"})
    if forced["bloque"]:
        assert forced["resultats"] == []  # masqué tant que non justifié
        r = client.post(f"/api/datasets/{did}/stats", json={"analyse": "comparer_groupes", "test": "anova", "force": True,
                                                            "variables": {"y": "debarquement_euros", "groupe": "quartier_cod"}})
        assert r.status_code == 400
        ok = _run(client, did, analyse="comparer_groupes", test="anova", force=True, justification="test",
                  variables={"y": "debarquement_euros", "groupe": "quartier_cod"})
        assert ok["resultats"]


def test_two_groups_filter_and_method(client):
    did = upload(client, "logbook_2023.csv")["id"]
    body = {"analyse": "comparer_groupes", "variables": {"y": "duree_maree", "groupe": "quartier_cod"},
            "filters": [{"column": "quartier_cod", "op": "in", "values": ["BR", "LO"]}]}
    res = _run(client, did, **body)
    assert set(res["effectifs"]) >= {"BR", "LO"} and res["test"] in ("t_welch", "mann_whitney")
    md = client.post(f"/api/datasets/{did}/stats/method.md", json=body)
    if not res["bloque"]:
        assert md.status_code == 200 and "Conditions d'application" in md.text and "BR" in md.text
        assert "figures/boites.svg" in md.text and "(Welch, 1947" in md.text or "(Mann et Whitney, 1947)" in md.text
        assert not any(ch in md.text for ch in "✅⛔⚠ℹ")  # pas d'émojis
        z = client.post(f"/api/datasets/{did}/stats/method.zip", json=body)
        import io
        import zipfile

        names = zipfile.ZipFile(io.BytesIO(z.content)).namelist()
        assert {"analyse_methode.md", "analyse_methode.html", "figures/boites.svg", "figures/qq.svg"} - set(names) == \
            {"figures/qq.svg"}


def test_association_correlation_regression(client):
    did = upload(client, "logbook_2023.csv")["id"]
    a = _run(client, did, analyse="association", variables={"x": "quartier_cod", "y": "engin_cod"})
    assert a["test"] in ("chi2", "fisher") and a["tableaux"]
    c = _run(client, did, analyse="correlation", variables={"x": "debarquement_Kg", "y": "debarquement_euros"})
    assert c["test"] in ("pearson", "spearman") and c["graph"]["type"] == "nuage"
    r = _run(client, did, analyse="regression", force=True, justification="essai",
             variables={"y": "debarquement_euros", "x": ["debarquement_Kg", "engin_cod"]})
    coefs = next(t for t in r["tableaux"] if t["titre"] == "Coefficients")
    assert len(coefs["lignes"]) > 2 and r["resultats"][0]["nom"] == "R²"
    saved = _run(client, did, analyse="correlation", save=True, variables={"x": "debarquement_Kg", "y": "duree_maree"})
    assert saved.get("id") and client.get(f"/api/datasets/{did}/stats").json()


def test_stat_rejects_text_measure(client):
    did = upload(client, "logbook_2023.csv")["id"]
    r = client.post(f"/api/datasets/{did}/stats", json={"analyse": "correlation", "variables": {"x": "engin_cod", "y": "debarquement_Kg"}})
    assert r.status_code == 400 and "numérique" in r.json()["detail"]
