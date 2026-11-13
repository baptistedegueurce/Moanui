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


# --------------------------------------------------------------------------- croisement VMS × SACROIS
# Méthode usuelle (Hintzen et al. 2012, VMStools « splitAmongPings » ; Gerritsen & Lordan 2011) :
# les captures déclarées par navire et par jour (et par rectangle CIEM si disponible) sont réparties
# entre les positions de pêche du même navire, du même jour (et du même rectangle). Les captures
# sans position correspondante au niveau fin sont reportées au niveau « jour » ; le reste n'est pas
# attribué (signalé dans les vérifications).

SPLIT_WEIGHTS = {"egal": "à parts égales entre les positions", "duree": "au prorata du temps passé (écart avec la position précédente ; intervalle médian du navire après une coupure)"}


def _key(expr: str) -> str:
    return f"upper(trim(CAST({expr} AS VARCHAR)))"


def _day(col: str, t: str) -> str:
    c = ident(col)
    if t.upper().startswith(("TIMESTAMP", "DATE")):
        return f"CAST({c} AS DATE)"
    v = f"trim(CAST({c} AS VARCHAR))"
    return (f"coalesce(TRY_CAST({v} AS DATE), CAST(try_strptime({v}, '%d/%m/%Y') AS DATE), "
            f"CAST(try_strptime({v}, '%d/%m/%Y %H:%M') AS DATE), CAST(try_strptime({v}, '%d/%m/%Y %H:%M:%S') AS DATE))")


def catch_split_parts(prev: str, p: dict, schema) -> dict:
    """Morceaux SQL du croisement (réutilisés par les vérifications)."""
    from .recipe import resolve

    other_sql, other, _ = resolve(p.get("dataset_id"))
    vessel, when = p.get("vessel"), p.get("datetime")
    _need(schema, vessel)
    tw = _need(schema, when)
    if not tw.upper().startswith(("TIMESTAMP", "DATE")):
        raise RecipeError(f"« {when} » doit être une date-heure (convertissez-la d'abord avec « Changer le type »).")
    act, act_val = p.get("activity") or "", p.get("activity_value") or "pêche"
    rect = p.get("rect") or ""
    s_vessel, s_date, s_rect, s_species = p.get("s_vessel"), p.get("s_date"), p.get("s_rect") or "", p.get("s_species") or ""
    values = [v for v in p.get("values") or [] if v]
    for c, label in ((s_vessel, "navire"), (s_date, "date")):
        if not c:
            raise RecipeError(f"Indiquez la colonne {label} du jeu de captures.")
    if not values:
        raise RecipeError("Choisissez au moins une quantité à répartir (poids, valeur…).")
    for c in [s_vessel, s_date, s_rect, s_species, *values]:
        if c and c not in other:
            raise RecipeError(f"La colonne « {c} » n'existe pas dans le jeu de captures.")
    if bool(rect) != bool(s_rect):
        raise RecipeError("Pour répartir par rectangle, indiquez la colonne rectangle des deux côtés (ou aucune).")
    if rect:
        _need(schema, rect)
    weight = p.get("weight") or "egal"
    if weight not in SPLIT_WEIGHTS:
        raise RecipeError("Mode de pondération inconnu.")
    w = "1.0"
    if weight == "duree":
        gap = float(p.get("max_gap_min", 120))
        col = p.get("duration") or "ecart_min"
        tdur = _need(schema, col)
        e = _num(col, tdur)
        ok = f"{e} > 0 AND {e} <= {gap}"
        # écart absent (1re position) ou trop long (coupure) : intervalle médian du navire ; doublon (0) : poids nul
        w = (f"CASE WHEN {ok} THEN {e} WHEN {e} = 0 THEN 0 ELSE coalesce(median(CASE WHEN {ok} THEN {e} END) "
             f"OVER (PARTITION BY {ident(vessel)}), 1) END")

    where = ""
    if act:
        _need(schema, act)
        where = f" WHERE CAST({ident(act)} AS VARCHAR) = {string_lit(act_val)}"
    v = (f"SELECT row_number() OVER () AS __k, *, {_key(ident(vessel))} AS __nav, CAST({ident(when)} AS DATE) AS __jour"
         f"{', ' + _key(ident(rect)) + ' AS __rect' if rect else ''}, {w} AS __w FROM {prev}{where}")
    vals = ", ".join(f"sum({_num(c, other[c])}) AS {ident('__v' + str(i))}" for i, c in enumerate(values))
    sp = f", CAST({ident(s_species)} AS VARCHAR) AS __esp" if s_species else ""
    c = (f"SELECT row_number() OVER () AS __cid, * FROM (SELECT {_key(ident(s_vessel))} AS __nav, "
         f"{_day(s_date, other[s_date])} AS __jour"
         f"{', ' + _key(ident(s_rect)) + ' AS __rect' if s_rect else ''}{sp}, {vals} FROM ({other_sql}) GROUP BY ALL)")
    return {"v": v, "c": c, "values": values, "species": s_species, "rect": bool(rect), "other": other}


