# Les structures de la pêche professionnelle et ce qu'elles attendent de Moanui

Document de travail pour prioriser la feuille de route. Chaque affirmation renvoie à une source effectivement lue
(consultée en novembre 2026) ; ce qui n'a pas pu être vérifié est marqué **[à confirmer]**. Rien de ce document n'est
encore repris dans l'appli ni dans le guide.

## 1. Qui fait quoi

| Structure | Rôle (d'après la source) | Données qu'elle manipule | Ce que Moanui peut lui apporter | Source |
|---|---|---|---|---|
| **CNPMEM** (comité national) | « Organisme de droit privé chargé de missions de service public » ; « saisi par l'Etat pour avis sur les mesures réglementaires relatives à la gestion des ressources marines » ; « peut également édicter ses propres règles professionnelles, obligatoires pour les pêcheurs concernés ». Financé surtout par la cotisation professionnelle obligatoire (CPO) et les quotes-parts sur les licences | Délibérations, licences, avis sur les arrêtés | Fiches chiffrées pour les avis (D1, D2), registre des licences (F1) | [CNPMEM](https://www.comite-peches.fr/le-cnpmem/) |
| **CRPMEM** (12 comités régionaux) | Missions de l'article L912-3, « à l'échelle des bassins maritimes » ; « participent à l'élaboration de la réglementation régionale » ; représentent la profession auprès des préfets de région, des DIRM et des collectivités | Licences et contingents régionaux, VMS et SACROIS pour les études d'impact (éolien, AMP) | Analyse d'impact d'une zone (E1), suivi des gisements (F3), contrôle des règles régionales (F4) | [CNPMEM, comités en région](https://www.comite-peches.fr/le-cnpmem/comites-des-peches-en-region/) |
| **CDPMEM / CIDPMEM** (13 comités départementaux ou interdépartementaux) | « La représentation et la promotion, au niveau local, des intérêts généraux de la profession » ; « l'information et le conseil aux entreprises de pêche » | Suivi local de la flottille, pêche à pied | Tableaux de bord simples, fiches port (D1, D2, I2) | même source |
| **Organisations de producteurs (OP)** | 15 OP reconnues, qui gèrent « plus de 90 % des possibilités de pêche attribuées à la France » et répartissent les quotas entre leurs membres « en fonction des critères de leur choix » | Sous-quotas, consommation par navire, plans de gestion, marché | Suivi des quotas et alertes (Gestion, F2), analyse des prix (D5) | [Oceana, briefing 2024](https://europe.oceana.org/wp-content/uploads/sites/26/2024/07/Briefing-Comment-la-France-attribue-t-elle-les-possibilites-de-peche-a-ses-pecheurs-for-screens.pdf), p. 3 |
| **DGAMPA** (administration) | Supervise la répartition des possibilités de pêche, conseillée par la CCGRH (OP) et le CNPMEM ; gère le sous-quota collectif des navires hors OP, « premier arrivé, premier servi » | Quotas, consommation nationale, journaux de bord | Comparaison « consommation annoncée » / données propres (déjà dans Gestion) | Oceana, p. 2-3 |
| **Prud'homies** (Méditerranée) | Réglementent localement (postes, tailles de filets et d'hameçons) mais « sont dépourvues d'autorité réglementaire officielle » sur les possibilités de pêche | Règles locales | Règles de limitation propres (F4) | Oceana, p. 3 |
| **Ifremer, Système d'informations halieutiques (SIH)** | SACROIS : « rapprochement, vérification, contrôles de cohérence de différents flux » (ventes, déclarations, VMS) ; estimations mensuelles « spatialisées et redressées » avec des « indicateurs de qualification » ; projet DPMA (maîtrise d'ouvrage) / Ifremer | Fichiers SACROIS par navire × marée × jour, rapprochement marées-ventes, catégories commerciales | Profils d'import SACROIS (B1), lecture des indicateurs de qualification | [Sextant, fiche SACROIS](https://sextant.ifremer.fr/geonetwork/srv/api/records/3e177f76-96b0-42e2-8007-62210767dc07) |

## 2. Comment se répartissent les quotas (utile au module Gestion)

- Les possibilités de pêche sont réparties chaque année en sous-quotas pour les membres des OP et pour les navires hors OP,
  qui soumettent des plans de gestion à l'approbation du ministère (article R921-61 du Code rural et de la pêche
  maritime, cité par Oceana p. 2).
- Le critère principal reste l'antériorité des captures sur 2001-2003 (article R921-35, Oceana p. 3) : pondération
  estimée à 96 % en 2022, contre 1 % pour l'environnement et 3 % pour les contributions socio-économiques locales.
- Les attributions aux OP et aux navires hors OP sont publiées chaque année au Journal officiel (Oceana p. 3).
- Plans de gestion à notifier à la DGAMPA avant le 31 mai, et mesures exigées pour les « stocks sensibles » dont la
  consommation dépasse 80 % (arrêté du 4 décembre 2024) **[à confirmer]** : vu seulement dans des extraits de recherche,
  le texte n'a pas été lu. Si c'est confirmé, le seuil d'alerte de 80 % de Moanui tombe juste et peut être nommé ainsi.

