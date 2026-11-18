import { useEffect, useState } from 'react';
import { Badge, Button, Card, Group, Stack, Table, Text, TextInput, Title } from '@mantine/core';
import { IconUpload, IconSearch } from '@tabler/icons-react';
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtDate, fmtNumber } from '../lib/format';
import { fail } from '../lib/notify';
import type { DatasetSummary } from '../lib/types';
import ImportModal from '../components/ImportModal';

const KIND_LABEL: Record<string, string> = {
  generique: 'Générique',
  sacrois: 'SACROIS',
  logbook: 'Marées',
  vms: 'VMS',
  referentiel: 'Référentiel',
  quotas: 'Quotas',
};

export default function DatasetsPage() {
  const { structure, canWrite } = useAuth();
  const nav = useNavigate();
  const [list, setList] = useState<DatasetSummary[]>([]);
  const [q, setQ] = useState('');
  const [importing, setImporting] = useState(false);

  const load = () => api.get<DatasetSummary[]>('/api/datasets').then(setList).catch(fail);
  useEffect(() => {
    load();
  }, [structure?.id]);

  const shown = list.filter((d) => (d.name + d.source_name + d.description).toLowerCase().includes(q.toLowerCase()));

  return (
    <Stack maw={1200}>
      <Group justify="space-between">
        <Title order={1}>Données</Title>
        {canWrite && (
          <Button leftSection={<IconUpload size={16} />} onClick={() => setImporting(true)}>
            Importer un fichier
          </Button>
        )}
      </Group>
      <TextInput leftSection={<IconSearch size={16} />} placeholder="Rechercher…" value={q} onChange={(e) => setQ(e.currentTarget.value)} maw={360} />
      <Card p={0}>
        <Table highlightOnHover verticalSpacing="sm" className="mo-table">
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Nom</Table.Th>
              <Table.Th>Nature</Table.Th>
              <Table.Th>Fichier source</Table.Th>
              <Table.Th ta="right">Lignes (brut)</Table.Th>
              <Table.Th ta="right">Opérations</Table.Th>
              <Table.Th>Modifié</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {shown.map((d) => (
              <Table.Tr key={d.id} style={{ cursor: 'pointer' }} onClick={() => nav(`/donnees/${d.id}`)}>
                <Table.Td>
                  <Text fw={600}>{d.name}</Text>
                  {d.description && (
                    <Text size="xs" c="dimmed" lineClamp={1}>
                      {d.description}
                    </Text>
                  )}
                </Table.Td>
                <Table.Td>
                  <Group gap={4}>
                    <Badge variant="light">{KIND_LABEL[d.kind] || d.kind}</Badge>
                    {d.shared_from_other && (
                      <Badge variant="outline" color="grape">
                        partagé par {d.structure_name}
                      </Badge>
                    )}
                  </Group>
                </Table.Td>
                <Table.Td>
                  <Text size="sm">{d.source_name}</Text>
                </Table.Td>
                <Table.Td ta="right">{fmtNumber(d.n_rows_raw)}</Table.Td>
                <Table.Td ta="right">{d.n_steps}</Table.Td>
                <Table.Td>
                  <Text size="sm">{fmtDate(d.updated_at)}</Text>
                </Table.Td>
              </Table.Tr>
            ))}
            {shown.length === 0 && (
              <Table.Tr>
                <Table.Td colSpan={6}>
                  <Text c="dimmed" ta="center" p="lg">
                    Aucun jeu de données.
                  </Text>
                </Table.Td>
              </Table.Tr>
            )}
          </Table.Tbody>
        </Table>
      </Card>
      <ImportModal opened={importing} onClose={() => setImporting(false)} onDone={(id) => nav(`/donnees/${id}`)} />
    </Stack>
  );
}
