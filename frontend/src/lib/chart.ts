// Construction des figures Plotly à partir d'une spécification simple + charte de la structure.
import type { Theme } from './types';
import { fontOf } from './theme';

export type ChartType =
  | 'barres'
  | 'barres_h'
  | 'lignes'
  | 'aires'
  | 'combine'
  | 'secteurs'
  | 'chaleur'
  | 'nuage'
  | 'bulles'
  | 'boites'
  | 'violons'
  | 'histogramme'
  | 'nuage3d'
  | 'surface3d';

export type AxisId = 'y' | 'y2' | 'y3' | 'y4';
export type Mark = 'barres' | 'lignes' | 'aires' | 'points';

export interface Measure {
  column?: string;
  agg: string;
  axis?: AxisId;
  mark?: Mark;
  label?: string;
  color?: string; // couleur de la palette (si pas de série)
  dash?: boolean; // courbe en tirets
  show_values?: boolean;
}

/** Réglages d'un axe vertical (l'axe principal garde aussi les anciens champs y_title, y_scale, y_min, y_max). */
export interface AxisCfg {
  title?: string;
  scale?: 'lineaire' | 'log';
  min?: number | null;
  max?: number | null;
  suffix?: string;
}

/** Repère : ligne horizontale (quota, moyenne…), ligne verticale, zone (période) ou note sur une catégorie. */
export interface RefMark {
  kind: 'ligne_h' | 'ligne_v' | 'zone_v' | 'note';
  value?: number | string | null;
  value2?: string | null;
  axis?: AxisId;
  label?: string;
  color?: string;
}

export const AXES: { value: AxisId; label: string }[] = [
  { value: 'y', label: 'Axe gauche' },
  { value: 'y2', label: 'Axe droit' },
  { value: 'y3', label: 'Axe gauche n° 2' },
  { value: 'y4', label: 'Axe droit n° 2' },
];

export const MARKS: { value: Mark; label: string }[] = [
  { value: 'barres', label: 'Barres' },
  { value: 'lignes', label: 'Courbe' },
  { value: 'aires', label: 'Aire' },
  { value: 'points', label: 'Points' },
];

export const SIZE_PRESETS: { value: string; label: string; width: number; height: number }[] = [
  { value: 'rapport', label: 'Rapport (pleine largeur)', width: 1100, height: 620 },
  { value: 'a4_paysage', label: 'Page A4 paysage', width: 1500, height: 1000 },
  { value: 'a4_portrait', label: 'Page A4 portrait', width: 1000, height: 1300 },
  { value: 'diapo', label: 'Diapositive 16:9', width: 1280, height: 720 },
  { value: 'carre', label: 'Carré (réseaux sociaux)', width: 1080, height: 1080 },
  { value: 'bandeau', label: 'Bandeau', width: 1400, height: 480 },
];

export interface ChartSpec {
  type: ChartType;
  x?: string;
  y?: string; // nuages / 3D (colonne brute)
  z?: string;
  size?: string;
  series?: string;
  facet?: string;
  measures: Measure[];
  filters: any[];
  stack?: 'groupe' | 'empile' | 'pourcent';
  y_scale?: 'lineaire' | 'log';
  y_min?: number | null;
  y_max?: number | null;
  y_title?: string;
  y2_title?: string;
  x_title?: string;
  sort?: 'aucun' | 'valeur_desc' | 'valeur_asc';
  show_values?: boolean;
  axes?: Partial<Record<AxisId, AxisCfg>>;
  refs?: RefMark[];
  legend?: 'haut' | 'droite' | 'bas' | 'aucune';
  decimals?: number | null;
  facet_scale?: 'independante' | 'commune';
  facet_cols?: number | null;
  template: {
    title: string;
    subtitle: string;
    source: string;
    author: string;
    show_date: boolean;
    show_logo: boolean;
    caption: string;
    width: number;
    height: number;
  };
}

export const RAW_TYPES: ChartType[] = ['nuage', 'bulles', 'boites', 'violons', 'histogramme', 'nuage3d'];

