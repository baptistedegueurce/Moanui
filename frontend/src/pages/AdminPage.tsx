import { useEffect, useState } from 'react';
import { ActionIcon, Badge, Button, Group, Modal, Paper, PasswordInput, Select, Stack, Switch, Table, Tabs, Text, TextInput, Title, Alert } from '@mantine/core';
import { IconPlus, IconPencil, IconTrash, IconPalette } from '@tabler/icons-react';
import { api } from '../lib/api';
import { useAuth } from '../lib/auth';
import { fmtDate } from '../lib/format';
import { fail, ok } from '../lib/notify';
import type { Structure } from '../lib/types';
import { ThemeEditor } from './StructurePage';

interface AdminUser {
  id: string;
  username: string;
  display_name: string;
  is_superadmin: boolean;
  created_at: string;
  memberships: { structure_id: string; role: string; name: string }[];
}

const ROLES = [
  { value: 'admin', label: 'Administrateur' },
  { value: 'analyste', label: 'Analyste (modifie les données)' },
  { value: 'lecteur', label: 'Lecteur (consulte, exporte)' },
];

function UserModal({ user, structures, onClose, onSaved }: { user: AdminUser | 'new' | null; structures: Structure[]; onClose: () => void; onSaved: () => void }) {
  const isNew = user === 'new';
  const [f, setF] = useState<any>({});
  useEffect(() => {
    if (user === 'new') setF({ username: '', display_name: '', password: '', is_superadmin: false, memberships: [] });
    else if (user) setF({ display_name: user.display_name, password: '', is_superadmin: user.is_superadmin, memberships: user.memberships.map((m) => ({ structure_id: m.structure_id, role: m.role })) });
  }, [user]);
  if (!user) return null;
  const ms: any[] = f.memberships || [];
  const save = async () => {
    try {
      if (isNew) await api.post('/api/admin/users', f);
      else await api.patch(`/api/admin/users/${(user as AdminUser).id}`, { ...f, password: f.password || undefined });
      ok('Compte enregistré');
      onSaved();
      onClose();
    } catch (e) {
      fail(e);
    }
  };
  return (
    <Modal opened onClose={onClose} title={isNew ? 'Nouveau compte' : `Modifier ${(user as AdminUser).username}`} size="lg">
      <Stack>
        {isNew && <TextInput label="Identifiant" value={f.username || ''} onChange={(e) => setF({ ...f, username: e.currentTarget.value })} />}
        <TextInput label="Nom affiché" value={f.display_name || ''} onChange={(e) => setF({ ...f, display_name: e.currentTarget.value })} />
        <PasswordInput label={isNew ? 'Mot de passe' : 'Nouveau mot de passe (laisser vide pour ne pas changer)'} value={f.password || ''} onChange={(e) => setF({ ...f, password: e.currentTarget.value })} />
        <Switch label="Administrateur général (gère toutes les structures et les comptes)" checked={!!f.is_superadmin} onChange={(e) => setF({ ...f, is_superadmin: e.currentTarget.checked })} />
        <Text fw={500} size="sm">
          Structures et rôles
        </Text>
        {ms.map((m, i) => (
          <Group key={i} grow>
            <Select data={structures.map((s) => ({ value: s.id, label: s.name }))} value={m.structure_id} onChange={(v) => setF({ ...f, memberships: ms.map((x, j) => (j === i ? { ...x, structure_id: v } : x)) })} />
            <Group wrap="nowrap">
              <Select style={{ flex: 1 }} data={ROLES} value={m.role} onChange={(v) => setF({ ...f, memberships: ms.map((x, j) => (j === i ? { ...x, role: v } : x)) })} />
              <ActionIcon color="red" variant="subtle" onClick={() => setF({ ...f, memberships: ms.filter((_, j) => j !== i) })}>
                <IconTrash size={16} />
              </ActionIcon>
            </Group>
          </Group>
        ))}
        <Button variant="light" size="xs" w="fit-content" leftSection={<IconPlus size={14} />} onClick={() => setF({ ...f, memberships: [...ms, { structure_id: structures[0]?.id, role: 'analyste' }] })}>
          Ajouter une structure
        </Button>
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Annuler
          </Button>
          <Button onClick={save}>Enregistrer</Button>
        </Group>
      </Stack>
    </Modal>
  );
}

