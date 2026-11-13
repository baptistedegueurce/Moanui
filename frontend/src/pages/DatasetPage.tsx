import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  Alert,
  Badge,
  Button,
  Card,
  Group,
  Menu,
  Modal,
  Paper,
  SegmentedControl,
  Select,
  Stack,
  Switch,
  Table,
  Tabs,
  Text,
  TextInput,
  Textarea,
  Title,
  Loader,
  Center,
} from '@mantine/core';
import {
  IconDownload,
  IconFileText,
  IconCopy,
  IconShare,
  IconChartBar,
  IconShieldCheck,
  IconSearch,
  IconDeviceFloppy,
  IconX,
  IconDots,
  IconTrash,
  IconFingerprint,
  IconAlertTriangle,
  IconMathFunction,
} from '@tabler/icons-react';
import { api, download, saveText } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtDate, fmtNumber, fmtSize, typeLabel } from '../lib/format';
import { fail, ok } from '../lib/notify';
import type { Dataset, Warning } from '../lib/types';
import DataGrid, { GridHandle, PendingEdit } from '../components/DataGrid';
import RecipePanel from '../components/RecipePanel';
import StepModal, { StepDraft } from '../components/StepModal';
import ColumnDrawer from '../components/ColumnDrawer';
import Markdown from '../components/Markdown';
import TemplateModal from '../components/TemplateModal';

const LEVEL_COLOR: Record<string, string> = { info: 'blue', attention: 'orange', alerte: 'red' };

