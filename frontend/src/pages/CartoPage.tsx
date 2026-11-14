import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  Accordion,
  ActionIcon,
  Alert,
  Badge,
  Button,
  ColorInput,
  Divider,
  Group,
  Loader,
  Menu,
  Modal,
  NumberInput,
  Paper,
  ScrollArea,
  SegmentedControl,
  Select,
  Slider,
  Stack,
  Switch,
  Text,
  TextInput,
  Title,
  Tooltip,
} from '@mantine/core';
import {
  IconArrowDown,
  IconArrowUp,
  IconChevronDown,
  IconDeviceFloppy,
  IconDownload,
  IconEye,
  IconEyeOff,
  IconFocus2,
  IconLayersSubtract,
  IconPhoto,
  IconFileText,
  IconPlus,
  IconTrash,
  IconUpload,
} from '@tabler/icons-react';
import 'maplibre-gl/dist/maplibre-gl.css';
import { api, download, downloadPost, saveBlob } from '../lib/api';
import { useAuth } from '../lib/auth';
import {
  AggParams,
  apiUrl,
  BASEMAPS,
  CatalogLayer,
  catScale,
  colorExpr,
  composeMapImage,
  defaultMapSpec,
  fmtN,
  guessLat,
  guessLon,
  guessRect,
  guessVessel,
  LAND,
  legendItems,
  MapLayer,
  MapSpec,
  numScale,
  scaleBar,
  SEA,
  styleFor,
  uid,
} from '../lib/carto';
import { fail, ok } from '../lib/notify';
import { NEUTRAL } from '../lib/theme';
import type { Column, DatasetSummary } from '../lib/types';
import LayerImportModal from '../components/LayerImportModal';

let maplibrePromise: Promise<any> | null = null;
const loadMaplibre = () => (maplibrePromise ??= import('maplibre-gl').then((m) => m.default || m));

interface SavedMap {
  id: string;
  name: string;
  spec: MapSpec;
}

/** Données d'exécution d'une couche (non enregistrées) : clé des tuiles de points, GeoJSON des mailles. */
interface Runtime {
  key?: string;
  geojson?: any;
  info?: string;
  masked?: number;
  summary?: { min: number | null; max: number | null; quantiles: (number | null)[] };
  error?: string;
  loading?: boolean;
}

const AGG_LABELS: Record<string, string> = {
  nombre: 'Nombre de positions / lignes',
  somme: 'Somme',
  moyenne: 'Moyenne',
  max: 'Maximum',
  navires: 'Nombre de navires distincts',
};

