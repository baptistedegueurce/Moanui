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
