"""Import des fichiers bruts.

Principe : le fichier d'origine est copié tel quel (empreinte SHA-256), puis
converti en Parquet typé. Les deux copies sont en lecture seule ; toutes les
modifications passent ensuite par une recette.

Détection des types « à la française » : virgule décimale, dates JJ/MM/AAAA,
et les codes à zéros initiaux (« 0123 ») restent du texte pour ne rien perdre.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import stat
from datetime import date, datetime, time
from pathlib import Path

import duckdb

from .sql import ROW_ID, RecipeError, ident, string_lit

SUPPORTED = {".csv": "csv", ".txt": "csv", ".tsv": "csv", ".xlsx": "xlsx", ".xlsm": "xlsx"}
MAX_COLUMNS = 2000


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def make_read_only(path: Path) -> None:
    os.chmod(path, stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)


def _options_key(options: dict) -> str:
    return hashlib.sha256(json.dumps(options, sort_keys=True).encode()).hexdigest()[:10]


def _unique_names(names: list[str]) -> list[str]:
    out, seen = [], {}
    for i, n in enumerate(names):
        n = (str(n).strip() if n is not None else "") or f"colonne_{i + 1}"
        if n.startswith("__"):
            n = n.lstrip("_") or f"colonne_{i + 1}"
        base, k = n, 1
        while n.lower() in seen:
            k += 1
            n = f"{base}_{k}"
        seen[n.lower()] = True
        out.append(n)
    return out


# --------------------------------------------------------------------------- lecture texte brut


def _detect_encoding(path: Path) -> str:
    with open(path, "rb") as f:
        head = f.read(1 << 20)
    if head.startswith(b"\xef\xbb\xbf"):
        return "utf-8"
    try:
        head.decode("utf-8")
        return "utf-8"
    except UnicodeDecodeError as e:
        # coupure possible au milieu d'un caractère en fin de bloc
        if e.start > len(head) - 4:
            return "utf-8"
        return "latin-1"


def _detect_delimiter(path: Path, encoding: str) -> str:
    with open(path, encoding=encoding, errors="replace") as f:
        lines = [f.readline() for _ in range(20)]
    lines = [ln for ln in lines if ln.strip()]
    best, best_score = ",", -1
    for d in (";", ",", "\t", "|"):
        counts = [ln.count(d) for ln in lines]
        if not counts or counts[0] == 0:
            continue
        score = counts[0] * 10 - sum(abs(c - counts[0]) for c in counts)
        if score > best_score:
            best, best_score = d, score
    return best


def _read_csv_into(con, src: Path, delim: str, header: bool) -> None:
    """Charge un CSV en table DuckDB « brut0 », tout en texte, dans l'ordre du fichier."""
    con.execute(
        f"CREATE OR REPLACE TABLE brut0 AS SELECT * FROM read_csv({string_lit(str(src))}, delim={string_lit(delim)}, "
        f"header={str(bool(header)).lower()}, all_varchar=true, quote='\"', escape='\"', null_padding=true, "
        "ignore_errors=false, sample_size=-1, strict_mode=false)"
    )


def read_csv_as_text(con, path: Path, options: dict) -> dict:
    encoding = options.get("encoding") or _detect_encoding(path)
    delim = options.get("delimiter") or _detect_delimiter(path, encoding)
    header = options.get("header", True)
    src = path
    if encoding not in ("utf-8", "utf8"):
        # DuckDB lit l'UTF-8 nativement : on transcode dans une copie temporaire.
        src = path.with_suffix(".utf8.tmp")
        with open(path, encoding=encoding, errors="replace") as fi, open(src, "w", encoding="utf-8") as fo:
            shutil.copyfileobj(fi, fo, 1 << 20)
    try:
        _read_csv_into(con, src, delim, header)
    finally:
        if src != path:
            src.unlink(missing_ok=True)
    return {"encoding": encoding, "delimiter": delim, "header": bool(header)}


def _cell_to_text(v) -> str | None:
    if v is None:
        return None
    if isinstance(v, bool):
        return "vrai" if v else "faux"
    if isinstance(v, datetime):
        return v.date().isoformat() if v.time() == time(0) else v.isoformat(sep=" ")
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, float):
        return str(int(v)) if v.is_integer() and abs(v) < 1e15 else repr(v)
    s = str(v)
    return s if s.strip() != "" else None


