import { useState } from 'react';
import { Alert, Button, Group, List, Modal, Select, Stack, Text, TextInput, Textarea } from '@mantine/core';
import { Dropzone } from '@mantine/dropzone';
import { IconUpload } from '@tabler/icons-react';
import { api } from '../lib/api';
import type { CatalogLayer } from '../lib/carto';
import { fail, ok } from '../lib/notify';

interface Found {
  file: string;
  layer: string;
  n: number | null;
  geometry: string | null;
  crs: string | null;
  fields: string[];
}

/** Import d'une couche SHP / GeoPackage / GeoJSON / KML (copie brute conservée, reprojection en WGS84). */
export default function LayerImportModal({ opened, onClose, onDone }: { opened: boolean; onClose: () => void; onDone: (l: CatalogLayer) => void }) {
  const [files, setFiles] = useState<File[]>([]);
  const [found, setFound] = useState<Found[] | null>(null);
  const [choice, setChoice] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [crs, setCrs] = useState('');
  const [busy, setBusy] = useState(false);

  const reset = () => {
    setFiles([]);
    setFound(null);
    setChoice(null);
    setName('');
    setDescription('');
    setCrs('');
  };

  const form = () => {
    const f = new FormData();
    files.forEach((x) => f.append('files', x, x.name));
    return f;
  };

  const inspect = async (list: File[]) => {
    setFiles(list);
    setFound(null);
    if (!list.length) return;
    const f = new FormData();
    list.forEach((x) => f.append('files', x, x.name));
    setBusy(true);
    try {
      const r = await api.upload<{ layers: Found[] }>('/api/geo/layers/inspect', f);
      setFound(r.layers);
      const first = r.layers[0];
      setChoice(first ? `${first.file}|${first.layer}` : null);
      if (first && !name) setName(first.layer);
    } catch (e) {
      fail(e, 'Fichiers illisibles');
    } finally {
      setBusy(false);
    }
  };

  const sel = found?.find((x) => `${x.file}|${x.layer}` === choice);

  const submit = async () => {
    if (!sel) return;
    const f = form();
    f.append('name', name);
    f.append('description', description);
    f.append('file', sel.file);
    if (found && found.filter((x) => x.file === sel.file).length > 1) f.append('layer', sel.layer);
    f.append('crs', crs.trim());
    setBusy(true);
    try {
      const l = await api.upload<CatalogLayer>('/api/geo/layers', f);
      ok(`${l.n_features} entités importées.`, 'Couche importée');
      (l.warnings || []).forEach((w) => ok(w, 'À savoir'));
      onDone(l);
      reset();
      onClose();
    } catch (e) {
      fail(e, 'Import impossible');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal opened={opened} onClose={() => { reset(); onClose(); }} title="Importer une couche géographique" size="lg">
      <Stack>
        <Text size="sm" c="dimmed">
          Shapefile (sélectionnez ensemble .shp, .dbf, .shx, .prj, ou un zip), GeoPackage, GeoJSON, KML. Le fichier d'origine est conservé tel quel ; la couche est
          reprojetée en WGS84 et optimisée pour l'affichage.
        </Text>
        <Dropzone onDrop={inspect} multiple maxSize={1024 ** 3} loading={busy}>
          <Group justify="center" gap="sm" mih={90} style={{ pointerEvents: 'none' }}>
            <IconUpload size={28} />
            <Text>Déposez les fichiers ici ou cliquez pour les choisir</Text>
          </Group>
        </Dropzone>
        {files.length > 0 && (
          <Text size="xs" c="dimmed">
            {files.map((f) => f.name).join(', ')}
          </Text>
        )}
        {found && (
          <>
            {found.length > 1 && (
              <Select
                label="Couche à importer"
                data={found.map((x) => ({ value: `${x.file}|${x.layer}`, label: `${x.layer} (${x.file}) : ${x.n ?? '?'} entités, ${x.geometry || '?'}` }))}
                value={choice}
                onChange={setChoice}
              />
            )}
            {sel && (
              <Alert variant="light" color={sel.crs ? 'teal' : 'orange'} title={`${sel.n ?? '?'} entités · ${sel.geometry || 'géométrie ?'}`}>
                <List size="sm">
                  <List.Item>Projection : {sel.crs || 'non indiquée (fichier .prj absent ?)'}</List.Item>
                  <List.Item>Attributs : {sel.fields.slice(0, 15).join(', ') || 'aucun'}{sel.fields.length > 15 ? '…' : ''}</List.Item>
                </List>
              </Alert>
            )}
            <TextInput label="Nom de la couche" value={name} onChange={(e) => setName(e.currentTarget.value)} required />
            <Textarea label="Description / source (recommandé)" autosize minRows={2} value={description} onChange={(e) => setDescription(e.currentTarget.value)} />
            {sel && !sel.crs && (
              <TextInput
                label="Code EPSG de la projection"
                description="Ex. EPSG:2154 (Lambert-93), EPSG:4326 (degrés WGS84), EPSG:32630 (UTM 30N). Laissez vide si les coordonnées sont en degrés."
                value={crs}
                onChange={(e) => setCrs(e.currentTarget.value)}
              />
            )}
          </>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={() => { reset(); onClose(); }}>
            Annuler
          </Button>
          <Button onClick={submit} disabled={!sel || !name.trim()} loading={busy}>
            Importer
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
