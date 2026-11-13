// Cartographie : modèle d'une carte, styles MapLibre, légende et export image.
import type { Theme } from './types';

export type Basemap = 'ign' | 'osm' | 'horsligne' | 'aucun';

export interface ColorScale {
  kind: 'cat' | 'num';
  column: string;
  values?: string[]; // catégories
  breaks?: number[]; // bornes intérieures (classes)
  colors: string[];
}

export interface LayerStyle {
  color: string;
  opacity: number; // opacité générale
  fill: number; // opacité du remplissage (polygones)
  width: number; // épaisseur des traits
  radius: number; // rayon des points
  dashed?: boolean;
  minzoom?: number;
  scale?: ColorScale | null;
}

export interface AggParams {
  mode: 'grille' | 'ciem';
  cell: number;
  rect_column?: string | null;
  value?: string | null;
  agg: string;
  vessel?: string | null;
  secret: number;
}

export interface MapLayer {
  uid: string;
  kind: 'couche' | 'points' | 'agregat';
  title: string;
  visible: boolean;
  geom: 'polygone' | 'ligne' | 'point';
  layerId?: string;
  datasetId?: string;
  lon?: string;
  lat?: string;
  agg?: AggParams;
  style: LayerStyle;
}

export interface MapTemplate {
  title: string;
  subtitle: string;
  source: string;
  author: string;
  show_logo: boolean;
  show_legend: boolean;
  show_date: boolean;
  width: number;
  height: number;
}

export interface MapSpec {
  basemap: Basemap;
  center: [number, number];
  zoom: number;
  layers: MapLayer[];
  template: MapTemplate;
}

export interface CatalogLayer {
  id: string;
  nom: string;
  description: string;
  groupe: string;
  source?: string;
  licence?: string;
  url?: string;
  integree: boolean;
  modifiable: boolean;
  publique?: boolean;
  kind: 'polygone' | 'ligne' | 'point';
  n_features: number;
  bbox: [number, number, number, number] | null;
  columns: { name: string; type: string }[];
  style?: any;
  crs_source?: string;
  warnings?: string[];
  created_at?: string;
}

export const BASEMAPS: { value: Basemap; label: string; attribution: string }[] = [
  { value: 'ign', label: 'Plan IGN (internet)', attribution: '© IGN – Géoplateforme' },
  { value: 'osm', label: 'OpenStreetMap (internet)', attribution: '© contributeurs OpenStreetMap' },
  { value: 'horsligne', label: 'Hors ligne (côtes intégrées)', attribution: 'Natural Earth' },
  { value: 'aucun', label: 'Aucun fond', attribution: '' },
];

export const SEA = '#dde9f2';
export const LAND = '#eeebe4';

export function defaultMapSpec(author: string, source: string): MapSpec {
  return {
    basemap: 'ign',
    center: [-3.2, 47.6],
    zoom: 5.6,
    layers: [],
    template: { title: '', subtitle: '', source, author, show_logo: true, show_legend: true, show_date: true, width: 1400, height: 1000 },
  };
}

export const uid = () => Math.random().toString(36).slice(2, 10);

export function styleFor(kind: string, color: string, preset?: any): LayerStyle {
  return {
    color: preset?.couleur || color,
    opacity: 1,
    fill: preset?.remplissage ?? (kind === 'polygone' ? 0.3 : 1),
    width: preset?.epaisseur ?? (kind === 'point' ? 0.5 : 1.5),
    radius: 3.5,
    dashed: !!preset?.pointilles,
    minzoom: undefined,
    scale: null,
  };
}

export function apiUrl(path: string) {
  return `${location.origin}${path}`;
}

// --------------------------------------------------------------------------- couleurs

/** n couleurs prises régulièrement dans une palette séquentielle. */
export function pick(seq: string[], n: number): string[] {
  if (n <= 1) return [seq[seq.length - 1]];
  return Array.from({ length: n }, (_, i) => seq[Math.round((i * (seq.length - 1)) / (n - 1))]);
}

