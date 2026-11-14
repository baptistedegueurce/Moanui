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

export interface Measure {
  column?: string;
  agg: string;
  axis?: 'y' | 'y2';
  mark?: 'barres' | 'lignes';
  label?: string;
}

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
  return { x: s.x, series: s.series, facet: s.facet, measures: s.measures, filters };
}

interface Data {
  columns: string[];
  rows: any[][];
  sampled?: boolean;
  total?: number | null;
}

const fmtFr = (v: any) => (typeof v === 'number' ? v.toLocaleString('fr-FR', { maximumFractionDigits: 2 }) : v);

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
  const ncols = nf > 1 ? Math.ceil(Math.sqrt(nf)) : 1;
  const nrows = Math.ceil(nf / ncols);
  const axisName = (k: number, a: 'x' | 'y') => (k === 0 ? a : `${a}${k + 1}`);

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

    // --- graphiques agrégés : barres, courbes, aires, combiné
    const mStart = d.columns.length - s.measures.length;
    const xs = [...new Set(rows.map((r) => r[xi]))];
    let order = xs;
    if (s.sort && s.sort !== 'aucun' && s.measures.length) {
      const tot = new Map<any, number>();
      rows.forEach((r) => tot.set(r[xi], (tot.get(r[xi]) || 0) + (r[mStart] || 0)));
      order = [...xs].sort((a, b) => ((tot.get(a) || 0) - (tot.get(b) || 0)) * (s.sort === 'valeur_desc' ? -1 : 1));
    }
    const horizontal = s.type === 'barres_h';
    s.measures.forEach((m, mi) => {
      const groups = si >= 0 ? seriesValues : [null];
      groups.forEach((g) => {
        const rr = si >= 0 ? rows.filter((r) => r[si] === g) : rows;
        const byX = new Map(rr.map((r) => [r[xi], r[mStart + mi]]));
        const xv = order;
        const yv = order.map((x) => byX.get(x) ?? null);
        const name = [s.measures.length > 1 ? measureLabel(m) : null, g === null ? null : String(g)].filter(Boolean).join(' · ') || measureLabel(m);
        const color = si >= 0 ? colorOf(g) : pal[mi % pal.length];
        const mark = s.type === 'combine' ? m.mark || 'barres' : s.type === 'lignes' || s.type === 'aires' ? 'lignes' : 'barres';
        const yaxis = m.axis === 'y2' && nf === 1 ? 'y2' : ya;
        const base: any = { name, legendgroup: name, showlegend: showLegend, xaxis: xa, yaxis };
        const hover = `${horizontal ? '%{y}' : '%{x}'}<br>${name} : %{${horizontal ? 'x' : 'y'}:,.2f}<extra></extra>`;
        if (mark === 'barres') {
          traces.push({
            ...base,
            type: 'bar',
            orientation: horizontal ? 'h' : 'v',
            x: horizontal ? yv : xv,
            y: horizontal ? xv : yv,
            marker: { color, line: { color: theme.chart.background, width: 1 }, cornerradius: 3 },
            text: s.show_values ? yv.map(fmtFr) : undefined,
            textposition: s.show_values ? 'outside' : undefined,
            cliponaxis: false,
            hovertemplate: hover,
          });
        } else {
          traces.push({
            ...base,
            type: 'scatter',
            mode: xv.length > 40 ? 'lines' : 'lines+markers',
            x: xv,
            y: yv,
            line: { color, width: 2.2 },
            marker: { color, size: 7 },
            fill: s.type === 'aires' ? (s.stack !== 'groupe' ? 'tonexty' : 'tozeroy') : undefined,
            stackgroup: s.type === 'aires' && s.stack !== 'groupe' ? `s${mi}` : undefined,
            groupnorm: s.type === 'aires' && s.stack === 'pourcent' ? 'percent' : undefined,
            connectgaps: false,
            hovertemplate: hover,
          });
        }
      });
    });
  });

  // --- mise en page
  const t = s.template;
  const top = 64 + (t.subtitle ? 22 : 0);
  const bottom = 70 + (t.caption ? 18 : 0);
  const layout: any = {
    width: t.width,
    height: t.height,
    paper_bgcolor: theme.chart.background,
    plot_bgcolor: theme.chart.background,
    font: { family: fontOf(theme), color: ink, size: 13 },
    margin: { l: 72, r: s.measures.some((m) => m.axis === 'y2') ? 72 : 32, t: top, b: bottom },
    title: {
      text: `<b>${esc(t.title || '')}</b>${t.subtitle ? `<br><span style="font-size:13px;color:${muted}">${esc(t.subtitle)}</span>` : ''}`,
      x: 0.01,
      xanchor: 'left',
      y: 0.985,
      yanchor: 'top',
      font: { size: 18 },
    },
    legend: { orientation: 'h', x: 0, y: 1.0, yanchor: 'bottom', font: { size: 12, color: ink } },
    barmode: s.stack === 'empile' ? 'stack' : s.stack === 'pourcent' ? 'relative' : 'group',
    barnorm: s.stack === 'pourcent' ? 'percent' : undefined,
    bargap: 0.25,
    hoverlabel: { font: { family: theme.font } },
    separators: ', ',
    annotations: [] as any[],
    images: [] as any[],
  };

  if (!is3d && s.type !== 'secteurs') {
    if (nf > 1) layout.grid = { rows: nrows, columns: ncols, pattern: 'independent', xgap: 0.08, ygap: 0.16 };
    for (let k = 0; k < nf; k++) {
      const xk = k === 0 ? 'xaxis' : `xaxis${k + 1}`;
      const yk = k === 0 ? 'yaxis' : `yaxis${k + 1}`;
      const horizontal = s.type === 'barres_h';
      const valueAxis: any = {
        gridcolor: grid,
        zerolinecolor: muted,
        linecolor: grid,
        tickfont: { color: muted },
        type: s.y_scale === 'log' ? 'log' : 'linear',
        title: k === 0 ? { text: s.y_title || defaultYTitle(s), font: { size: 12, color: muted } } : undefined,
        rangemode: s.type.startsWith('barres') || s.type === 'histogramme' ? 'tozero' : undefined,
        tickformat: s.stack === 'pourcent' ? '.0f' : undefined,
        ticksuffix: s.stack === 'pourcent' ? ' %' : undefined,
        automargin: true,
      };
      if ((s.y_min ?? null) !== null || (s.y_max ?? null) !== null) {
        valueAxis.range = [s.y_min ?? null, s.y_max ?? null];
        if (s.y_scale === 'log') valueAxis.range = valueAxis.range.map((v: any) => (v > 0 ? Math.log10(v) : null));
      }
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
      layout[xk] = horizontal ? valueAxis : catAxis;
      layout[yk] = horizontal ? { ...catAxis, autorange: 'reversed' } : valueAxis;
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
    if (s.measures.some((m) => m.axis === 'y2') && nf === 1) {
      layout.yaxis2 = {
        overlaying: 'y',
        side: 'right',
        showgrid: false,
        tickfont: { color: muted },
        title: { text: s.y2_title || s.measures.filter((m) => m.axis === 'y2').map(measureLabel).join(', '), font: { size: 12, color: muted } },
        rangemode: 'tozero',
        automargin: true,
      };
    }
  }
  if (is3d) {
    layout.scene = {
      xaxis: { title: { text: s.x || '' }, gridcolor: grid },
      yaxis: { title: { text: s.type === 'surface3d' ? s.series || '' : s.y || '' }, gridcolor: grid },
      zaxis: { title: { text: s.type === 'surface3d' ? measureLabel(s.measures[0]) : s.z || '' }, gridcolor: grid },
    };
  }

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

function defaultYTitle(s: ChartSpec): string {
  if (RAW_TYPES.includes(s.type)) return s.type === 'histogramme' ? 'Effectif' : s.y || '';
  const left = s.measures.filter((m) => m.axis !== 'y2');
  return left.map(measureLabel).join(', ');
}

function esc(t: string): string {
  return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

/** Conseils de lecture et garde-fous affichés à côté du graphique. */
export function chartAdvice(s: ChartSpec, d: Data | null): string[] {
  const out: string[] = [];
  if (!s.template.source) out.push('Indiquez la source des données (obligatoire pour une diffusion).');
  if (!s.template.title) out.push('Donnez un titre qui dit ce que montre le graphique, pas seulement ce qu’il représente.');
  if (s.measures.some((m) => m.axis === 'y2'))
    out.push('Deux axes verticaux : le lecteur peut croire à un lien entre les courbes. Légendez chaque axe, ou préférez deux graphiques côte à côte (petits multiples).');
  if (s.type === 'secteurs' && d && d.rows.length > 6) out.push('Plus de 6 parts : un anneau devient illisible, préférez des barres horizontales triées.');
  if (s.y_scale === 'log') out.push('Échelle logarithmique : précisez-le dans le sous-titre, les écarts se lisent en rapports.');
  if (s.type.startsWith('barres') && s.y_min !== null && s.y_min !== undefined && s.y_min > 0) out.push('Des barres doivent partir de zéro : un minimum > 0 exagère les écarts.');
  if (d?.sampled) out.push('Le nuage affiche un échantillon aléatoire : les tendances restent valables, pas les effectifs.');
  if (s.measures.some((m) => m.agg === 'nombre_lignes') && !s.type.match(/barres|lignes/)) out.push('« Nombre de lignes » compte des lignes, pas des navires ni des marées : utilisez « Nombre distinct » sur l’identifiant.');
  return out;
}
