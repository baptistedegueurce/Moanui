"""Données de démonstration Moanui : flottille bretonne FICTIVE (navires, captures, VMS, couches SIG).

    cd backend && uv run python ../outils/generer_donnees_demo.py        -> écrit exemples/donnees_demo/

Tout est inventé (graine fixe, résultat identique à chaque exécution) : navires « MOANUI 01… », patrons et
téléphones manifestement faux, zones « fictives ». Les ordres de grandeur (captures, prix, vitesses, saisons)
sont plausibles pour la petite pêche et la pêche côtière du sud Finistère / Morbihan, sans prétendre décrire la
réalité. Codes de ports et sous-divisions CIEM indicatifs.

Anomalies volontaires (pour éprouver les contrôles) : voir exemples/donnees_demo/LISEZMOI.md.
"""
from __future__ import annotations

import csv
import io
import json
import math
import random
import zipfile
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "exemples" / "donnees_demo"
REF = ROOT / "backend" / "moanui" / "referentiels"
R = random.Random(2026)

# ------------------------------------------------------------------ référentiels fictifs (codes indicatifs)
PORTS = [  # code, nom, département, quartier, lat, lon, point de sortie en mer
    ("FRBES", "Brest", "29", "BR", 48.380, -4.490, [(48.350, -4.620), (48.300, -4.800)]),
    ("FRDOU", "Douarnenez", "29", "DZ", 48.100, -4.330, [(48.150, -4.450)]),
    ("FRAUD", "Audierne", "29", "AD", 48.010, -4.540, [(47.980, -4.600)]),
    ("FRGVC", "Le Guilvinec", "29", "GV", 47.790, -4.280, [(47.720, -4.300)]),
    ("FRCOC", "Concarneau", "29", "CC", 47.870, -3.920, [(47.780, -3.950)]),
    ("FRLRT", "Lorient", "56", "LO", 47.730, -3.370, [(47.680, -3.350), (47.600, -3.300)]),
]
PORT = {p[0]: p for p in PORTS}

# lieux de pêche : rectangle CIEM, centre, demi-largeur (degrés), sous-division indicative
GROUNDS = {
    "25E4": (48.25, -5.40, 0.12, "27.7.h"),
    "25E5": (48.16, -4.42, 0.03, "27.7.e"),   # baie de Douarnenez (dragueurs, fileyeurs)
    "24E4": (47.70, -5.30, 0.12, "27.8.a"),
    "24E5": (47.70, -4.60, 0.10, "27.8.a"),
    "23E5": (47.25, -4.50, 0.12, "27.8.a"),
    "24E6": (47.62, -3.85, 0.08, "27.8.a"),
    "23E6": (47.25, -3.60, 0.12, "27.8.a"),
}

SPECIES = {  # code FAO : nom, prix moyen €/kg
    "HKE": ("Merlu européen", 4.6), "NEP": ("Langoustine", 13.5), "ANF": ("Baudroie commune", 8.2),
    "MEG": ("Cardine franche", 4.1), "LEZ": ("Cardines nca", 3.9), "WHG": ("Merlan", 2.4),
    "SQR": ("Calmar commun", 9.5), "CTC": ("Seiche commune", 3.6), "SOL": ("Sole commune", 15.0),
    "RJC": ("Raie bouclée", 2.6), "JOD": ("Saint-Pierre", 12.5), "POL": ("Lieu jaune", 8.8),
    "BSS": ("Bar européen", 15.5), "CRE": ("Tourteau", 3.2), "LBE": ("Homard européen", 24.0),
    "SCR": ("Araignée de mer", 3.8), "WHE": ("Buccin", 2.3), "MAC": ("Maquereau commun", 1.6),
    "SCE": ("Coquille Saint-Jacques", 4.4),
}
GROUPE = {"HKE": "Démersal", "NEP": "Crustacé", "ANF": "Démersal", "MEG": "Démersal", "LEZ": "Démersal",
          "WHG": "Démersal", "SQR": "Céphalopode", "CTC": "Céphalopode", "SOL": "Démersal", "RJC": "Démersal",
          "JOD": "Démersal", "POL": "Démersal", "BSS": "Démersal", "CRE": "Crustacé", "LBE": "Crustacé",
          "SCR": "Crustacé", "WHE": "Coquillage", "MAC": "Pélagique", "SCE": "Coquillage"}