def list_sheets(path: Path) -> list[str]:
    from openpyxl import load_workbook

    wb = load_workbook(path, read_only=True)
    try:
        return list(wb.sheetnames)
    finally:
        wb.close()


def read_xlsx_as_text(con, path: Path, options: dict) -> dict:
    """Feuille Excel → CSV temporaire (tout en texte) → table DuckDB « brut0 »."""
    from openpyxl import load_workbook

    wb = load_workbook(path, read_only=True, data_only=True)
    tmp = path.with_suffix(".feuille.tmp.csv")
    try:
        sheet = options.get("sheet") or wb.sheetnames[0]
        if sheet not in wb.sheetnames:
            raise RecipeError(f"La feuille « {sheet} » n'existe pas dans ce classeur.")
        ws = wb[sheet]
        skip = int(options.get("skip_rows") or 0)
        rows = ws.iter_rows(values_only=True)
        for _ in range(skip):
            next(rows, None)
        header = options.get("header", True)
        first = next(rows, None)
        if first is None:
            raise RecipeError("La feuille est vide.")
        width = len(first)
        names = _unique_names(list(first) if header else [f"colonne_{i + 1}" for i in range(width)])
        n_written = 0
        used_cols = [header and first[i] is not None for i in range(width)]
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f, delimiter=";", quoting=csv.QUOTE_ALL)
            w.writerow(names)
            pending = [] if header else [first]
            for r in pending + [r for r in rows]:
                if r is None or all(v is None for v in r):
                    continue
                vals = [_cell_to_text(r[i]) if i < len(r) else None for i in range(width)]
                for i, v in enumerate(vals):
                    if v is not None:
                        used_cols[i] = True
                w.writerow(["" if v is None else v for v in vals])
                n_written += 1
        _read_csv_into(con, tmp, ";", True)
        # colonnes entièrement vides et sans en-tête : retirées
        drop = [names[i] for i in range(width) if not used_cols[i]]
        if drop and len(drop) < width:
            con.execute(f"CREATE OR REPLACE TABLE brut0 AS SELECT * EXCLUDE ({', '.join(ident(d) for d in drop)}) "
                        "FROM brut0 ORDER BY rowid")
        return {"sheet": sheet, "header": bool(header), "skip_rows": skip}
    finally:
        wb.close()
        tmp.unlink(missing_ok=True)


# --------------------------------------------------------------------------- détection des types

NULL_TOKENS = ("na", "n/a", "#n/a", "null", "nan", "none", "#valeur!", "#value!", "#div/0!", "#ref!")

_LEAD0 = r"^[-+]?0\d+$"


def _clean(c: str) -> str:
    v = f"nullif(trim({ident(c)}), '')"
    toks = ", ".join(string_lit(t) for t in NULL_TOKENS)
    return f"(CASE WHEN lower({v}) IN ({toks}) THEN NULL ELSE {v} END)"


# candidats : (nom, type, expression de conversion à partir de {v}, libellé)
_CANDIDATES = [
    # motifs stricts : DuckDB accepterait « 12.5 » en entier (arrondi) et « 25E4 » (rectangle CIEM) en nombre
    ("entier", "CAST({v} AS BIGINT)",
     "(CASE WHEN regexp_full_match({v}, '^[-+]?\\d{{1,18}}$') THEN TRY_CAST({v} AS BIGINT) END)", "nombre entier"),
    ("decimal", "CAST({v} AS DOUBLE)",
     "(CASE WHEN regexp_full_match({v}, '^[-+]?(\\d+(\\.\\d*)?|\\.\\d+)$') THEN TRY_CAST({v} AS DOUBLE) END)",
     "nombre décimal"),
    ("decimal_virgule", "CAST(replace({v}, ',', '.') AS DOUBLE)",
     "(CASE WHEN regexp_full_match({v}, '^[-+]?\\d+(,\\d+)?$') THEN TRY_CAST(replace({v}, ',', '.') AS DOUBLE) END)",
     "nombre décimal"),
    ("date", "CAST({v} AS DATE)",
     "(CASE WHEN regexp_full_match({v}, '\\d{{4}}-\\d{{2}}-\\d{{2}}') THEN TRY_CAST({v} AS DATE) END)", "date"),
    ("date_fr", "CAST(strptime({v}, '%d/%m/%Y') AS DATE)",
     "(CASE WHEN regexp_full_match({v}, '\\d{{1,2}}/\\d{{1,2}}/\\d{{4}}') THEN try_strptime({v}, '%d/%m/%Y') END)",
     "date"),
    ("dateheure", "CAST({v} AS TIMESTAMP)",
     "(CASE WHEN regexp_full_match({v}, '\\d{{4}}-\\d{{2}}-\\d{{2}}([ T]\\d{{2}}:\\d{{2}}(:\\d{{2}}(\\.\\d+)?)?)?') "
     "THEN TRY_CAST({v} AS TIMESTAMP) END)", "date et heure"),
    ("dateheure_fr", "coalesce(try_strptime({v}, '%d/%m/%Y %H:%M:%S'), try_strptime({v}, '%d/%m/%Y %H:%M'))",
     "coalesce(try_strptime({v}, '%d/%m/%Y %H:%M:%S'), try_strptime({v}, '%d/%m/%Y %H:%M'))", "date et heure"),
    ("booleen", "(lower({v}) IN ('vrai', 'true'))",
     "(CASE WHEN lower({v}) IN ('vrai', 'true', 'faux', 'false') THEN TRUE END)", "vrai/faux"),
]
_FINAL_TYPE = {"entier": "entier", "decimal": "decimal", "decimal_virgule": "decimal", "date": "date",
               "date_fr": "date", "dateheure": "dateheure", "dateheure_fr": "dateheure", "booleen": "booleen"}