export function catScale(column: string, values: string[], palette: string[]): ColorScale {
  const top = values.slice(0, palette.length);
  return { kind: 'cat', column, values: top, colors: top.map((_, i) => palette[i % palette.length]) };
}

export function numScale(column: string, quantiles: (number | null)[], seq: string[], min?: number | null, max?: number | null): ColorScale {
  const qs = Array.from(new Set(quantiles.filter((q): q is number => q !== null && Number.isFinite(q)))).sort((a, b) => a - b);
  const breaks = qs.filter((q) => (min == null || q > min) && (max == null || q < max));
  return { kind: 'num', column, breaks, colors: pick(seq, breaks.length + 1) };
}

/** Expression MapLibre de couleur (fixe ou selon un attribut). */
export function colorExpr(s: LayerStyle, other = '#b9b9b9'): any {
  const sc = s.scale;
  if (!sc) return s.color;
  if (sc.kind === 'cat' && sc.values?.length) {
    const pairs: any[] = [];
    sc.values.forEach((v, i) => pairs.push(v, sc.colors[i]));
    return ['match', ['to-string', ['get', sc.column]], ...pairs, other];
  }
  if (sc.kind === 'num') {
    const steps: any[] = [sc.colors[0]];
    (sc.breaks || []).forEach((b, i) => steps.push(b, sc.colors[i + 1]));
    const val = ['to-number', ['get', sc.column], -1e308];
    return ['case', ['==', ['get', sc.column], null], other, steps.length > 1 ? ['step', val, ...steps] : sc.colors[0]];
  }
  return s.color;
}

const fmt = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 2 });
export const fmtN = (v: number | null | undefined) => (v === null || v === undefined ? '' : fmt.format(v));

export interface LegendItem {
  label: string;
  color: string;
  shape: 'polygone' | 'ligne' | 'point';
  dashed?: boolean;
  outline?: boolean; // polygone sans remplissage
}

export function legendItems(l: MapLayer, extra?: { masked?: boolean }): LegendItem[] {
  const s = l.style;
  const sc = s.scale;
  if (!sc) return [{ label: l.title, color: s.color, shape: l.geom, dashed: s.dashed, outline: l.geom === 'polygone' && s.fill < 0.05 }];
  const items: LegendItem[] = [];
  if (sc.kind === 'cat') {
    (sc.values || []).forEach((v, i) => items.push({ label: v, color: sc.colors[i], shape: l.geom }));
    items.push({ label: 'Autres / vide', color: '#b9b9b9', shape: l.geom });
  } else {
    const b = sc.breaks || [];
    sc.colors.forEach((c, i) => {
      const lo = i === 0 ? null : b[i - 1];
      const hi = i === b.length ? null : b[i];
      const label = lo === null && hi === null ? 'Toutes valeurs' : lo === null ? `< ${fmtN(hi)}` : hi === null ? `≥ ${fmtN(lo)}` : `${fmtN(lo)} – ${fmtN(hi)}`;
      items.push({ label, color: c, shape: l.geom });
    });
  }
  if (extra?.masked) items.push({ label: 'Secret statistique', color: '#d0d0d0', shape: l.geom });
  return items;
}

// --------------------------------------------------------------------------- échelle

export function scaleBar(map: any, maxPx = 120): { px: number; label: string } {
  const c = map.getCenter();
  const mPerPx = (40075016.686 * Math.cos((c.lat * Math.PI) / 180)) / (512 * Math.pow(2, map.getZoom()));
  const maxM = mPerPx * maxPx;
  const nm = maxM / 1852;
  // milles nautiques si l'échelle est marine et lisible, sinon km / m
  const nice = (x: number) => {
    const p = Math.pow(10, Math.floor(Math.log10(x)));
    const d = x / p;
    return (d >= 5 ? 5 : d >= 2 ? 2 : 1) * p;
  };
  if (nm >= 1) {
    const v = nice(nm);
    return { px: (v * 1852) / mPerPx, label: `${fmtN(v)} M (milles)` };
  }
  const km = maxM / 1000;
  if (km >= 1) {
    const v = nice(km);
    return { px: (v * 1000) / mPerPx, label: `${fmtN(v)} km` };
  }
  const v = nice(maxM);
  return { px: v / mPerPx, label: `${fmtN(v)} m` };
}

