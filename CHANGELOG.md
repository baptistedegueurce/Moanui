# Journal des versions

Écrit pour les utilisateurs. La section « Non publié » s'affiche en tête de chaque version de développement
publiée automatiquement ; au passage d'une version stable, elle est renommée `[x.y.z] — date`.

## Non publié

- **Nouvelle présentation de l'interface**, sur les règles de systèmes de design publics éprouvés (Carbon d'IBM,
  GOV.UK) : barre du haut sombre à la couleur de la structure, navigation plus lisible, titres et textes sur une
  échelle typographique unique, champs, boutons et tableaux homogènes (en-têtes de tableau marqués, lignes de 40 px),
  angles droits, contrastes conformes WCAG 2.1 AA (texte 4,5:1, bordures de champs 3:1) et focus clavier toujours
  visible. L'accueil devient un « Tableau de bord ». Les structures restées sur la charte par défaut passent à la
  nouvelle ; les chartes personnalisées ne changent pas. Graphiques : plus de légende pour une seule série, titre de
  l'axe horizontal qui ne chevauche plus la source.
- **Rapports PDF et Word aux usages des publications** : bandeau « organisme · nature du document », bloc
  documentaire (organisme, données, auteur, date, version du logiciel), ligne « Pour citer ce document » (modèle des
  rapports du CIEM), pagination « 3 / 6 » avec l'organisme en pied de page, titres jamais isolés en bas de page,
  typographie française (espaces insécables avant : ; % et entre nombre et unité, vrai signe moins).
- **Graphiques : modes Simple et Avancé.** Le mode simple n'affiche que l'essentiel (données, séries, petits
  multiples, filtres, titre et source) ; le mode avancé donne tous les réglages. Changer de mode ne modifie pas le
  graphique.
