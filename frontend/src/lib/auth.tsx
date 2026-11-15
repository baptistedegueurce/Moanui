import { createContext, ReactNode, useCallback, useContext, useEffect, useState } from 'react';
import { api } from './api';
import { memoClear, memoScope } from './memo';
import type { Me, Meta, Structure } from './types';

interface AuthState {
  me: Me | null;
  meta: Meta | null;
  loading: boolean;
  needsSetup: boolean;
  structure: Structure | null;
  refresh: () => Promise<void>;
  switchStructure: (id: string) => Promise<void>;
  logout: () => Promise<void>;
  canWrite: boolean;
  isStructureAdmin: boolean;
}

const Ctx = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [meta, setMeta] = useState<Meta | null>(null);
  const [loading, setLoading] = useState(true);
  const [needsSetup, setNeedsSetup] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const s = await api.get<{ needs_setup: boolean }>('/api/setup/status');
      setNeedsSetup(s.needs_setup);
      if (s.needs_setup) {
        setMe(null);
        return;
      }
      const m = await api.get<Me>('/api/auth/me');
      setMe(m);
      if (!meta) setMeta(await api.get<Meta>('/api/meta'));
    } catch {
      setMe(null);
    } finally {
      setLoading(false);
    }
  }, [meta]);

  useEffect(() => {
    refresh();
    const onLogout = () => {
      memoClear();
      setMe(null);
    };
    window.addEventListener('moanui:logout', onLogout);
    return () => window.removeEventListener('moanui:logout', onLogout);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const structure = me?.structures.find((s) => s.id === me.active_structure_id) || me?.structures[0] || null;
  memoScope(me?.id, structure?.id);

  const value: AuthState = {
    me,
    meta,
    loading,
    needsSetup,
    structure,
    refresh,
    switchStructure: async (id) => {
      await api.post('/api/auth/active-structure', { structure_id: id });
      await refresh();
    },
    logout: async () => {
      await api.post('/api/auth/logout');
      memoClear();
      setMe(null);
    },
    canWrite: !!structure && (structure.role === 'admin' || structure.role === 'analyste'),
    isStructureAdmin: !!structure && structure.role === 'admin',
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAuth(): AuthState {
  const v = useContext(Ctx);
  if (!v) throw new Error('AuthProvider manquant');
  return v;
}
