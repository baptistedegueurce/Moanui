# Données de démonstration Moanui

Une flottille **entièrement fictive** de 36 navires du sud Finistère / Morbihan (navires `MOANUI 01` à `MOANUI 36`,
identifiants `FRA999…`, patrons `… FICTIF-nn`, téléphones `06 00 00 00 nn`). Les ordres de grandeur (captures,
prix, saisons, vitesses) sont plausibles, mais rien ne décrit la réalité. Les codes de ports et les sous-divisions
CIEM sont indicatifs. Régénération : `cd backend && uv run python ../outils/generer_donnees_demo.py` (résultat
identique à chaque fois). Le test `backend/tests/test_donnees_demo.py` vérifie que chaque scénario ci-dessous marche.

## Les fichiers

| Fichier | Contenu | Particularités volontaires |
|---|---|---|
| `sacrois_2025.csv` | Captures par marée × espèce × rectangle (≈ 17 000 lignes), format SACROIS / journal de bord | `;`, virgule décimale, dates jj/mm/aaaa ; codes espèce en minuscules ou avec espaces, engins vides, montants manquants, 3 poids nuls, 4 lignes en double, ~15 engins incohérents avec l'espèce |
| `sacrois_2024.csv` | Même format, année 2024 | Encodé en **Windows-1252** (export Excel ancien) ; mêmes types d'erreurs |
| `sacrois_2023_extrait_tonnes.csv` | Extrait 2023 (12 navires) | Les poids de la colonne `debarquement_Kg` sont **en tonnes** (erreur d'unité) |
| `flotte_navires.xlsx` | Fichier flotte (Excel) : longueur, puissance, jauge, flottille, fournisseur VMS | Colonnes sensibles : nom du navire, patron, téléphone, licence (`licence_cod` à zéros initiaux) |
| `ref_especes.csv` | Référentiel espèces : nom commun, groupe, prix de référence | Un code `XXX` absent des captures |
| `ref_ports.csv` | Référentiel ports | Codes indicatifs |
| `corrections_engins.csv` | Corrections d'engins à importer dans le contrôle engin / espèce | Le bar en casier est laissé sans correction |
| `vms_agiltech_2025.csv` | Positions VMS Agiltech 2025, toutes les 15 min environ (≈ 114 000 positions) | `Latitude, Longitude, Vitesse` (nœuds), date `jj/mm/aaaa hh:mm`, `navire` |
| `vms_cls_2025.csv` | Positions VMS CLS 2025, toutes les heures environ (≈ 29 000 positions) | `LT, LG, SP` (dixièmes de nœud), `col_date`, `OP` |
| `suivi_casiers_homard.csv` | Campagne fictive de suivi au casier (2023-2025) : homards par station | Comptages très dispersés, effort = nombre de casiers |
| `zone_eolienne_fictive.geojson` | Zone d'étude éolienne fictive au sud des Glénan + raccordement | Recouvre un lieu de pêche des chalutiers |
| `gisements_coquille_fictifs.kml` | Deux gisements fictifs de coquille en baie de Douarnenez | KML |
| `cantonnements_fictifs_L93.zip` | Shapefile en **Lambert-93** (3 zones) | Reprojection automatique |
| `ports_fictifs.gpkg` | Ports en points (GeoPackage) | |

Dans ces données, seuls les navires de 12 m et plus ont un VMS (la moitié chez Agiltech, l'autre chez CLS) ; un
chalutier n'a aucune position (balise en panne) ; les caseyeurs, ligneurs et petits fileyeurs n'en ont pas.

## Scénarios à dérouler (résultat attendu)

### 1. Import et contrôle qualité
1. Importer `sacrois_2025.csv` (type « SACROIS ») puis `sacrois_2024.csv`.
   Attendu : `date_deb` reconnue comme date, poids et montants comme nombres, accents de 2024 lisibles.
2. Ouvrir le contrôle qualité. Attendu : vides signalés (engins, montants), doublons repérés.

### 2. Préparation SACROIS (onglet Pêche > modèle SACROIS)
1. Appliquer le modèle. Attendu : codes nettoyés (majuscules, espaces), découpage année / trimestre / mois, secteur
   `NS` (Nord pour 27.7, Sud pour 27.8), `metier`, `engin_sug`, `prix_moyen_kg`, `cpue_kg_jdm`, `debarquement_t`.
2. Dans le contrôle engin / espèce : la liste des incohérences contient sole au casier (`SOL` / `FPO`), langoustine
   à la ligne (`NEP` / `LHP`), coquille au chalut (`SCE` / `OTB`)… Importer `corrections_engins.csv`.
   Attendu : corrections appliquées, le bar en casier reste marqué `*`.
3. Lignes > Supprimer les doublons. Attendu : 4 lignes en moins.

### 3. Empilement, jointures, référentiels
1. Regrouper > Empiler : ajouter `sacrois_2024` et `sacrois_2023_extrait_tonnes` à 2025.
   Attendu : alerte « Unités différentes » sur `debarquement_Kg` (le fichier 2023 est en tonnes). Corriger 2023 avec
   Créer > Convertir une unité (t → kg) avant d'empiler.
2. Associer `flotte_navires` sur `navire_cod`. Attendu : longueur, puissance, flottille ajoutées à chaque ligne.
3. Associer `ref_especes` sur `esp_cod_fao` **avant** nettoyage : clés sans correspondance signalées (codes en
   minuscules / avec espaces) ; après nettoyage, plus d'écart.

### 4. Synthèses et secret statistique
1. Regrouper par espèce × port × mois avec somme des poids et secret statistique (navire, seuil 3).
   Attendu : groupes masqués, notamment pour la coquille (3 dragueurs d'un seul port) et les petits ports.

### 5. Graphiques
- Débarquements mensuels par métier (barres empilées), prix moyen par espèce (boîtes), CPUE 2024 / 2025 (courbes),
  valeur par port (anneau). Export PNG / SVG et fiche méthode.

### 6. Statistiques guidées (sur SACROIS préparé)
1. Comparer la CPUE entre métiers. Attendu : conditions vérifiées, test adapté proposé.
2. Lien entre métier et secteur `NS` (χ²).
3. Relation longueur du navire / débarquement (après jointure flotte).
4. Régression débarquement ~ longueur + puissance + métier.
5. GLM débarquement ~ métier + mois, effort `duree_maree`. Attendu : **bloqué** (poids nuls + décimales, conseil
   « delta ») ; après un filtre `debarquement_Kg > 0`, GLM Gamma accepté avec indice standardisé.
6. Sur `suivi_casiers_homard.csv` : GLM `nb_homards` ~ zone + année, effort `nb_casiers`. Attendu : binomiale négative
   (surdispersion) ; Poisson imposé = bloqué, contournable avec justification.

### 7. Export et données sensibles
1. Exporter `flotte_navires`. Attendu : alerte (nom du navire, patron, téléphone, licence) ; « Tout anonymiser ».

### 8. Cartographie
1. Importer les quatre couches (GeoJSON, KML, shapefile zip en Lambert-93, GeoPackage). Attendu : reprojection en
   WGS84, styles par attribut (`nom`, `densite_kg_m2`).
2. Afficher les couches de contexte (rectangles CIEM, 12 milles, AMP, Natura 2000).

### 9. VMS
1. Importer `vms_agiltech_2025.csv` et `vms_cls_2025.csv`, appliquer le modèle VMS à chacun.
   Attendu : colonnes harmonisées (`lat`, `lon`, `date_heure`, `navire`, `vitesse_nds`), vitesse CLS convertie,
   alerte « sauts de plus de 25 nœuds » (erreurs GPS volontaires), activité pêche / route / arrêt, rectangle CIEM.
   Pour les fileyeurs, adapter les seuils (pêche lente, 0,8 à 2,6 nœuds).
2. Empiler CLS sous Agiltech (colonne source « fournisseur »).
3. Repérer les positions dans la zone éolienne fictive (Créer > zone). Attendu : plusieurs centaines de positions
   de pêche dans la zone ; carte de densité par carroyage ou rectangle CIEM avec secret statistique.
4. Répartir les captures sur les positions (VMS × SACROIS) avec `sacrois_2025` : navire `navire` ↔ `navire_cod`,
   jour `date_heure` ↔ `date_deb`, rectangle `rectangle_ciem` ↔ `stat_rect`, espèce `esp_cod_fao`, poids et montants.
   Attendu : environ 80 % des captures attribuées, le reste expliqué (navires sans VMS, balise en panne).
   Ensuite : valeur pêchée dans la zone éolienne = filtre `zone_eol` non vide + somme des montants.
