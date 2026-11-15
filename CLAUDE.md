# Moanui — consignes de reprise pour Claude

1. **Lire `PROGRESS.md` en premier** (état, décisions validées, journal). Arborescence détaillée : `docs/ARCHITECTURE.md`.
2. **Carte du code = Graphify** (dépôt `baptistedegueurce/Moanui`, branche indexée : `main`). L'utiliser avant de relire des fichiers :
   - où est défini X → `graphify_find` ; comment marche Y → `query_graph` (`skeleton=true` pour économiser) ;
   - quels fichiers concernent une question → `graphify_rank_files` ; appelants / impact / tests → `graphify_callers`, `graphify_impact`, `graphify_tests_for`, `graphify_file_neighbors`.
3. **Fraîcheur** : comparer le `commitSha` de `graph_stats` à `git rev-parse HEAD`. S'ils diffèrent, lire directement les fichiers de `git diff --name-only <commitSha>..HEAD` ; le reste du graphe est fiable.
4. Grep seulement pour les chaînes littérales, la config et les fichiers non indexés (Graphify gratuit n'indexe que `README.md` parmi les documents : `PROGRESS.md` et `docs/` n'y sont pas).
5. Développer sur `claude/compassionate-johnson-0kgjax`. `main` est avancé (avance rapide) jusqu'à la branche de travail à la demande de l'utilisateur, pour que Graphify réindexe. Pas de PR sans demande, pas d'identifiant de modèle dans les commits.
6. **À chaque push** : compléter la section « Non publié » de `CHANGELOG.md` (texte pour les utilisateurs, en français) ;
   chaque push publie un exe en pré-version. Version stable : retirer `.dev0` de `backend/moanui/__init__.py`
   (et renommer la section en `[x.y.z] — date`) uniquement sur accord de l'utilisateur, puis passer à `x.y+1.0.dev0`.
