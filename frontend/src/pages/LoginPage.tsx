import { useState } from 'react';
import { Alert, Button, Center, Paper, PasswordInput, Stack, Text, TextInput, Title } from '@mantine/core';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';

export default function LoginPage() {
  const { refresh } = useAuth();
  const [username, setU] = useState('');
  const [password, setP] = useState('');
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      await api.post('/api/auth/login', { username, password });
      await refresh();
    } catch (e: any) {
      setErr(e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Center mih="100vh" p="md">
      <Paper withBorder shadow="sm" p="xl" w={380}>
        <form onSubmit={submit}>
          <Stack>
            <div style={{ textAlign: 'center' }}>
              <img src="/favicon.svg" width={48} alt="" />
              <Title order={2}>Moanui</Title>
              <Text c="dimmed" size="sm">
                Données halieutiques : traiter, comprendre, présenter
              </Text>
            </div>
            <TextInput label="Identifiant" value={username} onChange={(e) => setU(e.currentTarget.value)} autoFocus />
            <PasswordInput label="Mot de passe" value={password} onChange={(e) => setP(e.currentTarget.value)} />
            {err && <Alert color="red">{err}</Alert>}
            <Button type="submit" loading={busy}>
              Se connecter
            </Button>
          </Stack>
        </form>
      </Paper>
    </Center>
  );
}