export const CHART_TYPES: { value: ChartType; label: string; hint: string }[] = [
  { value: 'barres', label: 'Barres', hint: 'Comparer des quantités entre catégories' },
  { value: 'barres_h', label: 'Barres horizontales', hint: 'Catégories aux noms longs, classements' },
  { value: 'lignes', label: 'Courbes', hint: 'Évolution dans le temps' },
  { value: 'aires', label: 'Aires', hint: 'Évolution d’un total et de sa composition' },
  { value: 'combine', label: 'Barres + courbes', hint: 'Plusieurs mesures, deux axes possibles' },
  { value: 'secteurs', label: 'Anneau', hint: 'Parts d’un tout (≤ 6 catégories)' },
  { value: 'chaleur', label: 'Carte de chaleur', hint: 'Deux dimensions croisées (mois × espèce…)' },
  { value: 'nuage', label: 'Nuage de points', hint: 'Relation entre deux variables' },
  { value: 'bulles', label: 'Bulles', hint: 'Nuage + une 3e variable en taille' },
  { value: 'boites', label: 'Boîtes à moustaches', hint: 'Distribution par groupe' },
  { value: 'violons', label: 'Violons', hint: 'Forme de la distribution par groupe' },
  { value: 'histogramme', label: 'Histogramme', hint: 'Distribution d’une variable' },
  { value: 'nuage3d', label: 'Nuage 3D', hint: 'Trois variables numériques' },
  { value: 'surface3d', label: 'Surface 3D', hint: 'Mesure selon deux dimensions' },
];

export const AGG_LABEL: Record<string, string> = {
  somme: 'Somme',
  moyenne: 'Moyenne',
  mediane: 'Médiane',
  min: 'Min',
  max: 'Max',
  nombre: 'Nombre',
  nombre_lignes: 'Nombre de lignes',
  nombre_distinct: 'Nombre distinct',
  ecart_type: 'Écart-type',
};

export function measureLabel(m: Measure): string {
  if (m.label) return m.label;
  if (m.agg === 'nombre_lignes') return 'Nombre de lignes';
  return `${AGG_LABEL[m.agg] || m.agg} de ${m.column}`;
}

export function defaultSpec(author: string, source: string): ChartSpec {
  return {
    type: 'barres',
    measures: [{ agg: 'somme', axis: 'y', mark: 'barres' }],
    filters: [],
    stack: 'groupe',
    y_scale: 'lineaire',
    sort: 'aucun',
    template: { title: '', subtitle: '', source, author, show_date: true, show_logo: true, caption: '', width: 1100, height: 620 },
  };
}

/** Requête à envoyer à /chart-data. */
export function dataRequest(s: ChartSpec) {
  // conditions incomplètes ignorées tant qu'elles sont en cours de saisie
  const filters = (s.filters || []).filter(
    (c) => c.column && (['is_null', 'not_null'].includes(c.op) || (['in', 'not_in'].includes(c.op) ? c.values?.length : c.value !== '' && c.value != null)),
  );
  if (RAW_TYPES.includes(s.type)) {
    const cols = [s.x, s.y, s.z, s.size].filter(Boolean);
    return {
      raw: true,
      x: s.type === 'histogramme' ? undefined : s.x,
      series: s.series,
      facet: s.facet,
      z: s.z,
      measures: [...new Set(cols.filter((c) => c !== s.x || s.type === 'histogramme'))].map((c) => ({ column: c, agg: 'somme' })),
      filters,
      limit: 50000,
    };
  }
  // seuls la colonne et l'agrégat concernent le serveur : le style ne relance pas la requête
  return { x: s.x, series: s.series, facet: s.facet, measures: s.measures.map((m) => ({ column: m.column, agg: m.agg })), filters };
}

interface Data {
  columns: string[];
  rows: any[][];
  sampled?: boolean;
  total?: number | null;
}

const fmtFr = (v: any, d = 2) => (typeof v === 'number' ? v.toLocaleString('fr-FR', { maximumFractionDigits: d }) : v);

/** Réglages effectifs d'un axe (compatibles avec les graphiques enregistrés avant les axes multiples). */
export function axisCfg(s: ChartSpec, a: AxisId): AxisCfg {
  const c = s.axes?.[a] || {};
  if (a === 'y') return { title: c.title ?? s.y_title, scale: c.scale ?? s.y_scale, min: c.min ?? s.y_min, max: c.max ?? s.y_max, suffix: c.suffix };
  if (a === 'y2') return { ...c, title: c.title ?? s.y2_title };
  return c;
}

/** Marque effective d'une mesure selon le type du graphique. */
export function markOf(s: ChartSpec, m: Measure): Mark {
  if (s.type === 'barres_h') return 'barres';
  if (m.mark) return m.mark;
  if (s.type === 'lignes') return 'lignes';
  if (s.type === 'aires') return 'aires';
  return 'barres';
}

/** Axe effectif d'une mesure : barres horizontales = un seul axe ; petits multiples = deux axes par panneau. */
export function axisOf(s: ChartSpec, m: Measure): AxisId {
  if (s.type === 'barres_h') return 'y';
  const a = m.axis || 'y';
  if (s.facet && (a === 'y3' || a === 'y4')) return a === 'y3' ? 'y' : 'y2';
  return a;
}

