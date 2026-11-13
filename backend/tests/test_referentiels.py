"""Référentiels engins : cohérence interne et règles du contrôle engin / espèce."""

import duckdb

from moanui.engine.halieutique import gear_check_expr, referentiels


def test_codes_engins_sont_tous_fao():
    refs = referentiels()
    fao = {r["engin_cod"] for r in refs["engins_fao"]["lignes"]}
    assert {"OTB", "GTR", "FPO", "DRB", "LHP", "NK"} <= fao
    for code, esp in refs["engins_coherents"]["especes"].items():
        assert set(esp["principaux"]) <= set(esp["coherents"]) <= fao, code
    metiers = {r["engin_cod"] for r in refs["engins_metiers"]["lignes"]}
    assert fao <= metiers


def test_controle_generiques_et_inconnus():
    con = duckdb.connect()
    con.execute("CREATE TABLE t AS SELECT * FROM (VALUES ('SOL','GTR'),('SOL','LHP'),('SOL','TX'),"
                "('SOL','LX'),('SOL','NK'),('SCE','DRB'),('SCE','OTB'),('XYZ','PS'),('sol ','gtr')) v(esp, eng)")
    expr = gear_check_expr({"species_column": "esp", "gear_column": "eng"}, {"esp": "VARCHAR", "eng": "VARCHAR"})
    got = [r[0] for r in con.execute(f"SELECT {expr} FROM t").fetchall()]
    assert got == ["GTR", "LHP*", "TX", "LX*", "NK", "DRB", "OTB*", "PS", "GTR"]
