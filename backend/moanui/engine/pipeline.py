"""Exécution d'une recette sur la copie Parquet en lecture seule."""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import duckdb

from .recipe import Schema, compile_step, describe_step
from .sql import ROW_ID, RecipeError, ident, is_numeric_type, is_temporal_type, string_lit

MAX_PAGE = 2000


@dataclass
class Plan:
    sql: str  # requête finale (WITH … SELECT …)
    schema: Schema
    steps: list[dict] = field(default_factory=list)  # état de chaque étape
    error: dict | None = None  # première étape en erreur


def connect(threads: int | None = None) -> duckdb.DuckDBPyConnection:
    con = duckdb.connect(config={"threads": threads} if threads else {})
    return con


def ensure_spatial(con, steps: list[dict]) -> None:
    """Charge l'extension spatiale si une étape géographique est présente."""
    from .geo import load_spatial
    from .geo_steps import SPATIAL_STEPS
    if any(s.get("type") in SPATIAL_STEPS and s.get("enabled", True) for s in steps):
        load_spatial(con)


def build(con, parquet: Path | str, recipe: list[dict], upto: int | None = None) -> Plan:
    """Compile la recette ; s'arrête à la première étape invalide (signalée, pas levée)."""
    ensure_spatial(con, recipe)
    base = f"SELECT * FROM read_parquet({string_lit(str(parquet))})"
    ctes = [f"s0 AS ({base})"]
    schema = _describe(con, ctes, "s0")
    steps_state = []
    error = None
    last = "s0"
    active = recipe if upto is None else recipe[:upto]
    for i, s in enumerate(active, start=1):
        state = {"id": s.get("id"), "index": i, "description": describe_step(s), "enabled": s.get("enabled", True)}
        if not s.get("enabled", True):
            state["status"] = "desactivee"
            steps_state.append(state)
            continue
        if error:
            state["status"] = "non_appliquee"
            steps_state.append(state)
            continue
        name = f"s{i}"
        try:
            sql = compile_step(s, last, schema)
            new_schema = _describe(con, ctes + [f"{name} AS ({sql})"], name)
        except RecipeError as e:
            error = {"step_id": s.get("id"), "index": i, "message": str(e)}
        except duckdb.Error as e:
            error = {"step_id": s.get("id"), "index": i, "message": _friendly(e)}
        if error:
            state["status"] = "erreur"
            state["error"] = error["message"]
        else:
            ctes.append(f"{name} AS ({sql})")
            added = [c for c in new_schema if c not in schema]
            removed = [c for c in schema if c not in new_schema]
            state.update(status="ok", added=added, removed=removed)
            schema = new_schema
            last = name
        steps_state.append(state)
    final = "WITH " + ", ".join(ctes) + f" SELECT * FROM {last}"
    return Plan(sql=final, schema=schema, steps=steps_state, error=error)


def check_step(con, parquet, recipe: list[dict], new_step: dict) -> Schema:
    """Valide une étape avant de l'ajouter ; lève RecipeError si elle est invalide."""
    ensure_spatial(con, [new_step])
    plan = build(con, parquet, recipe)
    if plan.error:
        raise RecipeError(f"La recette contient déjà une erreur à l'étape {plan.error['index']} : "
                          f"{plan.error['message']}")
    sub = f"({plan.sql})"
    try:
        sql = compile_step(new_step, sub, plan.schema)
        rows = con.execute(f"DESCRIBE {sql}").fetchall()
        con.execute(f"SELECT * FROM ({sql}) LIMIT 1").fetchall()
    except duckdb.Error as e:
        raise RecipeError(_friendly(e)) from e
    return {r[0]: r[1] for r in rows}


def _describe(con, ctes: list[str], name: str) -> Schema:
    rows = con.execute(f"DESCRIBE WITH {', '.join(ctes)} SELECT * FROM {name}").fetchall()
    return {r[0]: r[1] for r in rows}


def _friendly(e: Exception) -> str:
    msg = str(e).split("\n")[0]
    if "Conversion Error" in msg:
        return "Conversion impossible : certaines valeurs ne correspondent pas au type attendu. " + msg
    if "Binder Error" in msg:
        return "Colonne ou expression invalide. " + msg
    return msg


