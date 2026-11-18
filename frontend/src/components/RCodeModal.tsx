import { useEffect, useState } from "react";
import {
  Alert,
  Button,
  Code,
  CopyButton,
  Group,
  Loader,
  Modal,
  ScrollArea,
  Stack,
  Text,
} from "@mantine/core";
import {
  IconCheck,
  IconCode,
  IconCopy,
  IconDownload,
} from "@tabler/icons-react";
import { api, downloadPost } from "../lib/api";
import { fail } from "../lib/notify";

/** « Code R équivalent » : le script affiché, à copier, ou à télécharger avec ses données. */
export default function RCodeModal({
  opened,
  onClose,
  url,
  body,
  zipName,
  what = "le graphique",
}: {
  opened: boolean;
  onClose: () => void;
  url: string; // POST -> { script, avertissements } ; `${url}.zip` -> archive
  body: any;
  zipName: string;
  what?: string;
}) {
  const [res, setRes] = useState<{
    script: string;
    avertissements: string[];
  } | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!opened) return;
    setRes(null);
    setErr(null);
    api
      .post(url, body)
      .then(setRes)
      .catch((e) => setErr(e?.message || String(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened]);

  return (
    <Modal
      opened={opened}
      onClose={onClose}
      title="Code R équivalent"
      size="xl"
    >
      <Stack gap="sm">
        <Text size="sm">
          Ce script refait {what} dans R (RStudio) à partir des données
          exportées avec lui. Téléchargez l’archive : elle contient le script et
          les données au format CSV, prêtes à l’emploi. Le code se lit et se
          modifie librement.
        </Text>
        {err && <Alert color="red">{err}</Alert>}
        {!res && !err && <Loader size="sm" />}
        {res && (
          <>
            {res.avertissements.length > 0 && (
              <Alert
                color="yellow"
                variant="light"
                p="xs"
                title="Ce qui diffère de l’appli"
              >
                {res.avertissements.map((a) => (
                  <Text size="xs" key={a}>
                    {a}
                  </Text>
                ))}
              </Alert>
            )}
            <ScrollArea h={420} type="auto">
              <Code block style={{ fontSize: 12, whiteSpace: "pre" }}>
                {res.script}
              </Code>
            </ScrollArea>
            <Group justify="flex-end" gap="xs">
              <CopyButton value={res.script}>
                {({ copied, copy }) => (
                  <Button
                    size="xs"
                    variant="default"
                    leftSection={
                      copied ? <IconCheck size={14} /> : <IconCopy size={14} />
                    }
                    onClick={copy}
                  >
                    {copied ? "Copié" : "Copier le code"}
                  </Button>
                )}
              </CopyButton>
              <Button
                size="xs"
                leftSection={<IconDownload size={14} />}
                onClick={() =>
                  downloadPost(`${url}.zip`, body, zipName).catch(fail)
                }
              >
                Télécharger le script et les données
              </Button>
            </Group>
          </>
        )}
      </Stack>
    </Modal>
  );
}

export const RIcon = IconCode;
