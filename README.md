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

### Utilisateur (Windows / macOS, sans droits administrateur)

Depuis une archive de version (interface déjà construite) :

1. Installer [uv](https://docs.astral.sh/uv/getting-started/installation/) (installation utilisateur, pas d'admin) ;
2. double-cliquer sur `lancer_moanui.bat` (Windows) ou `lancer_moanui.command` (macOS).

uv télécharge Python et les dépendances la première fois, puis Moanui s'ouvre dans le navigateur.
Les données sont stockées dans le dossier utilisateur (`%LOCALAPPDATA%\Moanui` sous Windows,
`~/Library/Application Support/Moanui` sous macOS), modifiable avec `--home` ou `MOANUI_HOME`.

> Depuis le dépôt git, l'interface doit d'abord être construite (voir « Développement »).
> Un exécutable autonome (sans uv) est prévu : voir la feuille de route.

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
