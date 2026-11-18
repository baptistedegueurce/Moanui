from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from moanui.config import load_settings
from moanui.main import create_app

FIXTURES = Path(__file__).parent / "fixtures"
PASSWORD = "motdepasse1"


@pytest.fixture
def client(tmp_path):
    app = create_app(load_settings(tmp_path / "home"))
    with TestClient(app) as c:
        r = c.post("/api/setup", json={"username": "admin", "display_name": "Admin Test", "password": PASSWORD,
                                       "structure_name": "Structure Test", "structure_short_name": "ST"})
        assert r.status_code == 200, r.text
        yield c


def upload(client, name, **form):
    with open(FIXTURES / name, "rb") as f:
        r = client.post("/api/datasets/import", files={"file": (name, f, "text/csv")}, data=form)
    assert r.status_code == 200, r.text
    return r.json()


_R_OK: dict[str, bool] = {}


def r_ready(*packages: str) -> bool:
    """R est installé avec ces paquets (sinon les scripts R générés ne sont pas exécutés, seulement vérifiés)."""
    import os
    import shutil
    import subprocess

    key = ",".join(packages)
    if key not in _R_OK:
        ok = bool(shutil.which("Rscript"))
        if ok:
            libs = "; ".join(f"library({p})" for p in packages) or "invisible(0)"
            ok = subprocess.run(["Rscript", "-e", libs], capture_output=True, timeout=120).returncode == 0
        _R_OK[key] = ok
    if not _R_OK[key] and os.environ.get("MOANUI_EXIGER_R"):
        # en CI Windows, R et ses paquets sont installés : leur absence est une erreur, pas un test sauté
        raise RuntimeError(f"R ou les paquets {packages} manquent alors que MOANUI_EXIGER_R est défini.")
    return _R_OK[key]
