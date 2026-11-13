"""Statistiques guidées : vérification des conditions, test adapté, interprétation en français.

Principes :
- chaque analyse vérifie ses conditions d'application avant de conclure ;
- si une condition bloquante n'est pas remplie, le résultat est bloqué et une
  alternative est proposée ; l'utilisateur peut passer outre en le justifiant
  (la justification figure dans la fiche méthode) ;
- l'interprétation est rédigée pour des non-statisticiens, avec ses limites.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from scipy import stats as st

from .engine.sql import RecipeError, ident, is_numeric_type

ALPHA = 0.05
SHAPIRO_MAX = 5000


# --------------------------------------------------------------------------- outils


def fr(x, d=3) -> str:
    """Nombre au format français."""
    if x is None or (isinstance(x, float) and not math.isfinite(x)):
        return "—"
    if isinstance(x, (int, np.integer)):
        return f"{int(x):,}".replace(",", " ")
    x = float(x)
    if abs(x) >= 1e6 or (abs(x) < 1e-3 and x != 0):
        return f"{x:.{d}g}".replace(".", ",")
    s = f"{x:,.{d}f}".replace(",", " ")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s.replace(".", ",")


def fp(p: float) -> str:
    if p is None or not math.isfinite(p):
        return "—"
    return "< 0,001" if p < 0.001 else fr(p, 3)


def fpe(p: float) -> str:
    """« p = 0,03 » ou « p < 0,001 »."""
    f = fp(p)
    return f"p {f}" if f.startswith("<") else f"p = {f}"


def relax_normality(checks: list, nonparam: bool) -> None:
    """Si un test non paramétrique est utilisé, la non-normalité n'est plus bloquante."""
    if not nonparam:
        return
    for c in checks:
        if c.nom.startswith("Normalité") and not c.ok and c.niveau == "bloquant":
            c.niveau = "info"
            c.message += " Un test qui ne suppose pas la normalité est donc utilisé."


def num(v) -> float | None:
    try:
        f = float(v)
        return f if math.isfinite(f) else None
    except (TypeError, ValueError):
        return None


@dataclass
class Check:
    nom: str
    ok: bool
    niveau: str  # bloquant | avertissement | info
    message: str
    detail: str = ""

    def as_dict(self):
        return {"nom": self.nom, "ok": self.ok, "niveau": self.niveau, "message": self.message, "detail": self.detail}


@dataclass
class Result:
    analyse: str
    titre: str
    test: str = ""
    test_label: str = ""
    checks: list[Check] = field(default_factory=list)
    bloque: bool = False
    alternative: str | None = None
    resultats: list[dict] = field(default_factory=list)  # lignes clé / valeur
    tableaux: list[dict] = field(default_factory=list)  # {titre, colonnes, lignes}
    interpretation: list[str] = field(default_factory=list)
    limites: list[str] = field(default_factory=list)
    graph: dict | None = None
    effectifs: dict = field(default_factory=dict)

    def as_dict(self):
        return {
            "analyse": self.analyse, "titre": self.titre, "test": self.test, "test_label": self.test_label,
            "checks": [c.as_dict() for c in self.checks], "bloque": self.bloque, "alternative": self.alternative,
            "resultats": self.resultats, "tableaux": self.tableaux, "interpretation": self.interpretation,
            "limites": self.limites, "graph": self.graph, "effectifs": self.effectifs,
        }


def normality(x: np.ndarray, label: str) -> Check:
    n = len(x)
    if n < 3:
        return Check(f"Normalité ({label})", False, "bloquant", f"Trop peu de valeurs ({n}) pour juger la forme de la distribution.")
    if np.ptp(x) == 0:
        return Check(f"Normalité ({label})", False, "avertissement", "Toutes les valeurs sont identiques.")
    sample = x if n <= SHAPIRO_MAX else np.random.default_rng(0).choice(x, SHAPIRO_MAX, replace=False)
    w, p = st.shapiro(sample)
    skew = float(st.skew(x))
    if p >= ALPHA:
        return Check(f"Normalité ({label})", True, "info", f"Distribution compatible avec une loi normale (Shapiro-Wilk {fpe(p)}).")
    if n >= 50 and abs(skew) < 1:
        return Check(f"Normalité ({label})", True, "avertissement",
                     f"Écart à la normalité détecté ({fpe(p)}) mais l'effectif ({n}) et l'asymétrie modérée "
                     f"({fr(skew, 2)}) rendent les tests sur les moyennes fiables (théorème central limite).")
    return Check(f"Normalité ({label})", False, "bloquant",
                 f"Distribution non normale (Shapiro-Wilk {fpe(p)}, asymétrie {fr(skew, 2)}, n = {n}).",
                 "Fréquent pour des captures ou des prix (beaucoup de petites valeurs, quelques très grandes).")


