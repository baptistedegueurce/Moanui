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


def test_tailles_effet_et_rapport_normalise():
    """Valeurs de référence des tailles d'effet, bootstrap reproductible, rapport et discussion."""
    import time

    import numpy as np
    from scipy import stats as st

    from moanui import stats

    rng = np.random.default_rng(1)
    a, b, c = rng.normal(10, 2, 300), rng.normal(11, 2, 300), rng.normal(10.2, 2, 300)
    # ε² des rangs = H / (n − 1) (Tomczak et Tomczak, 2014)
    h = st.kruskal(a, b, c).statistic
    assert abs(stats.eps2_kw(a, b, c) - h / 899) < 1e-12
    # rang-bisériale : 1 si toutes les paires sont favorables à a, −1 dans l'autre sens
    assert stats.rank_biserial(np.array([5.0, 6, 7]), np.array([1.0, 2])) == 1.0
    assert stats.rank_biserial(np.array([1.0, 2]), np.array([5.0, 6, 7])) == -1.0
    # bootstrap reproductible (graine fixe)
    assert stats.boot_groups(stats.eps2_kw, [a, b, c]) == stats.boot_groups(stats.eps2_kw, [a, b, c])
    y = np.concatenate([a, b, c])
    g = np.array(["A"] * 300 + ["B"] * 300 + ["C"] * 300)
    r = stats.finalize(stats.compare_groups(y, g, "kg", "engin", "kruskal"))
    assert r.rapport[0].startswith("H(2) = ") and "ε² = " in r.rapport[0] and "IC 95 %" in r.rapport[0]
    lo, hi = [float(x.replace(",", ".")) for x in r.rapport[0].split("IC 95 % ")[1].split("]")[0].split(" ; ")]
    assert lo <= stats.eps2_kw(a, b, c) <= hi
    assert r.resume.startswith("Comparer") and any("{{hurlbert1984" in d for d in r.discussion)
    assert "(Hurlbert, 1984" in stats.cites_text(r.discussion[-2])
    pairs = next(t for t in r.tableaux if t["titre"].startswith("Comparaisons"))
    assert pairs["colonnes"][2] == "Taille d'effet" and pairs["lignes"][0][2].startswith("r = ")
    # Spearman : IC de Bonett et Wright
    x = rng.normal(size=200)
    rs = stats.correlation(x, x + rng.normal(size=200), "x", "y", "spearman")
    assert rs.rapport[0].startswith("ρ de Spearman(198) = ") and "IC 95 %" in rs.rapport[0]
    # temps : 17 000 lignes en quelques secondes
    big_y = rng.gamma(2, 20, 17000)
    big_g = rng.choice(list("ABCDEF"), 17000)
    t0 = time.time()
    stats.finalize(stats.compare_groups(big_y, big_g, "cpue", "metier", None))
    assert time.time() - t0 < 8
