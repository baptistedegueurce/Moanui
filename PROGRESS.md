# Moanui — état du projet (à lire en premier)

> Fichier de reprise : tout ce qu'il faut pour continuer le projet depuis une nouvelle conversation
> sans relire l'historique. **À mettre à jour à chaque étape significative** (section « Journal »).

## 1. Le projet en une minute

Moanui (refonte complète de l'ancienne app R Shiny + Electron de la branche `script`, CRPM Bretagne)
est une **application web locale** de traitement de données halieutiques : « mieux qu'Excel pour
corriger la donnée, plus simple que R ». Cible : comités des pêches (CNPM, CRPM, CDPMEM), OP,
structures sans formation poussée en stats. Tout en **français**.

- Tourne **en local sur chaque PC** (serveur partagé plus tard si financé). **Windows d'abord**
  (exécutable sans droits admin), macOS plus tard.
- Branche de travail : `claude/compassionate-johnson-0kgjax` (dépôt `baptistedegueurce/moanui`).
  Ne pas créer de PR sans demande. Pas d'identifiant de modèle dans les commits.
- Exécutable Windows : construit par GitHub Actions (workflow « Exécutable Windows ») et **publié dans
  Releases à chaque push** sur `main` ou `claude/**` : pré-version `v<base>-dev.<n° de commit>` tant que
  `__version__` finit par `.dev0`, version stable `v<version>` (« Latest ») quand on retire le suffixe.
  Notes = section « Non publié » de `CHANGELOG.md` + commits (`outils/notes_de_version.py`).
  Deux fichiers : `Moanui-installation.exe` (Inno Setup `packaging/moanui.iss`, par utilisateur, programme dans
  `%LOCALAPPDATA%\Programs\Moanui`) et le zip portable. Le zip téléchargé doit être « débloqué » avant extraction,
  sinon Windows refuse `python312.dll` (Mark of the Web) : constaté sur le poste de l'utilisateur.
- Données de démonstration fictives : `exemples/donnees_demo/` (générées par `outils/generer_donnees_demo.py`,
  scénarios dans `LISEZMOI.md`, vérifiées par `backend/tests/test_donnees_demo.py`).

## 2. Choix validés avec l'utilisateur (ne pas remettre en cause)

| Sujet | Décision |
|---|---|
| Pile | Python FastAPI + DuckDB (données) + SQLite (métadonnées) ; React + Vite + TS + Mantine ; AG Grid ; Plotly (chargé à la demande) ; MapLibre pour la carto |
| Déploiement | Local, 127.0.0.1 uniquement, comptes locaux ; données dans `%LOCALAPPDATA%\Moanui` |
| Structures | Superadmin crée les structures ; utilisateurs multi-structures ; rôles admin / analyste / lecteur ; **cloisonnement strict**, partage explicite de jeux |
| Charte | Thème par structure (couleurs, logo, source par défaut) ; marque neutre par défaut |
| Brut | **Fichier brut jamais modifié** : copie en lecture seule + SHA-256 ; on travaille via une **recette** (étapes rejouables) |
| Méthode | Fiches méthode Markdown générées automatiquement (données, graphiques, stats) |
| Sensibles | Détection des colonnes nominatives ; alerte à l'export + bouton « tout anonymiser » ; travailler avec reste autorisé |
| Formats | CSV / XLSX en entrée et sortie ; SHP / GeoJSON / GPKG pour la carto |
| SACROIS | Prioritaire ; formats variables selon l'émetteur ; jusqu'à quelques centaines de milliers de lignes |
| VMS | Agiltech (Latitude, Longitude, Vitesse en nœuds, date jj/mm/aaaa hh:mm, navire) et CLS (LT, LG, SP 0–100 = dixièmes de nœud, col_date, OP) à harmoniser ; carroyage, suivi de zones, identification des zones de pêche |
| Stats | Contrôles des conditions, **blocage contournable avec justification écrite**, guides pas à pas, interprétation vulgarisée ; R facultatif plus tard |
| Carto | Internet supposé (fond IGN/OSM) avec fond hors ligne de secours ; couches de contexte : rectangles CIEM, ZEE, 3/12 milles, AMP, Natura 2000, ZFP, gisements |
| Palette | Palette catégorielle validée : `#2a78d6 #eb6834 #1baf7a #eda100 #e87ba4 #008300 #6250d6 #e34948` |

Fichiers de test fournis par l'utilisateur (simulés, **non commités** pour `PECHE_TEST_GRAPHIQUES.csv`
car noms de navires réalistes) ; les fixtures synthétiques sont dans `backend/tests/fixtures/`.

