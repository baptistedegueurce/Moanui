"""Recettes : suite d'étapes de transformation appliquées à une copie des données.

Le fichier brut n'est jamais modifié. Chaque étape est enregistrée (qui, quand,
pourquoi), peut être désactivée ou supprimée, et produit une phrase en français
reprise dans la fiche méthode.

Chaque étape devient une sous-requête SQL ; DuckDB exécute le tout sur le
fichier Parquet d'origine, sans jamais charger plus que nécessaire.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from .formula import compile_formula
from .sql import (
    ROW_ID,
    RecipeError,
    free_literal,
    ident,
    is_numeric_type,
    literal_for,
    string_lit,
)

Schema = dict[str, str]  # nom de colonne -> type DuckDB, dans l'ordre


@dataclass
class StepDef:
    type: str
    label: str
    compile: Callable[[str, dict, Schema], str]
    describe: Callable[[dict], str]


STEPS: dict[str, StepDef] = {}


def step(type_: str, label: str):
    def deco(fn):
        def wrap(describe):
            STEPS[type_] = StepDef(type_, label, fn, describe)
            return describe
        return wrap
    return deco


def _need(schema: Schema, col: str) -> str:
    if col not in schema:
        raise RecipeError(f"La colonne « {col} » n'existe pas (ou plus) à cette étape.")
    return schema[col]


def _need_new_name(name: str) -> str:
    name = (name or "").strip()
    if not name:
        raise RecipeError("Donnez un nom à la nouvelle colonne.")
    if name.startswith("__"):
        raise RecipeError("Les noms commençant par « __ » sont réservés à Moanui.")
    if len(name) > 120:
        raise RecipeError("Nom de colonne trop long (120 caractères maximum).")
    return name


# --------------------------------------------------------------------------- conditions

OPS = {
    "eq": "est égal à", "neq": "est différent de", "gt": "est supérieur à", "gte": "est supérieur ou égal à",
    "lt": "est inférieur à", "lte": "est inférieur ou égal à", "between": "est compris entre",
    "in": "fait partie de", "not_in": "ne fait pas partie de", "contains": "contient",
    "not_contains": "ne contient pas", "starts_with": "commence par", "ends_with": "finit par",
    "is_null": "est vide", "not_null": "n'est pas vide",
}


def condition_sql(cond: dict, schema: Schema) -> str:
    col = cond.get("column")
    op = cond.get("op")
    t = _need(schema, col)
    c = ident(col)
    v = cond.get("value")
    if op not in OPS:
        raise RecipeError(f"Opérateur de filtre inconnu : {op}.")
    if op == "is_null":
        return f"({c} IS NULL OR trim(CAST({c} AS VARCHAR)) = '')"
    if op == "not_null":
        return f"({c} IS NOT NULL AND trim(CAST({c} AS VARCHAR)) <> '')"
    if op in ("contains", "not_contains", "starts_with", "ends_with"):
        if v is None or str(v) == "":
            raise RecipeError(f"Indiquez le texte recherché pour la colonne « {col} ».")
        txt = f"lower(CAST({c} AS VARCHAR))"
        lit = string_lit(str(v).lower())
        expr = {
            "contains": f"contains({txt}, {lit})",
            "not_contains": f"NOT contains({txt}, {lit})",
            "starts_with": f"starts_with({txt}, {lit})",
            "ends_with": f"ends_with({txt}, {lit})",
        }[op]
        return f"coalesce({expr}, FALSE)" if op != "not_contains" else f"coalesce({expr}, TRUE)"
    if op in ("in", "not_in"):
        values = cond.get("values") if cond.get("values") is not None else v
        if not isinstance(values, list) or not values:
            raise RecipeError(f"Choisissez au moins une valeur pour la colonne « {col} ».")
        non_null = [x for x in values if x is not None]
        parts = []
        if non_null:
            parts.append(f"{c} IN ({', '.join(literal_for(x, t) for x in non_null)})")
        if len(non_null) < len(values):
            parts.append(f"{c} IS NULL")
        inside = "(" + " OR ".join(parts) + ")"
        return inside if op == "in" else f"(NOT coalesce({inside}, FALSE))"
    if op == "between":
        v2 = cond.get("value2")
        if v is None or v2 is None:
            raise RecipeError(f"Indiquez les deux bornes pour la colonne « {col} ».")
        return f"({c} BETWEEN {literal_for(v, t)} AND {literal_for(v2, t)})"
    if v is None or (isinstance(v, str) and v == "" and op != "eq" and op != "neq"):
        raise RecipeError(f"Indiquez une valeur pour la colonne « {col} ».")
    sym = {"eq": "=", "neq": "<>", "gt": ">", "gte": ">=", "lt": "<", "lte": "<="}[op]
    if op == "neq":
        return f"({c} IS DISTINCT FROM {literal_for(v, t)})"
    return f"({c} {sym} {literal_for(v, t)})"


def conditions_sql(params: dict, schema: Schema) -> str:
    conds = params.get("conditions") or []
    if not conds:
        raise RecipeError("Ajoutez au moins une condition.")
    joiner = " OR " if params.get("logic") == "or" else " AND "
    return "(" + joiner.join(condition_sql(c, schema) for c in conds) + ")"


def describe_condition(cond: dict) -> str:
    op = cond.get("op")
    col = f"« {cond.get('column')} »"
    if op in ("is_null", "not_null"):
        return f"{col} {OPS[op]}"
    if op in ("in", "not_in"):
        vals = cond.get("values") if cond.get("values") is not None else cond.get("value")
        vals = vals or []
        shown = ", ".join("(vide)" if x is None else str(x) for x in vals[:12])
        more = f" … (+{len(vals) - 12})" if len(vals) > 12 else ""
        return f"{col} {OPS[op]} [{shown}{more}]"
    if op == "between":
        return f"{col} {OPS[op]} {cond.get('value')} et {cond.get('value2')}"
    return f"{col} {OPS.get(op, op)} « {cond.get('value')} »"


def describe_conditions(params: dict) -> str:
    joiner = " OU " if params.get("logic") == "or" else " ET "
    return joiner.join(describe_condition(c) for c in params.get("conditions") or [])


# --------------------------------------------------------------------------- étapes


@step("filter", "Filtrer les lignes")
def _filter(prev, p, schema):
    where = conditions_sql(p, schema)
    if p.get("keep", True):
        return f"SELECT * FROM {prev} WHERE coalesce({where}, FALSE)"
    return f"SELECT * FROM {prev} WHERE NOT coalesce({where}, FALSE)"


@_filter
def _(p):
    verb = "Conserver" if p.get("keep", True) else "Exclure"
    return f"{verb} les lignes où {describe_conditions(p)}."


@step("select_columns", "Garder des colonnes")
def _select(prev, p, schema):
    cols = p.get("columns") or []
    if not cols:
        raise RecipeError("Choisissez au moins une colonne à garder.")
    for c in cols:
        _need(schema, c)
    keep = list(cols)
    if ROW_ID in schema and ROW_ID not in keep:
        keep.insert(0, ROW_ID)
    return f"SELECT {', '.join(ident(c) for c in keep)} FROM {prev}"


@_select
def _(p):
    return f"Garder uniquement les colonnes : {', '.join(p.get('columns') or [])}."


@step("drop_columns", "Supprimer des colonnes")
def _drop(prev, p, schema):
    cols = p.get("columns") or []
    if not cols:
        raise RecipeError("Choisissez au moins une colonne à supprimer.")
    for c in cols:
        _need(schema, c)
        if c == ROW_ID:
            raise RecipeError("Le numéro de ligne d'origine ne peut pas être supprimé : il assure la traçabilité.")
    if len(cols) >= len([c for c in schema if c != ROW_ID]):
        raise RecipeError("Impossible de supprimer toutes les colonnes.")
    return f"SELECT * EXCLUDE ({', '.join(ident(c) for c in cols)}) FROM {prev}"


@_drop
def _(p):
    return f"Supprimer les colonnes : {', '.join(p.get('columns') or [])}."


@step("rename", "Renommer des colonnes")
def _rename(prev, p, schema):
    mapping = p.get("mapping") or {}
    if not mapping:
        raise RecipeError("Aucun renommage indiqué.")
    final = [mapping.get(c, c) for c in schema]
    if len(set(x.lower() for x in final)) != len(final):
        raise RecipeError("Deux colonnes auraient le même nom après renommage.")
    parts = []
    for old, new in mapping.items():
        _need(schema, old)
        if old == ROW_ID:
            raise RecipeError("Le numéro de ligne d'origine ne peut pas être renommé.")
        parts.append(f"{ident(old)} AS {ident(_need_new_name(new))}")
    return f"SELECT * RENAME ({', '.join(parts)}) FROM {prev}"


@_rename
def _(p):
    return "Renommer : " + ", ".join(f"« {a} » → « {b} »" for a, b in (p.get("mapping") or {}).items()) + "."


CAST_TYPES = {
    "entier": ("BIGINT", "nombre entier"),
    "decimal": ("DOUBLE", "nombre décimal"),
    "texte": ("VARCHAR", "texte"),
    "date": ("DATE", "date"),
    "dateheure": ("TIMESTAMP", "date et heure"),
    "booleen": ("BOOLEAN", "vrai/faux"),
}


def cast_expr(col: str, src_type: str, to: str, fmt: str | None = None) -> str:
    if to not in CAST_TYPES:
        raise RecipeError(f"Type inconnu : {to}.")
    c = ident(col)
    target = CAST_TYPES[to][0]
    as_text = f"trim(CAST({c} AS VARCHAR))"
    if to in ("entier", "decimal") and not is_numeric_type(src_type):
        cleaned = f"replace(replace(replace({as_text}, ' ', ''), chr(160), ''), ',', '.')"
        expr = f"TRY_CAST({cleaned} AS DOUBLE)"
        return f"CAST(round({expr}) AS BIGINT)" if to == "entier" else expr
    if to in ("date", "dateheure") and fmt:
        expr = f"try_strptime({as_text}, {string_lit(fmt)})"
        return f"CAST({expr} AS DATE)" if to == "date" else expr
    if to == "date" and src_type.upper().startswith("VARCHAR"):
        return (f"coalesce(TRY_CAST({as_text} AS DATE), CAST(try_strptime({as_text}, '%d/%m/%Y') AS DATE))")
    if to == "booleen" and src_type.upper().startswith("VARCHAR"):
        low = f"lower({as_text})"
        return (f"(CASE WHEN {low} IN ('1','vrai','true','oui','o','y','yes') THEN TRUE "
                f"WHEN {low} IN ('0','faux','false','non','n','no') THEN FALSE ELSE NULL END)")
    return f"TRY_CAST({c} AS {target})"


@step("cast", "Changer le type")
def _cast(prev, p, schema):
    col = p.get("column")
    t = _need(schema, col)
    return f"SELECT * REPLACE ({cast_expr(col, t, p.get('to'), p.get('format'))} AS {ident(col)}) FROM {prev}"


@_cast
def _(p):
    label = CAST_TYPES.get(p.get("to"), (None, p.get("to")))[1]
    fmt = f" (format {p['format']})" if p.get("format") else ""
    return (f"Convertir « {p.get('column')} » en {label}{fmt}. "
            "Les valeurs non convertibles deviennent vides.")


@step("replace_values", "Remplacer des valeurs")
def _replace(prev, p, schema):
    col = p.get("column")
    t = _need(schema, col)
    pairs = p.get("pairs") or []
    if not pairs:
        raise RecipeError("Indiquez au moins un remplacement.")
    c = ident(col)
    whens = []
    for pair in pairs:
        frm, to = pair.get("from"), pair.get("to")
        cond = f"{c} IS NULL" if frm is None else f"{c} = {literal_for(frm, t)}"
        whens.append(f"WHEN {cond} THEN {literal_for(to, t)}")
    return f"SELECT * REPLACE ((CASE {' '.join(whens)} ELSE {c} END) AS {c}) FROM {prev}"


@_replace
def _(p):
    pairs = p.get("pairs") or []
    shown = "; ".join(f"« {x.get('from') if x.get('from') is not None else '(vide)'} » → "
                      f"« {x.get('to') if x.get('to') is not None else '(vide)'} »" for x in pairs[:20])
    more = f" … (+{len(pairs) - 20})" if len(pairs) > 20 else ""
    return f"Dans « {p.get('column')} », remplacer : {shown}{more}."


@step("edit_cells", "Corriger des cellules")
def _edit(prev, p, schema):
    edits = p.get("edits") or []
    if not edits:
        raise RecipeError("Aucune correction indiquée.")
    if ROW_ID not in schema:
        raise RecipeError("Correction cellule par cellule impossible après un regroupement "
                          "(le numéro de ligne d'origine n'existe plus). Placez la correction avant.")
    by_col: dict[str, list[tuple[int, object]]] = {}
    for e in edits:
        col = e.get("column")
        _need(schema, col)
        if col == ROW_ID:
            raise RecipeError("Le numéro de ligne d'origine ne peut pas être modifié.")
        try:
            row = int(e.get("row"))
        except (TypeError, ValueError) as err:
            raise RecipeError("Numéro de ligne invalide dans une correction.") from err
        by_col.setdefault(col, []).append((row, e.get("value")))
    reps = []
    for col, items in by_col.items():
        t = schema[col]
        whens = " ".join(f"WHEN {row} THEN {literal_for(val, t)}" for row, val in items)
        reps.append(f"(CASE {ident(ROW_ID)} {whens} ELSE {ident(col)} END) AS {ident(col)}")
    return f"SELECT * REPLACE ({', '.join(reps)}) FROM {prev}"


@_edit
def _(p):
    edits = p.get("edits") or []
    lines = [f"ligne {e.get('row')}, « {e.get('column')} » → « {e.get('value')} »"
             + (f" (ancienne valeur : « {e['old']} »)" if "old" in e else "") for e in edits[:30]]
    more = f" … (+{len(edits) - 30})" if len(edits) > 30 else ""
    return f"Corriger {len(edits)} cellule(s) à la main : " + "; ".join(lines) + more + "."


@step("formula", "Calculer une colonne (formule)")
def _formula(prev, p, schema):
    name = _need_new_name(p.get("name"))
    expr, _ = compile_formula(p.get("expression", ""), list(schema))
    if name in schema:
        return f"SELECT * REPLACE ({expr} AS {ident(name)}) FROM {prev}"
    return f"SELECT *, {expr} AS {ident(name)} FROM {prev}"


@_formula
def _(p):
    return f"Calculer « {p.get('name')} » = {p.get('expression')}."


@step("case_when", "Coder une colonne selon des conditions")
def _case_when(prev, p, schema):
    name = _need_new_name(p.get("name"))
    rules = p.get("rules") or []
    if not rules:
        raise RecipeError("Ajoutez au moins une règle.")
    values = [r.get("value") for r in rules] + [p.get("default")]
    numeric = all(v is None or _is_number(v) for v in values)
    lit = (lambda v: "NULL" if v is None else free_literal(v)) if numeric else (
        lambda v: "NULL" if v is None else string_lit(v))
    whens = " ".join(f"WHEN coalesce({conditions_sql(r, schema)}, FALSE) THEN {lit(r.get('value'))}" for r in rules)
    expr = f"(CASE {whens} ELSE {lit(p.get('default'))} END)"
    if name in schema:
        return f"SELECT * REPLACE ({expr} AS {ident(name)}) FROM {prev}"
    return f"SELECT *, {expr} AS {ident(name)} FROM {prev}"


def _is_number(v) -> bool:
    try:
        free_literal(v)
        return free_literal(v)[0] != "'"
    except Exception:
        return False


@_case_when
def _(p):
    parts = [f"si {describe_conditions(r)} alors « {r.get('value')} »" for r in p.get("rules") or []]
    default = p.get("default")
    tail = f" ; sinon « {default} »" if default is not None else " ; sinon vide"
    return f"Créer « {p.get('name')} » : " + " ; ".join(parts) + tail + "."


AGG_FUNCS = {
    "somme": ("sum({c})", "somme"),
    "moyenne": ("avg({c})", "moyenne"),
    "mediane": ("median({c})", "médiane"),
    "min": ("min({c})", "minimum"),
    "max": ("max({c})", "maximum"),
    "nombre": ("count({c})", "nombre de valeurs renseignées"),
    "nombre_lignes": ("count(*)", "nombre de lignes"),
    "nombre_distinct": ("count(DISTINCT {c})", "nombre de valeurs distinctes"),
    "ecart_type": ("stddev_samp({c})", "écart-type"),
    "premier": ("first({c})", "première valeur"),
}


@step("aggregate", "Regrouper et résumer")
def _aggregate(prev, p, schema):
    groups = p.get("group_by") or []
    aggs = p.get("aggregations") or []
    if not aggs:
        raise RecipeError("Ajoutez au moins un calcul (somme, moyenne…).")
    for g in groups:
        _need(schema, g)
    sel = [ident(g) for g in groups]
    names = set(groups)
    for a in aggs:
        fn = a.get("fn")
        if fn not in AGG_FUNCS:
            raise RecipeError(f"Calcul inconnu : {fn}.")
        col = a.get("column")
        if fn != "nombre_lignes":
            t = _need(schema, col)
            if fn in ("somme", "moyenne", "mediane", "ecart_type") and not is_numeric_type(t):
                raise RecipeError(f"« {col} » n'est pas numérique : impossible de calculer une {AGG_FUNCS[fn][1]}. "
                                  "Convertissez d'abord son type.")
        name = _need_new_name(a.get("name") or (f"{fn}_{col}" if col else fn))
        if name in names:
            raise RecipeError(f"Deux colonnes résultat s'appelleraient « {name} ».")
        names.add(name)
        sel.append(f"{AGG_FUNCS[fn][0].format(c=ident(col) if col else '*')} AS {ident(name)}")
    group = f" GROUP BY {', '.join(ident(g) for g in groups)}" if groups else ""
    order = f" ORDER BY {', '.join(ident(g) for g in groups)}" if groups else ""
    return f"SELECT {', '.join(sel)} FROM {prev}{group}{order}"


@_aggregate
def _(p):
    aggs = ", ".join(f"{AGG_FUNCS.get(a.get('fn'), (0, a.get('fn')))[1]} de « {a.get('column') or 'lignes'} »"
                     for a in p.get("aggregations") or [])
    groups = p.get("group_by") or []
    by = f" par {', '.join('« ' + g + ' »' for g in groups)}" if groups else " sur l'ensemble des lignes"
    return f"Regrouper{by} et calculer : {aggs}."


@step("sort", "Trier")
def _sort(prev, p, schema):
    by = p.get("by") or []
    if not by:
        raise RecipeError("Choisissez au moins une colonne de tri.")
    parts = []
    for b in by:
        _need(schema, b.get("column"))
        parts.append(f"{ident(b['column'])} {'DESC' if b.get('desc') else 'ASC'} NULLS LAST")
    return f"SELECT * FROM {prev} ORDER BY {', '.join(parts)}"


@_sort
def _(p):
    return "Trier par " + ", ".join(
        f"« {b.get('column')} » ({'décroissant' if b.get('desc') else 'croissant'})" for b in p.get("by") or []) + "."


@step("dedupe", "Supprimer les doublons")
def _dedupe(prev, p, schema):
    cols = p.get("columns") or [c for c in schema if c != ROW_ID]
    for c in cols:
        _need(schema, c)
    part = ", ".join(ident(c) for c in cols)
    order = ident(ROW_ID) if ROW_ID in schema else part
    return f"SELECT * FROM {prev} QUALIFY row_number() OVER (PARTITION BY {part} ORDER BY {order}) = 1"


@_dedupe
def _(p):
    cols = p.get("columns")
    on = f"sur les colonnes {', '.join(cols)}" if cols else "sur l'ensemble des colonnes"
    return f"Supprimer les lignes en double {on} (la première occurrence est conservée)."


@step("fill_null", "Remplir les vides")
def _fill(prev, p, schema):
    col = p.get("column")
    t = _need(schema, col)
    c = ident(col)
    method = p.get("method", "valeur")
    if method == "valeur":
        if p.get("value") is None:
            raise RecipeError("Indiquez la valeur de remplacement.")
        fill = literal_for(p.get("value"), t)
    elif method in ("moyenne", "mediane"):
        if not is_numeric_type(t):
            raise RecipeError(f"« {col} » n'est pas numérique.")
        fn = "avg" if method == "moyenne" else "median"
        fill = f"(SELECT {fn}({c}) FROM {prev})"
        if not t.upper().startswith(("DOUBLE", "FLOAT", "REAL", "DECIMAL")):
            fill = f"CAST(round({fill}) AS {t})"
    else:
        raise RecipeError(f"Méthode de remplissage inconnue : {method}.")
    return f"SELECT * REPLACE (coalesce({c}, {fill}) AS {c}) FROM {prev}"


@_fill
def _(p):
    m = p.get("method", "valeur")
    what = f"la valeur « {p.get('value')} »" if m == "valeur" else f"la {m.replace('mediane', 'médiane')} de la colonne"
    return f"Remplacer les vides de « {p.get('column')} » par {what}."


@step("clean_text", "Nettoyer du texte")
def _clean(prev, p, schema):
    cols = p.get("columns") or []
    if not cols:
        raise RecipeError("Choisissez au moins une colonne.")
    reps = []
    for col in cols:
        _need(schema, col)
        e = f"CAST({ident(col)} AS VARCHAR)"
        if p.get("trim", True):
            e = f"trim(regexp_replace({e}, '\\s+', ' ', 'g'))"
        if p.get("strip_accents"):
            e = f"strip_accents({e})"
        case = p.get("case")
        if case == "upper":
            e = f"upper({e})"
        elif case == "lower":
            e = f"lower({e})"
        if p.get("empty_to_null", True):
            e = f"nullif({e}, '')"
        reps.append(f"{e} AS {ident(col)}")
    return f"SELECT * REPLACE ({', '.join(reps)}) FROM {prev}"


@_clean
def _(p):
    ops = []
    if p.get("trim", True):
        ops.append("suppression des espaces superflus")
    if p.get("strip_accents"):
        ops.append("suppression des accents")
    if p.get("case") == "upper":
        ops.append("mise en majuscules")
    if p.get("case") == "lower":
        ops.append("mise en minuscules")
    if p.get("empty_to_null", True):
        ops.append("textes vides convertis en vides")
    return f"Nettoyer {', '.join(p.get('columns') or [])} : {', '.join(ops) or 'aucune opération'}."


DATE_PARTS = {
    "annee": ("year({c})", "année"),
    "semestre": ("(CASE WHEN month({c}) <= 6 THEN 1 ELSE 2 END)", "semestre"),
    "trimestre": ("quarter({c})", "trimestre"),
    "mois": ("month({c})", "mois"),
    "semaine": ("week({c})", "semaine"),
    "jour": ("day({c})", "jour"),
    "jour_semaine": ("isodow({c})", "jour de la semaine"),
}


@step("date_parts", "Extraire année, mois…")
def _date_parts(prev, p, schema):
    col = p.get("column")
    t = _need(schema, col)
    if not t.upper().startswith(("DATE", "TIMESTAMP")):
        raise RecipeError(f"« {col} » n'est pas une date. Convertissez-la d'abord (étape « Changer le type »).")
    parts = p.get("parts") or []
    if not parts:
        raise RecipeError("Choisissez au moins un élément à extraire.")
    sel = []
    for part in parts:
        if part not in DATE_PARTS:
            raise RecipeError(f"Élément de date inconnu : {part}.")
        name = f"{col}_{part}"
        if name in schema:
            raise RecipeError(f"La colonne « {name} » existe déjà.")
        sel.append(f"{DATE_PARTS[part][0].format(c=ident(col))} AS {ident(name)}")
    return f"SELECT *, {', '.join(sel)} FROM {prev}"


@_date_parts
def _(p):
    return (f"Extraire de « {p.get('column')} » : "
            + ", ".join(DATE_PARTS.get(x, (0, x))[1] for x in p.get("parts") or []) + ".")


@step("anonymize", "Anonymiser")
def _anon(prev, p, schema):
    cols = p.get("columns") or []
    if not cols:
        raise RecipeError("Choisissez au moins une colonne à anonymiser.")
    method = p.get("method", "code")
    reps = []
    for col in cols:
        _need(schema, col)
        c = ident(col)
        if method == "code":
            prefix = string_lit((p.get("prefix") or col[:3].upper()) + "_")
            code = f"{prefix} || lpad(CAST(dense_rank() OVER (ORDER BY {c}) AS VARCHAR), 4, '0')"
            reps.append(f"(CASE WHEN {c} IS NULL THEN NULL ELSE {code} END) AS {c}")
        elif method == "masque":
            reps.append(f"(CASE WHEN {c} IS NULL THEN NULL ELSE '***' END) AS {c}")
        else:
            raise RecipeError(f"Méthode d'anonymisation inconnue : {method}.")
    return f"SELECT * REPLACE ({', '.join(reps)}) FROM {prev}"


@_anon
def _(p):
    how = ("remplacées par un code (même valeur d'origine = même code)" if p.get("method", "code") == "code"
           else "masquées")
    return f"Anonymiser {', '.join(p.get('columns') or [])} : valeurs {how}."


# --------------------------------------------------------------------------- compilation


def step_types() -> list[dict]:
    return [{"type": s.type, "label": s.label} for s in STEPS.values()]


def describe_step(s: dict) -> str:
    d = STEPS.get(s.get("type"))
    if not d:
        return f"Étape inconnue ({s.get('type')})."
    try:
        return d.describe(s.get("params") or {})
    except Exception:
        return d.label + "."


def compile_step(s: dict, prev: str, schema: Schema) -> str:
    d = STEPS.get(s.get("type"))
    if not d:
        raise RecipeError(f"Type d'étape inconnu : {s.get('type')}.")
    return d.compile(prev, s.get("params") or {}, schema)


# --------------------------------------------------------------------------- jointures et empilements
# Ces étapes font appel à d'autres jeux de données : leur requête est fournie
# par un « résolveur » (contexte d'exécution), qui applique aussi leurs recettes.

import contextvars  # noqa: E402

RESOLVER: contextvars.ContextVar = contextvars.ContextVar("moanui_resolver", default=None)


def resolve(dataset_id: str) -> tuple[str, Schema, str]:
    """Renvoie (requête SQL, schéma, nom) du jeu de données référencé."""
    r = RESOLVER.get()
    if r is None:
        raise RecipeError("Ce type d'étape n'est pas disponible ici.")
    if not dataset_id:
        raise RecipeError("Choisissez le jeu de données à associer.")
    return r(dataset_id)


JOIN_KINDS = {
    "left": ("LEFT JOIN", "garder toutes les lignes du jeu actuel et ajouter les informations trouvées"),
    "inner": ("INNER JOIN", "garder uniquement les lignes présentes dans les deux jeux"),
    "full": ("FULL OUTER JOIN", "garder toutes les lignes des deux jeux"),
    "right": ("RIGHT JOIN", "garder toutes les lignes de l'autre jeu"),
    "anti": ("ANTI JOIN", "garder les lignes du jeu actuel SANS correspondance"),
    "semi": ("SEMI JOIN", "garder les lignes du jeu actuel AVEC correspondance (sans ajouter de colonnes)"),
}


def join_parts(p: dict, schema: Schema) -> tuple[str, str, list[tuple[str, str]], Schema, str]:
    how = p.get("how", "left")
    if how not in JOIN_KINDS:
        raise RecipeError(f"Type de jointure inconnu : {how}.")
    other_sql, other_schema, _ = resolve(p.get("dataset_id"))
    keys = [(k.get("left"), k.get("right")) for k in p.get("keys") or []]
    if not keys:
        raise RecipeError("Indiquez au moins une colonne de correspondance (clé).")
    conds = []
    for lk, rk in keys:
        lt = _need(schema, lk)
        if rk not in other_schema:
            raise RecipeError(f"La colonne « {rk} » n'existe pas dans le jeu associé.")
        rt = other_schema[rk]
        if (is_numeric_type(lt) != is_numeric_type(rt)) or (lt.upper()[:4] == "DATE") != (rt.upper()[:4] == "DATE"):
            conds.append(f"CAST(l.{ident(lk)} AS VARCHAR) = CAST(r.{ident(rk)} AS VARCHAR)")
        else:
            conds.append(f"l.{ident(lk)} = r.{ident(rk)}")
    return how, other_sql, keys, other_schema, " AND ".join(conds)


@step("join", "Associer un autre jeu (jointure)")
def _join(prev, p, schema):
    how, other_sql, keys, other_schema, on = join_parts(p, schema)
    sql_kind = JOIN_KINDS[how][0]
    if how in ("anti", "semi"):
        return f"SELECT l.* FROM {prev} l {sql_kind} ({other_sql}) r ON {on}"
    right_keys = {rk for _, rk in keys}
    wanted = p.get("columns") or [c for c in other_schema if c not in right_keys and not c.startswith("__")]
    suffix = p.get("suffix") or "_2"
    sel = []
    for lk, rk in keys:
        if how in ("full", "right"):
            sel.append(f"coalesce(l.{ident(lk)}, r.{ident(rk)}) AS {ident(lk)}")
    key_left = {lk for lk, _ in keys}
    left_cols = [c for c in schema if not (how in ("full", "right") and c in key_left)]
    sel = [f"l.{ident(c)}" for c in left_cols] + sel
    taken = set(schema)
    for c in wanted:
        if c not in other_schema:
            raise RecipeError(f"La colonne « {c} » n'existe pas dans le jeu associé.")
        name = c
        while name in taken:
            name = name + suffix
        taken.add(name)
        sel.append(f"r.{ident(c)} AS {ident(name)}")
    return f"SELECT {', '.join(sel)} FROM {prev} l {sql_kind} ({other_sql}) r ON {on}"


@_join
def _(p):
    keys = ", ".join(f"« {k.get('left')} » = « {k.get('right')} »" for k in p.get("keys") or [])
    how = JOIN_KINDS.get(p.get("how", "left"), ("", p.get("how")))[1]
    name = p.get("dataset_name") or p.get("dataset_id")
    return f"Associer le jeu « {name} » par {keys} : {how}."


ROW_BLOCK = 1_000_000_000


@step("union", "Empiler d'autres jeux (ajouter des lignes)")
def _union(prev, p, schema):
    ids = p.get("dataset_ids") or []
    if not ids:
        raise RecipeError("Choisissez au moins un jeu de données à empiler.")
    src_col = (p.get("source_column") or "").strip()
    parts = []
    first_label = string_lit(p.get("self_label") or "jeu actuel")
    extra = f", {first_label} AS {ident(src_col)}" if src_col else ""
    parts.append(f"SELECT *{extra} FROM {prev}")
    for k, ds_id in enumerate(ids, start=1):
        sql, other_schema, name = resolve(ds_id)
        label = string_lit(name)
        reid = ""
        if ROW_ID in other_schema:
            reid = f" REPLACE ({ident(ROW_ID)} + {k * ROW_BLOCK} AS {ident(ROW_ID)})"
        extra = f", {label} AS {ident(src_col)}" if src_col else ""
        parts.append(f"SELECT *{reid}{extra} FROM ({sql})")
    return " UNION ALL BY NAME ".join(f"({x})" for x in parts)


@_union
def _(p):
    names = p.get("dataset_names") or p.get("dataset_ids") or []
    src = f" ; colonne « {p['source_column']} » indiquant la provenance" if p.get("source_column") else ""
    return (f"Empiler les lignes de : {', '.join('« ' + str(n) + ' »' for n in names)} "
            f"(colonnes associées par leur nom, colonnes absentes laissées vides{src}).")