# captures moyennes (kg par jour de mer) par engin et espèce, probabilité de présence dans la marée
CATCH = {
    "OTB": {"HKE": (150, .9), "NEP": (55, .6), "ANF": (70, .7), "MEG": (45, .6), "LEZ": (35, .4), "WHG": (55, .6),
            "SQR": (30, .35), "CTC": (45, .4), "SOL": (12, .5), "RJC": (25, .5), "JOD": (8, .4)},
    "GNS": {"HKE": (120, .9), "ANF": (55, .6), "POL": (35, .5), "BSS": (15, .3), "RJC": (20, .3)},
    "GTR": {"SOL": (22, .95), "ANF": (35, .5), "RJC": (25, .4), "SCR": (45, .5)},
    "FPO": {"CRE": (75, .9), "LBE": (10, .8), "SCR": (55, .6), "WHE": (140, .3)},
    "LHP": {"BSS": (25, .9), "POL": (28, .7), "MAC": (55, .5)},
    "LLS": {"HKE": (55, .5), "BSS": (28, .7), "POL": (25, .7)},
    "DRB": {"SCE": (380, 1.0)},
}
SEASON = {  # coefficient mensuel (1 = moyenne)
    "SQR": [1.3, .8, .5, .3, .3, .4, .6, .9, 1.4, 1.9, 1.8, 1.6], "CTC": [.6, .9, 1.8, 2.0, 1.6, .9, .5, .4, .4, .6, .8, .7],
    "BSS": [1.6, 1.5, 1.1, .8, .7, .7, .8, .9, 1.0, 1.1, 1.3, 1.5], "MAC": [.3, .3, .6, 1.2, 1.8, 1.9, 1.6, 1.2, .9, .6, .4, .3],
    "LBE": [.2, .2, .4, .9, 1.4, 1.7, 1.8, 1.6, 1.2, .8, .4, .2], "CRE": [.6, .6, .8, 1.0, 1.1, 1.2, 1.3, 1.3, 1.2, 1.1, .9, .7],
    "NEP": [.6, .7, .9, 1.2, 1.4, 1.4, 1.3, 1.2, 1.0, .9, .7, .6],
}
YEAR = {2024: {}, 2025: {"HKE": 1.10, "SOL": 0.85, "NEP": 0.92}}

FLEETS = [  # flottille, engins, longueur (min, max), puissance kW (min, max), ports, lieux, sorties/an, jours/marée
    ("Chalutiers de fond 12-24 m", ["OTB"], (14, 22), (220, 450), ["FRGVC", "FRCOC", "FRLRT"],
     ["24E5", "24E6", "23E6", "23E5"], 175, [1, 1, 1, 1, 2]),
    ("Fileyeurs 10-16 m", ["GNS", "GTR"], (10, 16), (110, 300), ["FRAUD", "FRGVC", "FRDOU"],
     ["24E5", "24E4", "25E4", "25E5"], 170, [1, 1, 1, 2]),
    ("Caseyeurs côtiers", ["FPO"], (8, 11.5), (60, 150), ["FRAUD", "FRDOU", "FRCOC"], ["24E5", "25E5"], 150, [1]),
    ("Ligneurs côtiers", ["LHP", "LLS"], (7, 10.5), (40, 110), ["FRAUD", "FRLRT"], ["24E5", "24E6"], 140, [1]),
    ("Dragueurs à coquille", ["DRB"], (10, 12.5), (120, 220), ["FRDOU"], ["25E5"], 60, [1]),
]
FLEET_SIZE = [10, 9, 8, 6, 3]

FIRST = ["Yann", "Erwan", "Gwenaël", "Loïc", "Marie", "Nolwenn", "Pierre", "Ronan", "Soizic", "Tanguy", "Hervé",
         "Anne", "Jean-Luc", "Maël", "Klervi", "Corentin", "Gaëlle", "Youenn"]