_NOTES = {"decimal_virgule": "virgule décimale convertie", "date_fr": "dates JJ/MM/AAAA",
          "dateheure_fr": "dates JJ/MM/AAAA hh:mm"}


def infer_types(con, view: str, columns: list[str]) -> dict[str, dict]:
    """Pour chaque colonne, propose un type et l'expression de conversion.

    Une conversion n'est retenue que si 100 % des valeurs renseignées la
    réussissent : on ne perd jamais une valeur en silence. Sinon la colonne
    reste en texte, avec un avertissement et des exemples de valeurs fautives.
    """
    if not columns:
        return {}
    out = {}
    for c in columns:
        v = _clean(c)
        exprs = [f"count({v})", f"count_if(regexp_full_match({v}, '{_LEAD0}'))",
                 f"count_if(lower(trim({ident(c)})) IN ({', '.join(string_lit(t) for t in NULL_TOKENS)}))"]
        exprs += [f"count({test.format(v=v)})" for _, _, test, _ in _CANDIDATES]
        row = con.execute(f"SELECT {', '.join(exprs)} FROM {view}").fetchone()
        n, lead0, null_tok = row[0], row[1], row[2]
        ok = dict(zip([k for k, *_ in _CANDIDATES], row[3:]))
        note_null = f"{null_tok} valeur(s) « NA »/« NULL » lues comme vides" if null_tok else ""
        if n == 0:
            out[c] = {"type": "texte", "sql": v, "note": "colonne vide", "warning": None}
            continue
        chosen = None
        for k, *_ in _CANDIDATES:
            if ok[k] == n:
                chosen = k
                break
        if chosen in ("entier", "decimal", "decimal_virgule") and lead0:
            out[c] = {"type": "texte", "sql": v, "warning": None,
                      "note": ", ".join(x for x in ["codes à zéros initiaux conservés en texte", note_null] if x)}
            continue
        if chosen:
            conv = next(conv for k, conv, *_ in _CANDIDATES if k == chosen)
            out[c] = {"type": _FINAL_TYPE[chosen], "sql": conv.format(v=v), "warning": None,
                      "note": ", ".join(x for x in [_NOTES.get(chosen, ""), note_null] if x)}
            continue
        # presque convertible ? on prévient sans rien perdre
        best = max(ok, key=lambda k: ok[k])
        warning = None
        if ok[best] >= 0.9 * n and ok[best] < n:
            test = next(t for k, _, t, _ in _CANDIDATES if k == best)
            label = next(lb for k, _, _, lb in _CANDIDATES if k == best)
            bad = [r[0] for r in con.execute(
                f"SELECT DISTINCT {v} FROM {view} WHERE {v} IS NOT NULL AND {test.format(v=v)} IS NULL LIMIT 5"
            ).fetchall()]
            warning = {
                "suggested_type": _FINAL_TYPE[best],
                "invalid_count": n - ok[best],
                "examples": bad,
                "message": f"{n - ok[best]} valeur(s) empêchent de lire cette colonne comme {label} "
                           f"(ex. : {', '.join(map(str, bad[:3]))}). Elle est gardée en texte : corrigez ces "
                           "valeurs puis changez son type.",
            }
        out[c] = {"type": "texte", "sql": v, "note": note_null, "warning": warning}
    return out