## 3. Architecture (où est quoi)

```
backend/moanui/
  main.py            app FastAPI, en-têtes de sécurité, TrustedHost, service du front, run()
  config.py db.py    réglages / schéma SQLite (users, structures, memberships, raw_files, datasets,
                     dataset_shares, journal, analyses, charts, + carto)
  security.py        scrypt, jetons de session
  themes.py themes/  chartes prédéfinies
  methods.py         fiche méthode des jeux (contenu)
  fiche.py           modèle commun des fiches : Markdown + HTML imprimable + ZIP (figures SVG)
  figures.py         figures SVG sans dépendance (boîtes, nuage, QQ, barres avec IC, barres empilées…)
  biblio.py          références bibliographiques (source unique : fiches + guide via /api/meta « biblio »)
  stats.py           statistiques guidées (scipy/numpy) + fiche méthode statistique (method_fiche)
  glm.py             GLM (IRLS)
  engine/
    store.py         import CSV/XLSX → copie brute RO + Parquet typé (__ligne = n° de ligne d'origine)
    sql.py           identifiants, littéraux, RecipeError
    formula.py       langage de formules FR (SI, ARRONDI, ANNEE…) compilé en SQL sûr
    recipe.py        registre @step(type) → chaîne de CTE ; toutes les étapes génériques
    halieutique.py   étapes métier (lookup, unit_convert, gear_check) + modèle SACROIS
    pipeline.py      build / page / profil / valeurs / chart_data / diagnostics
    sensitivity.py   motifs de colonnes sensibles
    geo.py           (carto) extension spatiale, import couches, tuiles MVT, carroyage, CIEM
  referentiels/*.json engins_fao, engins_coherents, engins_metiers (régénérés par outils/)
  api/               auth, admin, datasets, charts, analyses, (geo)
frontend/src/
  pages/             Home, Datasets, Dataset (grille + panneau de traitement), Charts, Stats, Carto, Structure, Admin, Guide
  components/        DataGrid (AG Grid infini, en-têtes typés), TreatmentPanel (onglets Colonnes / Lignes / Créer /
                     Regrouper / Pêche / Historique), RecipePanel (historique), StepForm, StepModal, ImportModal…
  lib/               api, types, chart (buildFigure Plotly), theme, format, auth
packaging/           PyInstaller (moanui.spec, lanceur.py, icône, LISEZMOI)
.github/workflows/   tests.yml (pytest + build front), windows.yml (exe + test de démarrage)
outils/              generer_referentiels_engins.py
docs/                ARCHITECTURE.md, FEUILLE_DE_ROUTE.md
```

Principes clés :
- **Recette** = liste JSON d'étapes `{id,type,params,comment,enabled,author,at}` compilée en SQL
  (CTE s0..sN). Aperçu à n'importe quelle étape, nombre de lignes par étape, désactivation/réordonnancement.
  Pour ajouter une étape : `@step("type","Libellé")` + description (`@_fn` décorateur) + formulaire
  dans `StepForm.tsx` + `DEFAULT_PARAMS`.
- Jointures / empilements entre jeux via un résolveur (détection de cycles).
- Inférence de type : conversion vérifiée à 100 %, sinon texte + avertissement ; codes à zéros
  initiaux et `25E4` gardés en texte.
- DuckDB 2.0 : utiliser `con.execute(...).fetchone()` (plus de `.fetchone()` sur les relations).

