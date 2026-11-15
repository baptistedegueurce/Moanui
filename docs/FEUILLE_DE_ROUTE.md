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

## Catalogue des fonctions possibles (à prioriser)

Liste ouverte, numérotée pour pouvoir répondre « on garde 3, 7, 12… ». Taille : **S** (≤ 1 jour), **M** (2 à 4 jours),
**L** (1 semaine et plus). « Dépend de » = format, accès ou règle à obtenir avant de coder. Les sources servent
d'inspiration ; aucun chiffre ni règle n'en est repris sans lecture du document original.

### A. Prise en main et accompagnement
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| A1 | Assistant « Que voulez-vous faire ? » (parcours guidés de bout en bout) | Un débutant produit un bilan sans connaître les menus | L | idée sans source |
| A2 | Données de démonstration intégrées à l'appli + visite guidée | Essayer sans ses propres fichiers | S | `exemples/donnees_demo` (fait) |
| A3 | Aide en contexte sur chaque opération (exemple avant / après, pièges) | Moins d'erreurs de manipulation | M | idée sans source |
| A4 | Glossaire halieutique (marée, métier DCF, effort, CPUE, secret statistique…) | Vocabulaire commun dans les fiches | S | idée sans source |
| A5 | Correction proposée en un clic sur chaque alerte qualité | Corriger sans chercher l'étape | M | idée sans source |
| A6 | Page « Nouveautés » + avis de nouvelle version | Les utilisateurs suivent les évolutions | S | CHANGELOG (fait) |
| A7 | Mode « explication » des statistiques : schéma animé de ce que fait le test | Comprendre avant de conclure | M | idée sans source |

