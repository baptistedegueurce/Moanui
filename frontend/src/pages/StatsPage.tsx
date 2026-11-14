import { useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  Accordion,
  Alert,
  Badge,
  Button,
  Group,
  List,
  MultiSelect,
  Paper,
  ScrollArea,
  Select,
  Stack,
  Table,
  Text,
  Textarea,
  ThemeIcon,
  Title,
  UnstyledButton,
} from '@mantine/core';
import { IconCheck, IconAlertTriangle, IconBan, IconInfoCircle, IconFileText, IconDeviceFloppy, IconPlayerPlay } from '@tabler/icons-react';
import { api, downloadPost } from '../lib/api';
import { useAuth } from '../lib/auth';
import { isNumericType } from '../lib/format';
import { fail, ok } from '../lib/notify';
import { NEUTRAL, fontOf } from '../lib/theme';
import type { Column, DatasetSummary } from '../lib/types';
import { Conditions } from '../components/StepForm';

interface Analyse {
  titre: string;
  question: string;
  variables: { role: string; label: string; type: 'num' | 'cat' | 'any'; multiple?: boolean; optional?: boolean }[];
  tests: Record<string, string>;
}

interface Check {
  nom: string;
  ok: boolean;
  niveau: 'bloquant' | 'avertissement' | 'info';
  message: string;
  detail: string;
}

interface Res {
  titre: string;
  test: string;
  test_label: string;
  checks: Check[];
  bloque: boolean;
  alternative: string | null;
  force?: boolean;
  resultats: { nom: string; valeur: string }[];
  tableaux: { titre: string; colonnes: string[]; lignes: any[][] }[];
  interpretation: string[];
  limites: string[];
  graph: any;
  effectifs: Record<string, number>;
}

// Guides pas à pas (vulgarisation), affichés avant de lancer l'analyse
const GUIDES: Record<string, string[]> = {
  comparer_groupes: [
    'Choisissez la mesure (ex. débarquements en kg) et la variable qui définit les groupes (ex. engin).',
    'Une ligne = une observation indépendante : si vos lignes sont des espèces d’une même marée, regroupez d’abord par marée.',
    'Moanui vérifie la forme des distributions : si elles sont très asymétriques, il compare les rangs (Mann-Whitney, Kruskal-Wallis) plutôt que les moyennes.',
    'Avec plus de deux groupes, un résultat significatif est suivi des comparaisons deux à deux, corrigées pour éviter les faux positifs.',
  ],
  association: [
    'Choisissez deux variables à catégories (ex. quartier et engin).',
    'Le test regarde si la répartition de l’une change selon l’autre.',
    'Il faut suffisamment de lignes dans chaque case du tableau croisé : regroupez les catégories rares sinon.',
  ],
  correlation: [
    'Choisissez deux mesures numériques (ex. volume débarqué et prix moyen).',
    'Pearson mesure une relation en ligne droite ; Spearman, plus robuste, une relation qui monte (ou descend) toujours.',
    'Regardez toujours le nuage de points : une corrélation peut être créée par quelques points extrêmes.',
  ],
  regression: [
    'Choisissez la mesure à expliquer et un ou plusieurs facteurs (numériques ou catégories).',
    'Chaque coefficient se lit « à autres facteurs égaux ».',
    'Vérifiez le graphique des résidus : ils doivent former un nuage sans forme particulière autour de zéro.',
    'Pour des comptages, des captures très asymétriques ou une présence / absence, utilisez plutôt « Modéliser des captures, comptages ou présences (GLM) ».',
  ],
  glm: [
    'Choisissez la mesure : un nombre (individus, marées), une quantité positive (kg, CPUE) ou une présence codée 0 / 1.',
    'En automatique, Moanui choisit la famille : logistique pour 0 / 1, Poisson pour des comptages (binomiale négative si les comptages sont trop dispersés, cas le plus fréquent), Gamma pour des quantités positives.',
    'Effort (facultatif) : jours de mer, heures de pêche… Il est pris en « décalage » (offset) : le modèle porte alors sur la capture par unité d’effort, c’est la standardisation de CPUE.',
    'Pour obtenir un indice par année, mettez l’année en texte (étape « Changer le type ») et placez-la en premier facteur : le tableau « Valeurs prédites » donne l’indice standardisé.',
    'Les effets se lisent en multiplicateurs : « × 1,3 » = 30 % de plus, à autres facteurs égaux.',
    'Captures avec beaucoup de zéros : modèle « delta » en deux temps (présence 0 / 1 puis quantités positives) ; Moanui vous le signale.',
  ],
};

