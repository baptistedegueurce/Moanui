import { createTheme, MantineColorsTuple } from '@mantine/core';
import type { Theme } from './types';

function hexToRgb(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function rgbToHex([r, g, b]: number[]): string {
  return '#' + [r, g, b].map((x) => Math.round(Math.max(0, Math.min(255, x))).toString(16).padStart(2, '0')).join('');
}

function mix(a: string, b: string, t: number): string {
  const ca = hexToRgb(a);
  const cb = hexToRgb(b);
  return rgbToHex(ca.map((x, i) => x + (cb[i] - x) * t));
}

/** Génère les 10 nuances attendues par Mantine à partir d'une couleur de charte. */
export function shades(hex: string): MantineColorsTuple {
  const light = [0.92, 0.82, 0.68, 0.5, 0.3, 0.12].map((t) => mix(hex, '#ffffff', t));
  const dark = [0.15, 0.3, 0.45].map((t) => mix(hex, '#000000', t));
  return [...light, hex, ...dark] as unknown as MantineColorsTuple;
}

/** Police embarquée (fonctionne hors ligne) ; les anciennes chartes « Inter » basculent dessus. */
export const FONT = "'IBM Plex Sans', 'Segoe UI', system-ui, sans-serif";
export const fontOf = (t: Theme) => (!t.font || t.font.startsWith('Inter') ? FONT : t.font);

export function mantineTheme(t: Theme) {
  const font = fontOf(t);
  return createTheme({
    primaryColor: 'charte',
    primaryShade: 6,
    colors: { charte: shades(t.colors.primary), accent: shades(t.colors.accent) },
    fontFamily: font,
    fontFamilyMonospace: "'IBM Plex Mono', Consolas, monospace",
    headings: {
      fontFamily: font,
      fontWeight: '600',
      sizes: { h1: { fontSize: '26px', lineHeight: '1.25' }, h2: { fontSize: '22px', lineHeight: '1.3' }, h3: { fontSize: '18px', lineHeight: '1.35' }, h4: { fontSize: '15px', lineHeight: '1.4' } },
    },
    defaultRadius: 'sm',
    radius: { xs: '2px', sm: '4px', md: '6px', lg: '8px', xl: '12px' },
    components: {
      Button: { defaultProps: { radius: 'sm' }, styles: { root: { fontWeight: 500 } } },
      Card: { defaultProps: { radius: 'sm', withBorder: true, shadow: undefined } },
      Paper: { defaultProps: { radius: 'sm' } },
      Badge: { defaultProps: { radius: 'sm' }, styles: { root: { textTransform: 'none', fontWeight: 500, letterSpacing: 0 } } },
      Modal: { defaultProps: { radius: 'sm', overlayProps: { backgroundOpacity: 0.35 } } },
      Tabs: { styles: { tab: { fontWeight: 500 } } },
      Tooltip: { defaultProps: { withArrow: true, openDelay: 300, multiline: true, maw: 320 } },
    },
  });
}

export function cssVars(t: Theme): Record<string, string> {
  return {
    '--mo-bg': t.colors.background,
    '--mo-surface': t.colors.surface,
    '--mo-text': t.colors.text,
    '--mo-muted': t.colors.muted,
    '--mo-border': t.colors.border,
    '--mo-primary': t.colors.primary,
    '--mo-primary-contrast': t.colors.primary_contrast,
    '--mo-accent': t.colors.accent,
    '--mo-mono': "'IBM Plex Mono', Consolas, monospace",
  };
}

export const NEUTRAL: Theme = {
  name: 'Neutre',
  colors: {
    primary: '#2F4858',
    primary_contrast: '#FFFFFF',
    accent: '#3A7CA5',
    background: '#F6F7F9',
    surface: '#FFFFFF',
    text: '#1C2430',
    muted: '#5F6B7A',
    border: '#DDE2E8',
  },
  // palette catégorielle validée (daltonisme, contraste) : l'ordre compte, ne pas le mélanger
  palette: ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6', '#e34948'],
  sequential: ['#cde2fb', '#9ec5f4', '#6da7ec', '#3987e5', '#256abf', '#184f95', '#0d366b'],
  diverging: ['#184f95', '#3987e5', '#9ec5f4', '#f0efec', '#f2a3a2', '#e34948', '#a32f2f'],
  font: "'IBM Plex Sans', 'Segoe UI', system-ui, sans-serif",
  chart: { show_logo: true, logo_position: 'bas-droite', default_source: '', background: '#FFFFFF', grid: '#E6E9EE' },
};
