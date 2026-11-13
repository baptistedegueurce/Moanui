import { useEffect, useState } from 'react';
import { Alert, Button, Checkbox, Group, Loader, Modal, Paper, Stack, Text } from '@mantine/core';
import { api } from '../lib/api';
import { fail, ok } from '../lib/notify';

interface Proposal {
  nom: string;
  description: string;
  steps: { type: string; params: any; why: string; description: string }[];
}

/** Applique un modèle de traitement : étapes proposées, cochables, ajoutées d'un coup (tout ou rien). */
export default function TemplateModal({ datasetId, templateId, onClose, onDone }: { datasetId: string; templateId: string | null; onClose: () => void; onDone: () => void }) {
  const [p, setP] = useState<Proposal | null>(null);
  const [sel, setSel] = useState<boolean[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    setP(null);
    setErr(null);
    if (!templateId) return;
    api
      .get<Proposal>(`/api/datasets/${datasetId}/templates/${templateId}`)
      .then((r) => {
        setP(r);
        setSel(r.steps.map(() => true));
      })
      .catch((e) => setErr(e.message));
  }, [datasetId, templateId]);

  const apply = async () => {
    if (!p) return;
    setBusy(true);
    try {
      const steps = p.steps.filter((_, i) => sel[i]).map((s) => ({ type: s.type, params: s.params, comment: `Modèle « ${p.nom} » : ${s.why}` }));
      await api.post(`/api/datasets/${datasetId}/steps/batch`, { steps });
      ok(`${steps.length} étape(s) ajoutée(s). Chacune reste modifiable.`);
      onDone();
      onClose();
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal opened={!!templateId} onClose={onClose} title={p?.nom || 'Modèle de traitement'} size="xl">
      {err && <Alert color="red">{err}</Alert>}
      {!p && !err && <Loader />}
      {p && (
        <Stack>
          <Text size="sm" c="dimmed">
            {p.description} Les étapes sont adaptées aux colonnes de ce jeu ; décochez celles qui ne conviennent pas.
          </Text>
          {p.steps.length === 0 && <Alert>Aucune colonne reconnue pour ce modèle (vérifiez les noms de colonnes).</Alert>}
          {p.steps.map((s, i) => (
            <Paper withBorder p="xs" key={i}>
              <Checkbox
                checked={sel[i]}
                onChange={(e) => {
                  const on = e.currentTarget.checked;
                  setSel((x) => x.map((v, j) => (j === i ? on : v)));
                }}
                label={<Text size="sm" fw={500}>{s.description}</Text>}
                description={s.why}
              />
            </Paper>
          ))}
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>
              Annuler
            </Button>
            <Button onClick={apply} loading={busy} disabled={!sel.some(Boolean)}>
              Ajouter {sel.filter(Boolean).length} étape(s)
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}
