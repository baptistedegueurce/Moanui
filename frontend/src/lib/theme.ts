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

/**
 * Thème de l'interface. Règles reprises de systèmes de design publics et éprouvés (pas de leur identité) :
 * échelle typographique « productive » et espacements de 2 / 4 / 8 px de Carbon (IBM), contrastes WCAG 2.1 AA
 * (4,5:1 pour le texte, 3:1 pour les bordures de champs), focus toujours visible (GOV.UK), angles quasi droits.
 */
export function mantineTheme(t: Theme) {
  const font = fontOf(t);
  return createTheme({
    primaryColor: 'charte',
    primaryShade: 6,
    colors: { charte: shades(t.colors.primary), accent: shades(t.colors.accent) },
    fontFamily: font,
    fontFamilyMonospace: "'IBM Plex Mono', Consolas, monospace",
    fontSizes: { xs: '12px', sm: '14px', md: '14px', lg: '16px', xl: '20px' },
    lineHeights: { xs: '1.34', sm: '1.43', md: '1.43', lg: '1.5', xl: '1.4' },
    spacing: { xs: '8px', sm: '12px', md: '16px', lg: '24px', xl: '32px' },
    focusRing: 'auto',
    headings: {
      fontFamily: font,
      fontWeight: '600',
      sizes: {
        h1: { fontSize: '28px', lineHeight: '1.29', fontWeight: '400' },
        h2: { fontSize: '24px', lineHeight: '1.33', fontWeight: '400' },
        h3: { fontSize: '20px', lineHeight: '1.4', fontWeight: '400' },
        h4: { fontSize: '16px', lineHeight: '1.375', fontWeight: '600' },
        h5: { fontSize: '14px', lineHeight: '1.29', fontWeight: '600' },
      },
    },
    defaultRadius: 'sm',
    radius: { xs: '0px', sm: '2px', md: '2px', lg: '4px', xl: '4px' },
    shadows: { xs: 'none', sm: '0 1px 2px rgba(0,0,0,.12)', md: '0 2px 6px rgba(0,0,0,.18)', lg: '0 2px 6px rgba(0,0,0,.18)', xl: '0 4px 12px rgba(0,0,0,.2)' },
    components: {
      Button: { defaultProps: { size: 'sm' }, styles: { root: { fontWeight: 500 } } },
      ActionIcon: { defaultProps: { variant: 'subtle', color: 'gray' } },
      Card: { defaultProps: { withBorder: true, shadow: undefined, padding: 'md' } },
      Badge: { defaultProps: { variant: 'light' }, styles: { root: { textTransform: 'none', fontWeight: 500, letterSpacing: 0 } } },
      Modal: { defaultProps: { overlayProps: { backgroundOpacity: 0.5 }, shadow: 'xl' } },
      Menu: { defaultProps: { shadow: 'md' } },
      Popover: { defaultProps: { shadow: 'md' } },
      Tabs: { styles: { tab: { fontWeight: 500 } } },
      Tooltip: { defaultProps: { withArrow: true, openDelay: 300, multiline: true, maw: 320 } },
      Alert: { defaultProps: { variant: 'light' } },
      Table: { defaultProps: { verticalSpacing: 8, horizontalSpacing: 12 } },
    },
  });
}

/** Barre du haut : la couleur principale de la charte, assombrie (texte blanc toujours lisible). */
export const headerOf = (t: Theme) => mix(t.colors.primary, '#000000', 0.35);

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
    '--mo-header': headerOf(t),
    '--mo-primary-soft': mix(t.colors.primary, '#ffffff', 0.9),
  };
}

export const NEUTRAL: Theme = {
  name: 'Neutre',
  colors: {
    primary: '#2F4858',
    primary_contrast: '#FFFFFF',
    accent: '#1F5F8B',
    background: '#F4F4F4',
    surface: '#FFFFFF',
    text: '#161616',
    muted: '#525252',
    border: '#E0E0E0',
  },
  // palette catégorielle validée (daltonisme, contraste) : l'ordre compte, ne pas le mélanger
  palette: ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6', '#e34948'],
  sequential: ['#cde2fb', '#9ec5f4', '#6da7ec', '#3987e5', '#256abf', '#184f95', '#0d366b'],
  diverging: ['#184f95', '#3987e5', '#9ec5f4', '#f0efec', '#f2a3a2', '#e34948', '#a32f2f'],
  font: "'IBM Plex Sans', 'Segoe UI', system-ui, sans-serif",
  chart: { show_logo: true, logo_position: 'bas-droite', default_source: '', background: '#FFFFFF', grid: '#E0E0E0' },
};