let plotlyPromise: Promise<any> | null = null;
const loadPlotly = () => (plotlyPromise ??= import('plotly.js-dist-min').then((m) => m.default || m));

function StatGraph({ g }: { g: any }) {
  const { structure } = useAuth();
  const theme = structure?.theme || NEUTRAL;
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!g || !ref.current) return;
    const pal = theme.palette;
    let data: any[] = [];
    const layout: any = {
      height: 380,
      margin: { l: 60, r: 20, t: 20, b: 50 },
      paper_bgcolor: '#fff',
      plot_bgcolor: '#fff',
      font: { family: fontOf(theme), size: 12, color: theme.colors.text },
      showlegend: false,
      separators: ', ',
      yaxis: { gridcolor: theme.chart.grid, title: { text: g.yname || g.y || '' } },
      xaxis: { gridcolor: theme.chart.grid, title: { text: g.xname || '' } },
    };
    if (g.type === 'boites') {
      data = g.groupes.map((name: string, i: number) => ({
        type: 'box',
        name,
        y: g.valeurs[i],
        boxpoints: 'outliers',
        marker: { color: pal[i % pal.length], size: 4 },
        line: { width: 1.5 },
      }));
    } else {
      data = [{ type: 'scattergl', mode: 'markers', x: g.x, y: g.y, marker: { color: pal[0], size: 6, opacity: 0.6 } }];
      if (g.type === 'residus') layout.shapes = [{ type: 'line', xref: 'paper', x0: 0, x1: 1, y0: 0, y1: 0, line: { color: theme.colors.muted, dash: 'dot' } }];
    }
    loadPlotly().then((P) => ref.current && P.react(ref.current, data, layout, { displaylogo: false, responsive: true }));
  }, [g, theme]);
  return <div ref={ref} />;
}

const ICON: Record<string, JSX.Element> = {
  ok: <IconCheck size={14} />,
  bloquant: <IconBan size={14} />,
  avertissement: <IconAlertTriangle size={14} />,
  info: <IconInfoCircle size={14} />,
};

