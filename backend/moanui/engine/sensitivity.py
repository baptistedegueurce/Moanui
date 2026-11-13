"""Repérage des colonnes sensibles (secret statistique, données personnelles).

Les structures ont le droit de travailler avec ces données : Moanui ne bloque
rien, mais alerte avant tout export et propose l'anonymisation en un clic.
"""

from __future__ import annotations

import re

PATTERNS = [
    (r"navs?_?cod|^cfr$|immat|navire|bateau|vessel|^nav_", "identifiant de navire"),
    (r"patron|armateur|propri[eé]taire|^nom($|_)|pr[eé]nom|marin|p[eê]cheur", "nom de personne"),
    (r"siret|siren|num_?pmp|licence", "identifiant administratif"),
    (r"t[eé]l[eé]phone|mail|adresse", "coordonnées"),
]


def detect(columns: list[str]) -> list[dict]:
    out = []
    for c in columns:
        if c.startswith("__"):
            continue
        low = c.lower()
        for rx, kind in PATTERNS:
            if re.search(rx, low):
                out.append({"column": c, "kind": kind})
                break
    return out