const escapeHtml = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export default function CartoPage() {
  const { me, structure } = useAuth();
  const theme = structure?.theme || NEUTRAL;
  const [params, setParams] = useSearchParams();
  const [spec, setSpec] = useState<MapSpec>(() => defaultMapSpec(me?.display_name || '', theme.chart.default_source));
  const [catalog, setCatalog] = useState<CatalogLayer[]>([]);
  const [notes, setNotes] = useState<any>({});
  const [datasets, setDatasets] = useState<DatasetSummary[]>([]);
  const [runtime, setRuntime] = useState<Record<string, Runtime>>({});
  const [saved, setSaved] = useState<SavedMap[]>([]);
  const [current, setCurrent] = useState<SavedMap | null>(null);
  const [status, setStatus] = useState<{ ok: boolean; message?: string; vitesses?: any } | null>(null);
  const [addCtx, setAddCtx] = useState(false);
  const [addData, setAddData] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [manage, setManage] = useState(false);
  const [mapReady, setMapReady] = useState(false);
  const [scale, setScale] = useState<{ px: number; label: string } | null>(null);
  const mapRef = useRef<any>(null);
  const boxRef = useRef<HTMLDivElement>(null);
  const logoUrl = structure?.has_logo ? `/api/structures/${structure.id}/logo` : null;
  const canWrite = structure?.role === 'admin' || structure?.role === 'analyste' || me?.is_superadmin;

  const loadCatalog = useCallback(() => {
    api.get('/api/geo/layers').then((r) => { setCatalog(r.couches); setNotes(r.notes || {}); }).catch(fail);
  }, []);

  useEffect(() => {
    api.get('/api/geo/status').then(setStatus).catch(() => setStatus({ ok: false }));
    loadCatalog();
    api.get<DatasetSummary[]>('/api/datasets').then(setDatasets).catch(fail);
    api.get<SavedMap[]>('/api/geo/maps').then(setSaved).catch(() => setSaved([]));
  }, [structure?.id, loadCatalog]);

  const setT = (patch: Partial<MapSpec['template']>) => setSpec((s) => ({ ...s, template: { ...s.template, ...patch } }));
  const setLayer = (u: string, patch: Partial<MapLayer>) => setSpec((s) => ({ ...s, layers: s.layers.map((l) => (l.uid === u ? { ...l, ...patch } : l)) }));
  const setStyle = (u: string, patch: Partial<MapLayer['style']>) =>
    setSpec((s) => ({ ...s, layers: s.layers.map((l) => (l.uid === u ? { ...l, style: { ...l.style, ...patch } } : l)) }));

  // ------------------------------------------------------------------ carte MapLibre
  useEffect(() => {
    let disposed = false;
    loadMaplibre().then((maplibregl) => {
      if (disposed || !boxRef.current) return;
      const map = new maplibregl.Map({
        container: boxRef.current,
        style: { version: 8, sources: {}, layers: [{ id: 'mo-fond', type: 'background', paint: { 'background-color': SEA } }] },
        center: spec.center,
        zoom: spec.zoom,
        preserveDrawingBuffer: true,
        attributionControl: { compact: true },
        maxZoom: 18,
      });
      map.addControl(new maplibregl.NavigationControl({ showCompass: true }), 'top-right');
      map.on('load', () => { setMapReady(true); setScale(scaleBar(map)); });
      map.on('moveend', () => {
        setScale(scaleBar(map));
        const c = map.getCenter();
        setSpec((s) => ({ ...s, center: [Math.round(c.lng * 1e4) / 1e4, Math.round(c.lat * 1e4) / 1e4], zoom: Math.round(map.getZoom() * 100) / 100 }));
      });
      map.on('click', (e: any) => {
        const feats = map.queryRenderedFeatures(e.point).filter((f: any) => String(f.layer.id).startsWith('mo-l-'));
        if (!feats.length) return;
        const f = feats[0];
        const title = f.layer.metadata?.title || '';
        const rows = Object.entries(f.properties || {})
          .filter(([k]) => !k.startsWith('__'))
          .slice(0, 30)
          .map(([k, v]) => `<tr><th>${escapeHtml(k)}</th><td>${escapeHtml(typeof v === 'number' ? fmtN(v) : String(v ?? ''))}</td></tr>`)
          .join('');
        new maplibregl.Popup({ maxWidth: '360px' })
          .setLngLat(e.lngLat)
          .setHTML(`<div class="mo-popup"><b>${escapeHtml(title)}</b><table>${rows}</table></div>`)
          .addTo(map);
      });
      map.on('mousemove', (e: any) => {
        const hit = map.queryRenderedFeatures(e.point).some((f: any) => String(f.layer.id).startsWith('mo-l-'));
        map.getCanvas().style.cursor = hit ? 'pointer' : '';
      });
      mapRef.current = map;
    });
    return () => {
      disposed = true;
      mapRef.current?.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ------------------------------------------------------------------ données d'exécution (points, mailles)
  const prepare = useCallback(async (l: MapLayer) => {
    if (l.kind === 'couche') return;
    setRuntime((r) => ({ ...r, [l.uid]: { ...r[l.uid], loading: true, error: undefined } }));
    try {
      if (l.kind === 'points') {
        const p = await api.post(`/api/geo/datasets/${l.datasetId}/points`, { lon: l.lon, lat: l.lat });
        const info = `${fmtN(p.n)} positions${p.ignored ? ` (${fmtN(p.ignored)} sans coordonnées valides ignorées)` : ''}`;
        setRuntime((r) => ({ ...r, [l.uid]: { key: p.key, info } }));
      } else {
        const a = l.agg!;
        const res = await api.post(`/api/geo/datasets/${l.datasetId}/aggregate`, { ...a, lon: l.lon, lat: l.lat });
        const info = `${fmtN(res.n)} ${a.mode === 'ciem' ? 'rectangles' : 'mailles'} · total ${fmtN(res.total)}${res.masquees ? ` · ${res.masquees} masquée(s) (secret)` : ''}`;
        setRuntime((r) => ({ ...r, [l.uid]: { geojson: res.geojson, info, masked: res.masquees, summary: { min: res.min, max: res.max, quantiles: res.quantiles } } }));
        // échelle de couleurs par défaut sur la valeur
        setSpec((s) => ({
          ...s,
          layers: s.layers.map((x) =>
            x.uid === l.uid && (!x.style.scale || x.style.scale.column === 'valeur')
              ? { ...x, style: { ...x.style, scale: numScale('valeur', res.quantiles || [], theme.sequential, res.min, res.max) } }
              : x,
          ),
        }));
      }
    } catch (e: any) {
      setRuntime((r) => ({ ...r, [l.uid]: { error: e.message } }));
    }
  }, [theme.sequential]);

  // ------------------------------------------------------------------ synchronisation du style MapLibre
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !mapReady) return;
    const style = map.getStyle();
    for (const ly of style.layers) if (ly.id.startsWith('mo-')) map.removeLayer(ly.id);
    map.addLayer({ id: 'mo-fond', type: 'background', paint: { 'background-color': spec.basemap === 'aucun' ? '#ffffff' : SEA } });
    const ensureSource = (id: string, src: any) => {
      const cur = map.getSource(id);
      if (cur && src.type === 'geojson') {
        cur.setData(src.data);
        return;
      }
      if (!cur) map.addSource(id, src);
    };
    if (spec.basemap === 'ign' || spec.basemap === 'osm') {
      const url = spec.basemap === 'ign'
        ? 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      ensureSource(`fond-${spec.basemap}`, {
        type: 'raster', tiles: [url], tileSize: 256, maxzoom: spec.basemap === 'ign' ? 18 : 19,
        attribution: BASEMAPS.find((b) => b.value === spec.basemap)!.attribution,
      });
      map.addLayer({ id: 'mo-fond-raster', type: 'raster', source: `fond-${spec.basemap}`, paint: { 'raster-opacity': 0.85 } });
    } else if (spec.basemap === 'horsligne') {
      ensureSource('fond-terres', { type: 'vector', tiles: [apiUrl('/api/geo/layers/ctx:terres/tiles/{z}/{x}/{y}.pbf')], maxzoom: 12, attribution: 'Natural Earth' });
      map.addLayer({ id: 'mo-fond-terres', type: 'fill', source: 'fond-terres', 'source-layer': 'couche', paint: { 'fill-color': LAND, 'fill-outline-color': '#b8b2a5' } });
    }
    // couches de l'utilisateur : la première de la liste est dessinée au-dessus
    [...spec.layers].reverse().forEach((l) => {
      const rt = runtime[l.uid];
      let srcId: string | null = null;
      let srcLayer: string | undefined;
      if (l.kind === 'couche' && l.layerId) {
        srcId = `src-${l.layerId}`;
        ensureSource(srcId, { type: 'vector', tiles: [apiUrl(`/api/geo/layers/${l.layerId}/tiles/{z}/{x}/{y}.pbf`)], maxzoom: 14 });
        srcLayer = 'couche';
      } else if (l.kind === 'points' && rt?.key) {
        srcId = `src-pts-${rt.key}`;
        ensureSource(srcId, { type: 'vector', tiles: [apiUrl(`/api/geo/points/${rt.key}/tiles/{z}/{x}/{y}.pbf`)], maxzoom: 14 });
        srcLayer = 'couche';
      } else if (l.kind === 'agregat' && rt?.geojson) {
        srcId = `src-agg-${l.uid}`;
        ensureSource(srcId, { type: 'geojson', data: rt.geojson });
      }
      if (!srcId) return;
      const s = l.style;
      const vis = l.visible ? 'visible' : 'none';
      const base: any = { source: srcId, layout: { visibility: vis }, metadata: { title: l.title } };
      if (srcLayer) base['source-layer'] = srcLayer;
      if (s.minzoom) base.minzoom = s.minzoom;
      const color = l.kind === 'agregat' ? ['case', ['==', ['get', 'secret'], true], '#d0d0d0', colorExpr(s)] : colorExpr(s);
      if (l.geom === 'polygone') {
        map.addLayer({ ...base, id: `mo-l-${l.uid}-f`, type: 'fill', paint: { 'fill-color': color, 'fill-opacity': s.fill * s.opacity } });
        map.addLayer({ ...base, id: `mo-l-${l.uid}-l`, type: 'line', paint: { 'line-color': l.kind === 'agregat' ? 'rgba(255,255,255,0.6)' : color, 'line-width': s.width, 'line-opacity': s.opacity, ...(s.dashed ? { 'line-dasharray': [3, 2] } : {}) } });
      } else if (l.geom === 'ligne') {
        map.addLayer({ ...base, id: `mo-l-${l.uid}`, type: 'line', paint: { 'line-color': color, 'line-width': s.width, 'line-opacity': s.opacity, ...(s.dashed ? { 'line-dasharray': [3, 2] } : {}) } });
      } else {
        map.addLayer({ ...base, id: `mo-l-${l.uid}`, type: 'circle', paint: {
          'circle-color': color, 'circle-opacity': s.opacity, 'circle-stroke-color': '#ffffff', 'circle-stroke-width': s.width,
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 4, Math.max(1.2, s.radius * 0.5), 10, s.radius, 14, s.radius * 1.6],
        } });
      }
    });
    // nettoyage des sources devenues inutiles
    const used = new Set(map.getStyle().layers.map((x: any) => x.source).filter(Boolean));
    for (const id of Object.keys(map.getStyle().sources)) if (!used.has(id)) map.removeSource(id);
  }, [spec.layers, spec.basemap, runtime, mapReady]);

  // prépare les couches de jeux de données à l'ouverture d'une carte
  useEffect(() => {
    spec.layers.forEach((l) => {
      if (l.kind !== 'couche' && !runtime[l.uid]) prepare(l);
    });
  }, [spec.layers, runtime, prepare]);

  const fit = (bbox: (number | null)[] | null | undefined) => {
    if (!bbox || bbox[0] == null || !mapRef.current) return;
    const [x0, y0, x1, y1] = bbox as number[];
    if (x0 === x1 && y0 === y1) mapRef.current.flyTo({ center: [x0, y0], zoom: 9 });
    else mapRef.current.fitBounds([[Math.max(-179, x0), Math.max(-85, y0)], [Math.min(179, x1), Math.min(85, y1)]], { padding: 40, maxZoom: 11, duration: 600 });
  };

  const fitLayer = (l: MapLayer) => {
    if (l.kind === 'couche') fit(catalog.find((c) => c.id === l.layerId)?.bbox);
    else if (l.kind === 'agregat') {
      const fc = runtime[l.uid]?.geojson;
      if (fc?.features?.length) {
        let x0 = 180, y0 = 90, x1 = -180, y1 = -90;
        for (const f of fc.features) for (const ring of f.geometry?.coordinates || []) for (const [x, y] of ring) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
        fit([x0, y0, x1, y1]);
      }
    } else {
      const key = runtime[l.uid]?.key;
      if (key) api.post(`/api/geo/datasets/${l.datasetId}/points`, { lon: l.lon, lat: l.lat }).then((p) => fit(p.bbox)).catch(fail);
    }
  };

  // ------------------------------------------------------------------ ajout de couches
  const addCatalogLayer = (c: CatalogLayer) => {
    const l: MapLayer = {
      uid: uid(), kind: 'couche', title: c.nom, visible: true, geom: c.kind, layerId: c.id,
      style: { ...styleFor(c.kind, theme.palette[spec.layers.length % theme.palette.length], c.style), minzoom: c.id === 'ctx:ciem_rectangles' ? 4 : undefined },
    };
    setSpec((s) => ({ ...s, layers: [l, ...s.layers] }));
    if (!c.integree) fit(c.bbox);
  };

  // ouverture d'une carte enregistrée (?map=…), depuis l'accueil
  const mapParam = params.get('map');
  useEffect(() => {
    if (mapParam && saved.some((m) => m.id === mapParam) && current?.id !== mapParam && mapRef.current) openMap(mapParam);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapParam, saved, mapReady]);

  // ouverture depuis un jeu de données (?dataset=…)
  const dsParam = params.get('dataset');
  useEffect(() => {
    if (!dsParam) return;
    setAddData(true);
  }, [dsParam]);

  // ------------------------------------------------------------------ enregistrement
  const saveMap = async (asNew: boolean) => {
    const name = asNew || !current ? prompt('Nom de la carte', spec.template.title || 'Nouvelle carte') : current.name;
    if (!name) return;
    try {
      const m = asNew || !current ? await api.post<SavedMap>('/api/geo/maps', { name, spec }) : await api.put<SavedMap>(`/api/geo/maps/${current.id}`, { name, spec });
      setCurrent(m);
      setSaved((l) => [m, ...l.filter((x) => x.id !== m.id)]);
      ok('Carte enregistrée.');
    } catch (e) {
      fail(e);
    }
  };

  const openMap = (id: string | null) => {
    const m = saved.find((x) => x.id === id) || null;
    setCurrent(m);
    if (!m) return;
    setRuntime({});
    setSpec(m.spec);
    mapRef.current?.jumpTo({ center: m.spec.center, zoom: m.spec.zoom });
  };

  const exportPng = async () => {
    const map = mapRef.current;
    if (!map) return;
    try {
      const masked = Object.fromEntries(spec.layers.map((l) => [l.uid, !!runtime[l.uid]?.masked]));
      const blob = await composeMapImage(map, spec, theme, { logoUrl, masked, attribution: BASEMAPS.find((b) => b.value === spec.basemap)?.attribution || '' });
      saveBlob(blob, `${(spec.template.title || 'carte').replace(/[^\w-]+/g, '_')}.png`);
    } catch (e) {
      fail(e, 'Export impossible (le fond de carte en ligne bloque peut-être la copie : essayez le fond hors ligne)');
    }
  };

  const exportMethod = async () => {
    const map = mapRef.current;
    let png: string | undefined;
    try {
      if (map) {
        const masked = Object.fromEntries(spec.layers.map((l) => [l.uid, !!runtime[l.uid]?.masked]));
        const blob = await composeMapImage(map, spec, theme, { logoUrl, masked, attribution: BASEMAPS.find((b) => b.value === spec.basemap)?.attribution || '' });
        png = await new Promise<string>((ok_, ko) => {
          const r = new FileReader();
          r.onload = () => ok_(String(r.result));
          r.onerror = ko;
          r.readAsDataURL(blob);
        });
      }
    } catch {
      png = undefined; // fond en ligne non copiable : la fiche est produite sans l'image
    }
    try {
      await downloadPost('/api/geo/maps/method.zip', { name: spec.template.title || current?.name || 'carte', spec, png }, 'carte_methode.zip');
    } catch (e) {
      fail(e);
    }
  };

  const visibleLegend = spec.layers.filter((l) => l.visible);

  return (
    <Stack gap="sm" h="calc(100vh - 90px)">
      <Group justify="space-between">
        <Group gap="xs">
          <Title order={3}>Cartographie</Title>
          <Select size="xs" w={220} placeholder="Cartes enregistrées" clearable data={saved.map((m) => ({ value: m.id, label: m.name }))} value={current?.id || null} onChange={openMap} />
        </Group>
        <Group gap="xs">
          {canWrite && (
            <Menu>
              <Menu.Target>
                <Button size="xs" variant="default" leftSection={<IconDeviceFloppy size={16} />} rightSection={<IconChevronDown size={14} />}>
                  Enregistrer
                </Button>
              </Menu.Target>
              <Menu.Dropdown>
                <Menu.Item onClick={() => saveMap(false)}>{current ? `Mettre à jour « ${current.name} »` : 'Enregistrer'}</Menu.Item>
                <Menu.Item onClick={() => saveMap(true)}>Enregistrer sous…</Menu.Item>
                {current && (
                  <Menu.Item color="red" onClick={async () => { if (confirm('Supprimer cette carte ?')) { await api.del(`/api/geo/maps/${current.id}`); setSaved((l) => l.filter((x) => x.id !== current.id)); setCurrent(null); } }}>
                    Supprimer la carte
                  </Menu.Item>
                )}
              </Menu.Dropdown>
            </Menu>
          )}
          <Button size="xs" variant="default" leftSection={<IconFileText size={16} />} onClick={exportMethod} disabled={!mapReady}>
            Fiche méthode
          </Button>
          <Button size="xs" leftSection={<IconPhoto size={16} />} onClick={exportPng} disabled={!mapReady}>
            Exporter en image
          </Button>
        </Group>
      </Group>

      {status && !status.ok && (
        <Alert color="red" title="Module cartographique indisponible">
          {status.message || "L'extension spatiale n'a pas pu être chargée."}
        </Alert>
      )}

      <Group align="stretch" gap="sm" wrap="nowrap" style={{ flex: 1, minHeight: 0 }}>
        {/* panneau des couches */}
        <Paper withBorder w={350} p="xs" style={{ display: 'flex', flexDirection: 'column', minHeight: 0 }}>
          <Group justify="space-between" mb={6}>
            <Text fw={600} size="sm">
              Couches
            </Text>
            <Menu position="bottom-end">
              <Menu.Target>
                <Button size="compact-xs" leftSection={<IconPlus size={14} />}>
                  Ajouter
                </Button>
              </Menu.Target>
              <Menu.Dropdown>
                <Menu.Item onClick={() => setAddCtx(true)} leftSection={<IconLayersSubtract size={16} />}>
                  Couche de contexte ou importée
                </Menu.Item>
                <Menu.Item onClick={() => setAddData(true)} leftSection={<IconPlus size={16} />}>
                  Données d'un jeu (positions, carroyage, rectangles)
                </Menu.Item>
                {canWrite && (
                  <Menu.Item onClick={() => setImportOpen(true)} leftSection={<IconUpload size={16} />}>
                    Importer une couche (SHP, GPKG…)
                  </Menu.Item>
                )}
                <Menu.Divider />
                <Menu.Item onClick={() => setManage(true)}>Gérer les couches importées</Menu.Item>
              </Menu.Dropdown>
            </Menu>
          </Group>
          <ScrollArea style={{ flex: 1 }} type="auto">
            {spec.layers.length === 0 && (
              <Text size="sm" c="dimmed" p="sm">
                Ajoutez une couche : limites maritimes, rectangles CIEM, aires protégées, vos propres couches, ou les positions / mailles d'un jeu de données (VMS, SACROIS).
              </Text>
            )}
            <Accordion multiple variant="separated" chevronPosition="left" styles={{ content: { padding: 8 }, control: { padding: '4px 6px' } }}>
              {spec.layers.map((l, i) => (
                <Accordion.Item key={l.uid} value={l.uid}>
                  <Group gap={2} wrap="nowrap" pr={4}>
                    <Accordion.Control style={{ flex: 1, minWidth: 0 }}>
                      <Group gap={6} wrap="nowrap">
                        <span className="mo-swatch" style={{ background: l.style.scale ? `linear-gradient(90deg, ${l.style.scale.colors.join(',')})` : l.style.color }} />
                        <Text size="sm" truncate>
                          {l.title}
                        </Text>
                        {runtime[l.uid]?.loading && <Loader size={12} />}
                      </Group>
                    </Accordion.Control>
                    <ActionIcon size="sm" variant="subtle" aria-label="Afficher / masquer" onClick={() => setLayer(l.uid, { visible: !l.visible })}>
                      {l.visible ? <IconEye size={15} /> : <IconEyeOff size={15} />}
                    </ActionIcon>
                    <ActionIcon size="sm" variant="subtle" aria-label="Centrer" onClick={() => fitLayer(l)}>
                      <IconFocus2 size={15} />
                    </ActionIcon>
                    <ActionIcon size="sm" variant="subtle" aria-label="Monter" disabled={i === 0} onClick={() => setSpec((s) => { const a = [...s.layers]; [a[i - 1], a[i]] = [a[i], a[i - 1]]; return { ...s, layers: a }; })}>
                      <IconArrowUp size={15} />
                    </ActionIcon>
                    <ActionIcon size="sm" variant="subtle" aria-label="Descendre" disabled={i === spec.layers.length - 1} onClick={() => setSpec((s) => { const a = [...s.layers]; [a[i + 1], a[i]] = [a[i], a[i + 1]]; return { ...s, layers: a }; })}>
                      <IconArrowDown size={15} />
                    </ActionIcon>
                    <ActionIcon size="sm" variant="subtle" color="red" aria-label="Retirer" onClick={() => setSpec((s) => ({ ...s, layers: s.layers.filter((x) => x.uid !== l.uid) }))}>
                      <IconTrash size={15} />
                    </ActionIcon>
                  </Group>
                  <Accordion.Panel>
                    <LayerEditor
                      layer={l}
                      rt={runtime[l.uid]}
                      catalog={catalog}
                      datasets={datasets}
                      palette={theme.palette}
                      seq={theme.sequential}
                      onLayer={(p) => setLayer(l.uid, p)}
                      onStyle={(p) => setStyle(l.uid, p)}
                      onRecompute={(p) => { const nl = { ...l, ...p }; setLayer(l.uid, p); prepare(nl); }}
                    />
                  </Accordion.Panel>
                </Accordion.Item>
              ))}
            </Accordion>
          </ScrollArea>
          <Divider my={6} />
          <Select
            size="xs"
            label="Fond de carte"
            data={BASEMAPS.map((b) => ({ value: b.value, label: b.label }))}
            value={spec.basemap}
            onChange={(v) => v && setSpec((s) => ({ ...s, basemap: v as any }))}
          />
          <Accordion variant="default" mt={4}>
            <Accordion.Item value="tpl">
              <Accordion.Control>
                <Text size="xs" fw={600}>
                  Mise en page (titre, source, logo)
                </Text>
              </Accordion.Control>
              <Accordion.Panel>
                <Stack gap={6}>
                  <TextInput size="xs" label="Titre" value={spec.template.title} onChange={(e) => setT({ title: e.currentTarget.value })} />
                  <TextInput size="xs" label="Sous-titre" value={spec.template.subtitle} onChange={(e) => setT({ subtitle: e.currentTarget.value })} />
                  <TextInput size="xs" label="Source des données" value={spec.template.source} onChange={(e) => setT({ source: e.currentTarget.value })} />
                  <TextInput size="xs" label="Réalisation" value={spec.template.author} onChange={(e) => setT({ author: e.currentTarget.value })} />
                  <Group gap="md">
                    <Switch size="xs" label="Légende" checked={spec.template.show_legend} onChange={(e) => setT({ show_legend: e.currentTarget.checked })} />
                    <Switch size="xs" label="Date" checked={spec.template.show_date} onChange={(e) => setT({ show_date: e.currentTarget.checked })} />
                    <Switch size="xs" label="Logo" disabled={!logoUrl} checked={spec.template.show_logo} onChange={(e) => setT({ show_logo: e.currentTarget.checked })} />
                  </Group>
                </Stack>
              </Accordion.Panel>
            </Accordion.Item>
          </Accordion>
        </Paper>

        {/* carte */}
        <Paper withBorder style={{ flex: 1, position: 'relative', overflow: 'hidden', minWidth: 0 }}>
          {spec.template.title && (
            <div className="mo-map-title">
              <div className="t">{spec.template.title}</div>
              {spec.template.subtitle && <div className="s">{spec.template.subtitle}</div>}
            </div>
          )}
          <div ref={boxRef} style={{ position: 'absolute', inset: 0 }} />
          {!mapReady && (
            <Group justify="center" style={{ position: 'absolute', inset: 0 }}>
              <Loader />
            </Group>
          )}
          {spec.template.show_legend && visibleLegend.length > 0 && (
            <div className="mo-map-legend">
              {visibleLegend.map((l) => {
                const items = legendItems(l, { masked: !!runtime[l.uid]?.masked });
                const multi = items.length > 1 || !!l.style.scale;
                return (
                  <div key={l.uid} className="grp">
                    {multi && <div className="h">{l.title}</div>}
                    {items.map((it, k) => (
                      <div key={k} className="row">
                        <span className={`sw ${it.shape}${it.dashed ? ' dashed' : ''}`} style={{ background: it.shape === 'ligne' || it.outline ? undefined : it.color, borderColor: it.color, borderWidth: it.outline ? 2 : undefined }} />
                        <span>{multi ? it.label : l.title}</span>
                      </div>
                    ))}
                  </div>
                );
              })}
            </div>
          )}
          {scale && (
            <div className="mo-map-scale">
              <div style={{ width: scale.px }} />
              <span>{scale.label}</span>
            </div>
          )}
        </Paper>
      </Group>

      <AddContextModal
        opened={addCtx}
        onClose={() => setAddCtx(false)}
        catalog={catalog}
        notes={notes}
        onPick={(c) => { addCatalogLayer(c); setAddCtx(false); }}
      />
      <AddDataModal
        opened={addData}
        onClose={() => { setAddData(false); if (dsParam) setParams({}); }}
        datasets={datasets}
        initial={dsParam}
        onAdd={(l) => {
          setSpec((s) => ({ ...s, layers: [l, ...s.layers] }));
          prepare(l).then(() => setTimeout(() => fitLayer(l), 300));
          setAddData(false);
          if (dsParam) setParams({});
        }}
      />
      <LayerImportModal opened={importOpen} onClose={() => setImportOpen(false)} onDone={(l) => { loadCatalog(); addCatalogLayer(l); }} />
      <ManageLayersModal opened={manage} onClose={() => setManage(false)} catalog={catalog} isSuper={!!me?.is_superadmin} reload={loadCatalog} />
    </Stack>
  );
}

