"""Point d'entrée de l'exécutable autonome (PyInstaller).

En cas d'erreur au démarrage, la fenêtre reste ouverte avec le message et le détail est écrit dans
moanui-erreur.log (à côté de Moanui.exe, ou dans %LOCALAPPDATA%\\Moanui si le dossier est protégé).
"""

import multiprocessing
import os
import sys
import traceback
from datetime import datetime
from pathlib import Path


def _console_utf8() -> None:
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass


def _journal(texte: str) -> str:
    lieux = [Path(sys.executable).parent,
             Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "Moanui"]
    for d in lieux:
        try:
            d.mkdir(parents=True, exist_ok=True)
            p = d / "moanui-erreur.log"
            with open(p, "a", encoding="utf-8") as f:
                f.write(f"\n===== {datetime.now():%Y-%m-%d %H:%M:%S} =====\n{texte}\n")
            return str(p)
        except Exception:
            continue
    return ""


PAUSE = "--no-pause" not in sys.argv
sys.argv = [a for a in sys.argv if a != "--no-pause"]


def _attendre() -> None:
    if PAUSE:
        try:
            input("\nAppuyez sur Entrée pour fermer cette fenêtre.")
        except Exception:
            pass


if __name__ == "__main__":
    multiprocessing.freeze_support()
    _console_utf8()
    try:
        from moanui.main import run
        run()
    except KeyboardInterrupt:
        sys.exit(0)
    except SystemExit as e:
        if e.code not in (None, 0):
            print(f"\nMoanui s'est arrêté : {e.code}")
            _attendre()
        raise
    except BaseException:
        detail = traceback.format_exc()
        log = _journal(detail)
        print("\nMoanui n'a pas pu démarrer.\n")
        print(detail)
        if log:
            print(f"Le détail a été enregistré dans : {log}")
        print("Envoyez ce fichier (ou une capture de cette fenêtre) pour que le problème soit corrigé.")
        _attendre()
        sys.exit(1)