### B. Sources de données et imports
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| B1 | Profils d'import par émetteur SACROIS (colonnes renommées et typées automatiquement) | Plus de mise en forme manuelle chaque mois | M | exemples réels des structures |
| B2 | Import des ventes en criée (données VISIOMer, ex-RIC, de FranceAgriMer) | Prix et volumes par halle à marée, espèce, calibre | M | format d'extraction à obtenir ([FranceAgriMer](https://www.franceagrimer.fr/sites/default/files/2025-06/BIL-MER-VENTES_HAM-A24.pdf)) |
| B3 | Import des journaux de bord électroniques (ERS) et fiches de pêche des moins de 10 m | Données plus fines que SACROIS, plus rapides | L | format d'export [à confirmer] ([arrêté du 18/03/2015](https://www.dm.sud-ocean-indien.developpement-durable.gouv.fr/IMG/pdf/arrete_du_18_mars_2015_relatif_aux_obligations_declaratives_peche_maritime_cle5593d6-1.pdf)) |
| B4 | Import des enquêtes d'activité type VALPENA (zones fréquentées par navire et par mois) | Cartographier l'activité des navires sans VMS | L | méthode et format du GIS VALPENA ([présentation](https://www.agglo-larochelle.fr/documents/10839/11884269/VALPENA.pdf/b00cc3e7-781d-4c10-b4bd-1b891ced7614)) |
| B5 | Import des observations à bord (ObsMer : rejets, captures accidentelles) | Analyses de captures accessoires | M | accès aux données Ifremer [à confirmer] ([fiche ObsMer](https://sextant.ifremer.fr/geonetwork/srv/api/records/24538369-ea5a-48d7-a89b-0c9530247ed2)) |
| B6 | Fichier flotte (FPC / flotte UE) intégré comme référentiel navires | Longueur, puissance, port d'attache sans saisie | M | fichier public UE à télécharger |
| B7 | Fichiers multiples d'un coup (dossier mensuel) avec empilement automatique | Gain de temps sur les séries | S | idée sans source |
| B8 | Saisie directe dans l'appli (formulaires de campagne, enquêtes) | Structures qui collectent elles-mêmes | L | idée sans source |
| B9 | Connexion à une base existante (PostgreSQL, Access, partage réseau) | Éviter les exports manuels | M | besoin à confirmer |

### C. Traitement et qualité
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| C1 | Recettes enregistrées comme modèles, appliquées au fichier du mois suivant | Traitement mensuel en un clic | M | prévu |
| C2 | Corrections d'engins / espèces partagées par structure | Les corrections servent à tous | M | prévu |
| C3 | Règles de contrôle personnalisées (« taille > 24 m interdit dans la bande des 3 milles »…) | Contrôles propres à chaque structure | M | idée sans source |
| C4 | Comparaison de deux versions d'un fichier (lignes ajoutées / modifiées) | Suivre les révisions des exports | M | idée sans source |
| C5 | Export de la recette en script R et Python | Reproductibilité, passage aux scientifiques | M | prévu |
| C6 | Identification automatique des métiers par classification (méthode DCF) | Métiers sans table manuelle | L | [vmstools](https://research.wur.nl/en/publications/vmstools-open-source-software-for-the-processing-analysis-and-vis/) |

### D. Analyse des flottilles (SACROIS, ventes)
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| D1 | Tableau de bord flottille : débarquements, valeur, prix, effort, navires actifs, N / N-1 | Réponse immédiate aux questions courantes | M | inspiré des fiches SIH ([Ifremer](https://archimer.ifremer.fr/doc/00912/102420/113688.pdf)) |
| D2 | Fiches automatiques par port, quartier, flottille ou espèce | Restitution type « fiche SIH » à la charte de la structure | M | même source |
| D3 | Dépendance économique des navires à une espèce, une zone, un port | Arguments chiffrés pour les concertations | M | idée sans source |
| D4 | Saisonnalité et calendrier d'activité par métier | Voir quand chaque métier travaille | S | idée sans source |
| D5 | Analyse des prix (évolution, effet volume / prix, comparaison entre criées) | Suivi de marché pour les OP | M | dépend de B2 |
| D6 | Indicateurs économiques simples (chiffre d'affaires, valeur par jour de mer) | Évaluer la rentabilité d'un métier | M | coûts non disponibles dans SACROIS |

### E. Spatial et VMS
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| E1 | **Analyse d'impact d'une zone** (éolien, AMP, extraction) : activité, valeur, navires, métiers touchés, rapport type | Besoin récurrent dans les débats publics | L | pratiques des études VMS × SACROIS ([Cerema / Normandie](https://www.energiesdelamer.eu/wp-content/uploads/2022/01/etude_peche_VMS_VDef.pdf), [enjeux pêche Bretagne Sud](https://eolbretsud.debatpublic.fr/wp-content/uploads/enjeux-peche.pdf)) |
| E2 | Combinaison VMS + enquêtes pour les navires non équipés | Pallier la couverture partielle du VMS | L | limite signalée par les comités ([CRPMEM PACA](https://eos.debatpublic.fr/wp-content/uploads/EOS-CA-CRPMEM-PACA.pdf)) ; dépend de B4 |
| E3 | Trajectoires interpolées par marée, VMS × SACROIS par marée | Répartition plus juste des captures | M | [vmstools](https://research.wur.nl/en/publications/vmstools-open-source-software-for-the-processing-analysis-and-vis/) |
| E4 | Zones d'activité par noyau de densité, comparaison entre années | Cartes de fréquentation lissées | M | prévu |
| E5 | Bande des 3 milles, étiquettes, polices hors ligne | Cartes complètes | M | licence OFB / CNSP à vérifier |
| E6 | Atlas : une carte par espèce, mois ou métier en un clic | Rapports cartographiques rapides | M | idée sans source |
| E7 | Sensibilité au choix de la maille (grille, mois, trimestre) | Robustesse des cartes d'effort | S | [vmstools / DTU](https://orbit.dtu.dk/en/projects/development-of-tools-for-logbook-and-vms-data-analysis-38751/) |

### F. Gestion des pêcheries
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| F1 | **Licences et contingents** : registre, demandes, critères d'attribution, listes éditées | Cœur du travail des comités (délibérations par gisement) | L | règles par délibération ([exemple CNPMEM coquille](https://www.comite-peches.fr/wp-content/uploads/B26-2018_Db-coquillages-cadre.pdf)) [à confirmer] |
| F2 | Suivi de consommation des quotas / sous-quotas, alertes de seuil | Anticiper les fermetures | M | format des données quotas ; exemple de publications ([Royaume-Uni](https://www.gov.uk/government/statistical-data-sets/quota-use-statistics)) |
| F3 | Évaluation des gisements (campagnes de prospection, estimateurs stratifiés, cartes de densité) | Base pour fixer les ouvertures | L | protocole de campagne ([exemple Belle-Île / Quiberon, Ifremer](https://archimer.ifremer.fr/doc/00289/39988/79639.pdf)) |
| F4 | Calendrier des mesures (fermetures, tailles, zones) et contrôle des déclarations | Repérer les déclarations hors règles | M | textes réglementaires par structure |
| F5 | Captures accidentelles et espèces protégées : saisie et synthèse | Obligations de suivi | M | dépend de B5 |
| F6 | Suivi des engins perdus / macrodéchets | Programmes environnementaux | S | idée sans source |

### G. Statistiques
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| G1 | Modèle delta assisté (présence + quantité) | Standardiser des CPUE avec zéros | M | prévu |
| G2 | GLMM (effet navire), GAM | Indices plus robustes | L | prévu |
| G3 | Séries temporelles (tendance, saisonnalité, rupture) | Évolutions interannuelles | M | prévu |
| G4 | ACP / classification des navires ou marées | Typologies de flottilles | M | prévu |
| G5 | Plans de sondage et estimateurs (enquêtes, campagnes) | Extrapoler des enquêtes partielles | L | travaux sur l'échantillonnage VALPENA ([résumé](https://toltex.imag.fr/users/RCqls/Workshop/sondages2018/resumesLongs/subm42.pdf)) |
| G6 | Moteur R facultatif | Méthodes avancées si R est installé | M | prévu |

### H. Graphiques et composition
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| H1 | **Plusieurs axes verticaux** (jusqu'à 4), réglages par axe (titre, échelle, bornes, unité) | Mettre des grandeurs différentes sur une même figure | M | **en cours** |
| H2 | **Style par mesure** : barres / courbe / aire / points, couleur de la palette, tirets, valeurs affichées | Composer librement dans tout graphique agrégé | M | **en cours** |
| H3 | **Lignes et zones de référence** (quota, moyenne, seuil, période de fermeture) et annotations | Lecture guidée, comme dans les outils de datajournalisme ([Datawrapper](https://www.datawrapper.de/blog/dual-axis-charts), [Flourish](https://flourish.studio/2020/11/17/introducing-annotations/)) | M | **en cours** |
| H4 | **Formats prédéfinis** (rapport A4, diapositive 16:9, carré), légende, format des nombres | Export directement utilisable | S | **en cours** |
| H5 | Petits multiples : échelle commune ou indépendante, nombre de colonnes | Comparaisons justes entre panneaux | S | **en cours** ([Datawrapper](https://www.datawrapper.de/blog/small-multiple-line-charts)) |
| H6 | Planches : assembler plusieurs graphiques et cartes sur une page, export PNG / SVG / PDF | Pages de rapport prêtes | L | à valider |
| H7 | Styles enregistrés par structure (modèles de graphiques) | Cohérence visuelle entre auteurs | S | idée sans source |
| H8 | Graphiques en cascade (écarts N / N-1 par espèce), pyramides, diagrammes de Sankey (port → espèce → acheteur) | Types utiles aux bilans | M | [Datawrapper](https://www.datawrapper.de/blog/waterfall-charts) |

### I. Restitution et rapports
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| I1 | Rapports PDF / Word à la charte (graphiques, cartes, tableaux, fiche méthode en annexe) | Livrable final sans copier-coller | L | prévu |
| I2 | Modèles « bilan annuel », « note de conjoncture », « fiche port » | Rapports récurrents automatisés | M | dépend de I1 |
| I3 | Export PowerPoint des graphiques | Réunions et conseils | M | idée sans source |
| I4 | Publication d'un tableau de bord consultable hors de l'appli (HTML autonome) | Diffusion aux adhérents | M | inspiré des tableaux de bord publics ([Pêches et Océans Canada](https://www.dfo-mpo.gc.ca/stats/commercial/sea-maritimes-eng.htm)) |

### J. Plateforme
| N° | Fonction | Ce que ça apporte | Taille | Dépend de / source |
|---|---|---|---|---|
| J1 | Signature de l'exécutable (supprime l'avertissement SmartScreen) | Installation sans alerte | M | offres et éligibilité à confirmer : [options Microsoft](https://learn.microsoft.com/windows/apps/package-and-deploy/code-signing-options), SignPath Foundation pour projets libres (le dépôt n'a pas encore de licence) |
| J2 | Sauvegarde / restauration de l'espace, transfert vers un autre poste | Sécurité des données | S | prévu |
| J3 | Mode serveur partagé par structure, comptes centralisés | Travail à plusieurs | L | financement |
| J4 | Version macOS | Postes Mac | M | prévu |
| J5 | Journal d'audit exportable (qui a fait quoi, quand) | Traçabilité pour les financeurs | S | journal existant |
