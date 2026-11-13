# Feuille de route

## Fait (0.2 — socle)

- Comptes locaux, structures cloisonnées, rôles, partage explicite, journal d'activité
- Chartes graphiques par structure (couleurs, palette validée daltonisme, logo, source par défaut)
- Import CSV/XLSX non destructif, détection des types à la française, rapport d'import
- Recettes : filtres, tri, doublons, colonnes, types, remplacements, nettoyage de texte, vides,
  formules, codage conditionnel, dates, regroupements, jointures, empilements, anonymisation,
  corrections cellule par cellule justifiées
- Contrôle qualité automatique et diagnostics de jointure / empilement
- Graphiques : barres, courbes, aires, combinés (2 axes), anneau, chaleur, nuages, bulles,
  boîtes, violons, histogrammes, 3D ; petits multiples ; échelles ; gabarit titre / source /
  auteur / date / logo ; export PNG HD et SVG ; tableau des valeurs ; fiche méthode
- Exports CSV (Excel FR) / XLSX / Parquet + fiche méthode, alerte données sensibles
- SACROIS : modèle de préparation (codes, périodes, Nord/Sud, métiers, engin_sug, prix moyen, CPUE,
  tonnages), référentiels intégrés, cohérence engin/espèce avec corrections importables en CSV,
  secret statistique dans les regroupements, conversions d'unités
- Exécutable Windows autonome construit et testé par GitHub Actions
- Statistiques guidées : comparaison de groupes, lien entre catégories, corrélation, régression
  linéaire ; conditions vérifiées, blocage contournable avec justification, interprétation,
  graphiques, fiches méthode, historique
- Référentiel engins : codes FAO ISSCFG 2016 complets, engins cohérents pour 26 espèces Manche /
  golfe de Gascogne (littérature), codes génériques gérés
- Cartographie : import SHP / GeoPackage / GeoJSON / KML (brut conservé, reprojection), tuiles
  vectorielles, couches de contexte intégrées (rectangles CIEM, lignes de base, 12 / 24 milles, ZEE,
  délimitations — Shom ; aires marines protégées et Natura 2000 — OFB ; terres hors ligne),
  styles par attribut, légende, échelle, export image avec titre / source / logo, cartes enregistrées
- VMS : modèle d'harmonisation Agiltech / CLS, écarts, distances, vitesses, activité de pêche par
  seuils selon l'engin, alerte sur les sauts impossibles, rectangle CIEM, appartenance à une zone
  (jointure spatiale) ; carroyage et rectangles CIEM avec secret statistique, export SIG

## Prochaines étapes

1. **SACROIS (suite)** : référentiels espèces / ports / rectangles CIEM, référentiels et corrections
   d'engins propres à chaque structure (base partagée), recettes enregistrables comme modèles,
   alignement sur les traitements CDP22 / DGAMPA.
2. **Statistiques (suite)** : GLM (Poisson, binomiale négative), GLMM, GAM, séries temporelles,
   ACP / classification ; moteur R utilisé s'il est installé.
3. **Cartographie (suite)** : bande des 3 milles (couche OFB/CNSP à intégrer si licence claire),
   étiquettes sur la carte (polices embarquées), trajectoires par marée, croisement VMS × SACROIS
   (répartition des captures sur les positions de pêche), zones d'activité par noyau de densité.
4. **Composition** : planches multi-graphiques et rapports PDF / PPTX.
5. **macOS** (exécutable), signature de l'exécutable Windows, mises à jour.
6. **Mode serveur** : déploiement partagé par structure, SSO.
7. Export des recettes en script R et Python.
