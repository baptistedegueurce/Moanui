import { useState } from 'react';
import { Button, Center, Paper, PasswordInput, Select, Stack, Text, TextInput, Title, Alert } from '@mantine/core';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';

const KINDS = [
  { value: 'crpm', label: 'Comité régional (CRPM)' },
  { value: 'cdpm', label: 'Comité départemental (CDPMEM)' },
  { value: 'cnpm', label: 'Comité national (CNPMEM)' },
  { value: 'op', label: 'Organisation de producteurs (OP)' },
  { value: 'autre', label: 'Autre' },
];

export default function SetupPage() {
  const { refresh } = useAuth();
  const [f, setF] = useState({
    username: '',
    display_name: '',
    password: '',
    password2: '',
    structure_name: '',
    structure_short_name: '',
    structure_kind: 'crpm',
  });
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const set = (k: string) => (e: any) => setF({ ...f, [k]: e?.currentTarget ? e.currentTarget.value : e });

  const submit = async () => {
    setErr(null);
    if (f.password !== f.password2) return setErr('Les deux mots de passe ne correspondent pas.');
    setBusy(true);
    try {
      await api.post('/api/setup', f);
      await refresh();
    } catch (e: any) {
      setErr(e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Center mih="100vh" p="md">
      <Paper withBorder shadow="sm" p="xl" w={520}>
        <Stack>
          <div>
            <Title order={2}>Bienvenue dans Moanui</Title>
            <Text c="dimmed" size="sm">
              Première installation : créez le compte administrateur et votre structure. Tout reste sur cet ordinateur.
            </Text>
          </div>
          <TextInput label="Nom affiché" placeholder="Prénom Nom" value={f.display_name} onChange={set('display_name')} required />
          <TextInput label="Identifiant de connexion" value={f.username} onChange={set('username')} required />
          <PasswordInput label="Mot de passe" description="8 caractères minimum, lettres et chiffres" value={f.password} onChange={set('password')} required />
          <PasswordInput label="Confirmer le mot de passe" value={f.password2} onChange={set('password2')} required />
          <TextInput label="Nom de la structure" placeholder="Comité régional des pêches…" value={f.structure_name} onChange={set('structure_name')} required />
          <TextInput label="Sigle" placeholder="CRPMEM…" value={f.structure_short_name} onChange={set('structure_short_name')} required />
          <Select label="Type de structure" data={KINDS} value={f.structure_kind} onChange={set('structure_kind')} />
          {err && <Alert color="red">{err}</Alert>}
          <Button onClick={submit} loading={busy}>
            Créer et commencer
          </Button>
        </Stack>
      </Paper>
    </Center>
  );
}
