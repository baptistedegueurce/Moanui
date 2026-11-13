import { useEffect, useState } from 'react';
import { Button, Card, Group, SimpleGrid, Stack, Text, Title, ThemeIcon } from '@mantine/core';
import { IconTable, IconChartBar, IconShieldCheck, IconFileText } from '@tabler/icons-react';
import { Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtDate, fmtNumber } from '../lib/format';
import type { DatasetSummary } from '../lib/types';

export default function HomePage() {
  const { me, structure } = useAuth();
  const [recent, setRecent] = useState<DatasetSummary[]>([]);
  useEffect(() => {
    api.get<DatasetSummary[]>('/api/datasets').then((d) => setRecent(d.slice(0, 6))).catch(() => {});
  }, [structure?.id]);

  const tile = (icon: React.ReactNode, title: string, text: string) => (
    <Card>
      <Group align="flex-start" wrap="nowrap">
        <ThemeIcon variant="light" size="lg">
          {icon}
        </ThemeIcon>
        <div>
          <Text fw={600}>{title}</Text>
          <Text size="sm" c="dimmed">
            {text}
          </Text>
        </div>
      </Group>
    </Card>
  );

  return (
    <Stack maw={1100}>
      <div>
        <Title order={2}>Bonjour {me?.display_name.split(' ')[0]}</Title>
        <Text c="dimmed">{structure?.name}</Text>
      </div>
      <SimpleGrid cols={{ base: 1, sm: 2, lg: 4 }}>
        {tile(<IconTable size={20} />, 'Importer et corriger', 'Mieux qu’un tableur : chaque correction est tracée et réversible.')}
        {tile(<IconShieldCheck size={20} />, 'Contrôler', 'Vides, aberrants, doublons, jointures risquées : détectés pour vous.')}
        {tile(<IconChartBar size={20} />, 'Représenter', 'Graphiques aux couleurs de la structure, avec logo, source et auteur.')}
        {tile(<IconFileText size={20} />, 'Documenter', 'Une fiche méthode Markdown accompagne chaque export.')}
      </SimpleGrid>
      <Group justify="space-between" mt="md">
        <Title order={4}>Jeux de données récents</Title>
        <Button component={Link} to="/donnees" variant="light">
          Tous les jeux
        </Button>
      </Group>
      {recent.length === 0 ? (
        <Card>
          <Text>
            Aucun jeu de données pour l’instant. Commencez par{' '}
            <Link to="/donnees">importer un fichier CSV ou Excel</Link>.
          </Text>
        </Card>
      ) : (
        <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }}>
          {recent.map((d) => (
            <Card key={d.id} component={Link} to={`/donnees/${d.id}`}>
              <Text fw={600} truncate>
                {d.name}
              </Text>
              <Text size="xs" c="dimmed" truncate>
                {d.source_name} · {fmtNumber(d.n_rows_raw)} lignes · {d.n_steps} étape(s)
              </Text>
              <Text size="xs" c="dimmed">
                Modifié le {fmtDate(d.updated_at)}
              </Text>
            </Card>
          ))}
        </SimpleGrid>
      )}
    </Stack>
  );
}
