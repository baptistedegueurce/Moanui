import { useEffect, useState } from 'react';
import { Button, Group, Stack, Table, Text, Title } from '@mantine/core';
import { IconUpload, IconChartBar, IconMap2, IconMathFunction } from '@tabler/icons-react';
import { Link, useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtDate, fmtNumber } from '../lib/format';
import type { DatasetSummary } from '../lib/types';
import ImportModal from '../components/ImportModal';

interface Item {
  id: string;
  name: string;
  dataset_id?: string;
  dataset?: string;
  at: string;
  who?: string;
}

function List({ title, items, href, empty }: { title: string; items: Item[]; href: (i: Item) => string; empty: string }) {
  return (
    <div className="mo-panel">
      <div className="mo-panel-head">{title}</div>
      {items.length === 0 ? (
        <Text size="sm" c="dimmed" p="sm">
          {empty}
        </Text>
      ) : (
        items.map((i) => (
          <Link key={i.id} to={href(i)} className="mo-list-row">
            <span className="mo-list-main">
              <span className="mo-list-name">{i.name}</span>
              {i.dataset && <span className="mo-list-sub">{i.dataset}</span>}
            </span>
            <span className="mo-list-date">{fmtDate(i.at)}</span>
          </Link>
        ))
      )}
    </div>
  );
}

export default function HomePage() {
  const { me, structure, canWrite } = useAuth();
  const nav = useNavigate();
  const [datasets, setDatasets] = useState<DatasetSummary[]>([]);
  const [recent, setRecent] = useState<{ graphiques: Item[]; analyses: Item[]; cartes: Item[] }>({ graphiques: [], analyses: [], cartes: [] });
  const [importing, setImporting] = useState(false);
  useEffect(() => {
    api.get<DatasetSummary[]>('/api/datasets').then(setDatasets).catch(() => {});
    api.get('/api/recent').then(setRecent).catch(() => {});
  }, [structure?.id]);

  const sorted = [...datasets].sort((a, b) => (b.updated_at || '').localeCompare(a.updated_at || '')).slice(0, 8);

  return (
    <Stack maw={1180} gap="lg">
      <div className="mo-page-head">
        <div>
          <div className="mo-page-eyebrow">{structure?.name}</div>
          <Title order={1}>Tableau de bord</Title>
          <Text c="dimmed" size="sm" mt={4}>
            {datasets.length} jeu{datasets.length > 1 ? 'x' : ''} de données · connecté en tant que {me?.display_name}
          </Text>
        </div>
        <Group gap="xs">
          {canWrite && (
            <Button leftSection={<IconUpload size={16} />} onClick={() => setImporting(true)}>
              Importer un fichier
            </Button>
          )}
          <Button variant="default" leftSection={<IconChartBar size={16} />} onClick={() => nav('/graphiques')}>
            Graphique
          </Button>
          <Button variant="default" leftSection={<IconMap2 size={16} />} onClick={() => nav('/cartographie')}>
            Carte
          </Button>
          <Button variant="default" leftSection={<IconMathFunction size={16} />} onClick={() => nav('/statistiques')}>
            Statistiques
          </Button>
        </Group>
      </div>

      <div className="mo-panel">
        <Group className="mo-panel-head" justify="space-between">
          <span>Derniers jeux de données</span>
          <Link to="/donnees" className="mo-link">
            Tous les jeux
          </Link>
        </Group>
        {sorted.length === 0 ? (
          <Text size="sm" p="md">
            Aucun jeu de données pour l’instant. Importez un fichier CSV ou Excel (SACROIS, journal de bord, VMS…) : il est conservé tel quel, et chaque
            correction est enregistrée comme une étape réversible.
          </Text>
        ) : (
          <Table highlightOnHover verticalSpacing={7} className="mo-table">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Nom</Table.Th>
                <Table.Th>Fichier</Table.Th>
                <Table.Th ta="right">Lignes</Table.Th>
                <Table.Th ta="right">Opérations</Table.Th>
                <Table.Th>Modifié</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {sorted.map((d) => (
                <Table.Tr key={d.id} style={{ cursor: 'pointer' }} onClick={() => nav(`/donnees/${d.id}`)}>
                  <Table.Td fw={600}>{d.name}</Table.Td>
                  <Table.Td c="dimmed">{d.source_name}</Table.Td>
                  <Table.Td ta="right" className="mo-num">
                    {fmtNumber(d.n_rows_raw)}
                  </Table.Td>
                  <Table.Td ta="right" className="mo-num">
                    {d.n_steps}
                  </Table.Td>
                  <Table.Td c="dimmed">{fmtDate(d.updated_at)}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </div>

      <div className="mo-home-grid">
        <List title="Graphiques" items={recent.graphiques} href={(i) => `/graphiques?dataset=${i.dataset_id}&chart=${i.id}`} empty="Aucun graphique enregistré." />
        <List title="Analyses statistiques" items={recent.analyses} href={(i) => `/statistiques?dataset=${i.dataset_id}`} empty="Aucune analyse enregistrée." />
        <List title="Cartes" items={recent.cartes} href={(i) => `/cartographie?map=${i.id}`} empty="Aucune carte enregistrée." />
      </div>
      <ImportModal opened={importing} onClose={() => setImporting(false)} onDone={(id) => nav(`/donnees/${id}`)} />
    </Stack>
  );
}
