import { Paper, Text, Title, List } from '@mantine/core';

const PLANS: Record<string, string[]> = {
  Cartographie: [
    'Couches importées (SHP, GeoJSON, GeoPackage) converties pour un affichage fluide',
    'Couches de contexte : rectangles CIEM, ZEE, eaux territoriales, 3 et 12 milles, AMP, Natura 2000, gisements',
    'VMS : harmonisation des formats (Agiltech, CLS…), carroyage, zones d’activité, suivi de zones',
    'Fond de carte hors ligne de secours',
  ],
  Statistiques: [
    'Assistant « quelle est ma question ? » qui oriente vers le bon test ou modèle',
    'Vérification automatique des conditions (normalité, variances, surdispersion, résidus) avec blocage contournable',
    'Tests, corrélations, régressions (LM, GLM, GLMM, GAM), séries temporelles, ACP, classification',
    'Aide à l’interprétation et fiche méthode Markdown générée',
    'Moteur R utilisé s’il est installé, sinon Python',
  ],
};

export default function SoonPage({ title }: { title: string }) {
  return (
    <Paper p="xl" withBorder maw={720}>
      <Title order={2}>{title}</Title>
      <Text c="dimmed" mb="md">
        Module prévu dans les prochaines étapes :
      </Text>
      <List spacing="xs">
        {(PLANS[title] || []).map((p) => (
          <List.Item key={p}>{p}</List.Item>
        ))}
      </List>
    </Paper>
  );
}