export const usedAxes = (s: ChartSpec): AxisId[] =>
  RAW_TYPES.includes(s.type) || ['secteurs', 'chaleur', 'surface3d'].includes(s.type)
    ? ['y']
    : (['y', 'y2', 'y3', 'y4'] as AxisId[]).filter((a) => a === 'y' || s.measures.some((m) => axisOf(s, m) === a));

/** Construit la figure Plotly (traces + mise en page) avec le gabarit de la structure. */
export function buildFigure(s: ChartSpec, d: Data, theme: Theme, opts: { logoUrl?: string | null; structureName?: string }) {
  const pal = theme.palette;
  const col = (name?: string) => (name ? d.columns.indexOf(name) : -1);
  const ink = theme.colors.text;
  const muted = theme.colors.muted;
  const grid = theme.chart.grid;
  const traces: any[] = [];

  // --- découpage en panneaux (petits multiples)
  const fi = col(s.facet);
  const facets: any[] = fi >= 0 ? [...new Set(d.rows.map((r) => r[fi]))].slice(0, 16) : [null];
  const nf = facets.length;
  const ncols = nf > 1 ? Math.min(nf, Math.max(1, s.facet_cols || Math.ceil(Math.sqrt(nf)))) : 1;
  const nrows = Math.ceil(nf / ncols);
  const axisName = (k: number, a: 'x' | 'y') => (k === 0 ? a : `${a}${k + 1}`);
  // axes verticaux : panneau k -> y, y2… (un par panneau) ; axes secondaires numérotés après les panneaux
  const extra: Record<AxisId, number> = { y: 0, y2: 1, y3: 2, y4: 3 };
  const yId = (k: number, a: AxisId) => (a === 'y' ? axisName(k, 'y') : `y${nf + k * 3 + extra[a]}`);
  const dec = Math.max(0, Math.min(4, s.decimals ?? 2));
  const used = usedAxes(s);
  const multiBarAxes = new Set(s.measures.filter((m) => markOf(s, m) === 'barres').map((m) => axisOf(s, m))).size > 1;
  const shapes: any[] = [];
  const notes: any[] = [];
  let firstOrder: any[] = [];

  const is3d = s.type === 'nuage3d' || s.type === 'surface3d';
  const raw = RAW_TYPES.includes(s.type);
  const xi = col(s.x);
  const si = col(s.series);

  // couleurs stables par valeur de série (la couleur suit l'entité, pas son rang)
  const seriesValues: any[] = si >= 0 ? [...new Set(d.rows.map((r) => r[si]))] : [null];
  const colorOf = (v: any, k = 0) => pal[(si >= 0 ? seriesValues.indexOf(v) : k) % pal.length];

  facets.forEach((fv, k) => {
    const rows = fi >= 0 ? d.rows.filter((r) => r[fi] === fv) : d.rows;
    const xa = axisName(k, 'x');
    const ya = axisName(k, 'y');
    const showLegend = k === 0;

    if (s.type === 'secteurs') {
      const mi = d.columns.length - 1;
      traces.push({
        type: 'pie',
        hole: 0.55,
        labels: rows.map((r) => r[xi] ?? '(vide)'),
        values: rows.map((r) => r[mi]),
        marker: { colors: rows.map((_, i) => pal[i % pal.length]), line: { color: theme.chart.background, width: 2 } },
        textinfo: 'label+percent',
        sort: true,
        domain: nf > 1 ? { row: Math.floor(k / ncols), column: k % ncols } : undefined,
        title: nf > 1 ? { text: String(fv) } : undefined,
        hovertemplate: '%{label}<br>%{value:,.0f} (%{percent})<extra></extra>',
      });
      return;
    }

    if (s.type === 'chaleur' || s.type === 'surface3d') {
      const mi = d.columns.length - 1;
      const xs = [...new Set(rows.map((r) => r[xi]))];
      const ys = [...new Set(rows.map((r) => r[si]))];
      const z = ys.map((y) => xs.map((x) => rows.find((r) => r[xi] === x && r[si] === y)?.[mi] ?? null));
      const scale = theme.sequential.map((c, i) => [i / (theme.sequential.length - 1), c]);
      traces.push(
        s.type === 'chaleur'
          ? { type: 'heatmap', x: xs.map(String), y: ys.map(String), z, colorscale: scale, xaxis: xa, yaxis: ya, xgap: 2, ygap: 2, showscale: k === 0, hovertemplate: '%{x} · %{y}<br>%{z:,.2f}<extra></extra>' }
          : { type: 'surface', x: xs.map(String), y: ys.map(String), z, colorscale: scale, showscale: true },
      );
      return;
    }

    if (s.type === 'nuage3d') {
      const [a, b, c] = [col(s.x), col(s.y), col(s.z)];
      const groups = si >= 0 ? seriesValues : [null];
      groups.forEach((g, gi) => {
        const rr = si >= 0 ? rows.filter((r) => r[si] === g) : rows;
        traces.push({
          type: 'scatter3d',
          mode: 'markers',
          name: g === null ? 'valeurs' : String(g),
          x: rr.map((r) => r[a]),
          y: rr.map((r) => r[b]),
          z: rr.map((r) => r[c]),
          marker: { size: 4, color: colorOf(g, gi), opacity: 0.8 },
          showlegend: si >= 0,
        });
      });
      return;
    }

    if (raw) {
      const groups = si >= 0 ? seriesValues : [null];
      groups.forEach((g, gi) => {
        const rr = si >= 0 ? rows.filter((r) => r[si] === g) : rows;
        const name = g === null ? (s.y || s.x || '') : String(g);
        const color = colorOf(g, gi);
        const common = { name, xaxis: xa, yaxis: ya, showlegend: showLegend && si >= 0, legendgroup: name, marker: { color } };
        if (s.type === 'histogramme') {
          traces.push({ ...common, type: 'histogram', x: rr.map((r) => r[col(s.x)]), opacity: si >= 0 ? 0.65 : 1, marker: { color, line: { color: theme.chart.background, width: 1 } } });
        } else if (s.type === 'boites' || s.type === 'violons') {
          const yv = rr.map((r) => r[col(s.y)]);
          const xv = xi >= 0 ? rr.map((r) => r[xi]) : undefined;
          traces.push(
            s.type === 'boites'
              ? { ...common, type: 'box', x: xv, y: yv, boxpoints: 'outliers', marker: { color, size: 4 }, line: { width: 1.5 } }
              : { ...common, type: 'violin', x: xv, y: yv, box: { visible: true }, meanline: { visible: true }, line: { color } },
          );
        } else {
          const sizes = s.type === 'bulles' && s.size ? rr.map((r) => r[col(s.size)]) : null;
          const maxS = sizes ? Math.max(...sizes.filter((v) => typeof v === 'number'), 1) : 1;
          traces.push({
            ...common,
            type: 'scattergl',
            mode: 'markers',
            x: rr.map((r) => r[col(s.x)]),
            y: rr.map((r) => r[col(s.y)]),
            marker: {
              color,
              size: sizes ? sizes.map((v) => 6 + 34 * Math.sqrt(Math.max(0, v || 0) / maxS)) : 8,
              opacity: 0.75,
              line: { color: theme.chart.background, width: 1 },
            },
          });
        }
      });
      return;
    }

    // --- graphiques agrégés : barres, courbes, aires, points, sur 1 à 4 axes
    const mStart = d.columns.length - s.measures.length;
    const xs = [...new Set(rows.map((r) => r[xi]))];
    let order = xs;
    if (s.sort && s.sort !== 'aucun' && s.measures.length) {
      const tot = new Map<any, number>();
      rows.forEach((r) => tot.set(r[xi], (tot.get(r[xi]) || 0) + (r[mStart] || 0)));
      order = [...xs].sort((a, b) => ((tot.get(a) || 0) - (tot.get(b) || 0)) * (s.sort === 'valeur_desc' ? -1 : 1));
    }
    if (k === 0) firstOrder = order;
    const horizontal = s.type === 'barres_h';
    s.measures.forEach((m, mi) => {
      const groups = si >= 0 ? seriesValues : [null];
      const mark = markOf(s, m);
      const ax = axisOf(s, m);
      const suffix = axisCfg(s, ax).suffix ? ` ${axisCfg(s, ax).suffix}` : '';
      groups.forEach((g) => {
        const rr = si >= 0 ? rows.filter((r) => r[si] === g) : rows;
        const byX = new Map(rr.map((r) => [r[xi], r[mStart + mi]]));
        const xv = order;
        const yv = order.map((x) => byX.get(x) ?? null);
        const name = [s.measures.length > 1 ? measureLabel(m) : null, g === null ? null : String(g)].filter(Boolean).join(' · ') || measureLabel(m);
        const color = si >= 0 ? colorOf(g) : m.color || pal[mi % pal.length];
        const yaxis = yId(k, ax);
        const base: any = { name, legendgroup: name, showlegend: showLegend && s.legend !== 'aucune', xaxis: xa, yaxis };
        const hover = `${horizontal ? '%{y}' : '%{x}'}<br>${esc(name)} : %{${horizontal ? 'x' : 'y'}:,.${dec}f}${esc(suffix)}<extra></extra>`;
        const values = m.show_values || (s.show_values && mark === 'barres');
        const text = values ? yv.map((v) => (v == null ? '' : fmtFr(v, dec))) : undefined;
        if (mark === 'barres') {
          traces.push({
            ...base,
            type: 'bar',
            orientation: horizontal ? 'h' : 'v',
            x: horizontal ? yv : xv,
            y: horizontal ? xv : yv,
            // barres sur plusieurs axes : côte à côte (sinon elles se superposent)
            offsetgroup: multiBarAxes ? (s.stack === 'groupe' ? `${ax}-${mi}-${g}` : ax) : undefined,
            marker: { color, line: { color: theme.chart.background, width: 1 }, cornerradius: 3 },
            text,
            textposition: values ? 'outside' : undefined,
            cliponaxis: false,
            hovertemplate: hover,
          });
        } else {
          const lines = mark !== 'points';
          traces.push({
            ...base,
            type: 'scatter',
            mode: [lines ? 'lines' : null, !lines || xv.length <= 40 ? 'markers' : null, values ? 'text' : null].filter(Boolean).join('+'),
            x: xv,
            y: yv,
            text,
            textposition: values ? 'top center' : undefined,
            textfont: values ? { size: 11, color } : undefined,
            line: lines ? { color, width: 2.2, dash: m.dash ? 'dash' : 'solid' } : undefined,
            marker: { color, size: lines ? 7 : 9 },
            fill: mark === 'aires' ? (s.stack !== 'groupe' && s.type === 'aires' ? 'tonexty' : 'tozeroy') : undefined,
            fillcolor: mark === 'aires' && s.type !== 'aires' ? hexA(color, 0.25) : undefined,
            stackgroup: mark === 'aires' && s.type === 'aires' && s.stack !== 'groupe' ? `s${mi}` : undefined,
            groupnorm: mark === 'aires' && s.type === 'aires' && s.stack === 'pourcent' ? 'percent' : undefined,
            connectgaps: false,
            hovertemplate: hover,
          });
        }
      });
    });

    // repères : lignes de référence, zones et notes (dans chaque panneau)
    const isCat = s.type.startsWith('barres') || s.type === 'combine' || order.some((v) => typeof v !== 'number');
    const catPos = (v: any, off = 0) => {
      if (!isCat) return typeof v === 'string' && v.trim() !== '' && !isNaN(Number(v)) ? Number(v) + off : v;
      const i = order.findIndex((o) => String(o) === String(v));
      return i < 0 ? null : i + off;
    };
    const xd = `${xa} domain`;
    const yd = `${ya} domain`;
    (s.refs || []).forEach((r) => {
      const c = r.color || ink;
      if (r.kind === 'ligne_h') {
        const v = Number(r.value);
        if (r.value === '' || r.value == null || isNaN(v)) return;
        const vax = yId(k, horizontal ? 'y' : axisOf(s, { agg: '', axis: r.axis }));
        shapes.push(horizontal
          ? { type: 'line', xref: xa, yref: yd, x0: v, x1: v, y0: 0, y1: 1, line: { color: c, width: 1.6, dash: 'dash' }, layer: 'above' }
          : { type: 'line', xref: xd, yref: vax, x0: 0, x1: 1, y0: v, y1: v, line: { color: c, width: 1.6, dash: 'dash' }, layer: 'above' });
        if (r.label)
          notes.push(horizontal
            ? { text: esc(r.label), xref: xa, yref: yd, x: v, y: 1, xanchor: 'left', yanchor: 'top', xshift: 4, showarrow: false, font: { size: 11, color: c } }
            : { text: esc(r.label), xref: xd, yref: vax, x: 1, y: v, xanchor: 'right', yanchor: 'bottom', showarrow: false, font: { size: 11, color: c } });
      } else if (r.kind === 'ligne_v' || r.kind === 'zone_v') {
        const zone = r.kind === 'zone_v';
        const p0 = catPos(r.value, zone && isCat ? -0.5 : 0);
        const p1 = zone ? catPos(r.value2 ?? r.value, isCat ? 0.5 : 0) : p0;
        if (p0 == null || p1 == null) return;
        const ln = zone ? { width: 0 } : { color: c, width: 1.6, dash: 'dot' };
        const fill = zone ? hexA(r.color || muted, 0.14) : undefined;
        shapes.push(horizontal
          ? { type: zone ? 'rect' : 'line', xref: xd, yref: ya, x0: 0, x1: 1, y0: p0, y1: p1, line: ln, fillcolor: fill, layer: 'below' }
          : { type: zone ? 'rect' : 'line', xref: xa, yref: yd, x0: p0, x1: p1, y0: 0, y1: 1, line: ln, fillcolor: fill, layer: 'below' });
        if (r.label)
          notes.push(horizontal
            ? { text: esc(r.label), xref: xd, yref: ya, x: 1, y: p0, xanchor: 'right', yanchor: 'bottom', showarrow: false, font: { size: 11, color: c } }
            : { text: esc(r.label), xref: xa, yref: yd, x: zone ? (Number(p0) + Number(p1)) / 2 : p0, y: 1, xanchor: zone ? 'center' : 'left', yanchor: 'top', xshift: zone ? 0 : 4, showarrow: false, font: { size: 11, color: c } });
      } else if (r.kind === 'note' && r.label) {
        const p = catPos(r.value);
        if (p == null) return;
        const m0 = s.measures.findIndex((m) => axisOf(s, m) === 'y');
        const vals = rows.filter((row) => String(row[xi]) === String(r.value)).map((row) => row[mStart + Math.max(0, m0)]).filter((v) => typeof v === 'number');
        const top = vals.length ? (s.stack === 'empile' ? vals.reduce((a, b) => a + b, 0) : Math.max(...vals)) : null;
        notes.push(horizontal
          ? { text: esc(r.label), xref: top == null ? xd : xa, yref: ya, x: top ?? 0.9, y: p, ax: 40, ay: -24, showarrow: true, arrowhead: 0, arrowcolor: c, font: { size: 11, color: c }, align: 'left' }
          : { text: esc(r.label), xref: xa, yref: top == null ? yd : ya, x: p, y: top ?? 0.9, ax: 0, ay: -34, showarrow: true, arrowhead: 0, arrowcolor: c, font: { size: 11, color: c }, bgcolor: hexA(theme.chart.background, 0.85) });
      }
    });
  });

  // --- mise en page
  const t = s.template;
  const legendPos = s.legend || 'haut';
  const top = 64 + (t.subtitle ? 22 : 0) + (nf > 1 && legendPos === 'haut' ? 40 : 0);
  const bottom = 70 + (t.caption ? 18 : 0) + (legendPos === 'bas' ? 40 : 0);
  const rightAxes = used.filter((a) => a === 'y2' || a === 'y4').length;
  const layout: any = {
    width: t.width,
    height: t.height,
    paper_bgcolor: theme.chart.background,
    plot_bgcolor: theme.chart.background,
    font: { family: fontOf(theme), color: ink, size: 13 },
    margin: { l: 72, r: rightAxes ? 72 : legendPos === 'droite' ? 24 : 32, t: top, b: bottom },
    title: {
      text: `<b>${esc(t.title || '')}</b>${t.subtitle ? `<br><span style="font-size:13px;color:${muted}">${esc(t.subtitle)}</span>` : ''}`,
      x: 0.01,
      xanchor: 'left',
      // titre sur deux lignes (titre + sous-titre) : position en pixels depuis le haut, sinon il est rogné
      yref: 'container',
      y: 1 - (t.subtitle ? 34 : 14) / t.height,
      yanchor: t.subtitle ? 'middle' : 'top',
      font: { size: 18 },
    },
    showlegend: legendPos !== 'aucune',
    legend:
      legendPos === 'droite'
        ? { orientation: 'v', x: rightAxes ? 1.1 : 1.02, xanchor: 'left', y: 1, yanchor: 'top', font: { size: 12, color: ink } }
        : legendPos === 'bas'
          ? { orientation: 'h', x: 0, y: -0.12, yanchor: 'top', font: { size: 12, color: ink } }
          : nf > 1
            ? { orientation: 'h', x: 0, yref: 'container', y: 1 - (38 + (t.subtitle ? 22 : 0)) / t.height, yanchor: 'top', font: { size: 12, color: ink } }
            : { orientation: 'h', x: 0, y: 1.0, yanchor: 'bottom', font: { size: 12, color: ink } },
    barmode: s.stack === 'empile' ? 'stack' : s.stack === 'pourcent' ? 'relative' : 'group',
    barnorm: s.stack === 'pourcent' ? 'percent' : undefined,
    bargap: 0.25,
    hoverlabel: { font: { family: theme.font } },
    separators: ', ',
    annotations: [...notes] as any[],
    shapes,
    images: [] as any[],
  };

  // couleur du titre d'axe = couleur de sa première mesure quand il y a plusieurs axes (lecture sans ambiguïté)
  const axisColor = (a: AxisId) => {
    if (used.length < 2 || si >= 0) return muted;
    const i = s.measures.findIndex((m) => axisOf(s, m) === a);
    return i < 0 ? muted : s.measures[i].color || pal[i % pal.length];
  };
  const valueAxis = (a: AxisId, k: number): any => {
    const c = axisCfg(s, a);
    const ax: any = {
      gridcolor: grid,
      zerolinecolor: muted,
      linecolor: grid,
      tickfont: { color: a === 'y' ? muted : axisColor(a) },
      type: c.scale === 'log' ? 'log' : 'linear',
      title: k === 0 ? { text: c.title || defaultYTitle(s, a), font: { size: 12, color: axisColor(a) } } : undefined,
      rangemode: s.type.startsWith('barres') || s.type === 'histogramme' || s.measures.some((m) => axisOf(s, m) === a && markOf(s, m) === 'barres') ? 'tozero' : undefined,
      tickformat: s.stack === 'pourcent' && a === 'y' ? '.0f' : undefined,
      ticksuffix: s.stack === 'pourcent' && a === 'y' ? ' %' : c.suffix ? ` ${c.suffix}` : undefined,
      separatethousands: true,
      exponentformat: 'none',
      automargin: true,
    };
    if ((c.min ?? null) !== null || (c.max ?? null) !== null) {
      ax.range = [c.min ?? null, c.max ?? null];
      if (c.scale === 'log') ax.range = ax.range.map((v: any) => (v > 0 ? Math.log10(v) : null));
    }
    return ax;
  };

  if (!is3d && s.type !== 'secteurs') {
    if (nf > 1) layout.grid = { rows: nrows, columns: ncols, pattern: 'independent', xgap: used.length > 1 ? 0.16 : 0.08, ygap: 0.16 };
    const horizontal = s.type === 'barres_h';
    for (let k = 0; k < nf; k++) {
      const xk = k === 0 ? 'xaxis' : `xaxis${k + 1}`;
      const yk = k === 0 ? 'yaxis' : `yaxis${k + 1}`;
      const vAxis = valueAxis('y', k);
      const catAxis: any = {
        showgrid: false,
        linecolor: grid,
        tickfont: { color: muted },
        title: k === 0 ? { text: s.x_title ?? s.x ?? '', font: { size: 12, color: muted } } : undefined,
        automargin: true,
        type: s.type.startsWith('barres') || s.type === 'combine' || s.type === 'chaleur' ? 'category' : undefined,
      };
      if (RAW_TYPES.includes(s.type) && s.type !== 'boites' && s.type !== 'violons') {
        catAxis.type = undefined;
        catAxis.showgrid = true;
        catAxis.gridcolor = grid;
      }
      if (nf > 1 && s.facet_scale === 'commune' && k > 0) vAxis.matches = horizontal ? 'x' : 'y';
      layout[xk] = horizontal ? vAxis : catAxis;
      layout[yk] = horizontal ? { ...catAxis, autorange: 'reversed' } : vAxis;
      // axes secondaires de ce panneau
      for (const a of used.filter((u) => u !== 'y')) {
        const id = yId(k, a);
        const ax = valueAxis(a, nf > 1 ? (k === 0 ? 0 : 1) : 0);
        ax.overlaying = axisName(k, 'y');
        ax.showgrid = false;
        ax.side = a === 'y3' ? 'left' : 'right';
        if (a === 'y2') ax.anchor = axisName(k, 'x');
        else {
          ax.anchor = 'free';
          ax.autoshift = true;
          ax.position = a === 'y3' ? 0 : 1;
        }
        if (nf > 1 && s.facet_scale === 'commune' && k > 0) ax.matches = yId(0, a);
        layout[`yaxis${id.slice(1)}`] = ax;
      }
      if (nf > 1) {
        layout.annotations.push({
          text: `<b>${esc(String(facets[k] ?? '(vide)'))}</b>`,
          xref: `${k === 0 ? 'x' : `x${k + 1}`} domain`,
          yref: `${k === 0 ? 'y' : `y${k + 1}`} domain`,
          x: 0,
          y: 1.06,
          xanchor: 'left',
          yanchor: 'bottom',
          showarrow: false,
          font: { size: 12, color: ink },
        });
      }
    }
  }
  if (is3d) {
    layout.scene = {
      xaxis: { title: { text: s.x || '' }, gridcolor: grid },
      yaxis: { title: { text: s.type === 'surface3d' ? s.series || '' : s.y || '' }, gridcolor: grid },
      zaxis: { title: { text: s.type === 'surface3d' ? measureLabel(s.measures[0]) : s.z || '' }, gridcolor: grid },
    };
  }
  void firstOrder;

  // pied de graphique : source · auteur · date (+ structure)
  const foot = [
    t.source ? `Source : ${esc(t.source)}` : null,
    t.author ? `Réalisation : ${esc(t.author)}${opts.structureName ? ` (${esc(opts.structureName)})` : ''}` : null,
    t.show_date ? new Date().toLocaleDateString('fr-FR') : null,
    d.sampled ? `échantillon de ${d.rows.length.toLocaleString('fr-FR')} points sur ${d.total?.toLocaleString('fr-FR')}` : null,
  ]
    .filter(Boolean)
    .join('  ·  ');
  layout.annotations.push({
    text: foot,
    xref: 'paper',
    yref: 'paper',
    x: 0,
    y: 0,
    yshift: -bottom + 14,
    xanchor: 'left',
    yanchor: 'bottom',
    showarrow: false,
    font: { size: 11, color: muted },
  });
  if (t.caption) {
    layout.annotations.push({
      text: `<i>${esc(t.caption)}</i>`,
      xref: 'paper',
      yref: 'paper',
      x: 0,
      y: 0,
      yshift: -bottom + 32,
      xanchor: 'left',
      yanchor: 'bottom',
      showarrow: false,
      font: { size: 11, color: muted },
    });
  }
  if (t.show_logo && opts.logoUrl) {
    const pos = theme.chart.logo_position || 'bas-droite';
    layout.images.push({
      source: opts.logoUrl,
      xref: 'paper',
      yref: 'paper',
      x: pos.endsWith('droite') ? 1 : 0,
      y: pos.startsWith('haut') ? 1 : 0,
      sizex: 0.14,
      sizey: 0.1,
      xanchor: pos.endsWith('droite') ? 'right' : 'left',
      yanchor: pos.startsWith('haut') ? 'bottom' : 'top',
      yshift: 0,
      layer: 'above',
    });
    if (pos.startsWith('bas')) layout.images[0].y = -((bottom - 8) / t.height);
    else layout.images[0].y = 1 + (top - 12) / t.height - 0.1;
  }
  return { data: traces, layout };
}

