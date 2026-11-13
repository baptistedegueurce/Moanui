// Client HTTP : toutes les erreurs remontent avec un message en français.

export class ApiError extends Error {
  status: number;
  detail: any;
  constructor(status: number, message: string, detail?: any) {
    super(message);
    this.status = status;
    this.detail = detail;
  }
}

async function handle<T>(res: Response): Promise<T> {
  if (res.ok) {
    const ct = res.headers.get('content-type') || '';
    if (ct.includes('application/json')) return res.json();
    return (await res.text()) as unknown as T;
  }
  let detail: any = null;
  try {
    detail = (await res.json()).detail;
  } catch {
    /* réponse non JSON */
  }
  const msg = typeof detail === 'string' ? detail : detail?.message || `Erreur ${res.status}`;
  if (res.status === 401 && !location.pathname.startsWith('/connexion') && !location.pathname.startsWith('/installation')) {
    window.dispatchEvent(new Event('moanui:logout'));
  }
  throw new ApiError(res.status, msg, detail);
}

export const api = {
  get: <T = any>(url: string) => fetch(url, { credentials: 'same-origin' }).then((r) => handle<T>(r)),
  post: <T = any>(url: string, body?: any) =>
    fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    }).then((r) => handle<T>(r)),
  patch: <T = any>(url: string, body: any) =>
    fetch(url, {
      method: 'PATCH',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).then((r) => handle<T>(r)),
  put: <T = any>(url: string, body: any) =>
    fetch(url, {
      method: 'PUT',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }).then((r) => handle<T>(r)),
  del: <T = any>(url: string) => fetch(url, { method: 'DELETE', credentials: 'same-origin' }).then((r) => handle<T>(r)),
  upload: <T = any>(url: string, form: FormData) =>
    fetch(url, { method: 'POST', credentials: 'same-origin', body: form }).then((r) => handle<T>(r)),
};

/** Télécharge une URL de l'API en fichier ; renvoie l'erreur éventuelle (ex. 409 données sensibles). */
export async function download(url: string, fallbackName = 'export'): Promise<void> {
  const res = await fetch(url, { credentials: 'same-origin' });
  if (!res.ok) await handle(res);
  const blob = await res.blob();
  const cd = res.headers.get('content-disposition') || '';
  const m = /filename="([^"]+)"/.exec(cd);
  saveBlob(blob, m ? m[1] : fallbackName);
}

export function saveBlob(blob: Blob, name: string) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => {
    URL.revokeObjectURL(a.href);
    a.remove();
  }, 1000);
}

export function saveText(text: string, name: string, type = 'text/markdown;charset=utf-8') {
  saveBlob(new Blob([text], { type }), name);
}