# --------------------------------------------------------------------------- lecture


def to_json_value(v):
    if v is None:
        return None
    if isinstance(v, float):
        # 12 chiffres significatifs : masque les artefacts binaires (315.84000000000003) à l'affichage ;
        # les exports, eux, gardent la valeur exacte
        return float(f"{v:.12g}") if math.isfinite(v) else None
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    if isinstance(v, (bytes, bytearray)):
        return v.hex()
    if isinstance(v, (int, str, bool)):
        return v
    return str(v)


def rows_json(res) -> list[list]:
    return [[to_json_value(v) for v in r] for r in res.fetchall()]


def page(con, plan: Plan, offset: int = 0, limit: int = 100, sort: list[dict] | None = None,
         quick_filters: list[dict] | None = None, search: str | None = None) -> dict:
    limit = max(1, min(int(limit), MAX_PAGE))
    offset = max(0, int(offset))
    where = _view_filters(plan.schema, quick_filters, search)
    order = ""
    if sort:
        parts = []
        for s in sort:
            if s.get("column") in plan.schema:
                parts.append(f"{ident(s['column'])} {'DESC' if s.get('desc') else 'ASC'} NULLS LAST")
        if parts:
            order = " ORDER BY " + ", ".join(parts)
    base = f"SELECT * FROM ({plan.sql}) t{where}"
    total = con.execute(f"SELECT count(*) FROM ({base})").fetchone()[0]
    res = con.execute(f"{base}{order} LIMIT {limit} OFFSET {offset}")
    return {
        "columns": [{"name": c, "type": t} for c, t in plan.schema.items()],
        "rows": rows_json(res),
        "total": total,
        "offset": offset,
        "limit": limit,
    }


def _view_filters(schema: Schema, quick_filters, search) -> str:
    """Filtres d'affichage (ne modifient pas la recette)."""
    from .recipe import condition_sql

    parts = []
    for f in quick_filters or []:
        parts.append(condition_sql(f, schema))
    if search:
        txt = string_lit(search.lower())
        cols = [c for c in schema if c != ROW_ID]
        if cols:
            parts.append("(" + " OR ".join(f"contains(lower(CAST({ident(c)} AS VARCHAR)), {txt})" for c in cols) + ")")
    return (" WHERE " + " AND ".join(f"coalesce({p}, FALSE)" for p in parts)) if parts else ""


def profile(con, plan: Plan) -> dict:
    cols = [c for c in plan.schema if c != ROW_ID]
    src = f"({plan.sql})"
    n = con.execute(f"SELECT count(*) FROM {src}").fetchone()[0]
    out = []
    for c in cols:
        t = plan.schema[c]
        q = ident(c)
        if is_numeric_type(t):
            r = con.execute(
                f"SELECT count({q}), count(DISTINCT {q}), min({q}), max({q}), avg({q}), median({q}), "
                f"stddev_samp({q}), quantile_cont({q}, 0.25), quantile_cont({q}, 0.75), count_if({q} < 0), "
                f"count_if({q} = 0) FROM {src}"
            ).fetchone()
            info = dict(zip(["non_vides", "distinctes", "min", "max", "moyenne", "mediane", "ecart_type",
                             "q1", "q3", "negatifs", "zeros"], (to_json_value(x) for x in r)))
            info["outliers"] = _outlier_count(con, src, q, info)
        else:
            r = con.execute(f"SELECT count({q}), count(DISTINCT {q}), min({q}), max({q}) FROM {src}").fetchone()
            info = dict(zip(["non_vides", "distinctes", "min", "max"], (to_json_value(x) for x in r)))
        info["vides"] = n - (info["non_vides"] or 0)
        info["top"] = [{"valeur": to_json_value(v), "n": k} for v, k in con.execute(
            f"SELECT {q}, count(*) AS k FROM {src} GROUP BY 1 ORDER BY k DESC, 1 LIMIT 5").fetchall()]
        out.append({"name": c, "type": t, **info})
    return {"n_rows": n, "columns": out, "warnings": quality_warnings(n, out)}