// --------------------------------------------------------------------------- export image

function loadImage(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = src;
  });
}

/** Compose la carte avec titre, légende, échelle, nord, source, auteur et logo dans une image PNG. */
export async function composeMapImage(map: any, spec: MapSpec, theme: Theme, opts: { logoUrl?: string | null; masked: Record<string, boolean>; attribution: string }): Promise<Blob> {
  const t = spec.template;
  const ratio = 2;
  const mapCanvas: HTMLCanvasElement = map.getCanvas();
  const W = mapCanvas.clientWidth;
  const H = mapCanvas.clientHeight;
  const head = t.title ? (t.subtitle ? 74 : 50) : 12;
  const foot = 46;
  const visible = spec.layers.filter((l) => l.visible);
  const items = t.show_legend ? visible.map((l) => ({ l, it: legendItems(l, { masked: opts.masked[l.uid] }) })) : [];
  const canvas = document.createElement('canvas');
  canvas.width = W * ratio;
  canvas.height = (H + head + foot) * ratio;
  const ctx = canvas.getContext('2d')!;
  ctx.scale(ratio, ratio);
  const font = theme.font || 'sans-serif';
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, W, H + head + foot);
  if (t.title) {
    ctx.fillStyle = theme.colors.text;
    ctx.font = `600 22px ${font}`;
    ctx.fillText(t.title, 16, 32);
    if (t.subtitle) {
      ctx.fillStyle = theme.colors.muted;
      ctx.font = `15px ${font}`;
      ctx.fillText(t.subtitle, 16, 58);
    }
  }
  ctx.drawImage(mapCanvas, 0, head, W, H);
  ctx.strokeStyle = theme.colors.border;
  ctx.strokeRect(0.5, head + 0.5, W - 1, H - 1);

  // légende
  if (items.length) {
    ctx.font = `12px ${font}`;
    const lines = items.reduce((n, x) => n + 1 + (x.it.length > 1 || x.l.style.scale ? x.it.length : 0), 0);
    const lw = Math.min(280, Math.max(...items.flatMap((x) => [x.l.title, ...x.it.map((i) => i.label)]).map((s) => ctx.measureText(s).width)) + 46);
    const lh = lines * 18 + 14;
    const x0 = 12;
    const y0 = head + H - lh - 12;
    ctx.fillStyle = 'rgba(255,255,255,0.92)';
    ctx.fillRect(x0, y0, lw, lh);
    ctx.strokeStyle = theme.colors.border;
    ctx.strokeRect(x0 + 0.5, y0 + 0.5, lw, lh);
    let y = y0 + 20;
    for (const { l, it } of items) {
      const multi = it.length > 1 || !!l.style.scale;
      if (multi) {
        ctx.fillStyle = theme.colors.text;
        ctx.font = `600 12px ${font}`;
        ctx.fillText(l.title, x0 + 10, y);
        y += 18;
      }
      for (const i of it) {
        drawSwatch(ctx, i, x0 + 10 + (multi ? 6 : 0), y - 10);
        ctx.fillStyle = theme.colors.text;
        ctx.font = `12px ${font}`;
        ctx.fillText(multi ? i.label : l.title, x0 + 34 + (multi ? 6 : 0), y);
        y += 18;
      }
    }
  }
  // échelle + nord
  const sb = scaleBar(map, 140);
  const sx = W - sb.px - 20;
  const sy = head + H - 22;
  ctx.fillStyle = 'rgba(255,255,255,0.85)';
  ctx.fillRect(sx - 8, sy - 18, sb.px + 16, 30);
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(sx, sy - 4);
  ctx.lineTo(sx, sy);
  ctx.lineTo(sx + sb.px, sy);
  ctx.lineTo(sx + sb.px, sy - 4);
  ctx.stroke();
  ctx.lineWidth = 1;
  ctx.fillStyle = '#333';
  ctx.font = `11px ${font}`;
  ctx.fillText(sb.label, sx, sy - 7);
  const nx = W - 30;
  const ny = head + 18;
  ctx.fillStyle = 'rgba(255,255,255,0.85)';
  ctx.beginPath();
  ctx.arc(nx, ny + 12, 16, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#333';
  ctx.beginPath();
  ctx.moveTo(nx, ny);
  ctx.lineTo(nx + 6, ny + 16);
  ctx.lineTo(nx, ny + 12);
  ctx.lineTo(nx - 6, ny + 16);
  ctx.closePath();
  ctx.fill();
  ctx.font = `600 10px ${font}`;
  ctx.fillText('N', nx - 3.5, ny + 26);

  // pied : source, auteur, date, fond de carte, logo
  const parts = [t.source && `Source : ${t.source}`, opts.attribution && `Fond : ${opts.attribution}`, t.author && `Réalisation : ${t.author}`,
    t.show_date && new Date().toLocaleDateString('fr-FR')].filter(Boolean);
  ctx.fillStyle = theme.colors.muted;
  ctx.font = `12px ${font}`;
  ctx.fillText(parts.join(' · '), 16, head + H + 28);
  if (t.show_logo && opts.logoUrl) {
    const img = await loadImage(opts.logoUrl);
    if (img) {
      const h = 34;
      const w = (img.width / img.height) * h;
      ctx.drawImage(img, W - w - 12, head + H + 6, w, h);
    }
  }
  return new Promise((resolve) => canvas.toBlob((b) => resolve(b!), 'image/png'));
}