**Pour Moanui** : importer les attributions publiées au JO comme quotas de référence ; afficher par OP ou hors OP ;
marquer les stocks sensibles ; exporter un tableau prêt pour le plan de gestion.

## 3. Le nouveau règlement contrôle (UE) 2023/2842 : ce qui change pour les données

Source : texte officiel au JO UE du 20.12.2023, mis en ligne par le
[CNPMEM](https://www.comite-peches.fr/wp-content/uploads/2025/11/Nouveau-reglement-controle-2023-2842.pdf)
(articles 7 et 8 pour les dates).

| Mesure | Date | Article | Conséquence pour Moanui |
|---|---|---|---|
| Règle générale : l'essentiel du règlement modifié s'applique | 10 janvier 2026 | art. 7 § 2 | Les formats des journaux de bord et des notes de vente évoluent : surveiller les profils d'import (B1, B3) |
| **Marge de tolérance** entre journal de bord et débarquement : 10 % par espèce, 20 % sous 100 kg | 10 juillet 2024 | art. 14 § 3 (modifié) ; art. 7 § 5 | Nouveau contrôle possible : écart journal / pesée par marée et par espèce (C3, F4) |
| **Navires de moins de 12 m** : dispositif de géolocalisation (« qui ne doit pas nécessairement être installé à bord ») et journal de pêche électronique transmis « avant le début du débarquement » | 10 janvier 2028 | art. 9 § 3 et art. 15 § 2 (modifiés) ; art. 8 § 2 | Toute la flotte aura des positions : les imports VMS doivent tenir des volumes bien plus grands, et la combinaison VMS + enquêtes (E2) ne servira plus que pour l'historique |
| **Pêche sans navire** (pêche à pied) : licence ou enregistrement, enregistrement des captures | 10 janvier 2028 | art. 54 quinquies (inséré) ; art. 7 § 7 | Module pêche à pied de l'ancienne appli à reprendre (biomasse, suivi des gisements) |
| **Pêche récréative** : enregistrement des pêcheurs et déclaration électronique des captures pour les stocks sous quota, plan pluriannuel ou obligation de débarquement | 10 janvier 2026 (le système de la Commission est en développement depuis 2024) | art. 55 (modifié) | Import des déclarations récréatives pour compléter les bilans par stock **[format à confirmer]** |
| **Pesée** de toutes les quantités par espèce dès le débarquement, sur des systèmes approuvés | 10 janvier 2026 | art. 60 (modifié) | Les données de pesée deviennent la référence pour le contrôle de la marge de tolérance |

## 4. Ce qu'on en tire pour la feuille de route

Par ordre d'intérêt pour les structures :

1. **Contrôle de la marge de tolérance** (nouveau, rattaché à C3 / F4) : écart entre journal de bord et pesée, par marée
   et espèce, avec les seuils de 10 % / 20 %. Les comités et les OP pourraient prévenir leurs adhérents avant un contrôle.
2. **Quotas « à la française »** dans Gestion : sous-quotas OP / hors OP, import des attributions publiées, stocks
   sensibles (si le seuil de 80 % est confirmé).
3. **Montée en charge du VMS** pour les moins de 12 m d'ici 2028 : tester l'import et les cartes sur plusieurs millions de
   positions.
4. **Pêche à pied** (licences, gisements, biomasse) : priorité 2028, et reprise d'une fonction de l'ancienne appli.
5. **Avis et délibérations** (CNPMEM, CRPMEM) : fiche chiffrée type, à joindre à un avis sur un projet d'arrêté (I2).

## Sources consultées

- [CNPMEM : le comité national](https://www.comite-peches.fr/le-cnpmem/) et
  [les comités en région](https://www.comite-peches.fr/le-cnpmem/comites-des-peches-en-region/)
- [Règlement (UE) 2023/2842, texte du JO UE mis en ligne par le CNPMEM](https://www.comite-peches.fr/wp-content/uploads/2025/11/Nouveau-reglement-controle-2023-2842.pdf)
- [Oceana (2024), « Comment la France attribue-t-elle les possibilités de pêche à ses pêcheurs ? »](https://europe.oceana.org/wp-content/uploads/sites/26/2024/07/Briefing-Comment-la-France-attribue-t-elle-les-possibilites-de-peche-a-ses-pecheurs-for-screens.pdf)
  (ONG : les chiffres de répartition sont les siens, à recouper avec les textes officiels)
- [Ifremer, fiche Sextant « Données de production et d'effort de pêche (SACROIS) »](https://sextant.ifremer.fr/geonetwork/srv/api/records/3e177f76-96b0-42e2-8007-62210767dc07)

Non lus (accès refusé ou indisponible) : Légifrance (articles L912-2 et L912-3), mer.gouv.fr (page « Révision du
contrôle de la pêche »). Les missions légales exactes des comités restent donc à vérifier dans le Code.
