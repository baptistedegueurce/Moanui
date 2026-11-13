"""Formules façon tableur, traduites en SQL de façon sûre.

Syntaxe :
  - colonnes entre crochets : [Poids vif] ; un nom simple sans espace marche aussi
  - nombres (1.5 ou 1,5 entre parenthèses de fonction : utiliser le point), textes "..." ou '...'
  - opérateurs : + - * / ^ %   & (concaténation)   = <> < > <= >=   ET OU NON
  - fonctions en français ou en anglais : SI(cond; a; b), ARRONDI(x; 2), ...
    (le séparateur d'arguments peut être ; ou ,)

Seules les fonctions de la liste blanche sont acceptées : impossible d'injecter
du SQL arbitraire.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .sql import RecipeError, ident, string_lit


@dataclass
class Tok:
    kind: str  # num, str, col, name, op, lp, rp, sep, end
    value: str
    pos: int


_TOKEN_RE = re.compile(
    r"""
    (?P<ws>\s+)
  | (?P<num>\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
  | (?P<str>"(?:[^"]|"")*"|'(?:[^']|'')*')
  | (?P<col>\[[^\]]+\])
  | (?P<op><>|<=|>=|!=|==|[-+*/^%&=<>])
  | (?P<lp>\()
  | (?P<rp>\))
  | (?P<sep>[;,])
  | (?P<name>[A-Za-zÀ-ÖØ-öø-ÿ_][A-Za-zÀ-ÖØ-öø-ÿ0-9_.]*)
    """,
    re.VERBOSE,
)


def tokenize(src: str) -> list[Tok]:
    out: list[Tok] = []
    i = 0
    while i < len(src):
        m = _TOKEN_RE.match(src, i)
        if not m:
            raise RecipeError(f"Caractère inattendu « {src[i]} » à la position {i + 1} de la formule.")
        kind = m.lastgroup
        if kind != "ws":
            out.append(Tok(kind, m.group(), i))
        i = m.end()
    out.append(Tok("end", "", len(src)))
    return out


# nom (en majuscules) -> (nb_args_min, nb_args_max, générateur SQL)
def _fn(sql_name):
    return lambda args: f"{sql_name}({', '.join(args)})"


FUNCTIONS: dict[str, tuple[int, int, object, str]] = {}


def _reg(names, nmin, nmax, gen, doc):
    for n in names:
        FUNCTIONS[n] = (nmin, nmax, gen, doc)


_reg(["ARRONDI", "ROUND"], 1, 2, lambda a: f"round({a[0]}, {a[1] if len(a) > 1 else 0})", "ARRONDI(x; décimales)")
_reg(["ABS"], 1, 1, _fn("abs"), "ABS(x) : valeur absolue")
_reg(["RACINE", "SQRT"], 1, 1, _fn("sqrt"), "RACINE(x)")
_reg(["LN"], 1, 1, _fn("ln"), "LN(x) : logarithme népérien")
_reg(["LOG10"], 1, 1, _fn("log10"), "LOG10(x)")
_reg(["LOG1P"], 1, 1, lambda a: f"ln(1 + {a[0]})", "LOG1P(x) : ln(1 + x)")
_reg(["EXP"], 1, 1, _fn("exp"), "EXP(x)")
_reg(["PUISSANCE", "POWER"], 2, 2, _fn("pow"), "PUISSANCE(x; n)")
_reg(["MIN", "LEAST"], 2, 10, _fn("least"), "MIN(a; b; ...) : plus petite valeur de la ligne")
_reg(["MAX", "GREATEST"], 2, 10, _fn("greatest"), "MAX(a; b; ...) : plus grande valeur de la ligne")
_reg(["SI", "IF"], 2, 3, lambda a: f"(CASE WHEN {a[0]} THEN {a[1]} ELSE {a[2] if len(a) > 2 else 'NULL'} END)",
     "SI(condition; si_vrai; si_faux)")
_reg(["SIVIDE", "COALESCE"], 2, 10, _fn("coalesce"), "SIVIDE(x; remplacement) : remplace les vides")
_reg(["ESTVIDE", "ISNULL"], 1, 1, lambda a: f"({a[0]} IS NULL)", "ESTVIDE(x)")
_reg(["MAJUSCULE", "UPPER"], 1, 1, _fn("upper"), "MAJUSCULE(texte)")
_reg(["MINUSCULE", "LOWER"], 1, 1, _fn("lower"), "MINUSCULE(texte)")
_reg(["SUPPRESPACE", "TRIM"], 1, 1, _fn("trim"), "SUPPRESPACE(texte) : enlève les espaces autour")
_reg(["LONGUEUR", "LENGTH"], 1, 1, lambda a: f"length(CAST({a[0]} AS VARCHAR))", "LONGUEUR(texte)")
_reg(["GAUCHE", "LEFT"], 2, 2, lambda a: f"left(CAST({a[0]} AS VARCHAR), {a[1]})", "GAUCHE(texte; n)")
_reg(["DROITE", "RIGHT"], 2, 2, lambda a: f"right(CAST({a[0]} AS VARCHAR), {a[1]})", "DROITE(texte; n)")
_reg(["STXT", "MID", "SUBSTR"], 3, 3, lambda a: f"substr(CAST({a[0]} AS VARCHAR), {a[1]}, {a[2]})",
     "STXT(texte; début; longueur)")
_reg(["CONCAT", "CONCATENER"], 2, 10, lambda a: "concat(" + ", ".join(a) + ")", "CONCAT(a; b; ...)")
_reg(["CONTIENT", "CONTAINS"], 2, 2,
     lambda a: f"contains(lower(CAST({a[0]} AS VARCHAR)), lower(CAST({a[1]} AS VARCHAR)))",
     "CONTIENT(texte; motif) : vrai si le texte contient le motif (sans tenir compte de la casse)")
_reg(["REMPLACER", "REPLACE"], 3, 3, lambda a: f"replace(CAST({a[0]} AS VARCHAR), {a[1]}, {a[2]})",
     "REMPLACER(texte; ancien; nouveau)")
_reg(["TEXTE", "TEXT"], 1, 1, lambda a: f"CAST({a[0]} AS VARCHAR)", "TEXTE(x) : convertit en texte")
_reg(["NOMBRE", "NUMBER"], 1, 1, lambda a: f"TRY_CAST(replace(CAST({a[0]} AS VARCHAR), ',', '.') AS DOUBLE)",
     "NOMBRE(x) : convertit en nombre (vide si impossible)")
_reg(["ANNEE", "YEAR"], 1, 1, _fn("year"), "ANNEE(date)")
_reg(["MOIS", "MONTH"], 1, 1, _fn("month"), "MOIS(date)")
_reg(["JOUR", "DAY"], 1, 1, _fn("day"), "JOUR(date)")
_reg(["TRIMESTRE", "QUARTER"], 1, 1, _fn("quarter"), "TRIMESTRE(date)")
_reg(["SEMESTRE", "SEMESTER"], 1, 1, lambda a: f"(CASE WHEN month({a[0]}) <= 6 THEN 1 ELSE 2 END)", "SEMESTRE(date)")
_reg(["SEMAINE", "WEEK"], 1, 1, _fn("week"), "SEMAINE(date) : semaine ISO")
_reg(["JOURSEM", "WEEKDAY"], 1, 1, _fn("isodow"), "JOURSEM(date) : 1 = lundi … 7 = dimanche")
_reg(["DATE"], 3, 3, _fn("make_date"), "DATE(année; mois; jour)")
_reg(["ECARTJOURS", "DATEDIFF"], 2, 2, lambda a: f"date_diff('day', {a[0]}, {a[1]})",
     "ECARTJOURS(début; fin) : nombre de jours entre deux dates")


class _Parser:
    def __init__(self, tokens: list[Tok], columns: list[str]):
        self.t = tokens
        self.i = 0
        self.columns = columns
        self.lower_cols = {c.lower(): c for c in columns}
        self.used: set[str] = set()

    def peek(self) -> Tok:
        return self.t[self.i]

    def next(self) -> Tok:
        tok = self.t[self.i]
        self.i += 1
        return tok

    def is_kw(self, *words) -> bool:
        tok = self.peek()
        return tok.kind == "name" and tok.value.upper() in words

    def expect(self, kind: str, what: str) -> Tok:
        tok = self.next()
        if tok.kind != kind:
            got = tok.value or "fin de formule"
            raise RecipeError(f"{what} attendu(e) à la position {tok.pos + 1}, trouvé « {got} ».")
        return tok

    def parse(self) -> str:
        e = self.or_()
        if self.peek().kind != "end":
            tok = self.peek()
            raise RecipeError(f"Élément inattendu « {tok.value} » à la position {tok.pos + 1}.")
        return e

    def or_(self):
        left = self.and_()
        while self.is_kw("OU", "OR"):
            self.next()
            left = f"({left} OR {self.and_()})"
        return left

    def and_(self):
        left = self.not_()
        while self.is_kw("ET", "AND"):
            self.next()
            left = f"({left} AND {self.not_()})"
        return left

    def not_(self):
        if self.is_kw("NON", "NOT"):
            self.next()
            return f"(NOT {self.not_()})"
        return self.cmp()

    def cmp(self):
        left = self.add()
        tok = self.peek()
        if tok.kind == "op" and tok.value in ("=", "==", "<>", "!=", "<", ">", "<=", ">="):
            self.next()
            op = {"==": "=", "!=": "<>"}.get(tok.value, tok.value)
            return f"({left} {op} {self.add()})"
        return left

    def add(self):
        left = self.mul()
        while self.peek().kind == "op" and self.peek().value in ("+", "-", "&"):
            op = self.next().value
            right = self.mul()
            left = f"concat({left}, {right})" if op == "&" else f"({left} {op} {right})"
        return left

    def mul(self):
        left = self.unary()
        while self.peek().kind == "op" and self.peek().value in ("*", "/", "%"):
            op = self.next().value
            left = f"({left} {op} {self.unary()})"
        return left

    def unary(self):
        tok = self.peek()
        if tok.kind == "op" and tok.value in ("-", "+"):
            self.next()
            inner = self.unary()
            return f"(-{inner})" if tok.value == "-" else inner
        return self.power()

    def power(self):
        base = self.atom()
        if self.peek().kind == "op" and self.peek().value == "^":
            self.next()
            return f"pow({base}, {self.unary()})"
        return base

    def column(self, name: str, pos: int) -> str:
        real = name if name in self.columns else self.lower_cols.get(name.lower())
        if real is None:
            raise RecipeError(f"Colonne inconnue « {name} » (position {pos + 1}).")
        self.used.add(real)
        return ident(real)

    def atom(self):
        tok = self.next()
        if tok.kind == "num":
            return tok.value
        if tok.kind == "str":
            q = tok.value[0]
            return string_lit(tok.value[1:-1].replace(q + q, q))
        if tok.kind == "col":
            return self.column(tok.value[1:-1].strip(), tok.pos)
        if tok.kind == "lp":
            e = self.or_()
            self.expect("rp", "Parenthèse fermante")
            return f"({e})"
        if tok.kind == "name":
            up = tok.value.upper()
            if self.peek().kind == "lp":
                if up not in FUNCTIONS:
                    raise RecipeError(f"Fonction inconnue « {tok.value} ». Consultez l'aide des formules.")
                self.next()
                args = []
                if self.peek().kind != "rp":
                    args.append(self.or_())
                    while self.peek().kind == "sep":
                        self.next()
                        args.append(self.or_())
                self.expect("rp", "Parenthèse fermante")
                nmin, nmax, gen, doc = FUNCTIONS[up]
                if not nmin <= len(args) <= nmax:
                    raise RecipeError(f"Mauvais nombre d'arguments pour {up} : {doc}.")
                return gen(args)
            if up in ("VRAI", "TRUE"):
                return "TRUE"
            if up in ("FAUX", "FALSE"):
                return "FALSE"
            if up in ("VIDE", "NULL"):
                return "NULL"
            return self.column(tok.value, tok.pos)
        raise RecipeError(f"Élément inattendu « {tok.value or 'fin de formule'} » à la position {tok.pos + 1}.")


def compile_formula(expression: str, columns: list[str]) -> tuple[str, set[str]]:
    """Traduit une formule en expression SQL. Renvoie (sql, colonnes_utilisées)."""
    if not expression or not expression.strip():
        raise RecipeError("La formule est vide.")
    if len(expression) > 2000:
        raise RecipeError("Formule trop longue (2000 caractères maximum).")
    p = _Parser(tokenize(expression.lstrip("=")), columns)
    return p.parse(), p.used


def function_help() -> list[dict]:
    seen, out = set(), []
    for name, (_, _, _, doc) in FUNCTIONS.items():
        if doc in seen:
            continue
        seen.add(doc)
        out.append({"name": name, "doc": doc})
    return out