def effect_words(v: float, seuils: tuple[float, float, float]) -> str:
    a = abs(v)
    if a < seuils[0]:
        return "négligeable"
    if a < seuils[1]:
        return "faible"
    if a < seuils[2]:
        return "moyen"
    return "fort"


def sig_sentence(p: float) -> str:
    if p < ALPHA:
        return f"La probabilité d'observer un tel écart par simple hasard est faible ({fpe(p)}{'' if p < 0.001 else ' < 0,05'}) : le résultat est statistiquement significatif."
    return (f"L'écart observé pourrait s'expliquer par le hasard ({fpe(p)} ≥ 0,05) : on ne peut pas conclure à une "
            "différence. Attention, cela ne prouve pas que les groupes sont identiques.")


COMMON_LIMITS = [
    "« Significatif » ne veut pas dire « important » : regardez la taille de l'effet et les valeurs elles-mêmes.",
    "Les observations doivent être indépendantes : plusieurs lignes d'une même marée ou d'un même navire ne sont pas "
    "des observations indépendantes (agrégez d'abord, par exemple par marée).",
]


# --------------------------------------------------------------------------- extraction


def fetch(con, plan_sql: str, schema: dict, columns: list[str], filters_sql: str = "") -> tuple[dict, int, int]:
    for c in columns:
        if c not in schema:
            raise RecipeError(f"Colonne inconnue : {c}.")
    cols = ", ".join(ident(c) for c in columns)
    notnull = " AND ".join(f"{ident(c)} IS NOT NULL" for c in columns)
    total = con.execute(f"SELECT count(*) FROM ({plan_sql}) t{filters_sql}").fetchone()[0]
    where = f"{filters_sql} AND {notnull}" if filters_sql else f" WHERE {notnull}"
    data = con.execute(f"SELECT {cols} FROM ({plan_sql}) t{where} LIMIT 2000000").fetchnumpy()
    n = len(next(iter(data.values()))) if data else 0
    return {k: np.asarray(v) for k, v in data.items()}, total, n


# --------------------------------------------------------------------------- analyses