def coherent() -> dict:
    d = json.loads((REF / "engins_coherents.json").read_text(encoding="utf-8"))["especes"]
    return {k: set(v.get("coherents") or []) for k, v in d.items()}


def fr(x: float, nd: int = 2) -> str:
    return f"{x:.{nd}f}".replace(".", ",")


# ------------------------------------------------------------------ flotte
def make_fleet() -> list[dict]:
    vessels, n = [], 0
    for (fleet, gears, lng, kw, ports, grounds, trips, durees), size in zip(FLEETS, FLEET_SIZE):
        for _ in range(size):
            n += 1
            L = round(R.uniform(*lng), 1)
            port = R.choice(ports)
            v = {
                "navire_cod": f"FRA999{n:06d}", "nom_navire": f"MOANUI {n:02d}", "flottille": fleet,
                "quartier_cod": PORT[port][3], "port_attache": port, "longueur_m": L,
                "puissance_kw": int(R.uniform(*kw) * (0.8 + 0.3 * (L - lng[0]) / max(1, lng[1] - lng[0]))),
                "annee_construction": R.randint(1982, 2021), "jauge_ums": round(L ** 2.4 / 18, 1),
                "patron": f"{R.choice(FIRST)} FICTIF-{n:02d}", "telephone": f"06 00 00 00 {n:02d}",
                "licence_cod": f"{R.randint(1, 400):05d}",
                "gears": gears, "grounds": [g for g in grounds if R.random() < .75] or grounds[:1],
                "trips": trips * R.uniform(.8, 1.15), "durees": durees, "skill": math.exp(R.gauss(0, .25)),
            }
            v["vms"] = L >= 12
            vessels.append(v)
    vms = [v for v in vessels if v["vms"]]
    for i, v in enumerate(vms):
        v["vms_fournisseur"] = "Agiltech" if i % 2 == 0 else "CLS"
    vms[-1]["vms_fournisseur"] = "aucun (balise en panne)"  # captures sans positions : repli / non attribué
    return vessels


# ------------------------------------------------------------------ marées et captures
def trips_for(v: dict, year: int) -> list[dict]:
    out, d = [], date(year, 1, 1)
    p_day = v["trips"] / 250
    busy_until = d
    k = 0
    while d.year == year:
        m = d.month
        ok = d >= busy_until
        if v["gears"] == ["DRB"] and not (m >= 11 or m <= 3):
            ok = False  # coquille : saison novembre-mars
        wd = d.weekday()
        p = p_day * (1.0 if wd < 4 else .5 if wd == 4 else .25 if wd == 5 else .03)
        p *= [.55, .6, .8, 1, 1.1, 1.15, 1.15, 1.1, 1, .9, .7, .55][m - 1]  # météo
        if ok and R.random() < p:
            k += 1
            duree = R.choice(v["durees"])
            gear = R.choice(v["gears"])
            rects = [R.choice(v["grounds"])]
            if gear in ("OTB", "GNS") and R.random() < .15 and len(v["grounds"]) > 1:
                rects.append(R.choice([g for g in v["grounds"] if g != rects[0]]))
            out.append({"num_maree": f"{year}{v['navire_cod'][-3:]}{k:04d}", "v": v, "date_deb": d,
                        "date_ret": d + timedelta(days=duree - 1), "duree": duree, "gear": gear, "rects": rects})
            busy_until = d + timedelta(days=duree)
        d += timedelta(days=1)
    return out


