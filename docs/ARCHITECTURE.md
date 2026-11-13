# Architecture de Moanui 0.2

```
navigateur (React + Mantine + AG Grid + Plotly)
        │  HTTP local, cookie de session HttpOnly
        ▼
serveur local FastAPI (127.0.0.1 uniquement)
   ├── comptes, structures, chartes, partage ──► SQLite (moanui.db)
   ├── import ──► raw/<sha256>/source.csv (copie brute, lecture seule)
   │             raw/<sha256>/<id>.parquet  (copie typée, lecture seule)
   └── recettes ──► SQL DuckDB exécuté à la volée sur le Parquet
```

## Principes

| Principe | Mise en œuvre |
|---|---|
| Ne jamais toucher au brut | Copie à l'import + `chmod` lecture seule + empreinte SHA-256 vérifiable |
| Toute modification est tracée | Recette = liste JSON d'étapes (type, paramètres, auteur, date, justification) |
| Réversible | Étapes désactivables, supprimables, réordonnables ; aperçu à n'importe quelle étape |
| Reproductible | Fiche méthode Markdown + requête SQL équivalente en annexe |
| Rien perdu en silence | Une colonne n'est typée que si 100 % des valeurs se convertissent ; sinon texte + alerte |
| Gros volumes | DuckDB (colonnes, parallèle) ; l'interface ne reçoit que des pages ou des agrégats |
| Sécurité | Écoute locale, contrôle d'hôte (anti DNS-rebinding), mots de passe scrypt, cookies HttpOnly/SameSite, formules en liste blanche (aucun SQL libre), SVG avec script refusés |

## Arborescence

```
backend/moanui/
  main.py            application FastAPI, lancement local
  config.py          dossier de travail (MOANUI_HOME)
  db.py              métadonnées SQLite + journal d'activité
  security.py        mots de passe, jetons
  themes.py, themes/ chartes graphiques (modèles + validation)
  methods.py         fiches méthode Markdown
  engine/
    store.py         import CSV/XLSX, détection des types, Parquet
    recipe.py        types d'étapes → SQL + description en français
    formula.py       formules façon tableur (analyseur, liste blanche)
    pipeline.py      exécution, pagination, profil, diagnostics, données de graphique
    sensitivity.py   colonnes sensibles (secret statistique)
  api/               routes : auth, admin, datasets, charts
frontend/src/
  pages/             accueil, données, jeu de données, graphiques, charte, administration
  components/        grille, recette, formulaires d'étapes, import…
  lib/               client API, charte → thème, construction des figures
```

## Ajouter un type d'étape

1. Dans `engine/recipe.py`, déclarer `@step("mon_type", "Libellé")` avec la fonction de compilation
   (`prev`, `params`, `schema` → SQL) puis la fonction de description en français.
2. Ajouter le formulaire dans `frontend/src/components/StepForm.tsx` et le ranger dans un groupe
   de `RecipePanel.tsx`.
3. Ajouter un test dans `backend/tests/`.

## Rôles

- **Administrateur général** : crée les structures et les comptes, voit le journal.
- **Admin de structure** : charte, logo, partage des jeux.
- **Analyste** : importe et traite les données.
- **Lecteur** : consulte, fait des graphiques, exporte.