function QualityTab({ id }: { id: string }) {
  const [p, setP] = useState<any>(null);
  useEffect(() => {
    api.get(`/api/datasets/${id}/profile`).then(setP).catch(fail);
  }, [id]);
  if (!p) return <Loader />;
  return (
    <Stack>
      <Text size="sm" c="dimmed">
        Contrôles calculés sur le résultat de la recette ({fmtNumber(p.n_rows)} lignes). Ce sont des signaux à vérifier, pas forcément des erreurs.
      </Text>
      {p.warnings.length === 0 ? (
        <Alert color="teal">Aucune anomalie détectée par les contrôles automatiques.</Alert>
      ) : (
        p.warnings.map((w: Warning, i: number) => (
          <Alert key={i} color={LEVEL_COLOR[w.niveau]} p="xs" icon={<IconAlertTriangle size={18} />}>
            <Text size="sm">
              {w.colonne && <b>{w.colonne} : </b>}
              {w.message}
            </Text>
          </Alert>
        ))
      )}
      <Card p={0}>
        <Table fz="sm" striped>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Colonne</Table.Th>
              <Table.Th>Type</Table.Th>
              <Table.Th ta="right">Vides</Table.Th>
              <Table.Th ta="right">Distinctes</Table.Th>
              <Table.Th>Min</Table.Th>
              <Table.Th>Max</Table.Th>
              <Table.Th ta="right">Moyenne</Table.Th>
              <Table.Th ta="right">Médiane</Table.Th>
              <Table.Th>Valeurs les plus fréquentes</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {p.columns.map((c: any) => (
              <Table.Tr key={c.name}>
                <Table.Td fw={600}>{c.name}</Table.Td>
                <Table.Td>{typeLabel(c.type)}</Table.Td>
                <Table.Td ta="right" c={c.vides ? 'orange' : undefined}>
                  {fmtNumber(c.vides)}
                </Table.Td>
                <Table.Td ta="right">{fmtNumber(c.distinctes)}</Table.Td>
                <Table.Td>{fmtNumber(c.min)}</Table.Td>
                <Table.Td>{fmtNumber(c.max)}</Table.Td>
                <Table.Td ta="right">{fmtNumber(c.moyenne)}</Table.Td>
                <Table.Td ta="right">{fmtNumber(c.mediane)}</Table.Td>
                <Table.Td>
                  <Text size="xs" c="dimmed" lineClamp={1}>
                    {c.top.map((t: any) => `${t.valeur ?? '(vide)'} (${t.n})`).join(', ')}
                  </Text>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Card>
    </Stack>
  );
}

function ExportModal({ ds, opened, onClose }: { ds: Dataset; opened: boolean; onClose: () => void }) {
  const [fmt, setFmt] = useState('csv');
  const [rowId, setRowId] = useState(false);
  const [sensitive, setSensitive] = useState<any[] | null>(null);
  const [busy, setBusy] = useState(false);
  const run = async (confirm = false) => {
    setBusy(true);
    try {
      await download(`/api/datasets/${ds.id}/export?fmt=${fmt}&include_row_id=${rowId}&confirm_sensitive=${confirm}`);
      ok('Export prêt : données + fiche méthode dans le ZIP.');
      setSensitive(null);
      onClose();
    } catch (e: any) {
      if (e.status === 409 && e.detail?.code === 'donnees_sensibles') setSensitive(e.detail.columns);
      else fail(e);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Modal opened={opened} onClose={onClose} title="Exporter le résultat">
      <Stack>
        <Text size="sm" c="dimmed">
          L’export contient le résultat de la recette (jamais le brut modifié) et sa fiche méthode Markdown.
        </Text>
        <SegmentedControl
          value={fmt}
          onChange={setFmt}
          data={[
            { value: 'csv', label: 'CSV (Excel FR)' },
            { value: 'xlsx', label: 'Excel' },
            { value: 'parquet', label: 'Parquet (R/Python)' },
          ]}
        />
        <Switch label="Inclure le numéro de ligne d’origine (traçabilité)" checked={rowId} onChange={(e) => setRowId(e.currentTarget.checked)} />
        {sensitive && (
          <Alert color="grape" title="Données sensibles">
            <Text size="sm">Ces colonnes ne sont pas anonymisées : {sensitive.map((s) => `${s.column} (${s.kind})`).join(', ')}.</Text>
            <Text size="sm" mt={4}>
              Vous pouvez exporter pour un usage interne ; pour une diffusion, ajoutez plutôt une étape « Anonymiser ».
            </Text>
            <Button mt="sm" color="grape" size="xs" onClick={() => run(true)} loading={busy}>
              J’ai compris, exporter quand même
            </Button>
          </Alert>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Annuler
          </Button>
          <Button leftSection={<IconDownload size={16} />} onClick={() => run(false)} loading={busy}>
            Exporter
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

function ShareModal({ ds, opened, onClose, onDone }: { ds: Dataset; opened: boolean; onClose: () => void; onDone: () => void }) {
  const [structures, setStructures] = useState<{ id: string; name: string }[]>([]);
  const [sel, setSel] = useState<string | null>(null);
  useEffect(() => {
    if (opened) api.get('/api/structures').then(setStructures).catch(fail);
  }, [opened]);
  const shared = new Set(ds.shares.map((s) => s.structure_id));
  return (
    <Modal opened={opened} onClose={onClose} title="Partager avec une autre structure">
      <Stack>
        <Text size="sm" c="dimmed">
          La structure invitée voit ce jeu en lecture seule (elle peut en faire une copie de travail). Le partage se retire à tout moment.
        </Text>
        {ds.shares.map((s) => (
          <Group key={s.structure_id} justify="space-between">
            <Text size="sm">{s.name}</Text>
            <Button size="xs" variant="subtle" color="red" onClick={() => api.del(`/api/datasets/${ds.id}/shares/${s.structure_id}`).then(onDone).catch(fail)}>
              Retirer
            </Button>
          </Group>
        ))}
        <Group align="flex-end">
          <Select
            style={{ flex: 1 }}
            label="Structure"
            data={structures.filter((s) => s.id !== ds.structure_id && !shared.has(s.id)).map((s) => ({ value: s.id, label: s.name }))}
            value={sel}
            onChange={setSel}
          />
          <Button disabled={!sel} onClick={() => api.post(`/api/datasets/${ds.id}/shares`, { structure_id: sel }).then(() => { setSel(null); onDone(); }).catch(fail)}>
            Partager
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

export default function DatasetPage() {
  const { id } = useParams<{ id: string }>();
  const nav = useNavigate();
  const { isStructureAdmin } = useAuth();
  const [ds, setDs] = useState<Dataset | null>(null);
  const [tab, setTab] = useState<string | null>('donnees');
  const [search, setSearch] = useState('');
  const [debounced, setDebounced] = useState('');
  const [total, setTotal] = useState(0);
  const [pending, setPending] = useState<PendingEdit[]>([]);
  const [editComment, setEditComment] = useState('');
  const [draft, setDraft] = useState<StepDraft | null>(null);
  const [template, setTemplate] = useState<string | null>(null);
  const [colOpen, setColOpen] = useState<string | null>(null);
  const [exportOpen, setExportOpen] = useState(false);
  const [shareOpen, setShareOpen] = useState(false);
  const [method, setMethod] = useState<string>('');
  const [notes, setNotes] = useState('');
  const [viewUpto, setViewUpto] = useState<number | null>(null);
  const [viewCols, setViewCols] = useState<Dataset['schema'] | null>(null);
  const grid = useRef<GridHandle>(null);

  const load = useCallback(async () => {
    try {
      const d = await api.get<Dataset>(`/api/datasets/${id}`);
      setDs(d);
      setNotes(d.notes);
    } catch (e) {
      fail(e);
      nav('/donnees');
    }
  }, [id, nav]);

  useEffect(() => {
    load();
  }, [load]);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 350);
    return () => clearTimeout(t);
  }, [search]);
  useEffect(() => {
    grid.current?.refresh();
  }, [debounced]);
  useEffect(() => {
    // aperçu des données à une étape donnée : les colonnes peuvent différer du résultat final
    if (viewUpto === null || !id) return setViewCols(null);
    api
      .post(`/api/datasets/${id}/rows`, { limit: 1, upto: viewUpto })
      .then((r) => setViewCols(r.columns))
      .catch(fail);
  }, [viewUpto, id]);
  useEffect(() => {
    if (tab === 'methode' && id) api.get<string>(`/api/datasets/${id}/method.md`).then(setMethod).catch(fail);
  }, [tab, id, ds]);

  if (!ds)
    return (
      <Center h={300}>
        <Loader />
      </Center>
    );

  const canWrite = ds.mode === 'ecriture';
  const columns = viewUpto !== null ? viewCols : ds.schema;

  const changed = async () => {
    await load();
    grid.current?.refresh();
  };

  const saveEdits = async () => {
    if (!editComment.trim()) return fail({ message: 'Indiquez brièvement pourquoi ces corrections (source, échange, évidence…).' }, 'Justification requise');
    try {
      await api.post(`/api/datasets/${ds.id}/steps`, { type: 'edit_cells', params: { edits: pending }, comment: editComment });
      ok(`${pending.length} correction(s) enregistrée(s) dans la recette.`);
      setPending([]);
      setEditComment('');
      await changed();
    } catch (e) {
      fail(e);
    }
  };

  return (
    <Stack h="calc(100vh - 88px)" gap="sm">
      <Group justify="space-between" wrap="nowrap">
        <div style={{ minWidth: 0 }}>
          <Group gap="xs">
            <Title order={3} lineClamp={1}>
              {ds.name}
            </Title>
            {!canWrite && <Badge color="gray">lecture seule</Badge>}
            {ds.shared_from_other && <Badge color="grape">partagé par {ds.structure_name}</Badge>}
          </Group>
          <Text size="xs" c="dimmed">
            {ds.raw.name} · {fmtNumber(ds.raw.n_rows)} lignes brutes · {fmtSize(ds.raw.size_bytes)} · importé le {fmtDate(ds.raw.imported_at)} par {ds.created_by}
          </Text>
        </div>
        <Group gap="xs" wrap="nowrap">
          <Button variant="light" leftSection={<IconChartBar size={16} />} onClick={() => nav(`/graphiques?dataset=${ds.id}`)}>
            Graphique
          </Button>
          <Button variant="light" leftSection={<IconMathFunction size={16} />} onClick={() => nav(`/statistiques?dataset=${ds.id}`)}>
            Statistiques
          </Button>
          <Button leftSection={<IconDownload size={16} />} onClick={() => setExportOpen(true)}>
            Exporter
          </Button>
          <Menu position="bottom-end" withinPortal>
            <Menu.Target>
              <Button variant="default" px="xs">
                <IconDots size={18} />
              </Button>
            </Menu.Target>
            <Menu.Dropdown>
              <Menu.Item leftSection={<IconFileText size={16} />} onClick={() => api.get<string>(`/api/datasets/${ds.id}/method.md`).then((t) => saveText(t, `${ds.name}_methode.md`)).catch(fail)}>
                Télécharger la fiche méthode
              </Menu.Item>
              <Menu.Item leftSection={<IconCopy size={16} />} onClick={() => api.post(`/api/datasets/${ds.id}/duplicate`).then((r) => nav(`/donnees/${r.id}`)).catch(fail)}>
                Faire une copie de travail
              </Menu.Item>
              <Menu.Item
                leftSection={<IconFingerprint size={16} />}
                onClick={() =>
                  api
                    .get(`/api/datasets/${ds.id}/integrity`)
                    .then((r) => (r.ok ? ok(r.message, 'Intégrité') : fail({ message: r.message })))
                    .catch(fail)
                }
              >
                Vérifier l’intégrité du brut
              </Menu.Item>
              {isStructureAdmin && canWrite && (
                <Menu.Item leftSection={<IconShare size={16} />} onClick={() => setShareOpen(true)}>
                  Partager…
                </Menu.Item>
              )}
              {canWrite && (
                <Menu.Item
                  color="red"
                  leftSection={<IconTrash size={16} />}
                  onClick={() => {
                    if (confirm('Supprimer ce jeu de données ? Le fichier brut reste conservé.'))
                      api.del(`/api/datasets/${ds.id}`).then(() => nav('/donnees')).catch(fail);
                  }}
                >
                  Supprimer le jeu
                </Menu.Item>
              )}
            </Menu.Dropdown>
          </Menu>
        </Group>
      </Group>

      {ds.error && (
        <Alert color="red" p="xs">
          L’étape {ds.error.index} ne s’applique plus : {ds.error.message} Les étapes suivantes sont suspendues.
        </Alert>
      )}

      <Tabs value={tab} onChange={setTab} keepMounted={false} style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <Tabs.List>
          <Tabs.Tab value="donnees">Données</Tabs.Tab>
          <Tabs.Tab value="qualite" leftSection={<IconShieldCheck size={14} />}>
            Contrôle qualité
          </Tabs.Tab>
          <Tabs.Tab value="import">Import</Tabs.Tab>
          <Tabs.Tab value="methode" leftSection={<IconFileText size={14} />}>
            Fiche méthode & notes
          </Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="donnees" pt="sm" style={{ flex: 1, minHeight: 0 }}>
          <div style={{ display: 'flex', gap: 12, height: '100%' }}>
            <Stack gap={6} style={{ flex: 1, minWidth: 0 }}>
              <Group justify="space-between">
                <TextInput size="xs" w={280} leftSection={<IconSearch size={14} />} placeholder="Rechercher dans toutes les colonnes" value={search} onChange={(e) => setSearch(e.currentTarget.value)} />
                <Text size="xs" c="dimmed">
                  {viewUpto !== null && (
                    <Badge mr={6} color="blue" variant="light" rightSection={<IconX size={10} style={{ cursor: 'pointer' }} onClick={() => setViewUpto(null)} />}>
                      Aperçu à l’étape {viewUpto}
                    </Badge>
                  )}
                  {fmtNumber(total)} lignes · {ds.schema.filter((c) => !c.name.startsWith('__')).length} colonnes
                  {canWrite && ' · double-clic sur une cellule pour corriger'}
                </Text>
              </Group>
              {pending.length > 0 && (
                <Paper withBorder p="xs" style={{ background: 'var(--mantine-color-yellow-0)' }}>
                  <Group gap="xs" wrap="nowrap">
                    <Text size="sm" fw={600} style={{ whiteSpace: 'nowrap' }}>
                      {pending.length} correction(s) en attente
                    </Text>
                    <TextInput size="xs" style={{ flex: 1 }} placeholder="Justification (obligatoire) : ex. erreur de saisie confirmée par le patron" value={editComment} onChange={(e) => setEditComment(e.currentTarget.value)} />
                    <Button size="xs" leftSection={<IconDeviceFloppy size={14} />} onClick={saveEdits}>
                      Enregistrer
                    </Button>
                    <Button
                      size="xs"
                      variant="default"
                      onClick={() => {
                        setPending([]);
                        grid.current?.refresh();
                      }}
                    >
                      Annuler
                    </Button>
                  </Group>
                </Paper>
              )}
              <div style={{ flex: 1, minHeight: 0 }}>
                {columns && (
                <DataGrid
                  key={columns.map((c) => c.name).join('|') + (viewUpto ?? '') + ds.steps.length}
                  ref={grid}
                  datasetId={ds.id}
                  columns={columns}
                  search={debounced}
                  filters={[]}
                  editable={canWrite && viewUpto === null}
                  pending={pending}
                  onEdit={(e) => setPending((p) => [...p.filter((x) => !(x.row === e.row && x.column === e.column)), e])}
                  onHeaderClick={setColOpen}
                  onTotal={setTotal}
                  upto={viewUpto}
                />
                )}
              </div>
            </Stack>
            <Paper withBorder p="sm" w={340} style={{ flexShrink: 0, background: 'var(--mo-bg)' }}>
              <RecipePanel datasetId={ds.id} steps={ds.steps} canWrite={canWrite} onAdd={setDraft} onChanged={changed} viewUpto={viewUpto} setViewUpto={setViewUpto} onTemplate={setTemplate} />
            </Paper>
          </div>
        </Tabs.Panel>

        <Tabs.Panel value="qualite" pt="sm" style={{ overflow: 'auto' }}>
          <QualityTab id={ds.id} />
        </Tabs.Panel>

        <Tabs.Panel value="import" pt="sm" style={{ overflow: 'auto' }}>
          <Stack maw={900}>
            <Text size="sm">
              <b>Empreinte SHA-256 du fichier brut</b> : <code>{ds.raw.sha256}</code>
            </Text>
            <Text size="sm">
              Options de lecture :{' '}
              {Object.entries(ds.raw.report.options || {})
                .map(([k, v]) => `${k} = ${v === '\t' ? 'tabulation' : v}`)
                .join(', ')}
            </Text>
            <Table fz="sm" striped withTableBorder>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Colonne</Table.Th>
                  <Table.Th>Type détecté</Table.Th>
                  <Table.Th>Remarques</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {ds.raw.report.columns.map((c) => (
                  <Table.Tr key={c.name}>
                    <Table.Td>{c.name}</Table.Td>
                    <Table.Td>{typeLabel(c.type)}</Table.Td>
                    <Table.Td>
                      <Text size="xs">{c.note}</Text>
                      {c.warning && (
                        <Text size="xs" c="orange">
                          {c.warning.message}
                        </Text>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Stack>
        </Tabs.Panel>

        <Tabs.Panel value="methode" pt="sm" style={{ overflow: 'auto' }}>
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) 360px', gap: 16 }}>
            <Paper withBorder p="md">
              <Markdown text={method} />
            </Paper>
            <Stack>
              <Textarea
                label="Notes libres (reprises dans la fiche)"
                description="Contexte, limites connues, échanges avec les fournisseurs de données…"
                autosize
                minRows={8}
                value={notes}
                disabled={!canWrite}
                onChange={(e) => setNotes(e.currentTarget.value)}
              />
              {canWrite && (
                <Button onClick={() => api.patch(`/api/datasets/${ds.id}`, { notes }).then(() => { ok('Notes enregistrées'); load(); }).catch(fail)}>
                  Enregistrer les notes
                </Button>
              )}
              <Button variant="light" leftSection={<IconFileText size={16} />} onClick={() => saveText(method, `${ds.name}_methode.md`)}>
                Télécharger la fiche (.md)
              </Button>
            </Stack>
          </div>
        </Tabs.Panel>
      </Tabs>

      <TemplateModal datasetId={ds.id} templateId={template} onClose={() => setTemplate(null)} onDone={changed} />
      <StepModal draft={draft} onClose={() => setDraft(null)} onSaved={changed} datasetId={ds.id} columns={ds.schema} />
      <ColumnDrawer datasetId={ds.id} column={colOpen} columns={ds.schema} canWrite={canWrite} onClose={() => setColOpen(null)} onStep={setDraft} />
      <ExportModal ds={ds} opened={exportOpen} onClose={() => setExportOpen(false)} />
      <ShareModal ds={ds} opened={shareOpen} onClose={() => setShareOpen(false)} onDone={load} />
    </Stack>
  );
}
