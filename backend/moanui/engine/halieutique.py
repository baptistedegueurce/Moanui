"""Étapes et référentiels propres aux données halieutiques (SACROIS, marées…).

Reprend et fiabilise la logique de Moanui 0.1 (routine halieutique standard,
métiers par engin, cohérence engin / espèce avec la colonne engin_sug).
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

from .recipe import _need, _need_new_name, step
from .sql import RecipeError, ident, is_numeric_type, string_lit

REF_DIR = Path(__file__).resolve().parent.parent / "referentiels"


@lru_cache
def referentiels() -> dict[str, dict]:
    return {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted(REF_DIR.glob("*.json"))}


def _values_table(rows: list[list], names: list[str]) -> str:
    vals = ", ".join("(" + ", ".join("NULL" if v is None else string_lit(v) for v in r) + ")" for r in rows)
    return f"(VALUES {vals}) AS ref({', '.join(ident(n) for n in names)})"


# --------------------------------------------------------------------------- référentiel


@step("lookup", "Compléter avec un référentiel")
def _lookup(prev, p, schema):
    ref_id = p.get("referentiel")
    ref = referentiels().get(ref_id)
    if not ref or "lignes" not in ref:
        raise RecipeError("Référentiel inconnu.")
    col = p.get("column")
    _need(schema, col)
    outputs = p.get("outputs") or ref["colonnes"]
    for o in outputs:
        if o not in ref["colonnes"]:
            raise RecipeError(f"Le référentiel ne fournit pas « {o} ».")
        if o in schema:
            raise RecipeError(f"La colonne « {o} » existe déjà : renommez-la ou supprimez-la d'abord.")
    names = ["__cle"] + ref["colonnes"]
    rows = [[r[ref["cle"]]] + [r.get(c) for c in ref["colonnes"]] for r in ref["lignes"]]
    default = p.get("default", "Autres")
    sel = ", ".join(
        f"coalesce(ref.{ident(o)}, {string_lit(default) if default is not None else 'NULL'}) AS {ident(o)}"
        for o in outputs)
    return (f"SELECT l.*, {sel} FROM {prev} l LEFT JOIN {_values_table(rows, names)} "
            f"ON upper(trim(CAST(l.{ident(col)} AS VARCHAR))) = ref.\"__cle\"")


@_lookup
def _(p):
    ref = referentiels().get(p.get("referentiel"), {})
    outs = ", ".join(p.get("outputs") or ref.get("colonnes", []))
    d = p.get("default", "Autres")
    return (f"Ajouter {outs} à partir de « {p.get('column')} » (référentiel « {ref.get('nom', p.get('referentiel'))} »)"
            f" ; codes absents du référentiel : « {d} ».")


# --------------------------------------------------------------------------- unités

UNITS = {
    "masse": {"g": 0.001, "kg": 1.0, "t": 1000.0},
    "longueur": {"cm": 0.01, "m": 1.0, "km": 1000.0, "mille_nautique": 1852.0},
    "vitesse": {"noeud": 1.0, "km_h": 1 / 1.852, "m_s": 3.6 / 1.852, "dixieme_noeud": 0.1},
    "duree": {"minute": 1 / 60, "heure": 1.0, "jour": 24.0},
}
UNIT_LABELS = {"g": "g", "kg": "kg", "t": "tonnes", "cm": "cm", "m": "m", "km": "km", "mille_nautique": "milles nautiques",
               "noeud": "nœuds", "km_h": "km/h", "m_s": "m/s", "dixieme_noeud": "dixièmes de nœud",
               "minute": "minutes", "heure": "heures", "jour": "jours"}


def unit_factor(frm: str, to: str) -> float:
    for table in UNITS.values():
        if frm in table and to in table:
            return table[frm] / table[to]
    raise RecipeError("Conversion impossible entre ces deux unités.")


@step("unit_convert", "Convertir une unité")
def _unit(prev, p, schema):
    col = p.get("column")
    t = _need(schema, col)
    if not is_numeric_type(t):
        raise RecipeError(f"« {col} » n'est pas numérique.")
    f = unit_factor(p.get("from"), p.get("to"))
    name = (p.get("name") or "").strip()
    expr = f"({ident(col)} * {f!r})"
    if not name or name == col:
        return f"SELECT * REPLACE ({expr} AS {ident(col)}) FROM {prev}"
    name = _need_new_name(name)
    if name in schema:
        raise RecipeError(f"La colonne « {name} » existe déjà.")
    return f"SELECT *, {expr} AS {ident(name)} FROM {prev}"


@_unit
def _(p):
    target = f"dans « {p['name']} »" if p.get("name") and p.get("name") != p.get("column") else "(colonne remplacée)"
    return (f"Convertir « {p.get('column')} » de {UNIT_LABELS.get(p.get('from'), p.get('from'))} en "
            f"{UNIT_LABELS.get(p.get('to'), p.get('to'))} {target}.")


# --------------------------------------------------------------------------- cohérence engin / espèce


def coherent_gears(p: dict) -> dict[str, list[str]]:
    """Engins cohérents par espèce, tels que saisis (ou le référentiel par défaut)."""
    if p.get("coherents"):
        return {k.upper(): [g.upper() for g in v] for k, v in p["coherents"].items()}
    return {k: v["coherents"] for k, v in referentiels()["engins_coherents"]["especes"].items()}


def _with_generics(gears: list[str]) -> list[str]:
    """Ajoute les codes « non spécifiés » (TX, GEN, LX…) dont un engin précis est cohérent."""
    gen = referentiels()["engins_coherents"].get("generiques", {})
    out = set(gears)
    out |= {g for g, members in gen.items() if out & set(members)}
    return sorted(out)


def non_controlables() -> list[str]:
    return referentiels()["engins_coherents"].get("non_controlables", [])


def gear_check_expr(p: dict, schema) -> str:
    sp, gear = p.get("species_column"), p.get("gear_column")
    _need(schema, sp)
    _need(schema, gear)
    vessel = p.get("vessel_column")
    if vessel:
        _need(schema, vessel)
    coh = coherent_gears(p)
    if not coh:
        raise RecipeError("Aucune espèce dans la liste des engins cohérents.")
    s = f"upper(trim(CAST({ident(sp)} AS VARCHAR)))"
    g = f"upper(trim(CAST({ident(gear)} AS VARCHAR)))"
    whens = []
    for c in p.get("corrections") or []:
        if not (c.get("species") and c.get("gear")):
            continue
        cond = f"{s} = {string_lit(c['species'].upper())} AND {g} = {string_lit(c['gear'].upper())}"
        if vessel and c.get("vessel"):
            cond += f" AND CAST({ident(vessel)} AS VARCHAR) = {string_lit(c['vessel'])}"
        target = c.get("corrected")
        whens.append(f"WHEN {cond} THEN {string_lit(target) if target else g + ' || ' + string_lit('*')}")
    coh_sql = " OR ".join(
        f"({s} = {string_lit(k)} AND {g} IN ({', '.join(string_lit(x) for x in _with_generics(v))}))"
        for k, v in coh.items() if v)
    unk = ", ".join(string_lit(x) for x in non_controlables()) or "''"
    known = ", ".join(string_lit(k) for k in coh)
    return (f"(CASE WHEN {ident(gear)} IS NULL THEN NULL "
            f"WHEN {s} NOT IN ({known}) OR {g} IN ({unk}) THEN {g} "
            f"WHEN {coh_sql or 'FALSE'} THEN {g} "
            f"{' '.join(whens)} "
            f"ELSE {g} || '*' END)")


@step("gear_check", "Contrôler la cohérence engin / espèce")
def _gear(prev, p, schema):
    name = _need_new_name(p.get("name") or "engin_sug")
    expr = gear_check_expr(p, schema)
    if name in schema:
        return f"SELECT * REPLACE ({expr} AS {ident(name)}) FROM {prev}"
    return f"SELECT *, {expr} AS {ident(name)} FROM {prev}"


@_gear
def _(p):
    n = len([c for c in p.get("corrections") or [] if c.get("species")])
    codes = list(coherent_gears(p))
    especes = ", ".join(codes) if len(codes) <= 8 else f"{len(codes)} codes espèces du référentiel"
    return (f"Créer « {p.get('name') or 'engin_sug'} » : engin de « {p.get('gear_column')} » vérifié selon l'espèce "
            f"« {p.get('species_column')} » (espèces contrôlées : {especes}). Engin cohérent : inchangé ; "
            f"incohérent : suffixé « * » ; codes génériques (TX, GEN, LX…) acceptés si un engin précis du groupe est "
            f"cohérent ; MIS / NK non contrôlés ; {n} correction(s) connue(s) appliquée(s). La colonne d'origine est conservée.")


def gear_inconsistencies(con, plan_sql: str, p: dict, schema, limit: int = 500) -> list[dict]:
    """Combinaisons navire / espèce / engin incohérentes non encore corrigées (à faire valider)."""
    expr = gear_check_expr(p, schema)
    vessel = p.get("vessel_column")
    cols = ([ident(vessel)] if vessel else []) + [ident(p["species_column"]), ident(p["gear_column"])]
    rows = con.execute(
        f"SELECT {', '.join(cols)}, count(*) AS n FROM ({plan_sql}) WHERE ends_with({expr}, '*') "
        f"GROUP BY ALL ORDER BY n DESC LIMIT {int(limit)}").fetchall()
    keys = (["vessel"] if vessel else []) + ["species", "gear", "n"]
    return [dict(zip(keys, r)) for r in rows]


# --------------------------------------------------------------------------- modèles de traitement


def _find(schema, *candidates):
    low = {c.lower(): c for c in schema}
    for cand in candidates:
        if cand.lower() in low:
            return low[cand.lower()]
    return None


def sacrois_template(schema: dict) -> list[dict]:
    """Propose les étapes de préparation standard, adaptées aux colonnes présentes."""
    steps: list[dict] = []
    date = next((c for c in ("date_deb", "date", "date_maree", "date_debarque", "DATE_DEB", "date_ret")
                 if c in schema and schema[c].upper().startswith(("DATE", "TIMESTAMP"))), None)
    if date:
        steps.append({"type": "date_parts", "params": {"column": date, "parts": ["annee", "semestre", "trimestre", "mois"]},
                      "why": f"Découper la date « {date} » pour les synthèses par période."})
    div = _find(schema, "div_ciem_cod_sipa", "div_ciem", "division_ciem")
    if div and "NS" not in schema:
        steps.append({"type": "case_when", "params": {
            "name": "NS",
            "rules": [
                {"conditions": [{"column": div, "op": "starts_with", "value": "27.7"}], "value": "Nord"},
                {"conditions": [{"column": div, "op": "starts_with", "value": "27.8"}], "value": "Sud"},
            ], "default": None},
            "why": "Secteur Nord (divisions CIEM 27.7) / Sud (27.8), comme dans la routine historique."})
    gear = _find(schema, "engin_cod", "engin", "gear_cod")
    if gear and "metier" not in schema:
        steps.append({"type": "lookup", "params": {"referentiel": "engins_metiers", "column": gear,
                                                   "outputs": ["metier", "metier_detail"], "default": "Autres"},
                      "why": "Regrouper les engins en métiers."})
    sp = _find(schema, "esp_cod_fao", "espece_cod", "esp_cod")
    if gear and sp:
        vessel = _find(schema, "cfr_cod", "navs_cod", "navire_cod", "cfr")
        steps.append({"type": "gear_check", "params": {"species_column": sp, "gear_column": gear,
                                                       "vessel_column": vessel, "name": "engin_sug",
                                                       "corrections": []},
                      "why": "Repérer les engins incohérents avec l'espèce (colonne engin_sug, l'original est gardé)."})
    kg = _find(schema, "debarquement_Kg", "quant_poids_vif", "poids_vif_kg", "debarquement_kg")
    eur = _find(schema, "debarquement_euros", "montant_euros", "valeur_euros")
    if kg and eur and "prix_moyen_kg" not in schema:
        steps.append({"type": "formula", "params": {
            "name": "prix_moyen_kg", "expression": f"SI([{kg}] > 0; [{eur}] / [{kg}]; VIDE)"},
            "why": "Prix moyen (€/kg), vide si le poids est nul."})
    duree = _find(schema, "duree_maree", "duree_maree_j", "jours_mer")
    if kg and duree and "cpue_kg_jdm" not in schema:
        steps.append({"type": "formula", "params": {
            "name": "cpue_kg_jdm", "expression": f"SI([{duree}] > 0; [{kg}] / [{duree}]; VIDE)"},
            "why": "Captures par unité d'effort (kg par jour de mer)."})
    if kg and "debarquement_t" not in schema:
        steps.append({"type": "unit_convert", "params": {"column": kg, "from": "kg", "to": "t", "name": "debarquement_t"},
                      "why": "Tonnages, plus lisibles dans les graphiques."})
    # uniquement les colonnes de codes : les libellés (noms de ports, d'espèces) gardent leur casse
    text_codes = [c for c in schema if schema[c].upper().startswith("VARCHAR")
                  and (c.lower().endswith(("_cod", "_code", "_cod_fao")) or c.lower() in ("quartier", "stat_rect"))]
    if text_codes:
        steps.insert(0, {"type": "clean_text", "params": {"columns": text_codes, "trim": True, "case": "upper",
                                                        "empty_to_null": True},
                         "why": "Uniformiser les codes (espaces, majuscules) avant tout regroupement."})
    return steps


def vms_template(schema: dict) -> list[dict]:
    """Harmonise un fichier VMS (Agiltech, CLS ou autre) puis identifie l'activité et le rectangle CIEM."""
    steps: list[dict] = []
    lat = _find(schema, "lat", "latitude", "LT", "LAT", "y")
    lon = _find(schema, "lon", "longitude", "LG", "LON", "lng", "x")
    speed = _find(schema, "vitesse_nds", "vitesse", "SP", "speed", "vit")
    when = _find(schema, "date_heure", "col_date", "date", "datetime", "horodatage", "DATE_POS")
    vessel = _find(schema, "navire", "OP", "cfr", "cfr_cod", "navs_cod", "immatriculation")
    if not (lat and lon and when and vessel):
        return []
    std = {lat: "lat", lon: "lon", when: "date_heure", vessel: "navire"}
    if speed:
        std[speed] = "vitesse_nds"
    mapping = {k: v for k, v in std.items() if k != v and v not in schema}
    if mapping:
        steps.append({"type": "rename", "params": {"mapping": mapping},
                      "why": "Noms de colonnes harmonisés (lat, lon, date_heure, navire, vitesse_nds) : les fichiers "
                             "Agiltech et CLS deviennent empilables."})
    name = {k: mapping.get(k, k) for k in std}
    if not schema[when].upper().startswith(("TIMESTAMP", "DATE")):
        steps.append({"type": "cast", "params": {"column": name[when], "to": "dateheure", "format": "%d/%m/%Y %H:%M"},
                      "why": "La date-heure doit être reconnue comme telle (format à vérifier)."})
    unit = "noeud"
    if speed and speed.upper() == "SP":
        steps.append({"type": "unit_convert", "params": {"column": name[speed], "from": "dixieme_noeud", "to": "noeud"},
                      "why": "Format CLS : la vitesse SP est en dixièmes de nœud (0–100) ; convertie en nœuds comme "
                             "chez Agiltech."})
    steps.append({"type": "vms_activity", "params": {
        "vessel": name[vessel], "datetime": name[when], "lon": name[lon], "lat": name[lat],
        "speed": name[speed] if speed else None, "speed_unit": unit, "preset": "chalut_fond", "min": 2.0, "max": 5.0,
        "max_gap_min": 120},
        "why": "Activité de pêche déduite de la vitesse (seuils du chalut de fond par défaut : à adapter à l'engin)."})
    steps.append({"type": "ciem_rect", "params": {"lon": name[lon], "lat": name[lat], "name": "rectangle_ciem"},
                  "why": "Rectangle statistique de chaque position, pour croiser avec SACROIS."})
    return steps


TEMPLATES = {
    "sacrois": {
        "nom": "Préparation SACROIS / marées standard",
        "description": "Nettoyage des codes, périodes, secteur Nord/Sud, métiers, cohérence engin/espèce, prix moyen, "
                       "CPUE et tonnages. Chaque étape reste modifiable.",
        "build": sacrois_template,
    },
    "vms": {
        "nom": "Préparation VMS (Agiltech, CLS…)",
        "description": "Harmonisation des colonnes et des unités, écarts de temps, distances et vitesses entre positions, "
                       "activité de pêche (seuils de vitesse) et rectangle CIEM. Chaque étape reste modifiable.",
        "build": vms_template,
    },
}