export default function StatsPage() {
  const [params, setParams] = useSearchParams();
  const dsId = params.get('dataset');
  const [datasets, setDatasets] = useState<DatasetSummary[]>([]);
  const [catalogue, setCatalogue] = useState<Record<string, Analyse>>({});
  const [columns, setColumns] = useState<Column[]>([]);
  const [kind, setKind] = useState<string | null>(null);
  const [vars, setVars] = useState<Record<string, any>>({});
  const [test, setTest] = useState<string | null>(null);
  const [filters, setFilters] = useState<any[]>([]);
  const [res, setRes] = useState<Res | null>(null);
  const [busy, setBusy] = useState(false);
  const [justif, setJustif] = useState('');
  const [history, setHistory] = useState<any[]>([]);
  const { structure } = useAuth();

  useEffect(() => {
    api.get('/api/datasets').then(setDatasets).catch(fail);
    api.get('/api/stats/catalogue').then(setCatalogue).catch(fail);
  }, [structure?.id]);
  useEffect(() => {
    setRes(null);
    if (!dsId) return;
    api.get(`/api/datasets/${dsId}`).then((d) => setColumns(d.schema.filter((c: Column) => !c.name.startsWith('__')))).catch(fail);
    api.get(`/api/datasets/${dsId}/stats`).then(setHistory).catch(() => setHistory([]));
  }, [dsId]);

  const a = kind ? catalogue[kind] : null;
  const opts = (t: string) =>
    columns.filter((c) => (t === 'num' ? isNumericType(c.type) : true)).map((c) => ({ value: c.name, label: `${c.name}${isNumericType(c.type) ? '' : ' (catégories)'}` }));
  const complete = a?.variables.every((v) => v.optional || (v.multiple ? (vars[v.role] || []).length : vars[v.role]));
  const validFilters = filters.filter((c) => c.column && (['is_null', 'not_null'].includes(c.op) || (['in', 'not_in'].includes(c.op) ? c.values?.length : c.value !== '')));
  const body = (extra: any = {}) => ({ analyse: kind, variables: vars, test, filters: validFilters, ...extra });

  const run = async (extra: any = {}) => {
    setBusy(true);
    try {
      const r = await api.post<Res>(`/api/datasets/${dsId}/stats`, body(extra));
      setRes(r);
      if (extra.save) {
        ok('Analyse enregistrée dans l’historique');
        setHistory(await api.get(`/api/datasets/${dsId}/stats`));
      }
    } catch (e) {
      fail(e);
    } finally {
      setBusy(false);
    }
  };

  const forced = res?.force ? { force: true, justification: justif } : {};

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '380px minmax(0, 1fr)', gap: 16, height: 'calc(100vh - 88px)' }}>
      <Paper withBorder p="sm" style={{ overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        <ScrollArea style={{ flex: 1 }} offsetScrollbars>
          <Stack gap="sm">
            <Title order={4}>Statistiques</Title>
            <Select label="Jeu de données" searchable data={datasets.map((d) => ({ value: d.id, label: d.name }))} value={dsId} onChange={(v) => v && setParams({ dataset: v })} />
            <Text size="sm" fw={600}>
              Quelle est votre question ?
            </Text>
            <Stack gap={6}>
              {Object.entries(catalogue).map(([k, c]) => (
                <UnstyledButton
                  key={k}
                  onClick={() => {
                    setKind(k);
                    setVars({});
                    setTest(null);
                    setRes(null);
                  }}
                >
                  <Paper withBorder p="xs" style={{ borderColor: kind === k ? 'var(--mo-accent)' : undefined, borderWidth: kind === k ? 2 : 1 }}>
                    <Text size="sm" fw={600}>
                      {c.titre}
                    </Text>
                    <Text size="xs" c="dimmed">
                      {c.question}
                    </Text>
                  </Paper>
                </UnstyledButton>
              ))}
            </Stack>
            {a && dsId && (
              <>
                <Accordion variant="contained">
                  <Accordion.Item value="guide">
                    <Accordion.Control>Pas à pas</Accordion.Control>
                    <Accordion.Panel>
                      <List size="xs" spacing={4} type="ordered">
                        {(GUIDES[kind!] || []).map((g) => (
                          <List.Item key={g}>{g}</List.Item>
                        ))}
                      </List>
                    </Accordion.Panel>
                  </Accordion.Item>
                </Accordion>
                {a.variables.map((v) =>
                  v.multiple ? (
                    <MultiSelect key={v.role} label={v.label} searchable data={opts(v.type)} value={vars[v.role] || []} onChange={(x) => setVars({ ...vars, [v.role]: x })} />
                  ) : (
                    <Select key={v.role} label={v.label} searchable clearable={!!v.optional} data={opts(v.type)} value={vars[v.role] || null} onChange={(x) => setVars({ ...vars, [v.role]: x })} />
                  ),
                )}
                <Select
                  label="Test"
                  description="Automatique : Moanui choisit selon les conditions vérifiées"
                  data={[{ value: '', label: 'Automatique (recommandé)' }, ...Object.entries(a.tests).map(([k2, l]) => ({ value: k2, label: l }))]}
                  value={test || ''}
                  onChange={(x) => setTest(x || null)}
                  allowDeselect={false}
                />
                <Accordion variant="contained">
                  <Accordion.Item value="filtres">
                    <Accordion.Control>Restreindre les données ({validFilters.length})</Accordion.Control>
                    <Accordion.Panel>
                      <Conditions value={{ conditions: filters, logic: 'and' }} onChange={(v) => setFilters(v.conditions || [])} columns={columns} datasetId={dsId} />
                    </Accordion.Panel>
                  </Accordion.Item>
                </Accordion>
                <Button leftSection={<IconPlayerPlay size={16} />} disabled={!complete} loading={busy} onClick={() => run()}>
                  Lancer l’analyse
                </Button>
              </>
            )}
            {history.length > 0 && (
              <>
                <Text size="sm" fw={600} mt="sm">
                  Historique
                </Text>
                {history.slice(0, 15).map((h) => (
                  <UnstyledButton
                    key={h.id}
                    onClick={() => {
                      setKind(h.spec.analyse);
                      setVars(h.spec.variables);
                      setTest(h.spec.test);
                      setFilters(h.spec.filters || []);
                      setRes(null);
                    }}
                  >
                    <Text size="xs" lineClamp={2}>
                      {h.titre}
                    </Text>
                    <Text size="10px" c="dimmed">
                      {h.auteur} · {new Date(h.created_at).toLocaleDateString('fr-FR')}
                    </Text>
                  </UnstyledButton>
                ))}
              </>
            )}
          </Stack>
        </ScrollArea>
      </Paper>

      <ScrollArea type="auto">
        {!res ? (
          <div className="mo-panel" style={{ maxWidth: 860 }}>
            <div className="mo-panel-head">Fonctionnement</div>
            <div style={{ padding: '14px 18px' }}>
              <Text size="sm" mb="sm">
                Choisissez une question à gauche, puis les colonnes concernées. Moanui vérifie les conditions d’application, choisit le test adapté et, si une condition
                n’est pas remplie, bloque en proposant une alternative (un passage en force reste possible avec une justification écrite). Le résultat comprend la
                taille de l’effet, une interprétation, les limites et une fiche méthode avec figures et références.
              </Text>
              <table className="mo-doc-table">
                <thead>
                  <tr>
                    <th>Question</th>
                    <th>Tests possibles</th>
                  </tr>
                </thead>
                <tbody>
                  {Object.entries(catalogue).map(([k, c]) => (
                    <tr key={k}>
                      <td>{c.titre}</td>
                      <td>{Object.values(c.tests).join(', ')}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <Text size="xs" c="dimmed">
                Rappel : une ligne doit correspondre à une observation indépendante. Si vos lignes sont des espèces d’une même marée, regroupez d’abord par marée.
              </Text>
            </div>
          </div>
        ) : (
          <Stack>
            <Group justify="space-between">
              <div>
                <Title order={3}>{res.titre}</Title>
                <Text c="dimmed" size="sm">
                  {res.test_label} · {res.effectifs.lignes_utilisees} observations
                </Text>
              </div>
              {(!res.bloque || res.force) && (
                <Group gap="xs">
                  <Button
                    variant="default"
                    leftSection={<IconFileText size={16} />}
                    onClick={() => downloadPost(`/api/datasets/${dsId}/stats/method.zip`, body(forced), `analyse_${kind}.zip`).catch(fail)}
                  >
                    Fiche méthode
                  </Button>
                  <Button leftSection={<IconDeviceFloppy size={16} />} onClick={() => run({ ...forced, save: true })}>
                    Enregistrer
                  </Button>
                </Group>
              )}
            </Group>

            {res.bloque && !res.force && (
              <Alert color="red" icon={<IconBan />} title="Analyse bloquée : une condition n’est pas remplie">
                <Stack gap="xs">
                  {(() => {
                    const bl = res.checks.filter((c) => !c.ok && c.niveau === 'bloquant');
                    const details = [...new Set(bl.map((c) => c.detail).filter(Boolean))];
                    return (
                      <>
                        {bl.slice(0, 4).map((c) => (
                          <Text size="sm" key={c.nom}>
                            <b>{c.nom}</b> : {c.message}
                          </Text>
                        ))}
                        {bl.length > 4 && <Text size="sm">… et {bl.length - 4} autre(s) condition(s) du même type.</Text>}
                        {details.map((d) => (
                          <Text size="sm" fs="italic" key={d}>
                            {d}
                          </Text>
                        ))}
                      </>
                    );
                  })()}
                  <Group align="flex-end">
                    {res.alternative && a && (
                      <Button
                        color="teal"
                        onClick={() => {
                          setTest(res.alternative);
                          setBusy(true);
                          api
                            .post<Res>(`/api/datasets/${dsId}/stats`, { ...body(), test: res.alternative })
                            .then(setRes)
                            .catch(fail)
                            .finally(() => setBusy(false));
                        }}
                      >
                        Utiliser plutôt : {a.tests[res.alternative]}
                      </Button>
                    )}
                  </Group>
                  <Textarea
                    label="Ou passer outre (justification obligatoire, reprise dans la fiche méthode)"
                    placeholder="Ex. : validé avec le référent statistique ; robustesse vérifiée par un test non paramétrique"
                    value={justif}
                    onChange={(e) => setJustif(e.currentTarget.value)}
                    autosize
                    minRows={2}
                  />
                  <Button variant="outline" color="red" w="fit-content" disabled={!justif.trim()} onClick={() => run({ force: true, justification: justif })}>
                    Passer outre et afficher les résultats
                  </Button>
                </Stack>
              </Alert>
            )}
            {res.force && (
              <Alert color="orange" icon={<IconAlertTriangle />}>
                Résultats affichés malgré une condition non remplie (justification : « {justif} »). À interpréter avec prudence.
              </Alert>
            )}

            <Paper withBorder p="md">
              <Text fw={600} mb="xs">
                Conditions vérifiées
              </Text>
              <Stack gap={6}>
                {res.checks.map((c, i) => (
                  <Group key={i} gap="xs" wrap="nowrap" align="flex-start">
                    <ThemeIcon size="sm" radius="xl" color={c.ok ? 'teal' : c.niveau === 'bloquant' ? 'red' : c.niveau === 'avertissement' ? 'orange' : 'blue'}>
                      {c.ok ? ICON.ok : ICON[c.niveau]}
                    </ThemeIcon>
                    <Text size="sm">
                      <b>{c.nom}</b> : {c.message}
                    </Text>
                  </Group>
                ))}
              </Stack>
            </Paper>

            {res.interpretation.length > 0 && (
              <Alert color="blue" variant="light" title="Ce qu’il faut retenir">
                <Stack gap={4}>
                  {res.interpretation.map((p) => (
                    <Text size="sm" key={p}>
                      {p}
                    </Text>
                  ))}
                </Stack>
              </Alert>
            )}

            {res.resultats.length > 0 && (
              <Group gap="xs">
                {res.resultats.map((r) => (
                  <Paper withBorder p="xs" key={r.nom}>
                    <Text size="xs" c="dimmed">
                      {r.nom}
                    </Text>
                    <Text fw={600}>{r.valeur}</Text>
                  </Paper>
                ))}
              </Group>
            )}

            {res.graph && (!res.bloque || res.force) && (
              <Paper withBorder p="xs">
                <StatGraph g={res.graph} />
              </Paper>
            )}

            {res.tableaux.map((t) => (
              <Paper withBorder key={t.titre}>
                <Text fw={600} p="xs">
                  {t.titre}
                </Text>
                <ScrollArea>
                  <Table fz="sm" striped>
                    <Table.Thead>
                      <Table.Tr>
                        {t.colonnes.map((c) => (
                          <Table.Th key={c}>{c}</Table.Th>
                        ))}
                      </Table.Tr>
                    </Table.Thead>
                    <Table.Tbody>
                      {t.lignes.map((row, i) => (
                        <Table.Tr key={i}>
                          {row.map((v, j) => (
                            <Table.Td key={j}>{v === 'oui' ? <Badge color="teal" variant="light">oui</Badge> : String(v)}</Table.Td>
                          ))}
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                </ScrollArea>
              </Paper>
            ))}

            {res.limites.length > 0 && (
              <Paper withBorder p="md">
                <Text fw={600} size="sm">
                  Limites à garder en tête
                </Text>
                <List size="sm" mt={4}>
                  {res.limites.map((l) => (
                    <List.Item key={l}>{l}</List.Item>
                  ))}
                </List>
              </Paper>
            )}
          </Stack>
        )}
      </ScrollArea>
    </div>
  );
}
