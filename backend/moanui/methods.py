"""Fiches méthode en Markdown.

Chaque jeu de données traité, chaque export et chaque graphique peut produire
sa fiche : d'où vient la donnée, ce qui lui a été fait, par qui, quand, et
comment le refaire. C'est la mémoire du traitement.
"""

from __future__ import annotations

import json
from datetime import datetime

from . import __version__
from .engine.recipe import describe_step

TYPE_LABELS = {"texte": "texte", "entier": "nombre entier", "decimal": "nombre décimal", "date": "date",
               "dateheure": "date et heure", "booleen": "vrai/faux"}


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


def dataset_method(ds: dict, raw: dict, structure: dict, users: dict[str, str], plan, sensitive: list[dict],
                   generated_by: str, purpose: str | None = None) -> str:
    report = json.loads(raw["import_report"])
    recipe = json.loads(ds["recipe"])
    L: list[str] = []
    L.append(f"# Fiche méthode : {ds['name']}")
    L.append("")
    L.append(f"- **Structure** : {structure['name']}")
    L.append(f"- **Créé par** : {users.get(ds['created_by'], '?')} le {_fmt_date(ds['created_at'])}")
    L.append(f"- **Fiche générée par** : {generated_by} le {datetime.now().strftime('%d/%m/%Y %H:%M')}")
    L.append(f"- **Outil** : Moanui {__version__}")
    if ds.get("description"):
        L.append("")
        L.append(f"> {ds['description']}")
    if purpose:
        L += ["", "## Objectif", "", purpose]

    L += ["", "## 1. Donnée source (fichier brut, jamais modifié)", ""]
    L.append(f"- **Fichier** : `{raw['original_name']}` ({_size(raw['size_bytes'])}, format {raw['format'].upper()})")
    L.append(f"- **Empreinte SHA-256** : `{raw['sha256']}`")
    L.append("  (permet de vérifier que le fichier d'origine est strictement identique)")
    L.append(f"- **Importé le** : {_fmt_date(raw['imported_at'])}")
    L.append(f"- **Lignes** : {raw['n_rows']:,}".replace(",", " "))
    opts = report.get("options", {})
    if opts:
        o = ", ".join(f"{k} = `{'tabulation' if v == chr(9) else v}`" for k, v in opts.items())
        L.append(f"- **Options de lecture** : {o}")
    L += ["", "| Colonne | Type détecté | Remarque |", "|---|---|---|"]
    for c in report.get("columns", []):
        L.append(f"| {c['name']} | {TYPE_LABELS.get(c['type'], c['type'])} | {c.get('note') or ''} |")

    L += ["", "## 2. Traitements appliqués (dans l'ordre)", ""]
    active = [s for s in recipe if s.get("enabled", True)]
    if not active:
        L.append("Aucun traitement : la donnée est utilisée telle qu'importée.")
    states = {s["id"]: s for s in plan.steps}
    n = 0
    for s in recipe:
        if not s.get("enabled", True):
            continue
        n += 1
        st = states.get(s.get("id"), {})
        who = users.get(s.get("author"), "?")
        L.append(f"{n}. {describe_step(s)}")
        meta = f"   *{who}, {_fmt_date(s.get('at'))}*"
        if st.get("added"):
            meta += f" · colonnes créées : {', '.join(st['added'])}"
        L.append(meta)
        if s.get("comment"):
            L.append(f"   > Justification : {s['comment']}")
        if st.get("status") == "erreur":
            L.append(f"   ⚠️ Étape en erreur : {st.get('error')}")
    disabled = [s for s in recipe if not s.get("enabled", True)]
    if disabled:
        L += ["", "Étapes désactivées (non appliquées, conservées pour mémoire) :", ""]
        for s in disabled:
            L.append(f"- {describe_step(s)}")

    L += ["", "## 3. Résultat", ""]
    L.append(f"- **Colonnes** : {', '.join(c for c in plan.schema if not c.startswith('__'))}")
    if plan.error:
        L.append(f"- ⚠️ La recette s'arrête à l'étape {plan.error['index']} : {plan.error['message']}")

    if sensitive:
        L += ["", "## 4. Confidentialité", ""]
        L.append("Colonnes potentiellement soumises au secret statistique ou aux données personnelles :")
        L.append("")
        for s in sensitive:
            L.append(f"- {s['column']} ({s['kind']})")
        anon = [c for st in active if st["type"] == "anonymize" for c in st["params"].get("columns", [])]
        if anon:
            L.append("")
            L.append(f"Anonymisées dans la recette : {', '.join(anon)}.")

    if ds.get("notes"):
        L += ["", "## Notes", "", ds["notes"]]

    L += ["", "## Annexe : reproduire le traitement", "",
          "Requête SQL équivalente (DuckDB), à exécuter sur la copie Parquet du fichier brut :", "",
          "```sql", plan.sql, "```", ""]
    return "\n".join(L)