// ---------------------------------------------------------------------------- éditeur d'une couche

function LayerEditor({ layer: l, rt, catalog, datasets, palette, seq, onLayer, onStyle, onRecompute }: {
  layer: MapLayer;
  rt?: Runtime;
  catalog: CatalogLayer[];
  datasets: DatasetSummary[];
  palette: string[];
  seq: string[];
  onLayer: (p: Partial<MapLayer>) => void;
  onStyle: (p: Partial<MapLayer['style']>) => void;
  onRecompute: (p: Partial<MapLayer>) => void;
}) {
  const s = l.style;
  const [busy, setBusy] = useState(false);
  const cat = catalog.find((c) => c.id === l.layerId);
  const [cols, setCols] = useState<Column[]>([]);
  useEffect(() => {
    if (l.kind === 'couche') setCols(cat?.columns || []);
    else if (l.datasetId) api.get(`/api/datasets/${l.datasetId}`).then((d) => setCols(d.schema.filter((c: Column) => !c.name.startsWith('__')))).catch(() => setCols([]));
  }, [l.kind, l.layerId, l.datasetId, cat]);

  const colorChoices = l.kind === 'agregat'
    ? [{ value: 'valeur', label: 'Valeur agrégée' }, { value: 'n_navires', label: 'Nombre de navires' }]
    : cols.map((c) => ({ value: c.name, label: c.name }));

  const setColorBy = async (col: string | null) => {
    if (!col) return onStyle({ scale: null });
    setBusy(true);
    try {
      if (l.kind === 'agregat') {
        const vals = (rt?.geojson?.features || []).map((f: any) => f.properties[col]).filter((v: any) => typeof v === 'number').sort((a: number, b: number) => a - b);
        const q = [0.2, 0.4, 0.6, 0.8].map((p) => (vals.length ? vals[Math.floor(p * (vals.length - 1))] : null));
        onStyle({ scale: numScale(col, q, seq, vals[0], vals[vals.length - 1]) });
      } else {
        const url = l.kind === 'couche' ? `/api/geo/layers/${l.layerId}/values/${encodeURIComponent(col)}` : `/api/geo/points/${rt?.key}/values/${encodeURIComponent(col)}`;
        const r = await api.get(url);
        onStyle({ scale: r.numeric ? numScale(col, r.quantiles || [], seq, r.min, r.max) : catScale(col, r.values.map((v: any) => v.value), palette) });
      }
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Stack gap={6}>
      <TextInput size="xs" label="Nom dans la légende" value={l.title} onChange={(e) => onLayer({ title: e.currentTarget.value })} />
      {rt?.info && <Text size="xs" c="dimmed">{rt.info}</Text>}
      {rt?.error && <Alert color="red" p={6}><Text size="xs">{rt.error}</Text></Alert>}
      {cat && cat.integree && <Text size="xs" c="dimmed">Source : {cat.source} ({cat.licence})</Text>}
      {l.kind === 'agregat' && l.agg && (
        <AggEditor l={l} cols={cols} onApply={(agg) => onRecompute({ agg })} />
      )}
      <Group grow gap={6}>
        <ColorInput size="xs" label="Couleur" value={s.color} onChange={(v) => onStyle({ color: v })} disabled={!!s.scale} format="hex" swatches={palette} />
        <Select size="xs" label="Couleur selon" placeholder="Couleur unique" clearable data={colorChoices} value={s.scale?.column || null} onChange={setColorBy} rightSection={busy ? <Loader size={12} /> : undefined} />
      </Group>
      <Text size="xs">Opacité</Text>
      <Slider size="xs" min={0.1} max={1} step={0.05} value={s.opacity} onChange={(v) => onStyle({ opacity: v })} label={(v) => `${Math.round(v * 100)} %`} />
      {l.geom === 'polygone' && (
        <>
          <Text size="xs">Remplissage</Text>
          <Slider size="xs" min={0} max={1} step={0.05} value={s.fill} onChange={(v) => onStyle({ fill: v })} label={(v) => `${Math.round(v * 100)} %`} />
        </>
      )}
      <Group grow gap={6}>
        <NumberInput size="xs" label={l.geom === 'point' ? 'Contour' : 'Épaisseur'} min={0} max={10} step={0.5} decimalScale={1} value={s.width} onChange={(v) => onStyle({ width: Number(v) || 0 })} />
        {l.geom === 'point' && <NumberInput size="xs" label="Rayon" min={1} max={20} step={0.5} value={s.radius} onChange={(v) => onStyle({ radius: Number(v) || 3 })} />}
        <NumberInput size="xs" label="Visible dès le zoom" min={0} max={16} value={s.minzoom ?? ''} onChange={(v) => onStyle({ minzoom: v === '' ? undefined : Number(v) })} />
      </Group>
      {l.geom !== 'point' && <Switch size="xs" label="Pointillés" checked={!!s.dashed} onChange={(e) => onStyle({ dashed: e.currentTarget.checked })} />}
      {s.scale?.kind === 'cat' && (s.scale.values?.length || 0) >= palette.length && (
        <Text size="xs" c="orange">
          Seules les {palette.length} catégories les plus fréquentes ont une couleur ; les autres sont en gris.
        </Text>
      )}
      {l.kind === 'agregat' && l.datasetId && (
        <Menu>
          <Menu.Target>
            <Button size="compact-xs" variant="default" leftSection={<IconDownload size={14} />}>
              Exporter les mailles
            </Button>
          </Menu.Target>
          <Menu.Dropdown>
            {(['gpkg', 'shp', 'geojson'] as const).map((f) => (
              <Menu.Item key={f} onClick={() => exportAgg(l, f)}>
                {f === 'gpkg' ? 'GeoPackage' : f === 'shp' ? 'Shapefile (zip)' : 'GeoJSON'}
              </Menu.Item>
            ))}
          </Menu.Dropdown>
        </Menu>
      )}
      {datasets.length === 0 && null}
    </Stack>
  );
}

async function exportAgg(l: MapLayer, fmt: string) {
  try {
    const res = await fetch(`/api/geo/datasets/${l.datasetId}/aggregate/export?fmt=${fmt}`, {
      method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ ...l.agg, lon: l.lon, lat: l.lat }),
    });
    if (!res.ok) throw new Error((await res.json()).detail || 'Export impossible');
    const cd = res.headers.get('content-disposition') || '';
    const m = /filename="([^"]+)"/.exec(cd);
    saveBlob(await res.blob(), m ? m[1] : `mailles.${fmt}`);
  } catch (e) {
    fail(e);
  }
}