## 4. Lancer / tester

```bash
cd backend && uv sync --extra dev && uv run pytest -q      # tests (31)
cd frontend && npm ci && npm run build                      # compile vers backend/moanui/static
cd backend && uv run moanui --home ../.moanui-dev           # http://127.0.0.1:8765
cd frontend && npm run dev                                  # dev avec proxy /api → 8765
```

## 5. Ce qui est fait

- **Socle** : comptes, structures, rôles, partage, journal, chartes + logos, import non destructif,
  recettes (≈25 étapes), corrections cellule par cellule justifiées, contrôle qualité, exports
  CSV/XLSX/Parquet + fiche méthode, alerte données sensibles.
- **Graphiques** : tous types usuels, 2 axes, 3D, petits multiples, gabarit (titre, source,
  auteur, logo), export PNG/SVG, fiche méthode.
- **SACROIS** : modèle de préparation (codes, périodes, Nord/Sud, métiers, `engin_sug`, prix moyen,
  CPUE, tonnes), cohérence engin/espèce avec corrections CSV, secret statistique (< 3 navires).
- **Référentiel engins (nov. 2026)** : ISSCFG 2016 complet (69 codes, + DCF/historiques),
  engins cohérents pour 20 espèces principales Manche / golfe de Gascogne + 6 complémentaires,
  à partir de la littérature (FAO, CIEM, Ifremer SIH, DCF). Le top 20 « comités / hors OP »
  n'est pas public → repli sur les principales espèces de la façade, orienté petite pêche.
  Codes génériques (TX, GEN, LX…) acceptés si un engin précis du groupe est cohérent ; MIS/NK
  jamais signalés. Les tolérances de l'ancienne app (MAC en FPO/DRB/LLS, SOL en FPO) ont été
  retirées faute d'appui bibliographique : à rajouter par structure si besoin.
- **Exécutable Windows** testé automatiquement (démarrage + `/api/health`).
- **Cartographie + VMS (nov. 2026)** : voir §7.
- **Statistiques guidées** : comparaison de groupes (t de Welch, Mann-Whitney, ANOVA, Welch,
  Kruskal + post-hoc Holm), khi² / Fisher, corrélation, régression linéaire (VIF, Breusch-Pagan,
  Cook) ; blocage contournable, interprétation, historique, fiche méthode.
