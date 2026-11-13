"""Étapes de recette géographiques : rectangle CIEM, activité VMS, appartenance à une zone."""

from __future__ import annotations

from .geo import ciem_code_sql, resolve_layer
from .recipe import _need, _need_new_name, step
from .sql import RecipeError, ident, is_numeric_type, string_lit

SPATIAL_STEPS = {"zone_tag"}

# seuils de vitesse (nœuds) usuels pour identifier l'activité de pêche à partir de la VMS ;
# ordres de grandeur de la littérature (ex. Lee et al. 2010, Hintzen et al. 2012 — VMStools), à adapter
SPEED_PRESETS = {
    "chalut_fond": {"label": "Chalut de fond (OTB, OTT, PTB)", "min": 2.0, "max": 5.0},
    "chalut_perche": {"label": "Chalut à perche (TBB)", "min": 3.5, "max": 7.0},
    "chalut_pelagique": {"label": "Chalut pélagique (OTM, PTM)", "min": 2.5, "max": 6.0},
    "drague": {"label": "Drague (DRB)", "min": 1.5, "max": 4.0},
    "arts_dormants": {"label": "Arts dormants : filets, casiers, palangres (relève)", "min": 0.5, "max": 3.0},
    "senne": {"label": "Senne (SDN, SSC)", "min": 1.0, "max": 4.0},
}


def _num(col: str, t: str) -> str:
    return ident(col) if is_numeric_type(t) else f"TRY_CAST({ident(col)} AS DOUBLE)"


# --------------------------------------------------------------------------- rectangle CIEM


@step("ciem_rect", "Calculer le rectangle CIEM")
def _ciem(prev, p, schema):
    lon, lat = p.get("lon"), p.get("lat")
    tlon, tlat = _need(schema, lon), _need(schema, lat)
    name = _need_new_name(p.get("name") or "rectangle_ciem")
    expr = ciem_code_sql(_num(lon, tlon), _num(lat, tlat))
    if name in schema:
        return f"SELECT * REPLACE ({expr} AS {ident(name)}) FROM {prev}"
    return f"SELECT *, {expr} AS {ident(name)} FROM {prev}"


@_ciem
def _(p):
    return (f"Créer « {p.get('name') or 'rectangle_ciem'} » : rectangle statistique CIEM (1° × 0,5°, ex. 25E4) "
            f"calculé à partir de la longitude « {p.get('lon')} » et de la latitude « {p.get('lat')} ».")


# --------------------------------------------------------------------------- activité VMS


@step("vms_activity", "Identifier l'activité de pêche (VMS)")
def _vms(prev, p, schema):
    vessel, when, lon, lat = p.get("vessel"), p.get("datetime"), p.get("lon"), p.get("lat")
    _need(schema, vessel)
    tw = _need(schema, when)
    if not tw.upper().startswith(("TIMESTAMP", "DATE")):
        raise RecipeError(f"« {when} » doit être une date-heure (convertissez-la d'abord avec « Changer le type »).")
    x, y = _num(lon, _need(schema, lon)), _num(lat, _need(schema, lat))
    speed = p.get("speed")
    factor = {"noeud": 1.0, "dixieme_noeud": 0.1, "km_h": 1 / 1.852}.get(p.get("speed_unit") or "noeud")
    if factor is None:
        raise RecipeError("Unité de vitesse inconnue.")
    vmin, vmax = float(p.get("min", 2)), float(p.get("max", 5))
    if not (0 <= vmin < vmax <= 40):
        raise RecipeError("Seuils de vitesse incohérents (minimum < maximum, en nœuds).")
    gap = float(p.get("max_gap_min", 120))
    for n in ("ecart_min", "distance_km", "vitesse_calc_nds", "activite"):
        if n in schema:
            raise RecipeError(f"La colonne « {n} » existe déjà : cette étape a-t-elle déjà été appliquée ?")
    w = f"(PARTITION BY {ident(vessel)} ORDER BY {ident(when)})"
    t = f"CAST({ident(when)} AS TIMESTAMP)"
    hav = (f"2 * 6371.0088 * asin(sqrt(pow(sin(radians({y} - lag({y}) OVER {w}) / 2), 2) + "
           f"cos(radians(lag({y}) OVER {w})) * cos(radians({y})) * pow(sin(radians({x} - lag({x}) OVER {w}) / 2), 2)))")
    inner = (f"SELECT *, date_diff('second', lag({t}) OVER {w}, {t}) / 60.0 AS ecart_min, {hav} AS distance_km "
             f"FROM {prev}")
    calc = (f"CASE WHEN ecart_min > 0 AND ecart_min <= {gap} THEN round(distance_km / (ecart_min / 60.0) / 1.852, 2) "
            f"END")
    if speed:
        ts = _need(schema, speed)
        used = f"({_num(speed, ts)} * {factor})"
    else:
        used = "vitesse_calc_nds"
    act = (f"CASE WHEN {used} IS NULL THEN NULL WHEN {used} < {vmin} THEN 'arrêt / lent' "
           f"WHEN {used} <= {vmax} THEN 'pêche' ELSE 'route' END")
    return (f"SELECT * REPLACE (round(ecart_min, 1) AS ecart_min, round(distance_km, 3) AS distance_km), "
            f"{act} AS activite FROM (SELECT *, {calc} AS vitesse_calc_nds FROM ({inner}))")