function AggEditor({ l, cols, onApply }: { l: MapLayer; cols: Column[]; onApply: (a: AggParams) => void }) {
  const [a, setA] = useState<AggParams>(l.agg!);
  useEffect(() => setA(l.agg!), [l.agg]);
  const names = cols.map((c) => c.name);
  return (
    <Paper withBorder p={6}>
      <Stack gap={6}>
        {a.mode === 'grille' ? (
          <NumberInput size="xs" label="Taille de maille (degrés)" description="0,05° ≈ 3 milles en latitude" min={0.001} max={5} step={0.01} decimalScale={3} value={a.cell} onChange={(v) => setA({ ...a, cell: Number(v) || 0.05 })} />
        ) : (
          <Select size="xs" label="Colonne des rectangles CIEM" data={names} value={a.rect_column || null} onChange={(v) => setA({ ...a, rect_column: v })} />
        )}
        <Select size="xs" label="Mesure" data={Object.entries(AGG_LABELS).map(([value, label]) => ({ value, label }))} value={a.agg} onChange={(v) => v && setA({ ...a, agg: v })} />
        {['somme', 'moyenne', 'max'].includes(a.agg) && <Select size="xs" label="Colonne" searchable data={names} value={a.value || null} onChange={(v) => setA({ ...a, value: v })} />}
        <Select size="xs" label="Colonne navire" description="Nécessaire au secret statistique" clearable searchable data={names} value={a.vessel || null} onChange={(v) => setA({ ...a, vessel: v })} />
        <Switch size="xs" label="Secret statistique (masquer les mailles de moins de 3 navires)" checked={a.secret > 0} disabled={!a.vessel} onChange={(e) => setA({ ...a, secret: e.currentTarget.checked ? 3 : 0 })} />
        <Button size="compact-xs" onClick={() => onApply(a)}>
          Recalculer
        </Button>
      </Stack>
    </Paper>
  );
}