def compare_groups(y: np.ndarray, g: np.ndarray, yname: str, gname: str, force: str | None) -> Result:
    levels = [lv for lv in sorted(set(g.tolist()), key=str)]
    groups = [y[g == lv].astype(float) for lv in levels]
    k = len(levels)
    if k < 2:
        raise RecipeError(f"« {gname} » ne contient qu'un seul groupe : rien à comparer.")
    if k > 30:
        raise RecipeError(f"« {gname} » contient {k} groupes : regroupez les modalités ou choisissez une autre variable.")
    titre = f"Comparer « {yname} » entre les {'deux ' if k == 2 else ''}groupes de « {gname} »"
    r = Result("comparer_groupes", titre)
    r.effectifs = {str(lv): int(len(x)) for lv, x in zip(levels, groups)}
    small = [str(lv) for lv, x in zip(levels, groups) if len(x) < 3]
    r.checks.append(Check("Effectifs", not small, "bloquant" if small else "info",
                          f"Groupes avec moins de 3 valeurs : {', '.join(small)}." if small else
                          "Chaque groupe contient au moins 3 valeurs."))
    norm = [normality(x, str(lv)) for lv, x in zip(levels, groups) if len(x) >= 3]
    normal_ok = all(c.ok for c in norm)
    r.checks += norm
    lev_p = st.levene(*[x for x in groups if len(x) >= 2]).pvalue if all(len(x) >= 2 for x in groups) else float("nan")
    var_ok = not (lev_p < ALPHA)
    r.checks.append(Check("Égalité des variances", var_ok, "avertissement" if not var_ok else "info",
                          f"Variances {'différentes' if not var_ok else 'comparables'} entre groupes (Levene {fpe(lev_p)})."))
    param = normal_ok
    auto = ("t_welch" if param else "mann_whitney") if k == 2 else (
        ("anova" if var_ok else "welch_anova") if param else "kruskal")
    test = force or auto
    allowed = {"t_welch", "mann_whitney"} if k == 2 else {"anova", "welch_anova", "kruskal"}
    if test not in allowed:
        raise RecipeError("Test non adapté au nombre de groupes.")
    parametric = test in ("t_welch", "anova", "welch_anova")
    relax_normality(r.checks, not parametric)
    if small or (parametric and not normal_ok):
        r.bloque = True
        r.alternative = ("mann_whitney" if k == 2 else "kruskal") if not small else None
    r.test = test
    means = [float(np.mean(x)) for x in groups]
    meds = [float(np.median(x)) for x in groups]
    r.tableaux.append({"titre": "Résumé par groupe", "colonnes": ["Groupe", "n", "Moyenne", "Médiane", "Écart-type", "Min", "Max"],
                       "lignes": [[str(lv), len(x), fr(float(np.mean(x))), fr(float(np.median(x))),
                                   fr(float(np.std(x, ddof=1))) if len(x) > 1 else "—", fr(float(np.min(x))), fr(float(np.max(x)))]
                                  for lv, x in zip(levels, groups)]})
    r.graph = {"type": "boites", "groupes": [str(lv) for lv in levels],
               "valeurs": [x[:5000].tolist() for x in groups], "y": yname}
    if small:
        return r
    if k == 2:
        a, b = groups
        if test == "t_welch":
            res = st.ttest_ind(a, b, equal_var=False)
            sp = math.sqrt((np.var(a, ddof=1) + np.var(b, ddof=1)) / 2)
            d = (np.mean(a) - np.mean(b)) / sp if sp else 0.0
            ci = res.confidence_interval(0.95)
            r.test_label = "Test t de Welch (comparaison de deux moyennes)"
            r.resultats = [{"nom": "Différence des moyennes", "valeur": fr(means[0] - means[1])},
                           {"nom": "Intervalle de confiance à 95 %", "valeur": f"[{fr(ci.low)} ; {fr(ci.high)}]"},
                           {"nom": "t", "valeur": fr(float(res.statistic))}, {"nom": "ddl", "valeur": fr(float(res.df), 1)},
                           {"nom": "p", "valeur": fp(res.pvalue)},
                           {"nom": "Taille d'effet (d de Cohen)", "valeur": f"{fr(d, 2)} ({effect_words(d, (0.2, 0.5, 0.8))})"}]
            p = res.pvalue
            r.interpretation = [
                f"En moyenne, « {yname} » vaut {fr(means[0])} pour « {levels[0]} » et {fr(means[1])} pour « {levels[1]} ».",
                sig_sentence(p),
                f"La vraie différence se situe probablement entre {fr(ci.low)} et {fr(ci.high)} ; l'effet est "
                f"{effect_words(d, (0.2, 0.5, 0.8))}."]
        else:
            res = st.mannwhitneyu(a, b, alternative="two-sided")
            rb = 1 - 2 * res.statistic / (len(a) * len(b))
            r.test_label = "Test de Mann-Whitney (comparaison de deux distributions, sans hypothèse de normalité)"
            p = res.pvalue
            r.resultats = [{"nom": "Médianes", "valeur": f"{fr(meds[0])} / {fr(meds[1])}"},
                           {"nom": "U", "valeur": fr(float(res.statistic))}, {"nom": "p", "valeur": fp(p)},
                           {"nom": "Taille d'effet (corrélation rang-bisériale)", "valeur": f"{fr(rb, 2)} ({effect_words(rb, (0.1, 0.3, 0.5))})"}]
            r.interpretation = [
                f"Médiane de « {yname} » : {fr(meds[0])} pour « {levels[0]} », {fr(meds[1])} pour « {levels[1]} ».",
                sig_sentence(p), f"L'effet est {effect_words(rb, (0.1, 0.3, 0.5))}."]
    else:
        n_tot = sum(len(x) for x in groups)
        if test == "anova":
            res = st.f_oneway(*groups)
            ss_b = sum(len(x) * (np.mean(x) - np.mean(np.concatenate(groups))) ** 2 for x in groups)
            ss_t = float(np.sum((np.concatenate(groups) - np.mean(np.concatenate(groups))) ** 2))
            eta2 = ss_b / ss_t if ss_t else 0.0
            r.test_label = "ANOVA à un facteur (comparaison de plusieurs moyennes)"
            stat_txt, p = f"F = {fr(float(res.statistic))}", res.pvalue
            eff = f"η² = {fr(eta2, 3)} ({effect_words(math.sqrt(eta2), (0.1, 0.25, 0.4))})"
        elif test == "welch_anova":
            stat, p, df1, df2 = welch_anova(groups)
            r.test_label = "ANOVA de Welch (moyennes, variances inégales)"
            stat_txt = f"F = {fr(stat)} (ddl {fr(df1, 1)} ; {fr(df2, 1)})"
            eff = "—"
        else:
            res = st.kruskal(*groups)
            eps2 = (res.statistic - k + 1) / (n_tot - k) if n_tot > k else 0.0
            r.test_label = "Test de Kruskal-Wallis (plusieurs distributions, sans hypothèse de normalité)"
            stat_txt, p = f"H = {fr(float(res.statistic))}", res.pvalue
            eff = f"ε² = {fr(eps2, 3)} ({effect_words(math.sqrt(max(eps2, 0)), (0.1, 0.25, 0.4))})"
        r.resultats = [{"nom": "Statistique", "valeur": stat_txt}, {"nom": "p", "valeur": fp(p)},
                       {"nom": "Taille d'effet", "valeur": eff}]
        r.interpretation = [sig_sentence(p).replace("un tel écart", "de tels écarts entre groupes")]
        if p < ALPHA:
            pairs = pairwise(groups, levels, parametric)
            r.tableaux.append({"titre": "Comparaisons deux à deux (correction de Holm)",
                               "colonnes": ["Groupe A", "Groupe B", "p ajusté", "Différent ?"], "lignes": pairs})
            diff = [f"{a} / {b}" for a, b, _, ok in pairs if ok == "oui"]
            r.interpretation.append(
                "Paires de groupes qui diffèrent : " + (", ".join(diff[:12]) + (" …" if len(diff) > 12 else "")
                                                       if diff else "aucune après correction des comparaisons multiples."))
    r.limites = COMMON_LIMITS + (["Les comparaisons deux à deux sont corrigées (Holm) pour éviter les faux positifs."] if k > 2 else [])
    return r


