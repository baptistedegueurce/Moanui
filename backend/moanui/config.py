"""Emplacement de l'espace de travail local.

Tout ce que Moanui écrit (base de métadonnées, copies brutes, exports) vit
sous un seul dossier, choisi dans cet ordre :
1. la variable d'environnement MOANUI_HOME ;
2. le dossier de données utilisateur du système (aucun droit admin requis).
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from platformdirs import user_data_dir


@dataclass(frozen=True)
class Settings:
    home: Path

    @property
    def db_path(self) -> Path:
        return self.home / "moanui.db"

    @property
    def raw_dir(self) -> Path:
        return self.home / "raw"

    @property
    def assets_dir(self) -> Path:
        return self.home / "assets"

    @property
    def exports_dir(self) -> Path:
        return self.home / "exports"

    def ensure(self) -> None:
        for d in (self.home, self.raw_dir, self.assets_dir, self.exports_dir):
            d.mkdir(parents=True, exist_ok=True)


def load_settings(home: str | os.PathLike | None = None) -> Settings:
    if home is None:
        home = os.environ.get("MOANUI_HOME") or user_data_dir("Moanui", appauthor=False)
    s = Settings(home=Path(home).expanduser().resolve())
    s.ensure()
    return s
