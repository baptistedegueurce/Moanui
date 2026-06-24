# Moanui
# Data App — Releases
 
Application de visualisation et d'analyse de données halieutiques.
 
---
 
## 📥 Télécharger la dernière version
 
👉 [Télécharger v0.0.1](../../releases/latest)
 
---
 
## 📋 Patch notes
### v0.0.2 — 24/06/2026

**Nouveautés**

- Nouvelle section "Composition" permettant de gérer plusieurs graphiques sur un seul pannel.
  --> Composez des graphiques avec légendes via le cache de l'application et les images présentes sur votre PC.
- Ajout d'un sous-onglet "valeurs uniques" dans l'onglet gestion de la donnée : donne pour la colonne de votre choix les valeurs uniques et leur effectif/ratio sur la donnée totale.
- Refonte des filtres avec une visibilité et un contrôle accru sur les filtres appliqués (vision de tous les filtres actifs et suppression facilitée)
- Ajout en test d'un outil de correction qui détecte les incohérences et permet via une base de donnée interne à l'application de corriger votre donnée en ajoutant une colonne "engin_sug" avec des corrections par bateau.
 
**Corrections**

*Améliorations générales*
- Optimisation majeure de la VMS (95% de gain sur le temps d'exécution pour une perte mineure de qualité)
  
---
 
## 🐛 Bugs connus
 
| Bug | Sévérité | État |
|------|----------|------|
| AUCUN | BUG | RECENSE |

### v0.0.1 — 12/06/2026

**Nouveautés**

- Première version publique
- Nouvelle section "Composition" permettant de gérer plusieurs graphiques sur un seul pannel.
- Ajout d'une fonctionnalité "zone de contexte" dans la partie cartographie
- Ajout de l'export en format ".shp" dans la partie VMS et Cartographie
- Ajout d'une option de création de colonne "case_when" qui permet de donner des conditions sur les valeurs pour coder une colonne
- Ajout d'une option de regroupement des données par catégorie dans le sous onglet "Colonnes" de gestion de la donnée
- Ajout d'une option de filtre "Est dans la liste" qui permet de voir tous les intitulés d'une colonne et de créer par clic une liste de variables à garder.
 
**Corrections**

*Améliorations générales*
- Harmonisation des fonctions d'import à travers les onglets
- Amélioration de l'ergonomie et de l'esthétique de certains espaces

*Amélioration de l'onglet Représentation des données*
- Changement des caractéristiques du graphique L + points (lignes en somme et points en données brutes)
- Changement des caractéristiques du graphique points (points en donnée brute par défaut)
- Harmonisation de l'export des graphiques. Correction des graphiques Aires, Lollipop, Boxplot (et d'autres) qui exportaient des graphes en barre.
- Gestion plus ergonomique des axes. Ajout et correction sur le tri des données sur l'axe X
- Correction des dimensions d'export qui entrainaient un arrêt complet de l'application
- Correction des fonctions de Titrage et Sous-titrage sur la représentation des données
- Correction du facetting dans la représentation des données qui n'exportait qu'un seul graphique

*Amélioration de l'onglet Cartographie*
- Correction du code pour l'affichage des frontières

*Amélioration de l'onglet VMS*
- Optimisation du script de traitement automatisé des données VMS (gain de 5 à 15% selon la version et l'ordinateur)

**Poursuites**

- Ajout d'une option interne de correction (sans écrasement) de la donnée SACROIS
- Correction des problèmes liés à l'ajout de l'onglet "Composition"
- Gestion des légendes plus ergonomique (titres et axes parfois chevauchant)
- Ajout d'une option pour visualiser les valeurs uniques d'une colonne

---
 
## 🐛 Bugs connus
 
| Bug | Sévérité | État |
|------|----------|------|
| Problème de tri des données dans le suivi des quotas | Faible | En cours (secondaire) |
| Nombreux problèmes de prise en main dans l'onglet suivi des quotas | Faible | En cours (secondaire) |
| Patchwork non installé dans le premier .exe d'installation | Moyen | En cours (secondaire) |
| Erreur de rendu graphique lors de l'ajout du groupe | Majeur | Prioritaire |

---
 
## 📦 Versions précédentes
 
👉 [Voir toutes les releases](../../releases)
 
