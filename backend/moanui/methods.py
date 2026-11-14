"""Fiche méthode d'un jeu de données : d'où vient la donnée, ce qui lui a été fait, par qui, quand,
avec quelles méthodes (et leurs références), ce qu'on obtient et comment le refaire.
"""

from __future__ import annotations

import json
from datetime import datetime

from . import __version__, figures
from .engine.recipe import describe_step
from .fiche import Fiche

TYPE_LABELS = {"texte": "texte", "entier": "nombre entier", "decimal": "nombre décimal", "date": "date",
               "dateheure": "date et heure", "booleen": "vrai/faux"}

# Paragraphes de méthode associés à certains types d'étapes, avec leurs références.
STEP_METHODS: dict[str, tuple[str, str, tuple[str, ...]]] = {
    "edit_cells": ("Corrections manuelles",
                   "Les cellules corrigées à la main sont listées individuellement avec leur ancienne valeur et la "
                   "justification saisie ; la valeur d'origine reste dans le fichier brut. Cette pratique suit les "
                   "recommandations d'organisation des données tabulaires : ne jamais écraser la source, documenter "
                   "chaque modification", ("broman2018",)),
    "fill_null": ("Valeurs manquantes",
                  "Des valeurs manquantes ont été remplacées. Une imputation par une constante, la moyenne ou la médiane "
                  "réduit artificiellement la variabilité et peut biaiser les analyses ultérieures ; elle n'est "
                  "acceptable que si les manques sont peu nombreux et sans lien avec la valeur manquante", ("little2019",)),
    "dedupe": ("Doublons",
               "Les lignes en double ont été retirées selon les colonnes indiquées. Un doublon de déclaration gonfle les "
               "sommes (captures, effort) sans être visible dans les moyennes", ("zuur2010",)),
    "transform": ("Transformations",
                  "Des transformations (logarithme, racine, classes) ont été appliquées. Le logarithme réduit "
                  "l'asymétrie des quantités pêchées ; log(1 + x) permet de conserver les zéros. Les résultats "
                  "exprimés sur une échelle transformée doivent être rétro-transformés avec prudence", ("zuur2010",)),
    "gear_check": ("Cohérence engin / espèce",
                   "Les engins déclarés ont été comparés à une liste d'engins plausibles par espèce, construite à partir "
                   "de la classification FAO des engins (ISSCFG) et de la littérature ; les combinaisons improbables sont "
                   "signalées et un engin suggéré (engin_sug) est proposé, sans écraser la déclaration", ("isscfg",)),
    "lookup": ("Référentiels",
               "Des libellés ou regroupements ont été ajoutés à partir d'un référentiel (engins, métiers). Les codes "
               "absents du référentiel reçoivent une valeur par défaut, à vérifier", ("isscfg", "dcf_metiers")),
    "ciem_rect": ("Rectangles statistiques",
                  "Chaque position a été rattachée à son rectangle statistique CIEM (1° de longitude sur 0,5° de "
                  "latitude), unité spatiale des déclarations de captures", ("ices_rect",)),
    "vms_activity": ("Activité de pêche déduite de la VMS",
                     "L'activité de chaque position VMS a été déduite de la vitesse (déclarée ou calculée entre deux "
                     "positions successives par la formule de haversine), selon des seuils propres à l'engin : en "
                     "dessous, arrêt ou manœuvre ; au-dessus, route. Cette méthode est la plus répandue mais reste une "
                     "approximation : les seuils doivent être vérifiés sur des marées connues", ("lee2010", "hintzen2012")),
    "zone_tag": ("Appartenance à une zone",
                 "Chaque position a été testée contre les polygones d'une couche (point dans polygone, coordonnées "
                 "WGS84). Le résultat dépend de la précision et de la date de la couche utilisée", ()),
    "vms_catch_split": ("Répartition des captures sur les positions",
                        "Les captures déclarées par navire et par jour (et par rectangle quand il est disponible) ont été "
                        "réparties entre les positions de pêche du même navire le même jour, à parts égales ou au prorata "
                        "du temps ; les captures sans position correspondante au niveau fin sont reportées au niveau du "
                        "jour. Méthode usuelle de croisement journaux de bord / VMS", ("gerritsen2011", "hintzen2012")),
    "anonymize": ("Anonymisation",
                  "Des colonnes identifiantes ont été remplacées par des codes, hachées ou supprimées avant diffusion. "
                  "Un code stable reste une pseudonymisation au sens du RGPD si la table de correspondance existe", ("rgpd",)),
    "join": ("Jointures",
             "Des colonnes d'autres jeux ont été associées par clé. Une clé non unique dans le jeu associé duplique des "
             "lignes (double comptage) : le nombre de lignes avant et après chaque jointure est indiqué au tableau des "
             "traitements", ()),
}


