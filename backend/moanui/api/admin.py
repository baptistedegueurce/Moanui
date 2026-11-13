"""Administration : structures, comptes, chartes graphiques, logos."""

from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from ..db import Database, new_id, now
from ..engine.sql import RecipeError
from ..security import check_password_strength, hash_password
from ..themes import default_theme, presets, validate_theme
from .auth import structure_public
from .deps import User, current_user, get_db, get_settings, require_role, require_superadmin

router = APIRouter(prefix="/api", tags=["admin"])

STRUCTURE_KINDS = {"crpm": "Comité régional (CRPM)", "cdpm": "Comité départemental (CDPMEM)",
                   "cnpm": "Comité national (CNPMEM)", "op": "Organisation de producteurs (OP)",
                   "autre": "Autre"}
LOGO_TYPES = {"image/png": ".png", "image/jpeg": ".jpg", "image/svg+xml": ".svg", "image/webp": ".webp"}
MAX_LOGO = 2 * 1024 * 1024


class StructureIn(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    short_name: str = Field(min_length=1, max_length=30)
    kind: str = "autre"
    preset: str | None = None


class StructurePatch(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    short_name: str | None = Field(default=None, min_length=1, max_length=30)
    kind: str | None = None
    theme: dict | None = None


class UserIn(BaseModel):
    username: str = Field(min_length=2, max_length=60)
    display_name: str = Field(min_length=1, max_length=120)
    password: str
    is_superadmin: bool = False
    memberships: list[dict] = []


class UserPatch(BaseModel):
    display_name: str | None = None
    password: str | None = None
    is_superadmin: bool | None = None
    memberships: list[dict] | None = None


def _bad(e: RecipeError):
    raise HTTPException(400, str(e))


@router.get("/themes/presets")
def theme_presets(_: User = Depends(current_user)):
    return presets()


@router.get("/admin/structure-kinds")
def kinds(_: User = Depends(current_user)):
    return STRUCTURE_KINDS


@router.get("/admin/structures")
def list_structures(_: User = Depends(require_superadmin), db: Database = Depends(get_db)):
    rows = db.all("SELECT * FROM structures ORDER BY name")
    counts = {r["structure_id"]: r["n"] for r in
              db.all("SELECT structure_id, count(*) AS n FROM memberships GROUP BY 1")}
    return [{**structure_public(s), "members": counts.get(s["id"], 0)} for s in rows]


@router.post("/admin/structures")
def create_structure(body: StructureIn, user: User = Depends(require_superadmin), db: Database = Depends(get_db)):
    if body.kind not in STRUCTURE_KINDS:
        raise HTTPException(400, "Type de structure inconnu.")
    theme = presets().get(body.preset or "neutre", default_theme())
    sid = new_id()
    try:
        db.execute("INSERT INTO structures(id, name, short_name, kind, theme, created_at) VALUES (?,?,?,?,?,?)",
                   (sid, body.name.strip(), body.short_name.strip(), body.kind, json.dumps(theme), now()))
    except Exception as e:
        raise HTTPException(409, "Une structure porte déjà ce nom.") from e
    db.log("structure_creee", user_id=user.id, structure_id=sid, name=body.name)
    return {"id": sid}


@router.patch("/structures/{sid}")
def update_structure(sid: str, body: StructurePatch, user: User = Depends(current_user),
                     db: Database = Depends(get_db)):
    """L'administrateur d'une structure peut modifier sa charte ; le nom reste au super-admin."""
    require_role(user, sid, "admin")
    s = db.one("SELECT * FROM structures WHERE id = ?", (sid,))
    if not s:
        raise HTTPException(404, "Structure introuvable.")
    if (body.name or body.short_name or body.kind) and not user.is_superadmin:
        raise HTTPException(403, "Seul l'administrateur général peut renommer une structure.")
    if body.kind and body.kind not in STRUCTURE_KINDS:
        raise HTTPException(400, "Type de structure inconnu.")
    theme = json.loads(s["theme"])
    if body.theme is not None:
        try:
            new_theme = validate_theme(body.theme)
        except RecipeError as e:
            _bad(e)
        new_theme["logo"] = theme.get("logo")  # le logo ne se change que par téléversement
        theme = new_theme
    db.execute("UPDATE structures SET name = ?, short_name = ?, kind = ?, theme = ? WHERE id = ?",
               (body.name or s["name"], body.short_name or s["short_name"], body.kind or s["kind"],
                json.dumps(theme), sid))
    db.log("structure_modifiee", user_id=user.id, structure_id=sid)
    return structure_public(db.one("SELECT * FROM structures WHERE id = ?", (sid,)))


@router.post("/structures/{sid}/logo")
async def upload_logo(sid: str, file: UploadFile = File(...), user: User = Depends(current_user),
                      db: Database = Depends(get_db), settings=Depends(get_settings)):
    require_role(user, sid, "admin")
    s = db.one("SELECT * FROM structures WHERE id = ?", (sid,))
    if not s:
        raise HTTPException(404, "Structure introuvable.")
    ext = LOGO_TYPES.get(file.content_type or "")
    if not ext:
        raise HTTPException(400, "Format de logo accepté : PNG, JPEG, SVG ou WEBP.")
    data = await file.read(MAX_LOGO + 1)
    if len(data) > MAX_LOGO:
        raise HTTPException(400, "Logo trop lourd (2 Mo maximum).")
    if ext == ".svg" and (b"<script" in data.lower() or b"javascript:" in data.lower()):
        raise HTTPException(400, "Ce fichier SVG contient du code : refusé par sécurité.")
    folder = settings.assets_dir / sid
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("logo.*"):
        old.unlink()
    (folder / f"logo{ext}").write_bytes(data)
    theme = json.loads(s["theme"])
    theme["logo"] = f"logo{ext}"
    db.execute("UPDATE structures SET theme = ? WHERE id = ?", (json.dumps(theme), sid))
    db.log("logo_modifie", user_id=user.id, structure_id=sid)
    return {"ok": True}


@router.get("/structures/{sid}/logo")
def get_logo(sid: str, user: User = Depends(current_user), db: Database = Depends(get_db),
             settings=Depends(get_settings)):
    s = db.one("SELECT theme FROM structures WHERE id = ?", (sid,))
    if not s:
        raise HTTPException(404, "Structure introuvable.")
    logo = json.loads(s["theme"]).get("logo")
    if not logo:
        raise HTTPException(404, "Pas de logo.")
    path = settings.assets_dir / sid / Path(logo).name
    if not path.exists():
        raise HTTPException(404, "Pas de logo.")
    return FileResponse(path, headers={"Cache-Control": "no-cache", "Content-Security-Policy": "script-src 'none'"})


# --------------------------------------------------------------------------- comptes


def _members_out(db: Database, uid: str) -> list[dict]:
    return db.all("SELECT m.structure_id, m.role, s.name FROM memberships m JOIN structures s ON s.id = m.structure_id "
                  "WHERE m.user_id = ? ORDER BY s.name", (uid,))


def _set_memberships(db: Database, uid: str, memberships: list[dict]) -> None:
    db.execute("DELETE FROM memberships WHERE user_id = ?", (uid,))
    for m in memberships:
        if m.get("role") not in ("admin", "analyste", "lecteur"):
            raise HTTPException(400, "Rôle inconnu (admin, analyste ou lecteur).")
        if not db.one("SELECT id FROM structures WHERE id = ?", (m.get("structure_id"),)):
            raise HTTPException(400, "Structure inconnue.")
        db.execute("INSERT INTO memberships(user_id, structure_id, role) VALUES (?,?,?)",
                   (uid, m["structure_id"], m["role"]))
    first = memberships[0]["structure_id"] if memberships else None
    db.execute("UPDATE users SET active_structure_id = coalesce(active_structure_id, ?) WHERE id = ?", (first, uid))


@router.get("/admin/users")
def list_users(_: User = Depends(require_superadmin), db: Database = Depends(get_db)):
    users = db.all("SELECT id, username, display_name, is_superadmin, created_at FROM users ORDER BY username")
    return [{**u, "is_superadmin": bool(u["is_superadmin"]), "memberships": _members_out(db, u["id"])}
            for u in users]


@router.post("/admin/users")
def create_user(body: UserIn, admin: User = Depends(require_superadmin), db: Database = Depends(get_db)):
    if err := check_password_strength(body.password):
        raise HTTPException(400, err)
    uid = new_id()
    with db.transaction():
        if db.one("SELECT id FROM users WHERE username = ?", (body.username.strip(),)):
            raise HTTPException(409, "Cet identifiant existe déjà.")
        db.execute("INSERT INTO users(id, username, display_name, password_hash, is_superadmin, created_at) "
                   "VALUES (?,?,?,?,?,?)", (uid, body.username.strip(), body.display_name.strip(),
                                            hash_password(body.password), int(body.is_superadmin), now()))
        _set_memberships(db, uid, body.memberships)
    db.log("compte_cree", user_id=admin.id, target=uid)
    return {"id": uid}


@router.patch("/admin/users/{uid}")
def update_user(uid: str, body: UserPatch, admin: User = Depends(require_superadmin), db: Database = Depends(get_db)):
    u = db.one("SELECT * FROM users WHERE id = ?", (uid,))
    if not u:
        raise HTTPException(404, "Compte introuvable.")
    with db.transaction():
        if body.display_name:
            db.execute("UPDATE users SET display_name = ? WHERE id = ?", (body.display_name.strip(), uid))
        if body.password:
            if err := check_password_strength(body.password):
                raise HTTPException(400, err)
            db.execute("UPDATE users SET password_hash = ? WHERE id = ?", (hash_password(body.password), uid))
            db.execute("DELETE FROM sessions WHERE user_id = ?", (uid,))
        if body.is_superadmin is not None:
            if uid == admin.id and not body.is_superadmin:
                raise HTTPException(400, "Vous ne pouvez pas retirer vos propres droits d'administrateur général.")
            db.execute("UPDATE users SET is_superadmin = ? WHERE id = ?", (int(body.is_superadmin), uid))
        if body.memberships is not None:
            _set_memberships(db, uid, body.memberships)
    db.log("compte_modifie", user_id=admin.id, target=uid)
    return {"ok": True}


@router.delete("/admin/users/{uid}")
def delete_user(uid: str, admin: User = Depends(require_superadmin), db: Database = Depends(get_db)):
    if uid == admin.id:
        raise HTTPException(400, "Vous ne pouvez pas supprimer votre propre compte.")
    if db.one("SELECT id FROM datasets WHERE created_by = ? LIMIT 1", (uid,)):
        # on garde la traçabilité : le compte est désactivé (mot de passe invalidé) plutôt que supprimé
        db.execute("UPDATE users SET password_hash = '!desactive' WHERE id = ?", (uid,))
        db.execute("DELETE FROM sessions WHERE user_id = ?", (uid,))
        db.execute("DELETE FROM memberships WHERE user_id = ?", (uid,))
        db.log("compte_desactive", user_id=admin.id, target=uid)
        return {"ok": True, "desactive": True}
    db.execute("DELETE FROM users WHERE id = ?", (uid,))
    db.log("compte_supprime", user_id=admin.id, target=uid)
    return {"ok": True}


@router.get("/admin/journal")
def journal(limit: int = 200, _: User = Depends(require_superadmin), db: Database = Depends(get_db)):
    rows = db.all("SELECT j.*, u.display_name AS user_name FROM journal j LEFT JOIN users u ON u.id = j.user_id "
                  "ORDER BY j.id DESC LIMIT ?", (min(limit, 2000),))
    for r in rows:
        r["details"] = json.loads(r["details"])
    return rows