# --------------------------------------------------------------------------- import


def import_file(src: Path, original_name: str, raw_dir: Path, options: dict | None = None) -> dict:
    """Copie le fichier brut, le convertit en Parquet typé et renvoie le rapport d'import."""
    options = dict(options or {})
    ext = Path(original_name).suffix.lower()
    fmt = SUPPORTED.get(ext)
    if fmt is None:
        raise RecipeError(f"Format non pris en charge : « {ext or 'sans extension'} ». "
                          "Formats acceptés : CSV, TXT, TSV, XLSX.")
    sha = file_sha256(src)
    key_opts = {k: v for k, v in options.items() if k in ("encoding", "delimiter", "header", "sheet", "skip_rows",
                                                          "keep_text")}
    raw_id = f"{sha[:16]}-{_options_key(key_opts)}"
    folder = raw_dir / sha
    folder.mkdir(parents=True, exist_ok=True)
    source_copy = folder / f"source{ext}"
    if not source_copy.exists():
        shutil.copyfile(src, source_copy)
        make_read_only(source_copy)
    parquet = folder / f"{raw_id}.parquet"

    con = duckdb.connect()
    try:
        if fmt == "csv":
            used = read_csv_as_text(con, source_copy, options)
        else:
            used = read_xlsx_as_text(con, source_copy, options)
        raw_names = [r[0] for r in con.execute("DESCRIBE brut0").fetchall()]
        if len(raw_names) > MAX_COLUMNS:
            raise RecipeError(f"Trop de colonnes ({len(raw_names)}). Vérifiez le séparateur.")
        names = _unique_names(raw_names)
        # numéro de ligne d'origine : rowid suit l'ordre d'insertion, donc l'ordre du fichier
        con.execute("CREATE OR REPLACE TABLE brut AS SELECT CAST(rowid + 1 AS BIGINT) AS " + ident(ROW_ID) + ", "
                    + ", ".join(f"{ident(o)} AS {ident(n)}" for o, n in zip(raw_names, names))
                    + " FROM brut0 ORDER BY rowid")
        keep_text = set(options.get("keep_text") or [])
        types = infer_types(con, "brut", [c for c in names if c not in keep_text])
        for c in keep_text:
            if c in names:
                types[c] = {"type": "texte", "sql": _clean(c), "note": "forcé en texte", "warning": None}
        select = [ident(ROW_ID)]
        select += [f"{types[c]['sql']} AS {ident(c)}" for c in names]
        if not parquet.exists():
            tmp = parquet.with_suffix(".tmp")
            con.execute(f"COPY (SELECT {', '.join(select)} FROM brut ORDER BY {ident(ROW_ID)}) TO {string_lit(str(tmp))} "
                    "(FORMAT parquet, COMPRESSION zstd)")
            tmp.rename(parquet)
            make_read_only(parquet)
        n_rows = con.execute(f"SELECT count(*) FROM read_parquet({string_lit(str(parquet))})").fetchone()[0]
        schema = describe(con, f"read_parquet({string_lit(str(parquet))})")
    except duckdb.Error as e:
        raise RecipeError(f"Lecture du fichier impossible : {e}") from e
    finally:
        con.close()

    report = {
        "format": fmt,
        "options": used,
        "columns": [{"name": c, "type": types[c]["type"], "note": types[c]["note"], "warning": types[c]["warning"]}
                    for c in names],
    }
    return {
        "raw_id": raw_id,
        "sha256": sha,
        "format": fmt,
        "size_bytes": source_copy.stat().st_size,
        "n_rows": n_rows,
        "parquet": str(parquet),
        "schema": schema,
        "report": report,
        "options": key_opts,
    }


def describe(con, relation_sql: str) -> dict[str, str]:
    rows = con.execute(f"DESCRIBE SELECT * FROM {relation_sql}").fetchall()
    return {r[0]: r[1] for r in rows}


def parquet_path(raw_dir: Path, sha: str, raw_id: str) -> Path:
    return raw_dir / sha / f"{raw_id}.parquet"


def source_path(raw_dir: Path, sha: str) -> Path | None:
    folder = raw_dir / sha
    for p in folder.glob("source.*"):
        return p
    return None


def verify_integrity(raw_dir: Path, sha: str) -> bool:
    p = source_path(raw_dir, sha)
    return bool(p and p.exists() and file_sha256(p) == sha)

