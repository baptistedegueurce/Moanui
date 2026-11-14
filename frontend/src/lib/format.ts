export const nf = new Intl.NumberFormat('fr-FR');
export const nf2 = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 2 });

export function fmtNumber(v: any): string {
  if (v === null || v === undefined || v === '') return '';
  if (typeof v === 'number') return Number.isInteger(v) ? nf.format(v) : nf2.format(v);
  return String(v);
}

export function fmtDate(iso?: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
}

export function fmtSize(n: number): string {
  const units = ['o', 'Ko', 'Mo', 'Go'];
  let i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return `${n.toFixed(i ? 1 : 0)} ${units[i]}`;
}

export const TYPE_LABELS: Record<string, string> = {
  BIGINT: 'entier',
  INTEGER: 'entier',
  DOUBLE: 'décimal',
  FLOAT: 'décimal',
  VARCHAR: 'texte',
  DATE: 'date',
  TIMESTAMP: 'date-heure',
  BOOLEAN: 'vrai/faux',
  texte: 'texte',
  entier: 'entier',
  decimal: 'décimal',
  date: 'date',
  dateheure: 'date-heure',
  booleen: 'vrai/faux',
};

export function typeLabel(t: string): string {
  return TYPE_LABELS[t] || TYPE_LABELS[t.split('(')[0]] || t.toLowerCase();
}

export function isNumericType(t: string): boolean {
  return /^(TINYINT|SMALLINT|INTEGER|BIGINT|HUGEINT|U\w*INT|FLOAT|DOUBLE|REAL|DECIMAL)/i.test(t);
}

export function isTemporalType(t: string): boolean {
  return /^(DATE|TIMESTAMP)/i.test(t);
}

/** Étiquette courte du type, affichée dans les en-têtes et la liste des colonnes. */
export function typeTag(t: string): { label: string; cls: string } {
  if (isNumericType(t)) return { label: '123', cls: 'num' };
  if (isTemporalType(t)) return { label: 'date', cls: 'date' };
  if (t.toUpperCase().startsWith('BOOL')) return { label: 'oui/non', cls: 'bool' };
  return { label: 'abc', cls: 'txt' };
}

// tableau : toute la précision, virgule décimale, séparateur de milliers à partir de 10 000 (années intactes)
const nfGrid = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 12, useGrouping: 'min2' } as any);
export const fmtCell = (v: number) => nfGrid.format(v);