def welch_anova(groups):
    k = len(groups)
    n = np.array([len(x) for x in groups], float)
    m = np.array([np.mean(x) for x in groups])
    v = np.array([np.var(x, ddof=1) for x in groups])
    w = n / v
    mw = np.sum(w * m) / np.sum(w)
    a = np.sum(w * (m - mw) ** 2) / (k - 1)
    tmp = np.sum((1 - w / np.sum(w)) ** 2 / (n - 1))
    b = 1 + 2 * (k - 2) / (k ** 2 - 1) * tmp
    f = a / b
    df2 = (k ** 2 - 1) / (3 * tmp)
    p = st.f.sf(f, k - 1, df2)
    return float(f), float(p), k - 1, float(df2)


def holm(ps: list[float]) -> list[float]:
    order = np.argsort(ps)
    m = len(ps)
    adj = [0.0] * m
    running = 0.0
    for rank, i in enumerate(order):
        running = max(running, min(1.0, (m - rank) * ps[i]))
        adj[i] = running
    return adj


def pairwise(groups, levels, parametric: bool):
    pairs, ps = [], []
    for i in range(len(groups)):
        for j in range(i + 1, len(groups)):
            if parametric:
                p = st.ttest_ind(groups[i], groups[j], equal_var=False).pvalue
            else:
                p = st.mannwhitneyu(groups[i], groups[j], alternative="two-sided").pvalue
            pairs.append((str(levels[i]), str(levels[j])))
            ps.append(float(p))
    adj = holm(ps)
    return [[a, b, fp(p), "oui" if p < ALPHA else "non"] for (a, b), p in zip(pairs, adj)]