def _share(part: str) -> str:
    return (f"CASE WHEN sum(v.__w) OVER {part} > 0 THEN v.__w / sum(v.__w) OVER {part} "
            f"ELSE 1.0 / count(*) OVER {part} END")


@step("vms_catch_split", "Répartir les captures sur les positions (VMS × SACROIS)")
def _split(prev, p, schema):
    x = catch_split_parts(prev, p, schema)
    values, s_species = x["values"], x["species"]
    taken = set(schema)
    out_cols = []

    def new(name):
        while name in taken:
            name += "_2"
        taken.add(name)
        return name

    if s_species:
        out_cols.append(f"a.__esp AS {ident(new(s_species))}")
    for i, c in enumerate(values):
        out_cols.append(f"round(a.{ident('__v' + str(i))}, 4) AS {ident(new(c))}")
    out_cols.append(f"a.__niveau AS {ident(new('niveau_repartition'))}")
    esp = ", c.__esp" if s_species else ""
    part = "(PARTITION BY c.__cid)"
    levels = []
    if x["rect"]:
        levels.append(("jour + rectangle", "v.__nav = c.__nav AND v.__jour = c.__jour AND v.__rect = c.__rect"))
    levels.append(("jour", "v.__nav = c.__nav AND v.__jour = c.__jour"))
    parts = []
    done = []
    for label, on in levels:
        excl = "".join(f" AND c.__cid NOT IN (SELECT __cid FROM {d})" for d in done)
        name = f"l{len(done)}"
        parts.append(f"{name} AS (SELECT v.__k, c.__cid{esp}, {_share(part)} AS __part, {string_lit(label)} AS __niveau, "
                     f"{', '.join('c.' + ident('__v' + str(i)) for i in range(len(values)))} "
                     f"FROM c JOIN v ON {on} WHERE TRUE{excl})")
        done.append(name)
    union = " UNION ALL ".join(
        f"SELECT __k{', __esp' if s_species else ''}, __niveau, "
        + ", ".join(f"{ident('__v' + str(i))} * __part AS {ident('__v' + str(i))}" for i in range(len(values)))
        + f" FROM {d}" for d in done)
    keep = bool(p.get("keep_unmatched"))
    join = "LEFT JOIN" if keep else "JOIN"
    order = "v.__k" + (", a.__esp" if s_species else "")
    return (f"WITH v AS ({x['v']}), c AS ({x['c']}), {', '.join(parts)}, a AS ({union}) "
            f"SELECT v.* EXCLUDE (__k, __nav, __jour, __w{', __rect' if x['rect'] else ''}), {', '.join(out_cols)} "
            f"FROM v {join} a ON a.__k = v.__k ORDER BY {order}")


@_split
def _(p):
    lvl = ("navire + jour + rectangle CIEM (« " + str(p.get("rect")) + " » / « " + str(p.get("s_rect")) + " »), "
           "puis navire + jour pour les captures sans position dans le rectangle déclaré") if p.get("rect") else "navire + jour"
    act = (f" Seules les positions où « {p.get('activity')} » = « {p.get('activity_value') or 'pêche'} » reçoivent des captures."
           if p.get("activity") else " Toutes les positions reçoivent des captures.")
    vals = ", ".join(f"« {v} »" for v in p.get("values") or [])
    sp = f", par « {p.get('s_species')} »" if p.get("s_species") else ""
    keep = " Les positions sans capture correspondante sont conservées (quantités vides)." if p.get("keep_unmatched") else \
        " Les positions sans capture correspondante sont retirées."
    return (f"Répartir {vals}{sp} du jeu « {p.get('dataset_name') or p.get('dataset_id')} » sur les positions VMS "
            f"(navire « {p.get('vessel')} » = « {p.get('s_vessel')} », jour de « {p.get('datetime')} » = « {p.get('s_date')} »), "
            f"{SPLIT_WEIGHTS.get(p.get('weight') or 'egal', '')}. Niveaux de correspondance : {lvl}.{act}{keep} "
            "Colonne niveau_repartition : niveau utilisé. Une ligne par position et par espèce "
            "(méthode de Hintzen et al. 2012, VMStools).")
