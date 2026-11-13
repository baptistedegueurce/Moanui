import { useState } from 'react';
import { Alert, Badge, Button, Collapse, Group, Modal, Select, Stack, Table, Text, TextInput, Textarea, Switch } from '@mantine/core';
import { Dropzone } from '@mantine/dropzone';
import { IconUpload, IconFile, IconAlertTriangle } from '@tabler/icons-react';
import { api } from '../lib/api';
import { typeLabel, fmtNumber } from '../lib/format';
import type { ImportColumn } from '../lib/types';

const KINDS = [
  { value: 'generique', label: 'Générique' },
  { value: 'sacrois', label: 'SACROIS (captures / débarquements)' },
  { value: 'logbook', label: 'Journal de bord / marées' },
  { value: 'vms', label: 'VMS (positions)' },
  { value: 'referentiel', label: 'Référentiel (ports, espèces, engins…)' },
  { value: 'quotas', label: 'Quotas' },
];

interface Result {
  id: string;
  n_rows: number;
  report: { columns: ImportColumn[]; options: any };
  sensitive: { column: string; kind: string }[];
}

export default function ImportModal({ opened, onClose, onDone }: { opened: boolean; onClose: () => void; onDone: (id: string) => void }) {
  const [file, setFile] = useState<File | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [kind, setKind] = useState('generique');
  const [sheets, setSheets] = useState<string[]>([]);
  const [sheet, setSheet] = useState<string | null>(null);
  const [advanced, setAdvanced] = useState(false);
  const [delimiter, setDelimiter] = useState<string | null>(null);
  const [encoding, setEncoding] = useState<string | null>(null);
  const [header, setHeader] = useState(true);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [result, setResult] = useState<Result | null>(null);

  const reset = () => {
    setFile(null);
    setName('');
    setDescription('');
    setSheets([]);
    setSheet(null);
    setResult(null);
    setErr(null);
  };

  const pick = async (f: File) => {
    setFile(f);
    setName(f.name.replace(/\.[^.]+$/, ''));
    setErr(null);
    if (/\.xlsx?m?$/i.test(f.name)) {
      const fd = new FormData();
      fd.append('file', f);
      try {
        const r = await api.upload<{ sheets: string[] }>('/api/datasets/inspect', fd);
        setSheets(r.sheets);
        setSheet(r.sheets[0] || null);
      } catch (e: any) {
        setErr(e.message);
      }
    } else {
      setSheets([]);
    }
  };

  const submit = async () => {
    if (!file) return;
    setBusy(true);
    setErr(null);
    const fd = new FormData();
    fd.append('file', file);
    fd.append('name', name);
    fd.append('description', description);
    fd.append('kind', kind);
    const opts: any = { header };
    if (sheet) opts.sheet = sheet;
    if (delimiter) opts.delimiter = delimiter === 'tab' ? '\t' : delimiter;
    if (encoding) opts.encoding = encoding;
    fd.append('options', JSON.stringify(opts));
    try {
      setResult(await api.upload<Result>('/api/datasets/import', fd));
    } catch (e: any) {
      setErr(e.message);
    } finally {
      setBusy(false);
    }
  };

  const close = () => {
    reset();
    onClose();
  };

  const warnings = result?.report.columns.filter((c) => c.warning) || [];

  return (
    <Modal opened={opened} onClose={close} title="Importer un fichier" size="xl">
      {!result ? (
        <Stack>
          <Dropzone onDrop={(f) => f[0] && pick(f[0])} multiple={false} maxSize={1024 ** 3}>
            <Group justify="center" mih={110} style={{ pointerEvents: 'none' }}>
              {file ? <IconFile size={36} /> : <IconUpload size={36} />}
              <div>
                <Text fw={600}>{file ? file.name : 'Déposez un fichier ici ou cliquez pour choisir'}</Text>
                <Text size="sm" c="dimmed">
                  CSV, TXT, TSV ou Excel (XLSX). Le fichier d’origine sera conservé intact, en lecture seule.
                </Text>
              </div>
            </Group>
          </Dropzone>
          {file && (
            <>
              <Group grow>
                <TextInput label="Nom du jeu de données" value={name} onChange={(e) => setName(e.currentTarget.value)} />
                <Select label="Nature des données" data={KINDS} value={kind} onChange={(v) => setKind(v || 'generique')} />
              </Group>
              {sheets.length > 0 && <Select label="Feuille" data={sheets} value={sheet} onChange={setSheet} />}
              <Textarea
                label="Description (origine, période, qui a fourni le fichier…)"
                autosize
                minRows={2}
                value={description}
                onChange={(e) => setDescription(e.currentTarget.value)}
              />
              <Button variant="subtle" size="xs" onClick={() => setAdvanced((a) => !a)} w="fit-content">
                {advanced ? 'Masquer' : 'Afficher'} les options de lecture
              </Button>
              <Collapse in={advanced}>
                <Group grow>
                  <Select
                    label="Séparateur"
                    placeholder="Détection automatique"
                    clearable
                    data={[
                      { value: ';', label: 'Point-virgule ;' },
                      { value: ',', label: 'Virgule ,' },
                      { value: 'tab', label: 'Tabulation' },
                      { value: '|', label: 'Barre |' },
                    ]}
                    value={delimiter}
                    onChange={setDelimiter}
                  />
                  <Select
                    label="Encodage"
                    placeholder="Détection automatique"
                    clearable
                    data={[
                      { value: 'utf-8', label: 'UTF-8' },
                      { value: 'latin-1', label: 'Latin-1 / Windows' },
                    ]}
                    value={encoding}
                    onChange={setEncoding}
                  />
                  <Switch label="Première ligne = en-têtes" checked={header} onChange={(e) => setHeader(e.currentTarget.checked)} mt="xl" />
                </Group>
              </Collapse>
            </>
          )}
          {err && <Alert color="red">{err}</Alert>}
          <Group justify="flex-end">
            <Button variant="default" onClick={close}>
              Annuler
            </Button>
            <Button onClick={submit} disabled={!file} loading={busy}>
              Importer
            </Button>
          </Group>
        </Stack>
      ) : (
        <Stack>
          <Alert color="teal" title="Import réussi">
            {fmtNumber(result.n_rows)} lignes, {result.report.columns.length} colonnes. Séparateur «{' '}
            {result.report.options.delimiter === '\t' ? 'tabulation' : result.report.options.delimiter || '—'} », encodage{' '}
            {result.report.options.encoding || '—'}.
          </Alert>
          {warnings.length > 0 && (
            <Alert color="orange" icon={<IconAlertTriangle />} title="À vérifier">
              {warnings.map((c) => (
                <Text size="sm" key={c.name}>
                  <b>{c.name}</b> : {c.warning!.message}
                </Text>
              ))}
            </Alert>
          )}
          {result.sensitive.length > 0 && (
            <Alert color="grape" title="Colonnes sensibles repérées">
              {result.sensitive.map((s) => `${s.column} (${s.kind})`).join(', ')}. Vous pouvez les utiliser ; Moanui vous
              demandera confirmation avant tout export et propose une étape d’anonymisation.
            </Alert>
          )}
          <Table striped withTableBorder fz="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Colonne</Table.Th>
                <Table.Th>Type détecté</Table.Th>
                <Table.Th>Remarque</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {result.report.columns.map((c) => (
                <Table.Tr key={c.name}>
                  <Table.Td>{c.name}</Table.Td>
                  <Table.Td>
                    <Badge variant="light" color={c.warning ? 'orange' : 'gray'}>
                      {typeLabel(c.type)}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Text size="xs" c="dimmed">
                      {c.note}
                    </Text>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
          <Group justify="flex-end">
            <Button
              onClick={() => {
                const id = result.id;
                close();
                onDone(id);
              }}
            >
              Ouvrir le jeu de données
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}
