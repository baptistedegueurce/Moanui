"""Point d'entrée : serveur local (127.0.0.1 uniquement) + ouverture du navigateur."""

from __future__ import annotations

import argparse
import os
import socket
import threading
import webbrowser
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import FileResponse, JSONResponse

from . import __version__
from .api import admin, auth, charts, datasets
from .config import Settings, load_settings
from .db import Database
from .engine.sql import RecipeError

STATIC_DIR = Path(__file__).parent / "static"


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or load_settings()
    app = FastAPI(title="Moanui", version=__version__, docs_url="/api/docs", redoc_url=None,
                  openapi_url="/api/openapi.json")
    app.state.settings = settings
    app.state.db = Database(settings.db_path)

    # protège contre le « DNS rebinding » : seul l'accès local est accepté
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=["127.0.0.1", "localhost", "testserver"])

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        if request.url.path.startswith("/api/"):
            response.headers.setdefault("Cache-Control", "no-store")
        return response

    @app.exception_handler(RecipeError)
    async def recipe_error(_: Request, exc: RecipeError):
        return JSONResponse({"detail": str(exc)}, status_code=400)

    @app.exception_handler(RequestValidationError)
    async def validation_error(_: Request, exc: RequestValidationError):
        msgs = []
        for e in exc.errors():
            loc = ".".join(str(x) for x in e.get("loc", [])[1:])
            msgs.append(f"{loc} : {e.get('msg')}" if loc else e.get("msg"))
        return JSONResponse({"detail": "Données envoyées invalides : " + " ; ".join(msgs)}, status_code=422)

    for r in (auth.router, admin.router, datasets.router, charts.router):
        app.include_router(r)

    @app.get("/api/health")
    def health():
        return {"ok": True, "version": __version__, "home": str(settings.home)}

    if STATIC_DIR.exists():
        @app.get("/{path:path}", include_in_schema=False)
        def spa(path: str):
            if path.startswith("api/"):
                return JSONResponse({"detail": "Introuvable."}, status_code=404)
            target = (STATIC_DIR / path).resolve()
            if path and target.is_file() and STATIC_DIR.resolve() in target.parents:
                return FileResponse(target)
            return FileResponse(STATIC_DIR / "index.html", headers={"Cache-Control": "no-cache"})

    return app


def _free_port(preferred: int) -> int:
    for port in [preferred] + list(range(preferred + 1, preferred + 20)):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    raise SystemExit("Aucun port libre trouvé.")


def run() -> None:
    import uvicorn

    parser = argparse.ArgumentParser(description="Lancer Moanui")
    parser.add_argument("--port", type=int, default=int(os.environ.get("MOANUI_PORT", 8765)))
    parser.add_argument("--home", help="Dossier de l'espace de travail")
    parser.add_argument("--no-browser", action="store_true", help="Ne pas ouvrir le navigateur")
    args = parser.parse_args()

    settings = load_settings(args.home)
    port = _free_port(args.port)
    url = f"http://127.0.0.1:{port}"
    print(f"Moanui {__version__}")
    print(f"Espace de travail : {settings.home}")
    print(f"Ouvrez {url} dans votre navigateur (Ctrl+C pour arrêter).")
    if not args.no_browser:
        threading.Timer(1.2, lambda: webbrowser.open(url)).start()
    uvicorn.run(create_app(settings), host="127.0.0.1", port=port, log_level="warning")


if __name__ == "__main__":
    run()