// ---------------------------------------------------------------------------- ajout : contexte

function AddContextModal({ opened, onClose, catalog, notes, onPick }: { opened: boolean; onClose: () => void; catalog: CatalogLayer[]; notes: any; onPick: (c: CatalogLayer) => void }) {
  const groups = useMemo(() => {
    const g: Record<string, CatalogLayer[]> = {};
    catalog.filter((c) => c.groupe !== 'Fond de carte').forEach((c) => (g[c.groupe] ||= []).push(c));
    return g;
  }, [catalog]);
  return (
    <Modal opened={opened} onClose={onClose} title="Ajouter une couche" size="lg">
      <Stack gap="sm">
        {Object.entries(groups).map(([g, list]) => (
          <div key={g}>
            <Text size="xs" fw={700} c="dimmed" tt="uppercase" mb={4}>
              {g}
            </Text>
            <Stack gap={4}>
              {list.map((c) => (
                <Paper key={c.id} withBorder p={8} className="mo-pick" onClick={() => onPick(c)}>
                  <Group justify="space-between" wrap="nowrap">
                    <div style={{ minWidth: 0 }}>
                      <Text size="sm" fw={600}>
                        {c.nom} {c.publique && <Badge size="xs" variant="light">partagée</Badge>}
                      </Text>
                      <Text size="xs" c="dimmed" lineClamp={2}>
                        {c.description || c.source}
                      </Text>
                    </div>
                    <Badge variant="outline" size="sm">
                      {fmtN(c.n_features)} · {c.kind}
                    </Badge>
                  </Group>
                </Paper>
              ))}
            </Stack>
          </div>
        ))}
        {(notes?.manquantes || []).length > 0 && (
          <Alert variant="light" title="Couches non fournies">
            {(notes.manquantes as any[]).map((m) => (
              <Text key={m.nom} size="xs">
                <b>{m.nom}</b> : {m.conseil}
              </Text>
            ))}
          </Alert>
        )}
      </Stack>
    </Modal>
  );
}

