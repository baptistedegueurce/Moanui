// Formulaires des étapes de recette : un formulaire par type, en clic-bouton.
import { useEffect, useState } from 'react';
import {
  ActionIcon,
  Button,
  Group,
  MultiSelect,
  NumberInput,
  SegmentedControl,
  Select,
  Stack,
  Switch,
  Text,
  TextInput,
  Textarea,
  Checkbox,
  Paper,
  Code,
  ScrollArea,
  Tooltip,
  Popover,
  FileButton,
} from '@mantine/core';
import { IconPlus, IconTrash, IconHelp } from '@tabler/icons-react';
import { api, saveText } from '../lib/api';
import { useAuth } from '../lib/auth';
import { isNumericType, isTemporalType } from '../lib/format';
import type { Column, DatasetSummary } from '../lib/types';

export interface FormProps {
  params: any;
  set: (p: any) => void;
  columns: Column[];
  datasetId: string;
}

const visible = (cols: Column[]) => cols.filter((c) => !c.name.startsWith('__'));
const colData = (cols: Column[]) => visible(cols).map((c) => c.name);

function Rows<T>({ items, onChange, render, empty, addLabel }: {
  items: T[];
  onChange: (x: T[]) => void;
  render: (item: T, update: (v: Partial<T>) => void) => React.ReactNode;
  empty: T;
  addLabel: string;
}) {
  return (
    <Stack gap={6}>
      {items.map((it, i) => (
        <Group key={i} gap={6} wrap="nowrap" align="flex-end">
          <div style={{ flex: 1 }}>{render(it, (v) => onChange(items.map((x, j) => (j === i ? { ...x, ...v } : x))))}</div>
          <ActionIcon variant="subtle" color="red" onClick={() => onChange(items.filter((_, j) => j !== i))} mb={4} aria-label="Retirer">
            <IconTrash size={16} />
          </ActionIcon>
        </Group>
      ))}
      <Button size="xs" variant="light" leftSection={<IconPlus size={14} />} onClick={() => onChange([...items, empty])} w="fit-content">
        {addLabel}
      </Button>
    </Stack>
  );
}

// --------------------------------------------------------------------------- conditions

function ValuesPicker({ datasetId, column, value, onChange }: { datasetId: string; column: string; value: any[]; onChange: (v: any[]) => void }) {
  const [vals, setVals] = useState<{ valeur: any; n: number }[]>([]);
  const [search, setSearch] = useState('');
  useEffect(() => {
    if (!column) return;
    const t = setTimeout(() => {
      api
        .get(`/api/datasets/${datasetId}/values/${encodeURIComponent(column)}?limit=300${search ? `&search=${encodeURIComponent(search)}` : ''}`)
        .then((r) => setVals(r.values))
        .catch(() => setVals([]));
    }, 200);
    return () => clearTimeout(t);
  }, [datasetId, column, search]);
  const key = (v: any) => (v === null ? '∅' : String(v));
  const selected = new Set((value || []).map(key));
  return (
    <Paper withBorder p={6}>
      <TextInput size="xs" placeholder="Chercher une valeur…" value={search} onChange={(e) => setSearch(e.currentTarget.value)} mb={4} />
      <ScrollArea h={160}>
        {vals.map((v) => (
          <Checkbox
            key={key(v.valeur)}
            size="xs"
            mb={3}
            label={`${v.valeur === null ? '(vide)' : v.valeur}  ·  ${v.n}`}
            checked={selected.has(key(v.valeur))}
            onChange={(e) => {
              const on = e.currentTarget.checked;
              const next = (value || []).filter((x) => key(x) !== key(v.valeur));
              onChange(on ? [...next, v.valeur] : next);
            }}
          />
        ))}
      </ScrollArea>
      <Text size="xs" c="dimmed">
        {selected.size} valeur(s) choisie(s)
      </Text>
    </Paper>
  );
}

