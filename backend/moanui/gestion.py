"""Gestion des pêcheries : suivi de consommation des quotas et contrôle des limitations de captures.

Calculs faits dans DuckDB sur le résultat de la recette d'un jeu de données (jamais sur le fichier brut), à partir
d'une correspondance de colonnes : espèce, date, poids (kg), navire, marée (facultatif), quartier / engin / nom
(facultatifs, pour le détail des dépassements).

- Quota : consommation cumulée sur la période (débarquements des espèces du quota), part consommée, reste,
  consommation par mois, projection à la fin de la période (extrapolation linéaire du rythme moyen, et du rythme des
  30 derniers jours), date estimée d'atteinte, comparaison avec une consommation annoncée (ex. DGAMPA), seuils d'alerte.
- Limitations : règles par espèce (à la marée, au jour, à la semaine, au mois, au trimestre, au semestre, à l'année,
  sur une période de validité ; 0 kg = fermeture) ; une règle est dépassée quand la somme des captures d'un navire sur
  une unité de temps dépasse la limite (la limite elle-même est autorisée).
"""

from __future__ import annotations

from datetime import date, timedelta

from .engine.sql import RecipeError, ident, string_lit

PERIODS = {
    "maree": "à la marée",
    "jour": "par jour",
    "semaine": "par semaine (lundi-dimanche)",
    "mois": "par mois civil",
    "trimestre": "par trimestre civil",
    "semestre": "par semestre civil",
    "annee": "par année civile",
}

# propositions automatiques de colonnes
GUESS = {
    "espece": ("esp_cod_fao", "espece_cod", "esp_cod", "espece", "species"),
    "date": ("date_deb", "date", "date_maree", "date_debarque", "date_ret", "date_vente"),
    "poids": ("debarquement_kg", "quant_poids_vif", "poids_vif_kg", "poids_kg", "kg", "quantite_kg"),
    "navire": ("navire_cod", "navs_cod", "cfr_cod", "cfr", "navire", "immatriculation"),
    "maree": ("num_maree", "maree_id", "id_maree", "maree"),
    "nom": ("nom_navire", "navire_nom", "nom"),
    "quartier": ("quartier_cod", "quartier"),
    "engin": ("engin_sug", "engin_cod", "engin"),
}


def guess_mapping(schema: dict) -> dict:
    low = {c.lower(): c for c in schema}
    return {k: next((low[c] for c in cands if c in low), None) for k, cands in GUESS.items()}


def _day_expr(col: str, t: str) -> str:
    c = ident(col)
    if t.upper().startswith(("TIMESTAMP", "DATE")):
        return f"CAST({c} AS DATE)"
    v = f"trim(CAST({c} AS VARCHAR))"
    return (f"coalesce(TRY_CAST({v} AS DATE), CAST(try_strptime({v}, '%d/%m/%Y') AS DATE), "
            f"CAST(try_strptime({v}, '%d/%m/%Y %H:%M') AS DATE))")


def _need(schema: dict, m: dict, *keys: str) -> None:
    for k in keys:
        if not m.get(k):
            raise RecipeError(f"Choisissez la colonne « {k} ».")
        if m[k] not in schema:
            raise RecipeError(f"La colonne « {m[k]} » n'existe pas (ou plus) dans ce jeu.")


def _base(plan_sql: str, schema: dict, m: dict, species: list[str] | None) -> str:
    """Lignes utiles : espèce normalisée, jour, poids (kg), navire, marée, détails."""
    sp = f"upper(trim(CAST({ident(m['espece'])} AS VARCHAR)))"
    cols = [f"{sp} AS esp", f"{_day_expr(m['date'], schema[m['date']])} AS jour",
            f"TRY_CAST({ident(m['poids'])} AS DOUBLE) AS kg"]
    for k in ("navire", "maree", "nom", "quartier", "engin"):
        if m.get(k) and m[k] in schema:
            cols.append(f"CAST({ident(m[k])} AS VARCHAR) AS {k}")
        else:
            cols.append(f"NULL::VARCHAR AS {k}")
    where = ""
    if species:
        where = f" WHERE {sp} IN ({', '.join(string_lit(s.strip().upper()) for s in species)})"
    return f"SELECT {', '.join(cols)} FROM ({plan_sql}) src{where}"


def _d(v) -> date:
    if isinstance(v, date):
        return v
    try:
        return date.fromisoformat(str(v)[:10])
    except ValueError as e:
        raise RecipeError(f"Date invalide : {v} (attendu AAAA-MM-JJ).") from e