def association(x: np.ndarray, y: np.ndarray, xname: str, yname: str, force: str | None) -> Result:
    xs = sorted(set(x.tolist()), key=str)
    ys = sorted(set(y.tolist()), key=str)
    if len(xs) < 2 or len(ys) < 2:
        raise RecipeError("Chaque variable doit avoir au moins deux modalités.")
    if len(xs) * len(ys) > 400:
        raise RecipeError("Trop de modalités croisées : regroupez les catégories rares d'abord.")
    table = np.array([[int(np.sum((x == a) & (y == b))) for b in ys] for a in xs])
    r = Result("association", f"Lien entre « {xname} » et « {yname} »")
    r.effectifs = {"n": int(table.sum())}
    chi2, p, dof, expected = st.chi2_contingency(table, correction=False)
    low = float(np.mean(expected < 5))
    tiny = bool(np.any(expected < 1))
    ok = low <= 0.2 and not tiny
    r.checks.append(Check("Effectifs théoriques", ok, "bloquant" if not ok else "info",
                          f"{low:.0%} des cases ont un effectif attendu < 5" + (" et certaines < 1" if tiny else "") + "."
                          if not ok else "Effectifs attendus suffisants (≥ 5 dans au moins 80 % des cases).",
                          "Regroupez les modalités rares, ou utilisez le test exact de Fisher (tableau 2×2)."))
    is2x2 = table.shape == (2, 2)
    test = force or ("chi2" if ok else ("fisher" if is2x2 else "chi2"))
    if test == "fisher" and not is2x2:
        raise RecipeError("Le test exact de Fisher n'est proposé que pour un tableau 2×2.")
    r.test = test
    if test == "chi2" and not ok:
        r.bloque = True
        r.alternative = "fisher" if is2x2 else None
    n = table.sum()
    v = math.sqrt(chi2 / (n * (min(table.shape) - 1))) if n else 0.0
    if test == "fisher":
        odds, p = st.fisher_exact(table)
        r.test_label = "Test exact de Fisher"
        r.resultats = [{"nom": "Rapport des cotes", "valeur": fr(float(odds))}, {"nom": "p", "valeur": fp(p)}]
    else:
        r.test_label = "Test du χ² d'indépendance"
        r.resultats = [{"nom": "χ²", "valeur": fr(float(chi2))}, {"nom": "ddl", "valeur": str(dof)},
                       {"nom": "p", "valeur": fp(p)},
                       {"nom": "V de Cramér", "valeur": f"{fr(v, 2)} ({effect_words(v, (0.1, 0.3, 0.5))})"}]
    r.tableaux.append({"titre": "Tableau croisé (effectifs observés)", "colonnes": [xname + " \\ " + yname] + [str(b) for b in ys],
                       "lignes": [[str(a)] + [int(c) for c in row] for a, row in zip(xs, table)]})
    resid = (table - expected) / np.sqrt(np.where(expected > 0, expected, 1))
    strong = [(str(xs[i]), str(ys[j]), resid[i, j]) for i in range(len(xs)) for j in range(len(ys)) if abs(resid[i, j]) > 2]
    r.interpretation = [sig_sentence(p).replace("un tel écart", "une telle répartition") if p < ALPHA else
                        f"Rien n'indique que « {xname} » et « {yname} » soient liés ({fpe(p)})."]
    if p < ALPHA and strong:
        r.interpretation.append("Combinaisons plus (+) ou moins (−) fréquentes qu'attendu : " + ", ".join(
            f"{a} × {b} ({'+' if v_ > 0 else '−'})" for a, b, v_ in sorted(strong, key=lambda t: -abs(t[2]))[:10]) + ".")
    r.limites = COMMON_LIMITS[:1] + ["Un lien statistique n'indique pas de relation de cause à effet."]
    return r


def correlation(x: np.ndarray, y: np.ndarray, xname: str, yname: str, force: str | None) -> Result:
    x, y = x.astype(float), y.astype(float)
    n = len(x)
    r = Result("correlation", f"Relation entre « {xname} » et « {yname} »")
    r.effectifs = {"n": n}
    if n < 5:
        r.checks.append(Check("Effectif", False, "bloquant", f"Seulement {n} paires de valeurs."))
        r.bloque = True
        return r
    nx, ny = normality(x, xname), normality(y, yname)
    r.checks += [nx, ny]
    z = np.abs(st.zscore(x)) > 4 if np.std(x) else np.zeros(n, bool)
    z |= np.abs(st.zscore(y)) > 4 if np.std(y) else np.zeros(n, bool)
    out = int(z.sum())
    r.checks.append(Check("Valeurs extrêmes", out == 0, "avertissement" if out else "info",
                          f"{out} point(s) très éloigné(s) (> 4 écarts-types) : ils peuvent à eux seuls créer ou masquer une corrélation."
                          if out else "Pas de valeur extrême marquée."))
    param = nx.ok and ny.ok
    test = force or ("pearson" if param else "spearman")
    r.test = test
    relax_normality(r.checks, test == "spearman")
    if test == "pearson" and not param:
        r.bloque = True
        r.alternative = "spearman"
    if test == "pearson":
        res = st.pearsonr(x, y)
        ci = res.confidence_interval(0.95)
        coef, p = float(res.statistic), float(res.pvalue)
        r.test_label = "Corrélation de Pearson (relation linéaire)"
        r.resultats = [{"nom": "r", "valeur": fr(coef, 2)}, {"nom": "IC 95 %", "valeur": f"[{fr(ci.low, 2)} ; {fr(ci.high, 2)}]"},
                       {"nom": "p", "valeur": fp(p)}, {"nom": "Part de variance commune (r²)", "valeur": f"{coef ** 2:.0%}"}]
    else:
        res = st.spearmanr(x, y)
        coef, p = float(res.statistic), float(res.pvalue)
        r.test_label = "Corrélation de Spearman (relation monotone, sur les rangs)"
        r.resultats = [{"nom": "ρ", "valeur": fr(coef, 2)}, {"nom": "p", "valeur": fp(p)}]
    sens = "augmente" if coef > 0 else "diminue"
    r.interpretation = [
        f"Quand « {xname} » augmente, « {yname} » {sens} en tendance : lien {effect_words(coef, (0.1, 0.3, 0.5))} "
        f"({'r' if test == 'pearson' else 'ρ'} = {fr(coef, 2)}).", sig_sentence(p)]
    idx = np.random.default_rng(0).choice(n, min(n, 5000), replace=False)
    r.graph = {"type": "nuage", "x": x[idx].tolist(), "y": y[idx].tolist(), "xname": xname, "yname": yname}
    r.limites = ["Corrélation ne veut pas dire causalité : une troisième variable (saison, zone, engin…) peut expliquer les deux.",
                 COMMON_LIMITS[1]]
    return r