export function Conditions({ value, onChange, columns, datasetId }: { value: any; onChange: (v: any) => void; columns: Column[]; datasetId: string }) {
  const { meta } = useAuth();
  const ops = Object.entries(meta?.operators || {}).map(([k, v]) => ({ value: k, label: v }));
  const conds: any[] = value.conditions || [];
  const typeOf = (c: string) => columns.find((x) => x.name === c)?.type || 'VARCHAR';
  return (
    <Stack gap={6}>
      {conds.length > 1 && (
        <SegmentedControl
          size="xs"
          value={value.logic || 'and'}
          onChange={(v) => onChange({ ...value, logic: v })}
          data={[
            { value: 'and', label: 'Toutes les conditions (ET)' },
            { value: 'or', label: 'Au moins une (OU)' },
          ]}
        />
      )}
      <Rows
        items={conds}
        onChange={(c) => onChange({ ...value, conditions: c })}
        empty={{ column: '', op: 'eq', value: '' }}
        addLabel="Ajouter une condition"
        render={(c, up) => (
          <Stack gap={4}>
            <Group gap={6} grow>
              <Select size="xs" placeholder="Colonne" searchable data={colData(columns)} value={c.column || null} onChange={(v) => up({ column: v || '' })} />
              <Select size="xs" data={ops} value={c.op} onChange={(v) => up({ op: v || 'eq' })} />
              {!['is_null', 'not_null', 'in', 'not_in'].includes(c.op) &&
                (isTemporalType(typeOf(c.column)) ? (
                  <TextInput size="xs" type="date" value={c.value ?? ''} onChange={(e) => up({ value: e.currentTarget.value })} />
                ) : (
                  <TextInput size="xs" placeholder="Valeur" value={c.value ?? ''} onChange={(e) => up({ value: e.currentTarget.value })} />
                ))}
              {c.op === 'between' &&
                (isTemporalType(typeOf(c.column)) ? (
                  <TextInput size="xs" type="date" value={c.value2 ?? ''} onChange={(e) => up({ value2: e.currentTarget.value })} />
                ) : (
                  <TextInput size="xs" placeholder="et" value={c.value2 ?? ''} onChange={(e) => up({ value2: e.currentTarget.value })} />
                ))}
            </Group>
            {['in', 'not_in'].includes(c.op) && c.column && (
              <ValuesPicker datasetId={datasetId} column={c.column} value={c.values || []} onChange={(v) => up({ values: v })} />
            )}
          </Stack>
        )}
      />
    </Stack>
  );
}

// --------------------------------------------------------------------------- formulaires

function FilterForm({ params, set, columns, datasetId }: FormProps) {
  return (
    <Stack>
      <SegmentedControl
        value={params.keep === false ? 'exclude' : 'keep'}
        onChange={(v) => set({ ...params, keep: v === 'keep' })}
        data={[
          { value: 'keep', label: 'Garder les lignes qui…' },
          { value: 'exclude', label: 'Exclure les lignes qui…' },
        ]}
      />
      <Conditions value={params} onChange={set} columns={columns} datasetId={datasetId} />
    </Stack>
  );
}

function ColumnsForm({ params, set, columns, label }: FormProps & { label: string }) {
  return <MultiSelect label={label} searchable data={colData(columns)} value={params.columns || []} onChange={(v) => set({ ...params, columns: v })} />;
}

function RenameForm({ params, set, columns }: FormProps) {
  const entries = Object.entries(params.mapping || {}) as [string, string][];
  return (
    <Rows
      items={entries.map(([a, b]) => ({ from: a, to: b }))}
      onChange={(rows) => set({ ...params, mapping: Object.fromEntries(rows.filter((r) => r.from).map((r) => [r.from, r.to])) })}
      empty={{ from: '', to: '' }}
      addLabel="Ajouter un renommage"
      render={(r, up) => (
        <Group grow gap={6}>
          <Select size="xs" placeholder="Colonne" searchable data={colData(columns)} value={r.from || null} onChange={(v) => up({ from: v || '' })} />
          <TextInput size="xs" placeholder="Nouveau nom" value={r.to} onChange={(e) => up({ to: e.currentTarget.value })} />
        </Group>
      )}
    />
  );
}

function CastForm({ params, set, columns }: FormProps) {
  const { meta } = useAuth();
  return (
    <Stack>
      <Select label="Colonne" searchable data={colData(columns)} value={params.column || null} onChange={(v) => set({ ...params, column: v })} />
      <Select
        label="Nouveau type"
        data={Object.entries(meta?.cast_types || {}).map(([k, v]) => ({ value: k, label: v }))}
        value={params.to || null}
        onChange={(v) => set({ ...params, to: v })}
      />
      {(params.to === 'date' || params.to === 'dateheure') && (
        <TextInput
          label="Format de lecture (facultatif)"
          description="Ex. %d/%m/%Y pour 31/12/2024, %Y%m%d pour 20241231"
          value={params.format || ''}
          onChange={(e) => set({ ...params, format: e.currentTarget.value || undefined })}
        />
      )}
      <Text size="xs" c="dimmed">
        Les valeurs non convertibles deviennent vides : vérifiez le nombre de vides avant/après dans l’aperçu.
      </Text>
    </Stack>
  );
}

function ReplaceForm({ params, set, columns, datasetId }: FormProps) {
  const [vals, setVals] = useState<{ valeur: any; n: number }[]>([]);
  useEffect(() => {
    if (!params.column) return;
    api.get(`/api/datasets/${datasetId}/values/${encodeURIComponent(params.column)}?limit=200`).then((r) => setVals(r.values)).catch(() => {});
  }, [params.column, datasetId]);
  const pairs: any[] = params.pairs || [];
  return (
    <Stack>
      <Select label="Colonne" searchable data={colData(columns)} value={params.column || null} onChange={(v) => set({ ...params, column: v, pairs: [] })} />
      {params.column && (
        <Rows
          items={pairs}
          onChange={(p) => set({ ...params, pairs: p })}
          empty={{ from: '', to: '' }}
          addLabel="Ajouter un remplacement"
          render={(p, up) => (
            <Group grow gap={6}>
              <Select
                size="xs"
                placeholder="Valeur actuelle"
                searchable
                data={vals.map((v) => ({ value: v.valeur === null ? '__null__' : String(v.valeur), label: `${v.valeur ?? '(vide)'} (${v.n})` }))}
                value={p.from === null ? '__null__' : p.from === '' ? null : String(p.from)}
                onChange={(v) => up({ from: v === '__null__' ? null : v })}
              />
              <TextInput
                size="xs"
                placeholder="Nouvelle valeur (vide = effacer)"
                value={p.to ?? ''}
                onChange={(e) => up({ to: e.currentTarget.value === '' ? null : e.currentTarget.value })}
              />
            </Group>
          )}
        />
      )}
    </Stack>
  );
}