# --------------------------------------------------------------------------- quotas
def quota(con, plan_sql: str, schema: dict, spec: dict) -> dict:
    m = spec.get("mapping") or {}
    _need(schema, m, "espece", "date", "poids")
    species = [s for s in spec.get("especes") or [] if s]
    if not species:
        raise RecipeError("Indiquez au moins une espèce (code FAO) couverte par le quota.")
    start, end = _d(spec.get("debut")), _d(spec.get("fin"))
    if end < start:
        raise RecipeError("La fin de la période précède son début.")
    q = float(spec.get("quota_kg") or 0)
    if q <= 0:
        raise RecipeError("Indiquez un quota strictement positif (en kg).")
    base = _base(plan_sql, schema, m, species)
    where = f"jour BETWEEN DATE '{start}' AND DATE '{end}' AND kg IS NOT NULL"
    days = con.execute(f"SELECT jour, sum(kg) FROM ({base}) b WHERE {where} GROUP BY jour ORDER BY jour").fetchall()
    excl = con.execute(f"SELECT count(*), coalesce(sum(kg), 0) FROM ({base}) b WHERE jour IS NULL").fetchone()
    n_lines, n_vessels = con.execute(f"SELECT count(*), count(DISTINCT navire) FROM ({base}) b WHERE {where}").fetchone()
    total = float(sum(v for _, v in days))
    last = days[-1][0] if days else None
    # cumul quotidien
    cum, series = 0.0, []
    for d_, v in days:
        cum += float(v)
        series.append({"jour": d_.isoformat(), "kg": round(float(v), 3), "cumul": round(cum, 3)})
    # par mois
    months = con.execute(
        f"SELECT strftime(jour, '%Y-%m') AS mois, sum(kg), count(DISTINCT navire) FROM ({base}) b WHERE {where} "
        "GROUP BY mois ORDER BY mois").fetchall()
    cum, monthly = 0.0, []
    for mo, v, nv in months:
        cum += float(v)
        monthly.append({"mois": mo, "kg": round(float(v), 3), "cumul": round(cum, 3), "pct": round(100 * float(v) / q, 2),
                        "pct_cumul": round(100 * cum / q, 2), "navires": int(nv)})
    # projection : rythme moyen depuis le début, rythme des 30 derniers jours (extrapolations linéaires simples)
    proj = None
    if last and last < end:
        elapsed = (last - start).days + 1
        remaining = (end - last).days
        rate_all = total / elapsed if elapsed > 0 else 0.0
        recent = sum(float(v) for d_, v in days if d_ > last - timedelta(days=30))
        rate_30 = recent / 30
        proj = {"au": last.isoformat(), "jours_restants": remaining,
                "rythme_moyen_kg_j": round(rate_all, 2), "rythme_30j_kg_j": round(rate_30, 2),
                "fin_rythme_moyen": round(total + rate_all * remaining, 1),
                "fin_rythme_30j": round(total + rate_30 * remaining, 1)}
        for key, rate in (("atteinte_rythme_moyen", rate_all), ("atteinte_rythme_30j", rate_30)):
            if total >= q:
                proj[key] = None
            elif rate > 0:
                dd = last + timedelta(days=int((q - total) / rate) + 1)
                proj[key] = dd.isoformat() if dd <= end else None
            else:
                proj[key] = None
    # date de dépassement effective
    reached = next((s["jour"] for s in series if s["cumul"] >= q), None)
    seuils = sorted({float(s) for s in (spec.get("seuils") or [80, 90, 100]) if s})
    pct = 100 * total / q
    alertes = [s for s in seuils if pct >= s]
    annonce = float(spec.get("annonce_kg") or 0) or None
    return {
        "especes": [s.upper() for s in species], "debut": start.isoformat(), "fin": end.isoformat(), "quota_kg": q,
        "total_kg": round(total, 3), "pct": round(pct, 2), "reste_kg": round(q - total, 3), "derniere_donnee": last.isoformat() if last else None,
        "lignes": int(n_lines), "navires": int(n_vessels), "jours": series, "mois": monthly, "projection": proj,
        "atteint_le": reached, "seuils": seuils, "alertes": alertes,
        "annonce_kg": annonce, "ecart_annonce_pct": round(100 * (total - annonce) / annonce, 2) if annonce else None,
        "lignes_sans_date": int(excl[0]), "kg_sans_date": round(float(excl[1]), 3),
    }


# --------------------------------------------------------------------------- limitations et dépassements
_KEY = {
    "jour": "strftime(jour, '%Y-%m-%d')",
    "semaine": "strftime(jour, '%G-S%V')",
    "mois": "strftime(jour, '%Y-%m')",
    "trimestre": "strftime(jour, '%Y') || '-T' || CAST(quarter(jour) AS VARCHAR)",
    "semestre": "strftime(jour, '%Y') || '-S' || CASE WHEN month(jour) <= 6 THEN '1' ELSE '2' END",
    "annee": "strftime(jour, '%Y')",
}


