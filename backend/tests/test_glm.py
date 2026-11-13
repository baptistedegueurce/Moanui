"""GLM guidés : choix de la famille, surdispersion, offset, indice standardisé, blocages."""

import numpy as np


def _csv(client, name, rows, header):
    text = header + "\n" + "\n".join(",".join(str(v) for v in r) for r in rows) + "\n"
    r = client.post("/api/datasets/import", files={"file": (name, text.encode(), "text/csv")})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def _run(client, did, **body):
    r = client.post(f"/api/datasets/{did}/stats", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def _data():
    rng = np.random.default_rng(3)
    rows = []
    for i in range(600):
        annee = f"A{2019 + i % 5}"
        engin = ["OTB", "GNS", "FPO"][i % 3]
        jours = round(float(rng.uniform(1, 6)), 2)
        mu = jours * 4 * {"OTB": 2.0, "GNS": 1.0, "FPO": 0.5}[engin] * (1.3 if annee == "A2023" else 1.0)
        n = int(rng.negative_binomial(1.5, 1.5 / (1.5 + mu)))
        kg = round(float(rng.gamma(2, mu / 2)) + 0.01, 2)
        rows.append([annee, engin, jours, n, kg, int(n > 0), round(kg if n else 0, 2)])
    return rows


def test_glm_family_choice_offset_and_index(client):
    did = _csv(client, "cpue.csv", _data(), "annee,engin,jours_mer,nombre,kg,presence,kg0")
    v = {"y": "nombre", "x": ["engin", "annee"], "effort": "jours_mer"}
    res = _run(client, did, analyse="glm", variables=v)
    assert res["test"] == "binomiale_negative" and not res["bloque"]  # Poisson surdispersé → binomiale négative
    assert any(c["nom"] == "Surdispersion" and "binomial négatif" in c["message"] for c in res["checks"])
    titles = [t["titre"] for t in res["tableaux"]]
    assert any(t.startswith("Valeurs prédites par « engin »") for t in titles)
    coef = next(t for t in res["tableaux"] if t["titre"] == "Coefficients")
    otb = next(r for r in coef["lignes"] if r[0].startswith("engin = OTB"))
    assert "vs FPO" in otb[0]  # effectifs égaux : 1re modalité (FPO) en référence ; vrai rapport OTB / FPO = 4
    assert 3 < float(otb[2].replace(",", ".").replace("\u202f", "").replace(" ", "")) < 5.5
    assert any("offset" in s for s in res["interpretation"])
    # Poisson imposé : bloqué, alternative proposée
    po = _run(client, did, analyse="glm", test="poisson", variables=v)
    assert po["bloque"] and po["alternative"] == "binomiale_negative"
    # Gamma automatique sur des valeurs positives
    ga = _run(client, did, analyse="glm", variables={"y": "kg", "x": ["engin"]})
    assert ga["test"] == "gamma"
    # présence / absence → logistique
    lo = _run(client, did, analyse="glm", variables={"y": "presence", "x": ["engin", "jours_mer"]})
    assert lo["test"] == "logistique" and any(t["titre"].startswith("Valeurs prédites") for t in lo["tableaux"])
    # zéros + décimales : bloqué avec conseil « delta »
    z = _run(client, did, analyse="glm", variables={"y": "kg0", "x": ["engin"]})
    assert z["bloque"] and any("delta" in c["message"] for c in z["checks"])
    md = client.post(f"/api/datasets/{did}/stats/method.md", json={"analyse": "glm", "variables": v})
    assert md.status_code == 200 and "binomial négatif" in md.text


def test_glm_integer_weights_use_gamma(client):
    from conftest import upload

    did = upload(client, "logbook_2023.csv")["id"]
    res = _run(client, did, analyse="glm", variables={"y": "debarquement_Kg", "x": ["engin_cod"], "effort": "duree_maree"})
    assert res["test"] == "gamma" and "quantités" in res["checks"][1]["message"]
    nb = _run(client, did, analyse="glm", test="binomiale_negative",
              variables={"y": "debarquement_Kg", "x": ["engin_cod"], "effort": "duree_maree"})
    assert nb["test"] == "binomiale_negative" and not nb["bloque"]