function FormulaForm({ params, set }: FormProps) {
  const { meta } = useAuth();
  return (
    <Stack>
      <TextInput label="Nom de la colonne" description="Si la colonne existe, elle est recalculée" value={params.name || ''} onChange={(e) => set({ ...params, name: e.currentTarget.value })} />
      <Textarea
        label={
          <Group gap={4}>
            Formule
            <Popover width={420} position="bottom-start" withArrow>
              <Popover.Target>
                <ActionIcon size="xs" variant="subtle">
                  <IconHelp size={14} />
                </ActionIcon>
              </Popover.Target>
              <Popover.Dropdown>
                <Text size="xs" mb={4}>
                  Colonnes entre crochets : <Code>[debarquement_Kg] / 1000</Code>. Séparateur d’arguments : <Code>;</Code>. Opérateurs : + − * / ^ & (texte) = &lt;&gt; &lt; &gt; ET OU NON.
                </Text>
                <ScrollArea h={220}>
                  {meta?.functions.map((f) => (
                    <Text size="xs" key={f.name}>
                      <Code>{f.doc}</Code>
                    </Text>
                  ))}
                </ScrollArea>
              </Popover.Dropdown>
            </Popover>
          </Group>
        }
        placeholder="SI([debarquement_Kg] > 0; [debarquement_euros] / [debarquement_Kg]; VIDE)"
        autosize
        minRows={2}
        styles={{ input: { fontFamily: 'monospace' } }}
        value={params.expression || ''}
        onChange={(e) => set({ ...params, expression: e.currentTarget.value })}
      />
    </Stack>
  );
}

function CaseWhenForm({ params, set, columns, datasetId }: FormProps) {
  const rules: any[] = params.rules || [];
  return (
    <Stack>
      <TextInput label="Nom de la nouvelle colonne" value={params.name || ''} onChange={(e) => set({ ...params, name: e.currentTarget.value })} />
      {rules.map((r, i) => (
        <Paper withBorder p="xs" key={i}>
          <Group justify="space-between" mb={4}>
            <Text size="sm" fw={600}>
              Règle {i + 1} {i > 0 && <Text span size="xs" c="dimmed">(si les précédentes ne s’appliquent pas)</Text>}
            </Text>
            <ActionIcon variant="subtle" color="red" onClick={() => set({ ...params, rules: rules.filter((_, j) => j !== i) })}>
              <IconTrash size={14} />
            </ActionIcon>
          </Group>
          <Conditions value={r} onChange={(v) => set({ ...params, rules: rules.map((x, j) => (j === i ? v : x)) })} columns={columns} datasetId={datasetId} />
          <TextInput
            mt={6}
            size="xs"
            label="Alors la valeur est"
            value={r.value ?? ''}
            onChange={(e) => set({ ...params, rules: rules.map((x, j) => (j === i ? { ...x, value: e.currentTarget.value } : x)) })}
          />
        </Paper>
      ))}
      <Button size="xs" variant="light" leftSection={<IconPlus size={14} />} onClick={() => set({ ...params, rules: [...rules, { conditions: [{ column: '', op: 'eq', value: '' }], value: '' }] })} w="fit-content">
        Ajouter une règle
      </Button>
      <TextInput label="Sinon (valeur par défaut, vide possible)" value={params.default ?? ''} onChange={(e) => set({ ...params, default: e.currentTarget.value === '' ? null : e.currentTarget.value })} />
    </Stack>
  );
}

const AGGS = [
  { value: 'somme', label: 'Somme' },
  { value: 'moyenne', label: 'Moyenne' },
  { value: 'mediane', label: 'Médiane' },
  { value: 'min', label: 'Minimum' },
  { value: 'max', label: 'Maximum' },
  { value: 'nombre', label: 'Nombre de valeurs' },
  { value: 'nombre_lignes', label: 'Nombre de lignes' },
  { value: 'nombre_distinct', label: 'Nombre distinct (ex. navires)' },
  { value: 'ecart_type', label: 'Écart-type' },
  { value: 'premier', label: 'Première valeur' },
];
export { AGGS };

