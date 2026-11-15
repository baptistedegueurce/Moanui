import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActionIcon,
  Alert,
  Badge,
  Button,
  FileButton,
  Group,
  MultiSelect,
  NumberInput,
  Paper,
  Progress,
  ScrollArea,
  Select,
  SimpleGrid,
  Stack,
  Table,
  Tabs,
  TagsInput,
  Text,
  TextInput,
  Title,
  Tooltip,
} from '@mantine/core';
import { IconPlus, IconTrash, IconDeviceFloppy, IconFileSpreadsheet, IconUpload, IconPlayerPlay, IconAlertTriangle } from '@tabler/icons-react';
import { api, downloadPost } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtNumber } from '../lib/format';
import { fail, ok } from '../lib/notify';
import { recall, remember } from '../lib/memo';
import type { DatasetSummary } from '../lib/types';
import { loadPlotly } from '../lib/plotly';
import FicheMenu from '../components/FicheMenu';


type Mapping = Record<'espece' | 'date' | 'poids' | 'navire' | 'maree' | 'nom' | 'quartier' | 'engin', string | null>;
interface Suivi {
  id: string;
  kind: 'quota' | 'limitations';
  name: string;
  spec: any;
  who?: string;
}
interface Rule {
  espece: string;
  type: string;
  limite_kg: number | '' | null;
  debut: string;
  fin: string;
}

const PERIODS = [
  { value: 'maree', label: 'À la marée' },
  { value: 'jour', label: 'Par jour' },
  { value: 'semaine', label: 'Par semaine' },
  { value: 'mois', label: 'Par mois' },
  { value: 'trimestre', label: 'Par trimestre' },
  { value: 'semestre', label: 'Par semestre' },
  { value: 'annee', label: 'Par année' },
];
const MAP_LABELS: Record<keyof Mapping, string> = {
  espece: 'Espèce (code FAO)',
  date: 'Date',
  poids: 'Poids (kg)',
  navire: 'Navire',
  maree: 'Marée (facultatif)',
  nom: 'Nom du navire (facultatif)',
  quartier: 'Quartier (facultatif)',
  engin: 'Engin (facultatif)',
};
const year = new Date().getFullYear();
const d = (iso?: string | null) => (iso ? iso.slice(0, 10).split('-').reverse().join('/') : '–');
const t = (kg: number | null | undefined) => (kg == null ? '–' : `${fmtNumber(Math.round(kg / 100) / 10)} t`);
const color = (pct: number, seuils: number[] = [80, 90, 100]) =>
  pct >= (seuils[seuils.length - 1] ?? 100) ? 'red' : pct >= (seuils[1] ?? 90) ? 'orange' : pct >= (seuils[0] ?? 80) ? 'yellow' : 'teal';

/** Lecture simple d'un CSV (séparateur ; ou ,) en lignes d'objets. */
function parseCsv(text: string): Record<string, string>[] {
  const lines = text.replace(/^﻿/, '').split(/\r?\n/).filter((l) => l.trim());
  if (!lines.length) return [];
  const sep = lines[0].includes(';') ? ';' : ',';
  const head = lines[0].split(sep).map((h) => h.trim().toLowerCase());
  return lines.slice(1).map((l) => Object.fromEntries(l.split(sep).map((v, i) => [head[i], v.trim()])));
}

function Plot({ data, layout }: { data: any[]; layout: any }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let off = false;
    loadPlotly().then((P) => {
      if (!off && ref.current) P.react(ref.current, data, { margin: { l: 60, r: 20, t: 30, b: 40 }, height: 340, separators: ', ', font: { family: 'IBM Plex Sans' }, ...layout }, { displaylogo: false, responsive: true, locale: 'fr' });
    });
    return () => {
      off = true;
    };
  }, [data, layout]);
  return <div ref={ref} />;
}

function Tile({ label, value, c }: { label: string; value: string; c?: string }) {
  return (
    <Paper withBorder p="xs">
      <Text size="xs" c="dimmed">
        {label}
      </Text>
      <Text fw={600} size="lg" c={c}>
        {value}
      </Text>
    </Paper>
  );
}