def _fmt_date(iso: str | None) -> str:
    if not iso:
        return "?"
    try:
        return datetime.fromisoformat(iso).strftime("%d/%m/%Y %H:%M")
    except ValueError:
        return iso


def _size(n: int) -> str:
    for unit in ("o", "Ko", "Mo", "Go"):
        if n < 1024:
            return f"{n:.0f} {unit}"
        n /= 1024
    return f"{n:.1f} To"


def _n(v) -> str:
    if v is None:
        return ""
    if isinstance(v, float):
        return figures.fmt(v)
    if isinstance(v, int):
        return f"{v:,}".replace(",", " ")
    return str(v)


def dataset_method(ds: dict, raw: dict, structure: dict, users: dict[str, str], plan, sensitive: list[dict],
                   generated_by: str, purpose: str | None = None, prof: dict | None = None) -> Fiche:
    report = json.loads(raw["import_report"])
    recipe = json.loads(ds["recipe"])
    active = [s for s in recipe if s.get("enabled", True)]
    f = Fiche(f"Fiche méthode : {ds['name']}", ds.get("description") or "")
    f.meta = [("Structure", structure["name"]), ("Jeu créé par", f"{users.get(ds['created_by'], '?')}, le {_fmt_date(ds['created_at'])}"),
              ("Fiche établie par", f"{generated_by}, le {datetime.now().strftime('%d/%m/%Y %H:%M')}"),
              ("Outil", f"Moanui {__version__} (DuckDB)")]
    if purpose:
        f.h("Objectif").p(purpose)

    # ------------------------------------------------------------------ données sources
    f.h("Données sources")
    f.p("Le fichier d'origine est conservé tel quel, en lecture seule, avec son empreinte numérique : toute modification "
        "ultérieure serait détectée. Les traitements s'appliquent à une copie, sous forme d'étapes enregistrées et "
        f"rejouables, ce qui garantit la traçabilité et la reproductibilité {f.cite('wilkinson2016', 'broman2018')}.")
    opts = report.get("options", {})
    f.kv([("Fichier", f"`{raw['original_name']}`"), ("Format", f"{raw['format'].upper()}, {_size(raw['size_bytes'])}"),
          ("Empreinte SHA-256", f"`{raw['sha256']}`"), ("Importé le", _fmt_date(raw["imported_at"])),
          ("Lignes", _n(raw["n_rows"])), ("Colonnes", _n(len(report.get("columns", [])))),
          ("Options de lecture", ", ".join(f"{k} = {'tabulation' if v == chr(9) else v}" for k, v in opts.items()))])
    f.table(["Colonne", "Type détecté", "Remarque à l'import"],
            [[c["name"], TYPE_LABELS.get(c["type"], c["type"]), (c.get("note") or "") +
              (f" {c['warning']['message']}" if c.get("warning") else "")] for c in report.get("columns", [])],
            "Colonnes du fichier d'origine et type reconnu à l'import.")

    # ------------------------------------------------------------------ traitements
    f.h("Traitements appliqués")
    states = {s["id"]: s for s in plan.steps}
    if not active:
        f.p("Aucun traitement : la donnée est utilisée telle qu'importée.")
    else:
        f.p(f"{len(active)} opération(s), appliquées dans l'ordre ci-dessous au fichier d'origine "
            f"({_n(raw['n_rows'])} lignes). Chaque opération indique son auteur, sa date et, le cas échéant, la "
            "justification saisie.")
        rows, labels, counts = [], ["Origine"], [raw["n_rows"]]
        prev_n = raw["n_rows"]
        for i, s in enumerate(active, 1):
            st = states.get(s.get("id"), {})
            n_after = st.get("n_rows")
            delta = ""
            if n_after is not None and prev_n is not None and n_after != prev_n:
                delta = f" ({'+' if n_after > prev_n else '−'}{_n(abs(n_after - prev_n))})"
            desc = describe_step(s)
            if st.get("status") == "erreur":
                desc += f" **Étape en erreur : {st.get('error')}**"
            if s.get("comment"):
                desc += f" *Justification : {s['comment']}*"
            rows.append([str(i), desc, f"{users.get(s.get('author'), '?')}, {_fmt_date(s.get('at'))}",
                         (_n(n_after) + delta) if n_after is not None else ""])
            if n_after is not None:
                labels.append(str(i))
                counts.append(n_after)
                prev_n = n_after
        f.table(["N°", "Opération", "Auteur, date", "Lignes après"], rows, "Opérations de la recette.", "llll")
        if len(set(counts)) > 1:
            f.fig("lignes_par_etape", figures.bars(labels, counts, "Nombre de lignes", "Opération (n°)", color="#2f4858"),
                  "Nombre de lignes après chaque opération. Une baisse correspond à un filtre ou une suppression de "
                  "doublons ; une hausse, à une jointure ou un empilement.")
    disabled = [s for s in recipe if not s.get("enabled", True)]
    if disabled:
        f.p("Opérations désactivées (non appliquées, conservées pour mémoire) :")
        f.ul([describe_step(s) for s in disabled])

    # méthodes particulières
    used = []
    for s in active:
        t = s["type"]
        if t == "aggregate" and (s.get("params") or {}).get("secret", {}).get("vessel_column"):
            t = "_secret"
        if t not in used:
            used.append(t)
    paras = []
    for t in used:
        if t == "_secret":
            paras.append(("Secret statistique",
                          "Les regroupements comptant moins de navires que le seuil fixé ont été signalés (colonne "
                          "secret_stat) pour être masqués avant diffusion. Le secret statistique interdit de publier une "
                          "information permettant d'identifier un déclarant", ("loi1951", "reg223")))
        elif t in STEP_METHODS:
            paras.append(STEP_METHODS[t])
    if paras:
        f.h("Méthodes employées")
        for title, text, refs in paras:
            f.h3(title)
            f.p(f"{text} {f.cite(*refs)}.".replace(" .", "."))

    # ------------------------------------------------------------------ résultat
    f.h("Données obtenues")
    if plan.error:
        f.note(f"La recette s'arrête à l'opération {plan.error['index']} : {plan.error['message']}")
    cols = [c for c in plan.schema if not c.startswith("__")]
    if prof:
        n = prof["n_rows"]
        f.p(f"{_n(n)} lignes et {len(cols)} colonnes après traitement.")
        rows = []
        for c in prof["columns"]:
            fill = 100 * (1 - (c["vides"] / n)) if n else 0
            num = c.get("moyenne") is not None
            rows.append([c["name"], TYPE_LABELS.get(_kind(c["type"]), _kind(c["type"])), f"{figures.fmt(fill, 1)} %",
                         _n(c["distinctes"]), _n(c.get("min")) if num else "", _n(c.get("mediane")) if num else "",
                         _n(c.get("moyenne")) if num else "", _n(c.get("max")) if num else ""])
        f.table(["Colonne", "Type", "Renseignée", "Valeurs distinctes", "Min", "Médiane", "Moyenne", "Max"], rows,
                "Description des colonnes après traitement.", "llrrrrrr")
        incomplete = [c for c in prof["columns"] if c["vides"]]
        if incomplete:
            pct = sorted(((c["name"], 100 * c["vides"] / n) for c in incomplete), key=lambda x: -x[1])[:25]
            f.fig("valeurs_manquantes", figures.hbars([a for a, _ in pct], [b for _, b in pct], "Part de valeurs manquantes (%)",
                                                      maxv=100, color="#eb6834", suffix=" %"),
                  "Part de valeurs manquantes par colonne (colonnes incomplètes uniquement).")
        if prof.get("warnings"):
            f.h3("Points de vigilance relevés par les contrôles automatiques")
            f.p(f"Ces signaux ne sont pas forcément des erreurs ; ils sont à vérifier avant analyse {f.cite('zuur2010')}.")
            f.ul([(f"« {w['colonne']} » : " if w.get("colonne") else "") + w["message"] for w in prof["warnings"]])
    else:
        f.p(f"Colonnes : {', '.join(cols)}.")

    if sensitive:
        f.h("Confidentialité")
        f.p("Colonnes susceptibles de relever du secret statistique ou des données personnelles "
            f"{f.cite('loi1951', 'rgpd')} :")
        f.ul([f"{s['column']} ({s['kind']})" for s in sensitive])
        anon = [c for st in active if st["type"] == "anonymize" for c in st["params"].get("columns", [])]
        f.p(f"Anonymisées dans la recette : {', '.join(anon)}." if anon else
            "Aucune n'est anonymisée dans la recette : le jeu ne doit pas être diffusé en l'état.")

    if ds.get("notes"):
        f.h("Notes").p(ds["notes"])

    f.h("Reproduire le traitement")
    f.p("Requête SQL équivalente (dialecte DuckDB), exécutable sur la copie Parquet du fichier d'origine. Elle reprend "
        "toutes les opérations actives, dans l'ordre.")
    f.code(_pretty_sql(plan.sql), "sql")
    return f


def _pretty_sql(sql: str) -> str:
    """Une étape par ligne : plus lisible dans la fiche."""
    import re

    out = re.sub(r", (s\d+ AS \()", r",\n\1", sql)
    return re.sub(r"\) (SELECT \* FROM s\d+)$", r")\n\1", out)


def _kind(t: str) -> str:
    u = t.upper()
    if u.startswith(("BIGINT", "INTEGER", "SMALLINT", "TINYINT", "HUGEINT", "UBIGINT")):
        return "entier"
    if u.startswith(("DOUBLE", "FLOAT", "DECIMAL", "REAL")):
        return "decimal"
    if u.startswith("TIMESTAMP"):
        return "dateheure"
    if u.startswith("DATE"):
        return "date"
    if u.startswith("BOOL"):
        return "booleen"
    return "texte"