function AggregateForm({ params, set, columns }: FormProps) {
  return (
    <Stack>
      <MultiSelect label="Regrouper par" description="Vide = un seul résumé pour tout le jeu" searchable data={colData(columns)} value={params.group_by || []} onChange={(v) => set({ ...params, group_by: v })} />
      <Text size="sm" fw={500}>
        Calculs
      </Text>
      <Rows
        items={params.aggregations || []}
        onChange={(a) => set({ ...params, aggregations: a })}
        empty={{ column: '', fn: 'somme', name: '' }}
        addLabel="Ajouter un calcul"
        render={(a, up) => (
          <Group grow gap={6}>
            <Select size="xs" data={AGGS} value={a.fn} onChange={(v) => up({ fn: v || 'somme' })} />
            {a.fn !== 'nombre_lignes' && <Select size="xs" placeholder="Colonne" searchable data={colData(columns)} value={a.column || null} onChange={(v) => up({ column: v || '' })} />}
            <TextInput size="xs" placeholder="Nom du résultat" value={a.name} onChange={(e) => up({ name: e.currentTarget.value })} />
          </Group>
        )}
      />
      <Paper withBorder p="xs">
        <Switch
          label="Secret statistique : masquer les résultats portant sur trop peu de navires"
          checked={!!params.secret?.vessel_column}
          onChange={(e) => {
            const guess = colData(columns).find((c) => /cfr|navs|navire_cod/i.test(c)) || colData(columns).find((c) => /navire/i.test(c)) || '';
            set({ ...params, secret: e.currentTarget.checked ? { vessel_column: guess, threshold: 3 } : undefined });
          }}
        />
        {params.secret && (
          <Group grow mt={6}>
            <Select size="xs" label="Identifiant navire" searchable data={colData(columns)} value={params.secret.vessel_column || null} onChange={(v) => set({ ...params, secret: { ...params.secret, vessel_column: v } })} />
            <NumberInput size="xs" label="Seuil (navires)" min={1} value={params.secret.threshold ?? 3} onChange={(v) => set({ ...params, secret: { ...params.secret, threshold: Number(v) || 3 } })} />
          </Group>
        )}
      </Paper>
      <Text size="xs" c="dimmed">
        Après un regroupement, la correction cellule par cellule n’est plus possible (les lignes d’origine n’existent plus).
      </Text>
    </Stack>
  );
}

function SortForm({ params, set, columns }: FormProps) {
  return (
    <Rows
      items={params.by || []}
      onChange={(b) => set({ ...params, by: b })}
      empty={{ column: '', desc: false }}
      addLabel="Ajouter un critère"
      render={(b, up) => (
        <Group grow gap={6}>
          <Select size="xs" searchable data={colData(columns)} value={b.column || null} onChange={(v) => up({ column: v || '' })} />
          <SegmentedControl
            size="xs"
            value={b.desc ? 'desc' : 'asc'}
            onChange={(v) => up({ desc: v === 'desc' })}
            data={[
              { value: 'asc', label: 'Croissant' },
              { value: 'desc', label: 'Décroissant' },
            ]}
          />
        </Group>
      )}
    />
  );
}

function FillForm({ params, set, columns }: FormProps) {
  const t = columns.find((c) => c.name === params.column)?.type || '';
  return (
    <Stack>
      <Select label="Colonne" searchable data={colData(columns)} value={params.column || null} onChange={(v) => set({ ...params, column: v })} />
      <Select
        label="Remplir avec"
        data={[
          { value: 'valeur', label: 'Une valeur fixe' },
          ...(isNumericType(t)
            ? [
                { value: 'moyenne', label: 'La moyenne de la colonne' },
                { value: 'mediane', label: 'La médiane de la colonne' },
              ]
            : []),
        ]}
        value={params.method || 'valeur'}
        onChange={(v) => set({ ...params, method: v })}
      />
      {(params.method || 'valeur') === 'valeur' && <TextInput label="Valeur" value={params.value ?? ''} onChange={(e) => set({ ...params, value: e.currentTarget.value })} />}
      {params.method && params.method !== 'valeur' && (
        <Text size="xs" c="orange">
          Attention : remplacer des vides par une moyenne réduit artificiellement la variabilité. À justifier dans le commentaire.
        </Text>
      )}
    </Stack>
  );
}

function CleanForm({ params, set, columns }: FormProps) {
  const textCols = visible(columns).filter((c) => c.type.startsWith('VARCHAR')).map((c) => c.name);
  return (
    <Stack>
      <MultiSelect label="Colonnes texte" searchable data={textCols} value={params.columns || []} onChange={(v) => set({ ...params, columns: v })} />
      <Switch label="Supprimer les espaces en trop" checked={params.trim !== false} onChange={(e) => set({ ...params, trim: e.currentTarget.checked })} />
      <Switch label="Supprimer les accents" checked={!!params.strip_accents} onChange={(e) => set({ ...params, strip_accents: e.currentTarget.checked })} />
      <Switch label="Textes vides → vides" checked={params.empty_to_null !== false} onChange={(e) => set({ ...params, empty_to_null: e.currentTarget.checked })} />
      <SegmentedControl
        value={params.case || 'none'}
        onChange={(v) => set({ ...params, case: v })}
        data={[
          { value: 'none', label: 'Casse inchangée' },
          { value: 'upper', label: 'MAJUSCULES' },
          { value: 'lower', label: 'minuscules' },
        ]}
      />
    </Stack>
  );
}