def _outlier_count(con, src, q, info) -> int | None:
    if info.get("q1") is None or info.get("q3") is None:
        return None
    iqr = info["q3"] - info["q1"]
    lo, hi = info["q1"] - 3 * iqr, info["q3"] + 3 * iqr
    return con.execute(f"SELECT count_if({q} < {lo!r} OR {q} > {hi!r}) FROM {src}").fetchone()[0]


def quality_warnings(n: int, cols: list[dict]) -> list[dict]:
    """Alertes de qualité simples, en français, à vérifier par l'utilisateur."""
    w = []
    for c in cols:
        name = c["name"]
        if n and c["vides"] == n:
            w.append({"niveau": "info", "colonne": name, "message": "Colonne entièrement vide."})
        elif n and c["vides"] / n > 0.2:
            w.append({"niveau": "attention", "colonne": name,
                      "message": f"{c['vides'] / n:.0%} de valeurs vides."})
        if c.get("negatifs"):
            w.append({"niveau": "attention", "colonne": name,
                      "message": f"{c['negatifs']} valeur(s) négative(s) : normal pour cette variable ?"})
        if c.get("outliers"):
            w.append({"niveau": "attention", "colonne": name,
                      "message": f"{c['outliers']} valeur(s) très éloignée(s) du reste (au-delà de 3 écarts "
                                 "interquartiles) : erreurs de saisie ou d'unité possibles."})
    return w


def unique_values(con, plan: Plan, column: str, search: str | None = None, limit: int = 500) -> dict:
    if column not in plan.schema:
        raise RecipeError(f"Colonne inconnue : {column}.")
    q = ident(column)
    src = f"({plan.sql})"
    where = f" WHERE contains(lower(CAST({q} AS VARCHAR)), {string_lit(search.lower())})" if search else ""
    total = con.execute(f"SELECT count(*) FROM {src}").fetchone()[0]
    n_distinct = con.execute(f"SELECT count(DISTINCT {q}) + max(CASE WHEN {q} IS NULL THEN 1 ELSE 0 END) FROM {src}"
                         ).fetchone()[0]
    rows = con.execute(f"SELECT {q} AS v, count(*) AS n FROM {src}{where} GROUP BY 1 ORDER BY n DESC, 1 NULLS FIRST "
                   f"LIMIT {int(min(limit, 5000))}").fetchall()
    return {
        "column": column,
        "total": total,
        "distinct": n_distinct,
        "values": [{"valeur": to_json_value(v), "n": k, "part": (k / total if total else 0)} for v, k in rows],
    }


# --------------------------------------------------------------------------- données de graphique

AGG_SQL = {
    "somme": "sum({c})", "moyenne": "avg({c})", "mediane": "median({c})", "min": "min({c})", "max": "max({c})",
    "nombre": "count({c})", "nombre_lignes": "count(*)", "nombre_distinct": "count(DISTINCT {c})",
    "ecart_type": "stddev_samp({c})",
}


def chart_data(con, plan: Plan, spec: dict) -> dict:
    """Agrège côté serveur pour ne jamais envoyer des millions de points au navigateur.

    spec = {x, series?, facet?, filters?, measures: [{column, agg, axis?}], raw?: bool, z?, limit?}
    """
    schema = plan.schema
    dims = [d for d in (spec.get("x"), spec.get("series"), spec.get("facet")) if d]
    for d in dims:
        if d not in schema:
            raise RecipeError(f"Colonne inconnue : {d}.")
    where = _view_filters(schema, spec.get("filters"), None)
    src = f"(SELECT * FROM ({plan.sql}) t{where})"
    limit = int(min(spec.get("limit") or 50000, 200000))
    if spec.get("raw"):
        cols = list(dict.fromkeys(dims + [m["column"] for m in spec.get("measures") or [] if m.get("column")]
                                  + ([spec["z"]] if spec.get("z") else [])))
        for c in cols:
            if c not in schema:
                raise RecipeError(f"Colonne inconnue : {c}.")
        total = con.execute(f"SELECT count(*) FROM {src}").fetchone()[0]
        sample = f" USING SAMPLE {limit} ROWS" if total > limit else ""
        res = con.execute(f"SELECT {', '.join(ident(c) for c in cols)} FROM {src}{sample}")
        return {"columns": cols, "rows": rows_json(res), "total": total, "sampled": total > limit}
    measures = spec.get("measures") or [{"agg": "nombre_lignes"}]
    sel = [ident(d) for d in dims]
    names = []
    for i, m in enumerate(measures):
        agg = m.get("agg", "somme")
        if agg not in AGG_SQL:
            raise RecipeError(f"Calcul inconnu : {agg}.")
        col = m.get("column")
        if agg != "nombre_lignes":
            if col not in schema:
                raise RecipeError(f"Colonne inconnue : {col}.")
            if agg in ("somme", "moyenne", "mediane", "ecart_type") and not is_numeric_type(schema[col]):
                raise RecipeError(f"« {col} » n'est pas numérique.")
        name = f"m{i}"
        names.append(name)
        sel.append(f"{AGG_SQL[agg].format(c=ident(col) if col else '*')} AS {name}")
    group = f" GROUP BY {', '.join(ident(d) for d in dims)} ORDER BY {', '.join(ident(d) for d in dims)}" \
        if dims else ""
    res = con.execute(f"SELECT {', '.join(sel)} FROM {src}{group} LIMIT {limit}")
    return {"columns": dims + names, "rows": rows_json(res), "total": None, "sampled": False}


