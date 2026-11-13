import { notifications } from '@mantine/notifications';

export const ok = (message: string, title?: string) => notifications.show({ color: 'teal', title, message });
export const fail = (e: any, title = 'Erreur') =>
  notifications.show({ color: 'red', title, message: e?.message || String(e), autoClose: 9000 });
export const info = (message: string, title?: string) => notifications.show({ color: 'blue', title, message });