def regression(data: dict, yname: str, xnames: list[str], cat: set[str], force: str | None) -> Result:
    y = data[yname].astype(float)
    n = len(y)
    cols, names = [np.ones(n)], ["(constante)"]
    for xn in xnames:
        v = data[xn]
        if xn in cat:
            levels = sorted(set(v.tolist()), key=str)
            if len(levels) > 20:
                raise RecipeError(f"« {xn} » a trop de modalités ({len(levels)}) pour une régression.")
            for lv in levels[1:]:
                cols.append((v == lv).astype(float))
                names.append(f"{xn} = {lv} (vs {levels[0]})")
        else:
            cols.append(v.astype(float))
            names.append(xn)
    X = np.column_stack(cols)
    p_ = X.shape[1]
    r = Result("regression", f"Expliquer « {yname} » par {', '.join('« ' + x + ' »' for x in xnames)}")
    r.effectifs = {"n": n, "parametres": p_}
    enough = n >= 10 * (p_ - 1) and n > p_ + 2
    r.checks.append(Check("Effectif", enough, "bloquant" if n <= p_ + 2 else ("avertissement" if not enough else "info"),
                          f"{n} observations pour {p_ - 1} variable(s) explicative(s)"
                          + ("" if enough else " : règle usuelle de 10 observations par variable non respectée.")))
    if n <= p_ + 2:
        r.bloque = True
        return r
    beta, *_ = np.linalg.lstsq(X, y, rcond=None)
    fitted = X @ beta
    resid = y - fitted
    dof = n - p_
    sigma2 = float(resid @ resid / dof)
    try:
        xtx_inv = np.linalg.inv(X.T @ X)
    except np.linalg.LinAlgError as e:
        raise RecipeError("Variables explicatives redondantes (colinéarité parfaite) : retirez-en une.") from e
    se = np.sqrt(np.diag(xtx_inv) * sigma2)
    tvals = beta / se
    pvals = 2 * st.t.sf(np.abs(tvals), dof)
    tcrit = st.t.ppf(0.975, dof)
    ss_tot = float(np.sum((y - y.mean()) ** 2))
    r2 = 1 - float(resid @ resid) / ss_tot if ss_tot else 0.0
    r2a = 1 - (1 - r2) * (n - 1) / dof
    fstat = (r2 / (p_ - 1)) / ((1 - r2) / dof) if p_ > 1 and r2 < 1 else float("nan")
    fp_ = float(st.f.sf(fstat, p_ - 1, dof)) if math.isfinite(fstat) else float("nan")
    # conditions
    nres = normality(resid, "résidus")
    r.checks.append(nres)
    # Breusch-Pagan
    e2 = resid ** 2
    g, *_ = np.linalg.lstsq(X, e2, rcond=None)
    r2_aux = 1 - float(np.sum((e2 - X @ g) ** 2)) / float(np.sum((e2 - e2.mean()) ** 2) or 1)
    bp_p = float(st.chi2.sf(n * r2_aux, p_ - 1)) if p_ > 1 else 1.0
    homo = bp_p >= ALPHA
    r.checks.append(Check("Variance constante des résidus", homo, "avertissement" if not homo else "info",
                          f"Test de Breusch-Pagan {fpe(bp_p)} : "
                          + ("la dispersion des erreurs change avec les valeurs prédites (les p-values sont moins fiables)."
                             if not homo else "dispersion des erreurs stable.")))
    # VIF
    vifs = []
    for j in range(1, p_):
        others = np.delete(X, j, axis=1)
        gj, *_ = np.linalg.lstsq(others, X[:, j], rcond=None)
        ss = float(np.sum((X[:, j] - X[:, j].mean()) ** 2))
        r2j = 1 - float(np.sum((X[:, j] - others @ gj) ** 2)) / ss if ss else 0.0
        vifs.append(1 / (1 - r2j) if r2j < 1 else float("inf"))
    worst = max(vifs) if vifs else 1.0
    r.checks.append(Check("Colinéarité", worst < 5, "avertissement" if worst >= 5 else "info",
                          f"VIF maximal = {fr(worst, 1)}" + (" : des variables explicatives se recoupent, leurs effets sont "
                                                             "difficiles à séparer." if worst >= 5 else " (correct).")))
    h = np.einsum("ij,jk,ik->i", X, xtx_inv, X)
    cook = (resid ** 2 / (p_ * sigma2)) * h / (1 - h) ** 2
    infl = int(np.sum(cook > 4 / n))
    r.checks.append(Check("Points influents", infl <= max(1, 0.05 * n), "avertissement" if infl > max(1, 0.05 * n) else "info",
                          f"{infl} observation(s) pèsent fortement sur le résultat (distance de Cook > 4/n)."))
    test = force or "ols"
    r.test = test
    r.test_label = "Régression linéaire (moindres carrés)"
    if not nres.ok and n < 50:
        r.bloque = True
        r.alternative = None
        r.checks.append(Check("Conseil", False, "info", "Pour des comptages ou des valeurs très asymétriques, une "
                              "transformation (LOG1P dans une formule) ou un modèle linéaire généralisé est plus adapté."))
    r.resultats = [{"nom": "R²", "valeur": f"{r2:.1%}"}, {"nom": "R² ajusté", "valeur": f"{r2a:.1%}"},
                   {"nom": "F global", "valeur": f"{fr(fstat)} ({fpe(fp_)})"}, {"nom": "n", "valeur": fr(n)}]
    r.tableaux.append({"titre": "Coefficients", "colonnes": ["Terme", "Estimation", "IC 95 %", "p", "Significatif ?"],
                       "lignes": [[nm, fr(float(b)), f"[{fr(float(b - tcrit * s))} ; {fr(float(b + tcrit * s))}]", fp(float(pv)),
                                   "oui" if pv < ALPHA else "non"] for nm, b, s, pv in zip(names, beta, se, pvals)]})
    sig = [(nm, b) for nm, b, pv in zip(names[1:], beta[1:], pvals[1:]) if pv < ALPHA]
    r.interpretation = [f"Le modèle explique {r2:.0%} des variations de « {yname} »."]
    for nm, b in sig[:8]:
        if " = " in nm:
            r.interpretation.append(f"{nm} : « {yname} » est en moyenne {'plus élevé' if b > 0 else 'plus faible'} de {fr(abs(float(b)))}, "
                                    "à autres variables égales.")
        else:
            r.interpretation.append(f"Quand « {nm} » augmente de 1, « {yname} » {'augmente' if b > 0 else 'diminue'} en moyenne de "
                                    f"{fr(abs(float(b)))}, à autres variables égales.")
    if not sig:
        r.interpretation.append("Aucune variable explicative n'a d'effet statistiquement significatif.")
    idx = np.random.default_rng(0).choice(n, min(n, 5000), replace=False)
    r.graph = {"type": "residus", "x": fitted[idx].tolist(), "y": resid[idx].tolist(), "xname": "Valeurs prédites", "yname": "Résidus"}
    r.limites = ["Une relation dans un modèle n'est pas une preuve de causalité.",
                 "Le modèle ne vaut que dans la plage des valeurs observées : pas d'extrapolation."] + COMMON_LIMITS[1:]
    return r


