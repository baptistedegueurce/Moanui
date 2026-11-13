"""Dépendances communes : utilisateur connecté, droits, accès aux jeux de données."""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone

from fastapi import Depends, HTTPException, Request

from ..db import Database
from ..engine import geo, pipeline
from ..engine.recipe import RESOLVER
from ..engine.sql import RecipeError
from ..engine.store import parquet_path
from ..security import token_hash

SESSION_COOKIE = "moanui_session"
ROLE_RANK = {"lecteur": 1, "analyste": 2, "admin": 3}


@dataclass
class User:
    id: str
    username: str
    display_name: str
    is_superadmin: bool
    active_structure_id: str | None
    roles: dict[str, str]  # structure_id -> rôle

    def role_in(self, structure_id: str) -> str | None:
        if self.is_superadmin:
            return "admin"
        return self.roles.get(structure_id)


def get_db(request: Request) -> Database:
    return request.app.state.db


def get_settings(request: Request):
    return request.app.state.settings


def current_user(request: Request, db: Database = Depends(get_db)) -> User:
    token = request.cookies.get(SESSION_COOKIE)
    if not token:
        raise HTTPException(401, "Session absente : veuillez vous connecter.")
    sess = db.one("SELECT * FROM sessions WHERE token_hash = ?", (token_hash(token),))
    if not sess or sess["expires_at"] < datetime.now(timezone.utc).isoformat(timespec="seconds"):
        raise HTTPException(401, "Session expirée : veuillez vous reconnecter.")
    u = db.one("SELECT * FROM users WHERE id = ?", (sess["user_id"],))
    if not u:
        raise HTTPException(401, "Compte introuvable.")
    roles = {r["structure_id"]: r["role"] for r in
             db.all("SELECT structure_id, role FROM memberships WHERE user_id = ?", (u["id"],))}
    return User(u["id"], u["username"], u["display_name"], bool(u["is_superadmin"]), u["active_structure_id"], roles)


def require_superadmin(user: User = Depends(current_user)) -> User:
    if not user.is_superadmin:
        raise HTTPException(403, "Réservé à l'administrateur général.")
    return user


def require_role(user: User, structure_id: str, minimum: str) -> None:
    role = user.role_in(structure_id)
    if role is None or ROLE_RANK[role] < ROLE_RANK[minimum]:
        raise HTTPException(403, f"Droits insuffisants (rôle « {minimum} » requis dans cette structure).")


def active_structure(user: User) -> str:
    sid = user.active_structure_id
    if not sid or user.role_in(sid) is None:
        raise HTTPException(400, "Aucune structure active : choisissez une structure.")
    return sid


# --------------------------------------------------------------------------- jeux de données


def dataset_access(db: Database, user: User, dataset_id: str) -> tuple[dict, str]:
    """Renvoie (jeu, mode) avec mode ∈ {"ecriture", "lecture"} ; 404 si inaccessible."""
    ds = db.one("SELECT * FROM datasets WHERE id = ?", (dataset_id,))
    if not ds:
        raise HTTPException(404, "Jeu de données introuvable.")
    role = user.role_in(ds["structure_id"])
    if role:
        return ds, ("ecriture" if ROLE_RANK[role] >= ROLE_RANK["analyste"] else "lecture")
    shared = db.all("SELECT structure_id FROM dataset_shares WHERE dataset_id = ?", (dataset_id,))
    if any(user.role_in(s["structure_id"]) for s in shared):
        return ds, "lecture"
    raise HTTPException(404, "Jeu de données introuvable.")


def writable_dataset(db: Database, user: User, dataset_id: str) -> dict:
    ds, mode = dataset_access(db, user, dataset_id)
    if mode != "ecriture":
        raise HTTPException(403, "Ce jeu de données est en lecture seule pour vous.")
    return ds


def raw_of(db: Database, ds: dict) -> dict:
    return db.one("SELECT * FROM raw_files WHERE id = ?", (ds["raw_id"],))


