"""Gestion : suivis de quotas et contrôles de limitations, enregistrés par structure, avec fiches et exports."""

from __future__ import annotations

import io
import json
from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

from .. import gestion
from ..db import Database, new_id, now
from ..engine.sql import RecipeError
from .deps import User, Workspace, active_structure, current_user, dataset_access, get_db, get_settings, require_role, structure_name

router = APIRouter(prefix="/api/gestion", tags=["gestion"])

MOIS = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]


class SuiviIn(BaseModel):
    kind: str = Field(pattern="^(quota|limitations)$")
    name: str = Field(min_length=1, max_length=200)
    spec: dict


class CalcIn(BaseModel):
    dataset_id: str
    spec: dict
    name: str = ""


# --------------------------------------------------------------------------- suivis enregistrés
@router.get("/suivis")
def list_suivis(user: User = Depends(current_user), db: Database = Depends(get_db)):
    sid = active_structure(user)
    rows = db.all("SELECT s.*, u.display_name AS who FROM gestion_suivis s LEFT JOIN users u ON u.id = s.created_by "
                  "WHERE s.structure_id = ? ORDER BY s.kind, s.name", (sid,))
    return [{**r, "spec": json.loads(r["spec"])} for r in rows]


@router.post("/suivis")
def create_suivi(body: SuiviIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    sid = active_structure(user)
    require_role(user, sid, "analyste")
    i = new_id()
    db.execute("INSERT INTO gestion_suivis(id, structure_id, kind, name, spec, created_by, created_at, updated_at) "
               "VALUES (?,?,?,?,?,?,?,?)", (i, sid, body.kind, body.name, json.dumps(body.spec, ensure_ascii=False),
                                             user.id, now(), now()))
    db.log("gestion_suivi_cree", user_id=user.id, structure_id=sid, name=body.name, kind=body.kind)
    return {"id": i}


def _own(db: Database, user: User, i: str) -> dict:
    s = db.one("SELECT * FROM gestion_suivis WHERE id = ?", (i,))
    if not s or s["structure_id"] != active_structure(user):
        raise HTTPException(404, "Suivi introuvable.")
    return s


@router.put("/suivis/{i}")
def update_suivi(i: str, body: SuiviIn, user: User = Depends(current_user), db: Database = Depends(get_db)):
    s = _own(db, user, i)
    require_role(user, s["structure_id"], "analyste")
    db.execute("UPDATE gestion_suivis SET name = ?, spec = ?, updated_at = ? WHERE id = ?",
               (body.name, json.dumps(body.spec, ensure_ascii=False), now(), i))
    return {"ok": True}


@router.delete("/suivis/{i}")
def delete_suivi(i: str, user: User = Depends(current_user), db: Database = Depends(get_db)):
    s = _own(db, user, i)
    require_role(user, s["structure_id"], "analyste")
    db.execute("DELETE FROM gestion_suivis WHERE id = ?", (i,))
    return {"ok": True}


# --------------------------------------------------------------------------- calculs
def _calc(db, settings, user, body: CalcIn, fn):
    ds, _ = dataset_access(db, user, body.dataset_id)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        if plan.error:
            raise HTTPException(400, "La recette du jeu contient une erreur : corrigez-la d'abord.")
        try:
            return ds, fn(ws.con, plan.sql, plan.schema, body.spec)
        except RecipeError as e:
            raise HTTPException(400, str(e)) from e


@router.get("/colonnes/{did}")
def colonnes(did: str, user: User = Depends(current_user), db: Database = Depends(get_db), settings=Depends(get_settings)):
    """Colonnes du jeu et correspondance proposée (espèce, date, poids, navire…)."""
    ds, _ = dataset_access(db, user, did)
    with Workspace(db, settings, user) as ws:
        plan = ws.plan(ds)
        schema = {k: v for k, v in plan.schema.items() if not k.startswith("__")}
    return {"colonnes": list(schema), "proposition": gestion.guess_mapping(schema)}


@router.post("/quota")
def calc_quota(body: CalcIn, user: User = Depends(current_user), db: Database = Depends(get_db),
               settings=Depends(get_settings)):
    return _calc(db, settings, user, body, gestion.quota)[1]


@router.post("/depassements")
def calc_overshoots(body: CalcIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                    settings=Depends(get_settings)):
    return _calc(db, settings, user, body, gestion.overshoots)[1]


@router.get("/tableau-de-bord")
def dashboard(user: User = Depends(current_user), db: Database = Depends(get_db), settings=Depends(get_settings)):
    """Tous les quotas enregistrés de la structure, avec leur consommation actuelle."""
    out = []
    for s in list_suivis(user, db):
        if s["kind"] != "quota":
            continue
        row = {"id": s["id"], "name": s["name"], "spec": s["spec"]}
        try:
            res = _calc(db, settings, user, CalcIn(dataset_id=s["spec"].get("dataset_id", ""), spec=s["spec"]),
                        gestion.quota)[1]
            res.pop("jours", None)
            row["resultat"] = res
        except HTTPException as e:
            row["erreur"] = e.detail
        out.append(row)
    return out


# --------------------------------------------------------------------------- fiches et exports
def _fmt(v, d=0) -> str:
    from ..stats import fr

    return fr(v, d) if v is not None else "–"


def _quota_fiche(ds: dict, body: CalcIn, res: dict, user: User):
    from .. import figures
    from ..fiche import Fiche

    sp = body.spec
    q = res["quota_kg"]
    title = body.name or f"Quota {', '.join(res['especes'])} du {_d(res['debut'])} au {_d(res['fin'])}"
    f = Fiche(f"Suivi de consommation : {title}", f"Situation au {_d(res['derniere_donnee']) if res['derniere_donnee'] else '–'}")
    f.meta = [("Jeu de données", f"{ds['name']} (traitements décrits dans sa propre fiche méthode)"),
              ("Auteur", user.display_name), ("Date", __import__("datetime").datetime.now().strftime("%d/%m/%Y %H:%M"))]
    f.h("Résumé", numbered=False)
    proj = res.get("projection") or {}
    f.p(f"Au {_d(res['derniere_donnee'])}, **{_fmt(res['total_kg'] / 1000, 1)} t** ont été débarquées sur un quota de "
        f"{_fmt(q / 1000, 1)} t, soit **{_fmt(res['pct'], 1)} %** de consommation ({_fmt(res['reste_kg'] / 1000, 1)} t "
        f"restantes)." + (f" Le quota a été atteint le {_d(res['atteint_le'])}." if res.get("atteint_le") else "")
        + (f" Au rythme moyen observé depuis le début de la période, la consommation atteindrait "
           f"{_fmt(proj['fin_rythme_moyen'] / 1000, 1)} t en fin de période ({_fmt(100 * proj['fin_rythme_moyen'] / q, 0)} % "
           "du quota)." if proj else ""))
    f.h("Paramètres")
    m = sp.get("mapping") or {}
    f.kv([("Espèces couvertes", ", ".join(res["especes"])), ("Période", f"du {_d(res['debut'])} au {_d(res['fin'])}"),
          ("Quota", f"{_fmt(q)} kg"), ("Consommation annoncée", f"{_fmt(res['annonce_kg'])} kg" if res["annonce_kg"] else ""),
          ("Seuils d'alerte", ", ".join(f"{_fmt(s)} %" for s in res["seuils"])),
          ("Colonnes utilisées", f"espèce « {m.get('espece')} », date « {m.get('date')} », poids « {m.get('poids')} »"
                                 + (f", navire « {m['navire']} »" if m.get("navire") else ""))])
    f.h("Méthode")
    f.p("La consommation est la somme des quantités débarquées des espèces du quota, datées dans la période, issues du "
        "résultat de la recette du jeu de données (fichier brut inchangé). Les codes espèce sont comparés sans tenir compte "
        "des majuscules ni des espaces. Le poids est celui de la colonne choisie : vérifiez qu'il correspond à l'unité du "
        "quota (poids vif ou débarqué, à confirmer selon le stock). La projection est une **extrapolation linéaire** : "
        "rythme quotidien moyen depuis le début de la période, et rythme des 30 derniers jours, prolongés jusqu'à la fin. "
        "Elle ne tient pas compte de la saisonnalité ni des fermetures : c'est un ordre de grandeur, pas une prévision.")
    if res.get("lignes_sans_date"):
        f.note(f"{_fmt(res['lignes_sans_date'])} ligne(s) de ces espèces ({_fmt(res['kg_sans_date'])} kg) ont une date "
               "illisible et ne sont pas comptées.")
    f.h("Résultats")
    f.kv([("Débarqué", f"{_fmt(res['total_kg'])} kg"), ("Consommation", f"{_fmt(res['pct'], 1)} %"),
          ("Reste", f"{_fmt(res['reste_kg'])} kg"), ("Navires", _fmt(res["navires"])), ("Lignes", _fmt(res["lignes"])),
          ("Écart à l'annonce", f"{_fmt(res['ecart_annonce_pct'], 1)} %" if res["ecart_annonce_pct"] is not None else ""),
          ("Seuils franchis", ", ".join(f"{_fmt(s)} %" for s in res["alertes"]) or "aucun")])
    start = date.fromisoformat(res["debut"])
    end = date.fromisoformat(res["fin"])
    days = [(date.fromisoformat(x["jour"]) - start).days for x in res["jours"]]
    months, cur = [], date(start.year, start.month, 1)
    while cur <= end:
        if cur >= start:
            months.append(((cur - start).days, MOIS[cur.month - 1]))
        cur = date(cur.year + (cur.month == 12), cur.month % 12 + 1, 1)
    pj = ((end - start).days, proj["fin_rythme_moyen"]) if proj else None
    f.fig("cumul", figures.cumulative(days, [x["cumul"] for x in res["jours"]], (end - start).days or 1, q, months,
                                      res["annonce_kg"], pj),
          "Consommation cumulée (bleu), quota (rouge)" + (", consommation annoncée (tirets)" if res["annonce_kg"] else "")
          + (" et projection au rythme moyen (pointillés)" if pj else "") + ".")
    f.table(["Mois", "Débarqué (kg)", "Cumul (kg)", "% du quota", "% cumulé", "Navires"],
            [[x["mois"], _fmt(x["kg"]), _fmt(x["cumul"]), _fmt(x["pct"], 1), _fmt(x["pct_cumul"], 1), x["navires"]]
             for x in res["mois"]], "Consommation par mois.", "lrrrrr")
    if proj:
        f.table(["Hypothèse", "Rythme (kg/jour)", "Fin de période (kg)", "% du quota", "Quota atteint le"],
                [["Rythme moyen depuis le début", _fmt(proj["rythme_moyen_kg_j"], 1), _fmt(proj["fin_rythme_moyen"]),
                  _fmt(100 * proj["fin_rythme_moyen"] / q, 0), _d(proj.get("atteinte_rythme_moyen")) or "non atteint"],
                 ["Rythme des 30 derniers jours", _fmt(proj["rythme_30j_kg_j"], 1), _fmt(proj["fin_rythme_30j"]),
                  _fmt(100 * proj["fin_rythme_30j"] / q, 0), _d(proj.get("atteinte_rythme_30j")) or "non atteint"]],
                "Projections (extrapolations linéaires).", "lrrrl")
    f.h("Limites")
    f.ul(["Les données déclaratives arrivent avec retard : la consommation des dernières semaines est sous-estimée.",
          "Le périmètre du quota (zone, flottille, poids vif ou débarqué) doit correspondre aux données : à confirmer "
          "auprès du gestionnaire du quota.",
          "La projection linéaire ignore la saisonnalité, les fermetures et les échanges de quotas."])
    return f


def _overshoot_fiche(ds: dict, body: CalcIn, res: dict, user: User):
    from .. import figures
    from ..fiche import Fiche

    f = Fiche(f"Contrôle des limitations de captures{' : ' + body.name if body.name else ''}")
    f.meta = [("Jeu de données", f"{ds['name']} (traitements décrits dans sa propre fiche méthode)"),
              ("Auteur", user.display_name), ("Date", __import__("datetime").datetime.now().strftime("%d/%m/%Y %H:%M"))]
    t = res["total"]
    f.h("Résumé", numbered=False)
    f.p(f"**{_fmt(t['depassements'])} dépassement(s)** détecté(s), concernant **{_fmt(t['navires'])} navire(s)**, pour "
        f"**{_fmt(t['kg'])} kg** au-delà des limites ({len(res['regles'])} règle(s) contrôlée(s)).")
    f.h("Règles contrôlées")
    f.ul(res["regles"])
    f.h("Méthode")
    f.p("Pour chaque règle, les captures de l'espèce sont additionnées par navire et par unité de temps (marée, jour, "
        "semaine du lundi au dimanche, mois, trimestre ou semestre civils, année), sur la période de validité de la règle. "
        "Il y a dépassement quand la somme est strictement supérieure à la limite : la limite elle-même est autorisée ; "
        "une limite de 0 kg traduit une fermeture. Les périodes sont civiles (non glissantes). Sans colonne de marée, "
        "chaque ligne est considérée comme une marée.")
    f.h("Résultats")
    f.table(["Règle", "Dépassements", "Navires", "Quantité au-delà (kg)", "Unités contrôlées"],
            [[r["regle"], r["depassements"], r["navires"], _fmt(r["kg"]), r["unites_controlees"]] for r in res["par_regle"]],
            "Dépassements par règle.", "lrrrr")
    if res["par_mois"]:
        f.fig("mois", figures.bars([x["mois"] for x in res["par_mois"]], [x["kg"] for x in res["par_mois"]],
                                   "Quantité au-delà des limites (kg)", "Mois"),
              "Quantités pêchées au-delà des limites, par mois de fin de l'unité contrôlée.")
    f.table(["Règle", "Navire", "Nom", "Quartier", "Engin", "Dépassements", "Au-delà (kg)"],
            [[r["regle"], r["navire"], r["nom"] or "", r["quartier"] or "", r["engin"] or "", r["depassements"], _fmt(r["kg"])]
             for r in res["par_navire"][:300]], "Détail par navire (300 premiers).", "lllllrr")
    f.h("Confidentialité")
    f.p("Ce document cite des navires : il relève de la gestion interne de la structure et ne doit pas être diffusé "
        f"en l'état {f.cite('rgpd')}.")
    return f


def _d(iso: str | None) -> str:
    if not iso:
        return ""
    y, m, d = iso[:10].split("-")
    return f"{d}/{m}/{y}"


@router.post("/quota/method.{fmt}")
def quota_fiche(fmt: str, body: CalcIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                settings=Depends(get_settings)):
    ds, res = _calc(db, settings, user, body, gestion.quota)
    return _quota_fiche(ds, body, res, user).response(fmt, "suivi_quota", org=structure_name(db, user))


@router.post("/depassements/method.{fmt}")
def overshoot_fiche(fmt: str, body: CalcIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                    settings=Depends(get_settings)):
    ds, res = _calc(db, settings, user, body, gestion.overshoots)
    return _overshoot_fiche(ds, body, res, user).response(fmt, "controle_limitations", org=structure_name(db, user))


def _xlsx(sheets: list[tuple[str, list[str], list[list]]]) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Font

    wb = Workbook()
    wb.remove(wb.active)
    for title, head, rows in sheets:
        ws = wb.create_sheet(title[:31])
        ws.append(head)
        for c in ws[1]:
            c.font = Font(bold=True)
        for r in rows:
            ws.append(r)
        for col in ws.columns:
            ws.column_dimensions[col[0].column_letter].width = min(60, max(10, max(len(str(c.value or "")) for c in col) + 2))
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


@router.post("/quota/export.xlsx")
def quota_xlsx(body: CalcIn, user: User = Depends(current_user), db: Database = Depends(get_db),
               settings=Depends(get_settings)):
    _, res = _calc(db, settings, user, body, gestion.quota)
    data = _xlsx([("Par mois", ["mois", "kg", "cumul_kg", "pct_quota", "pct_cumule", "navires"],
                   [[x["mois"], x["kg"], x["cumul"], x["pct"], x["pct_cumul"], x["navires"]] for x in res["mois"]]),
                  ("Par jour", ["jour", "kg", "cumul_kg"], [[x["jour"], x["kg"], x["cumul"]] for x in res["jours"]])])
    return Response(data, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition": 'attachment; filename="suivi_quota.xlsx"'})


@router.post("/depassements/export.xlsx")
def overshoot_xlsx(body: CalcIn, user: User = Depends(current_user), db: Database = Depends(get_db),
                   settings=Depends(get_settings)):
    _, res = _calc(db, settings, user, body, gestion.overshoots)
    data = _xlsx([
        ("Par règle", ["regle", "depassements", "navires", "kg_au_dela", "unites_controlees"],
         [[r["regle"], r["depassements"], r["navires"], r["kg"], r["unites_controlees"]] for r in res["par_regle"]]),
        ("Par navire", ["regle", "navire", "nom", "quartier", "engin", "depassements", "kg_au_dela", "max_kg_unite"],
         [[r["regle"], r["navire"], r["nom"], r["quartier"], r["engin"], r["depassements"], r["kg"], r["max_kg"]]
          for r in res["par_navire"]]),
        ("Détail", ["regle", "navire", "nom", "unite", "debut", "fin", "kg", "limite", "depassement_kg", "lignes"],
         [[r["regle"], r["navire"], r["nom"], r["unite"], r["debut"], r["fin"], r["kg"], r["limite"], r["depassement_kg"],
           r["lignes"]] for r in res["detail"]]),
        ("Par mois", ["mois", "depassements", "kg_au_dela"], [[x["mois"], x["depassements"], x["kg"]] for x in res["par_mois"]]),
    ])
    return Response(data, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    headers={"Content-Disposition": 'attachment; filename="controle_limitations.xlsx"'})