function DatePartsForm({ params, set, columns }: FormProps) {
  const dateCols = visible(columns).filter((c) => isTemporalType(c.type)).map((c) => c.name);
  return (
    <Stack>
      <Select label="Colonne date" data={dateCols} value={params.column || null} onChange={(v) => set({ ...params, column: v })} />
      <Checkbox.Group label="À extraire" value={params.parts || []} onChange={(v) => set({ ...params, parts: v })}>
        <Group mt={6}>
          {[
            ['annee', 'Année'],
            ['semestre', 'Semestre'],
            ['trimestre', 'Trimestre'],
            ['mois', 'Mois'],
            ['semaine', 'Semaine'],
            ['jour', 'Jour'],
            ['jour_semaine', 'Jour de la semaine'],
          ].map(([v, l]) => (
            <Checkbox key={v} value={v} label={l} />
          ))}
        </Group>
      </Checkbox.Group>
      {dateCols.length === 0 && (
        <Text size="xs" c="orange">
          Aucune colonne de type date : convertissez d’abord une colonne avec « Changer le type ».
        </Text>
      )}
    </Stack>
  );
}

function AnonForm({ params, set, columns }: FormProps) {
  return (
    <Stack>
      <MultiSelect label="Colonnes à anonymiser" searchable data={colData(columns)} value={params.columns || []} onChange={(v) => set({ ...params, columns: v })} />
      <SegmentedControl
        value={params.method || 'code'}
        onChange={(v) => set({ ...params, method: v })}
        data={[
          { value: 'code', label: 'Remplacer par un code (NAV_0001…)' },
          { value: 'masque', label: 'Masquer (***)' },
        ]}
      />
      {(params.method || 'code') === 'code' && (
        <TextInput label="Préfixe des codes" placeholder="NAV" value={params.prefix || ''} onChange={(e) => set({ ...params, prefix: e.currentTarget.value })} />
      )}
      <Text size="xs" c="dimmed">
        Avec un code, une même valeur d’origine reçoit toujours le même code : on peut encore compter et suivre les navires sans les identifier. Placez cette étape en fin de recette.
      </Text>
    </Stack>
  );
}

function useOtherDatasets(datasetId: string) {
  const [list, setList] = useState<DatasetSummary[]>([]);
  useEffect(() => {
    api.get<DatasetSummary[]>('/api/datasets').then((l) => setList(l.filter((d) => d.id !== datasetId))).catch(() => {});
  }, [datasetId]);
  return list;
}

function useSchema(id?: string) {
  const [cols, setCols] = useState<Column[]>([]);
  useEffect(() => {
    if (!id) return setCols([]);
    api.get(`/api/datasets/${id}`).then((d) => setCols(d.schema)).catch(() => setCols([]));
  }, [id]);
  return cols;
}

function JoinForm({ params, set, columns, datasetId }: FormProps) {
  const { meta } = useAuth();
  const others = useOtherDatasets(datasetId);
  const otherCols = useSchema(params.dataset_id);
  return (
    <Stack>
      <Select
        label="Jeu à associer"
        searchable
        data={others.map((d) => ({ value: d.id, label: `${d.name} (${d.source_name})` }))}
        value={params.dataset_id || null}
        onChange={(v) => set({ ...params, dataset_id: v, keys: [{ left: '', right: '' }], columns: [] })}
      />
      <Select
        label="Type d’association"
        data={Object.entries(meta?.join_kinds || {}).map(([k, v]) => ({ value: k, label: v }))}
        value={params.how || 'left'}
        onChange={(v) => set({ ...params, how: v })}
      />
      {params.dataset_id && (
        <>
          <Text size="sm" fw={500}>
            Colonnes de correspondance (clés)
          </Text>
          <Rows
            items={params.keys || []}
            onChange={(k) => set({ ...params, keys: k })}
            empty={{ left: '', right: '' }}
            addLabel="Ajouter une clé"
            render={(k, up) => (
              <Group grow gap={6}>
                <Select size="xs" placeholder="Jeu actuel" searchable data={colData(columns)} value={k.left || null} onChange={(v) => up({ left: v || '', right: k.right || v || '' })} />
                <Select size="xs" placeholder="Jeu associé" searchable data={colData(otherCols)} value={k.right || null} onChange={(v) => up({ right: v || '' })} />
              </Group>
            )}
          />
          {!['anti', 'semi'].includes(params.how) && (
            <MultiSelect
              label="Colonnes à ajouter"
              description="Vide = toutes"
              searchable
              data={colData(otherCols).filter((c) => !(params.keys || []).some((k: any) => k.right === c))}
              value={params.columns || []}
              onChange={(v) => set({ ...params, columns: v })}
            />
          )}
        </>
      )}
    </Stack>
  );
}

