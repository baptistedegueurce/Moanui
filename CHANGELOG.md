# Journal des versions

Écrit pour les utilisateurs. La section « Non publié » s'affiche en tête de chaque version de développement
publiée automatiquement ; au passage d'une version stable, elle est renommée `[x.y.z] — date`.

## Non publié

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