__all__ = ["Plan", "build", "check_step", "page", "profile", "unique_values", "chart_data", "connect",
           "is_temporal_type"]


# --------------------------------------------------------------------------- diagnostics d'étape


def step_counts(con, plan: Plan) -> None:
    """Ajoute le nombre de lignes après chaque étape valide (traçabilité : 1779 → 1200 lignes…)."""
    ctes = plan.sql[len("WITH "):plan.sql.rindex(" SELECT * FROM ")]
    for st in plan.steps:
        if st.get("status") == "ok":
            st["n_rows"] = con.execute(f"WITH {ctes} SELECT count(*) FROM s{st['index']}").fetchone()[0]
    st0 = con.execute(f"WITH {ctes} SELECT count(*) FROM s0").fetchone()[0]
    plan.steps.insert(0, {"id": None, "index": 0, "description": "Fichier brut", "status": "ok", "n_rows": st0})


def diagnose(con, plan: Plan, step: dict) -> list[dict]:
    """Vérifications avant d'ajouter une étape de jointure ou d'empilement."""
    from .recipe import join_parts, resolve

    t = step.get("type")
    p = step.get("params") or {}
    out: list[dict] = []
    if t == "join":
        how, other_sql, keys, other_schema, on = join_parts(p, plan.schema)
        prev = f"({plan.sql})"
        n_left = con.execute(f"SELECT count(*) FROM {prev}").fetchone()[0]
        n_right = con.execute(f"SELECT count(*) FROM ({other_sql})").fetchone()[0]
        rk = ", ".join(ident(r) for _, r in keys)
        dup = con.execute(f"SELECT count(*) FROM (SELECT {rk} FROM ({other_sql}) GROUP BY ALL HAVING count(*) > 1)"
                          ).fetchone()[0]
        unmatched = con.execute(f"SELECT count(*) FROM {prev} l ANTI JOIN ({other_sql}) r ON {on}").fetchone()[0]
        unmatched_right = con.execute(f"SELECT count(*) FROM ({other_sql}) r ANTI JOIN {prev} l ON "
                                      f"{on}").fetchone()[0]
        from .recipe import compile_step
        n_after = con.execute(f"SELECT count(*) FROM ({compile_step(step, prev, plan.schema)})").fetchone()[0]
        out.append({"niveau": "info", "message": f"Lignes : {n_left} avant → {n_after} après "
                                                 f"(jeu associé : {n_right} lignes)."})
        if dup:
            out.append({"niveau": "attention",
                        "message": f"{dup} valeur(s) de clé apparaissent plusieurs fois dans le jeu associé : "
                                   "les lignes correspondantes seront dupliquées. Vérifiez la clé ou "
                                   "regroupez d'abord le jeu associé."})
        if unmatched:
            out.append({"niveau": "attention" if how in ("left", "full") else "info",
                        "message": f"{unmatched} ligne(s) du jeu actuel sans correspondance"
                                   + (" (colonnes ajoutées laissées vides)." if how in ("left", "full") else
                                      " (elles seront retirées)." if how in ("inner", "semi") else ".")})
        if unmatched_right and how in ("right", "full", "inner", "left"):
            out.append({"niveau": "info",
                        "message": f"{unmatched_right} ligne(s) du jeu associé ne trouvent pas de correspondance"
                                   + (" (ajoutées avec des vides)." if how in ("right", "full") else
                                      " (ignorées).")})
        if n_after > n_left and how in ("left", "inner"):
            out.append({"niveau": "attention",
                        "message": f"La jointure ajoute {n_after - n_left} ligne(s) : risque de double comptage "
                                   "dans les sommes."})
    elif t == "gear_check":
        from .halieutique import gear_inconsistencies

        inc = gear_inconsistencies(con, plan.sql, p, plan.schema)
        if inc:
            n = sum(x["n"] for x in inc)
            ex = "; ".join(f"{x.get('vessel', '')} {x['species']}/{x['gear']} ({x['n']})".strip() for x in inc[:5])
            out.append({"niveau": "attention",
                        "message": f"{len(inc)} combinaison(s) navire/espèce/engin incohérente(s), {n} ligne(s) "
                                   f"marquées « * » : {ex}{' …' if len(inc) > 5 else ''}. Ajoutez les corrections "
                                   "connues dans l'étape, ou exportez la liste pour validation."})
        else:
            out.append({"niveau": "info", "message": "Aucun engin incohérent pour les espèces contrôlées."})
    elif t == "vms_activity":
        from .recipe import compile_step

        sql = compile_step(step, f"({plan.sql})", plan.schema)
        n, jumps, gaps, dup, acts = con.execute(
            f"SELECT count(*), count_if(vitesse_calc_nds > 25), count_if(ecart_min > {float(p.get('max_gap_min', 120))}), "
            f"count_if(ecart_min = 0), histogram(activite) FROM ({sql})").fetchone()
        if jumps:
            out.append({"niveau": "attention",
                        "message": f"{jumps} position(s) impliquent une vitesse calculée de plus de 25 nœuds depuis la "
                                   "précédente : positions erronées, navires mélangés sous un même identifiant ou "
                                   "horodatage incorrect. À vérifier avant d'interpréter l'activité."})
        if dup:
            out.append({"niveau": "attention",
                        "message": f"{dup} position(s) ont le même horodatage que la précédente pour le même navire "
                                   "(doublons probables : voir l'étape « Supprimer les doublons »)."})
        if gaps:
            out.append({"niveau": "info", "message": f"{gaps} écart(s) de plus de {p.get('max_gap_min', 120)} min entre "
                                                     "deux positions : vitesse non calculée à ces endroits."})
        if acts:
            share = ", ".join(f"{k} : {round(100 * v / n)} %" for k, v in sorted(acts.items(), key=lambda x: -x[1]) if k)
            out.append({"niveau": "info", "message": f"Répartition de l'activité ({n} positions) : {share}."})
    elif t == "vms_catch_split":
        out.extend(catch_split_report(con, plan, step))
    elif t == "aggregate" and (p.get("secret") or {}).get("vessel_column"):
        from .recipe import compile_step

        sql = compile_step(step, f"({plan.sql})", plan.schema)
        n, k = con.execute(f"SELECT count(*), count_if(secret_stat) FROM ({sql})").fetchone()
        out.append({"niveau": "attention" if k else "info",
                    "message": f"Secret statistique : {k} groupe(s) sur {n} portent sur moins de "
                               f"{p['secret'].get('threshold') or 3} navires ; leurs valeurs seront masquées."})
    elif t == "union":
        sources = [("jeu actuel", f"({plan.sql})", plan.schema)]
        for ds_id in p.get("dataset_ids") or []:
            sql, sch, name = resolve(ds_id)
            sources.append((name, f"({sql})", sch))
        all_cols = list(dict.fromkeys(c for _, _, s in sources for c in s if not c.startswith("__")))
        for c in all_cols:
            missing = [n for n, _, s in sources if c not in s]
            if missing:
                out.append({"niveau": "attention", "colonne": c,
                            "message": f"« {c} » absente de : {', '.join(missing)} (laissée vide pour ces lignes). "
                                       "Si elle porte un autre nom, renommez-la d'abord."})
            types = {s[c] for _, _, s in sources if c in s}
            all_num = bool(types) and all(is_numeric_type(x) for x in types)
            if len(types) > 1 and not all_num:
                out.append({"niveau": "attention", "colonne": c,
                            "message": f"« {c} » n'a pas le même type partout ({', '.join(sorted(types))})."})
            if all_num:
                meds = []
                for n, sql, s in sources:
                    if c in s:
                        m = con.execute(f"SELECT median(abs({ident(c)})) FROM {sql}").fetchone()[0]
                        if m:
                            meds.append((n, float(m)))
                if len(meds) > 1:
                    lo, hi = min(meds, key=lambda x: x[1]), max(meds, key=lambda x: x[1])
                    if lo[1] > 0 and hi[1] / lo[1] >= 50:
                        out.append({"niveau": "alerte", "colonne": c,
                                    "message": f"Ordre de grandeur très différent pour « {c} » : médiane "
                                               f"{lo[1]:g} dans « {lo[0]} » contre {hi[1]:g} dans « {hi[0]} » "
                                               f"(×{hi[1] / lo[1]:.0f}). Unités différentes (tonnes / kg) ?"})
    return out