function UnionForm({ params, set, datasetId }: FormProps) {
  const others = useOtherDatasets(datasetId);
  return (
    <Stack>
      <MultiSelect
        label="Jeux à empiler sous le jeu actuel"
        searchable
        data={others.map((d) => ({ value: d.id, label: `${d.name} (${d.source_name})` }))}
        value={params.dataset_ids || []}
        onChange={(v) => set({ ...params, dataset_ids: v })}
      />
      <TextInput
        label="Colonne de provenance (facultatif)"
        description="Ajoute une colonne indiquant de quel jeu vient chaque ligne"
        placeholder="fichier"
        value={params.source_column || ''}
        onChange={(e) => set({ ...params, source_column: e.currentTarget.value })}
      />
      <TextInput
        label="Nom donné au jeu actuel dans cette colonne"
        placeholder="jeu actuel"
        value={params.self_label || ''}
        onChange={(e) => set({ ...params, self_label: e.currentTarget.value })}
      />
      <Text size="xs" c="dimmed">
        Les colonnes sont associées par leur nom. Renommez d’abord les colonnes qui n’ont pas le même nom d’un fichier à l’autre.
      </Text>
    </Stack>
  );
}


// --------------------------------------------------------------------------- halieutique

function LookupForm({ params, set, columns }: FormProps) {
  const { meta } = useAuth();
  const refs = Object.entries(meta?.referentiels || {}).filter(([, r]) => r.colonnes.length);
  const ref = meta?.referentiels[params.referentiel];
  return (
    <Stack>
      <Select
        label="Référentiel"
        description={ref?.description}
        data={refs.map(([k, r]) => ({ value: k, label: r.nom }))}
        value={params.referentiel || null}
        onChange={(v) => set({ ...params, referentiel: v, outputs: meta?.referentiels[v || '']?.colonnes })}
      />
      <Select label="Colonne de code" searchable data={colData(columns)} value={params.column || null} onChange={(v) => set({ ...params, column: v })} />
      {ref && <MultiSelect label="Colonnes à ajouter" data={ref.colonnes} value={params.outputs || ref.colonnes} onChange={(v) => set({ ...params, outputs: v })} />}
      <TextInput
        label="Valeur pour les codes absents du référentiel"
        description="Vide = laisser vide"
        value={params.default ?? 'Autres'}
        onChange={(e) => set({ ...params, default: e.currentTarget.value === '' ? null : e.currentTarget.value })}
      />
      <Text size="xs" c="dimmed">
        Pour un référentiel propre à votre structure, importez-le comme jeu de données puis utilisez « Associer un autre jeu ».
      </Text>
    </Stack>
  );
}

function UnitForm({ params, set, columns }: FormProps) {
  const { meta } = useAuth();
  const groups = Object.entries(meta?.units || {});
  const units = groups.flatMap(([g, us]) => Object.entries(us).map(([k, l]) => ({ value: k, label: l, group: g })));
  const groupOf = (u?: string) => units.find((x) => x.value === u)?.group;
  const sameGroup = units.filter((u) => !params.from || u.group === groupOf(params.from));
  const toData = (list: typeof units) =>
    groups
      .map(([g]) => ({ group: g, items: list.filter((u) => u.group === g).map((u) => ({ value: u.value, label: u.label })) }))
      .filter((g) => g.items.length);
  return (
    <Stack>
      <Select label="Colonne" searchable data={visible(columns).filter((c) => isNumericType(c.type)).map((c) => c.name)} value={params.column || null} onChange={(v) => set({ ...params, column: v })} />
      <Group grow>
        <Select label="Unité actuelle" data={toData(units)} value={params.from || null} onChange={(v) => set({ ...params, from: v, to: groupOf(v || '') === groupOf(params.to) ? params.to : null })} />
        <Select label="Convertir en" data={toData(sameGroup)} value={params.to || null} onChange={(v) => set({ ...params, to: v })} />
      </Group>
      <TextInput
        label="Nouvelle colonne (facultatif)"
        description="Vide = remplacer la colonne existante"
        value={params.name || ''}
        onChange={(e) => set({ ...params, name: e.currentTarget.value })}
      />
    </Stack>
  );
}