function drawSwatch(ctx: CanvasRenderingContext2D, i: LegendItem, x: number, y: number) {
  ctx.fillStyle = i.color;
  ctx.strokeStyle = i.color;
  if (i.shape === 'ligne') {
    ctx.lineWidth = 2.5;
    ctx.setLineDash(i.dashed ? [5, 3] : []);
    ctx.beginPath();
    ctx.moveTo(x, y + 6);
    ctx.lineTo(x + 18, y + 6);
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.lineWidth = 1;
  } else if (i.shape === 'point') {
    ctx.beginPath();
    ctx.arc(x + 9, y + 6, 5, 0, Math.PI * 2);
    ctx.fill();
  } else {
    if (!i.outline) {
      ctx.globalAlpha = 0.75;
      ctx.fillRect(x, y, 18, 12);
      ctx.globalAlpha = 1;
    }
    ctx.lineWidth = i.outline ? 1.5 : 1;
    ctx.strokeRect(x + 0.5, y + 0.5, 18, 12);
    ctx.lineWidth = 1;
  }
}

// --------------------------------------------------------------------------- aide à la saisie

const LON = /^(lon|lng|long|longitude|lg|x)$/i;
const LAT = /^(lat|latitude|lt|y)$/i;
const RECT = /^(stat_?rect|rect(angle)?(_ciem)?|rectangle_stat(istique)?|ices_?rect)$/i;
export const guessLon = (cols: string[]) => cols.find((c) => LON.test(c)) || null;
export const guessLat = (cols: string[]) => cols.find((c) => LAT.test(c)) || null;
export const guessRect = (cols: string[]) => cols.find((c) => RECT.test(c)) || null;
export const guessVessel = (cols: string[]) => cols.find((c) => /^(navire|cfr(_cod)?|navs_cod|op)$/i.test(c)) || null;