# --------------------------------------------------------------------------- catalogue

ANALYSES = {
    "comparer_groupes": {
        "titre": "Comparer une mesure entre groupes",
        "question": "Les débarquements, prix, tailles… diffèrent-ils entre engins, ports, années ?",
        "variables": [{"role": "y", "label": "Mesure (numérique)", "type": "num"},
                      {"role": "groupe", "label": "Groupes (catégories)", "type": "cat"}],
        "tests": {"t_welch": "Test t de Welch", "mann_whitney": "Mann-Whitney", "anova": "ANOVA",
                  "welch_anova": "ANOVA de Welch", "kruskal": "Kruskal-Wallis"},
    },
    "association": {
        "titre": "Lien entre deux catégories",
        "question": "L'engin dépend-il du quartier ? Le métier de la saison ?",
        "variables": [{"role": "x", "label": "Première variable (catégories)", "type": "cat"},
                      {"role": "y", "label": "Seconde variable (catégories)", "type": "cat"}],
        "tests": {"chi2": "χ² d'indépendance", "fisher": "Test exact de Fisher (2×2)"},
    },
    "correlation": {
        "titre": "Relation entre deux mesures",
        "question": "Le prix baisse-t-il quand les volumes augmentent ? La CPUE suit-elle la durée de marée ?",
        "variables": [{"role": "x", "label": "Première mesure", "type": "num"},
                      {"role": "y", "label": "Seconde mesure", "type": "num"}],
        "tests": {"pearson": "Pearson", "spearman": "Spearman"},
    },
    "regression": {
        "titre": "Expliquer une mesure par plusieurs facteurs",
        "question": "Quels facteurs (engin, mois, longueur du navire…) expliquent les captures ?",
        "variables": [{"role": "y", "label": "Mesure à expliquer", "type": "num"},
                      {"role": "x", "label": "Facteurs explicatifs", "type": "any", "multiple": True}],
        "tests": {"ols": "Régression linéaire"},
    },
}