class Workspace:
    """Construit les plans d'exécution en résolvant les jeux associés (jointures, empilements)."""

    MAX_DEPTH = 8

    def __init__(self, db: Database, settings, user: User):
        self.db, self.settings, self.user = db, settings, user
        self.con = pipeline.connect()
        self._stack: list[str] = []
        self._token = RESOLVER.set(self._resolve)
        self._ltoken = geo.LAYER_RESOLVER.set(lambda lid: layer_source(db, settings, user, lid))

    def close(self):
        RESOLVER.reset(self._token)
        geo.LAYER_RESOLVER.reset(self._ltoken)
        self.con.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    def parquet(self, ds: dict):
        raw = raw_of(self.db, ds)
        return parquet_path(self.settings.raw_dir, raw["sha256"], raw["id"])

    def plan(self, ds: dict, recipe: list[dict] | None = None, upto: int | None = None) -> pipeline.Plan:
        if recipe is None:
            recipe = json.loads(ds["recipe"])
        self._stack.append(ds["id"])
        try:
            return pipeline.build(self.con, self.parquet(ds), recipe, upto=upto)
        finally:
            self._stack.pop()

    def check(self, ds: dict, prefix: list[dict], step: dict):
        """Valide une étape en tenant compte des références circulaires."""
        self._stack.append(ds["id"])
        try:
            return pipeline.check_step(self.con, self.parquet(ds), prefix, step)
        finally:
            self._stack.pop()

    def diagnose(self, ds: dict, before, step: dict):
        self._stack.append(ds["id"])
        try:
            return pipeline.diagnose(self.con, before, step)
        finally:
            self._stack.pop()

    def _resolve(self, dataset_id: str):
        if dataset_id in self._stack:
            raise RecipeError("Référence circulaire : un jeu ne peut pas s'associer à lui-même "
                              "(directement ou indirectement).")
        if len(self._stack) >= self.MAX_DEPTH:
            raise RecipeError("Trop de jeux imbriqués.")
        try:
            other, _ = dataset_access(self.db, self.user, dataset_id)
        except HTTPException as e:
            raise RecipeError("Le jeu de données associé est introuvable ou inaccessible.") from e
        p = self.plan(other)
        if p.error:
            raise RecipeError(f"Le jeu associé « {other['name']} » contient une erreur (étape {p.error['index']}) : "
                              f"{p.error['message']}")
        return p.sql, p.schema, other["name"]


# --------------------------------------------------------------------------- couches cartographiques

BUILTIN_PREFIX = "ctx:"


def layer_access(db: Database, user: User, layer_id: str, write: bool = False) -> dict:
    """Couche importée accessible (structure de l'utilisateur, ou publique en lecture)."""
    row = db.one("SELECT * FROM layers WHERE id = ?", (layer_id,))
    if not row:
        raise HTTPException(404, "Couche introuvable.")
    role = user.role_in(row["structure_id"])
    if write:
        if role is None or ROLE_RANK[role] < ROLE_RANK["analyste"]:
            raise HTTPException(403, "Droits insuffisants sur cette couche.")
    elif role is None and not row["public"]:
        raise HTTPException(404, "Couche introuvable.")
    return row


def layer_source(db: Database, settings, user: User, layer_id: str):
    """(chemin Parquet, colonnes, nom) d'une couche intégrée ou importée accessible."""
    if layer_id.startswith(BUILTIN_PREFIX):
        meta = geo.builtin_layers().get(layer_id[len(BUILTIN_PREFIX):])
        if not meta:
            raise RecipeError("Couche de contexte inconnue.")
        return geo.BUILTIN_DIR / meta["fichier"], [c["name"] for c in meta["columns"]], meta["nom"]
    try:
        row = layer_access(db, user, layer_id)
    except HTTPException as e:
        raise RecipeError("La couche est introuvable ou inaccessible.") from e
    info = json.loads(row["info"])
    return settings.layers_dir / row["id"] / "couche.parquet", [c["name"] for c in info["columns"]], row["name"]
