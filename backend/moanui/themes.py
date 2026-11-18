"""Chartes graphiques : modèles fournis et validation des chartes de structure."""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

from .engine.sql import RecipeError

THEMES_DIR = Path(__file__).parent / "themes"
_HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
COLOR_KEYS = ("primary", "primary_contrast", "accent", "background", "surface", "text", "muted", "border")
LOGO_POSITIONS = ("haut-gauche", "haut-droite", "bas-gauche", "bas-droite")


@lru_cache
def presets() -> dict[str, dict]:
    return {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted(THEMES_DIR.glob("*.json"))}


def default_theme() -> dict:
    return json.loads(json.dumps(presets()["neutre"]))


# Couleurs de l'ancienne charte « Neutre » (avant la refonte de novembre 2026) : une structure qui les a gardées telles
# quelles reçoit la nouvelle charte par défaut ; une charte personnalisée n'est jamais modifiée.
OLD_NEUTRE = {"primary": "#2F4858", "primary_contrast": "#FFFFFF", "accent": "#3A7CA5", "background": "#F6F7F9",
              "surface": "#FFFFFF", "text": "#1C2430", "muted": "#5F6B7A", "border": "#DDE2E8"}


def refresh_default(theme: dict) -> dict | None:
    """Nouvelle version de la charte si elle est restée l'ancienne charte par défaut, sinon None."""
    cols = {k: str(v).upper() for k, v in (theme.get("colors") or {}).items()}
    if cols != {k: v.upper() for k, v in OLD_NEUTRE.items()}:
        return None
    new = default_theme()
    out = {**theme, "colors": new["colors"], "chart": {**(theme.get("chart") or {}), "grid": new["chart"]["grid"]}}
    if str(theme.get("name", "")).startswith("Neutre"):
        out["name"] = new["name"]
    return out


def validate_theme(theme: dict) -> dict:
    """Complète une charte avec les valeurs par défaut et vérifie les couleurs."""
    base = default_theme()
    if not isinstance(theme, dict):
        raise RecipeError("Charte graphique invalide.")
    out = {**base, **{k: v for k, v in theme.items() if k in base or k == "logo"}}
    out["colors"] = {**base["colors"], **(theme.get("colors") or {})}
    out["chart"] = {**base["chart"], **(theme.get("chart") or {})}
    for k in COLOR_KEYS:
        if not _HEX.match(str(out["colors"].get(k, ""))):
            raise RecipeError(f"Couleur invalide pour « {k} » : utilisez le format #RRVVBB.")
    for key in ("palette", "sequential", "diverging"):
        vals = out.get(key) or []
        if not isinstance(vals, list) or len(vals) < 2 or not all(_HEX.match(str(c)) for c in vals):
            raise RecipeError(f"Palette « {key} » invalide : au moins deux couleurs au format #RRVVBB.")
    if out["chart"].get("logo_position") not in LOGO_POSITIONS:
        raise RecipeError("Position du logo invalide.")
    out["name"] = str(out.get("name") or "Personnalisée")[:80]
    out["font"] = re.sub(r"[^\w\s,'\-]", "", str(out.get("font") or base["font"]))[:200]
    return out
