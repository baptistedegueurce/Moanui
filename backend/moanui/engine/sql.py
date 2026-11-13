"""Aides SQL : échappement des identifiants et des valeurs pour DuckDB.

Toute valeur venant de l'utilisateur passe par ces fonctions : on ne concatène
jamais de texte brut dans une requête.
"""

from __future__ import annotations

import math
import re
from datetime import date, datetime

TECH_PREFIX = "__"
ROW_ID = "__ligne"

NUMERIC_TYPES = ("TINYINT", "SMALLINT", "INTEGER", "BIGINT", "HUGEINT", "UTINYINT", "USMALLINT",
                 "UINTEGER", "UBIGINT", "FLOAT", "DOUBLE", "REAL")


class RecipeError(ValueError):
    """Erreur lisible par l'utilisateur (message en français)."""


def ident(name: str) -> str:
    if not isinstance(name, str) or name == "":
        raise RecipeError("Nom de colonne vide ou invalide.")
    return '"' + name.replace('"', '""') + '"'


def string_lit(value: str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def is_numeric_type(t: str) -> bool:
    t = t.upper()
    return t.startswith(NUMERIC_TYPES) or t.startswith("DECIMAL")


def is_temporal_type(t: str) -> bool:
    t = t.upper()
    return t.startswith("DATE") or t.startswith("TIMESTAMP")


def parse_number(value) -> float | int:
    if isinstance(value, bool):
        raise RecipeError(f"« {value} » n'est pas un nombre.")
    if isinstance(value, (int, float)):
        if isinstance(value, float) and not math.isfinite(value):
            raise RecipeError("Valeur numérique non finie.")
        return value
    s = str(value).strip().replace(" ", "").replace(" ", "").replace(",", ".")
    if not re.fullmatch(r"[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?", s):
        raise RecipeError(f"« {value} » n'est pas un nombre valide.")
    f = float(s)
    return int(f) if f.is_integer() and "." not in s and "e" not in s.lower() else f


def num_lit(value) -> str:
    return repr(parse_number(value))


_DATE_FORMATS = ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%Y/%m/%d")


def parse_date(value) -> date:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    s = str(value).strip()[:10]
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    raise RecipeError(f"« {value} » n'est pas une date reconnue (formats acceptés : AAAA-MM-JJ ou JJ/MM/AAAA).")


def literal_for(value, col_type: str) -> str:
    """Littéral SQL typé selon le type de la colonne visée."""
    if value is None:
        return "NULL"
    t = col_type.upper()
    if is_numeric_type(t):
        return num_lit(value)
    if t.startswith("TIMESTAMP"):
        s = str(value).strip()
        if len(s) <= 10:
            return f"TIMESTAMP {string_lit(parse_date(s).isoformat())}"
        try:
            return f"TIMESTAMP {string_lit(datetime.fromisoformat(s).isoformat(sep=' '))}"
        except ValueError as e:
            raise RecipeError(f"« {value} » n'est pas une date-heure valide.") from e
    if t.startswith("DATE"):
        return f"DATE {string_lit(parse_date(value).isoformat())}"
    if t == "BOOLEAN":
        s = str(value).strip().lower()
        if s in ("true", "vrai", "1", "oui"):
            return "TRUE"
        if s in ("false", "faux", "0", "non"):
            return "FALSE"
        raise RecipeError(f"« {value} » n'est pas une valeur booléenne (vrai/faux).")
    return string_lit(value)


def free_literal(value) -> str:
    """Littéral sans type cible : nombre si possible, sinon texte."""
    if value is None:
        return "NULL"
    try:
        return num_lit(value)
    except RecipeError:
        return string_lit(value)