def catch_lines(t: dict, coh: dict, year: int) -> list[dict]:
    v, gear = t["v"], t["gear"]
    lines = []
    for sp, (mean, prob) in CATCH[gear].items():
        if sp in coh and gear not in coh[sp]:
            continue  # ne produire que des lignes cohérentes (les incohérences sont ajoutées à part)
        if R.random() > prob:
            continue
        m = t["date_deb"].month
        mu = (mean * t["duree"] * (v["puissance_kw"] / 200) ** 0.35 * v["skill"] * SEASON.get(sp, [1] * 12)[m - 1]
              * YEAR[year].get(sp, 1.0))
        kg = R.gammavariate(2.0, mu / 2.0)
        shares = [1.0] if len(t["rects"]) == 1 else [R.uniform(.4, .75)]
        if len(t["rects"]) == 2:
            shares.append(1 - shares[0])
        for rect, sh in zip(t["rects"], shares):
            q = round(kg * sh, 1)
            if q < 0.5:
                continue
            price = SPECIES[sp][1] * math.exp(R.gauss(0, .12)) * (1.15 if m in (12, 1) else 1.0)
            lines.append({"t": t, "sp": sp, "rect": rect, "kg": q, "eur": round(q * price, 2)})
    return lines


SAC_COLS = ["num_maree", "navire_cod", "quartier_cod", "port_cod", "date_deb", "date_ret", "duree_maree",
            "engin_cod", "maillage", "esp_cod_fao", "stat_rect", "div_ciem_cod_sipa", "debarquement_Kg",
            "debarquement_euros"]
MESH = {"OTB": "80", "GNS": "100", "GTR": "250", "FPO": "", "LHP": "", "LLS": "", "DRB": "92"}


def sacrois_rows(lines: list[dict]) -> list[list[str]]:
    rows = []
    for ln in lines:
        t, v = ln["t"], ln["t"]["v"]
        rows.append([t["num_maree"], v["navire_cod"], v["quartier_cod"], v["port_attache"],
                     t["date_deb"].strftime("%d/%m/%Y"), t["date_ret"].strftime("%d/%m/%Y"), str(t["duree"]),
                     ln.get("gear_decl", t["gear"]), MESH[t["gear"]], ln["sp"], ln["rect"], GROUNDS[ln["rect"]][3],
                     fr(ln["kg"], 1), fr(ln["eur"], 2)])
    return rows


def inject_anomalies(rows: list[list[str]], year: int, vessels: list[dict]) -> dict:
    """Erreurs typiques d'un export : codes mal saisis, vides, doublons, engins incohérents."""
    info = {}
    idx = R.sample(range(len(rows)), 60)
    for i in idx[:25]:  # codes espèce en minuscules / avec espaces
        rows[i][9] = R.choice([rows[i][9].lower(), " " + rows[i][9], rows[i][9] + " "])
    for i in idx[25:35]:  # engin non renseigné
        rows[i][7] = ""
    for i in idx[35:42]:  # montant manquant
        rows[i][13] = ""
    for i in idx[42:45]:  # poids nul mais vendu (erreur de saisie)
        rows[i][12] = "0,0"
    info["doublons"] = 4
    for i in R.sample(range(len(rows)), 4):  # lignes en double (export répété)
        rows.append(list(rows[i]))
    # engins incohérents avec l'espèce (codes inversés, engin de la marée précédente…)
    bad = [("SOL", "FPO"), ("NEP", "LHP"), ("ANF", "DRB"), ("SCE", "OTB"), ("BSS", "FPO")]
    inc = []
    for sp, gear in bad:
        cand = [r for r in rows if r[9] == sp]
        for r in R.sample(cand, min(len(cand), 3)):
            inc.append((r[1], sp, gear, r[7]))
            r[7] = gear
    info["incoherences"] = inc
    return info


# ------------------------------------------------------------------ VMS (positions simulées)
def _move(lat, lon, head, nm):
    return (lat + nm * math.cos(head) / 60.0, lon + nm * math.sin(head) / (60.0 * math.cos(math.radians(lat))))


def _head(lat, lon, lat2, lon2):
    return math.atan2((lon2 - lon) * math.cos(math.radians(lat)), lat2 - lat)


def _dist_nm(lat, lon, lat2, lon2):
    return math.hypot((lat2 - lat) * 60, (lon2 - lon) * 60 * math.cos(math.radians(lat)))


def _bounds(rect):
    from_row = int(rect[:2])
    lat0 = 36.0 + (from_row - 1) * 0.5
    col = rect[2:]
    lon0 = {"E": -10, "F": 0}[col[0]] + int(col[1]) * 1.0 if col[0] in "EF" else None
    return lat0, lat0 + 0.5, lon0, lon0 + 1.0


