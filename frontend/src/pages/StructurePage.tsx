import { useEffect, useState } from 'react';
import { Button, ColorInput, FileButton, Group, Paper, Select, SimpleGrid, Stack, Text, TextInput, Title, Alert } from '@mantine/core';
import { IconUpload } from '@tabler/icons-react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fail, ok } from '../lib/notify';
import type { Structure, Theme } from '../lib/types';
import { StructureLogo } from '../components/Shell';

const COLOR_LABELS: Record<string, string> = {
  primary: 'Couleur principale (bandeau)',
  primary_contrast: 'Texte sur couleur principale',
  accent: 'Couleur d’accent',
  background: 'Fond de page',
  surface: 'Fond des panneaux',
  text: 'Texte',
  muted: 'Texte secondaire',
  border: 'Bordures',
};

export function ThemeEditor({ structure, onSaved }: { structure: Structure; onSaved: () => void }) {
  const [theme, setTheme] = useState<Theme>(structure.theme);
  const [presets, setPresets] = useState<Record<string, Theme>>({});
  const [v, setV] = useState(0);
  useEffect(() => setTheme(structure.theme), [structure]);
  useEffect(() => {
    api.get('/api/themes/presets').then(setPresets).catch(() => {});
  }, []);

  const save = async () => {
    try {
      await api.patch(`/api/structures/${structure.id}`, { theme });
      ok('Charte enregistrée');
      onSaved();
    } catch (e) {
      fail(e);
    }
  };

  const upload = async (f: File | null) => {
    if (!f) return;
    const fd = new FormData();
    fd.append('file', f);
    try {
      await api.upload(`/api/structures/${structure.id}/logo`, fd);
      ok('Logo enregistré');
      setV((x) => x + 1);
      onSaved();
    } catch (e) {
      fail(e);
    }
  };

  return (
    <Stack>
      <Paper withBorder p="md">
        <Group justify="space-between">
          <div>
            <Text fw={600}>Logo</Text>
            <Text size="xs" c="dimmed">
              PNG, SVG, JPEG ou WEBP, 2 Mo max. Utilisé dans l’en-tête et sur les graphiques. Utilisez le fichier officiel fourni par la structure.
            </Text>
          </div>
          <Group>
            <StructureLogo key={v} id={structure.id} has={structure.has_logo} height={48} />
            <FileButton onChange={upload} accept="image/png,image/jpeg,image/svg+xml,image/webp">
              {(props) => (
                <Button {...props} variant="default" leftSection={<IconUpload size={16} />}>
                  Téléverser
                </Button>
              )}
            </FileButton>
          </Group>
        </Group>
      </Paper>
      <Paper withBorder p="md">
        <Group justify="space-between" mb="sm">
          <Text fw={600}>Couleurs de l’interface</Text>
          <Select
            size="xs"
            placeholder="Partir d’un modèle…"
            data={Object.entries(presets).map(([k, t]) => ({ value: k, label: t.name }))}
            onChange={(k) => k && setTheme({ ...presets[k], logo: theme.logo })}
          />
        </Group>
        <SimpleGrid cols={{ base: 1, sm: 2, md: 4 }}>
          {Object.entries(COLOR_LABELS).map(([k, label]) => (
            <ColorInput key={k} label={label} value={(theme.colors as any)[k]} onChange={(c) => setTheme({ ...theme, colors: { ...theme.colors, [k]: c } })} format="hex" />
          ))}
        </SimpleGrid>
      </Paper>
      <Paper withBorder p="md">
        <Text fw={600}>Couleurs des graphiques</Text>
        <Text size="xs" c="dimmed" mb="sm">
          La palette par défaut a été validée pour les daltonismes et le contraste ; l’ordre des couleurs compte. Si vous la remplacez par celle de votre charte, gardez des couleurs bien distinctes et testez l’impression en noir et blanc.
        </Text>
        <Group gap={6} mb="xs">
          {theme.palette.map((c, i) => (
            <ColorInput key={i} w={120} size="xs" value={c} format="hex" onChange={(nc) => setTheme({ ...theme, palette: theme.palette.map((x, j) => (j === i ? nc : x)) })} />
          ))}
        </Group>
        <Group gap={0} mb="xs">
          {theme.sequential.map((c) => (
            <div key={c} style={{ width: 40, height: 16, background: c }} />
          ))}
          <Text size="xs" c="dimmed" ml="sm">
            dégradé (cartes de chaleur)
          </Text>
        </Group>
        <SimpleGrid cols={{ base: 1, sm: 3 }}>
          <TextInput label="Source par défaut des graphiques" value={theme.chart.default_source} onChange={(e) => setTheme({ ...theme, chart: { ...theme.chart, default_source: e.currentTarget.value } })} />
          <Select
            label="Position du logo sur les graphiques"
            data={[
              { value: 'bas-droite', label: 'En bas à droite' },
              { value: 'bas-gauche', label: 'En bas à gauche' },
              { value: 'haut-droite', label: 'En haut à droite' },
              { value: 'haut-gauche', label: 'En haut à gauche' },
            ]}
            value={theme.chart.logo_position}
            onChange={(p) => p && setTheme({ ...theme, chart: { ...theme.chart, logo_position: p } })}
          />
          <TextInput label="Police" value={theme.font} onChange={(e) => setTheme({ ...theme, font: e.currentTarget.value })} />
        </SimpleGrid>
      </Paper>
      <Group justify="flex-end">
        <Button onClick={save}>Enregistrer la charte</Button>
      </Group>
    </Stack>
  );
}

export default function StructurePage() {
  const { structure, refresh, isStructureAdmin } = useAuth();
  if (!structure || !isStructureAdmin) return <Alert>Réservé aux administrateurs de la structure.</Alert>;
  return (
    <Stack maw={1100}>
      <Title order={2}>Charte de {structure.short_name}</Title>
      <ThemeEditor structure={structure} onSaved={refresh} />
    </Stack>
  );
}
