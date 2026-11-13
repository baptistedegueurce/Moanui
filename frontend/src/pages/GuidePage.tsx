import { Accordion, Paper, Text, Title, List, Code } from '@mantine/core';

export default function GuidePage() {
  return (
    <Paper p="xl" withBorder maw={900}>
      <Title order={2}>Bonnes pratiques de traitement</Title>
      <Text c="dimmed" mb="lg">
        Moanui applique ces règles automatiquement ; cette page explique pourquoi.
      </Text>
      <Accordion multiple defaultValue={['brut']}>
        <Accordion.Item value="brut">
          <Accordion.Control>1. Ne jamais toucher au fichier brut</Accordion.Control>
          <Accordion.Panel>
            <List spacing={6}>
              <List.Item>À l'import, le fichier est copié tel quel, en lecture seule, avec son empreinte SHA-256.</List.Item>
              <List.Item>Toutes les modifications sont des <b>étapes de recette</b>, appliquées à une copie.</List.Item>
              <List.Item>On peut désactiver, supprimer ou réordonner une étape : rien n'est jamais perdu.</List.Item>
              <List.Item>Le bouton « Vérifier l'intégrité » confirme que le brut n'a pas bougé.</List.Item>
            </List>
          </Accordion.Panel>
        </Accordion.Item>
        <Accordion.Item value="trace">
          <Accordion.Control>2. Tout tracer, tout justifier</Accordion.Control>
          <Accordion.Panel>
            <List spacing={6}>
              <List.Item>Chaque étape garde son auteur, sa date et une justification (ex. : « mois 13 impossible, corrigé d'après le carnet »).</List.Item>
              <List.Item>La <b>fiche méthode</b> (Markdown) résume la source, les traitements dans l'ordre, le nombre de lignes à chaque étape et la requête pour tout refaire.</List.Item>
              <List.Item>Elle est jointe automatiquement à chaque export.</List.Item>
            </List>
          </Accordion.Panel>
        </Accordion.Item>
        <Accordion.Item value="controle">
          <Accordion.Control>3. Contrôler avant d'analyser</Accordion.Control>
          <Accordion.Panel>
            <List spacing={6}>
              <List.Item>Onglet « Contrôle qualité » : vides, valeurs négatives, valeurs aberrantes, codes avec plusieurs libellés, dates incohérentes.</List.Item>
              <List.Item>Jointures : Moanui prévient si des clés n'ont pas de correspondance ou si la jointure duplique des lignes (double comptage).</List.Item>
              <List.Item>Empilement de fichiers : alerte si une colonne manque ou si les ordres de grandeur diffèrent (tonnes / kg).</List.Item>
              <List.Item>
                Compter les navires avec leur identifiant (<Code>cfr_cod</Code>), jamais avec leur nom : plusieurs navires peuvent porter le même.
              </List.Item>
            </List>
          </Accordion.Panel>
        </Accordion.Item>
        <Accordion.Item value="secret">
          <Accordion.Control>4. Secret statistique et données personnelles</Accordion.Control>
          <Accordion.Panel>
            <List spacing={6}>
              <List.Item>Les colonnes sensibles (navire, patron, armateur…) sont repérées automatiquement.</List.Item>
              <List.Item>Avant tout export qui les contient, Moanui demande confirmation.</List.Item>
              <List.Item>L'étape « Anonymiser » remplace les identifiants par des codes (même navire = même code).</List.Item>
              <List.Item>Règle usuelle de diffusion : pas de résultat agrégé portant sur moins de 3 navires.</List.Item>
            </List>
          </Accordion.Panel>
        </Accordion.Item>
        <Accordion.Item value="graph">
          <Accordion.Control>5. Des graphiques honnêtes</Accordion.Control>
          <Accordion.Panel>
            <List spacing={6}>
              <List.Item>Toujours indiquer la source, l'unité et la période.</List.Item>
              <List.Item>Les barres commencent à zéro ; une échelle logarithmique se signale.</List.Item>
              <List.Item>Deux axes verticaux : à utiliser avec prudence, chaque axe doit être clairement légendé.</List.Item>
              <List.Item>Préférer les petits multiples à un graphique surchargé.</List.Item>
            </List>
          </Accordion.Panel>
        </Accordion.Item>
      </Accordion>
    </Paper>
  );
}