function GearCheckForm({ params, set, columns, datasetId }: FormProps) {
  const { meta } = useAuth();
  const [loading, setLoading] = useState(false);
  const [filtre, setFiltre] = useState('');
  const ref = meta?.referentiels.engins_coherents?.especes || {};
  const corrections: any[] = params.corrections || [];
  const coh: Record<string, string[]> = params.coherents || Object.fromEntries(Object.entries(ref).map(([k, v]) => [k, v.coherents]));

  const load = async () => {
    setLoading(true);
    try {
      const inc: any[] = await api.post(`/api/datasets/${datasetId}/gear-inconsistencies`, { type: 'gear_check', params });
      const key = (c: any) => `${c.vessel ?? ''}|${c.species}|${c.gear}`;
      const known = new Set(corrections.map(key));
      set({ ...params, corrections: [...corrections, ...inc.filter((c) => !known.has(key(c))).map((c) => ({ vessel: c.vessel, species: c.species, gear: c.gear, corrected: '', n: c.n }))] });
    } catch (e: any) {
      alert(e.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Stack>
      <Group grow>
        <Select label="Colonne espèce" searchable data={colData(columns)} value={params.species_column || null} onChange={(v) => set({ ...params, species_column: v })} />
        <Select label="Colonne engin" searchable data={colData(columns)} value={params.gear_column || null} onChange={(v) => set({ ...params, gear_column: v })} />
        <Select label="Colonne navire (facultatif)" searchable clearable data={colData(columns)} value={params.vessel_column || null} onChange={(v) => set({ ...params, vessel_column: v })} />
      </Group>
      <TextInput label="Nom de la colonne résultat" value={params.name || 'engin_sug'} onChange={(e) => set({ ...params, name: e.currentTarget.value })} />
      <Paper withBorder p="xs">
        <Group justify="space-between" mb={4}>
          <Text size="sm" fw={600}>
            Engins cohérents par espèce ({Object.keys(coh).length} codes)
          </Text>
          <Group gap={6}>
            <TextInput size="xs" placeholder="Filtrer (code ou nom)" value={filtre} onChange={(e) => setFiltre(e.currentTarget.value)} />
            {params.coherents && (
              <Button size="xs" variant="subtle" onClick={() => { const { coherents: _c, ...rest } = params; set(rest); }}>
                Revenir au référentiel
              </Button>
            )}
          </Group>
        </Group>
        <Text size="xs" c="dimmed" mb={4}>
          Liste issue de la littérature (FAO ISSCFG 2016, CIEM, Ifremer), à adapter. En gras au survol : engins ciblant l'espèce. Les codes génériques (TX, GEN, LX…) sont acceptés si un engin précis du groupe est cohérent ; MIS et NK ne sont jamais signalés.
        </Text>
        <ScrollArea.Autosize mah={260} type="auto">
        <Stack gap={4}>
          {Object.entries(coh)
            .filter(([sp]) => !filtre || sp.toLowerCase().includes(filtre.toLowerCase()) || (ref[sp]?.nom || '').toLowerCase().includes(filtre.toLowerCase()))
            .map(([sp, gears]) => (
            <Group key={sp} gap={6} wrap="nowrap">
              <Tooltip
                multiline
                w={320}
                label={ref[sp] ? `${ref[sp].nom} (${ref[sp].nom_latin}) — engins ciblants : ${(ref[sp].principaux || []).join(', ')}${ref[sp].note ? '. ' + ref[sp].note : ''}` : 'Espèce ajoutée à la main'}
              >
                <Text size="xs" w={150} truncate>
                  <b>{sp}</b> {ref[sp]?.nom || ''}
                </Text>
              </Tooltip>
              <TextInput
                size="xs"
                style={{ flex: 1 }}
                value={gears.join(', ')}
                onChange={(e) => set({ ...params, coherents: { ...coh, [sp]: e.currentTarget.value.split(/[\s,;]+/).filter(Boolean) } })}
              />
              <ActionIcon size="sm" variant="subtle" color="red" aria-label={`Retirer ${sp}`} onClick={() => { const c = { ...coh }; delete c[sp]; set({ ...params, coherents: c }); }}>
                <IconTrash size={14} />
              </ActionIcon>
            </Group>
          ))}
        </Stack>
        </ScrollArea.Autosize>
        <Stack gap={4} mt={4}>
          <Button
            size="xs"
            variant="light"
            w="fit-content"
            leftSection={<IconPlus size={14} />}
            onClick={() => {
              const sp = prompt('Code espèce FAO (ex. HKE)');
              if (sp) set({ ...params, coherents: { ...coh, [sp.toUpperCase()]: [] } });
            }}
          >
            Ajouter une espèce
          </Button>
        </Stack>
      </Paper>
      <Paper withBorder p="xs">
        <Group justify="space-between" mb={4}>
          <Text size="sm" fw={600}>
            Corrections connues ({corrections.length})
          </Text>
          <Group gap={4}>
            <Button size="xs" variant="light" loading={loading} disabled={!params.species_column || !params.gear_column} onClick={load}>
              Charger les incohérences du jeu
            </Button>
            <Button
              size="xs"
              variant="default"
              disabled={!corrections.length}
              onClick={() => {
                const lines = ['navire;espece;engin_declare;engin_corrige;lignes', ...corrections.map((c) => [c.vessel ?? '', c.species, c.gear, c.corrected ?? '', c.n ?? ''].join(';'))];
                saveText('\ufeff' + lines.join('\r\n'), 'corrections_engins.csv', 'text/csv;charset=utf-8');
              }}
            >
              Exporter (CSV)
            </Button>
            <FileButton
              accept=".csv,text/csv"
              onChange={async (f) => {
                if (!f) return;
                const rows = (await f.text()).replace(/^\ufeff/, '').split(/\r?\n/).filter((l) => l.trim());
                const sep = rows[0].includes(';') ? ';' : ',';
                const imported = rows.slice(1).map((l) => {
                  const [vessel, species, gear, corrected] = l.split(sep).map((x) => x.trim());
                  return { vessel: vessel || undefined, species: (species || '').toUpperCase(), gear: (gear || '').toUpperCase(), corrected: (corrected || '').toUpperCase() };
                }).filter((c) => c.species && c.gear);
                const key = (c: any) => `${c.vessel ?? ''}|${c.species}|${c.gear}`;
                const byKey = new Map(corrections.map((c) => [key(c), c]));
                imported.forEach((c) => byKey.set(key(c), { ...byKey.get(key(c)), ...c }));
                set({ ...params, corrections: [...byKey.values()] });
              }}
            >
              {(props) => (
                <Button {...props} size="xs" variant="default">
                  Importer (CSV)
                </Button>
              )}
            </FileButton>
          </Group>
        </Group>
        <Text size="xs" c="dimmed" mb={6}>
          Pour chaque incohérence, indiquez l’engin réel (laisser vide = rester marqué « * »). Ces corrections sont enregistrées dans la recette et donc dans la fiche méthode.
        </Text>
        <ScrollArea h={corrections.length ? 220 : 0}>
          <Stack gap={4}>
            {corrections.map((c, i) => (
              <Group key={i} gap={6} wrap="nowrap">
                <Text size="xs" style={{ flex: 1 }} truncate>
                  {c.vessel ? `${c.vessel} · ` : ''}
                  {c.species} / {c.gear}
                  {c.n ? ` (${c.n} l.)` : ''}
                </Text>
                <TextInput
                  size="xs"
                  w={110}
                  placeholder="engin réel"
                  value={c.corrected || ''}
                  onChange={(e) => set({ ...params, corrections: corrections.map((x, j) => (j === i ? { ...x, corrected: e.currentTarget.value.toUpperCase() } : x)) })}
                />
                <ActionIcon size="sm" variant="subtle" color="red" onClick={() => set({ ...params, corrections: corrections.filter((_, j) => j !== i) })}>
                  <IconTrash size={14} />
                </ActionIcon>
              </Group>
            ))}
          </Stack>
        </ScrollArea>
      </Paper>
    </Stack>
  );
}

function DedupeForm(p: FormProps) {
  return (
    <Stack>
      <ColumnsForm {...p} label="Colonnes à comparer (vide = toutes)" />
      <Text size="xs" c="dimmed">
        La première occurrence (dans l’ordre du fichier d’origine) est conservée.
      </Text>
    </Stack>
  );
}

export default function StepForm(props: FormProps & { type: string }) {
  switch (props.type) {
    case 'filter':
      return <FilterForm {...props} />;
    case 'select_columns':
      return <ColumnsForm {...props} label="Colonnes à garder" />;
    case 'drop_columns':
      return <ColumnsForm {...props} label="Colonnes à supprimer" />;
    case 'rename':
      return <RenameForm {...props} />;
    case 'cast':
      return <CastForm {...props} />;
    case 'replace_values':
      return <ReplaceForm {...props} />;
    case 'formula':
      return <FormulaForm {...props} />;
    case 'case_when':
      return <CaseWhenForm {...props} />;
    case 'aggregate':
      return <AggregateForm {...props} />;
    case 'sort':
      return <SortForm {...props} />;
    case 'dedupe':
      return <DedupeForm {...props} />;
    case 'fill_null':
      return <FillForm {...props} />;
    case 'clean_text':
      return <CleanForm {...props} />;
    case 'date_parts':
      return <DatePartsForm {...props} />;
    case 'anonymize':
      return <AnonForm {...props} />;
    case 'join':
      return <JoinForm {...props} />;
    case 'union':
      return <UnionForm {...props} />;
    case 'lookup':
      return <LookupForm {...props} />;
    case 'unit_convert':
      return <UnitForm {...props} />;
    case 'gear_check':
      return <GearCheckForm {...props} />;
    case 'edit_cells':
      return (
        <Text size="sm">
          Les corrections de cellules se font directement dans le tableau (double-clic sur une cellule), puis « Enregistrer les corrections ».
        </Text>
      );
    default:
      return <NumberInput disabled label="Type d’étape inconnu" />;
  }
}

export const DEFAULT_PARAMS: Record<string, any> = {
  filter: { keep: true, logic: 'and', conditions: [{ column: '', op: 'eq', value: '' }] },
  aggregate: { group_by: [], aggregations: [{ column: '', fn: 'somme', name: '' }] },
  sort: { by: [{ column: '', desc: false }] },
  case_when: { name: '', rules: [{ conditions: [{ column: '', op: 'eq', value: '' }], value: '' }], default: null },
  join: { how: 'left', keys: [{ left: '', right: '' }] },
  clean_text: { trim: true, empty_to_null: true, case: 'none' },
  anonymize: { method: 'code' },
  rename: { mapping: {} },
  replace_values: { pairs: [] },
  fill_null: { method: 'valeur' },
  lookup: { referentiel: 'engins_metiers', default: 'Autres' },
  unit_convert: { from: 'kg', to: 't' },
  gear_check: { name: 'engin_sug', corrections: [] },
};
