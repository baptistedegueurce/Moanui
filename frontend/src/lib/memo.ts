// Mémoire de travail de l'interface (en mémoire uniquement, jamais dans le stockage du navigateur : les données
// de navires restent cloisonnées). Permet de quitter une page et d'y revenir sans perdre son travail.
// Vidée à la déconnexion et au changement de structure.

type Bucket = { values: Map<string, any>; cache: Map<string, any> };
let owner = '';
let bucket: Bucket = { values: new Map(), cache: new Map() };
const MAX_CACHE = 60;

/** Associe la mémoire à l'utilisateur et à sa structure active ; tout est oublié si l'un change. */
export function memoScope(userId: string | undefined, structureId: string | undefined): void {
  const key = `${userId || ''}/${structureId || ''}`;
  if (key !== owner) {
    owner = key;
    bucket = { values: new Map(), cache: new Map() };
  }
}

export function memoClear(): void {
  owner = '';
  bucket = { values: new Map(), cache: new Map() };
}

export function remember<T>(key: string, value: T): void {
  bucket.values.set(key, value);
}

export function recall<T>(key: string): T | undefined {
  return bucket.values.get(key);
}

/** Petit cache LRU de réponses (ex. données d'un graphique). */
export function cacheGet<T>(key: string): T | undefined {
  const v = bucket.cache.get(key);
  if (v !== undefined) {
    bucket.cache.delete(key);
    bucket.cache.set(key, v);
  }
  return v;
}

export function cacheSet(key: string, value: any): void {
  bucket.cache.delete(key);
  bucket.cache.set(key, value);
  while (bucket.cache.size > MAX_CACHE) bucket.cache.delete(bucket.cache.keys().next().value as string);
}
