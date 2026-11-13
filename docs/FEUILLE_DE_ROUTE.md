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

## Prochaines étapes

1. **SACROIS (suite)** : référentiels espèces / ports / rectangles CIEM, référentiels et corrections
   d'engins propres à chaque structure (base partagée), recettes enregistrables comme modèles,
   alignement sur les traitements CDP22 / DGAMPA.
2. **Statistiques** : assistant de choix du test, vérification des conditions avec blocage
   contournable, tests, régressions (LM, GLM, GLMM, GAM), séries temporelles, ACP ; guides
   pas à pas, aide à l'interprétation, fiche méthode. Moteur R si installé, sinon Python.
3. **Cartographie** : import SHP / GeoJSON / GeoPackage converti en GeoParquet + tuiles
   vectorielles (MapLibre), couches de contexte (CIEM, ZEE, 3/12 milles, AMP, Natura 2000,
   gisements), VMS (harmonisation Agiltech / CLS, carroyage, zones d'activité), fond hors ligne.
4. **Composition** : planches multi-graphiques et rapports PDF / PPTX.
5. **macOS** (exécutable), signature de l'exécutable Windows, mises à jour.
6. **Mode serveur** : déploiement partagé par structure, SSO.
7. Export des recettes en script R et Python.