@_vms
def _(p):
    src = (f"la vitesse déclarée « {p.get('speed')} » ({'dixièmes de nœud' if p.get('speed_unit') == 'dixieme_noeud' else p.get('speed_unit') or 'nœuds'})"
           if p.get("speed") else "la vitesse calculée entre deux positions successives")
    return (f"Pour chaque navire « {p.get('vessel')} », positions triées par « {p.get('datetime')} » : écart de temps "
            f"(ecart_min), distance parcourue (distance_km, formule de haversine) et vitesse calculée "
            f"(vitesse_calc_nds, non calculée si l'écart dépasse {p.get('max_gap_min', 120)} min). Activité "
            f"(colonne activite) déduite de {src} : « pêche » entre {p.get('min', 2)} et {p.get('max', 5)} nœuds, "
            f"« arrêt / lent » en dessous, « route » au-dessus. Seuils à adapter à l'engin.")


# --------------------------------------------------------------------------- appartenance à une zone


@step("zone_tag", "Repérer les positions dans une zone")
def _zone(prev, p, schema):
    lon, lat = p.get("lon"), p.get("lat")
    x, y = _num(lon, _need(schema, lon)), _num(lat, _need(schema, lat))
    if not p.get("layer"):
        raise RecipeError("Choisissez la couche de zones.")
    path, cols, _name = resolve_layer(p["layer"])
    attr = p.get("attribute")
    if attr and attr not in cols:
        raise RecipeError(f"L'attribut « {attr} » n'existe pas dans la couche.")
    name = _need_new_name(p.get("name") or "zone")
    if name in schema:
        raise RecipeError(f"La colonne « {name} » existe déjà.")
    value = (f"string_agg(DISTINCT CAST(z.{ident(attr)} AS VARCHAR), ' ; ' ORDER BY CAST(z.{ident(attr)} AS VARCHAR))"
             if attr else "true")
    base = f"(SELECT row_number() OVER () AS __k, * FROM {prev})"
    hit = (f"(SELECT b.__k, {value} AS v FROM (SELECT __k, {x} AS __x, {y} AS __y FROM {base}) b "
           f"JOIN read_parquet({string_lit(str(path))}) z ON z.__minx <= b.__x AND z.__maxx >= b.__x "
           f"AND z.__miny <= b.__y AND z.__maxy >= b.__y AND ST_Intersects(z.geom, ST_Point(b.__x, b.__y)) "
           f"GROUP BY b.__k)")
    default = "false" if not attr else "NULL"
    return (f"SELECT a.* EXCLUDE (__k), coalesce(h.v, {default}) AS {ident(name)} FROM {base} a "
            f"LEFT JOIN {hit} h USING (__k) ORDER BY a.__k")


@_zone
def _(p):
    what = (f"la valeur de « {p.get('attribute')} » de la zone contenant la position (plusieurs zones séparées par « ; », "
            "vide hors zone)") if p.get("attribute") else "vrai si la position est dans une zone de la couche, faux sinon"
    return (f"Créer « {p.get('name') or 'zone'} » : {what}. Couche : « {p.get('layer_name') or p.get('layer')} » ; "
            f"positions « {p.get('lon')} » / « {p.get('lat')} » (WGS84).")