def track(t: dict, step_min: float) -> list[tuple[datetime, float, float, float]]:
    v = t["v"]
    p = PORT[v["port_attache"]]
    lat, lon = p[4], p[5]
    now = datetime.combine(t["date_deb"], datetime.min.time()) + timedelta(hours=4, minutes=R.randint(15, 100))
    end = datetime.combine(t["date_ret"], datetime.min.time()) + timedelta(hours=R.uniform(17, 20.5))
    pts = []
    dt = lambda: step_min * R.uniform(.85, 1.15)  # noqa: E731

    def emit(spd):
        pts.append((now, lat, lon, max(0.0, spd + R.gauss(0, .25))))

    for _ in range(2):  # à quai
        emit(0)
        now += timedelta(minutes=dt())

    def steam(path, until=None):
        nonlocal lat, lon, now
        for (tl, tn) in path:
            while _dist_nm(lat, lon, tl, tn) > 0.3:
                spd = R.uniform(8.5, 10.5)
                m = dt()
                step = min(spd * m / 60, _dist_nm(lat, lon, tl, tn))
                lat, lon = _move(lat, lon, _head(lat, lon, tl, tn), step)
                now += timedelta(minutes=m)
                emit(spd)

    exits = p[6]
    fish_speed = {"OTB": (2.8, 3.8), "GNS": (0.8, 2.6), "GTR": (0.8, 2.4), "DRB": (2.2, 3.2)}.get(t["gear"], (0.5, 2.5))
    back_at = end - timedelta(hours=2.2)
    for j, rect in enumerate(t["rects"]):
        c_lat, c_lon, hw, _ = GROUNDS[rect]
        b = _bounds(rect)
        tgt = (c_lat + R.uniform(-hw, hw) * .5, c_lon + R.uniform(-hw, hw) * .5)
        steam(exits + [tgt] if j == 0 else [tgt])
        stop = back_at if j == len(t["rects"]) - 1 else now + (back_at - now) * R.uniform(.4, .6)
        head = R.uniform(0, 2 * math.pi)
        while now < stop:
            m = dt()
            if R.random() < 0.08:  # virage / filage / relevage
                spd = R.uniform(0.2, 1.2)
            else:
                spd = R.uniform(*fish_speed)
            head += R.gauss(0, .35)
            nl, nn = _move(lat, lon, head, spd * m / 60)
            lo_lat, hi_lat = max(b[0] + .01, c_lat - hw), min(b[1] - .01, c_lat + hw)
            lo_lon, hi_lon = max(b[2] + .01, c_lon - hw), min(b[3] - .01, c_lon + hw)
            if not (lo_lat <= nl <= hi_lat and lo_lon <= nn <= hi_lon):
                head = _head(lat, lon, c_lat, c_lon) + R.gauss(0, .3)
                nl, nn = _move(lat, lon, head, spd * m / 60)
            lat, lon = nl, nn
            now += timedelta(minutes=m)
            emit(spd)
    steam(list(reversed(exits)) + [(p[4], p[5])])
    for _ in range(2):
        now += timedelta(minutes=dt())
        emit(0)
    return pts


def vms_files(trips: list[dict]) -> tuple[list, list]:
    agil, cls = [], []
    sel = [t for t in trips if t["v"]["vms"] and t["date_deb"].year == 2025
          and t["v"]["vms_fournisseur"] in ("Agiltech", "CLS")]
    for t in sorted(sel, key=lambda t: (t["v"]["navire_cod"], t["date_deb"])):
        v = t["v"]
        if v["vms_fournisseur"] == "Agiltech":
            for (ts, la, lo, sp) in track(t, 15):
                agil.append([f"{la:.4f}", f"{lo:.4f}", f"{sp:.1f}", ts.strftime("%d/%m/%Y %H:%M"), v["navire_cod"]])
        else:
            for (ts, la, lo, sp) in track(t, 60):
                cls.append([f"{la:.4f}", f"{lo:.4f}", str(int(round(sp * 10))), ts.strftime("%Y-%m-%d %H:%M:%S"),
                            v["navire_cod"]])
    # anomalies : sauts GPS impossibles, positions en double, vitesse manquante
    for rows in (agil, cls):
        for i in R.sample(range(10, len(rows) - 10), 3):
            rows[i][0] = f"{float(rows[i][0]) + R.choice([-1.8, 2.1]):.4f}"
        for i in R.sample(range(len(rows)), 5):
            rows.insert(i + 1, list(rows[i]))
        for i in R.sample(range(len(rows)), 4):
            rows[i][2] = ""
    return agil, cls