export default function AdminPage() {
  const { me, refresh } = useAuth();
  const [structures, setStructures] = useState<(Structure & { members: number })[]>([]);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [journal, setJournal] = useState<any[]>([]);
  const [kinds, setKinds] = useState<Record<string, string>>({});
  const [editUser, setEditUser] = useState<AdminUser | 'new' | null>(null);
  const [newS, setNewS] = useState<any | null>(null);
  const [themeFor, setThemeFor] = useState<Structure | null>(null);

  const load = () => {
    api.get('/api/admin/structures').then(setStructures).catch(fail);
    api.get('/api/admin/users').then(setUsers).catch(fail);
    api.get('/api/admin/structure-kinds').then(setKinds).catch(() => {});
  };
  useEffect(load, []);

  if (!me?.is_superadmin) return <Alert>Réservé à l’administrateur général.</Alert>;

  return (
    <Stack maw={1200}>
      <Title order={2}>Administration</Title>
      <Tabs defaultValue="structures" onChange={(t) => t === 'journal' && api.get('/api/admin/journal').then(setJournal).catch(fail)}>
        <Tabs.List>
          <Tabs.Tab value="structures">Structures</Tabs.Tab>
          <Tabs.Tab value="comptes">Comptes</Tabs.Tab>
          <Tabs.Tab value="journal">Journal d’activité</Tabs.Tab>
        </Tabs.List>
        <Tabs.Panel value="structures" pt="md">
          <Group justify="flex-end" mb="sm">
            <Button leftSection={<IconPlus size={16} />} onClick={() => setNewS({ name: '', short_name: '', kind: 'crpm', preset: 'neutre' })}>
              Nouvelle structure
            </Button>
          </Group>
          <Paper withBorder>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Structure</Table.Th>
                  <Table.Th>Type</Table.Th>
                  <Table.Th>Membres</Table.Th>
                  <Table.Th>Charte</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {structures.map((s) => (
                  <Table.Tr key={s.id}>
                    <Table.Td>
                      <Text fw={600}>{s.name}</Text>
                      <Text size="xs" c="dimmed">
                        {s.short_name}
                      </Text>
                    </Table.Td>
                    <Table.Td>{kinds[s.kind] || s.kind}</Table.Td>
                    <Table.Td>{s.members}</Table.Td>
                    <Table.Td>
                      <Group gap={2}>
                        {[s.theme.colors.primary, s.theme.colors.accent, ...s.theme.palette.slice(0, 4)].map((c, i) => (
                          <div key={i} style={{ width: 16, height: 16, borderRadius: 3, background: c }} />
                        ))}
                        {s.has_logo && <Badge size="xs" ml={6} variant="light">logo</Badge>}
                      </Group>
                    </Table.Td>
                    <Table.Td>
                      <ActionIcon variant="subtle" onClick={() => setThemeFor(s)} aria-label="Modifier la charte">
                        <IconPalette size={16} />
                      </ActionIcon>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Paper>
        </Tabs.Panel>
        <Tabs.Panel value="comptes" pt="md">
          <Group justify="flex-end" mb="sm">
            <Button leftSection={<IconPlus size={16} />} onClick={() => setEditUser('new')}>
              Nouveau compte
            </Button>
          </Group>
          <Paper withBorder>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Compte</Table.Th>
                  <Table.Th>Structures</Table.Th>
                  <Table.Th>Créé le</Table.Th>
                  <Table.Th />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {users.map((u) => (
                  <Table.Tr key={u.id}>
                    <Table.Td>
                      <Text fw={600}>
                        {u.display_name} {u.is_superadmin && <Badge size="xs">admin général</Badge>}
                      </Text>
                      <Text size="xs" c="dimmed">
                        {u.username}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      {u.memberships.map((m) => (
                        <Badge key={m.structure_id} variant="light" mr={4}>
                          {m.name} · {m.role}
                        </Badge>
                      ))}
                    </Table.Td>
                    <Table.Td>{fmtDate(u.created_at)}</Table.Td>
                    <Table.Td>
                      <Group gap={2} justify="flex-end">
                        <ActionIcon variant="subtle" onClick={() => setEditUser(u)}>
                          <IconPencil size={16} />
                        </ActionIcon>
                        {u.id !== me.id && (
                          <ActionIcon
                            variant="subtle"
                            color="red"
                            onClick={() => {
                              if (confirm(`Supprimer le compte ${u.username} ? S’il a créé des données, il sera désactivé pour garder la traçabilité.`))
                                api.del(`/api/admin/users/${u.id}`).then(load).catch(fail);
                            }}
                          >
                            <IconTrash size={16} />
                          </ActionIcon>
                        )}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Paper>
        </Tabs.Panel>
        <Tabs.Panel value="journal" pt="md">
          <Paper withBorder>
            <Table fz="sm">
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Qui</Table.Th>
                  <Table.Th>Action</Table.Th>
                  <Table.Th>Détails</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {journal.map((j) => (
                  <Table.Tr key={j.id}>
                    <Table.Td>{fmtDate(j.at)}</Table.Td>
                    <Table.Td>{j.user_name || '—'}</Table.Td>
                    <Table.Td>{j.action.replace(/_/g, ' ')}</Table.Td>
                    <Table.Td>
                      <Text size="xs" c="dimmed" lineClamp={2}>
                        {Object.entries(j.details)
                          .filter(([k]) => k !== 'removed')
                          .map(([k, v]) => `${k} : ${typeof v === 'object' ? JSON.stringify(v) : v}`)
                          .join(' · ')}
                      </Text>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Paper>
        </Tabs.Panel>
      </Tabs>

      <UserModal user={editUser} structures={structures} onClose={() => setEditUser(null)} onSaved={load} />
      <Modal opened={!!newS} onClose={() => setNewS(null)} title="Nouvelle structure">
        {newS && (
          <Stack>
            <TextInput label="Nom" value={newS.name} onChange={(e) => setNewS({ ...newS, name: e.currentTarget.value })} />
            <TextInput label="Sigle" value={newS.short_name} onChange={(e) => setNewS({ ...newS, short_name: e.currentTarget.value })} />
            <Select label="Type" data={Object.entries(kinds).map(([k, v]) => ({ value: k, label: v }))} value={newS.kind} onChange={(v) => setNewS({ ...newS, kind: v })} />
            <Select
              label="Charte de départ"
              data={[
                { value: 'neutre', label: 'Neutre' },
                { value: 'ocean', label: 'Océan' },
                { value: 'sable', label: 'Sable' },
              ]}
              value={newS.preset}
              onChange={(v) => setNewS({ ...newS, preset: v })}
            />
            <Button
              onClick={() =>
                api
                  .post('/api/admin/structures', newS)
                  .then(() => {
                    setNewS(null);
                    load();
                    refresh();
                  })
                  .catch(fail)
              }
            >
              Créer
            </Button>
          </Stack>
        )}
      </Modal>
      <Modal opened={!!themeFor} onClose={() => setThemeFor(null)} title={`Charte : ${themeFor?.name}`} size="90%">
        {themeFor && (
          <ThemeEditor
            structure={themeFor}
            onSaved={() => {
              load();
              refresh();
            }}
          />
        )}
      </Modal>
    </Stack>
  );
}
