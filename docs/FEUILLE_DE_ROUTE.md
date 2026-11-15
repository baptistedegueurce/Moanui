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

## Objectif : un mois (mi-novembre → mi-décembre 2026)

Une application complète, simple à prendre en main et **très accompagnée** pour le traitement. Priorité à
la prise en main et à l'accompagnement avant d'ajouter des fonctions. Une part de chaque semaine est
réservée aux **retours de test** de l'utilisateur (ils passent avant le reste).

Légende : **[validé]** décidé avec l'utilisateur · **[proposé]** à discuter · **[à confirmer]** dépend de
formats ou de règles métier à vérifier auprès des structures (ne pas coder de mémoire).

### Semaine 1 : distribution et premiers retours
- [validé] Exécutable publié dans Releases à chaque push, avec notes de version (CHANGELOG + commits). **Fait.**
- [proposé] Installateur Windows par utilisateur (évite le blocage des fichiers extraits du zip). **Fait.**
- [proposé] **Signature de l'exécutable** (supprime l'alerte SmartScreen et le blocage Smart App Control) : offre à
  choisir (certificat, service de signature en ligne, programme gratuit pour projets libres) [à confirmer : coût].
- [validé] Retours de test de l'utilisateur sur l'exe : corrections au fil de l'eau.
- [proposé] Page « Nouveautés » dans l'application (lit le CHANGELOG) et avis « une nouvelle version est
  disponible » (interroge Releases si Internet, sans rien installer seul).
- [proposé] Première version stable 0.2.0 (« Latest ») une fois les retours bloquants traités.

### Semaine 2 : prise en main et accompagnement
- [proposé] **Assistant « Que voulez-vous faire ? »** à l'accueil : parcours pas à pas (préparer un fichier
  SACROIS, faire le bilan d'une flottille, carte d'activité VMS, comparer deux années, vérifier les engins),
  chaque parcours enchaînant import → contrôles → traitement → graphique/carte → export + fiche méthode.
- [proposé] **Jeux de démonstration** synthétiques (SACROIS, VMS, criée) et visite guidée de l'interface.
- [proposé] **Aide en contexte** sur chaque opération : à quoi ça sert, exemple avant / après, pièges ;
  **glossaire halieutique** (marée, métier DCF, effort, CPUE, LPUE, secret statistique, rectangle CIEM…).
- [proposé] Messages d'erreur en langage clair avec l'action à faire ; contrôles qui proposent la
  correction en un clic (dates mal lues, séparateur décimal, codes avec zéros perdus, doublons).
- [proposé] **Modèles de recettes** : enregistrer une recette et l'appliquer au fichier du mois suivant
  (même format), avec vérification des colonnes attendues ; modèles partagés au niveau de la structure.

### Semaine 3 : outils métier pour les comités et OP
- [proposé] **Bilans automatiques de flottille** : tableau de bord débarquements / valeur / prix moyen /
  effort / nombre de navires par port, espèce, métier, mois, avec comparaison N / N-1 et export en rapport.
- [proposé] **Analyse d'impact d'une zone** (parc éolien, AMP, extraction, zone de conflit) : part de
  l'activité VMS et de la valeur des captures dans la zone, navires et métiers concernés, dépendance
  économique par navire, carte et rapport type. Très demandé pour les concertations.
- [proposé] Référentiels espèces (FAO 3-alpha, noms communs), ports, rectangles CIEM ; coefficients de
  conversion poids vif / débarqué [à confirmer : source officielle à retenir].
- [à confirmer] Lecture directe des autres sources courantes : ventes en criée (halles à marée), journaux de
  bord et fiches de pêche des moins de 10 m, fichier flotte UE. Formats à obtenir auprès des structures.

### Semaine 4 : restitution et stabilisation
- [proposé] **Rapports composés** (PDF et Word) à la charte de la structure : planches de graphiques et
  cartes, texte, tableaux, fiche méthode en annexe ; modèles « bilan annuel » et « note de conjoncture ».
- [proposé] Production en série : un graphique ou une carte par espèce / port / mois en un clic (atlas).
- [proposé] Sauvegarde et restauration de l'espace de travail (un fichier), transfert vers un autre poste.
- [proposé] Performances sur 500 000 lignes, tests sur les vrais fichiers de l'utilisateur, version stable.

## Idées pour après le mois (à prioriser ensemble)

Gestion des pêches :
- [à confirmer] **Licences et autorisations** (coquille Saint-Jacques, bulots, crustacés, pêche à pied…) :
  registre, contingents, critères d'attribution, suivi des campagnes, édition des listes.
- [à confirmer] **Suivi de consommation des quotas / sous-quotas** à partir des débarquements, alertes de
  seuil ; formats des données de quotas à obtenir.
- [à confirmer] **Évaluation des gisements** (campagnes de prospection coquille, palourde…) : estimateurs
  stratifiés de biomasse, cartes de densité, comparaison interannuelle.
- [proposé] Calendrier des mesures de gestion (fermetures, tailles minimales, zones) et vérification des
  déclarations par rapport à ces mesures.
- [proposé] Captures accessoires et accidentelles (observations à bord), enquêtes auprès des pêcheurs
  (saisie de questionnaires et analyse).
- [proposé] Saisie de données directement dans l'application (formulaires) pour les structures qui collectent.

Analyse (déjà prévu) :
- SACROIS : corrections d'engins propres à chaque structure (base partagée), alignement CDP22 / DGAMPA.
- Statistiques : GLMM (effet navire), GAM, modèle delta assisté, séries temporelles, ACP / classification ;
  moteur R utilisé s'il est installé.
- Cartographie : bande des 3 milles (licence OFB/CNSP à vérifier), étiquettes (polices embarquées),
  trajectoires et VMS × SACROIS par marée, zones d'activité par noyau de densité.

Plateforme :
- macOS, signature de l'exécutable Windows (évite l'alerte SmartScreen ; coût du certificat à voir).
- Mode serveur partagé par structure, SSO ; export des recettes en script R et Python.