/** Jeu de données et colonnes utilisées (proposées automatiquement). */
function Source({ datasets, dsId, setDsId, mapping, setMapping, need }: {
  datasets: DatasetSummary[];
  dsId: string | null;
  setDsId: (v: string | null) => void;
  mapping: Mapping | null;
  setMapping: (m: Mapping) => void;
  need: (keyof Mapping)[];
}) {
  const [cols, setCols] = useState<string[]>([]);
  useEffect(() => {
    if (!dsId) return;
    api
      .get(`/api/gestion/colonnes/${dsId}`)
      .then((r) => {
        setCols(r.colonnes);
        if (!mapping || Object.values(mapping).some((v) => v && !r.colonnes.includes(v))) setMapping(r.proposition);
      })
      .catch(fail);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dsId]);
  return (
    <Paper withBorder p="sm">
      <Group align="flex-end" gap="sm">
        <Select label="Données de captures (SACROIS, journaux, ventes…)" w={360} searchable data={datasets.map((d) => ({ value: d.id, label: d.name }))} value={dsId} onChange={setDsId} />
        {mapping &&
          need.map((k) => (
            <Select key={k} label={MAP_LABELS[k]} w={170} searchable clearable={!['espece', 'date', 'poids'].includes(k)} data={cols} value={mapping[k]} onChange={(v) => setMapping({ ...mapping, [k]: v })} />
          ))}
      </Group>
    </Paper>
  );
}

