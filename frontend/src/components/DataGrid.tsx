// Tableau de données : lecture paginée côté serveur (millions de lignes possibles),
// tri, recherche, correction de cellules par double-clic (en attente jusqu'à enregistrement).
import { forwardRef, useCallback, useEffect, useImperativeHandle, useMemo, useRef } from 'react';
import { AgGridReact } from 'ag-grid-react';
import { AllCommunityModule, ModuleRegistry, themeQuartz, type ColDef, type IDatasource, type GridApi } from 'ag-grid-community';
import { api } from '../lib/api';
import { fmtCell, isNumericType, typeLabel, typeTag } from '../lib/format';
import type { Column } from '../lib/types';

ModuleRegistry.registerModules([AllCommunityModule]);

export interface PendingEdit {
  row: number;
  column: string;
  value: any;
  old: any;
}

export interface GridHandle {
  refresh: () => void;
}

interface Props {
  datasetId: string;
  columns: Column[];
  search: string;
  filters: any[];
  editable: boolean;
  pending: PendingEdit[];
  onEdit: (e: PendingEdit) => void;
  onHeaderClick: (col: string) => void;
  selected?: string[];
  onTotal: (n: number) => void;
  upto?: number | null;
}

const gridTheme = themeQuartz.withParams({
  fontSize: 13,
  headerFontWeight: 600,
  rowHeight: 30,
  headerHeight: 40,
  spacing: 6,
  accentColor: 'var(--mo-accent)',
  headerBackgroundColor: 'var(--mo-bg)',
  borderColor: 'var(--mo-border)',
});

/** En-tête : clic sur le nom = sélection de la colonne ; flèche = tri. */
function Header(props: any) {
  const { displayName, colName, type, selected, onSelect, column, progressSort } = props;
  const sort = column.getSort?.();
  const tg = type ? typeTag(type) : null;
  return (
    <div className="mo-hdr" data-sel={selected || undefined}>
      <span className="mo-hdr-name" onClick={() => colName && onSelect?.(colName)} title={colName ? 'Sélectionner la colonne' : undefined}>
        {displayName}
      </span>
      {tg && <span className={`mo-type mo-type-${tg.cls}`}>{tg.label}</span>}
      <button
        type="button"
        className="mo-hdr-sort"
        data-on={sort || undefined}
        aria-label={`Trier par ${displayName}`}
        title="Trier (Maj + clic : tri sur plusieurs colonnes)"
        onClick={(e) => progressSort?.(e.shiftKey)}
      >
        {sort === 'asc' ? '▲' : sort === 'desc' ? '▼' : '↕'}
      </button>
    </div>
  );
}

const DataGrid = forwardRef<GridHandle, Props>(function DataGrid(p, ref) {
  const gridApi = useRef<GridApi | null>(null);
  const pendingRef = useRef(p.pending);
  pendingRef.current = p.pending;
  const propsRef = useRef(p);
  propsRef.current = p;

  const hasRowId = p.columns.some((c) => c.name === '__ligne');

  const colDefs = useMemo<ColDef[]>(
    () =>
      p.columns.map((c, i) => {
        const tech = c.name === '__ligne';
        return {
          field: `c${i}`,
          headerName: tech ? 'n°' : c.name,
          headerTooltip: tech ? 'Numéro de la ligne dans le fichier d’origine' : `${c.name} · ${typeLabel(c.type)}`,
          headerComponent: Header,
          pinned: tech ? 'left' : undefined,
          width: tech ? 92 : Math.min(300, Math.max(130, c.name.length * 8 + 78)),
          sortable: true,
          cellDataType: false, // éditeur texte simple : la conversion est faite côté serveur selon le type
          editable: !tech && p.editable && hasRowId,
          cellClass: (params: any) => {
            const row = params.data?.c_row;
            const edited = pendingRef.current.some((e) => e.row === row && e.column === c.name);
            const sel = propsRef.current.selected?.includes(c.name);
            return [tech ? 'mo-tech' : '', edited ? 'mo-cell-edited' : '', sel ? 'mo-col-sel' : ''].join(' ');
          },
          type: isNumericType(c.type) ? 'rightAligned' : undefined,
          valueFormatter: (params: any) =>
            params.value === null || params.value === undefined ? '' : !tech && typeof params.value === 'number' ? fmtCell(params.value) : String(params.value),
          headerComponentParams: tech ? {} : { colName: c.name, type: c.type, selected: p.selected?.includes(c.name), onSelect: p.onHeaderClick },
        } as ColDef;
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [p.columns, p.editable, hasRowId, p.selected],
  );

  const datasource: IDatasource = useMemo(
    () => ({
      getRows: async (params) => {
        const cur = propsRef.current;
        const sort = params.sortModel.map((s) => ({ column: cur.columns[Number(s.colId.slice(1))]?.name, desc: s.sort === 'desc' }));
        try {
          const res = await api.post(`/api/datasets/${cur.datasetId}/rows`, {
            offset: params.startRow,
            limit: params.endRow - params.startRow,
            sort,
            search: cur.search || null,
            filters: cur.filters,
            upto: cur.upto ?? null,
          });
          const rowIdx = res.columns.findIndex((c: Column) => c.name === '__ligne');
          const rows = res.rows.map((r: any[]) => {
            const o: any = {};
            r.forEach((v, i) => (o[`c${i}`] = v));
            o.c_row = rowIdx >= 0 ? r[rowIdx] : null;
            // réapplique les corrections en attente
            for (const e of pendingRef.current) {
              if (e.row === o.c_row) {
                const j = res.columns.findIndex((c: Column) => c.name === e.column);
                if (j >= 0) o[`c${j}`] = e.value;
              }
            }
            return o;
          });
          cur.onTotal(res.total);
          params.successCallback(rows, res.total);
        } catch {
          params.failCallback();
        }
      },
    }),
    [],
  );

  useEffect(() => {
    gridApi.current?.refreshCells({ force: true });
  }, [p.selected]);

  const refresh = useCallback(() => {
    gridApi.current?.purgeInfiniteCache();
  }, []);
  useImperativeHandle(ref, () => ({ refresh }), [refresh]);

  return (
    <div className="mo-grid-wrap">
      <AgGridReact
        theme={gridTheme}
        columnDefs={colDefs}
        rowModelType="infinite"
        datasource={datasource}
        cacheBlockSize={200}
        maxBlocksInCache={50}
        onGridReady={(e) => (gridApi.current = e.api)}
        onCellValueChanged={(e) => {
          const col = p.columns[Number(e.colDef.field!.slice(1))];
          if (!col || e.oldValue === e.newValue || e.data?.c_row == null) return; // ligne pas encore chargée
          p.onEdit({ row: e.data.c_row, column: col.name, value: e.newValue === '' ? null : e.newValue, old: e.oldValue });
        }}
        stopEditingWhenCellsLoseFocus
        singleClickEdit={false}
        overlayNoRowsTemplate="<span>Aucune ligne</span>"
        localeText={{ loadingOoo: 'Chargement…', noRowsToShow: 'Aucune ligne' }}
      />
    </div>
  );
});

export default DataGrid;