# ------------------------------------------------------------------ campagne de suivi (statistiques sur comptages)
def suivi_casiers() -> list[list]:
    rows = []
    zones = {"Chaussée de Sein": 1.0, "Glénan": 1.35, "Baie d'Audierne": 0.8, "Iroise": 1.15}
    k = 0
    for annee in (2023, 2024, 2025):
        for mois in (5, 6, 7, 8, 9):
            for zone, fz in zones.items():
                for _ in range(R.randint(5, 8)):
                    k += 1
                    prof = round(R.uniform(8, 45), 1)
                    nb_casiers = R.choice([20, 25, 30, 40, 50])
                    immersion = R.choice([24, 24, 48, 72])
                    mu = nb_casiers * 0.11 * fz * (1 + 0.25 * (annee - 2023)) * math.exp(-((prof - 25) / 22) ** 2) \
                        * SEASON["LBE"][mois - 1] * (immersion / 24) ** 0.3
                    # binomiale négative (agrégation des homards) : gamma-Poisson
                    lam = R.gammavariate(1.6, mu / 1.6)
                    n = _poisson(lam)
                    sous_taille = _poisson(n * 0.6 + 0.3)
                    rows.append([f"S{k:04d}", annee, mois, zone, fr(prof, 1), nb_casiers, immersion, n, sous_taille,
                                 "oui" if R.random() < .3 else "non"])
    return rows


def _poisson(lam: float) -> int:
    if lam <= 0:
        return 0
    if lam > 60:
        return max(0, int(round(R.gauss(lam, math.sqrt(lam)))))
    L, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= R.random()
        if p <= L:
            return k
        k += 1


# ------------------------------------------------------------------ couches SIG fictives
def poly(coords):
    ring = coords + [coords[0]]
    return {"type": "Polygon", "coordinates": [[[lon, lat] for lat, lon in ring]]}


