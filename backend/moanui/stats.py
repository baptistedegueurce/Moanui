"""Statistiques guidées : vérification des conditions, test adapté, interprétation en français.

Principes :
- chaque analyse vérifie ses conditions d'application avant de conclure ;
- si une condition bloquante n'est pas remplie, le résultat est bloqué et une
  alternative est proposée ; l'utilisateur peut passer outre en le justifiant
  (la justification figure dans la fiche méthode) ;
- l'interprétation est rédigée pour des non-statisticiens, avec ses limites.
"""

from __future__ import annotations

import json
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
        return "–"
    if isinstance(x, (int, np.integer)):
        return f"{int(x):,}".replace(",", " ")
    x = float(x)
    if abs(x) >= 1e6 or (abs(x) < 1e-3 and x != 0):
        return f"{x:.{d}g}".replace(".", ",")
    s = f"{x:,.{d}f}".replace(",", " ")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s.replace(".", ",")


def pc(x: float, d: int = 0) -> str:
    """Pourcentage à la française : « 12,5 % »."""
    if x is None or not math.isfinite(x):
        return "–"
    return f"{fr(100 * x, d)}\u202f%"


def fp(p: float) -> str:
    if p is None or not math.isfinite(p):
        return "–"
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
    fd: dict = field(default_factory=dict)  # données des figures de la fiche méthode (non renvoyées à l'interface)
    rapport: list[str] = field(default_factory=list)  # résultats au format normalisé (statistique, ddl, p, effet, IC)
    resume: str = ""  # résumé de type « abstract »
    discussion: list[str] = field(default_factory=list)  # avec appels de citation {{clé}}
    sci: dict = field(default_factory=dict)  # p, taille d'effet qualifiée, n, bootstrap (pour le résumé / la discussion)

    def as_dict(self):
        return {
            "analyse": self.analyse, "titre": self.titre, "test": self.test, "test_label": self.test_label,
            "checks": [c.as_dict() for c in self.checks], "bloque": self.bloque, "alternative": self.alternative,
            "resultats": self.resultats, "tableaux": self.tableaux, "interpretation": self.interpretation,
            "limites": self.limites, "graph": self.graph, "effectifs": self.effectifs,
            "rapport": self.rapport, "resume": cites_text(self.resume),
            "discussion": [cites_text(d) for d in self.discussion],
            "resume_src": self.resume, "discussion_src": self.discussion,
        }


def cites_text(text: str, cite=None) -> str:
    """Remplace les appels {{clé1,clé2}} par « (Auteur, année) » (ou par la fonction cite d'une fiche)."""
    import re as _re

    from .biblio import REFS
    from .fiche import _short

    def rep(m):
        keys = [k.strip() for k in m.group(1).split(",")]
        if cite:
            return cite(*keys)
        return "(" + " ; ".join(_short(REFS[k]) for k in keys if k in REFS) + ")"

    return _re.sub(r"\{\{([^}]+)\}\}", rep, text or "")


# --------------------------------------------------------------------------- intervalles par bootstrap
BOOT_B = 400
BOOT_SEED = 2026


def boot_groups(fn, groups, B: int | None = None):
    """IC 95 % percentile d'une statistique de plusieurs groupes, rééchantillonnés séparément (graine fixe)."""
    n = sum(len(g) for g in groups)
    B = B or (BOOT_B if n <= 50000 else 150)
    rng = np.random.default_rng(BOOT_SEED)
    vals = []
    for _ in range(B):
        try:
            v = fn(*[g[rng.integers(0, len(g), len(g))] for g in groups])
        except Exception:  # noqa: BLE001
            continue
        if v is not None and math.isfinite(v):
            vals.append(v)
    if len(vals) < 0.8 * B:
        return None
    return float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5))


def boot_rows(fn, n: int, B: int | None = None):
    """IC 95 % percentile d'une statistique calculée sur des lignes rééchantillonnées (indices)."""
    B = B or (BOOT_B if n <= 50000 else 150)
    rng = np.random.default_rng(BOOT_SEED)
    vals = []
    for _ in range(B):
        try:
            v = fn(rng.integers(0, n, n))
        except Exception:  # noqa: BLE001
            continue
        if v is not None and math.isfinite(v):
            vals.append(v)
    if len(vals) < 0.8 * B:
        return None
    return float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5))


def ci_txt(ci, d: int = 3) -> str:
    return f"[{fr(ci[0], d)} ; {fr(ci[1], d)}]" if ci else "non calculable"


def p_txt(p: float) -> str:
    return "p < 0,001" if p < 0.001 else f"p = {fr(p, 3)}"


def eps2_kw(*groups) -> float:
    n = sum(len(g) for g in groups)
    return float(st.kruskal(*groups).statistic) / (n - 1)


def eta2_of(*groups) -> float:
    allv = np.concatenate(groups)
    ss_t = float(np.sum((allv - allv.mean()) ** 2))
    ss_b = sum(len(x) * (np.mean(x) - allv.mean()) ** 2 for x in groups)
    return float(ss_b / ss_t) if ss_t else 0.0


def rank_biserial(a, b) -> float:
    """Corrélation rang-bisériale (Kerby, 2014) : part des paires où a > b moins part des paires où a < b."""
    return float(2 * st.mannwhitneyu(a, b, alternative="two-sided").statistic / (len(a) * len(b)) - 1)