- **Code R équivalent** (comme dans la version 0.1) : bouton « Code R » sur les graphiques et les analyses
  statistiques. Le script ggplot2 refait le graphique (séries, axes, repères, couleurs de la charte, titre, source,
  export PNG) ; celui des statistiques refait l'analyse avec les fonctions de base de R. Archive à télécharger : script,
  données en CSV et mode d'emploi pour RStudio. Ce que R ne reproduit pas à l'identique (plus d'un axe secondaire, 3D)
  est signalé en tête du script.
- **Statistiques : modes Guidé et Expert.** En mode guidé, trois étapes numérotées et la question reformulée en une
  phrase avec vos colonnes ; le résultat commence par « Ce qu'il faut retenir ». En mode expert, vous imposez le test,
  le seuil de significativité (0,10, 0,05 ou 0,01) et la correction des comparaisons deux à deux (Holm, Bonferroni,
  Benjamini-Hochberg ou aucune) ; interprétation, résumé et fiche méthode suivent ces choix, et les conditions
  d'application restent vérifiées.
- **Guide d'utilisation complet** (Word et PDF, joints à chaque version) : installation, interface, import, traitements,
  SACROIS, jointures et empilements, export et fiches, graphiques (axes multiples, repères, petits multiples),
  cartographie et VMS, statistiques, gestion des quotas et des limitations, réglages, problèmes fréquents ;
  52 figures tirées des données de démonstration, sommaire, index des figures et tableaux.
- **Nouvelle partie Gestion** :
  - *tableau de bord des quotas* : consommation de chaque quota enregistré (jauge colorée selon les seuils d'alerte),
    dernière donnée, projection de fin de période ; import d'une liste de quotas (CSV) ;
  - *suivi d'un quota* : espèces, période, quota et consommation annoncée (ex. DGAMPA) ; débarqué, part consommée,
    reste, écart à l'annonce, courbe cumulée face au quota, consommation par mois, projection (rythme moyen et
    30 derniers jours), date d'atteinte ; fiche de suivi PDF / Word et export Excel ;
  - *limitations et dépassements* : règles par espèce à la marée, au jour, à la semaine, au mois, au trimestre, au
    semestre ou à l'année, sur une période (0 kg = fermeture) ; dépassements par règle, par navire et par mois, lignes
    en cause ; fiche de contrôle PDF / Word et export Excel ; jeux de règles enregistrés.
- Graphiques et dates en français (mois, séparateurs) dans toutes les figures interactives.
- **Fiches statistiques de niveau « article »** : résumé en tête ; résultat principal en écriture normalisée
  (statistique, degrés de liberté, p exacte, taille d'effet et intervalle de confiance à 95 %, par bootstrap
  reproductible quand il n'existe pas de formule) ; taille d'effet pour chaque paire de groupes ; discussion qui
  dépend des résultats (effet faible mais significatif sur grand échantillon, absence de preuve, pseudo-réplication,
  standardisation de CPUE) ; partie reproductibilité. Références vérifiées (Nakagawa et Cuthill 2007, Zuur et Ieno
  2016, Hurlbert 1984, Lin et al. 2013…). L'écriture normalisée et la discussion s'affichent aussi à l'écran.
- **Fiches méthode en PDF et en Word** (jeux de données, statistiques, graphiques, cartes) : bouton « Fiche méthode »
  > PDF (à diffuser), Word (modifiable) ou archive (Markdown, HTML, figures SVG). Figures, tableaux numérotés,
  références et polices intégrés : rendu identique sur tous les postes, sans Word ni logiciel à installer.
- **Graphiques conservés d'une page à l'autre** : en revenant sur Graphiques, le dernier graphique (même non
  enregistré) réapparaît immédiatement, puis ses données sont revérifiées. Mémoire vidée à la déconnexion et au
  changement de structure, jamais écrite sur le disque.
- **Graphiques, composition** : jusqu'à 4 axes verticaux (gauche, droite, second gauche, second droit) avec titre,
  échelle, bornes et unité propres à chaque axe ; pour chaque mesure, forme (barres, courbe, aire, points),
  couleur de la palette, tirets et valeurs affichées, dans tous les graphiques en barres, courbes et aires ;
  repères (ligne de seuil ou de quota, ligne sur une date, zone de période, note) ; légende en haut, à droite,
  en bas ou masquée ; formats prédéfinis (rapport, A4, diapositive, carré, bandeau) ; décimales ; petits
  multiples à échelle commune ou indépendante et nombre de panneaux par ligne. Nombres affichés en entier
  (600 000 € au lieu de 600k), titre sur deux lignes plus rogné. Les graphiques déjà enregistrés s'ouvrent
  comme avant ; la fiche méthode décrit les axes et les repères.
- **Installateur Windows** (`Moanui-installation.exe`) : installation pour l'utilisateur courant, sans droits
  administrateur, raccourcis menu Démarrer et bureau, mise à jour en relançant l'installateur. Corrige la fenêtre
  qui se fermait aussitôt (« Failed to load Python DLL ») après extraction du zip téléchargé ; le zip portable
  reste proposé (le débloquer avant extraction).
- **Données de démonstration** fictives (`exemples/donnees_demo`) : SACROIS 2023-2025, flotte, référentiels, VMS
  Agiltech et CLS 2025, suivi au casier, couches SIG, avec un guide de scénarios de test.
- **Démarrage** : en cas d'erreur au lancement, la fenêtre reste ouverte avec le message, et le détail est
  enregistré dans `moanui-erreur.log` (à côté de Moanui.exe). Test automatique ajouté : zip extrait dans un
  dossier avec espaces et accents, lancement comme un double-clic.
- **Publication automatique** : chaque modification produit une version téléchargeable dans
  Releases (Moanui-windows.zip) avec ses notes de version ; le numéro de version s'affiche dans l'application
  (en bas de la barre latérale).
- **Traitement des données** : panneau à onglets Colonnes, Lignes, Créer, Regrouper, Pêche et Historique ;
  opérations simples appliquées directement avec « Annuler » ; nouvelles opérations « Transformer des colonnes »
  et « Fusionner des colonnes ».
- **Fiches méthode** illustrées (tableaux, figures, références bibliographiques), exportables en Markdown,
  HTML imprimable et ZIP, pour les jeux, statistiques, graphiques et cartes.
- **VMS × SACROIS** : répartition des captures déclarées sur les positions de pêche, avec bilan de la part
  attribuée avant validation.
- **Statistiques** : modèles linéaires généralisés guidés (Poisson, binomiale négative, Gamma, logistique),
  indice d'abondance standardisé.
- **Cartographie et VMS** : import de couches SIG, couches de contexte intégrées (CIEM, ZEE, 12 milles,
  AMP, Natura 2000), harmonisation Agiltech / CLS, activité de pêche, carroyage avec secret statistique.
- **Visuel** : nouvelle police, accueil avec les derniers travaux, guide des bonnes pratiques référencé.
