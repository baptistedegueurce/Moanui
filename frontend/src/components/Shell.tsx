import { ReactNode } from 'react';
import { AppShell, Group, Menu, NavLink, Select, Text, UnstyledButton, Avatar, Badge, Box, ScrollArea } from '@mantine/core';
import {
  IconHome,
  IconTable,
  IconChartBar,
  IconMap2,
  IconMathFunction,
  IconBook,
  IconSettings,
  IconPalette,
  IconLogout,
  IconChevronDown,
} from '@tabler/icons-react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../lib/auth';
import { fail } from '../lib/notify';

const ROLE_LABEL: Record<string, string> = { admin: 'Admin', analyste: 'Analyste', lecteur: 'Lecteur' };

export function StructureLogo({ id, has, height = 34 }: { id: string; has: boolean; height?: number }) {
  if (!has) return null;
  return <img className="mo-logo" style={{ maxHeight: height }} src={`/api/structures/${id}/logo`} alt="" />;
}

export default function Shell({ children }: { children: ReactNode }) {
  const { me, structure, switchStructure, logout, isStructureAdmin, meta } = useAuth();
  const loc = useLocation();
  const is = (p: string) => (p === '/' ? loc.pathname === '/' : loc.pathname.startsWith(p));

  const nav = (to: string, label: string, icon: ReactNode, extra?: ReactNode) => (
    <NavLink component={Link} to={to} label={label} leftSection={icon} active={is(to)} rightSection={extra} />
  );

  return (
    <AppShell header={{ height: 56 }} navbar={{ width: 230, breakpoint: 'sm' }} padding="md">
      <AppShell.Header style={{ background: 'var(--mo-primary)', color: 'var(--mo-primary-contrast)', borderBottom: 0 }}>
        <Group h="100%" px="md" justify="space-between" wrap="nowrap">
          <Group gap="lg" wrap="nowrap">
            <div className="mo-brand">
              <img src="/favicon.svg" width={28} height={28} alt="" />
              <span style={{ fontSize: 18 }}>Moanui</span>
            </div>
            {me && me.structures.length > 1 ? (
              <Select
                size="xs"
                w={260}
                value={structure?.id}
                data={me.structures.map((s) => ({ value: s.id, label: s.name }))}
                onChange={(v) => v && switchStructure(v).catch(fail)}
                aria-label="Structure active"
                allowDeselect={false}
              />
            ) : (
              <Text size="sm" fw={500} style={{ opacity: 0.9 }}>
                {structure?.name}
              </Text>
            )}
          </Group>
          <Group gap="md" wrap="nowrap">
            {structure && (
              <Box style={{ background: '#fff', borderRadius: 6, padding: structure.has_logo ? '2px 6px' : 0 }}>
                <StructureLogo id={structure.id} has={structure.has_logo} height={30} />
              </Box>
            )}
            <Menu position="bottom-end" withinPortal>
              <Menu.Target>
                <UnstyledButton style={{ color: 'inherit' }}>
                  <Group gap={6} wrap="nowrap">
                    <Avatar size="sm" color="gray" radius="xl">
                      {me?.display_name.slice(0, 2).toUpperCase()}
                    </Avatar>
                    <Text size="sm">{me?.display_name}</Text>
                    <IconChevronDown size={14} />
                  </Group>
                </UnstyledButton>
              </Menu.Target>
              <Menu.Dropdown>
                <Menu.Label>
                  {structure?.short_name} · {ROLE_LABEL[structure?.role || ''] || ''}
                </Menu.Label>
                <Menu.Item leftSection={<IconLogout size={16} />} onClick={() => logout()}>
                  Se déconnecter
                </Menu.Item>
              </Menu.Dropdown>
            </Menu>
          </Group>
        </Group>
      </AppShell.Header>

      <AppShell.Navbar p="xs" style={{ background: 'var(--mo-surface)' }}>
        <ScrollArea style={{ flex: 1 }}>
          {nav('/', 'Accueil', <IconHome size={18} />)}
          <div className="mo-nav-section">Travailler</div>
          {nav('/donnees', 'Données', <IconTable size={18} />)}
          {nav('/graphiques', 'Graphiques', <IconChartBar size={18} />)}
          {nav('/cartographie', 'Cartographie', <IconMap2 size={18} />, <Badge size="xs" variant="light">bientôt</Badge>)}
          {nav('/statistiques', 'Statistiques', <IconMathFunction size={18} />, <Badge size="xs" variant="light">bientôt</Badge>)}
          <div className="mo-nav-section">Aide</div>
          {nav('/guide', 'Bonnes pratiques', <IconBook size={18} />)}
          {(isStructureAdmin || me?.is_superadmin) && (
            <>
              <div className="mo-nav-section">Réglages</div>
              {isStructureAdmin && nav('/structure', 'Charte de la structure', <IconPalette size={18} />)}
              {me?.is_superadmin && nav('/administration', 'Administration', <IconSettings size={18} />)}
            </>
          )}
        </ScrollArea>
        <Text size="xs" c="dimmed" ta="center" p="xs">
          Moanui {meta?.version}
        </Text>
      </AppShell.Navbar>

      <AppShell.Main style={{ background: 'var(--mo-bg)' }}>{children}</AppShell.Main>
    </AppShell>
  );
}
