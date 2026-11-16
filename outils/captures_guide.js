// Captures d'écran du guide utilisateur, sur les données de démonstration (exemples/donnees_demo).
//
//   1. lancer Moanui sur un espace de travail VIDE :  cd backend && uv run moanui --home /tmp/guide --port 8811 --no-browser
//   2. node outils/captures_guide.js http://127.0.0.1:8811 docs/guide/images [échelle=2] [filtre]
//   3. cd backend && uv run python ../outils/construire_guide.py
//
// Chaque capture a un nom stable, référencé dans docs/guide/guide.md : relancer le script met les images à jour.
// Le « filtre » (facultatif) ne refait que les captures dont le nom contient l'un des motifs (séparés par des virgules).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const B = process.argv[2] || 'http://127.0.0.1:8811';
const OUT = process.argv[3] || 'docs/guide/images';
const SCALE = Number(process.argv[4] || 2);
const ONLY = process.argv[5] || '';
const D = path.join(__dirname, '..', 'exemples', 'donnees_demo') + path.sep;
const USER = { username: 'admin', password: 'motdepasse1' };

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: SCALE, acceptDownloads: true, locale: 'fr-FR' });
  const page = await ctx.newPage();
  page.setDefaultTimeout(20000);
  const api = ctx.request;
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  const wait = (ms) => page.waitForTimeout(ms);
  const shot = async (name, opts = {}) => {
    await wait(opts.delay ?? 700); // attendre même si la capture est filtrée : les étapes suivantes en dépendent
    if (ONLY && !ONLY.split(',').some((f) => name.includes(f))) return;
    const target = opts.locator ? (typeof opts.locator === 'string' ? page.locator(opts.locator).first() : opts.locator) : page;
    await target.screenshot({ path: path.join(OUT, `${name}.png`), fullPage: !!opts.full, clip: opts.clip });
    console.log('capture', name);
  };
  const tab = (name) => page.getByRole('tab', { name: new RegExp(`^${name}`) }).first().click();
  const btn = (name) => page.getByRole('button', { name, exact: false }).first().click();
  const pick = async (label, option) => {
    await page.getByLabel(label, { exact: true }).first().click();
    await page.getByRole('option', { name: option, exact: true }).first().click();
  };
  const post = async (url, data) => {
    const r = await api.post(B + url, { data });
    if (!r.ok()) throw new Error(`${url} : ${r.status()} ${await r.text()}`);
    return r.json();
  };
  const imp = async (name, kind) =>
    (await (await api.post(B + '/api/datasets/import', { multipart: { file: { name, mimeType: 'application/octet-stream', buffer: fs.readFileSync(D + name) }, ...(kind ? { kind } : {}) } })).json()).id;
  const section = async (title, fn) => {
    try {
      await fn();
    } catch (e) {
      console.log(`ÉCHEC ${title} : ${String(e).split('\n').slice(0, 3).join(' | ')}`);
      await page.screenshot({ path: path.join(OUT, `_echec_${title.replace(/\s+/g, '_')}.png`) }).catch(() => {});
      await page.keyboard.press('Escape').catch(() => {});
    }
  };

  // ------------------------------------------------------------------ 1. premier lancement
  await page.goto(B + '/');
  await wait(1000);
  if (await page.getByRole('button', { name: /Créer et commencer/ }).count()) {
    await page.getByLabel('Nom affiché').fill('Équipe données');
    await page.getByLabel('Identifiant de connexion').fill('admin');
    await shot('01_creation_compte');
    await post('/api/setup', { ...USER, display_name: 'Équipe données', structure_name: 'Comité fictif', structure_short_name: 'CF' });
  }
  await ctx.clearCookies();
  await page.goto(B + '/');
  await wait(800);
  await shot('02_connexion');
  await post('/api/auth/login', USER);

  // ------------------------------------------------------------------ jeux de démonstration
  const ids = {};
  for (const [n, k] of [['sacrois_2025.csv', 'sacrois'], ['sacrois_2024.csv', 'sacrois'], ['sacrois_2023_extrait_tonnes.csv', 'sacrois'], ['flotte_navires.xlsx'], ['ref_especes.csv'], ['vms_agiltech_2025.csv'], ['vms_cls_2025.csv'], ['suivi_casiers_homard.csv']])
    ids[n] = await imp(n, k);
  const S = ids['sacrois_2025.csv'];
  const VA = ids['vms_agiltech_2025.csv'];

  await section('accueil', async () => {
    await page.goto(B + '/');
    await page.getByText('sacrois_2025').first().waitFor();
    await shot('03_accueil');
    await page.goto(B + '/donnees');
    await shot('04_liste_donnees');
  });

  await section('import', async () => {
    await page.goto(B + '/donnees');
    await btn('Importer un fichier');
    await page.locator('input[type=file]').first().setInputFiles(D + 'ref_ports.csv');
    await wait(800);
    await shot('05_import_options', { locator: page.getByRole('dialog') });
    await page.getByRole('dialog').getByRole('button', { name: /Importer/ }).last().click();
    await page.getByText('Import réussi').waitFor();
    await shot('06_import_rapport', { locator: page.getByRole('dialog') });
    await page.keyboard.press('Escape');
  });

  // ------------------------------------------------------------------ 2. un jeu de données
  await section('jeu', async () => {
    await page.goto(`${B}/donnees/${S}`);
    await page.getByRole('tab', { name: 'Colonnes' }).waitFor();
    await shot('07_jeu_donnees');
    await page.locator('.ag-header').getByText('quartier_cod', { exact: true }).first().click();
    await shot('08_selection_colonne');
    await page.locator('.ag-header').getByText('quartier_cod', { exact: true }).first().click();
    for (const [t, n] of [['Lignes', '09_onglet_lignes'], ['Créer', '10_onglet_creer'], ['Regrouper', '11_onglet_regrouper'], ['Pêche', '12_onglet_peche']]) {
      await tab(t);
      await shot(n);
    }
  });

  const openDs = async (did) => {
    await page.goto(`${B}/donnees/${did}`);
    await page.getByRole('tab', { name: /^Colonnes/ }).waitFor();
    await wait(800);
  };
  await section('modele sacrois', async () => {
    await openDs(S);
    await tab('Pêche');
    await page.getByText('Préparation SACROIS / marées standard').first().click();
    await page.getByRole('dialog').waitFor();
    await shot('13_modele_sacrois', { locator: page.getByRole('dialog'), delay: 1200 });
    await page.getByRole('dialog').getByRole('button').last().click();
    await wait(4000);
    await tab('Historique');
    await shot('14_historique', { delay: 1500 });
  });

  await section('engins', async () => {
    await openDs(S);
    await tab('Pêche');
    await page.getByText('Cohérence engin / espèce').first().click();
    await page.getByRole('dialog').waitFor();
    await wait(800);
    await pick('Colonne espèce', 'esp_cod_fao');
    await pick('Colonne engin', 'engin_cod');
    await pick('Colonne navire (facultatif)', 'navire_cod');
    await page.getByRole('dialog').getByRole('button', { name: 'Charger les incohérences du jeu' }).click();
    await shot('15_coherence_engins', { locator: page.getByRole('dialog'), delay: 2500 });
    await page.keyboard.press('Escape');
  });

  await section('jointure etc', async () => {
    await openDs(S);
    await tab('Regrouper');
    await page.getByText('Associer un autre jeu (jointure)').first().click();
    await page.getByRole('dialog').waitFor();
    await page.getByLabel('Jeu à associer', { exact: true }).first().click();
    await page.getByRole('option', { name: /^ref_especes / }).first().click();
    await page.getByRole('dialog').getByPlaceholder('Jeu actuel').first().click();
    await page.getByRole('option', { name: 'esp_cod_fao', exact: true }).first().click();
    await wait(600);
    // la colonne du jeu associé est proposée automatiquement (même nom)
    await wait(4000);
    await shot('16_jointure', { locator: page.getByRole('dialog'), delay: 1500 });
    await page.keyboard.press('Escape');
    await page.getByText('Regrouper et résumer').first().click();
    await page.getByRole('dialog').waitFor();
    await page.getByLabel('Regrouper par').first().click();
    for (const o of ['esp_cod_fao', 'port_cod']) await page.getByRole('option', { name: o, exact: true }).click();
    await page.keyboard.press('Escape');
    await page.getByRole('dialog').getByPlaceholder('Colonne').first().click();
    await page.getByRole('option', { name: 'debarquement_Kg', exact: true }).click();
    await page.getByRole('dialog').getByText('Secret statistique : masquer').click();
    await wait(800);
    const nav = page.getByRole('dialog').getByLabel(/Colonne navire|Navire/);
    if (await nav.count()) { await nav.first().click(); await page.getByRole('option', { name: 'navire_cod', exact: true }).click(); }
    await shot('17_regrouper_resumer', { locator: page.getByRole('dialog'), delay: 2500 });
    await page.keyboard.press('Escape');
  });

  await section('qualite import methode', async () => {
    await openDs(S);
    await tab('Contrôle qualité');
    await page.getByText('Valeurs les plus fréquentes').first().waitFor({ timeout: 60000 });
    await shot('18_controle_qualite', { delay: 800 });
    await tab('Import');
    await shot('19_onglet_import');
    await tab('Fiche méthode & notes');
    await page.frameLocator('iframe').first().getByText('Données sources').first().waitFor({ timeout: 60000 }).catch(() => {});
    await shot('20_fiche_methode', { delay: 1500 });
  });

  await section('export', async () => {
    await page.goto(`${B}/donnees/${ids['flotte_navires.xlsx']}`);
    await page.getByRole('button', { name: 'Exporter' }).first().click();
    await wait(800);
    await shot('21_export');
    await page.getByRole('dialog').getByRole('button', { name: 'Exporter' }).click();
    await wait(1500);
    await shot('21b_export_sensible');
    await page.keyboard.press('Escape');
  });

  // empilement et jointure faits par l'API (pour les captures suivantes)
  const recipe = async (did, steps) => post(`/api/datasets/${did}/steps/batch`, { steps });
  await section('preparation API', async () => {
    await recipe(S, [{ type: 'join', params: { dataset_id: ids['flotte_navires.xlsx'], how: 'left', keys: [{ left: 'navire_cod', right: 'navire_cod' }] } }]);
    const v = await (await api.get(`${B}/api/datasets/${VA}/templates/vms`)).json();
    await recipe(VA, v.steps.map((s) => ({ type: s.type, params: s.params })));
    const vc = await (await api.get(`${B}/api/datasets/${ids['vms_cls_2025.csv']}/templates/vms`)).json();
    await recipe(ids['vms_cls_2025.csv'], vc.steps.map((s) => ({ type: s.type, params: s.params })));
  });

  await section('empilement', async () => {
    await openDs(ids['sacrois_2024.csv']);
    await tab('Regrouper');
    await page.getByText('Empiler d’autres jeux').first().click();
    await page.getByRole('dialog').waitFor();
    await page.getByLabel('Jeux à empiler sous le jeu actuel').first().click();
    for (const o of ['sacrois_2025', 'sacrois_2023_extrait_tonnes']) await page.getByRole('option', { name: new RegExp(`^${o} `) }).first().click();
    await page.keyboard.press('Escape');
    await page.getByRole('dialog').getByPlaceholder('fichier').fill('annee_fichier');
    await page.getByRole('dialog').getByText('Vérification').waitFor({ state: 'detached', timeout: 60000 }).catch(() => {});
    await shot('22_empilement', { locator: page.getByRole('dialog'), delay: 1500 });
    await page.keyboard.press('Escape');
  });

  // ------------------------------------------------------------------ 3. graphiques
  const base = { filters: [], stack: 'groupe', template: { title: '', subtitle: 'Flottille fictive, 2025', source: 'SACROIS (données fictives)', author: 'Équipe données', show_date: true, show_logo: false, caption: '', width: 1100, height: 620 } };
  const charts = {
    '23_graphique_barres': { ...base, type: 'barres', x: 'metier', sort: 'valeur_desc', measures: [{ agg: 'somme', column: 'debarquement_t' }], y_title: 'Débarquements (t)', template: { ...base.template, title: 'Débarquements par métier', width: 800, height: 560 } },
    '24_graphique_trois_axes': { ...base, type: 'combine', x: 'date_deb_mois', decimals: 0, measures: [{ agg: 'somme', column: 'debarquement_t', mark: 'barres', axis: 'y' }, { agg: 'somme', column: 'debarquement_euros', mark: 'lignes', axis: 'y2' }, { agg: 'moyenne', column: 'prix_moyen_kg', mark: 'points', axis: 'y3' }], axes: { y: { suffix: 't' }, y2: { title: 'Valeur (€)', suffix: '€' }, y3: { title: 'Prix moyen (€/kg)' } }, y_title: 'Débarquements (t)', refs: [{ kind: 'zone_v', value: '7', value2: '8', label: 'Été', color: '#eda100' }, { kind: 'ligne_h', value: 120, axis: 'y', label: 'Repère 120 t' }, { kind: 'note', value: '2', label: 'Tempête (fictive)' }], template: { ...base.template, title: 'Débarquements, valeur et prix moyen par mois' } },
    '25_graphique_petits_multiples': { ...base, type: 'lignes', x: 'date_deb_mois', facet: 'metier', facet_scale: 'commune', facet_cols: 3, series: 'NS', measures: [{ agg: 'somme', column: 'debarquement_t' }], y_title: 'Débarquements (t)', template: { ...base.template, title: 'Débarquements mensuels par métier et secteur', width: 1300, height: 820 } },
    '26_graphique_boites': { ...base, type: 'boites', x: 'metier', y: 'prix_moyen_kg', measures: [{ agg: 'somme' }], y_scale: 'log', template: { ...base.template, title: 'Prix moyen par métier (échelle logarithmique)' } },
  };
  const chartIds = {};
  await section('graphiques', async () => {
    for (const [n, spec] of Object.entries(charts)) chartIds[n] = (await post(`/api/datasets/${S}/charts`, { name: spec.template.title, spec })).id;
    for (const n of Object.keys(charts)) {
      await page.goto(`${B}/graphiques?dataset=${S}&chart=${chartIds[n]}`);
      await page.locator('.mo-chart-frame .main-svg').first().waitFor();
      // la page entière pour le premier, le graphique seul (taille réelle) pour les autres
      await shot(n, { delay: 1800, locator: n === '23_graphique_barres' ? undefined : '.mo-chart-frame' });
    }
    // réglages : axes, repères, mise en page
    await page.goto(`${B}/graphiques?dataset=${S}&chart=${chartIds['24_graphique_trois_axes']}`);
    await page.locator('.mo-chart-frame .main-svg').first().waitFor();
    await page.getByText('Données représentées').first().click();
    await page.getByText('Axes et échelles').first().click();
    await shot('27_graphique_reglages_axes', { delay: 1200 });
    await page.getByText('Axes et échelles').first().click();
    await page.getByText('Repères et annotations').first().click();
    await page.getByText('Mise en page').first().click();
    await shot('28_graphique_reperes_mise_en_page', { delay: 1200 });
    await page.getByRole('button', { name: 'Fiche méthode' }).click();
    await shot('29_menu_fiche', { delay: 500 });
    await page.keyboard.press('Escape');
  });

  // ------------------------------------------------------------------ 4. cartographie
  await section('cartes', async () => {
    const lay = await (await api.post(B + '/api/geo/layers', { multipart: { files: { name: 'zone_eolienne_fictive.geojson', mimeType: 'application/geo+json', buffer: fs.readFileSync(D + 'zone_eolienne_fictive.geojson') }, name: 'Zone éolienne fictive' } })).json();
    const tpl = { title: '', subtitle: '', source: 'Données fictives ; Shom, OFB, Natural Earth', author: 'Équipe données', show_logo: false, show_legend: true, show_date: true, width: 1200, height: 800 };
    const st = (color, kind, extra = {}) => ({ color, opacity: 1, fill: kind === 'polygone' ? 0.3 : 1, width: kind === 'point' ? 0.5 : 1.5, radius: 3, dashed: false, scale: null, ...extra });
    const maps = {
      '30_carte_contexte': { basemap: 'horsligne', center: [-4.6, 47.9], zoom: 7.2, layers: [
        { uid: 'a', kind: 'couche', title: 'Natura 2000 en mer', visible: true, geom: 'polygone', layerId: 'ctx:natura2000_mer', style: st('#1baf7a', 'polygone') },
        { uid: 'b', kind: 'couche', title: 'Limite des 12 milles', visible: true, geom: 'ligne', layerId: 'ctx:mer_territoriale_12m', style: st('#6250d6', 'ligne', { dashed: true }) },
        { uid: 'c', kind: 'couche', title: 'Rectangles statistiques CIEM', visible: true, geom: 'polygone', layerId: 'ctx:ciem_rectangles', style: st('#5f6b7a', 'polygone', { fill: 0 }) }], template: { ...tpl, title: 'Couches de contexte intégrées' } },
      '31_carte_positions_vms': { basemap: 'horsligne', center: [-4.2, 47.75], zoom: 8, layers: [
        { uid: 'p', kind: 'points', title: 'Positions VMS (Agiltech)', visible: true, geom: 'point', datasetId: VA, lon: 'lon', lat: 'lat', style: st('#2a78d6', 'point', { radius: 2 }) },
        { uid: 'z', kind: 'couche', title: 'Zone éolienne fictive', visible: true, geom: 'polygone', layerId: lay.id, style: st('#e34948', 'polygone') }], template: { ...tpl, title: 'Positions VMS et zone d’étude éolienne (fictives)' } },
      '32_carte_carroyage': { basemap: 'horsligne', center: [-4.3, 47.75], zoom: 8, layers: [
        { uid: 'g', kind: 'agregat', title: 'Navires par maille', visible: true, geom: 'polygone', datasetId: VA, lon: 'lon', lat: 'lat', agg: { mode: 'grille', cell: 0.05, agg: 'navires', vessel: 'navire', secret: 3 }, style: st('#2a78d6', 'polygone', { fill: 0.75, width: 0.5 }) },
        { uid: 'z', kind: 'couche', title: 'Zone éolienne fictive', visible: true, geom: 'polygone', layerId: lay.id, style: st('#e34948', 'polygone', { fill: 0 }) }], template: { ...tpl, title: 'Fréquentation : nombre de navires par maille (secret statistique)' } },
    };
    for (const [n, spec] of Object.entries(maps)) {
      const m = await post('/api/geo/maps', { name: spec.template.title, spec });
      await page.goto(`${B}/cartographie?map=${m.id}`);
      await wait(7000);
      await shot(n, { delay: 1500 });
      if (n === '32_carte_carroyage' && (!ONLY || ONLY.includes('32'))) {
        // couverture : la carte seule, sans titre, légende ni boutons
        const css = await page.addStyleTag({ content: '.mo-map-title,.mo-map-legend,.mo-map-scale,.maplibregl-control-container{display:none!important}' });
        const box = await page.locator('.maplibregl-canvas').first().boundingBox();
        await page.screenshot({ path: path.join(OUT, 'couverture.png'), clip: { x: box.x + box.width * 0.3, y: box.y + box.height * 0.3, width: 330, height: Math.min(540, box.height * 0.68) } });
        await css.evaluate((n) => n.remove());
      }
    }
    await page.getByRole('button', { name: /Ajouter/ }).first().click();
    await shot('33_carte_menu_ajouter', { delay: 600 });
    await page.getByText('Couche de contexte ou importée').first().click();
    await page.getByRole('dialog').waitFor();
    await shot('34_carte_ajouter_couche', { locator: page.getByRole('dialog'), delay: 800 });
    await page.keyboard.press('Escape');
  });

  await section('vms recette', async () => {
    await openDs(VA);
    await tab('Historique');
    await shot('35_vms_recette', { delay: 1500 });
    await tab('Pêche');
    await page.getByText('Répartir les captures sur les positions').first().click();
    await page.getByRole('dialog').waitFor();
    await shot('36_vms_sacrois', { locator: page.getByRole('dialog'), delay: 1200 });
    await page.keyboard.press('Escape');
  });

  // ------------------------------------------------------------------ 5. statistiques
  await section('stats groupes', async () => {
    await page.goto(`${B}/statistiques?dataset=${S}`);
    await wait(1500);
    await shot('37_stats_questions');
    await page.getByText('Comparer une mesure entre groupes').first().click();
    await pick('Mesure (numérique)', 'cpue_kg_jdm');
    await pick('Groupes (catégories)', 'metier (catégories)');
    await btn('Lancer l’analyse');
    await page.getByText('Écriture normalisée').first().waitFor({ timeout: 60000 });
    await shot('38_stats_resultats', { delay: 1500 });
    await page.setViewportSize({ width: 1440, height: 1300 });
    const top = (t) => page.getByText(t, { exact: true }).first().evaluate((el) => el.scrollIntoView({ block: 'start' }));
    await top('Écriture normalisée (à reprendre telle quelle dans un rapport)');
    await shot('39_stats_suite', { delay: 1500 });
    await top('Discussion');
    await shot('39b_stats_discussion', { delay: 1000 });
    await page.setViewportSize({ width: 1440, height: 900 });
  });

  await section('stats glm', async () => {
    await page.goto(`${B}/statistiques?dataset=${ids['suivi_casiers_homard.csv']}`);
    await wait(1500);
    await page.getByText('Modéliser des captures, comptages ou présences (GLM)').first().click();
    await pick('Mesure à modéliser (captures, nombre, 0 / 1)', 'nb_homards');
    await page.getByLabel('Facteurs explicatifs').first().click();
    await page.getByRole('option', { name: 'zone (catégories)', exact: true }).click();
    await page.getByRole('option', { name: 'annee', exact: true }).click();
    await page.keyboard.press('Escape');
    await pick('Effort (facultatif : jours de mer, heures, marées…)', 'nb_casiers');
    await pick('Test', 'Poisson (comptages)');
    await btn('Lancer l’analyse');
    await page.getByText('Analyse bloquée').first().waitFor({ timeout: 60000 });
    await shot('40_stats_bloquee', { delay: 1000 });
    await page.getByLabel('Test').first().click();
    await page.getByRole('option', { name: 'Binomiale négative (comptages dispersés)', exact: true }).click();
    await btn('Lancer l’analyse');
    await page.getByText('Écriture normalisée').first().waitFor({ timeout: 60000 });
    await page.setViewportSize({ width: 1440, height: 1300 });
    await page.getByText('Écriture normalisée (à reprendre telle quelle dans un rapport)', { exact: true }).first().evaluate((el) => el.scrollIntoView({ block: 'center' }));
    await shot('41_stats_glm', { delay: 2000 });
    await page.setViewportSize({ width: 1440, height: 900 });
  });

  // ------------------------------------------------------------------ 6. gestion
  await section('gestion', async () => {
    const m = (await (await api.get(`${B}/api/gestion/colonnes/${S}`)).json()).proposition;
    for (const [sp, kg, ann] of [['SOL', 20000, 21000], ['NEP', 70000, null], ['HKE', 400000, 360000], ['BSS', 12000, null]])
      await post('/api/gestion/suivis', { kind: 'quota', name: `Quota ${sp} 2025`, spec: { dataset_id: S, mapping: m, especes: [sp], debut: '2025-01-01', fin: '2025-12-31', quota_kg: kg, annonce_kg: ann, seuils: [80, 90, 100] } });
    await page.goto(B + '/gestion');
    await page.getByRole('cell', { name: 'Quota SOL 2025' }).waitFor();
    await shot('42_gestion_tableau', { delay: 1500 });
    await page.getByRole('cell', { name: 'Quota HKE 2025' }).click();
    await btn('Calculer');
    await page.locator('.main-svg').first().waitFor();
    await page.setViewportSize({ width: 1440, height: 1500 });
    await shot('43_gestion_quota', { delay: 2000 });
    await page.setViewportSize({ width: 1440, height: 900 });
    await tab('Limitations et dépassements');
    const [fc] = await Promise.all([page.waitForEvent('filechooser'), page.getByRole('button', { name: 'Importer des règles (CSV)' }).click()]);
    await fc.setFiles(D + 'limitations_2025_fictives.csv');
    await wait(500);
    await btn('Lancer le contrôle');
    await page.getByText('Par navire').first().waitFor();
    await wait(4500); // la notification d'import disparaît
    await page.setViewportSize({ width: 1440, height: 2100 });
    await shot('44_gestion_limitations', { delay: 1500 });
    await page.setViewportSize({ width: 1440, height: 900 });
  });

  // ------------------------------------------------------------------ 7. réglages
  await section('reglages', async () => {
    await page.goto(B + '/structure');
    await shot('46_charte', { delay: 1500 });
    await page.goto(B + '/administration');
    await shot('47_administration', { delay: 1500 });
    await page.goto(B + '/guide');
    await shot('48_bonnes_pratiques', { delay: 1200 });
  });

  console.log('erreurs de page', JSON.stringify(errors.slice(0, 5)));
  await browser.close();
})();
