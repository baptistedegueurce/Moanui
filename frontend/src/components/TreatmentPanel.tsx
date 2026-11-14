// Panneau de traitement : opérations classées par colonne, ligne, création, regroupement et métier,
// à la manière de l'ancienne application, mais chaque opération reste une étape de recette (traçable,
// réversible). Les opérations simples s'appliquent directement ; les autres ouvrent un formulaire avec aperçu.
import { useEffect, useMemo, useState } from 'react';
import {
  ActionIcon,
  Anchor,
  Badge,
  Button,
  Checkbox,
  Group,
  NumberInput,
  ScrollArea,
  SegmentedControl,
  Select,
  Stack,
  Tabs,
  Text,
  TextInput,
  Tooltip,
  UnstyledButton,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import {
  IconArrowBackUp,
  IconColumns3,
  IconLayoutRows,
  IconPlus,
  IconStack2,
  IconAnchor,
  IconHistory,
  IconSearch,
  IconChevronRight,
  IconListDetails,
} from '@tabler/icons-react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtNumber, isNumericType, isTemporalType, typeTag } from '../lib/format';
import { fail } from '../lib/notify';
import type { Column, Step } from '../lib/types';
import RecipePanel from './RecipePanel';
import { Conditions } from './StepForm';
import type { StepDraft } from './StepModal';

export type TreatTab = 'colonnes' | 'lignes' | 'creer' | 'regrouper' | 'metier' | 'historique';

/** Ligne de catalogue : titre + une phrase, ouvre le formulaire complet. */
function Entry({ title, text, onClick, disabled }: { title: string; text: string; onClick: () => void; disabled?: boolean }) {
  return (
    <UnstyledButton className="mo-entry" onClick={onClick} disabled={disabled} data-disabled={disabled || undefined}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <Text size="sm" fw={600}>
          {title}
        </Text>
        <Text size="xs" c="dimmed">
          {text}
        </Text>
      </div>
      <IconChevronRight size={16} className="mo-entry-arrow" />
    </UnstyledButton>
  );
}

function Section({ title, children, right }: { title: string; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="mo-section">
      <Group justify="space-between" mb={6} wrap="nowrap">
        <Text className="mo-section-title">{title}</Text>
        {right}
      </Group>
      {children}
    </div>
  );
}

export default function TreatmentPanel({
  datasetId,
  columns,
  steps,
  canWrite,
  tab,
  setTab,
  selected,
  setSelected,
  onAdd,
  onChanged,
  onValues,
  viewUpto,
  setViewUpto,
  onTemplate,
}: {
  datasetId: string;
  columns: Column[];
  steps: Step[];
  canWrite: boolean;
  tab: TreatTab;
  setTab: (t: TreatTab) => void;
  selected: string[];
  setSelected: (s: string[]) => void;
  onAdd: (d: StepDraft) => void;
  onChanged: () => void;
  onValues: (col: string) => void;
  viewUpto: number | null;
  setViewUpto: (n: number | null) => void;
  onTemplate: (id: string) => void;
}) {
  const { meta } = useAuth();
  const cols = useMemo(() => columns.filter((c) => !c.name.startsWith('__')), [columns]);
  const [q, setQ] = useState('');
  const [rename, setRename] = useState('');
  const [castTo, setCastTo] = useState<string | null>(null);
  const [op, setOp] = useState<string | null>(null);
  const [digits, setDigits] = useState<number>(0);
  const [k, setK] = useState<number>(4);
  const [keepOrig, setKeepOrig] = useState(false);
  const [filter, setFilter] = useState<any>({ conditions: [{ column: '', op: 'eq', value: '' }], logic: 'and' });
  const [keep, setKeep] = useState<'true' | 'false'>('true');
  const [busy, setBusy] = useState(false);
  const real = steps.filter((s) => s.id);
  const nRows = steps.length ? steps[steps.length - 1].n_rows : undefined;
  const one = selected.length === 1 ? cols.find((c) => c.name === selected[0]) : undefined;

  useEffect(() => {
    setRename(one?.name || '');
    setCastTo(null);
  }, [one?.name]);
  useEffect(() => {
    // une colonne disparue (supprimée, renommée) sort de la sélection
    const names = new Set(cols.map((c) => c.name));
    if (selected.some((s) => !names.has(s))) setSelected(selected.filter((s) => names.has(s)));
  }, [cols, selected, setSelected]);

  /** Applique directement une étape simple, avec possibilité d'annuler depuis la notification. */
  const apply = async (type: string, params: any) => {
    setBusy(true);
    try {
      const r = await api.post<{ id: string; description: string; downstream_error?: any }>(`/api/datasets/${datasetId}/steps`, { type, params });
      const nid = `step-${r.id}`;
      notifications.show({
        id: nid,
        color: 'teal',
        title: 'Opération ajoutée',
        autoClose: 7000,
        message: (
          <Stack gap={4}>
            <Text size="sm">{r.description}</Text>
            <Anchor
              size="sm"
              onClick={() => {
                notifications.hide(nid);
                api.del(`/api/datasets/${datasetId}/steps/${r.id}`).then(onChanged).catch(fail);
              }}
            >
              Annuler
            </Anchor>
          </Stack>
        ),
      });
      if (r.downstream_error) fail({ message: `Une étape suivante ne s’applique plus : ${r.downstream_error.message}` }, 'Attention');
      onChanged();
      return true;
    } catch (e) {
      fail(e, 'Opération impossible');
      return false;
    } finally {
      setBusy(false);
    }
  };

  const undoLast = () => {
    const last = real[real.length - 1];
    if (!last) return;
    api.del(`/api/datasets/${datasetId}/steps/${last.id}`).then(onChanged).catch(fail);
  };

  const shown = cols.filter((c) => c.name.toLowerCase().includes(q.toLowerCase()));
  const toggle = (n: string) => setSelected(selected.includes(n) ? selected.filter((x) => x !== n) : [...selected, n]);
  const ops = meta?.transforms || {};
  const selTypes = selected.map((s) => cols.find((c) => c.name === s)?.type || '');
  const allNum = selTypes.length > 0 && selTypes.every(isNumericType);
  const opOk = op && (ops[op]?.kind === 'texte' || allNum);

  return (
    <Stack gap={0} h="100%" className="mo-treat">
      <Tabs value={tab} onChange={(v) => setTab((v as TreatTab) || 'colonnes')} variant="default" className="mo-treat-tabs">
        <Tabs.List grow>
            <Tabs.Tab value="colonnes" leftSection={<IconColumns3 size={15} />}>
              Colonnes
            </Tabs.Tab>
            <Tabs.Tab value="lignes" leftSection={<IconLayoutRows size={15} />}>
              Lignes
            </Tabs.Tab>
            <Tabs.Tab value="creer" leftSection={<IconPlus size={15} />}>
              Créer
            </Tabs.Tab>
        </Tabs.List>
        <Tabs.List grow mt={-1}>
          <Tabs.Tab value="regrouper" leftSection={<IconStack2 size={15} />}>
            Regrouper
          </Tabs.Tab>
          <Tabs.Tab value="metier" leftSection={<IconAnchor size={15} />}>
            Pêche
          </Tabs.Tab>
          <Tabs.Tab value="historique" leftSection={<IconHistory size={15} />} rightSection={real.length ? <Badge size="xs" variant="light" circle>{real.length}</Badge> : null}>
            Historique
          </Tabs.Tab>
        </Tabs.List>
      </Tabs>

      <ScrollArea style={{ flex: 1 }} offsetScrollbars type="auto">
        <div className="mo-treat-body">
          {!canWrite && tab !== 'historique' && (
            <Text size="sm" c="dimmed" mb="sm">
              Jeu en lecture seule : faites une copie de travail (menu « … ») pour le traiter.
            </Text>
          )}

          {tab === 'colonnes' && (
            <Stack gap="md">
              <Section
                title={`Colonnes (${cols.length})`}
                right={
                  <Group gap={8}>
                    <Anchor size="xs" onClick={() => setSelected(shown.map((c) => c.name))}>
                      Tout
                    </Anchor>
                    <Anchor size="xs" onClick={() => setSelected([])}>
                      Aucune
                    </Anchor>
                  </Group>
                }
              >
                <TextInput size="xs" mb={6} leftSection={<IconSearch size={13} />} placeholder="Filtrer les colonnes" value={q} onChange={(e) => setQ(e.currentTarget.value)} />
                <div className="mo-collist">
                  {shown.map((c) => {
                    const tg = typeTag(c.type);
                    return (
                      <div key={c.name} className="mo-colrow" data-sel={selected.includes(c.name) || undefined} onClick={() => toggle(c.name)}>
                        <Checkbox size="xs" checked={selected.includes(c.name)} onChange={() => toggle(c.name)} onClick={(e) => e.stopPropagation()} aria-label={c.name} />
                        <span className="mo-colname">{c.name}</span>
                        <span className={`mo-type mo-type-${tg.cls}`}>{tg.label}</span>
                        <Tooltip label="Valeurs et recodage" openDelay={300}>
                          <ActionIcon
                            size="sm"
                            variant="subtle"
                            color="gray"
                            aria-label={`Valeurs de ${c.name}`}
                            onClick={(e) => {
                              e.stopPropagation();
                              onValues(c.name);
                            }}
                          >
                            <IconListDetails size={14} />
                          </ActionIcon>
                        </Tooltip>
                      </div>
                    );
                  })}
                </div>
              </Section>

              {canWrite && (
                <Section title={selected.length ? `Sélection : ${selected.length === 1 ? selected[0] : `${selected.length} colonnes`}` : 'Sélection'}>
                  {selected.length === 0 ? (
                    <Text size="xs" c="dimmed">
                      Cochez une ou plusieurs colonnes, ou cliquez sur un en-tête du tableau.
                    </Text>
                  ) : (
                    <Stack gap="sm">
                      {one && (
                        <>
                          <Group gap={6} align="flex-end" wrap="nowrap">
                            <TextInput size="xs" label="Renommer" style={{ flex: 1 }} value={rename} onChange={(e) => setRename(e.currentTarget.value)} />
                            <Button size="xs" variant="default" disabled={!rename.trim() || rename === one.name} loading={busy} onClick={() => apply('rename', { mapping: { [one.name]: rename.trim() } }).then((x) => x && setSelected([rename.trim()]))}>
                              OK
                            </Button>
                          </Group>
                          <Group gap={6} align="flex-end" wrap="nowrap">
                            <Select
                              size="xs"
                              label="Type"
                              style={{ flex: 1 }}
                              placeholder={typeTag(one.type).label === '123' ? 'nombre' : typeTag(one.type).label === 'abc' ? 'texte' : typeTag(one.type).label}
                              data={Object.entries(meta?.cast_types || {}).map(([v, l]) => ({ value: v, label: l }))}
                              value={castTo}
                              onChange={setCastTo}
                            />
                            <Button size="xs" variant="default" disabled={!castTo} loading={busy} onClick={() => apply('cast', { column: one.name, to: castTo })}>
                              Convertir
                            </Button>
                          </Group>
                        </>
                      )}
                      <div>
                        <Group gap={6} align="flex-end" wrap="nowrap">
                          <Select
                            size="xs"
                            label="Transformer"
                            style={{ flex: 1 }}
                            placeholder="Choisir…"
                            data={[
                              { group: 'Texte', items: Object.entries(ops).filter(([, o]) => o.kind === 'texte').map(([kk, o]) => ({ value: kk, label: o.label })) },
                              {
                                group: allNum ? 'Nombres' : 'Nombres (colonnes numériques seulement)',
                                items: Object.entries(ops)
                                  .filter(([, o]) => o.kind === 'nombre')
                                  .map(([kk, o]) => ({ value: kk, label: o.label, disabled: !allNum })),
                              },
                            ]}
                            value={op}
                            onChange={setOp}
                          />
                          {op === 'arrondir' && <NumberInput size="xs" w={70} label="Déc." min={-6} max={10} value={digits} onChange={(v) => setDigits(Number(v))} />}
                          {(op === 'classes_egales' || op === 'classes_quantiles') && <NumberInput size="xs" w={70} label="Classes" min={2} max={50} value={k} onChange={(v) => setK(Number(v))} />}
                          <Button
                            size="xs"
                            variant="default"
                            disabled={!opOk}
                            loading={busy}
                            onClick={() => apply('transform', { columns: selected, op, digits, k, suffix: keepOrig ? `_${op}` : '' })}
                          >
                            Appliquer
                          </Button>
                        </Group>
                        {op && <Checkbox size="xs" mt={6} label="Garder l’original (nouvelle colonne)" checked={keepOrig} onChange={(e) => setKeepOrig(e.currentTarget.checked)} />}
                      </div>
                      <Group gap={6}>
                        {one && (
                          <Button size="xs" variant="default" onClick={() => onValues(one.name)}>
                            Recoder des valeurs…
                          </Button>
                        )}
                        {one && (
                          <Button size="xs" variant="default" onClick={() => onAdd({ type: 'fill_null', params: { column: one.name, method: 'valeur' } })}>
                            Remplir les vides…
                          </Button>
                        )}
                        {selected.length >= 2 && (
                          <Button size="xs" variant="default" onClick={() => onAdd({ type: 'coalesce', params: { columns: selected, name: selected[0] } })}>
                            Fusionner…
                          </Button>
                        )}
                        <Button size="xs" variant="default" onClick={() => onAdd({ type: 'clean_text', params: { columns: selected, trim: true, empty_to_null: true, case: 'none' } })}>
                          Nettoyer…
                        </Button>
                      </Group>
                      <Group gap={6}>
                        <Button size="xs" variant="default" loading={busy} onClick={() => apply('select_columns', { columns: selected })}>
                          Garder seulement ces colonnes
                        </Button>
                        <Button size="xs" variant="default" color="red" c="red" loading={busy} onClick={() => apply('drop_columns', { columns: selected }).then((x) => x && setSelected([]))}>
                          Supprimer
                        </Button>
                      </Group>
                    </Stack>
                  )}
                </Section>
              )}
            </Stack>
          )}

          {tab === 'lignes' && canWrite && (
            <Stack gap="md">
              <Section title="Filtrer les lignes">
                <Stack gap={8}>
                  <SegmentedControl
                    size="xs"
                    fullWidth
                    value={keep}
                    onChange={(v) => setKeep(v as 'true' | 'false')}
                    data={[
                      { value: 'true', label: 'Garder les lignes où…' },
                      { value: 'false', label: 'Supprimer les lignes où…' },
                    ]}
                  />
                  <Conditions value={filter} onChange={setFilter} columns={columns} datasetId={datasetId} />
                  <Group justify="space-between">
                    <Text size="xs" c="dimmed">
                      {nRows !== undefined ? `${fmtNumber(nRows)} lignes actuellement` : ''}
                    </Text>
                    <Group gap={6}>
                      <Button size="xs" variant="subtle" onClick={() => onAdd({ type: 'filter', params: { ...filter, keep: keep === 'true' } })}>
                        Avec aperçu…
                      </Button>
                      <Button
                        size="xs"
                        loading={busy}
                        disabled={!(filter.conditions || []).some((c: any) => c.column)}
                        onClick={() =>
                          apply('filter', { ...filter, conditions: filter.conditions.filter((c: any) => c.column), keep: keep === 'true' }).then(
                            (x) => x && setFilter({ conditions: [{ column: '', op: 'eq', value: '' }], logic: 'and' }),
                          )
                        }
                      >
                        Appliquer
                      </Button>
                    </Group>
                  </Group>
                </Stack>
              </Section>
              <Section title="Autres opérations sur les lignes">
                <Stack gap={4}>
                  <Entry title="Supprimer les doublons" text="Lignes identiques, ou identiques sur certaines colonnes (ex. même marée et même espèce)." onClick={() => onAdd({ type: 'dedupe' })} />
                  <Entry
                    title="Supprimer les lignes vides"
                    text="Retire les lignes où une colonne choisie n’est pas renseignée."
                    onClick={() => onAdd({ type: 'filter', params: { keep: false, logic: 'or', conditions: [{ column: selected[0] || '', op: 'is_null' }] } })}
                  />
                  <Entry title="Trier" text="Ordre d’affichage et d’export, sur une ou plusieurs colonnes." onClick={() => onAdd({ type: 'sort' })} />
                  <Entry title="Corriger des cellules" text="Double-cliquez sur une cellule du tableau, puis enregistrez avec une justification." onClick={() => undefined} disabled />
                </Stack>
              </Section>
            </Stack>
          )}

          {tab === 'creer' && canWrite && (
            <Stack gap={4}>
              <Entry title="Formule" text="Calcul façon tableur : [kg] / 1000, SI([prix] > 5; « haut »; « bas »), ANNEE([date])…" onClick={() => onAdd({ type: 'formula' })} />
              <Entry title="Selon des conditions (si… alors…)" text="Coder une colonne par règles successives, ex. métier selon engin et maillage." onClick={() => onAdd({ type: 'case_when' })} />
              <Entry title="Fusionner des colonnes" text="Première valeur non vide parmi plusieurs colonnes, par ordre de priorité." onClick={() => onAdd({ type: 'coalesce', params: { columns: selected.length >= 2 ? selected : [], name: selected[0] || '' } })} />
              <Entry title="Extraire année, mois, trimestre…" text="À partir d’une colonne date." onClick={() => onAdd({ type: 'date_parts', params: { column: selected.find((s) => isTemporalType(cols.find((c) => c.name === s)?.type || '')) } })} />
              <Entry title="Convertir des unités" text="kg ↔ tonnes, euros ↔ k€, nœuds ↔ km/h…" onClick={() => onAdd({ type: 'unit_convert', params: { from: 'kg', to: 't', column: one?.name } })} />
              <Entry title="Ajouter depuis un référentiel" text="Métier (DCF) depuis l’engin, libellé FAO, famille d’engin…" onClick={() => onAdd({ type: 'lookup' })} />
              <Entry title="Rectangle CIEM" text="À partir de la longitude et de la latitude." onClick={() => onAdd({ type: 'ciem_rect' })} />
            </Stack>
          )}

          {tab === 'regrouper' && canWrite && (
            <Stack gap={4}>
              <Entry title="Regrouper et résumer" text="Une ligne par groupe (ex. par navire et mois) avec sommes, moyennes, effectifs ; secret statistique possible." onClick={() => onAdd({ type: 'aggregate' })} />
              <Entry title="Associer un autre jeu (jointure)" text="Ajouter des colonnes d’un autre jeu selon une clé commune (ex. flottille par navire)." onClick={() => onAdd({ type: 'join' })} />
              <Entry title="Empiler d’autres jeux" text="Ajouter les lignes d’autres jeux (ex. plusieurs années), colonnes associées par leur nom." onClick={() => onAdd({ type: 'union' })} />
            </Stack>
          )}

          {tab === 'metier' && canWrite && (
            <Stack gap="md">
              <Section title="Préparations complètes">
                <Stack gap={4}>
                  {Object.entries(meta?.templates || {}).map(([kk, t]) => (
                    <Entry key={kk} title={t.nom} text={t.description} onClick={() => onTemplate(kk)} />
                  ))}
                </Stack>
              </Section>
              <Section title="SACROIS / journaux de bord">
                <Stack gap={4}>
                  <Entry title="Cohérence engin / espèce" text="Repère les engins improbables pour l’espèce et propose un engin corrigé (engin_sug)." onClick={() => onAdd({ type: 'gear_check' })} />
                  <Entry title="Anonymiser" text="Codes, hachage ou suppression des colonnes nominatives avant diffusion." onClick={() => onAdd({ type: 'anonymize' })} />
                </Stack>
              </Section>
              <Section title="VMS et géographie">
                <Stack gap={4}>
                  <Entry title="Identifier l’activité de pêche" text="Vitesse entre positions, seuils selon l’engin : pêche, route, arrêt." onClick={() => onAdd({ type: 'vms_activity' })} />
                  <Entry title="Repérer les positions dans une zone" text="Natura 2000, 12 milles, vos propres zones…" onClick={() => onAdd({ type: 'zone_tag' })} />
                  <Entry title="Répartir les captures sur les positions" text="Croisement VMS × SACROIS par navire, jour et rectangle." onClick={() => onAdd({ type: 'vms_catch_split' })} />
                </Stack>
              </Section>
            </Stack>
          )}

          {tab === 'historique' && (
            <Stack gap="sm">
              {canWrite && real.length > 0 && (
                <Button size="xs" variant="default" leftSection={<IconArrowBackUp size={14} />} onClick={undoLast}>
                  Annuler la dernière opération
                </Button>
              )}
              <RecipePanel datasetId={datasetId} steps={steps} canWrite={canWrite} onAdd={onAdd} onChanged={onChanged} viewUpto={viewUpto} setViewUpto={setViewUpto} />
            </Stack>
          )}
        </div>
      </ScrollArea>
    </Stack>
  );
}
