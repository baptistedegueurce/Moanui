# -*- mode: python ; coding: utf-8 -*-
# Construction : pyinstaller packaging/moanui.spec (depuis la racine du dépôt, interface déjà construite)
import os
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

ROOT = os.path.abspath(os.path.join(SPECPATH, ".."))
PKG = os.path.join(ROOT, "backend", "moanui")

datas = [
    (os.path.join(PKG, "static"), "moanui/static"),
    (os.path.join(PKG, "themes"), "moanui/themes"),
    (os.path.join(PKG, "referentiels"), "moanui/referentiels"),
    (os.path.join(PKG, "couches"), "moanui/couches"),
    (os.path.join(PKG, "polices"), "moanui/polices"),
]
# extension spatiale DuckDB (cartographie) : copiée par le workflow avant la construction
_ext = os.path.join(SPECPATH, "duckdb_ext", "spatial.duckdb_extension")
if os.path.exists(_ext):
    datas.append((_ext, "duckdb_ext"))
datas += collect_data_files("openpyxl") + collect_data_files("docx") + collect_data_files("fpdf")

hiddenimports = (
    collect_submodules("uvicorn")
    + collect_submodules("moanui")
    + ["multipart", "python_multipart", "resvg_py"]
)

a = Analysis(
    [os.path.join(SPECPATH, "lanceur.py")],
    pathex=[os.path.join(ROOT, "backend")],
    datas=datas,
    hiddenimports=hiddenimports,
    excludes=["tkinter", "matplotlib", "pandas", "pyarrow", "IPython", "yaml", "pytest", "scipy.datasets"],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="Moanui",
    icon=os.path.join(SPECPATH, "moanui.ico") if os.path.exists(os.path.join(SPECPATH, "moanui.ico")) else None,
    console=True,  # fenêtre console : affiche l'adresse ; la fermer arrête Moanui
    upx=False,
)
coll = COLLECT(exe, a.binaries, a.datas, name="Moanui", upx=False)
