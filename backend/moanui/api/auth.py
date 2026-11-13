"""Première installation, connexion, profil."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field

from ..db import Database, new_id, now
from ..security import check_password_strength, hash_password, new_token, token_hash, verify_password
from ..themes import default_theme
from .deps import SESSION_COOKIE, User, current_user, get_db

router = APIRouter(prefix="/api", tags=["auth"])
SESSION_DAYS = 14


class SetupIn(BaseModel):
    username: str = Field(min_length=2, max_length=60)
    display_name: str = Field(min_length=1, max_length=120)
    password: str
    structure_name: str = Field(min_length=2, max_length=120)
    structure_short_name: str = Field(min_length=1, max_length=30)
    structure_kind: str = "autre"


class LoginIn(BaseModel):
    username: str
    password: str


class PasswordIn(BaseModel):
    current: str
    new: str


class ActiveIn(BaseModel):
    structure_id: str


def _open_session(db: Database, response: Response, user_id: str) -> None:
    token = new_token()
    expires = datetime.now(timezone.utc) + timedelta(days=SESSION_DAYS)
    db.execute("INSERT INTO sessions(token_hash, user_id, created_at, expires_at) VALUES (?,?,?,?)",
               (token_hash(token), user_id, now(), expires.isoformat(timespec="seconds")))
    response.set_cookie(SESSION_COOKIE, token, httponly=True, samesite="strict", max_age=SESSION_DAYS * 86400,
                        path="/")


@router.get("/setup/status")
def setup_status(db: Database = Depends(get_db)):
    n = db.one("SELECT count(*) AS n FROM users")["n"]
    return {"needs_setup": n == 0}


@router.post("/setup")
def setup(body: SetupIn, response: Response, db: Database = Depends(get_db)):
    """Création du premier compte (administrateur général) et de la première structure."""
    if err := check_password_strength(body.password):
        raise HTTPException(400, err)
    with db.transaction():
        if db.one("SELECT count(*) AS n FROM users")["n"] > 0:
            raise HTTPException(409, "Moanui est déjà initialisé.")
        uid, sid = new_id(), new_id()
        db.execute("INSERT INTO structures(id, name, short_name, kind, theme, created_at) VALUES (?,?,?,?,?,?)",
                   (sid, body.structure_name.strip(), body.structure_short_name.strip(), body.structure_kind,
                    json.dumps(default_theme()), now()))
        db.execute("INSERT INTO users(id, username, display_name, password_hash, is_superadmin, "
                   "active_structure_id, created_at) VALUES (?,?,?,?,1,?,?)",
                   (uid, body.username.strip(), body.display_name.strip(), hash_password(body.password), sid, now()))
        db.execute("INSERT INTO memberships(user_id, structure_id, role) VALUES (?,?, 'admin')", (uid, sid))
    db.log("installation", user_id=uid, structure_id=sid)
    _open_session(db, response, uid)
    return {"ok": True}


@router.post("/auth/login")
def login(body: LoginIn, response: Response, db: Database = Depends(get_db)):
    u = db.one("SELECT * FROM users WHERE username = ?", (body.username.strip(),))
    if not u or not verify_password(body.password, u["password_hash"]):
        db.log("connexion_refusee", username=body.username[:60])
        raise HTTPException(401, "Identifiant ou mot de passe incorrect.")
    db.execute("DELETE FROM sessions WHERE expires_at < ?", (now(),))
    _open_session(db, response, u["id"])
    db.log("connexion", user_id=u["id"])
    return {"ok": True}


@router.post("/auth/logout")
def logout(request: Request, response: Response, db: Database = Depends(get_db)):
    token = request.cookies.get(SESSION_COOKIE)
    if token:
        db.execute("DELETE FROM sessions WHERE token_hash = ?", (token_hash(token),))
    response.delete_cookie(SESSION_COOKIE, path="/")
    return {"ok": True}


def structure_public(s: dict) -> dict:
    theme = json.loads(s["theme"])
    return {"id": s["id"], "name": s["name"], "short_name": s["short_name"], "kind": s["kind"], "theme": theme,
            "has_logo": bool(theme.get("logo"))}


@router.get("/auth/me")
def me(user: User = Depends(current_user), db: Database = Depends(get_db)):
    if user.is_superadmin:
        rows = db.all("SELECT * FROM structures ORDER BY name")
    else:
        rows = db.all("SELECT s.* FROM structures s JOIN memberships m ON m.structure_id = s.id "
                      "WHERE m.user_id = ? ORDER BY s.name", (user.id,))
    structures = [{**structure_public(s), "role": user.role_in(s["id"])} for s in rows]
    active = user.active_structure_id if any(s["id"] == user.active_structure_id for s in structures) else (
        structures[0]["id"] if structures else None)
    return {
        "id": user.id,
        "username": user.username,
        "display_name": user.display_name,
        "is_superadmin": user.is_superadmin,
        "structures": structures,
        "active_structure_id": active,
    }


@router.post("/auth/active-structure")
def set_active(body: ActiveIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    if user.role_in(body.structure_id) is None or not db.one("SELECT id FROM structures WHERE id = ?",
                                                             (body.structure_id,)):
        raise HTTPException(403, "Vous n'appartenez pas à cette structure.")
    db.execute("UPDATE users SET active_structure_id = ? WHERE id = ?", (body.structure_id, user.id))
    return {"ok": True}


@router.post("/auth/password")
def change_password(body: PasswordIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    u = db.one("SELECT password_hash FROM users WHERE id = ?", (user.id,))
    if not verify_password(body.current, u["password_hash"]):
        raise HTTPException(400, "Mot de passe actuel incorrect.")
    if err := check_password_strength(body.new):
        raise HTTPException(400, err)
    db.execute("UPDATE users SET password_hash = ? WHERE id = ?", (hash_password(body.new), user.id))
    db.log("mot_de_passe_modifie", user_id=user.id)
    return {"ok": True}