- **GLM (nov. 2026)** : `backend/moanui/glm.py` (IRLS NumPy/SciPy, **pas de statsmodels** pour ne pas
  alourdir l'exe ; validé contre statsmodels à 1e-6) : Poisson, quasi-Poisson, binomiale négative
  (θ par MV en alternance, comme `MASS::glm.nb`), Gamma (log), logistique. Analyse `glm` dans
  `stats.py` (`glm_analysis`) : famille auto (0/1 → logistique ; entiers → Poisson puis NB si
  dispersion > 1,5 ; entiers élevés sans zéro ou décimaux > 0 → Gamma ; zéros + décimaux → bloqué
  avec conseil « delta »), effort en offset log, tests par facteur (LRT χ² ou F si dispersion estimée),
  rapports multiplicatifs, **indice standardisé** (prédictions par modalité du 1er facteur catégoriel),
  contrôles (surdispersion, zéros attendus/observés, séparation, VIF, résidus quantiles Dunn-Smyth).
  Référence = modalité la plus fréquente. AIC à la R (dispersion comptée pour Gamma/NB).
- **VMS × SACROIS (nov. 2026)** : étape `vms_catch_split` (geo_steps.py) — captures sommées par
  navire × jour (× rectangle) (× espèce), réparties sur les positions de pêche du même navire/jour/
  rectangle, repli au niveau jour, à parts égales ou au prorata de `ecart_min` (intervalle médian du
  navire après une coupure). Identifiants comparés en `upper(trim())`, dates texte jj/mm/aaaa lues.
  Bilan avant validation (`pipeline.catch_split_report`) : part attribuée par niveau, captures sans
  position. Formulaire `CatchSplitForm` avec propositions de colonnes SACROIS.

- **Ergonomie du traitement (nov. 2026)** : juste milieu avec l'ancienne appli R. Panneau à droite du tableau,
  onglets **Colonnes** (liste cochable avec type abc/123/date, renommer, type, transformer, recoder, remplir les
  vides, fusionner, garder / supprimer), **Lignes** (filtre direct garder/supprimer, doublons, vides, tri),
  **Créer** (formule, si/alors, fusion, dates, unités, référentiel, CIEM), **Regrouper** (agrégat, jointure,
  empilement), **Pêche** (modèles SACROIS/VMS, engins, VMS, anonymiser), **Historique** (recette + « Annuler la
  dernière opération »). Les opérations simples s'appliquent directement (notification avec « Annuler »), les
  autres ouvrent le formulaire avec aperçu. Clic sur le nom d'une colonne dans l'en-tête = sélection, flèche = tri.
  Nouvelles étapes `transform` (majuscules, minuscules, espaces, arrondir, abs, ln, log1p, log10, racine, classes
  égales / quantiles ; en place ou avec suffixe) et `coalesce` (fusion de colonnes).
- **Fiches méthode (nov. 2026)** : toutes construites avec `fiche.Fiche` (sections numérotées, tableaux et figures
  numérotés, citations auteur-date, liste de références). Jeu : sources, traitements (tableau + figure lignes par
  étape), méthodes employées selon les étapes (avec références), données obtenues (profil + figure des manques),
  confidentialité, SQL lisible. Stats : question, méthode (texte par test + références), conditions (tableau),
  résultats, figures (boîtes, barres empilées, nuage + droite, résidus + QQ, indice standardisé avec IC),
  interprétation détaillée, limites. Graphique : SVG du graphique joint (Plotly toImage), encodage, calcul,
  justification du choix (Cleveland & McGill…). Carte : PNG composé joint, couches et sources/licences, projection,
  méthodes (classes, VMS, secret). Routes `…/method.md|html|zip` ; l'export de données joint MD + HTML + figures.
  Aucun émoji dans les sorties (testé).
- **Visuel (nov. 2026)** : police IBM Plex Sans/Mono embarquée (@fontsource, hors ligne ; les chartes « Inter »
  basculent dessus), en-tête blanc, barre latérale sobre (repère d'onglet actif), rayons 4 px, boutons « default »,
  accueil utile (derniers jeux, graphiques, analyses, cartes via `/api/recent`), guide en document avec sommaire
  et références, page Statistiques sans cartes « marketing », nombres du tableau au format français sans perte de
  précision, notifications en bas à droite. Tirets cadratins et émojis retirés des textes.

- **Gestion (nov. 2026)** : `moanui/gestion.py` (consommation de quota, projection linéaire, dépassements par
  règle et unité de temps), `api/gestion.py` (suivis enregistrés `gestion_suivis` par structure, tableau de bord,
  fiches, exports Excel), `pages/GestionPage.tsx`. Inspiré des sections 6.3-6.4 du guide de l'ancienne appli R.
- **Exports PDF / Word (nov. 2026)** : `moanui/documents.py` (fpdf2, python-docx, resvg ; polices `moanui/polices`),
  `Fiche.response(fmt)` ; routes `method.{pdf,docx}` partout ; vérifié dans l'exe par la CI.
- **Fiches statistiques (nov. 2026)** : écriture normalisée, IC des tailles d'effet (bootstrap graine 2026),
  résumé et discussion conditionnés (`stats.finalize`), reproductibilité.
- **Cache des graphiques** : `lib/memo.ts` (mémoire par utilisateur et structure, jamais sur disque).

- **Guide utilisateur (nov. 2026)** : `docs/guide/guide.md` (source, conventions en tête de
  `outils/construire_guide.py`), captures `docs/guide/images` produites par `outils/captures_guide.js` (Playwright,
  données de démo, échelle 2), Word + PDF construits par `outils/construire_guide.py` (page de garde, avant-propos,
  sommaire, parties, index des figures) et joints aux releases. Forme reprise du guide de l'appli R v0.1 (fourni par
  l'utilisateur, non versionné).

## 6. En cours / à faire (ordre proposé)

1. Carto suite : bande des 3 milles (licence OFB/CNSP à vérifier), étiquettes (polices embarquées),
   trajectoires par marée ; VMS × SACROIS par marée (et non seulement par jour) si les données le permettent.
2. SACROIS suite : référentiels espèces / ports, corrections d'engins propres à chaque structure
   (base partagée), recettes enregistrables comme modèles, scripts CDP22 / DGAMPA.
3. Stats suite : GLMM (effet navire), GAM, modèle delta assisté, séries temporelles, ACP ; R si installé.
4. Composition de planches, rapports PDF / PPTX.
5. macOS, signature Windows, mises à jour ; mode serveur ; export des recettes en R / Python.

Questions ouvertes à l'utilisateur : traitements SACROIS récurrents (scripts CDP22),
vraies listes de corrections d'engins, retours de test de l'exécutable sur un poste.

## 7. Cartographie (détails)

- Moteur : extension **spatiale DuckDB** (GDAL/PROJ/GEOS). En dev elle est téléchargée une fois
  (`INSTALL spatial`) ; dans l'exe elle est **embarquée** (`packaging/extension_spatiale.py` la copie,
  `moanui.spec` l'ajoute, le test de démarrage CI vérifie `/api/health` → `cartographie: embarquee`).
  Toujours `SET geometry_always_xy = true` (fait par `geo.load_spatial`).
- Couche importée : `home/couches/<id>/source/*` (brut RO) + `couche.parquet` (colonnes attributaires,
  `geom` WGS84, `geom_m` Web Mercator, `__minx…__maxy`, `__fid`, tri Hilbert). Tuiles :
  `ST_AsMVT` à la demande, cache LRU mémoire, propriétés castées (MVT n'accepte pas DECIMAL).
- Couches intégrées : `backend/moanui/couches/*.parquet` + `couches.json`, régénérées par
  `outils/generer_couches_contexte.py` (Shom DELMAR, OFB AMP via WFS, Natural Earth). ~10 Mo.
  Ids côté API : `ctx:<id>`. Les terres sont découpées en carreaux de 1° (sinon tuiles lentes).
- Jeux sur la carte : positions = Parquet en cache (`home/cache/pts_<hash>.parquet`, clé = SQL de la
  recette) servies en tuiles ; carroyage / rectangles CIEM = GeoJSON calculé (≤ 150 000 mailles).
- Étapes : `ciem_rect`, `vms_activity` (seuils par engin, `SPEED_PRESETS`), `zone_tag` (jointure
  spatiale, nécessite `LAYER_RESOLVER` posé par `Workspace`). Modèle `vms` dans `halieutique.TEMPLATES`.
- Front : `pages/CartoPage.tsx` (MapLibre 4.7.1 chargé à la demande), `lib/carto.ts` (styles,
  légende, échelle en milles, export PNG composé), `components/LayerImportModal.tsx`.
  Fonds : Plan IGN (Géoplateforme, sans clé), OSM, hors ligne (terres intégrées), aucun.
  Pas d'étiquettes texte (il faudrait des polices de glyphes hors ligne) : infos au clic.

## 8. Journal

- 0.2 socle → SACROIS → exe Windows → stats (cf. historique git).
- 2026-11 : référentiel engins FAO + engins cohérents (26 espèces) ; PROGRESS.md.
- 2026-11 : cartographie + VMS (moteur, API, interface, étapes, couches de contexte, exe).
- 2026-11 : croisement VMS × SACROIS (répartition des captures) ; GLM guidés.
- 2026-11 : panneau de traitement par colonnes / lignes (inspiré de l'appli R), fiches méthode avec figures et
  bibliographie, guide référencé, refonte visuelle (IBM Plex, accueil, navigation).