def write_layers():
    eol = {"type": "FeatureCollection", "name": "zone_eolienne_fictive", "features": [
        {"type": "Feature", "properties": {"nom": "Zone d'étude éolienne FICTIVE - Sud Glénan", "statut": "projet fictif",
                                           "surface_km2": 0},
         "geometry": poly([(47.66, -3.95), (47.66, -3.74), (47.55, -3.70), (47.53, -3.88)])},
        {"type": "Feature", "properties": {"nom": "Zone de raccordement FICTIVE", "statut": "projet fictif",
                                           "surface_km2": 0},
         "geometry": poly([(47.74, -3.83), (47.74, -3.80), (47.66, -3.80), (47.66, -3.83)])}]}
    for f in eol["features"]:
        ring = f["geometry"]["coordinates"][0]
        a = 0.5 * abs(sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(ring, ring[1:])))
        f["properties"]["surface_km2"] = round(a * 111.32 * 111.32 * math.cos(math.radians(47.6)), 1)
    (OUT / "zone_eolienne_fictive.geojson").write_text(json.dumps(eol, ensure_ascii=False, indent=1), encoding="utf-8")

    gis = [("Gisement FICTIF de Morgat", 2.8, [(48.20, -4.47), (48.20, -4.43), (48.16, -4.42), (48.16, -4.47)]),
           ("Gisement FICTIF de Douarnenez", 1.6, [(48.165, -4.40), (48.165, -4.36), (48.14, -4.36), (48.14, -4.40)])]
    pm = []
    for nom, dens, ring in gis:
        c = " ".join(f"{lon},{lat},0" for lat, lon in ring + [ring[0]])
        pm.append(f"""  <Placemark><name>{nom}</name>
   <ExtendedData><Data name="densite_kg_m2"><value>{dens}</value></Data><Data name="campagne"><value>2025</value></Data></ExtendedData>
   <Polygon><outerBoundaryIs><LinearRing><coordinates>{c}</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark>""")
    (OUT / "gisements_coquille_fictifs.kml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<kml xmlns="http://www.opengis.net/kml/2.2"><Document>\n'
        + "\n".join(pm) + "\n</Document></kml>\n", encoding="utf-8")

    # shapefile en Lambert-93 et GeoPackage : écrits par l'extension spatiale DuckDB (comme l'application)
    import duckdb
    import sys
    sys.path.insert(0, str(ROOT / "backend"))
    from moanui.engine import geo
    con = duckdb.connect()
    geo.load_spatial(con)
    tmp = OUT / "_shp"
    tmp.mkdir(exist_ok=True)
    cant = [("Cantonnement langoustine FICTIF A", "2025-01-01", (47.58, -3.98, 47.64, -3.90)),
            ("Cantonnement langoustine FICTIF B", "2025-04-01", (47.26, -3.70, 47.32, -3.58)),
            ("Réserve de pêche FICTIVE", "2024-06-15", (47.68, -4.72, 47.73, -4.64))]
    vals = ", ".join(f"('{n}', DATE '{d}', ST_Transform(ST_MakeEnvelope({b[1]}, {b[0]}, {b[3]}, {b[2]}), "
                     f"'EPSG:4326', 'EPSG:2154'))" for n, d, b in cant)
    con.execute(f"COPY (SELECT * FROM (VALUES {vals}) t(nom, depuis, geom)) TO '{tmp / 'cantonnements_fictifs.shp'}' "
                "(FORMAT GDAL, DRIVER 'ESRI Shapefile', SRS 'EPSG:2154')")
    with zipfile.ZipFile(OUT / "cantonnements_fictifs_L93.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(tmp.iterdir()):
            z.write(f, f"cantonnements_fictifs/{f.name}")
    for f in tmp.iterdir():
        f.unlink()
    tmp.rmdir()
    gp = OUT / "ports_fictifs.gpkg"
    if gp.exists():
        gp.unlink()
    pv = ", ".join(f"('{c}', '{n}', '{q}', ST_Point({lo}, {la}))" for c, n, _, q, la, lo, _ in PORTS)
    con.execute(f"COPY (SELECT * FROM (VALUES {pv}) t(port_cod, nom_port, quartier_cod, geom)) TO '{gp}' "
                "(FORMAT GDAL, DRIVER 'GPKG', SRS 'EPSG:4326')")


# ------------------------------------------------------------------ écriture
def write_csv(path: Path, header, rows, sep=";", encoding="utf-8-sig"):
    with open(path, "w", newline="", encoding=encoding) as f:
        w = csv.writer(f, delimiter=sep, lineterminator="\r\n")
        w.writerow(header)
        w.writerows(rows)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    coh = coherent()
    vessels = make_fleet()

    # navires (Excel)
    from openpyxl import Workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "Flotte"
    cols = ["navire_cod", "nom_navire", "flottille", "quartier_cod", "port_attache", "longueur_m", "puissance_kw",
            "jauge_ums", "annee_construction", "vms_fournisseur", "licence_cod", "patron", "telephone"]
    ws.append(cols)
    for v in vessels:
        ws.append([v.get(c, "") if c != "vms_fournisseur" else v.get(c, "sans VMS (< 12 m)") for c in cols])
    for col in ws.columns:
        ws.column_dimensions[col[0].column_letter].width = max(12, max(len(str(c.value or "")) for c in col) + 2)
    wb.save(OUT / "flotte_navires.xlsx")

    write_csv(OUT / "ref_ports.csv", ["port_cod", "nom_port", "departement", "quartier_cod", "lat", "lon"],
              [[c, n, d, q, fr(la, 4), fr(lo, 4)] for c, n, d, q, la, lo, _ in PORTS])
    write_csv(OUT / "ref_especes.csv", ["esp_cod_fao", "nom_commun", "groupe", "prix_reference_eur_kg"],
              [[k, n, GROUPE[k], fr(p)] for k, (n, p) in SPECIES.items()] + [["XXX", "Espèce inconnue (test)", "", ""]])

    stats = {}
    all_trips = []
    for year in (2024, 2025):
        trips = [t for v in vessels for t in trips_for(v, year)]
        all_trips += trips
        lines = [ln for t in trips for ln in catch_lines(t, coh, year)]
        lines.sort(key=lambda ln: (ln["t"]["date_deb"], ln["t"]["num_maree"], ln["sp"]))
        rows = sacrois_rows(lines)
        info = inject_anomalies(rows, year, vessels)
        stats[year] = {"lignes": len(rows), "marees": len(trips), **info}
        if year == 2024:  # export Excel / logiciel ancien : Windows-1252, sans BOM
            write_csv(OUT / "sacrois_2024.csv", SAC_COLS, rows, encoding="cp1252")
        else:
            write_csv(OUT / "sacrois_2025.csv", SAC_COLS, rows)
            corr = []
            seen = set()
            for (vessel, sp, gear, original) in info["incoherences"]:
                if (vessel, sp, gear) in seen:
                    continue
                seen.add((vessel, sp, gear))
                fixed = "" if sp == "BSS" else original  # bar : laissé à l'utilisateur
                corr.append([vessel, sp, gear, fixed, ""])
            write_csv(OUT / "corrections_engins.csv", ["navire", "espece", "engin_declare", "engin_corrige", "lignes"],
                      corr)

    # 2023 : même format mais poids saisis en tonnes (erreur d'unité à détecter à l'empilement)
    trips23 = [t for v in vessels[:12] for t in trips_for(v, 2023)]
    lines23 = [ln for t in trips23 for ln in catch_lines(t, coh, 2024)]
    rows23 = sacrois_rows(lines23)
    for r in rows23:
        r[12] = fr(float(r[12].replace(",", ".")) / 1000, 4)
    write_csv(OUT / "sacrois_2023_extrait_tonnes.csv", SAC_COLS, rows23)

    agil, cls = vms_files(all_trips)
    write_csv(OUT / "vms_agiltech_2025.csv", ["Latitude", "Longitude", "Vitesse", "date", "navire"], agil,
              sep=",", encoding="utf-8")
    write_csv(OUT / "vms_cls_2025.csv", ["LT", "LG", "SP", "col_date", "OP"], cls, sep=",", encoding="utf-8")

    write_csv(OUT / "suivi_casiers_homard.csv",
              ["station", "annee", "mois", "zone", "profondeur_m", "nb_casiers", "immersion_h", "nb_homards",
               "nb_sous_taille", "observateur_embarque"], suivi_casiers())
    # gestion : quotas et limitations FICTIFS (valeurs choisies pour illustrer consommation, alerte et dépassements)
    write_csv(OUT / "quotas_2025_fictifs.csv", ["esp_cod_fao", "quota_kg", "annonce_kg", "debut", "fin"],
              [["SOL", "20000", "21000", "2025-01-01", "2025-12-31"], ["NEP", "70000", "", "2025-01-01", "2025-12-31"],
               ["HKE", "400000", "360000", "2025-01-01", "2025-12-31"], ["BSS", "12000", "", "2025-01-01", "2025-12-31"]])
    write_csv(OUT / "limitations_2025_fictives.csv", ["esp_cod_fao", "type", "limite_kg", "debut", "fin"],
              [["BSS", "mois", "250", "2025-01-01", "2025-12-31"], ["SCE", "maree", "600", "2025-01-01", "2025-03-31"],
               ["SCE", "maree", "600", "2025-11-01", "2025-12-31"], ["SOL", "mois", "0", "2025-02-01", "2025-02-28"],
               ["LBE", "semaine", "60", "2025-05-01", "2025-08-31"]])
    write_layers()
    stats["vms"] = {"agiltech": len(agil), "cls": len(cls)}
    print(json.dumps(stats, ensure_ascii=False, default=str, indent=1)[:3000])


if __name__ == "__main__":
    main()