function defaultYTitle(s: ChartSpec, a: AxisId = 'y'): string {
  if (RAW_TYPES.includes(s.type)) return s.type === 'histogramme' ? 'Effectif' : s.y || '';
  return s.measures.filter((m) => axisOf(s, m) === a).map(measureLabel).join(', ');
}

/** Couleur #rrggbb avec transparence. */
function hexA(c: string, a: number): string {
  const m = /^#?([0-9a-f]{6})$/i.exec(c || '');
  if (!m) return c;
  const n = parseInt(m[1], 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}

function esc(t: string): string {
  return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** Conseils de lecture et garde-fous affichés à côté du graphique. */
export function chartAdvice(s: ChartSpec, d: Data | null): string[] {
  const out: string[] = [];
  if (!s.template.source) out.push('Indiquez la source des données (obligatoire pour une diffusion).');
  if (!s.template.title) out.push('Donnez un titre qui dit ce que montre le graphique, pas seulement ce qu’il représente.');
  const nAxes = usedAxes(s).length;
  if (nAxes === 2)
    out.push('Deux axes verticaux : le lecteur peut croire à un lien entre les courbes. Légendez chaque axe (avec l’unité), ou préférez des petits multiples.');
  if (nAxes > 2)
    out.push(`${nAxes} axes verticaux : réservez-les à un public averti, donnez un titre et une unité à chaque axe ; les titres prennent la couleur de leur mesure.`);
  if (s.type === 'barres_h' && s.measures.some((m) => m.axis && m.axis !== 'y')) out.push('Barres horizontales : toutes les mesures partagent le même axe (axes secondaires ignorés).');
  if (s.facet && s.measures.some((m) => m.axis === 'y3' || m.axis === 'y4')) out.push('Petits multiples : deux axes au plus par panneau (les axes n° 2 sont regroupés avec les axes gauche et droit).');
  if (s.facet && s.facet_scale !== 'commune') out.push('Petits multiples à échelles indépendantes : comparez les formes, pas les hauteurs, ou choisissez une échelle commune.');
  if (s.type === 'secteurs' && d && d.rows.length > 6) out.push('Plus de 6 parts : un anneau devient illisible, préférez des barres horizontales triées.');
  if (s.y_scale === 'log') out.push('Échelle logarithmique : précisez-le dans le sous-titre, les écarts se lisent en rapports.');
  if (s.type.startsWith('barres') && s.y_min !== null && s.y_min !== undefined && s.y_min > 0) out.push('Des barres doivent partir de zéro : un minimum > 0 exagère les écarts.');
  if (d?.sampled) out.push('Le nuage affiche un échantillon aléatoire : les tendances restent valables, pas les effectifs.');
  if (s.measures.some((m) => m.agg === 'nombre_lignes') && !s.type.match(/barres|lignes/)) out.push('« Nombre de lignes » compte des lignes, pas des navires ni des marées : utilisez « Nombre distinct » sur l’identifiant.');
  return out;
}
