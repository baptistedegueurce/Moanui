import { useEffect, useState } from 'react';
import { Alert, Badge, Button, Group, Modal, ScrollArea, Stack, Table, Text, Textarea } from '@mantine/core';
import { IconAlertTriangle, IconInfoCircle, IconCheck } from '@tabler/icons-react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtNumber } from '../lib/format';
import { fail, ok } from '../lib/notify';
import type { Column, Warning } from '../lib/types';
import StepForm, { DEFAULT_PARAMS } from './StepForm';

export interface StepDraft {
  type: string;
  params?: any;
  editId?: string; // modification d'une étape existante
  comment?: string;
  position?: number;
}

interface Check {
  ok: boolean;
  error?: string;
  description?: string;
  diagnostics?: Warning[];
  n_before?: number;
  n_after?: number;
  preview?: { columns: Column[]; rows: any[][] };
}

const COLOR: Record<string, string> = { info: 'blue', attention: 'orange', alerte: 'red' };

export default function StepModal({ draft, onClose, onSaved, datasetId, columns }: {
  draft: StepDraft | null;
  onClose: () => void;
  onSaved: () => void;
  datasetId: string;
  columns: Column[];
}) {
  const { meta } = useAuth();
  const [params, setParams] = useState<any>({});
  const [comment, setComment] = useState('');
  const [check, setCheck] = useState<Check | null>(null);
  const [checking, setChecking] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (draft) {
      setParams(draft.params ?? structuredClone(DEFAULT_PARAMS[draft.type] || {}));
      setComment(draft.comment || '');
      setCheck(null);
    }
  }, [draft]);

  // vérification automatique (aperçu) après chaque modification
  useEffect(() => {
    if (!draft || draft.editId) return;
    const t = setTimeout(async () => {
      setChecking(true);
      try {
        setCheck(await api.post(`/api/datasets/${datasetId}/steps/check`, { type: draft.type, params, position: draft.position }));
      } catch (e: any) {
        setCheck({ ok: false, error: e.message });
      } finally {
        setChecking(false);
      }
    }, 600);
    return () => clearTimeout(t);
  }, [params, draft, datasetId]);

  if (!draft) return null;
  const label = meta?.steps.find((s) => s.type === draft.type)?.label || draft.type;

  const save = async () => {
    setSaving(true);
    try {
      if (draft.editId) {
        await api.patch(`/api/datasets/${datasetId}/steps/${draft.editId}`, { params, comment });
      } else {
        const r = await api.post(`/api/datasets/${datasetId}/steps`, { type: draft.type, params, comment, position: draft.position });
        if (r.downstream_error) fail({ message: `Une étape suivante ne s’applique plus : ${r.downstream_error.message}` }, 'Attention');
      }
      ok('Étape enregistrée');
      onSaved();
      onClose();
    } catch (e) {
      fail(e);
    } finally {
      setSaving(false);
    }
  };

  const delta = check?.ok && check.n_before !== undefined ? (check.n_after || 0) - check.n_before : 0;

  return (
    <Modal opened onClose={onClose} title={<Text fw={600}>{draft.editId ? 'Modifier' : 'Ajouter'} : {label}</Text>} size="xl">
      <Stack>
        <StepForm type={draft.type} params={params} set={setParams} columns={columns} datasetId={datasetId} />
        <Textarea
          label="Justification (reprise dans la fiche méthode)"
          placeholder="Pourquoi cette étape ? Ex. : engins mal codés d’après l’échange avec la DML du 12/03"
          autosize
          minRows={2}
          value={comment}
          onChange={(e) => setComment(e.currentTarget.value)}
        />
        {!draft.editId && (
          <div>
            {checking && <Text size="sm" c="dimmed">Vérification…</Text>}
            {check && !check.ok && (
              <Alert color="red" icon={<IconAlertTriangle />}>
                {check.error}
              </Alert>
            )}
            {check?.ok && (
              <Stack gap="xs">
                <Alert color="teal" icon={<IconCheck />}>
                  <Text size="sm">{check.description}</Text>
                  <Text size="sm" mt={4}>
                    Lignes : {fmtNumber(check.n_before)} → <b>{fmtNumber(check.n_after)}</b>
                    {delta !== 0 && (
                      <Badge ml={6} color={delta < 0 ? 'orange' : 'blue'} variant="light">
                        {delta > 0 ? '+' : ''}
                        {fmtNumber(delta)}
                      </Badge>
                    )}
                  </Text>
                </Alert>
                {check.diagnostics?.map((d, i) => (
                  <Alert key={i} color={COLOR[d.niveau]} icon={d.niveau === 'info' ? <IconInfoCircle /> : <IconAlertTriangle />} p="xs">
                    <Text size="sm">{d.message}</Text>
                  </Alert>
                ))}
                {check.preview && (
                  <ScrollArea h={200} type="auto">
                    <Table fz="xs" striped withTableBorder>
                      <Table.Thead>
                        <Table.Tr>
                          {check.preview.columns.map((c) => (
                            <Table.Th key={c.name} style={{ whiteSpace: 'nowrap' }}>
                              {c.name === '__ligne' ? 'n°' : c.name}
                            </Table.Th>
                          ))}
                        </Table.Tr>
                      </Table.Thead>
                      <Table.Tbody>
                        {check.preview.rows.map((r, i) => (
                          <Table.Tr key={i}>
                            {r.map((v, j) => (
                              <Table.Td key={j} style={{ whiteSpace: 'nowrap' }}>
                                {v === null ? <Text span c="dimmed" size="xs">vide</Text> : typeof v === 'number' ? fmtNumber(v) : String(v)}
                              </Table.Td>
                            ))}
                          </Table.Tr>
                        ))}
                      </Table.Tbody>
                    </Table>
                  </ScrollArea>
                )}
              </Stack>
            )}
          </div>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Annuler
          </Button>
          <Button onClick={save} loading={saving} disabled={!draft.editId && !check?.ok}>
            {draft.editId ? 'Enregistrer' : 'Ajouter à la recette'}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
