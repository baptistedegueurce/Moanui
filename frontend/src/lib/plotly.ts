// Chargement à la demande de Plotly, avec la locale française (mois, jours, séparateurs).
let p: Promise<any> | null = null;

const FR = {
  moduleType: 'locale',
  name: 'fr',
  dictionary: {
    Autoscale: 'Échelle automatique',
    'Reset axes': 'Réinitialiser les axes',
    'Zoom in': 'Zoom avant',
    'Zoom out': 'Zoom arrière',
    Pan: 'Déplacer',
    Zoom: 'Zoom',
    'Download plot as a png': 'Télécharger en PNG',
    'Toggle Spike Lines': 'Lignes de repère',
    'Show closest data on hover': 'Valeur la plus proche',
    'Compare data on hover': 'Comparer au survol',
  },
  format: {
    days: ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'],
    shortDays: ['dim.', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.'],
    months: ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'],
    shortMonths: ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'],
    date: '%d/%m/%Y',
    decimal: ',',
    thousands: ' ',
  },
};

export function loadPlotly(): Promise<any> {
  return (p ??= import('plotly.js-dist-min').then((m) => {
    const P = m.default || m;
    P.register(FR);
    P.setPlotConfig({ locale: 'fr' });
    return P;
  }));
}