def overshoots(con, plan_sql: str, schema: dict, spec: dict) -> dict:
    m = spec.get("mapping") or {}
    _need(schema, m, "espece", "date", "poids", "navire")
    rules = [r for r in spec.get("regles") or [] if r.get("espece")]
    if not rules:
        raise RecipeError("Ajoutez au moins une règle (espèce, type de limite, quantité, période).")
    base = _base(plan_sql, schema, m, None)
    parts, labels = [], []
    for i, r in enumerate(rules):
        kind = r.get("type") or "mois"
        if kind not in PERIODS:
            raise RecipeError(f"Type de limite inconnu : {kind}.")
        lim = r.get("limite_kg")
        if lim is None or lim == "":
            continue  # pas de règle = pas de limitation
        lim = float(lim)
        start, end = _d(r.get("debut")), _d(r.get("fin"))
        sp = [s.strip().upper() for s in str(r["espece"]).replace(";", ",").split(",") if s.strip()]
        if kind == "maree":
            key = "coalesce(maree, navire || ' ' || strftime(jour, '%Y-%m-%d'))" if m.get("maree") else \
                "'ligne ' || CAST(rid AS VARCHAR)"
        else:
            key = _KEY[kind]
        label = f"{', '.join(sp)} : {lim:g} kg {PERIODS[kind]} du {start:%d/%m/%Y} au {end:%d/%m/%Y}"
        labels.append(label)
        parts.append(
            f"SELECT {i} AS regle, navire, {key} AS unite, min(jour) AS debut_unite, max(jour) AS fin_unite, "
            f"sum(kg) AS kg, {lim} AS limite, count(*) AS lignes, any_value(nom) AS nom, any_value(quartier) AS quartier, "
            f"any_value(engin) AS engin FROM b WHERE esp IN ({', '.join(string_lit(x) for x in sp)}) "
            f"AND jour BETWEEN DATE '{start}' AND DATE '{end}' AND kg IS NOT NULL GROUP BY navire, unite")
    if not parts:
        raise RecipeError("Aucune règle avec une limite renseignée (0 kg = fermeture).")
    con.execute(f"CREATE OR REPLACE TEMP VIEW b AS SELECT row_number() OVER () AS rid, * FROM ({base}) x")
    con.execute(f"CREATE OR REPLACE TEMP TABLE gestion_units AS {' UNION ALL '.join(parts)}")
    over = "kg > limite"
    n, nv, kg = con.execute(f"SELECT count(*), count(DISTINCT navire), coalesce(sum(kg - limite), 0) FROM gestion_units "
                            f"WHERE {over}").fetchone()
    by_rule = con.execute(f"SELECT regle, count(*) FILTER (WHERE {over}), coalesce(sum(kg - limite) FILTER (WHERE {over}), 0), "
                          f"count(DISTINCT navire) FILTER (WHERE {over}), count(*) FROM gestion_units GROUP BY regle "
                          "ORDER BY regle").fetchall()
    by_vessel = con.execute(
        f"SELECT regle, navire, any_value(nom), any_value(quartier), any_value(engin), count(*), sum(kg - limite), max(kg) "
        f"FROM gestion_units WHERE {over} GROUP BY regle, navire ORDER BY sum(kg - limite) DESC LIMIT 2000").fetchall()
    detail = con.execute(
        f"SELECT regle, navire, nom, unite, debut_unite, fin_unite, kg, limite, "
        f"kg - limite, lignes FROM gestion_units WHERE {over} ORDER BY kg - limite DESC LIMIT 5000").fetchall()
    monthly = con.execute(
        f"SELECT strftime(fin_unite, '%Y-%m') AS mois, count(*), sum(kg - limite) FROM gestion_units WHERE {over} "
        "GROUP BY mois ORDER BY mois").fetchall()
    con.execute("DROP TABLE IF EXISTS gestion_units")
    return {
        "regles": labels,
        "total": {"depassements": int(n), "navires": int(nv), "kg": round(float(kg), 3)},
        "par_regle": [{"regle": labels[r], "depassements": int(c), "kg": round(float(k), 3), "navires": int(v),
                       "unites_controlees": int(u)} for r, c, k, v, u in by_rule],
        "par_navire": [{"regle": labels[r], "navire": nav, "nom": nom, "quartier": qu, "engin": en, "depassements": int(c),
                        "kg": round(float(k), 3), "max_kg": round(float(mx), 3)} for r, nav, nom, qu, en, c, k, mx in by_vessel],
        "detail": [{"regle": labels[r], "navire": nav, "nom": nom, "unite": u, "debut": d0.isoformat(), "fin": d1.isoformat(),
                    "kg": round(float(k), 3), "limite": float(lim), "depassement_kg": round(float(x), 3), "lignes": int(nl)}
                   for r, nav, nom, u, d0, d1, k, lim, x, nl in detail],
        "par_mois": [{"mois": mo, "depassements": int(c), "kg": round(float(k), 3)} for mo, c, k in monthly],
    }