def cohen_d(a, b) -> float:
    sp = math.sqrt((np.var(a, ddof=1) + np.var(b, ddof=1)) / 2)
    return float((np.mean(a) - np.mean(b)) / sp) if sp else 0.0


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
                                   fr(float(np.std(x, ddof=1))) if len(x) > 1 else "–", fr(float(np.min(x))), fr(float(np.max(x)))]
                                  for lv, x in zip(levels, groups)]})
    r.graph = {"type": "boites", "groupes": [str(lv) for lv in levels],
               "valeurs": [x[:5000].tolist() for x in groups], "y": yname}
    r.fd = {"kind": "boites", "levels": [str(lv) for lv in levels], "groups": groups, "y": yname, "g": gname}
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
            n1, n2 = len(a), len(b)
            se_d = math.sqrt((n1 + n2) / (n1 * n2) + d ** 2 / (2 * (n1 + n2)))  # Nakagawa et Cuthill (2007)
            d_ci = (d - 1.96 * se_d, d + 1.96 * se_d)
            r.rapport = [f"t({fr(float(res.df), 1)}) = {fr(float(res.statistic), 2)}, {p_txt(res.pvalue)} ; différence des "
                         f"moyennes = {fr(means[0] - means[1])} [IC 95 % {fr(ci.low)} ; {fr(ci.high)}] ; d de Cohen = "
                         f"{fr(d, 2)} [IC 95 % {fr(d_ci[0], 2)} ; {fr(d_ci[1], 2)}]."]
            r.sci = {"p": float(res.pvalue), "effet": effect_words(d, (0.2, 0.5, 0.8)), "n": n1 + n2, "boot": False}
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
            rb = rank_biserial(a, b)
            r.test_label = "Test de Mann-Whitney (comparaison de deux distributions, sans hypothèse de normalité)"
            p = res.pvalue
            rb_ci = boot_groups(rank_biserial, [a, b])
            md_ci = boot_groups(lambda u, v: float(np.median(u) - np.median(v)), [a, b])
            r.rapport = [f"U = {fr(float(res.statistic), 1)}, {p_txt(p)} ; corrélation rang-bisériale r = {fr(rb, 2)} "
                         f"[IC 95 % {ci_txt(rb_ci, 2)[1:-1]}] ; différence des médianes = {fr(meds[0] - meds[1])} "
                         f"[IC 95 % {ci_txt(md_ci)[1:-1]}] (n = {fr(len(a))} et {fr(len(b))})."]
            r.sci = {"p": float(p), "effet": effect_words(rb, (0.1, 0.3, 0.5)), "n": len(a) + len(b), "boot": True}
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
            e_ci = boot_groups(eta2_of, groups)
            r.rapport = [f"F({k - 1} ; {n_tot - k}) = {fr(float(res.statistic), 2)}, {p_txt(p)} ; η² = {fr(eta2, 3)} "
                         f"[IC 95 % {ci_txt(e_ci)[1:-1]}] (N = {fr(n_tot)}, {k} groupes)."]
            r.sci = {"p": float(p), "effet": effect_words(math.sqrt(eta2), (0.1, 0.25, 0.4)), "n": n_tot, "boot": True}
        elif test == "welch_anova":
            stat, p, df1, df2 = welch_anova(groups)
            r.test_label = "ANOVA de Welch (moyennes, variances inégales)"
            stat_txt = f"F = {fr(stat)} (ddl {fr(df1, 1)} ; {fr(df2, 1)})"
            eta2 = eta2_of(*groups)
            e_ci = boot_groups(eta2_of, groups)
            eff = f"η² = {fr(eta2, 3)} (descriptif, {effect_words(math.sqrt(eta2), (0.1, 0.25, 0.4))})"
            r.rapport = [f"F de Welch({fr(df1, 0)} ; {fr(df2, 1)}) = {fr(stat, 2)}, {p_txt(p)} ; η² = {fr(eta2, 3)} "
                         f"[IC 95 % {ci_txt(e_ci)[1:-1]}] (N = {fr(n_tot)}, {k} groupes)."]
            r.sci = {"p": float(p), "effet": effect_words(math.sqrt(eta2), (0.1, 0.25, 0.4)), "n": n_tot, "boot": True}
        else:
            res = st.kruskal(*groups)
            eps2 = float(res.statistic) / (n_tot - 1)  # ε² des rangs (Tomczak et Tomczak, 2014)
            r.test_label = "Test de Kruskal-Wallis (plusieurs distributions, sans hypothèse de normalité)"
            stat_txt, p = f"H = {fr(float(res.statistic))}", res.pvalue
            eff = f"ε² = {fr(eps2, 3)} ({effect_words(math.sqrt(max(eps2, 0)), (0.1, 0.25, 0.4))})"
            e_ci = boot_groups(eps2_kw, groups)
            r.rapport = [f"H({k - 1}) = {fr(float(res.statistic), 2)}, {p_txt(p)} ; ε² = {fr(eps2, 3)} "
                         f"[IC 95 % {ci_txt(e_ci)[1:-1]}] (N = {fr(n_tot)}, {k} groupes)."]
            r.sci = {"p": float(p), "effet": effect_words(math.sqrt(max(eps2, 0)), (0.1, 0.25, 0.4)), "n": n_tot,
                     "boot": True}
        r.resultats = [{"nom": "Statistique", "valeur": stat_txt}, {"nom": "p", "valeur": fp(p)},
                       {"nom": "Taille d'effet", "valeur": eff}]
        loc = means if parametric else meds
        word = "moyenne" if parametric else "médiane"
        hi_i, lo_i = int(np.argmax(loc)), int(np.argmin(loc))
        r.interpretation = [
            f"{word.capitalize()} de « {yname} » la plus élevée pour « {levels[hi_i]} » ({fr(loc[hi_i])}), la plus faible pour "
            f"« {levels[lo_i]} » ({fr(loc[lo_i])}), sur {k} groupes et {fr(n_tot)} observations.",
            sig_sentence(p).replace("un tel écart", "de tels écarts entre groupes")]
        if eff != "–":
            r.interpretation.append(f"Taille d'effet : {eff}.")
        if p < ALPHA:
            pairs = pairwise(groups, levels, parametric)
            r.tableaux.append({"titre": "Comparaisons deux à deux (correction de Holm) avec taille d'effet de chaque paire",
                               "colonnes": ["Groupe A", "Groupe B", "Taille d'effet", "p ajusté", "Différent ?"],
                               "lignes": pairs})
            diff = [f"{a} / {b}" for a, b, _, _, ok in pairs if ok == "oui"]
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
    """Comparaisons deux à deux (Welch ou Mann-Whitney), p corrigées par Holm, avec la taille d'effet de chaque paire
    (d de Cohen ou corrélation rang-bisériale)."""
    pairs, ps, effs = [], [], []
    for i in range(len(groups)):
        for j in range(i + 1, len(groups)):
            if parametric:
                p = st.ttest_ind(groups[i], groups[j], equal_var=False).pvalue
                e = cohen_d(groups[i], groups[j])
                effs.append(f"d = {fr(e, 2)} ({effect_words(e, (0.2, 0.5, 0.8))})")
            else:
                p = st.mannwhitneyu(groups[i], groups[j], alternative="two-sided").pvalue
                e = rank_biserial(groups[i], groups[j])
                effs.append(f"r = {fr(e, 2)} ({effect_words(e, (0.1, 0.3, 0.5))})")
            pairs.append((str(levels[i]), str(levels[j])))
            ps.append(float(p))
    adj = holm(ps)
    return [[a, b, ef, fp(p), "oui" if p < ALPHA else "non"] for (a, b), ef, p in zip(pairs, effs, adj)]


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
                          f"{pc(low, 0)} des cases ont un effectif attendu < 5" + (" et certaines < 1" if tiny else "") + "."
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
        try:
            oci = st.contingency.odds_ratio(table).confidence_interval(0.95)
            oci = (float(oci.low), float(oci.high))
        except Exception:  # noqa: BLE001
            oci = None
        r.resultats = [{"nom": "Rapport des cotes", "valeur": fr(float(odds))}, {"nom": "p", "valeur": fp(p)}]
        r.rapport = [f"Test exact de Fisher : rapport des cotes = {fr(float(odds), 2)} [IC 95 % {ci_txt(oci, 2)[1:-1]}], "
                     f"{p_txt(p)} (N = {fr(int(n))})."]
        r.sci = {"p": float(p), "effet": None, "n": int(n), "boot": False}
    else:
        r.test_label = "Test du χ² d'indépendance"
        xcode = np.array([xs.index(v) for v in x.tolist()]) if len(x) <= 200000 else None
        ycode = np.array([ys.index(v) for v in y.tolist()]) if xcode is not None else None

        def cramer(ix):
            tb = np.zeros(table.shape)
            np.add.at(tb, (xcode[ix], ycode[ix]), 1)
            tb = tb[tb.sum(axis=1) > 0][:, tb.sum(axis=0) > 0]
            if min(tb.shape) < 2:
                return None
            c2 = st.chi2_contingency(tb, correction=False)[0]
            return math.sqrt(c2 / (tb.sum() * (min(tb.shape) - 1)))

        v_ci = boot_rows(cramer, len(x)) if xcode is not None else None
        r.rapport = [f"χ²({dof}, N = {fr(int(n))}) = {fr(float(chi2), 2)}, {p_txt(p)} ; V de Cramér = {fr(v, 2)} "
                     f"[IC 95 % {ci_txt(v_ci, 2)[1:-1]}]."]
        r.sci = {"p": float(p), "effet": effect_words(v, (0.1, 0.3, 0.5)), "n": int(n), "boot": v_ci is not None}
        r.resultats = [{"nom": "χ²", "valeur": fr(float(chi2))}, {"nom": "ddl", "valeur": str(dof)},
                       {"nom": "p", "valeur": fp(p)},
                       {"nom": "V de Cramér", "valeur": f"{fr(v, 2)} ({effect_words(v, (0.1, 0.3, 0.5))})"}]
    r.tableaux.append({"titre": "Tableau croisé (effectifs observés)", "colonnes": [xname + " \\ " + yname] + [str(b) for b in ys],
                       "lignes": [[str(a)] + [int(c) for c in row] for a, row in zip(xs, table)]})
    resid = (table - expected) / np.sqrt(np.where(expected > 0, expected, 1))
    r.fd = {"kind": "empile", "xs": [str(a) for a in xs], "ys": [str(b) for b in ys], "table": table, "x": xname, "y": yname,
            "resid": resid}
    strong = [(str(xs[i]), str(ys[j]), resid[i, j]) for i in range(len(xs)) for j in range(len(ys)) if abs(resid[i, j]) > 2]
    r.interpretation = [sig_sentence(p).replace("un tel écart", "une telle répartition") if p < ALPHA else
                        f"Rien n'indique que « {xname} » et « {yname} » soient liés ({fpe(p)})."]
    if test == "chi2":
        r.interpretation.append(f"Intensité du lien (V de Cramér) : {fr(v, 2)}, soit un lien {effect_words(v, (0.1, 0.3, 0.5))} "
                                f"({fr(int(n))} observations, tableau {table.shape[0]} × {table.shape[1]}).")
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
                       {"nom": "p", "valeur": fp(p)}, {"nom": "Part de variance commune (r²)", "valeur": f"{pc(coef ** 2, 0)}"}]
        r.rapport = [f"r({n - 2}) = {fr(coef, 2)} [IC 95 % {fr(ci.low, 2)} ; {fr(ci.high, 2)}], {p_txt(p)} ; r² = "
                     f"{pc(coef ** 2, 1)} de variance commune."]
    else:
        res = st.spearmanr(x, y)
        coef, p = float(res.statistic), float(res.pvalue)
        r.test_label = "Corrélation de Spearman (relation monotone, sur les rangs)"
        # IC par la transformation de Fisher avec l'erreur type de Bonett et Wright (2000)
        if n > 4 and abs(coef) < 1:
            se = math.sqrt((1 + coef ** 2 / 2) / (n - 3))
            zc = math.atanh(coef)
            rci = (math.tanh(zc - 1.96 * se), math.tanh(zc + 1.96 * se))
        else:
            rci = None
        r.resultats = [{"nom": "ρ", "valeur": fr(coef, 2)}, {"nom": "IC 95 %", "valeur": ci_txt(rci, 2)},
                       {"nom": "p", "valeur": fp(p)}]
        r.rapport = [f"ρ de Spearman({n - 2}) = {fr(coef, 2)} [IC 95 % {ci_txt(rci, 2)[1:-1]}], {p_txt(p)}."]
    r.sci = {"p": float(p), "effet": effect_words(coef, (0.1, 0.3, 0.5)), "n": n, "boot": False}
    sens = "augmente" if coef > 0 else "diminue"
    r.interpretation = [
        f"Quand « {xname} » augmente, « {yname} » {sens} en tendance : lien {effect_words(coef, (0.1, 0.3, 0.5))} "
        f"({'r' if test == 'pearson' else 'ρ'} = {fr(coef, 2)}).", sig_sentence(p)]
    idx = np.random.default_rng(0).choice(n, min(n, 5000), replace=False)
    r.graph = {"type": "nuage", "x": x[idx].tolist(), "y": y[idx].tolist(), "xname": xname, "yname": yname}
    slope, icpt = np.polyfit(x, y, 1) if np.ptp(x) else (0.0, float(np.mean(y)))
    r.fd = {"kind": "nuage", "x": x, "y": y, "xname": xname, "yname": yname,
            "line": (float(icpt), float(slope)) if test == "pearson" else None}
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
    r.resultats = [{"nom": "R²", "valeur": f"{pc(r2, 1)}"}, {"nom": "R² ajusté", "valeur": f"{pc(r2a, 1)}"},
                   {"nom": "F global", "valeur": f"{fr(fstat)} ({fpe(fp_)})"}, {"nom": "n", "valeur": fr(n)}]
    r.rapport = [f"F({p_ - 1} ; {dof}) = {fr(fstat, 2)}, {p_txt(fp_) if math.isfinite(fp_) else 'p non calculable'} ; "
                 f"R² = {fr(r2, 3)}, R² ajusté = {fr(r2a, 3)} ; erreur type résiduelle = {fr(math.sqrt(sigma2))} (n = {n})."]
    r.sci = {"p": fp_ if math.isfinite(fp_) else 1.0, "effet": effect_words(math.sqrt(max(r2, 0)), (0.1, 0.3, 0.5)),
             "n": n, "boot": False}
    r.tableaux.append({"titre": "Coefficients", "colonnes": ["Terme", "Estimation", "IC 95 %", "p", "Significatif ?"],
                       "lignes": [[nm, fr(float(b)), f"[{fr(float(b - tcrit * s))} ; {fr(float(b + tcrit * s))}]", fp(float(pv)),
                                   "oui" if pv < ALPHA else "non"] for nm, b, s, pv in zip(names, beta, se, pvals)]})
    sig = [(nm, b) for nm, b, pv in zip(names[1:], beta[1:], pvals[1:]) if pv < ALPHA]
    r.interpretation = [f"Le modèle explique {pc(r2, 0)} des variations de « {yname} »."]
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
    r.fd = {"kind": "residus", "fitted": fitted, "resid": resid, "y": yname, "cook": cook}
    r.limites = ["Une relation dans un modèle n'est pas une preuve de causalité.",
                 "Le modèle ne vaut que dans la plage des valeurs observées : pas d'extrapolation."] + COMMON_LIMITS[1:]
    return r


