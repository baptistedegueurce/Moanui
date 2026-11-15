"""Version et notes de version des exécutables publiés par GitHub Actions.

    python outils/notes_de_version.py version      -> écrit tag=, version=, kind= (format GITHUB_OUTPUT)
    python outils/notes_de_version.py notes FICHIER -> écrit les notes Markdown de la release

Règles :
- `__version__` (backend/moanui/__init__.py) sans suffixe `.devN` et étiquette `v<version>` absente
  -> version stable `v<version>` (marquée « Latest ») ;
- sinon -> pré-version `v<base>-dev.<nombre de commits>` à chaque push.
Les notes reprennent la section du CHANGELOG.md (« Non publié » pour une pré-version, `[x.y.z]` pour une
stable) puis la liste des commits depuis la release précédente, sans les lignes d'attribution.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INIT = ROOT / "backend" / "moanui" / "__init__.py"
CHANGELOG = ROOT / "CHANGELOG.md"
TRAILERS = re.compile(r"^(Co-Authored-By|Claude-Session|Signed-off-by):", re.I)
MAX_COMMITS = 40


def git(*args: str) -> str:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, encoding="utf-8")
    return r.stdout.strip() if r.returncode == 0 else ""


def source_version() -> str:
    # version du commit (et non du fichier, que « stamp » réécrit pendant la construction)
    txt = git("show", "HEAD:backend/moanui/__init__.py") or INIT.read_text(encoding="utf-8")
    m = re.search(r'__version__\s*=\s*"([^"]+)"', txt)
    if not m:
        sys.exit("__version__ introuvable")
    return m.group(1)


def compute() -> dict:
    v = source_version()
    base = re.sub(r"\.?dev\d*$", "", v)
    stable = base == v and not git("tag", "--list", f"v{v}")
    if stable:
        return {"kind": "stable", "version": v, "tag": f"v{v}"}
    n = git("rev-list", "--count", "HEAD") or "0"
    dv = f"{base}-dev.{n}"
    return {"kind": "dev", "version": dv, "tag": f"v{dv}"}


def changelog_section(title: str) -> str:
    if not CHANGELOG.exists():
        return ""
    out, on = [], False
    for line in CHANGELOG.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            if on:
                break
            on = line[3:].strip().lstrip("[").lower().startswith(title.lower())
            continue
        if on:
            out.append(line)
    return "\n".join(out).strip()


def previous_tag(kind: str) -> str:
    args = ["describe", "--tags", "--abbrev=0", "--match", "v*"]
    if kind == "stable":
        args += ["--exclude", "*-dev*"]
    return git(*args, "HEAD^")


def commits(since: str) -> list[tuple[str, str, list[str]]]:
    rng = f"{since}..HEAD" if since else "HEAD"
    raw = git("log", rng, f"-{MAX_COMMITS}", "--no-merges", "--format=%h%x1f%s%x1f%b%x1e")
    res = []
    for rec in raw.split("\x1e"):
        rec = rec.strip()
        if not rec:
            continue
        h, s, b = (rec.split("\x1f") + ["", ""])[:3]
        body = [l.rstrip() for l in b.splitlines() if l.strip() and not TRAILERS.match(l.strip())]
        res.append((h, s.strip(), body))
    return res


def notes(info: dict) -> str:
    kind, version = info["kind"], info["version"]
    section = changelog_section(version if kind == "stable" else "Non publié")
    since = previous_tag(kind)
    lines = [f"# Moanui {version}", ""]
    if kind == "dev":
        lines += ["Version de développement, construite automatiquement à chaque modification.", ""]
    lines += ["## Nouveautés", "", section or "_Pas de résumé dans le CHANGELOG._", ""]
    lines += [f"## Détail des modifications" + (f" depuis {since}" if since else ""), ""]
    cs = commits(since)
    for h, s, body in cs:
        lines.append(f"- **{s}** ({h})")
        lines += [f"  {l}" for l in body]
    if not cs:
        lines.append("_Aucune modification de code._")
    if len(cs) == MAX_COMMITS:
        lines.append(f"- … (liste limitée aux {MAX_COMMITS} dernières modifications)")
    lines += ["", "## Installation", "",
              "**Recommandé : Moanui-installation.exe** (ci-dessous). Installation pour l'utilisateur courant, "
              "sans droits administrateur, avec raccourcis dans le menu Démarrer et sur le bureau. Au premier "
              "lancement, Windows peut afficher « Windows a protégé votre ordinateur » (application non signée) : "
              "cliquer sur « Informations complémentaires » puis « Exécuter quand même ». Pour mettre à jour, "
              "lancer simplement le nouvel installateur.", "",
              "**Version portable : Moanui-windows.zip.** Avant d'extraire, clic droit sur le zip > Propriétés > "
              "cocher « Débloquer » > OK (sinon Windows refuse de charger les fichiers extraits et la fenêtre se "
              "referme aussitôt). Puis Extraire tout et lancer Moanui.exe.", "",
              "Dans les deux cas, les données restent dans `%LOCALAPPDATA%\\Moanui` et sont conservées d'une "
              "version à l'autre (la désinstallation n'y touche pas).", ""]
    return "\n".join(lines)


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "version"
    info = compute()
    if cmd == "version":
        out = "".join(f"{k}={v}\n" for k, v in info.items())
        gh = os.environ.get("GITHUB_OUTPUT")
        if gh:
            with open(gh, "a", encoding="utf-8") as f:
                f.write(out)
        sys.stdout.write(out)
    elif cmd == "stamp":  # inscrit la version publiée dans le paquet (affichée par l'appli)
        txt = INIT.read_text(encoding="utf-8")
        INIT.write_text(re.sub(r'__version__\s*=\s*"[^"]+"', f'__version__ = "{info["version"]}"', txt),
                        encoding="utf-8")
        print(info["version"])
    elif cmd == "notes":
        Path(sys.argv[2]).write_text(notes(info), encoding="utf-8")
    else:
        sys.exit(f"commande inconnue : {cmd}")


if __name__ == "__main__":
    main()
