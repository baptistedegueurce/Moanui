# Moanui

Application locale de traitement, d'analyse et de visualisation de données halieutiques
(SACROIS, marées, VMS, quotas, référentiels…), pensée pour les comités des pêches,
organisations de producteurs et structures du secteur.

**L'idée : la puissance de R, la prise en main d'Excel, et les bonnes pratiques imposées par défaut.**

- **Le fichier brut n'est jamais modifié.** Il est copié en lecture seule avec son empreinte SHA-256 ;
  toutes les corrections sont des étapes de *recette*, réversibles et justifiées.
- **Chaque traitement est documenté.** Une fiche méthode Markdown (source, étapes, lignes à chaque étape,
  auteur, requête pour tout refaire) accompagne chaque export et chaque graphique.
- **Les erreurs classiques sont détectées** : dates impossibles, `NA` textuels, codes à zéros initiaux,
  rectangles CIEM pris pour des nombres, jointures qui dupliquent les lignes, fichiers empilés
  dont les unités diffèrent (t / kg), codes avec plusieurs libellés, noms de navire non uniques…
- **Multi-structures** : comptes, rôles (admin / analyste / lecteur), données cloisonnées
  avec partage explicite, charte graphique et logo par structure.

Tout tourne sur le poste de l'utilisateur (serveur local `127.0.0.1`, aucune donnée envoyée à l'extérieur).

## Lancer Moanui

### Utilisateur Windows (sans installation ni droits administrateur)

1. Télécharger `Moanui-windows.zip` depuis les [releases](../../releases) (ou l'onglet *Actions* →
   « Exécutable Windows » → artefact) ;
2. dézipper où l'on veut (Bureau, Documents…) ;
3. double-cliquer sur `Moanui.exe` : Moanui s'ouvre dans le navigateur.

Les données sont stockées dans `%LOCALAPPDATA%\Moanui` (modifiable avec `--home` ou `MOANUI_HOME`) et sont
conservées lors des mises à jour : il suffit de remplacer le dossier de l'application.

Pour publier une version : créer une étiquette `vX.Y.Z` ; le workflow construit le zip, vérifie que
l'exécutable démarre et l'attache à la release.

### Sans exécutable (uv)

Avec [uv](https://docs.astral.sh/uv/) installé pour l'utilisateur et l'interface construite :
`lancer_moanui.bat` (Windows) ou `lancer_moanui.command` (macOS).

### Développement

```bash
cd frontend && npm install && npm run build   # construit l'interface dans backend/moanui/static
cd ../backend && uv venv && uv pip install -e ".[dev]"
uv run moanui                                  # http://127.0.0.1:8765
uv run pytest                                  # tests
```

Pour développer l'interface avec rechargement à chaud : `uv run moanui --no-browser` d'un côté,
`npm run dev` de l'autre (http://localhost:5173, l'API est relayée).

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Feuille de route](docs/FEUILLE_DE_ROUTE.md)

## Historique

Les versions 0.0.x – 0.1.x (application R Shiny) sont sur la branche `script` et dans les
[releases](../../releases). La version 0.2 est une réécriture complète.
