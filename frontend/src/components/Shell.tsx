import { ReactNode } from 'react';
import { AppShell, Group, Menu, NavLink, Select, Text, UnstyledButton, Avatar, Box, ScrollArea } from '@mantine/core';
import {
  IconHome,
  IconTable,
  IconChartBar,
  IconMap2,
  IconMathFunction,
  IconScale,
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
    <NavLink component={Link} to={to} label={label} leftSection={icon} active={is(to)} rightSection={extra} className="mo-nav" />
  );

  return (
    <AppShell header={{ height: 48 }} navbar={{ width: 224, breakpoint: 'sm' }} padding="lg">
      <AppShell.Header className="mo-header">
        <Group h="100%" px="md" justify="space-between" wrap="nowrap">
          <Group gap="lg" wrap="nowrap">
            <Link to="/" className="mo-brand">
              <img src="/favicon.svg" width={22} height={22} alt="" />
              <span>Moanui</span>
            </Link>
            <span className="mo-header-sep" />
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
              <span className="mo-header-ctx">{structure?.name}</span>
            )}
          </Group>
          <Group gap="md" wrap="nowrap">
            {structure && (
              <Box>
                <StructureLogo id={structure.id} has={structure.has_logo} height={28} />
              </Box>
            )}
            <Menu position="bottom-end" withinPortal>
              <Menu.Target>
                <UnstyledButton className="mo-user">
                  <Group gap={8} wrap="nowrap">
                    <Avatar size={26} radius="xl" color="gray" variant="filled">
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

      <AppShell.Navbar py="sm" px={0} className="mo-navbar">
        <ScrollArea style={{ flex: 1 }}>
          {nav('/', 'Accueil', <IconHome size={17} />)}
          <div className="mo-nav-section">Travailler</div>
          {nav('/donnees', 'Données', <IconTable size={17} />)}
          {nav('/graphiques', 'Graphiques', <IconChartBar size={17} />)}
          {nav('/cartographie', 'Cartographie', <IconMap2 size={17} />)}
          {nav('/statistiques', 'Statistiques', <IconMathFunction size={17} />)}
          {nav('/gestion', 'Gestion', <IconScale size={17} />)}
          <div className="mo-nav-section">Aide</div>
          {nav('/guide', 'Bonnes pratiques', <IconBook size={17} />)}
          {(isStructureAdmin || me?.is_superadmin) && (
            <>
              <div className="mo-nav-section">Réglages</div>
              {isStructureAdmin && nav('/structure', 'Charte de la structure', <IconPalette size={17} />)}
              {me?.is_superadmin && nav('/administration', 'Administration', <IconSettings size={17} />)}
            </>
          )}
        </ScrollArea>
        <Text size="xs" c="dimmed" px={14} py="sm" style={{ borderTop: '1px solid var(--mo-border)' }}>
          Moanui {meta?.version}
        </Text>
      </AppShell.Navbar>

      <AppShell.Main style={{ background: 'var(--mo-bg)' }}>{children}</AppShell.Main>
    </AppShell>
  );
}
