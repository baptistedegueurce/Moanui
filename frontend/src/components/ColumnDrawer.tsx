import { useEffect, useState } from 'react';
import { Badge, Button, Checkbox, Divider, Drawer, Group, Progress, ScrollArea, Stack, Text, TextInput } from '@mantine/core';
import { IconFilter, IconFilterOff, IconReplace, IconTransform, IconPencil, IconTrash, IconSparkles } from '@tabler/icons-react';
import { api } from '../lib/api';
import { fmtNumber, typeLabel } from '../lib/format';
import type { Column } from '../lib/types';
import type { StepDraft } from './StepModal';

interface Vals {
  total: number;
  distinct: number;
  values: { valeur: any; n: number; part: number }[];
}

export default function ColumnDrawer({ datasetId, column, columns, canWrite, onClose, onStep }: {
  datasetId: string;
  column: string | null;
  columns: Column[];
  canWrite: boolean;
  onClose: () => void;
  onStep: (d: StepDraft) => void;
}) {
  const [vals, setVals] = useState<Vals | null>(null);
  const [search, setSearch] = useState('');
  const [sel, setSel] = useState<any[]>([]);
  const col = columns.find((c) => c.name === column);
  const key = (v: any) => (v === null ? '∅' : String(v));

  useEffect(() => {
    setSel([]);
    setSearch('');
  }, [column]);
  useEffect(() => {
    if (!column) return;
    const t = setTimeout(() => {
      api
        .get<Vals>(`/api/datasets/${datasetId}/values/${encodeURIComponent(column)}?limit=1000${search ? `&search=${encodeURIComponent(search)}` : ''}`)
        .then(setVals)
        .catch(() => setVals(null));
    }, 150);
    return () => clearTimeout(t);
  }, [datasetId, column, search]);

  const selSet = new Set(sel.map(key));
  const toggle = (v: any) => setSel((s) => (selSet.has(key(v)) ? s.filter((x) => key(x) !== key(v)) : [...s, v]));
  const go = (d: StepDraft) => {
    onStep(d);
    onClose();
  };

  return (
    <Drawer opened={!!column} onClose={onClose} position="right" size="md" title={<Text fw={700}>{column}</Text>}>
      {col && vals && (
        <Stack>
          <Group gap="xs">
            <Badge variant="light">{typeLabel(col.type)}</Badge>
            <Text size="sm" c="dimmed">
              {fmtNumber(vals.distinct)} valeur(s) distincte(s) sur {fmtNumber(vals.total)} lignes
            </Text>
          </Group>
          {canWrite && (
            <>
              <Text size="xs" c="dimmed">
                Actions sur toute la colonne (ajoutées à la recette, réversibles) :
              </Text>
              <Group gap={6}>
                <Button size="xs" variant="default" leftSection={<IconTransform size={14} />} onClick={() => go({ type: 'cast', params: { column } })}>
                  Changer le type
                </Button>
                <Button size="xs" variant="default" leftSection={<IconPencil size={14} />} onClick={() => go({ type: 'rename', params: { mapping: { [column!]: '' } } })}>
                  Renommer
                </Button>
                <Button size="xs" variant="default" leftSection={<IconSparkles size={14} />} onClick={() => go({ type: 'clean_text', params: { columns: [column], trim: true, empty_to_null: true, case: 'none' } })}>
                  Nettoyer
                </Button>
                <Button size="xs" variant="default" color="red" leftSection={<IconTrash size={14} />} onClick={() => go({ type: 'drop_columns', params: { columns: [column] } })}>
                  Supprimer
                </Button>
              </Group>
            </>
          )}
          <Divider label="Valeurs" labelPosition="left" />
          <TextInput size="xs" placeholder="Chercher…" value={search} onChange={(e) => setSearch(e.currentTarget.value)} />
          <ScrollArea h={380}>
            <Stack gap={4}>
              {vals.values.map((v) => (
                <Group key={key(v.valeur)} gap={6} wrap="nowrap">
                  {canWrite && <Checkbox size="xs" checked={selSet.has(key(v.valeur))} onChange={() => toggle(v.valeur)} />}
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <Group justify="space-between" gap={4} wrap="nowrap">
                      <Text size="sm" truncate c={v.valeur === null ? 'dimmed' : undefined}>
                        {v.valeur === null ? '(vide)' : String(v.valeur)}
                      </Text>
                      <Text size="xs" c="dimmed">
                        {fmtNumber(v.n)} · {(v.part * 100).toFixed(1)} %
                      </Text>
                    </Group>
                    <Progress value={v.part * 100} size="xs" />
                  </div>
                </Group>
              ))}
            </Stack>
          </ScrollArea>
          {canWrite && sel.length > 0 && (
            <Group gap={6}>
              <Button size="xs" leftSection={<IconFilter size={14} />} onClick={() => go({ type: 'filter', params: { keep: true, logic: 'and', conditions: [{ column, op: 'in', values: sel }] } })}>
                Garder ces {sel.length}
              </Button>
              <Button size="xs" color="orange" leftSection={<IconFilterOff size={14} />} onClick={() => go({ type: 'filter', params: { keep: false, logic: 'and', conditions: [{ column, op: 'in', values: sel }] } })}>
                Exclure
              </Button>
              <Button size="xs" variant="default" leftSection={<IconReplace size={14} />} onClick={() => go({ type: 'replace_values', params: { column, pairs: sel.map((s) => ({ from: s, to: '' })) } })}>
                Remplacer…
              </Button>
            </Group>
          )}
        </Stack>
      )}
    </Drawer>
  );
}