# --------------------------------------------------------------------------- résumé et discussion


def finalize(r: Result) -> Result:
    """Résumé (type « abstract ») et discussion conditionnés aux résultats obtenus, jamais génériques."""
    sci = r.sci
    if not sci or not r.rapport:
        return r
    p, eff, n = sci.get("p", 1.0), sci.get("effet"), sci.get("n", 0)
    signif = p < ALPHA
    concl = r.interpretation[0] if r.interpretation else ""
    r.resume = (f"{r.titre}. Méthode : {r.test_label[0].lower() + r.test_label[1:] if r.test_label else r.test} sur "
                f"{fr(n)} observations. Résultat : {r.rapport[0]} {concl}"
                + (" Le résultat est statistiquement significatif au seuil de 5 %" if signif else
                   " Le résultat n'est pas statistiquement significatif au seuil de 5 %")
                + (f", pour un effet {eff}." if eff else "."))
    d = []
    if signif and eff in ("négligeable", "faible"):
        d.append(f"L'effet est statistiquement significatif mais {eff} : la significativité tient en partie à l'effectif "
                 f"({fr(n)} observations). Avec de grands échantillons, des écarts minimes deviennent significatifs ; c'est la "
                 "taille d'effet et son intervalle de confiance qui disent si l'écart compte en pratique {{lin2013,nakagawa2007}}.")
    elif signif and eff in ("moyen", "fort"):
        d.append(f"L'effet est à la fois statistiquement significatif et {eff} : l'écart est net. Sa portée pratique "
                 "se juge sur les valeurs elles-mêmes (tableaux), au regard des enjeux de gestion {{nakagawa2007}}.")
    elif signif:
        d.append("Le résultat est statistiquement significatif ; son importance pratique se juge sur l'ampleur des effets "
                 "estimés et de leurs intervalles de confiance {{nakagawa2007}}.")
    else:
        d.append("L'absence de significativité ne démontre pas l'absence d'effet : les intervalles de confiance indiquent "
                 "les valeurs encore compatibles avec les données ; un effectif plus grand pourrait révéler un effet "
                 "faible {{wasserstein2016,nakagawa2007}}.")
    if r.bloque:
        d.append("Les conditions d'application n'étaient pas toutes réunies (analyse menée à la demande de l'analyste) : les "
                 "p-values et intervalles sont approximatifs et doivent être interprétés avec prudence.")
    d.append("Les lignes d'un même navire, d'une même marée ou d'un même jour ne sont pas des réplicats indépendants : "
             "traiter chaque ligne comme une observation indépendante (pseudo-réplication) rend les tests trop optimistes. "
             "Agréger à l'unité d'échantillonnage pertinente, ou utiliser un modèle à effet aléatoire, limite ce biais "
             "{{hurlbert1984,zuur2009}}.")
    if sci.get("glm"):
        d.append(f"Le modèle explique {pc(sci.get('expl', 0), 0)} de la déviance. Pour une standardisation de CPUE, l'indice "
                 "obtenu reflète l'abondance seulement si l'effort, la zone et la saison sont correctement pris en compte et "
                 "si la capturabilité est stable dans le temps {{maunder2004}}. La démarche suit le protocole de "
                 "présentation des modèles de régression de Zuur et Ieno {{zuur2016}}.")
    if sci.get("boot"):
        d.append(f"Les intervalles de confiance des tailles d'effet sont obtenus par bootstrap percentile ({BOOT_B} "
                 f"rééchantillonnages, graine {BOOT_SEED} : résultat reproductible) {{{{efron1993}}}}.")
    r.discussion = d
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
    "glm": {
        "titre": "Modéliser des captures, comptages ou présences (GLM)",
        "question": "Standardiser une CPUE, expliquer des comptages ou la présence d'une espèce selon l'année, l'engin, la zone…",
        "variables": [{"role": "y", "label": "Mesure à modéliser (captures, nombre, 0 / 1)", "type": "num"},
                      {"role": "x", "label": "Facteurs explicatifs", "type": "any", "multiple": True},
                      {"role": "effort", "label": "Effort (facultatif : jours de mer, heures, marées…)", "type": "num",
                       "optional": True}],
        "tests": {"poisson": "Poisson (comptages)", "quasi_poisson": "Quasi-Poisson",
                  "binomiale_negative": "Binomiale négative (comptages dispersés)",
                  "gamma": "Gamma (valeurs positives : CPUE, poids)", "logistique": "Logistique (présence / absence)"},
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
    elif kind == "glm":
        y, xs, eff = v.get("y"), v.get("x") or [], v.get("effort") or None
        if isinstance(xs, str):
            xs = [xs]
        if not xs:
            raise RecipeError("Choisissez au moins un facteur explicatif.")
        _need_num(schema, y)
        if eff:
            _need_num(schema, eff)
        if y in xs or (eff and (eff in xs or eff == y)):
            raise RecipeError("Une même colonne ne peut pas être à la fois mesure, facteur et effort.")
        cat = {x for x in xs if x in schema and not is_numeric_type(schema[x])}
        data, total, n = fetch(con, plan.sql, schema, [y] + xs + ([eff] if eff else []), filters_sql)
        if n == 0:
            raise RecipeError("Aucune ligne complète pour ces variables.")
        for c in cat:
            data[c] = data[c].astype(str)
        res = glm_analysis(data, y, xs, cat, eff, force)
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
    finalize(res)
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


# --------------------------------------------------------------------------- fiche méthode

TEST_INFO: dict[str, tuple[str, tuple[str, ...]]] = {
    "t_welch": ("Le test t de Welch compare les moyennes de deux groupes sans supposer que leurs variances sont égales ; "
                "il est recommandé par défaut à la place du test t de Student, dont il ne diffère presque pas quand les "
                "variances sont égales. La taille d'effet est le d de Cohen (écart des moyennes en écarts-types), donné avec son intervalle de confiance "
                "à 95 % (approximation normale de son erreur type)",
                ("welch1947", "delacre2017", "cohen1988", "nakagawa2007")),
    "mann_whitney": ("Le test de Mann-Whitney compare deux distributions à partir des rangs des valeurs : il ne suppose pas "
                     "de loi normale et résiste aux valeurs extrêmes. Il teste si une valeur tirée d'un groupe tend à être "
                     "plus grande qu'une valeur tirée de l'autre. La taille d'effet est la corrélation rang-bisériale (part des paires "
                     "favorables moins part des paires défavorables), avec la différence des médianes ; leurs intervalles de "
                     "confiance à 95 % sont estimés par bootstrap",
                     ("mannwhitney1947", "kerby2014", "efron1993")),
    "anova": ("L'analyse de variance (ANOVA) à un facteur compare les moyennes de plusieurs groupes en supposant des "
              "distributions normales de même variance. La taille d'effet η² est la part de la variabilité totale expliquée "
              "par les groupes (intervalle de confiance par bootstrap). Si le test est significatif, les groupes sont comparés "
              "deux à deux (tests t de Welch, d de Cohen pour chaque paire) avec correction de Holm",
              ("cohen1988", "holm1979", "efron1993")),
    "welch_anova": ("L'ANOVA de Welch compare les moyennes de plusieurs groupes sans supposer l'égalité des variances. Si "
                    "elle est significative, les groupes sont comparés deux à deux (tests t de Welch) avec correction de Holm",
                    ("welch1951", "holm1979")),
    "kruskal": ("Le test de Kruskal-Wallis compare plusieurs distributions à partir des rangs, sans hypothèse de normalité. "
                "La taille d'effet ε² = H / (n − 1) est fondée sur les rangs, avec un intervalle de confiance par bootstrap. Si "
                "le test est significatif, les groupes sont comparés deux à deux (Mann-Whitney, corrélation rang-bisériale "
                "pour chaque paire) avec correction de Holm",
                ("kruskal1952", "tomczak2014", "mannwhitney1947", "kerby2014", "holm1979", "efron1993")),
    "chi2": ("Le test du χ² d'indépendance compare les effectifs observés du tableau croisé aux effectifs attendus si les "
             "deux variables étaient indépendantes. Il suppose des effectifs attendus suffisants (au moins 5 dans 80 % "
             "des cases, aucun sous 1). L'intensité du lien est mesurée par le V de Cramér (0 = aucun lien, 1 = lien total) ; "
             "les résidus standardisés supérieurs à 2 en valeur absolue désignent les combinaisons sur- ou sous-représentées. "
             "L'intervalle de confiance du V est estimé par bootstrap",
             ("cochran1954", "cramer1946", "efron1993")),
    "fisher": ("Le test exact de Fisher calcule directement la probabilité du tableau 2 × 2 observé ; il reste valable avec de "
               "petits effectifs. L'intensité du lien est donnée par le rapport des cotes", ("fisher1922",)),
    "pearson": ("Le coefficient de corrélation de Pearson mesure l'intensité d'une relation linéaire entre deux mesures "
                "(de −1 à 1) ; son test suppose des distributions proches de la normale et est sensible aux valeurs "
                "extrêmes", ("cohen1988",)),
    "spearman": ("Le coefficient de Spearman est la corrélation de Pearson calculée sur les rangs : il mesure une relation "
                 "monotone (toujours croissante ou toujours décroissante), sans hypothèse de normalité, et résiste aux valeurs "
                 "extrêmes. Son intervalle de confiance utilise la transformation de Fisher avec l'erreur type de Bonett et Wright",
                 ("spearman1904", "bonett2000")),
    "ols": ("La régression linéaire multiple (moindres carrés) estime l'effet de chaque facteur sur la mesure, à autres "
            "facteurs constants. Les facteurs à catégories sont codés par indicatrices par rapport à une modalité de "
            "référence. Les conditions vérifiées sont la normalité et la variance constante des résidus (test de "
            "Breusch-Pagan), la colinéarité entre facteurs (VIF) et l'influence de chaque observation (distance de Cook)",
            ("breusch1979", "cook1977", "zuur2010")),
    "poisson": ("Le modèle linéaire généralisé (GLM) de Poisson à lien logarithmique décrit des comptages : les effets sont "
                "multiplicatifs. Il suppose une variance égale à la moyenne ; une variance plus forte (surdispersion) rend "
                "les p-values trop optimistes. Les facteurs sont testés par rapport de vraisemblance, en retirant chacun "
                "d'eux du modèle", ("mccullagh1989", "venables2004")),
    "quasi_poisson": ("Le GLM quasi-Poisson garde la structure du modèle de Poisson mais estime un paramètre de dispersion "
                      "(variance proportionnelle à la moyenne) ; les facteurs sont testés par des tests F", ("mccullagh1989",
                                                                                                          "verhoef2007")),
    "binomiale_negative": ("Le GLM binomial négatif (lien logarithmique, variance μ + μ²/θ) décrit des comptages plus "
                           "dispersés que ne le permet la loi de Poisson, situation habituelle pour des captures. Le "
                           "paramètre θ est estimé par maximum de vraisemblance, en alternance avec les coefficients, comme "
                           "dans la fonction glm.nb de R ; les facteurs sont testés par rapport de vraisemblance à θ fixé",
                           ("venables2002", "verhoef2007", "venables2004")),
    "gamma": ("Le GLM Gamma à lien logarithmique décrit des quantités strictement positives et asymétriques (poids "
              "débarqués, CPUE positives), avec une variance qui croît comme le carré de la moyenne ; les effets sont "
              "multiplicatifs et la dispersion est estimée (tests F)", ("mccullagh1989", "venables2004")),
    "logistique": ("La régression logistique (GLM binomial, lien logit) modélise la probabilité d'un événement (présence de "
                   "l'espèce, oui / non). Les effets s'expriment en rapports de cotes", ("mccullagh1989",)),
}

CHECK_REFS = {"Normalité": ("shapiro1965",), "Égalité des variances": ("levene1960", "brown1974"),
              "Effectifs théoriques": ("cochran1954",), "Colinéarité": ("zuur2010",),
              "Variance constante des résidus": ("breusch1979",), "Points influents": ("cook1977",),
              "Surdispersion": ("verhoef2007", "zuur2009"), "Zéros": ("martin2005",),
              "Ajustement (résidus quantiles)": ("dunn1996",)}

STATUS = {True: "Respectée", "bloquant": "Non respectée (bloquante)", "avertissement": "À surveiller", "info": "Information"}


def method_fiche(res: dict, spec: dict, dataset_name: str, author: str, justification: str | None, fd: dict | None = None):
    from . import figures
    from .fiche import Fiche

    fd = fd or {}
    f = Fiche(f"Fiche méthode statistique : {res['titre']}")
    var_labels = {v["role"]: v["label"] for v in ANALYSES.get(spec.get("analyse"), {}).get("variables", [])}
    vars_ = spec.get("variables") or {}
    eff = res.get("effectifs", {})
    f.meta = [("Jeu de données", f"{dataset_name} (traitements décrits dans sa propre fiche méthode)"), ("Analyste", author),
              ("Date", __import__("datetime").datetime.now().strftime("%d/%m/%Y %H:%M"))]

    if res.get("resume_src"):
        f.h("Résumé", numbered=False)
        f.p(cites_text(res["resume_src"], f.cite))

    f.h("Question et données")
    f.p(ANALYSES.get(spec.get("analyse"), {}).get("titre", "") + ".")
    f.kv([(var_labels.get(k, k), ", ".join(v) if isinstance(v, list) else str(v)) for k, v in vars_.items() if v]
         + [("Restriction des données", spec.get("filtres_desc") or "aucune"),
            ("Observations utilisées", f"{eff.get('lignes_utilisees', '?')} sur {eff.get('lignes_total', '?')} lignes "
                                       "(lignes incomplètes pour ces variables écartées)")])

    f.h("Méthode")
    chosen = "imposé par l'analyste" if spec.get("test") else "choisi automatiquement d'après les conditions vérifiées"
    info = TEST_INFO.get(res.get("test"), ("", ()))
    f.p(f"Test retenu : **{res['test_label']}** ({chosen}). {info[0]} {f.cite(*info[1])}.".replace(" .", "."))
    f.p(f"Seuil de significativité : 5 %. Une p-value mesure la compatibilité des données avec l'absence d'effet ; elle "
        f"ne mesure ni la taille ni l'importance de l'effet, d'où le report systématique des tailles d'effet et des "
        f"intervalles de confiance {f.cite('wasserstein2016')}.")

    f.h("Conditions d'application")
    rows = []
    for c in res["checks"]:
        key = next((k for k in CHECK_REFS if c["nom"].startswith(k)), None)
        refs = f" {f.cite(*CHECK_REFS[key])}" if key else ""
        status = STATUS[True] if c["ok"] else STATUS.get(c["niveau"], c["niveau"])
        rows.append([c["nom"], status, c["message"] + refs])
    f.table(["Condition", "Statut", "Détail"], rows, "Conditions vérifiées avant l'analyse.")
    if res["bloque"]:
        f.note(f"Une condition bloquante n'est pas remplie : l'analyse a été menée malgré tout, à la demande de l'analyste. "
               f"Justification : {justification or '(non renseignée)'}.")

    f.h("Résultats")
    if res.get("rapport"):
        f.p("Résultat principal, présenté selon les recommandations de report des statistiques (statistique de test, "
            f"degrés de liberté, p exacte, taille d'effet et intervalle de confiance) {f.cite('nakagawa2007', 'zuur2016')} :")
        for line in res["rapport"]:
            f.note(line)
    if res["resultats"]:
        f.kv([(r["nom"], r["valeur"]) for r in res["resultats"]])
    for t in res["tableaux"]:
        al = "l" + "r" * (len(t["colonnes"]) - 1)
        f.table([str(c) for c in t["colonnes"]], t["lignes"], t["titre"] + ".", al)
    _figures(f, fd, figures)

    f.h("Interprétation")
    f.ul(res["interpretation"])
    if res.get("discussion_src"):
        f.h("Discussion")
        for d in res["discussion_src"]:
            f.p(cites_text(d, f.cite))
    f.h("Limites")
    f.ul(res["limites"])
    import scipy

    from . import __version__

    f.h("Reproductibilité")
    f.kv([("Logiciel", f"Moanui {__version__} ; NumPy {np.__version__} ; SciPy {scipy.__version__}"),
          ("Données", f"« {dataset_name} », résultat de sa recette (fichier brut inchangé, empreinte SHA-256 dans la fiche "
                      "du jeu)"),
          ("Paramètres", json.dumps(spec.get("variables") or {}, ensure_ascii=False)
           + (f" ; test imposé : {spec['test']}" if spec.get("test") else "")),
          ("Aléa", f"bootstrap {BOOT_B} rééchantillonnages, graine {BOOT_SEED} ; sous-échantillon de Shapiro-Wilk : graine 0"),
          ("Seuil", "α = 0,05 (bilatéral)")])
    return f


def _figures(f, fd: dict, figures) -> None:
    k = fd.get("kind")
    if k == "boites":
        f.fig("boites", figures.boxplot(fd["levels"], fd["groups"], fd["y"], fd["g"]),
              f"Distribution de « {fd['y']} » selon « {fd['g']} ». Boîte : quartiles ; trait épais : médiane ; losange : "
              "moyenne ; moustaches : 1,5 fois l'écart interquartile ; points : valeurs individuelles ou extrêmes.")
    elif k == "empile":
        tab = np.asarray(fd["table"], dtype=float)
        props = tab / np.where(tab.sum(axis=1, keepdims=True) > 0, tab.sum(axis=1, keepdims=True), 1)
        f.fig("repartition", figures.stacked(fd["xs"], fd["ys"], props, f"Répartition de « {fd['y']} » (%)", fd["y"]),
              f"Répartition de « {fd['y']} » au sein de chaque modalité de « {fd['x']} » (pourcentages en ligne). Sans lien "
              "entre les variables, toutes les barres auraient la même composition.")
    elif k == "nuage":
        f.fig("nuage", figures.scatter(fd["x"], fd["y"], fd["xname"], fd["yname"], line=fd.get("line")),
              f"« {fd['yname']} » en fonction de « {fd['xname']} »"
              + (" ; droite des moindres carrés en orange." if fd.get("line") else "."))
    elif k in ("residus", "glm"):
        res_ = fd["resid"] if k == "residus" else fd["rq"]
        lab = "Résidus" if k == "residus" else "Résidus quantiles"
        xlab = "Valeurs prédites" + (" (échelle log)" if fd.get("log") else "")
        f.fig("residus", figures.scatter(fd["fitted"], res_, xlab, lab, hline=0.0, smooth=True),
              f"{lab} en fonction des valeurs prédites, avec leur moyenne glissante (orange). Un nuage sans forme autour de "
              "zéro indique un modèle adapté ; un entonnoir signale une variance non constante, une courbe un effet non "
              "linéaire oublié.")
        f.fig("qq", figures.qqplot(res_, lab),
              f"Diagramme quantile-quantile des {lab.lower()} : les points doivent suivre la diagonale."
              + (" Pour un GLM, les résidus quantiles randomisés suivent une loi normale si la famille est adaptée "
                 f"{f.cite('dunn1996')}." if k == "glm" else ""))
        ix = fd.get("index")
        if ix and ix["rows"]:
            labels = [r[0] for r in ix["rows"]]
            f.fig("indice", figures.bars(labels, [r[1] for r in ix["rows"]], ix["what"], ix["factor"],
                                         lo=[r[2] for r in ix["rows"]], hi=[r[3] for r in ix["rows"]]),
                  f"Valeurs prédites par « {ix['factor']} », autres facteurs à leur moyenne, avec intervalle de confiance à "
                  f"95 % : c'est l'indice standardisé {f.cite('maunder2004', 'campbell2004', 'searle1980')}.")


def method_md(res: dict, spec: dict, dataset_name: str, author: str, justification: str | None) -> str:
    return method_fiche(res, spec, dataset_name, author, justification).markdown()


# --------------------------------------------------------------------------- modèles linéaires généralisés


def design(data: dict, xnames: list[str], cat: set[str]):
    """Matrice du modèle : constante + variables numériques + indicatrices (modalité de référence = la plus fréquente)."""
    n = len(next(iter(data.values())))
    cols, names, terms, levels = [np.ones(n)], ["(constante)"], [], {}
    for xn in xnames:
        v = data[xn]
        start = len(cols)
        if xn in cat:
            vals, counts = np.unique(v.astype(str), return_counts=True)
            if len(vals) > 50:
                raise RecipeError(f"« {xn} » a trop de modalités ({len(vals)}) pour un modèle (50 maximum).")
            if len(vals) < 2:
                raise RecipeError(f"« {xn} » n'a qu'une seule valeur : retirez-la du modèle.")
            ref = vals[int(np.argmax(counts))]
            lv = [ref] + sorted((x for x in vals if x != ref), key=str)
            levels[xn] = lv
            for x in lv[1:]:
                cols.append((v.astype(str) == x).astype(float))
                names.append(f"{xn} = {x} (vs {ref})")
        else:
            cols.append(v.astype(float))
            names.append(xn)
        terms.append((xn, list(range(start, len(cols)))))
    return np.column_stack(cols), names, terms, levels


def _vif(X) -> float:
    worst = 1.0
    for j in range(1, X.shape[1]):
        others = np.delete(X, j, axis=1)
        gj, *_ = np.linalg.lstsq(others, X[:, j], rcond=None)
        ss = float(np.sum((X[:, j] - X[:, j].mean()) ** 2))
        r2j = 1 - float(np.sum((X[:, j] - others @ gj) ** 2)) / ss if ss else 0.0
        worst = max(worst, 1 / (1 - r2j) if r2j < 1 else float("inf"))
    return worst


def _pct(f: float) -> str:
    d = (f - 1) * 100
    return f"{'+' if d >= 0 else '−'}{fr(abs(d), 0 if abs(d) >= 10 else 1)} %"


def glm_analysis(data: dict, yname: str, xnames: list[str], cat: set[str], offset_name: str | None,
                 force: str | None) -> Result:
    from . import glm

    y = data[yname].astype(float)
    n = len(y)
    integer = bool(np.all(np.abs(y - np.round(y)) < 1e-9))
    binary = bool(np.all((y == 0) | (y == 1)))
    r = Result("glm", f"Modéliser « {yname} » selon {', '.join('« ' + x + ' »' for x in xnames)}"
               + (f" (effort : « {offset_name} »)" if offset_name else ""))
    # --- choix de la famille selon la nature de la mesure
    fam = force
    nature = ("présence / absence (0 / 1)" if binary else "comptages (entiers ≥ 0)" if integer and y.min() >= 0
              else "valeurs strictement positives" if y.min() > 0 else
              "valeurs positives avec des zéros" if y.min() == 0 else "valeurs négatives")
    # entiers élevés sans zéro (poids en kg arrondis, montants) : quantités plutôt que comptages
    big_int = integer and not binary and y.min() > 0 and float(np.median(y)) >= 20
    if fam is None:
        fam = ("logistique" if binary else "gamma" if big_int else "poisson" if integer and y.min() >= 0
               else "gamma" if y.min() > 0 else None)
    domain_ok = {
        "logistique": binary,
        "poisson": integer and y.min() >= 0, "quasi_poisson": y.min() >= 0, "binomiale_negative": integer and y.min() >= 0,
        "gamma": y.min() > 0,
    }
    if fam is None or not domain_ok[fam]:
        r.test, r.test_label = fam or "", glm.FAMILIES.get(fam or "", "GLM")
        advice = ("Les zéros et les valeurs décimales ne vont ensemble dans aucune de ces familles. Approche usuelle en "
                  "halieutique (modèle « delta ») : 1) une régression logistique sur la présence (formule "
                  f"SI([{yname}] > 0; 1; 0)), 2) un GLM Gamma sur les seules valeurs positives (filtre {yname} > 0)."
                  if y.min() == 0 and not integer else
                  "Pour des valeurs négatives, utilisez la régression linéaire." if y.min() < 0 else
                  "Choisissez une famille adaptée (ou « Automatique »).")
        r.checks.append(Check("Nature de la mesure", False, "bloquant",
                              f"« {yname} » contient des {nature} : incompatible avec {glm.FAMILIES.get(fam or '', 'les GLM proposés')}. {advice}"))
        r.bloque = True
        r.alternative = None
        return r
    r.checks.append(Check("Nature de la mesure", True, "info", f"« {yname} » : {nature}."
                          + (" Valeurs entières mais élevées et sans zéro (poids, montants) : traitées comme des quantités "
                             "continues (Gamma). S'il s'agit de vrais comptages d'individus, choisissez « Binomiale "
                             "négative »." if big_int and force is None else "")))
    off = None
    if offset_name:
        e = data[offset_name].astype(float)
        if np.any(e <= 0):
            raise RecipeError(f"L'effort « {offset_name} » doit être strictement positif (filtrez les valeurs ≤ 0).")
        off = np.log(e)
    X, names, terms, levels = design(data, xnames, cat)
    p_ = X.shape[1]
    r.effectifs = {"n": n, "parametres": p_}
    small = n <= p_ + 2
    if fam == "logistique":
        events = int(min(y.sum(), n - y.sum()))
        enough = events >= 10 * (p_ - 1)
        msg = f"{events} cas dans la catégorie la plus rare pour {p_ - 1} paramètre(s)"
    else:
        enough = n >= 10 * (p_ - 1)
        msg = f"{n} observations pour {p_ - 1} paramètre(s)"
    r.checks.append(Check("Effectif", enough and not small, "bloquant" if small else ("avertissement" if not enough else "info"),
                          msg + ("" if enough else " : règle usuelle de 10 par paramètre non respectée (estimations instables).")))
    if small:
        r.bloque = True
        return r
    m = glm.fit(X, y, fam, off)
    auto = force is None
    switched = None
    if fam == "poisson" and m["disp"] > 1.5:
        if auto:
            switched = m["disp"]
            fam = "binomiale_negative"
            m = glm.fit(X, y, fam, off)
        else:
            r.checks.append(Check("Surdispersion", False, "bloquant",
                                  f"Variance {fr(m['disp'], 1)} fois plus forte que prévu par le modèle de Poisson : les "
                                  "p-values seraient beaucoup trop optimistes (faux effets significatifs)."))
            r.bloque = True
            r.alternative = "binomiale_negative"
    if switched:
        r.checks.append(Check("Surdispersion", True, "info",
                              f"Variance {fr(switched, 1)} fois plus forte que prévu par un modèle de Poisson (fréquent pour des "
                              "captures) : le modèle binomial négatif, qui l'absorbe, est utilisé."))
    elif fam == "binomiale_negative":
        r.checks.append(Check("Surdispersion", True, "info", f"Paramètre de dispersion θ = {fr(m['theta'], 2)} "
                                                            "(plus θ est petit, plus les comptages sont dispersés)."))
    elif fam in ("poisson",) and not r.bloque:
        r.checks.append(Check("Surdispersion", True, "info", f"Rapport de dispersion = {fr(m['disp'], 2)} (≈ 1 attendu) : correct."))
    r.test, r.test_label = fam, glm.FAMILIES[fam]
    if not m["conv"]:
        r.checks.append(Check("Convergence", False, "avertissement", "L'ajustement n'a pas complètement convergé : "
                              "simplifiez le modèle (moins de facteurs ou de modalités)."))
    beta, cov, mu = m["beta"], m["cov"], m["mu"]
    se = np.sqrt(np.maximum(np.diag(cov), 0))
    if fam == "logistique" and (np.any(np.abs(beta[1:]) > 10) or np.mean((mu < 1e-6) | (mu > 1 - 1e-6)) > 0.05):
        r.checks.append(Check("Séparation", False, "avertissement",
                              "Certaines modalités prédisent parfaitement la présence ou l'absence : coefficients et "
                              "intervalles très incertains. Regroupez les modalités rares."))
    if fam in ("poisson", "quasi_poisson", "binomiale_negative"):
        z_obs, z_exp = int(np.sum(y == 0)), glm.expected_zeros(fam, mu, m["theta"])
        excess = z_obs > 1.5 * z_exp and (z_obs - z_exp) > 0.05 * n
        r.checks.append(Check("Zéros", not excess, "avertissement" if excess else "info",
                              f"{z_obs} zéros observés pour {fr(z_exp, 0)} attendus par le modèle"
                              + (" : excès de zéros. Envisagez un modèle « delta » (présence puis quantité si présent)."
                                 if excess else ".")))
    vif = _vif(X) if p_ > 2 else 1.0
    r.checks.append(Check("Colinéarité", vif < 5, "avertissement" if vif >= 5 else "info",
                          f"VIF maximal = {fr(vif, 1)}" + (" : des facteurs se recoupent (ex. port et quartier), leurs effets "
                                                           "sont difficiles à séparer." if vif >= 5 else " (correct).")))
    rq = glm.quantile_residuals(fam, y, mu, m["theta"], m["phi"])
    sample = rq if n <= SHAPIRO_MAX else np.random.default_rng(1).choice(rq, SHAPIRO_MAX, replace=False)
    p_sw = float(st.shapiro(sample).pvalue) if n >= 8 else 1.0
    fit_ok = p_sw >= ALPHA or n > 2000  # avec beaucoup de données, le moindre écart devient « significatif »
    r.checks.append(Check(
        "Ajustement (résidus quantiles)", fit_ok, "info" if fit_ok else "avertissement",
        f"Test de Shapiro-Wilk sur les résidus quantiles randomisés (Dunn & Smyth) {fpe(p_sw)} : "
        + ("la loi choisie décrit correctement les données." if p_sw >= ALPHA else
           "écart faible à cet effectif, voir le graphique des résidus." if fit_ok else
           "la loi choisie décrit imparfaitement les données (vérifiez la famille, ajoutez un facteur manquant, "
           "regardez le graphique des résidus).")))
    # --- tests de chaque facteur (rapport de vraisemblance / F, en retirant le facteur)
    est_phi = fam in glm.ESTIMATED_PHI
    dof = n - p_
    term_rows = []
    glm_rep: list[tuple[str, float]] = []
    for name, idx in terms:
        keep = [j for j in range(p_) if j not in idx]
        if fam == "binomiale_negative":  # θ fixé à celui du modèle complet (comme anova.negbin)
            b0, mu0, _, _ = glm.irls(X[:, keep], y, fam, off, m["theta"])
            d0 = float(np.sum(glm.deviance_units(fam, y, mu0, m["theta"])))
        else:
            d0 = glm.fit(X[:, keep], y, fam, off)["dev"]
        dd, k = max(d0 - m["dev"], 0.0), len(idx)
        if est_phi:
            stat, pv = dd / k / m["phi"], float(st.f.sf(dd / k / m["phi"], k, dof))
            term_rows.append([name, k, f"F = {fr(stat)}", fp(pv), "oui" if pv < ALPHA else "non"])
            glm_rep.append((f"« {name} » : F({k} ; {dof}) = {fr(stat, 2)}, {p_txt(pv)}", pv))
        else:
            pv = float(st.chi2.sf(dd, k))
            term_rows.append([name, k, f"χ² = {fr(dd)}", fp(pv), "oui" if pv < ALPHA else "non"])
            glm_rep.append((f"« {name} » : χ²({k}) = {fr(dd, 2)}, {p_txt(pv)}", pv))
    # déviance nulle (constante seule) : part de déviance expliquée
    if fam == "binomiale_negative":
        _, mun, _, _ = glm.irls(X[:, :1], y, fam, off, m["theta"])
        dnull = float(np.sum(glm.deviance_units(fam, y, mun, m["theta"])))
    else:
        dnull = glm.fit(X[:, :1], y, fam, off)["dev"]
    expl = 1 - m["dev"] / dnull if dnull > 0 else 0.0
    r.rapport = [f"{glm.FAMILIES[fam]} (n = {n}) : déviance expliquée = {pc(expl, 1)}"
                 + (f", AIC = {fr(m['aic'], 1)}" if m["aic"] is not None else "")
                 + (f", θ = {fr(m['theta'], 3)}" if m["theta"] else "") + (f", dispersion = {fr(m['phi'], 3)}" if est_phi else "")
                 + ". Tests par rapport de vraisemblance (facteur retiré) : " + " ; ".join(t for t, _ in glm_rep) + "."]
    r.sci = {"p": min([pv for _, pv in glm_rep] or [1.0]), "effet": None, "n": n, "boot": False, "glm": True,
             "expl": expl}
    q = st.t.ppf(0.975, dof) if est_phi else st.norm.ppf(0.975)
    pvals = 2 * (st.t.sf(np.abs(beta / se), dof) if est_phi else st.norm.sf(np.abs(beta / se)))
    eff = "Rapport de cotes" if fam == "logistique" else "Effet multiplicatif"
    r.resultats = [{"nom": "Déviance expliquée", "valeur": f"{pc(expl, 1)}"},
                   {"nom": "AIC", "valeur": fr(m["aic"], 1) if m["aic"] is not None else "non défini (quasi-vraisemblance)"},
                   {"nom": "n", "valeur": fr(n)}]
    if est_phi:
        r.resultats.append({"nom": "Dispersion estimée", "valeur": fr(m["phi"], 3)})
    if m["theta"]:
        r.resultats.append({"nom": "θ (binomiale négative)", "valeur": fr(m["theta"], 3)})
    r.tableaux.append({"titre": "Effet de chaque facteur (test en retirant le facteur)",
                       "colonnes": ["Facteur", "ddl", "Statistique", "p", "Significatif ?"], "lignes": term_rows})
    r.tableaux.append({"titre": "Coefficients",
                       "colonnes": ["Terme", "Estimation (échelle " + ("logit" if fam == "logistique" else "log") + ")",
                                    eff, "IC 95 %", "p"],
                       "lignes": [[nm, fr(float(b)), fr(math.exp(b)) if abs(b) < 50 else "–",
                                   f"[{fr(math.exp(b - q * s))} ; {fr(math.exp(b + q * s))}]" if abs(b) < 50 else "–",
                                   fp(float(pv))]
                                  for nm, b, s, pv in zip(names, beta, se, pvals)]})
    # --- valeurs prédites par modalité du premier facteur catégoriel (indice standardisé, ex. CPUE par année)
    first_cat = next((x for x in xnames if x in levels), None)
    if first_cat:
        base = np.array([1.0] + [0.0] * (p_ - 1))
        for name, idx in terms:
            if name not in levels:
                base[idx[0]] = float(np.mean(X[:, idx[0]]))
            else:  # autres facteurs : moyenne des indicatrices (prédiction « moyenne » sur l'échantillon)
                if name != first_cat:
                    base[idx] = X[:, idx].mean(axis=0)
        rows = []
        cat_idx = dict(terms)[first_cat]
        index_num: list[tuple] = []
        for i, lv in enumerate(levels[first_cat]):
            x0 = base.copy()
            x0[cat_idx] = 0.0
            if i:
                x0[cat_idx[i - 1]] = 1.0
            eta = float(x0 @ beta)
            s = float(math.sqrt(max(x0 @ cov @ x0, 0)))
            inv = (lambda e: 1 / (1 + math.exp(-e))) if fam == "logistique" else math.exp
            rows.append([lv, fr(inv(eta)), f"[{fr(inv(eta - q * s))} ; {fr(inv(eta + q * s))}]",
                         int(np.sum(data[first_cat].astype(str) == lv))])
            index_num.append((str(lv), inv(eta), inv(eta - q * s), inv(eta + q * s)))
        what = ("probabilité de présence" if fam == "logistique" else
                f"« {yname} » par unité de « {offset_name} »" if offset_name else f"« {yname} » moyen")
        rows.sort(key=lambda r_: str(r_[0]))
        index_num.sort(key=lambda t: t[0])
        r.fd["index"] = {"factor": first_cat, "what": what, "rows": index_num}
        r.tableaux.append({"titre": f"Valeurs prédites par « {first_cat} » ({what}, autres facteurs à leur moyenne) : "
                                    "indice standardisé",
                           "colonnes": [first_cat, "Prédiction", "IC 95 %", "n"], "lignes": rows})
    # --- interprétation
    sig_terms = [t[0] for t in term_rows if t[4] == "oui"]
    r.interpretation = [f"{glm.FAMILIES[fam]} ajusté sur {fr(n)} observations : il explique {pc(expl, 0)} de la déviance "
                        f"de « {yname} » (part de la variabilité prise en compte par les facteurs)."]
    for t in term_rows:
        r.interpretation.append(f"Effet de « {t[0]} » ({t[1]} ddl) : {t[2]}, p {t[3] if t[3].startswith('<') else '= ' + t[3]}"
                                f" : {'effet significatif' if t[4] == 'oui' else 'pas d’effet mis en évidence'}.")
    if not sig_terms:
        r.interpretation.append("Aucun facteur n'a d'effet statistiquement significatif : les écarts observés entre "
                                "modalités restent compatibles avec le hasard.")
    ix = r.fd.get("index")
    if ix and len(ix["rows"]) >= 2:
        hi_ = max(ix["rows"], key=lambda t: t[1])
        lo_ = min(ix["rows"], key=lambda t: t[1])
        if lo_[1] > 0:
            r.interpretation.append(
                f"Valeurs prédites par « {ix['factor']} » : la plus élevée pour « {hi_[0]} » ({fr(hi_[1])}), la plus faible "
                f"pour « {lo_[0]} » ({fr(lo_[1])}), soit un rapport de {fr(hi_[1] / lo_[1], 2)}"
                + ("." if ix["factor"] in sig_terms else " ; cet écart n'est pas significatif."))
    unit = (f"« {yname} » par unité de « {offset_name} »" if offset_name else f"« {yname} »")
    for nm, b, pv in list(zip(names[1:], beta[1:], pvals[1:])):
        if pv >= ALPHA or abs(b) > 50:
            continue
        f_ = math.exp(b)
        if fam == "logistique":
            what = f"les chances de présence sont multipliées par {fr(f_)}"
        else:
            what = f"{unit} est multiplié par {fr(f_)} ({_pct(f_)})"
        if " = " in nm:
            r.interpretation.append(f"{nm} : {what}, à autres facteurs égaux.")
        else:
            r.interpretation.append(f"Quand « {nm} » augmente de 1 : {what}, à autres facteurs égaux.")
        if len(r.interpretation) > 10:
            break
    if offset_name:
        r.interpretation.append(f"L'effort « {offset_name} » est pris en compte comme décalage (offset) : le modèle porte "
                                "sur le rendement (captures par unité d'effort), comme pour une standardisation de CPUE.")
    idx = np.random.default_rng(0).choice(n, min(n, 5000), replace=False)
    r.graph = {"type": "residus", "x": np.log(mu[idx]).tolist() if fam != "logistique" else mu[idx].tolist(),
               "y": rq[idx].tolist(), "xname": "Valeurs prédites" + (" (échelle log)" if fam != "logistique" else ""),
               "yname": "Résidus quantiles"}
    r.fd.update({"kind": "glm", "fitted": np.log(mu) if fam != "logistique" else mu, "rq": rq, "y": yname,
                 "log": fam != "logistique", "family": fam, "offset": offset_name, "disp": m["disp"]})
    r.limites = ["Un effet dans un modèle n'est pas une preuve de causalité.",
                 "Les lignes d'un même navire ou d'une même marée ne sont pas indépendantes : un modèle mixte (effet navire) "
                 "serait plus rigoureux ; à défaut, interprétez les p-values avec prudence.",
                 "Le modèle ne vaut que dans la plage des valeurs observées : pas d'extrapolation.",
                 "Pour une variable numérique (ex. année), l'effet est supposé régulier ; convertissez-la en texte pour "
                 "obtenir un effet par modalité (indice annuel)."] + COMMON_LIMITS[:1]
    return r