export default function GestionPage() {
  const { canWrite } = useAuth();
  const saved0 = recall<any>('gestion');
  const [tab, setTab] = useState<string | null>(saved0?.tab || 'tableau');
  const [datasets, setDatasets] = useState<DatasetSummary[]>([]);
  const [dsId, setDsId] = useState<string | null>(saved0?.dsId || null);
  const [mapping, setMapping] = useState<Mapping | null>(saved0?.mapping || null);
  const [suivis, setSuivis] = useState<Suivi[]>([]);
  const [board, setBoard] = useState<any[] | null>(null);
  // quota
  const [q, setQ] = useState<any>(saved0?.q || { id: null, name: '', especes: [], debut: `${year}-01-01`, fin: `${year}-12-31`, quota_kg: '', annonce_kg: '', seuils: ['80', '90', '100'] });
  const [qRes, setQRes] = useState<any>(saved0?.qRes || null);
  const [species, setSpecies] = useState<string[]>([]);
  // limitations
  const [lim, setLim] = useState<{ id: string | null; name: string; regles: Rule[] }>(saved0?.lim || { id: null, name: '', regles: [] });
  const [lRes, setLRes] = useState<any>(saved0?.lRes || null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    remember('gestion', { tab, dsId, mapping, q, qRes, lim, lRes });
  }, [tab, dsId, mapping, q, qRes, lim, lRes]);

  const loadSuivis = () => api.get<Suivi[]>('/api/gestion/suivis').then(setSuivis).catch(fail);
  const loadBoard = () => {
    setBoard(null);
    api.get('/api/gestion/tableau-de-bord').then(setBoard).catch(fail);
  };
  useEffect(() => {
    api.get<DatasetSummary[]>('/api/datasets').then(setDatasets).catch(fail);
    loadSuivis();
    loadBoard();
  }, []);
  useEffect(() => {
    if (!dsId || !mapping?.espece) return;
    api
      .get(`/api/datasets/${dsId}/values/${encodeURIComponent(mapping.espece)}?limit=500`)
      .then((r) => setSpecies([...new Set<string>(r.values.map((v: any) => String(v.valeur ?? '').trim().toUpperCase()).filter(Boolean))]))
      .catch(() => setSpecies([]));
  }, [dsId, mapping?.espece]);

  const qSpec = () => ({
    dataset_id: dsId,
    mapping,
    especes: q.especes,
    debut: q.debut,
    fin: q.fin,
    quota_kg: Number(q.quota_kg) || 0,
    annonce_kg: Number(q.annonce_kg) || null,
    seuils: (q.seuils || []).map(Number).filter((x: number) => x > 0),
  });
  const lSpec = () => ({ dataset_id: dsId, mapping, regles: lim.regles });

  const runQuota = async () => {
    setBusy(true);
    try {
      setQRes(await api.post('/api/gestion/quota', { dataset_id: dsId, spec: qSpec(), name: q.name }));
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  };
  const runLim = async () => {
    setBusy(true);
    try {
      setLRes(await api.post('/api/gestion/depassements', { dataset_id: dsId, spec: lSpec(), name: lim.name }));
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  };
  const save = async (kind: 'quota' | 'limitations') => {
    const name = kind === 'quota' ? q.name || `Quota ${q.especes.join(', ')} ${q.debut.slice(0, 4)}` : lim.name || 'Limitations';
    const spec = kind === 'quota' ? qSpec() : lSpec();
    const id = kind === 'quota' ? q.id : lim.id;
    try {
      if (id) await api.put(`/api/gestion/suivis/${id}`, { kind, name, spec });
      else {
        const r = await api.post('/api/gestion/suivis', { kind, name, spec });
        if (kind === 'quota') setQ({ ...q, id: r.id, name });
        else setLim({ ...lim, id: r.id, name });
      }
      ok('Suivi enregistré');
      loadSuivis();
      loadBoard();
    } catch (e) {
      fail(e);
    }
  };
  const openSuivi = (s: Suivi) => {
    if (s.spec.dataset_id) setDsId(s.spec.dataset_id);
    if (s.spec.mapping) setMapping(s.spec.mapping);
    if (s.kind === 'quota') {
      setQ({ id: s.id, name: s.name, especes: s.spec.especes || [], debut: s.spec.debut, fin: s.spec.fin, quota_kg: s.spec.quota_kg, annonce_kg: s.spec.annonce_kg ?? '', seuils: (s.spec.seuils || []).map(String) });
      setQRes(null);
      setTab('quota');
    } else {
      setLim({ id: s.id, name: s.name, regles: s.spec.regles || [] });
      setLRes(null);
      setTab('limitations');
    }
  };
  const importQuotas = async (file: File | null) => {
    if (!file || !dsId || !mapping) return;
    const rows = parseCsv(await file.text());
    let n = 0;
    for (const r of rows) {
      const sp = (r.esp_cod_fao || r.espece || '').toUpperCase();
      const kg = Number(String(r.quota_kg || '').replace(',', '.'));
      if (!sp || !kg) continue;
      const spec = { dataset_id: dsId, mapping, especes: sp.split(/[,|]/).map((x) => x.trim()), debut: r.debut || `${year}-01-01`, fin: r.fin || `${year}-12-31`, quota_kg: kg, annonce_kg: Number(String(r.annonce_kg || r.quota_dgampa || '').replace(',', '.')) || null, seuils: [80, 90, 100] };
      await api.post('/api/gestion/suivis', { kind: 'quota', name: `Quota ${sp} ${spec.debut.slice(0, 4)}`, spec });
      n++;
    }
    ok(`${n} quota(s) importé(s)`);
    loadSuivis();
    loadBoard();
  };
  const importRules = async (file: File | null) => {
    if (!file) return;
    const rows = parseCsv(await file.text());
    const regles = rows
      .map((r) => ({ espece: (r.esp_cod_fao || r.espece || '').toUpperCase(), type: (r.type || 'mois').toLowerCase().replace('é', 'e'), limite_kg: r.limite_kg === '' ? null : Number(String(r.limite_kg).replace(',', '.')), debut: r.debut || `${year}-01-01`, fin: r.fin || `${year}-12-31` }))
      .filter((r) => r.espece);
    setLim({ ...lim, regles: [...lim.regles, ...regles] });
    ok(`${regles.length} règle(s) ajoutée(s)`);
  };

  // --- figures du quota
  const qFig = useMemo(() => {
    if (!qRes) return null;
    const x = qRes.jours.map((d: any) => d.jour);
    const y = qRes.jours.map((d: any) => d.cumul / 1000);
    const data: any[] = [{ type: 'scatter', mode: 'lines', line: { shape: 'hv', color: '#2a78d6', width: 2.4 }, x, y, name: 'Consommation cumulée' }];
    const span = [qRes.debut, qRes.fin];
    data.push({ type: 'scatter', mode: 'lines', x: span, y: [qRes.quota_kg / 1000, qRes.quota_kg / 1000], line: { color: '#e34948', width: 2 }, name: 'Quota' });
    if (qRes.annonce_kg) data.push({ type: 'scatter', mode: 'lines', x: span, y: [qRes.annonce_kg / 1000, qRes.annonce_kg / 1000], line: { color: '#5f6b7a', dash: 'dash' }, name: 'Annoncé' });
    const p = qRes.projection;
    if (p && x.length)
      data.push(
        { type: 'scatter', mode: 'lines', x: [x[x.length - 1], qRes.fin], y: [y[y.length - 1], p.fin_rythme_moyen / 1000], line: { color: '#2a78d6', dash: 'dot' }, name: 'Projection (rythme moyen)' },
        { type: 'scatter', mode: 'lines', x: [x[x.length - 1], qRes.fin], y: [y[y.length - 1], p.fin_rythme_30j / 1000], line: { color: '#eb6834', dash: 'dot' }, name: 'Projection (30 derniers jours)' },
      );
    const m = { type: 'bar', x: qRes.mois.map((r: any) => r.mois), y: qRes.mois.map((r: any) => r.pct), marker: { color: '#2a78d6' }, name: '% du quota dans le mois' };
    return {
      cumul: { data, layout: { yaxis: { title: { text: 'Tonnes' }, rangemode: 'tozero' }, legend: { orientation: 'h', y: -0.15 }, title: { text: 'Consommation cumulée', font: { size: 14 } } } },
      mois: { data: [m], layout: { yaxis: { title: { text: '% du quota' } }, title: { text: 'Consommation par mois', font: { size: 14 } } } },
    };
  }, [qRes]);

  const lFig = useMemo(() => {
    if (!lRes) return null;
    const mo = lRes.par_mois.map((r: any) => r.mois);
    return {
      data: [
        { type: 'bar', x: mo, y: lRes.par_mois.map((r: any) => r.kg), name: 'Quantité au-delà (kg)', marker: { color: '#e34948' } },
        { type: 'scatter', mode: 'lines+markers', x: mo, y: lRes.par_mois.map((r: any) => r.depassements), name: 'Nombre de dépassements', yaxis: 'y2', line: { color: '#2a78d6' } },
      ],
      layout: { yaxis: { title: { text: 'kg au-delà' } }, yaxis2: { overlaying: 'y', side: 'right', title: { text: 'Dépassements' }, rangemode: 'tozero' }, legend: { orientation: 'h', y: -0.15 }, title: { text: 'Dépassements par mois', font: { size: 14 } } },
    };
  }, [lRes]);

  const quotas = suivis.filter((s) => s.kind === 'quota');
  const limits = suivis.filter((s) => s.kind === 'limitations');
  const needQ: (keyof Mapping)[] = ['espece', 'date', 'poids', 'navire'];
  const needL: (keyof Mapping)[] = ['espece', 'date', 'poids', 'navire', 'maree', 'nom', 'quartier', 'engin'];

  return (
    <Stack gap="sm">
      <Group justify="space-between">
        <div>
          <Title order={3}>Gestion</Title>
          <Text size="sm" c="dimmed">
            Suivi de la consommation des quotas et contrôle des limitations de captures, à partir de vos données de débarquement.
          </Text>
        </div>
      </Group>
      <Tabs value={tab} onChange={setTab}>
        <Tabs.List>
          <Tabs.Tab value="tableau">Tableau de bord des quotas</Tabs.Tab>
          <Tabs.Tab value="quota">Suivi d’un quota</Tabs.Tab>
          <Tabs.Tab value="limitations">Limitations et dépassements</Tabs.Tab>
        </Tabs.List>

        <Tabs.Panel value="tableau" pt="sm">
          <Stack gap="sm">
            {board === null ? (
              <Text c="dimmed">Calcul en cours…</Text>
            ) : board.length === 0 ? (
              <Alert color="blue" variant="light">
                Aucun quota enregistré. Ouvrez l’onglet « Suivi d’un quota », choisissez vos données, renseignez l’espèce et le quota, puis enregistrez. Vous pouvez aussi importer une liste de quotas (CSV : esp_cod_fao ; quota_kg ; annonce_kg ; debut ; fin).
              </Alert>
            ) : (
              <Paper withBorder>
                <Table striped highlightOnHover fz="sm">
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Quota</Table.Th>
                      <Table.Th>Espèces</Table.Th>
                      <Table.Th>Période</Table.Th>
                      <Table.Th>Consommation</Table.Th>
                      <Table.Th ta="right">Débarqué / quota</Table.Th>
                      <Table.Th>Dernière donnée</Table.Th>
                      <Table.Th>Projection fin de période</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {board.map((b) => {
                      const r = b.resultat;
                      return (
                        <Table.Tr key={b.id} style={{ cursor: 'pointer' }} onClick={() => openSuivi({ ...b, kind: 'quota' })}>
                          <Table.Td fw={500}>{b.name}</Table.Td>
                          <Table.Td>{(b.spec.especes || []).join(', ')}</Table.Td>
                          <Table.Td>
                            {d(b.spec.debut)} → {d(b.spec.fin)}
                          </Table.Td>
                          <Table.Td w={220}>
                            {r ? (
                              <Group gap={6} wrap="nowrap">
                                <Progress value={Math.min(100, r.pct)} color={color(r.pct, r.seuils)} w={120} />
                                <Text size="sm" fw={600} c={color(r.pct, r.seuils)}>
                                  {fmtNumber(Math.round(r.pct * 10) / 10)} %
                                </Text>
                              </Group>
                            ) : (
                              <Text size="xs" c="red">
                                {b.erreur}
                              </Text>
                            )}
                          </Table.Td>
                          <Table.Td ta="right">{r ? `${t(r.total_kg)} / ${t(r.quota_kg)}` : ''}</Table.Td>
                          <Table.Td>{r ? d(r.derniere_donnee) : ''}</Table.Td>
                          <Table.Td>{r?.projection ? `${fmtNumber(Math.round((100 * r.projection.fin_rythme_moyen) / r.quota_kg))} % (rythme moyen)` : r?.atteint_le ? `atteint le ${d(r.atteint_le)}` : ''}</Table.Td>
                        </Table.Tr>
                      );
                    })}
                  </Table.Tbody>
                </Table>
              </Paper>
            )}
            <Group>
              <Button variant="default" size="xs" onClick={loadBoard}>
                Actualiser
              </Button>
              {canWrite && (
                <FileButton onChange={importQuotas} accept=".csv,text/csv">
                  {(props) => (
                    <Tooltip label={dsId ? 'CSV : esp_cod_fao ; quota_kg ; annonce_kg ; debut ; fin' : 'Choisissez d’abord les données dans l’onglet « Suivi d’un quota »'}>
                      <Button {...props} size="xs" variant="default" leftSection={<IconUpload size={14} />} disabled={!dsId || !mapping}>
                        Importer une liste de quotas
                      </Button>
                    </Tooltip>
                  )}
                </FileButton>
              )}
            </Group>
          </Stack>
        </Tabs.Panel>

        <Tabs.Panel value="quota" pt="sm">
          <Stack gap="sm">
            <Source datasets={datasets} dsId={dsId} setDsId={setDsId} mapping={mapping} setMapping={setMapping} need={needQ} />
            <Paper withBorder p="sm">
              <Group align="flex-end" gap="sm">
                {quotas.length > 0 && <Select label="Quotas enregistrés" placeholder="Nouveau quota" w={220} data={quotas.map((s) => ({ value: s.id, label: s.name }))} value={q.id} onChange={(v) => { const s = quotas.find((x) => x.id === v); if (s) openSuivi(s); }} />}
                <TextInput label="Nom" w={200} placeholder="ex. Sole 2025" value={q.name} onChange={(e) => setQ({ ...q, name: e.currentTarget.value })} />
                <MultiSelect label="Espèces du quota" w={220} searchable data={[...new Set([...species, ...q.especes])]} value={q.especes} onChange={(v) => setQ({ ...q, especes: v })} />
                <TextInput label="Début" type="date" w={150} value={q.debut} onChange={(e) => setQ({ ...q, debut: e.currentTarget.value })} />
                <TextInput label="Fin" type="date" w={150} value={q.fin} onChange={(e) => setQ({ ...q, fin: e.currentTarget.value })} />
                <NumberInput label="Quota (kg)" w={130} thousandSeparator=" " min={0} value={q.quota_kg} onChange={(v) => setQ({ ...q, quota_kg: v })} />
                <NumberInput label="Annoncé (kg, facultatif)" w={170} thousandSeparator=" " min={0} value={q.annonce_kg} onChange={(v) => setQ({ ...q, annonce_kg: v })} />
                <TagsInput label="Seuils d’alerte (%)" w={170} value={q.seuils} onChange={(v) => setQ({ ...q, seuils: v })} />
              </Group>
              <Group mt="sm" gap="xs">
                <Button leftSection={<IconPlayerPlay size={16} />} loading={busy} disabled={!dsId || !q.especes.length || !q.quota_kg} onClick={runQuota}>
                  Calculer
                </Button>
                {canWrite && (
                  <Button variant="default" leftSection={<IconDeviceFloppy size={16} />} disabled={!dsId || !q.especes.length} onClick={() => save('quota')}>
                    {q.id ? 'Mettre à jour' : 'Enregistrer'}
                  </Button>
                )}
                {q.id && canWrite && (
                  <Button variant="subtle" color="red" onClick={async () => { if (confirm('Supprimer ce suivi ?')) { await api.del(`/api/gestion/suivis/${q.id}`); setQ({ ...q, id: null }); loadSuivis(); loadBoard(); } }}>
                    Supprimer
                  </Button>
                )}
                <FicheMenu size="sm" label="Fiche de suivi" disabled={!qRes} onExport={(fmt) => downloadPost(`/api/gestion/quota/method.${fmt === 'zip' ? 'zip' : fmt}`, { dataset_id: dsId, spec: qSpec(), name: q.name }, `suivi_quota.${fmt}`)} />
                <Button variant="default" size="sm" leftSection={<IconFileSpreadsheet size={16} />} disabled={!qRes} onClick={() => downloadPost('/api/gestion/quota/export.xlsx', { dataset_id: dsId, spec: qSpec() }, 'suivi_quota.xlsx').catch(fail)}>
                  Excel
                </Button>
              </Group>
            </Paper>
            {qRes && (
              <>
                {qRes.alertes.length > 0 && (
                  <Alert color={color(qRes.pct, qRes.seuils)} icon={<IconAlertTriangle size={18} />}>
                    Seuil{qRes.alertes.length > 1 ? 's' : ''} franchi{qRes.alertes.length > 1 ? 's' : ''} : {qRes.alertes.map((s: number) => `${s} %`).join(', ')}
                    {qRes.atteint_le ? ` ; quota atteint le ${d(qRes.atteint_le)}` : ''}.
                  </Alert>
                )}
                <SimpleGrid cols={{ base: 2, md: 6 }}>
                  <Tile label="Débarqué" value={t(qRes.total_kg)} />
                  <Tile label="Consommation" value={`${fmtNumber(Math.round(qRes.pct * 10) / 10)} %`} c={color(qRes.pct, qRes.seuils)} />
                  <Tile label="Reste" value={t(qRes.reste_kg)} />
                  <Tile label="Dernière donnée" value={d(qRes.derniere_donnee)} />
                  <Tile label="Écart à l’annonce" value={qRes.ecart_annonce_pct == null ? '–' : `${qRes.ecart_annonce_pct > 0 ? '+' : ''}${fmtNumber(qRes.ecart_annonce_pct)} %`} c={qRes.ecart_annonce_pct > 0 ? 'red' : 'teal'} />
                  <Tile label="Navires" value={fmtNumber(qRes.navires)} />
                </SimpleGrid>
                {qRes.projection && (
                  <Text size="sm" c="dimmed">
                    Projection (extrapolation linéaire, ordre de grandeur) : au rythme moyen, {t(qRes.projection.fin_rythme_moyen)} en fin de période
                    {qRes.projection.atteinte_rythme_moyen ? `, quota atteint vers le ${d(qRes.projection.atteinte_rythme_moyen)}` : ''} ; au rythme des 30 derniers jours, {t(qRes.projection.fin_rythme_30j)}
                    {qRes.projection.atteinte_rythme_30j ? `, quota atteint vers le ${d(qRes.projection.atteinte_rythme_30j)}` : ''}.
                  </Text>
                )}
                {qFig && (
                  <SimpleGrid cols={{ base: 1, lg: 2 }}>
                    <Paper withBorder p="xs">
                      <Plot {...qFig.cumul} />
                    </Paper>
                    <Paper withBorder p="xs">
                      <Plot {...qFig.mois} />
                    </Paper>
                  </SimpleGrid>
                )}
                <Paper withBorder>
                  <ScrollArea h={300}>
                    <Table fz="sm" striped>
                      <Table.Thead>
                        <Table.Tr>
                          {['Mois', 'Débarqué', 'Cumul', '% du quota', '% cumulé', 'Navires'].map((h) => (
                            <Table.Th key={h}>{h}</Table.Th>
                          ))}
                        </Table.Tr>
                      </Table.Thead>
                      <Table.Tbody>
                        {qRes.mois.map((r: any) => (
                          <Table.Tr key={r.mois}>
                            <Table.Td>{r.mois}</Table.Td>
                            <Table.Td>{t(r.kg)}</Table.Td>
                            <Table.Td>{t(r.cumul)}</Table.Td>
                            <Table.Td>{fmtNumber(r.pct)} %</Table.Td>
                            <Table.Td>
                              <Badge variant="light" color={color(r.pct_cumul, qRes.seuils)}>
                                {fmtNumber(r.pct_cumul)} %
                              </Badge>
                            </Table.Td>
                            <Table.Td>{r.navires}</Table.Td>
                          </Table.Tr>
                        ))}
                      </Table.Tbody>
                    </Table>
                  </ScrollArea>
                </Paper>
              </>
            )}
          </Stack>
        </Tabs.Panel>

        <Tabs.Panel value="limitations" pt="sm">
          <Stack gap="sm">
            <Source datasets={datasets} dsId={dsId} setDsId={setDsId} mapping={mapping} setMapping={setMapping} need={needL} />
            <Paper withBorder p="sm">
              <Group align="flex-end" gap="sm" mb="xs">
                {limits.length > 0 && <Select label="Jeux de règles enregistrés" placeholder="Nouveau" w={220} data={limits.map((s) => ({ value: s.id, label: s.name }))} value={lim.id} onChange={(v) => { const s = limits.find((x) => x.id === v); if (s) openSuivi(s); }} />}
                <TextInput label="Nom du jeu de règles" w={240} placeholder="ex. Limitations 2025" value={lim.name} onChange={(e) => setLim({ ...lim, name: e.currentTarget.value })} />
              </Group>
              <Table fz="sm">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Espèce(s)</Table.Th>
                    <Table.Th>Type de limite</Table.Th>
                    <Table.Th>Limite (kg)</Table.Th>
                    <Table.Th>Du</Table.Th>
                    <Table.Th>Au</Table.Th>
                    <Table.Th />
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {lim.regles.map((r, i) => {
                    const set = (p: Partial<Rule>) => setLim({ ...lim, regles: lim.regles.map((x, j) => (j === i ? { ...x, ...p } : x)) });
                    return (
                      <Table.Tr key={i}>
                        <Table.Td>
                          <Select size="xs" w={150} searchable data={[...new Set([...species, r.espece].filter(Boolean))]} value={r.espece || null} onChange={(v) => set({ espece: v || '' })} />
                        </Table.Td>
                        <Table.Td>
                          <Select size="xs" w={150} data={PERIODS} value={r.type} onChange={(v) => v && set({ type: v })} allowDeselect={false} />
                        </Table.Td>
                        <Table.Td>
                          <NumberInput size="xs" w={110} min={0} thousandSeparator=" " placeholder="0 = fermeture" value={r.limite_kg ?? ''} onChange={(v) => set({ limite_kg: v === '' ? null : Number(v) })} />
                        </Table.Td>
                        <Table.Td>
                          <TextInput size="xs" type="date" value={r.debut} onChange={(e) => set({ debut: e.currentTarget.value })} />
                        </Table.Td>
                        <Table.Td>
                          <TextInput size="xs" type="date" value={r.fin} onChange={(e) => set({ fin: e.currentTarget.value })} />
                        </Table.Td>
                        <Table.Td>
                          <ActionIcon variant="subtle" color="red" onClick={() => setLim({ ...lim, regles: lim.regles.filter((_, j) => j !== i) })}>
                            <IconTrash size={14} />
                          </ActionIcon>
                        </Table.Td>
                      </Table.Tr>
                    );
                  })}
                </Table.Tbody>
              </Table>
              <Group mt="xs" gap="xs">
                <Button size="xs" variant="default" leftSection={<IconPlus size={14} />} onClick={() => setLim({ ...lim, regles: [...lim.regles, { espece: '', type: 'mois', limite_kg: null, debut: `${year}-01-01`, fin: `${year}-12-31` }] })}>
                  Ajouter une règle
                </Button>
                <FileButton onChange={importRules} accept=".csv,text/csv">
                  {(props) => (
                    <Button {...props} size="xs" variant="default" leftSection={<IconUpload size={14} />}>
                      Importer des règles (CSV)
                    </Button>
                  )}
                </FileButton>
                <Text size="xs" c="dimmed">
                  La limite elle-même est autorisée ; 0 kg = fermeture ; une période sans règle n’est pas limitée.
                </Text>
              </Group>
              <Group mt="sm" gap="xs">
                <Button leftSection={<IconPlayerPlay size={16} />} loading={busy} disabled={!dsId || !lim.regles.length} onClick={runLim}>
                  Lancer le contrôle
                </Button>
                {canWrite && (
                  <Button variant="default" leftSection={<IconDeviceFloppy size={16} />} disabled={!lim.regles.length} onClick={() => save('limitations')}>
                    {lim.id ? 'Mettre à jour' : 'Enregistrer'}
                  </Button>
                )}
                <FicheMenu size="sm" label="Fiche de contrôle" disabled={!lRes} onExport={(fmt) => downloadPost(`/api/gestion/depassements/method.${fmt}`, { dataset_id: dsId, spec: lSpec(), name: lim.name }, `controle_limitations.${fmt}`)} />
                <Button variant="default" size="sm" leftSection={<IconFileSpreadsheet size={16} />} disabled={!lRes} onClick={() => downloadPost('/api/gestion/depassements/export.xlsx', { dataset_id: dsId, spec: lSpec() }, 'controle_limitations.xlsx').catch(fail)}>
                  Excel (règles, navires, lignes)
                </Button>
              </Group>
            </Paper>
            {lRes && (
              <>
                <SimpleGrid cols={3}>
                  <Tile label="Dépassements" value={fmtNumber(lRes.total.depassements)} c={lRes.total.depassements ? 'red' : 'teal'} />
                  <Tile label="Navires concernés" value={fmtNumber(lRes.total.navires)} />
                  <Tile label="Quantité au-delà des limites" value={`${fmtNumber(Math.round(lRes.total.kg))} kg`} />
                </SimpleGrid>
                <Paper withBorder>
                  <Text fw={600} p="xs">
                    Par règle
                  </Text>
                  <Table fz="sm" striped>
                    <Table.Thead>
                      <Table.Tr>
                        {['Règle', 'Dépassements', 'Navires', 'Au-delà (kg)', 'Unités contrôlées'].map((h) => (
                          <Table.Th key={h}>{h}</Table.Th>
                        ))}
                      </Table.Tr>
                    </Table.Thead>
                    <Table.Tbody>
                      {lRes.par_regle.map((r: any) => (
                        <Table.Tr key={r.regle}>
                          <Table.Td>{r.regle}</Table.Td>
                          <Table.Td>{r.depassements}</Table.Td>
                          <Table.Td>{r.navires}</Table.Td>
                          <Table.Td>{fmtNumber(Math.round(r.kg))}</Table.Td>
                          <Table.Td>{r.unites_controlees}</Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                </Paper>
                {lFig && lRes.par_mois.length > 0 && (
                  <Paper withBorder p="xs">
                    <Plot {...lFig} />
                  </Paper>
                )}
                <Paper withBorder>
                  <Text fw={600} p="xs">
                    Par navire ({lRes.par_navire.length})
                  </Text>
                  <ScrollArea h={320}>
                    <Table fz="sm" striped>
                      <Table.Thead>
                        <Table.Tr>
                          {['Règle', 'Navire', 'Nom', 'Quartier', 'Engin', 'Dépassements', 'Au-delà (kg)', 'Max sur une unité (kg)'].map((h) => (
                            <Table.Th key={h}>{h}</Table.Th>
                          ))}
                        </Table.Tr>
                      </Table.Thead>
                      <Table.Tbody>
                        {lRes.par_navire.slice(0, 500).map((r: any, i: number) => (
                          <Table.Tr key={i}>
                            <Table.Td>{r.regle.split(' : ')[0]}</Table.Td>
                            <Table.Td>{r.navire}</Table.Td>
                            <Table.Td>{r.nom}</Table.Td>
                            <Table.Td>{r.quartier}</Table.Td>
                            <Table.Td>{r.engin}</Table.Td>
                            <Table.Td>{r.depassements}</Table.Td>
                            <Table.Td>{fmtNumber(Math.round(r.kg))}</Table.Td>
                            <Table.Td>{fmtNumber(Math.round(r.max_kg))}</Table.Td>
                          </Table.Tr>
                        ))}
                      </Table.Tbody>
                    </Table>
                  </ScrollArea>
                </Paper>
              </>
            )}
          </Stack>
        </Tabs.Panel>
      </Tabs>
    </Stack>
  );
}
