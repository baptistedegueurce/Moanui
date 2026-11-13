"""Point d'entrée de l'exécutable autonome (PyInstaller)."""

import multiprocessing
import sys

from moanui.main import run

if __name__ == "__main__":
    multiprocessing.freeze_support()
    try:
        run()
    except KeyboardInterrupt:
        sys.exit(0)