def catch_split_report(con, plan: Plan, step: dict) -> list[dict]:
    """Bilan du croisement VMS × captures : part attribuée par niveau, captures non attribuées."""
    from .geo_steps import catch_split_parts
    from .recipe import compile_step

    p = step.get("params") or {}
    prev = f"({plan.sql})"
    x = catch_split_parts(prev, p, plan.schema)
    v0 = x["values"][0]
    sql = compile_step(step, prev, plan.schema)
    out_cols = [r[0] for r in con.execute(f"DESCRIBE SELECT * FROM ({sql})").fetchall()]
    niv, qcol = out_cols[-1], out_cols[-1 - len(x["values"])]  # colonnes ajoutées en fin : …, quantités, niveau
    total, n_lines = con.execute(f"WITH c AS ({x['c']}) SELECT sum(__v0), count(*) FROM c").fetchone()
    by = dict(con.execute(f"SELECT {ident(niv)}, sum({ident(qcol)}) FROM ({sql}) WHERE {ident(niv)} IS NOT NULL "
                          "GROUP BY 1").fetchall())
    n_out = con.execute(f"SELECT count(*) FROM ({sql})").fetchone()[0]
    total = float(total or 0)
    got = sum(float(b or 0) for b in by.values())
    out = []
    if total <= 0:
        return [{"niveau": "attention", "message": f"Aucune quantité « {v0} » à répartir dans le jeu de captures."}]
    pct = lambda a: f"{100 * a / total:.1f} %".replace(".", ",")  # noqa: E731
    detail = ", ".join(f"{k} : {pct(float(b or 0))}" for k, b in sorted(by.items()))
    out.append({"niveau": "info", "message": f"« {v0} » attribué aux positions : {pct(got)} du total déclaré "
                                             f"({detail or 'rien'}) ; {n_out} ligne(s) produites."})
    rest = total - got
    if rest > total * 0.001:
        miss = con.execute(
            f"WITH v AS ({x['v']}), c AS ({x['c']}) SELECT count(*), count(DISTINCT __nav) FROM c "
            f"WHERE NOT EXISTS (SELECT 1 FROM v WHERE v.__nav = c.__nav AND v.__jour = c.__jour)").fetchone()
        nodate = con.execute(f"WITH c AS ({x['c']}) SELECT count(*) FROM c WHERE __jour IS NULL").fetchone()[0]
        msg = (f"{pct(rest)} de « {v0} » non attribué : {miss[0]} ligne(s) de captures (navire × jour"
               f"{' × rectangle' if x['rect'] else ''}{' × espèce' if x['species'] else ''}, {miss[1]} navire(s)) "
               "sans aucune position de pêche le même jour. Causes possibles : navire sans VMS (moins de 12 m), "
               "identifiants de navire différents entre les deux jeux, seuils de vitesse trop stricts, "
               "date de débarquement au lieu de la date de capture.")
        if nodate:
            msg += f" {nodate} ligne(s) ont une date illisible."
        out.append({"niveau": "attention" if rest > total * 0.2 else "info", "message": msg})
    return out
