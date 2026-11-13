export type Role = 'admin' | 'analyste' | 'lecteur';

export interface Theme {
  name: string;
  colors: Record<'primary' | 'primary_contrast' | 'accent' | 'background' | 'surface' | 'text' | 'muted' | 'border', string>;
  palette: string[];
  sequential: string[];
  diverging: string[];
  font: string;
  logo?: string | null;
  chart: { show_logo: boolean; logo_position: string; default_source: string; background: string; grid: string };
}

export interface Structure {
  id: string;
  name: string;
  short_name: string;
  kind: string;
  theme: Theme;
  has_logo: boolean;
  role?: Role;
}

export interface Me {
  id: string;
  username: string;
  display_name: string;
  is_superadmin: boolean;
  structures: Structure[];
  active_structure_id: string | null;
}

export interface Column {
  name: string;
  type: string;
}

export interface Step {
  id: string | null;
  index: number;
  type?: string;
  params?: any;
  description: string;
  status: 'ok' | 'erreur' | 'desactivee' | 'non_appliquee';
  enabled?: boolean;
  error?: string;
  comment?: string;
  author?: string;
  at?: string;
  n_rows?: number;
  added?: string[];
  removed?: string[];
}

export interface DatasetSummary {
  id: string;
  name: string;
  description: string;
  kind: string;
  structure_id: string;
  structure_name: string;
  source_name: string;
  n_rows_raw: number;
  n_steps: number;
  created_at: string;
  updated_at: string;
  mode: 'ecriture' | 'lecture';
  shared_from_other: boolean;
}

export interface ImportColumn {
  name: string;
  type: string;
  note: string;
  warning: null | { suggested_type: string; invalid_count: number; examples: any[]; message: string };
}

export interface Dataset extends DatasetSummary {
  notes: string;
  raw: { name: string; sha256: string; size_bytes: number; n_rows: number; imported_at: string; report: { format: string; options: any; columns: ImportColumn[] } };
  created_by: string;
  schema: Column[];
  steps: Step[];
  error: null | { step_id: string; index: number; message: string };
  sensitive: { column: string; kind: string }[];
  shares: { structure_id: string; name: string }[];
}

export interface Meta {
  version: string;
  steps: { type: string; label: string }[];
  operators: Record<string, string>;
  cast_types: Record<string, string>;
  join_kinds: Record<string, string>;
  functions: { name: string; doc: string }[];
}

export interface Warning {
  niveau: 'info' | 'attention' | 'alerte';
  colonne?: string;
  message: string;
}