// ---------------------------------------------------------------------------- ajout : jeu de données

function AddDataModal({ opened, onClose, datasets, initial, onAdd }: { opened: boolean; onClose: () => void; datasets: DatasetSummary[]; initial: string | null; onAdd: (l: MapLayer) => void }) {
  const { structure } = useAuth();
  const palette = (structure?.theme || NEUTRAL).palette;
  const [did, setDid] = useState<string | null>(initial);
  const [cols, setCols] = useState<string[]>([]);
  const [mode, setMode] = useState<'points' | 'grille' | 'ciem'>('points');
  const [lon, setLon] = useState<string | null>(null);
  const [lat, setLat] = useState<string | null>(null);
  const [agg, setAgg] = useState<AggParams>({ mode: 'grille', cell: 0.05, agg: 'nombre', secret: 0 });

  useEffect(() => { if (initial) setDid(initial); }, [initial]);
  useEffect(() => {
    if (!did) return;
    api.get(`/api/datasets/${did}`).then((d) => {
      const names = d.schema.map((c: Column) => c.name).filter((c: string) => !c.startsWith('__'));
      setCols(names);
      const lo = guessLon(names), la = guessLat(names), rect = guessRect(names), ves = guessVessel(names);
      setLon(lo);
      setLat(la);
      setMode(lo && la ? 'points' : rect ? 'ciem' : 'points');
      setAgg((a) => ({ ...a, rect_column: rect, vessel: ves, secret: ves ? 3 : 0 }));
    }).catch(fail);
  }, [did]);

  const ds = datasets.find((d) => d.id === did);
  const valid = !!did && (mode === 'ciem' ? !!agg.rect_column : !!(lon && lat)) && (!['somme', 'moyenne', 'max'].includes(agg.agg) || !!agg.value);

  const add = () => {
    const title = `${ds?.name || 'Jeu'} : ${mode === 'points' ? 'positions' : mode === 'grille' ? 'carroyage' : 'rectangles CIEM'}`;
    const base = { uid: uid(), title, visible: true, datasetId: did!, lon: lon || undefined, lat: lat || undefined };
    if (mode === 'points') onAdd({ ...base, kind: 'points', geom: 'point', style: { ...styleFor('point', palette[0]), radius: 3 } });
    else onAdd({ ...base, kind: 'agregat', geom: 'polygone', agg: { ...agg, mode }, style: { ...styleFor('polygone', palette[0]), fill: 0.75, width: 0.5 } });
  };

  return (
    <Modal opened={opened} onClose={onClose} title="Afficher un jeu de données" size="lg">
      <Stack gap="sm">
        <Select label="Jeu de données" searchable allowDeselect={false} data={datasets.map((d) => ({ value: d.id, label: d.name }))} value={did} onChange={setDid} />
        <SegmentedControl
          fullWidth
          value={mode}
          onChange={(v) => setMode(v as any)}
          data={[
            { value: 'points', label: 'Positions (points)' },
            { value: 'grille', label: 'Carroyage' },
            { value: 'ciem', label: 'Rectangles CIEM' },
          ]}
        />
        <Text size="xs" c="dimmed">
          {mode === 'points' && 'Chaque ligne est un point (ex. positions VMS). Affichage rapide même avec des centaines de milliers de positions.'}
          {mode === 'grille' && "Les positions sont regroupées dans une grille régulière : nombre de positions, de navires, ou somme d'une valeur par maille."}
          {mode === 'ciem' && 'Agrégation par rectangle statistique CIEM (ex. colonne stat_rect de SACROIS), sans coordonnées.'}
        </Text>
        {mode !== 'ciem' && (
          <Group grow>
            <Select label="Longitude" searchable data={cols} value={lon} onChange={setLon} />
            <Select label="Latitude" searchable data={cols} value={lat} onChange={setLat} />
          </Group>
        )}
        {mode !== 'points' && (
          <Paper withBorder p="xs">
            <Stack gap={6}>
              {mode === 'grille' ? (
                <NumberInput label="Taille de maille (degrés)" description="0,05° ≈ 3 milles nautiques en latitude ; 0,5° = demi-rectangle CIEM" min={0.001} max={5} step={0.01} decimalScale={3} value={agg.cell} onChange={(v) => setAgg({ ...agg, cell: Number(v) || 0.05 })} />
              ) : (
                <Select label="Colonne des rectangles CIEM (ex. 25E4)" searchable data={cols} value={agg.rect_column || null} onChange={(v) => setAgg({ ...agg, rect_column: v })} />
              )}
              <Select label="Mesure" data={Object.entries(AGG_LABELS).map(([value, label]) => ({ value, label }))} value={agg.agg} onChange={(v) => v && setAgg({ ...agg, agg: v })} />
              {['somme', 'moyenne', 'max'].includes(agg.agg) && <Select label="Colonne à agréger" searchable data={cols} value={agg.value || null} onChange={(v) => setAgg({ ...agg, value: v })} />}
              <Select label="Colonne navire" clearable searchable data={cols} value={agg.vessel || null} onChange={(v) => setAgg({ ...agg, vessel: v, secret: v ? agg.secret : 0 })} />
              <Switch label="Secret statistique : masquer les mailles de moins de 3 navires" checked={agg.secret > 0} disabled={!agg.vessel} onChange={(e) => setAgg({ ...agg, secret: e.currentTarget.checked ? 3 : 0 })} />
            </Stack>
          </Paper>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Annuler
          </Button>
          <Button onClick={add} disabled={!valid}>
            Ajouter à la carte
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

// ---------------------------------------------------------------------------- gestion des couches importées

function ManageLayersModal({ opened, onClose, catalog, isSuper, reload }: { opened: boolean; onClose: () => void; catalog: CatalogLayer[]; isSuper: boolean; reload: () => void }) {
  const mine = catalog.filter((c) => !c.integree);
  return (
    <Modal opened={opened} onClose={onClose} title="Couches importées" size="lg">
      <Stack gap="xs">
        {mine.length === 0 && <Text c="dimmed" size="sm">Aucune couche importée pour cette structure.</Text>}
        {mine.map((c) => (
          <Paper key={c.id} withBorder p="xs">
            <Group justify="space-between" wrap="nowrap">
              <div style={{ minWidth: 0 }}>
                <Text fw={600} size="sm">{c.nom}</Text>
                <Text size="xs" c="dimmed">
                  {fmtN(c.n_features)} entités · {c.kind} · projection d'origine {c.crs_source} · {c.source}
                </Text>
              </div>
              <Group gap={4} wrap="nowrap">
                <Menu>
                  <Menu.Target>
                    <Tooltip label="Exporter"><ActionIcon variant="subtle"><IconDownload size={16} /></ActionIcon></Tooltip>
                  </Menu.Target>
                  <Menu.Dropdown>
                    {(['gpkg', 'shp', 'geojson'] as const).map((f) => (
                      <Menu.Item key={f} onClick={() => download(`/api/geo/layers/${c.id}/export?fmt=${f}`).catch(fail)}>
                        {f === 'gpkg' ? 'GeoPackage' : f === 'shp' ? 'Shapefile (zip)' : 'GeoJSON'}
                      </Menu.Item>
                    ))}
                  </Menu.Dropdown>
                </Menu>
                {isSuper && (
                  <Switch size="xs" label="Toutes structures" checked={!!c.publique}
                    onChange={(e) => api.patch(`/api/geo/layers/${c.id}`, { public: e.currentTarget.checked }).then(reload).catch(fail)} />
                )}
                {c.modifiable && (
                  <ActionIcon variant="subtle" color="red" aria-label="Supprimer"
                    onClick={() => confirm(`Supprimer la couche « ${c.nom} » ?`) && api.del(`/api/geo/layers/${c.id}`).then(reload).catch(fail)}>
                    <IconTrash size={16} />
                  </ActionIcon>
                )}
              </Group>
            </Group>
          </Paper>
        ))}
      </Stack>
    </Modal>
  );
}
