"""Copie l'extension spatiale DuckDB dans packaging/duckdb_ext pour l'embarquer dans l'exécutable."""

import shutil
from pathlib import Path

import duckdb

con = duckdb.connect()
con.execute("INSTALL spatial")
src = con.execute("SELECT install_path FROM duckdb_extensions() WHERE extension_name = 'spatial'").fetchone()[0]
dest = Path(__file__).parent / "duckdb_ext"
dest.mkdir(exist_ok=True)
shutil.copy(src, dest / "spatial.duckdb_extension")
print("extension copiee :", src, "->", dest)
