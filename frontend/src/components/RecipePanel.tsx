import { ActionIcon, Badge, Group, Stack, Switch, Text, Tooltip } from '@mantine/core';
import { IconTrash, IconPencil, IconArrowUp, IconArrowDown, IconEye } from '@tabler/icons-react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtDate, fmtNumber } from '../lib/format';
import { fail } from '../lib/notify';
import type { Step } from '../lib/types';
import type { StepDraft } from './StepModal';

/** Historique des opérations (recette) : chaque étape peut être vue, désactivée, modifiée, déplacée ou supprimée. */
export default function RecipePanel({ datasetId, steps, canWrite, onAdd, onChanged, viewUpto, setViewUpto }: {
  datasetId: string;
  steps: Step[];
  canWrite: boolean;
  onAdd: (d: StepDraft) => void;
  onChanged: () => void;
  viewUpto: number | null;
  setViewUpto: (n: number | null) => void;
}) {
  const { meta } = useAuth();
  const label = (t: string) => meta?.steps.find((s) => s.type === t)?.label || t;
  const real = steps.filter((s) => s.id);

  const act = async (fn: () => Promise<any>) => {
    try {
      await fn();
      onChanged();
    } catch (e) {
      fail(e);
    }
  };

  const move = (id: string, dir: -1 | 1) => {
    const ids = real.map((s) => s.id!);
    const i = ids.indexOf(id);
    const j = i + dir;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    act(() => api.post(`/api/datasets/${datasetId}/steps/reorder`, { order: ids }));
  };

  return (
    <Stack gap="xs">
        <Stack gap={6}>
          {steps.map((s) => {
            const active = viewUpto !== null ? s.index === viewUpto : false;
            return (
              <div className="mo-step" data-status={s.status} data-active={active} key={s.id || 'brut'}>
                <Group justify="space-between" wrap="nowrap" gap={4}>
                  <Group gap={6} wrap="nowrap">
                    <Badge size="sm" variant="light" circle>
                      {s.index}
                    </Badge>
                    <Text size="xs" fw={600}>
                      {s.id ? label(s.type || '') : 'Fichier d’origine (intact)'}
                    </Text>
                  </Group>
                  {s.n_rows !== undefined && (
                    <Text size="xs" c="dimmed">
                      {fmtNumber(s.n_rows)} l.
                    </Text>
                  )}
                </Group>
                {s.id && (
                  <Text size="xs" mt={4}>
                    {s.description}
                  </Text>
                )}
                {s.comment && (
                  <Text size="xs" c="dimmed" fs="italic" mt={2}>
                    « {s.comment} »
                  </Text>
                )}
                {s.error && (
                  <Text size="xs" c="red" mt={2}>
                    {s.error}
                  </Text>
                )}
                {s.id && (
                  <Group justify="space-between" mt={4} gap={2}>
                    <Text size="10px" c="dimmed">
                      {s.author} · {fmtDate(s.at)}
                    </Text>
                    <Group gap={0}>
                      <Tooltip label="Voir les données à cette étape">
                        <ActionIcon size="sm" aria-label="Voir les données à cette étape" variant={active ? 'filled' : 'subtle'} onClick={() => setViewUpto(active ? null : s.index)}>
                          <IconEye size={14} />
                        </ActionIcon>
                      </Tooltip>
                      {canWrite && (
                        <>
                          <Tooltip label={s.enabled === false ? 'Réactiver' : 'Désactiver (garder pour mémoire)'}>
                            <Switch
                              size="xs"
                              mx={4}
                              checked={s.enabled !== false}
                              onChange={(e) => {
                                const enabled = e.currentTarget.checked;
                                act(() => api.patch(`/api/datasets/${datasetId}/steps/${s.id}`, { enabled }));
                              }}
                            />
                          </Tooltip>
                          {s.type !== 'edit_cells' && (
                            <ActionIcon size="sm" variant="subtle" aria-label="Modifier l’étape" onClick={() => onAdd({ type: s.type!, params: s.params, editId: s.id!, comment: s.comment })}>
                              <IconPencil size={14} />
                            </ActionIcon>
                          )}
                          <ActionIcon size="sm" variant="subtle" aria-label="Monter" onClick={() => move(s.id!, -1)}>
                            <IconArrowUp size={14} />
                          </ActionIcon>
                          <ActionIcon size="sm" variant="subtle" aria-label="Descendre" onClick={() => move(s.id!, 1)}>
                            <IconArrowDown size={14} />
                          </ActionIcon>
                          <ActionIcon
                            size="sm"
                            variant="subtle"
                            color="red"
                            aria-label="Supprimer l’étape"
                            onClick={() => {
                              if (confirm('Supprimer cette étape ? (elle restera visible dans le journal)')) act(() => api.del(`/api/datasets/${datasetId}/steps/${s.id}`));
                            }}
                          >
                            <IconTrash size={14} />
                          </ActionIcon>
                        </>
                      )}
                    </Group>
                  </Group>
                )}
              </div>
            );
          })}
          {real.length === 0 && (
            <Text size="xs" c="dimmed">
              Aucune opération : la donnée est telle qu’importée.
            </Text>
          )}
        </Stack>
    </Stack>
  );
}