def run(con, plan, spec: dict, filters_sql: str = "") -> Result:
    kind = spec.get("analyse")
    if kind not in ANALYSES:
        raise RecipeError("Analyse inconnue.")
    v = spec.get("variables") or {}
    force = spec.get("test") or None
    if force and force not in ANALYSES[kind]["tests"]:
        raise RecipeError("Test inconnu pour cette analyse.")
    schema = plan.schema
    if kind == "comparer_groupes":
        y, g = v.get("y"), v.get("groupe")
        _need_num(schema, y)
        data, total, n = fetch(con, plan.sql, schema, [y, g], filters_sql)
        res = compare_groups(data[y], data[g].astype(str), y, g, force)
    elif kind == "association":
        x, y = v.get("x"), v.get("y")
        data, total, n = fetch(con, plan.sql, schema, [x, y], filters_sql)
        res = association(data[x].astype(str), data[y].astype(str), x, y, force)
    elif kind == "correlation":
        x, y = v.get("x"), v.get("y")
        _need_num(schema, x)
        _need_num(schema, y)
        data, total, n = fetch(con, plan.sql, schema, [x, y], filters_sql)
        res = correlation(data[x], data[y], x, y, force)
    else:
        y, xs = v.get("y"), v.get("x") or []
        if isinstance(xs, str):
            xs = [xs]
        if not xs:
            raise RecipeError("Choisissez au moins un facteur explicatif.")
        _need_num(schema, y)
        cat = {x for x in xs if x in schema and not is_numeric_type(schema[x])}
        data, total, n = fetch(con, plan.sql, schema, [y] + xs, filters_sql)
        for c in cat:
            data[c] = data[c].astype(str)
        res = regression(data, y, xs, cat, force)
    res.effectifs.update({"lignes_total": int(total), "lignes_utilisees": int(n)})
    if total > n:
        res.checks.insert(0, Check("Valeurs manquantes", True, "avertissement" if (total - n) / max(total, 1) > 0.1 else "info",
                                   f"{total - n} ligne(s) sur {total} ignorée(s) car une des variables est vide."))
    return res


def _need_num(schema, col):
    if col not in schema:
        raise RecipeError(f"Colonne inconnue : {col}.")
    if not is_numeric_type(schema[col]):
        raise RecipeError(f"« {col} » n'est pas numérique : convertissez son type d'abord.")


def method_md(res: dict, spec: dict, dataset_name: str, author: str, justification: str | None) -> str:
    L = [f"# Fiche méthode statistique : {res['titre']}", "",
         f"- **Jeu de données** : {dataset_name} (voir sa fiche méthode pour les traitements)",
         f"- **Analyste** : {author}", f"- **Test** : {res['test_label']}",
         f"- **Observations utilisées** : {res['effectifs'].get('lignes_utilisees')} sur {res['effectifs'].get('lignes_total')}"]
    if spec.get("filtres_desc"):
        L.append(f"- **Filtre** : {spec['filtres_desc']}")
    L += ["", "## Vérification des conditions", ""]
    for c in res["checks"]:
        mark = "✅" if c["ok"] else {"bloquant": "⛔", "avertissement": "⚠️"}.get(c["niveau"], "ℹ️")
        L.append(f"- {mark} **{c['nom']}** : {c['message']}")
    if res["bloque"]:
        L += ["", f"> ⛔ Une condition bloquante n'est pas remplie. Analyse menée malgré tout. Justification : "
                  f"{justification or '(non renseignée)'}"]
    L += ["", "## Résultats", ""]
    for r in res["resultats"]:
        L.append(f"- **{r['nom']}** : {r['valeur']}")
    for t in res["tableaux"]:
        L += ["", f"**{t['titre']}**", "", "| " + " | ".join(map(str, t["colonnes"])) + " |",
              "|" + "---|" * len(t["colonnes"])]
        L += ["| " + " | ".join(map(str, row)) + " |" for row in t["lignes"]]
    L += ["", "## Interprétation", ""] + [f"- {p}" for p in res["interpretation"]]
    L += ["", "## Limites", ""] + [f"- {p}" for p in res["limites"]]
    L += ["", f"Seuil de significativité : 5 %. Calculs : SciPy {__import__('scipy').__version__}."]
    return "\n".join(L)
