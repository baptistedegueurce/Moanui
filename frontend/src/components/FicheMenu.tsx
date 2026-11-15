import { Button, Menu } from '@mantine/core';
import { IconFileText, IconFileTypePdf, IconFileTypeDocx, IconFileZip } from '@tabler/icons-react';
import { fail } from '../lib/notify';

export type FicheFormat = 'pdf' | 'docx' | 'zip';

/** Bouton « Fiche méthode » : PDF, Word ou archive (Markdown + HTML + figures SVG). */
export default function FicheMenu({ onExport, label = 'Fiche méthode', size = 'xs', disabled }: {
  onExport: (fmt: FicheFormat) => Promise<unknown>;
  label?: string;
  size?: 'xs' | 'sm';
  disabled?: boolean;
}) {
  const go = (fmt: FicheFormat) => onExport(fmt).catch(fail);
  return (
    <Menu position="bottom-end" withinPortal>
      <Menu.Target>
        <Button size={size} variant="default" leftSection={<IconFileText size={16} />} disabled={disabled}>
          {label}
        </Button>
      </Menu.Target>
      <Menu.Dropdown>
        <Menu.Item leftSection={<IconFileTypePdf size={16} />} onClick={() => go('pdf')}>
          PDF (à diffuser, imprimer)
        </Menu.Item>
        <Menu.Item leftSection={<IconFileTypeDocx size={16} />} onClick={() => go('docx')}>
          Word (modifiable)
        </Menu.Item>
        <Menu.Item leftSection={<IconFileZip size={16} />} onClick={() => go('zip')}>
          Archive : Markdown, HTML et figures SVG
        </Menu.Item>
      </Menu.Dropdown>
    </Menu>
  );
}
