import { useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  Accordion,
  ActionIcon,
  Alert,
  Button,
  Group,
  Menu,
  NumberInput,
  Paper,
  ScrollArea,
  SegmentedControl,
  Select,
  Stack,
  Switch,
  Table,
  Text,
  TextInput,
  Textarea,
  Title,
  Tooltip,
  Loader,
  Center,
  Modal,
  ColorSwatch,
  CheckIcon,
} from '@mantine/core';
import { IconPlus, IconTrash, IconPhoto, IconFileText, IconDeviceFloppy, IconTable, IconBulb, IconVectorBezier } from '@tabler/icons-react';
import { api, downloadPost } from '../lib/api';
import { useAuth } from '../lib/auth';
import { AXES, axisCfg, AxisCfg, AxisId, buildFigure, CHART_TYPES, chartAdvice, ChartSpec, dataRequest, defaultSpec, Measure, MARKS, markOf, measureLabel, RAW_TYPES, RefMark, SIZE_PRESETS, usedAxes } from '../lib/chart';
import { fmtNumber, isNumericType } from '../lib/format';
import { fail, ok } from '../lib/notify';
import { NEUTRAL } from '../lib/theme';
import type { Column, DatasetSummary } from '../lib/types';
import { AGGS, Conditions } from '../components/StepForm';

let plotlyPromise: Promise<any> | null = null;
const loadPlotly = () => (plotlyPromise ??= import('plotly.js-dist-min').then((m) => m.default || m));

interface Saved {
  id: string;
  name: string;
  spec: ChartSpec;
}

