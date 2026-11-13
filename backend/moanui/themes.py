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