export default function ChartsPage() {
  const { me, structure } = useAuth();
  const theme = structure?.theme || NEUTRAL;
  const [params, setParams] = useSearchParams();
  const [datasets, setDatasets] = useState<DatasetSummary[]>([]);
  const dsId = params.get('dataset');
  const [columns, setColumns] = useState<Column[]>([]);
  const [spec, setSpec] = useState<ChartSpec>(() => defaultSpec(me?.display_name || '', theme.chart.default_source));
  const [data, setData] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [saved, setSaved] = useState<Saved[]>([]);
  const [current, setCurrent] = useState<Saved | null>(null);
  const [showTable, setShowTable] = useState(false);
  const plotRef = useRef<HTMLDivElement>(null);
  const canWrite = datasets.find((d) => d.id === dsId)?.mode === 'ecriture';

  useEffect(() => {
    api.get<DatasetSummary[]>('/api/datasets').then(setDatasets).catch(fail);
  }, [structure?.id]);

  useEffect(() => {
    if (!dsId) return;
    api.get(`/api/datasets/${dsId}`).then((d) => setColumns(d.schema.filter((c: Column) => !c.name.startsWith('__')))).catch(fail);
    const want = params.get('chart');
    api
      .get<Saved[]>(`/api/datasets/${dsId}/charts`)
      .then((l) => {
        setSaved(l);
        const s = want ? l.find((x) => x.id === want) : null;
        if (s) {
          setCurrent(s);
          setSpec(s.spec);
        }
      })
      .catch(() => setSaved([]));
    setCurrent(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dsId]);

  const set = (patch: Partial<ChartSpec>) => setSpec((s) => ({ ...s, ...patch }));
  const setT = (patch: Partial<ChartSpec['template']>) => setSpec((s) => ({ ...s, template: { ...s.template, ...patch } }));
  const setM = (i: number, patch: Partial<Measure>) => setSpec((s) => ({ ...s, measures: s.measures.map((x, j) => (j === i ? { ...x, ...patch } : x)) }));
  const setAxis = (a: AxisId, patch: Partial<AxisCfg>) =>
    setSpec((s) => {
      // l'axe principal garde ses anciens champs (graphiques déjà enregistrés)
      if (a === 'y') {
        const legacy: Partial<ChartSpec> = {};
        if ('title' in patch) legacy.y_title = patch.title || undefined;
        if ('scale' in patch) legacy.y_scale = patch.scale;
        if ('min' in patch) legacy.y_min = patch.min ?? null;
        if ('max' in patch) legacy.y_max = patch.max ?? null;
        const rest = { ...patch };
        delete rest.title; delete rest.scale; delete rest.min; delete rest.max;
        return { ...s, ...legacy, axes: { ...s.axes, y: { ...s.axes?.y, ...rest } } };
      }
      if (a === 'y2' && 'title' in patch) return { ...s, y2_title: patch.title || undefined, axes: { ...s.axes, y2: { ...s.axes?.y2, ...patch } } };
      return { ...s, axes: { ...s.axes, [a]: { ...s.axes?.[a], ...patch } } };
    });
  const setRef = (i: number, patch: Partial<RefMark>) => setSpec((s) => ({ ...s, refs: (s.refs || []).map((r, j) => (j === i ? { ...r, ...patch } : r)) }));

  const raw = RAW_TYPES.includes(spec.type);
  const ready = useMemo(() => {
    if (!dsId) return false;
    switch (spec.type) {
      case 'nuage':
      case 'bulles':
      case 'nuage3d':
        return !!spec.x && !!spec.y && (spec.type !== 'nuage3d' || !!spec.z) && (spec.type !== 'bulles' || !!spec.size);
      case 'boites':
      case 'violons':
        return !!spec.y;
      case 'histogramme':
        return !!spec.x;
      case 'chaleur':
      case 'surface3d':
        return !!spec.x && !!spec.series && spec.measures.length > 0 && spec.measures.every((m) => m.agg === 'nombre_lignes' || m.column);
      default:
        return !!spec.x && spec.measures.length > 0 && spec.measures.every((m) => m.agg === 'nombre_lignes' || m.column);
    }
  }, [spec, dsId]);

  // données (agrégées côté serveur) : uniquement quand la requête change
  const reqKey = JSON.stringify(ready ? dataRequest(spec) : null);
  useEffect(() => {
    if (!ready || !dsId) return setData(null);
    const t = setTimeout(async () => {
      setLoading(true);
      setErr(null);
      try {
        setData(await api.post(`/api/datasets/${dsId}/chart-data`, JSON.parse(reqKey)));
      } catch (e: any) {
        setErr(e.message);
        setData(null);
      } finally {
        setLoading(false);
      }
    }, 300);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reqKey, dsId]);

  const logoUrl = structure?.has_logo ? `/api/structures/${structure.id}/logo` : null;
  const figure = useMemo(() => (data ? buildFigure(spec, data, theme, { logoUrl, structureName: structure?.short_name }) : null), [data, spec, theme, logoUrl, structure]);

  useEffect(() => {
    if (!figure || !plotRef.current) return;
    let cancelled = false;
    loadPlotly().then((Plotly) => {
      if (cancelled || !plotRef.current) return;
      Plotly.react(plotRef.current, figure.data, figure.layout, {
        displaylogo: false,
        responsive: false,
        locale: 'fr',
        modeBarButtonsToRemove: ['select2d', 'lasso2d', 'toImage'],
      });
    });
    return () => {
      cancelled = true;
    };
  }, [figure]);

  const exportImage = async (format: 'png' | 'svg') => {
    const Plotly = await loadPlotly();
    if (!plotRef.current) return;
    const url = await Plotly.toImage(plotRef.current, { format, width: spec.template.width, height: spec.template.height, scale: format === 'png' ? 3 : 1 });
    const a = document.createElement('a');
    a.href = url;
    a.download = `${(spec.template.title || 'graphique').replace(/[^\w\- ]+/g, '_')}.${format}`;
    a.click();
  };

  const exportMethod = async () => {
    try {
      // le graphique tel qu'affiché est joint à la fiche (SVG vectoriel)
      let svg: string | undefined;
      const Plotly = await loadPlotly();
      if (plotRef.current) {
        const url: string = await Plotly.toImage(plotRef.current, { format: 'svg', width: spec.template.width, height: spec.template.height });
        const i = url.indexOf(',');
        svg = url.startsWith('data:image/svg+xml;base64,') ? atob(url.slice(i + 1)) : decodeURIComponent(url.slice(i + 1));
      }
      await downloadPost(`/api/datasets/${dsId}/charts/method.zip`, { name: spec.template.title || 'graphique', spec, svg }, 'graphique_methode.zip');
    } catch (e) {
      fail(e);
    }
  };

  const save = async () => {
    const name = spec.template.title || prompt('Nom du graphique') || 'Graphique';
    try {
      if (current) {
        await api.put(`/api/charts/${current.id}`, { name, spec });
      } else {
        const r = await api.post(`/api/datasets/${dsId}/charts`, { name, spec });
        setCurrent({ id: r.id, name, spec });
      }
      setSaved(await api.get(`/api/datasets/${dsId}/charts`));
      ok('Graphique enregistré');
    } catch (e) {
      fail(e);
    }
  };

  const cols = columns.map((c) => c.name);
  const numCols = columns.filter((c) => isNumericType(c.type)).map((c) => c.name);
  const advice = chartAdvice(spec, data);
  const xValues: string[] = useMemo(() => {
    if (!data || raw || !spec.x) return [];
    const i = data.columns.indexOf(spec.x);
    return i < 0 ? [] : [...new Set<string>(data.rows.map((r: any[]) => (r[i] == null ? '' : String(r[i]))))].filter(Boolean).slice(0, 500);
  }, [data, raw, spec.x]);
  const typeInfo = CHART_TYPES.find((t) => t.value === spec.type);

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '360px minmax(0, 1fr)', gap: 16, height: 'calc(100vh - 88px)' }}>
      <Paper withBorder p="sm" style={{ display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <ScrollArea style={{ flex: 1 }} offsetScrollbars>
          <Stack gap="sm">
            <Title order={4}>Graphique</Title>
            <Select
              label="Jeu de données"
              searchable
              data={datasets.map((d) => ({ value: d.id, label: d.name }))}
              value={dsId}
              onChange={(v) => v && setParams({ dataset: v })}
            />
            {saved.length > 0 && (
              <Select
                label="Graphiques enregistrés"
                placeholder="Nouveau graphique"
                clearable
                data={saved.map((s) => ({ value: s.id, label: s.name }))}
                value={current?.id || null}
                onChange={(v) => {
                  const s = saved.find((x) => x.id === v) || null;
                  setCurrent(s);
                  if (s) setSpec(s.spec);
                }}
              />
            )}
            <Select
              label="Type"
              description={typeInfo?.hint}
              data={CHART_TYPES.map((t) => ({ value: t.value, label: t.label }))}
              value={spec.type}
              onChange={(v) => v && set({ type: v as any })}
              allowDeselect={false}
            />
            <Accordion multiple defaultValue={['donnees', 'gabarit']} variant="contained">
              <Accordion.Item value="donnees">
                <Accordion.Control>Données représentées</Accordion.Control>
                <Accordion.Panel>
                  <Stack gap="xs">
                    {spec.type !== 'boites' && spec.type !== 'violons' && (
                      <Select
                        label={spec.type === 'histogramme' ? 'Variable' : spec.type === 'secteurs' ? 'Catégories' : 'Axe horizontal (X)'}
                        searchable
                        clearable
                        data={raw && spec.type !== 'histogramme' ? numCols.concat(cols.filter((c) => !numCols.includes(c))) : cols}
                        value={spec.x || null}
                        onChange={(v) => set({ x: v || undefined })}
                      />
                    )}
                    {(spec.type === 'boites' || spec.type === 'violons') && (
                      <Select label="Groupes (X, facultatif)" searchable clearable data={cols} value={spec.x || null} onChange={(v) => set({ x: v || undefined })} />
                    )}
                    {raw && spec.type !== 'histogramme' && (
                      <Select label="Axe vertical (Y)" searchable data={numCols} value={spec.y || null} onChange={(v) => set({ y: v || undefined })} />
                    )}
                    {spec.type === 'nuage3d' && <Select label="Profondeur (Z)" searchable data={numCols} value={spec.z || null} onChange={(v) => set({ z: v || undefined })} />}
                    {spec.type === 'bulles' && <Select label="Taille des bulles" searchable data={numCols} value={spec.size || null} onChange={(v) => set({ size: v || undefined })} />}
                    {!raw && (
                      <>
                        <Text size="sm" fw={500}>
                          {spec.type === 'chaleur' || spec.type === 'surface3d' ? 'Valeur (couleur / hauteur)' : 'Mesures'}
                        </Text>
                        {spec.measures.map((m, i) => (
                          <Paper key={i} withBorder p={6}>
                            <Group gap={4} wrap="nowrap">
                              <Select size="xs" w={130} data={AGGS.filter((a) => a.value !== 'premier')} value={m.agg} onChange={(v) => set({ measures: spec.measures.map((x, j) => (j === i ? { ...x, agg: v || 'somme' } : x)) })} />
                              {m.agg !== 'nombre_lignes' && (
                                <Select
                                  size="xs"
                                  style={{ flex: 1 }}
                                  searchable
                                  placeholder="Colonne"
                                  data={['nombre', 'nombre_distinct'].includes(m.agg) ? cols : numCols}
                                  value={m.column || null}
                                  onChange={(v) => set({ measures: spec.measures.map((x, j) => (j === i ? { ...x, column: v || undefined } : x)) })}
                                />
                              )}
                              {spec.measures.length > 1 && (
                                <ActionIcon variant="subtle" color="red" onClick={() => set({ measures: spec.measures.filter((_, j) => j !== i) })}>
                                  <IconTrash size={14} />
                                </ActionIcon>
                              )}
                            </Group>
                            {['barres', 'barres_h', 'lignes', 'combine', 'aires'].includes(spec.type) && (
                              <Stack gap={4} mt={4}>
                                <Group gap={4} wrap="nowrap">
                                  {spec.type !== 'barres_h' && (
                                    <Select size="xs" style={{ flex: 1 }} aria-label="Forme" data={MARKS} value={markOf(spec, m)} onChange={(v) => v && setM(i, { mark: v as any })} allowDeselect={false} />
                                  )}
                                  {spec.type !== 'barres_h' && (
                                    <Select size="xs" style={{ flex: 1 }} aria-label="Axe" data={AXES} value={m.axis || 'y'} onChange={(v) => v && setM(i, { axis: v as AxisId })} allowDeselect={false} />
                                  )}
                                </Group>
                                <Group gap={6} wrap="nowrap" justify="space-between">
                                  {!spec.series ? (
                                    <Group gap={3} wrap="nowrap">
                                      {theme.palette.map((c, ci) => {
                                        const cur = m.color || theme.palette[i % theme.palette.length];
                                        return (
                                          <ColorSwatch key={c} component="button" type="button" color={c} size={16} aria-label={`Couleur ${ci + 1}`} onClick={() => setM(i, { color: c })} style={{ cursor: 'pointer', color: '#fff' }}>
                                            {cur === c && <CheckIcon style={{ width: 9, height: 9 }} />}
                                          </ColorSwatch>
                                        );
                                      })}
                                    </Group>
                                  ) : (
                                    <Text size="xs" c="dimmed">Couleurs : une par valeur de série</Text>
                                  )}
                                </Group>
                                <Group gap="sm">
                                  {['lignes', 'points', 'aires'].includes(markOf(spec, m)) && markOf(spec, m) !== 'points' && (
                                    <Switch size="xs" label="Tirets" checked={!!m.dash} onChange={(e) => setM(i, { dash: e.currentTarget.checked })} />
                                  )}
                                  <Switch size="xs" label="Valeurs" checked={!!m.show_values} onChange={(e) => setM(i, { show_values: e.currentTarget.checked })} />
                                </Group>
                              </Stack>
                            )}
                          </Paper>
                        ))}
                        {['barres', 'barres_h', 'lignes', 'aires', 'combine'].includes(spec.type) && (
                          <Button size="xs" variant="default" leftSection={<IconPlus size={14} />} onClick={() => set({ measures: [...spec.measures, { agg: 'somme', axis: spec.measures.length && spec.type !== 'barres_h' ? 'y2' : 'y', mark: spec.type === 'barres_h' ? 'barres' : 'lignes' }] })}>
                            Ajouter une mesure
                          </Button>
                        )}
                      </>
                    )}
                    {spec.type !== 'secteurs' && spec.type !== 'histogramme' && (
                      <Select
                        label={spec.type === 'chaleur' || spec.type === 'surface3d' ? 'Axe vertical (Y)' : 'Couleur / séries'}
                        searchable
                        clearable
                        data={cols}
                        value={spec.series || null}
                        onChange={(v) => set({ series: v || undefined })}
                      />
                    )}
                    {!['nuage3d', 'surface3d'].includes(spec.type) && (
                      <Select
                        label="Petits multiples (un panneau par…)"
                        description="Plus lisible que de tout superposer"
                        searchable
                        clearable
                        data={cols}
                        value={spec.facet || null}
                        onChange={(v) => set({ facet: v || undefined })}
                      />
                    )}
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
              <Accordion.Item value="filtres">
                <Accordion.Control>Filtres du graphique</Accordion.Control>
                <Accordion.Panel>
                  {dsId && (
                    <Conditions
                      value={{ conditions: spec.filters, logic: 'and' }}
                      onChange={(v) => set({ filters: v.conditions || [] })}
                      columns={columns}
                      datasetId={dsId}
                    />
                  )}
                  <Text size="xs" c="dimmed" mt={4}>
                    Ces filtres ne concernent que ce graphique (ils sont indiqués dans sa fiche méthode).
                  </Text>
                </Accordion.Panel>
              </Accordion.Item>
              <Accordion.Item value="axes">
                <Accordion.Control>Axes et échelles</Accordion.Control>
                <Accordion.Panel>
                  <Stack gap="xs">
                    {['barres', 'barres_h', 'aires', 'combine'].includes(spec.type) && (
                      <SegmentedControl
                        size="xs"
                        value={spec.stack || 'groupe'}
                        onChange={(v) => set({ stack: v as any })}
                        data={[
                          { value: 'groupe', label: 'Côte à côte' },
                          { value: 'empile', label: 'Empilé' },
                          { value: 'pourcent', label: '100 %' },
                        ]}
                      />
                    )}
                    <TextInput size="xs" label="Titre de l’axe horizontal" placeholder={spec.x} value={spec.x_title ?? ''} onChange={(e) => set({ x_title: e.currentTarget.value || undefined })} />
                    {usedAxes(spec).map((a) => {
                      const c = axisCfg(spec, a);
                      return (
                        <Paper key={a} withBorder p={6}>
                          <Text size="xs" fw={600} mb={4}>
                            {spec.type === 'barres_h' ? 'Axe des valeurs' : AXES.find((x) => x.value === a)?.label}
                          </Text>
                          <Stack gap={4}>
                            <TextInput size="xs" placeholder="Titre avec l’unité, ex. Débarquements (t)" value={c.title ?? ''} onChange={(e) => setAxis(a, { title: e.currentTarget.value })} />
                            <SegmentedControl size="xs" value={c.scale || 'lineaire'} onChange={(v) => setAxis(a, { scale: v as any })} data={[{ value: 'lineaire', label: 'Linéaire' }, { value: 'log', label: 'Logarithmique' }]} />
                            <Group grow gap={4}>
                              <NumberInput size="xs" placeholder="Min auto" value={c.min ?? ''} onChange={(v) => setAxis(a, { min: v === '' ? null : Number(v) })} />
                              <NumberInput size="xs" placeholder="Max auto" value={c.max ?? ''} onChange={(v) => setAxis(a, { max: v === '' ? null : Number(v) })} />
                              <TextInput size="xs" placeholder="Unité (t, €, %)" value={c.suffix ?? ''} onChange={(e) => setAxis(a, { suffix: e.currentTarget.value || undefined })} />
                            </Group>
                          </Stack>
                        </Paper>
                      );
                    })}
                    {!raw && (
                      <Select
                        size="xs"
                        label="Ordre des catégories"
                        data={[
                          { value: 'aucun', label: 'Naturel (alphabétique / chronologique)' },
                          { value: 'valeur_desc', label: 'Valeur décroissante' },
                          { value: 'valeur_asc', label: 'Valeur croissante' },
                        ]}
                        value={spec.sort || 'aucun'}
                        onChange={(v) => set({ sort: v as any })}
                      />
                    )}
                    {spec.type.startsWith('barres') && <Switch size="xs" label="Afficher les valeurs" checked={!!spec.show_values} onChange={(e) => set({ show_values: e.currentTarget.checked })} />}
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
              {!raw && !['secteurs', 'chaleur', 'surface3d'].includes(spec.type) && (
                <Accordion.Item value="reperes">
                  <Accordion.Control>Repères et annotations</Accordion.Control>
                  <Accordion.Panel>
                    <Stack gap="xs">
                      {(spec.refs || []).map((r, i) => (
                        <Paper key={i} withBorder p={6}>
                          <Group gap={4} wrap="nowrap">
                            <Select
                              size="xs"
                              style={{ flex: 1 }}
                              data={[
                                { value: 'ligne_h', label: spec.type === 'barres_h' ? 'Ligne de valeur' : 'Ligne horizontale (seuil, quota, moyenne)' },
                                { value: 'ligne_v', label: 'Ligne sur une catégorie (date, événement)' },
                                { value: 'zone_v', label: 'Zone entre deux catégories (période)' },
                                { value: 'note', label: 'Note sur une catégorie' },
                              ]}
                              value={r.kind}
                              onChange={(v) => v && setRef(i, { kind: v as any, value: null, value2: null })}
                              allowDeselect={false}
                            />
                            <ActionIcon variant="subtle" color="red" onClick={() => set({ refs: (spec.refs || []).filter((_, j) => j !== i) })}>
                              <IconTrash size={14} />
                            </ActionIcon>
                          </Group>
                          <Group gap={4} mt={4} grow>
                            {r.kind === 'ligne_h' ? (
                              <NumberInput size="xs" placeholder="Valeur" value={(r.value as any) ?? ''} onChange={(v) => setRef(i, { value: v === '' ? null : Number(v) })} />
                            ) : (
                              <Select size="xs" searchable placeholder={r.kind === 'zone_v' ? 'Début' : 'Catégorie'} data={xValues} value={r.value == null ? null : String(r.value)} onChange={(v) => setRef(i, { value: v })} />
                            )}
                            {r.kind === 'zone_v' && <Select size="xs" searchable placeholder="Fin" data={xValues} value={r.value2 ?? null} onChange={(v) => setRef(i, { value2: v })} />}
                            {r.kind === 'ligne_h' && usedAxes(spec).length > 1 && (
                              <Select size="xs" data={AXES.filter((x) => usedAxes(spec).includes(x.value))} value={r.axis || 'y'} onChange={(v) => v && setRef(i, { axis: v as AxisId })} allowDeselect={false} />
                            )}
                          </Group>
                          <TextInput size="xs" mt={4} placeholder={r.kind === 'note' ? 'Texte de la note' : 'Libellé (facultatif)'} value={r.label ?? ''} onChange={(e) => setRef(i, { label: e.currentTarget.value })} />
                        </Paper>
                      ))}
                      <Button size="xs" variant="default" leftSection={<IconPlus size={14} />} onClick={() => set({ refs: [...(spec.refs || []), { kind: 'ligne_h', value: null, label: '' }] })}>
                        Ajouter un repère
                      </Button>
                      <Text size="xs" c="dimmed">
                        Quota ou seuil, moyenne de référence, période de fermeture, événement (tempête, changement de réglementation)…
                      </Text>
                    </Stack>
                  </Accordion.Panel>
                </Accordion.Item>
              )}
              <Accordion.Item value="mise_en_page">
                <Accordion.Control>Mise en page</Accordion.Control>
                <Accordion.Panel>
                  <Stack gap="xs">
                    <Select
                      size="xs"
                      label="Format"
                      placeholder="Personnalisé"
                      data={SIZE_PRESETS.map((p) => ({ value: p.value, label: `${p.label} (${p.width} × ${p.height})` }))}
                      value={SIZE_PRESETS.find((p) => p.width === spec.template.width && p.height === spec.template.height)?.value || null}
                      onChange={(v) => {
                        const p = SIZE_PRESETS.find((x) => x.value === v);
                        if (p) setT({ width: p.width, height: p.height });
                      }}
                    />
                    <Group grow>
                      <NumberInput size="xs" label="Largeur (px)" min={400} max={3000} value={spec.template.width} onChange={(v) => setT({ width: Number(v) || 1100 })} />
                      <NumberInput size="xs" label="Hauteur (px)" min={300} max={2000} value={spec.template.height} onChange={(v) => setT({ height: Number(v) || 620 })} />
                    </Group>
                    <Select
                      size="xs"
                      label="Légende"
                      data={[
                        { value: 'haut', label: 'En haut' },
                        { value: 'droite', label: 'À droite' },
                        { value: 'bas', label: 'En bas' },
                        { value: 'aucune', label: 'Masquée' },
                      ]}
                      value={spec.legend || 'haut'}
                      onChange={(v) => v && set({ legend: v as any })}
                      allowDeselect={false}
                    />
                    <NumberInput size="xs" label="Décimales (infobulles et valeurs)" min={0} max={4} value={spec.decimals ?? 2} onChange={(v) => set({ decimals: v === '' ? null : Number(v) })} />
                    {spec.facet && (
                      <>
                        <SegmentedControl
                          size="xs"
                          value={spec.facet_scale || 'independante'}
                          onChange={(v) => set({ facet_scale: v as any })}
                          data={[
                            { value: 'commune', label: 'Échelle commune' },
                            { value: 'independante', label: 'Échelles indépendantes' },
                          ]}
                        />
                        <NumberInput size="xs" label="Panneaux par ligne" placeholder="auto" min={1} max={8} value={spec.facet_cols ?? ''} onChange={(v) => set({ facet_cols: v === '' ? null : Number(v) })} />
                      </>
                    )}
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
              <Accordion.Item value="gabarit">
                <Accordion.Control>Titre, source, auteur</Accordion.Control>
                <Accordion.Panel>
                  <Stack gap="xs">
                    <TextInput size="xs" label="Titre" placeholder="Ce que montre le graphique" value={spec.template.title} onChange={(e) => setT({ title: e.currentTarget.value })} />
                    <TextInput size="xs" label="Sous-titre" placeholder="Périmètre, période, unité" value={spec.template.subtitle} onChange={(e) => setT({ subtitle: e.currentTarget.value })} />
                    <TextInput size="xs" label="Source" placeholder="ex. SACROIS – DGAMPA, traitement CRPM" value={spec.template.source} onChange={(e) => setT({ source: e.currentTarget.value })} />
                    <TextInput size="xs" label="Auteur" value={spec.template.author} onChange={(e) => setT({ author: e.currentTarget.value })} />
                    <Textarea size="xs" label="Note de lecture" autosize value={spec.template.caption} onChange={(e) => setT({ caption: e.currentTarget.value })} />
                    <Group>
                      <Switch size="xs" label="Date" checked={spec.template.show_date} onChange={(e) => setT({ show_date: e.currentTarget.checked })} />
                      <Switch size="xs" label="Logo" checked={spec.template.show_logo} disabled={!structure?.has_logo} onChange={(e) => setT({ show_logo: e.currentTarget.checked })} />
                    </Group>
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
            </Accordion>
          </Stack>
        </ScrollArea>
      </Paper>

      <Stack style={{ minWidth: 0, minHeight: 0 }} gap="sm">
        <Group justify="space-between">
          <Text size="sm" c="dimmed">
            {data ? (raw ? `${fmtNumber(data.rows.length)} points` : `${fmtNumber(data.rows.length)} valeurs agrégées`) : ''}
            {loading && <Loader size="xs" ml={6} />}
          </Text>
          <Group gap="xs">
            <Tooltip label="Voir les chiffres sous forme de tableau">
              <Button size="xs" variant="default" leftSection={<IconTable size={14} />} disabled={!data} onClick={() => setShowTable(true)}>
                Tableau
              </Button>
            </Tooltip>
            <Button size="xs" variant="default" leftSection={<IconFileText size={14} />} disabled={!figure} onClick={exportMethod}>
              Fiche méthode
            </Button>
            {canWrite && (
              <Button size="xs" variant="default" leftSection={<IconDeviceFloppy size={14} />} disabled={!figure} onClick={save}>
                Enregistrer
              </Button>
            )}
            <Menu withinPortal position="bottom-end">
              <Menu.Target>
                <Button size="xs" leftSection={<IconPhoto size={14} />} disabled={!figure}>
                  Exporter l’image
                </Button>
              </Menu.Target>
              <Menu.Dropdown>
                <Menu.Item leftSection={<IconPhoto size={14} />} onClick={() => exportImage('png')}>
                  PNG haute définition
                </Menu.Item>
                <Menu.Item leftSection={<IconVectorBezier size={14} />} onClick={() => exportImage('svg')}>
                  SVG (vectoriel, pour retouche)
                </Menu.Item>
              </Menu.Dropdown>
            </Menu>
          </Group>
        </Group>
        {advice.length > 0 && figure && (
          <Alert color="blue" variant="light" p="xs" icon={<IconBulb size={18} />}>
            {advice.map((a) => (
              <Text size="xs" key={a}>
                {a}
              </Text>
            ))}
          </Alert>
        )}
        {err && <Alert color="red">{err}</Alert>}
        <ScrollArea style={{ flex: 1 }} type="auto">
          {!dsId ? (
            <Center h={300}>
              <Text c="dimmed">Choisissez un jeu de données.</Text>
            </Center>
          ) : !ready ? (
            <Center h={300}>
              <Text c="dimmed">Complétez les champs « Données représentées » pour afficher le graphique.</Text>
            </Center>
          ) : (
            <div className="mo-chart-frame" style={{ width: spec.template.width, height: spec.template.height }}>
              <div ref={plotRef} />
            </div>
          )}
        </ScrollArea>
      </Stack>

      <Modal opened={showTable} onClose={() => setShowTable(false)} title="Données du graphique" size="xl">
        {data && (
          <ScrollArea h={500}>
            <Table fz="sm" striped withTableBorder>
              <Table.Thead>
                <Table.Tr>
                  {data.columns.map((c: string, i: number) => {
                    const mi = i - (data.columns.length - spec.measures.length);
                    return <Table.Th key={c}>{!raw && mi >= 0 ? measureLabel(spec.measures[mi]) : c}</Table.Th>;
                  })}
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {data.rows.slice(0, 2000).map((r: any[], i: number) => (
                  <Table.Tr key={i}>
                    {r.map((v, j) => (
                      <Table.Td key={j}>{fmtNumber(v)}</Table.Td>
                    ))}
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </ScrollArea>
        )}
      </Modal>
    </div>
  );
}
