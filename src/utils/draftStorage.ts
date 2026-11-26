export interface StoredDraftEnvelope<T> {
  data: T;
  savedAt: number;
}

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

function getDefaultStorage(): StorageLike | null {
  try {
    if (typeof window !== 'undefined' && window.localStorage) {
      return window.localStorage;
    }
  } catch {
    return null;
  }
  return null;
}

export function recipeDraftKey(workspaceId: string): string {
  return `sweet_draft_recipe_${workspaceId}`;
}

export function orderDraftKey(workspaceId: string): string {
  return `sweet_draft_order_${workspaceId}`;
}

export function sanitizeDraftPhotoUrl(photoUrl: string): string {
  if (!photoUrl) return '';
  if (photoUrl.startsWith('data:image/') && photoUrl.length > 180_000) {
    return '';
  }
  return photoUrl;
}

export function readFormDraft<T>(
  key: string,
  storage: StorageLike | null = getDefaultStorage(),
): StoredDraftEnvelope<T> | null {
  if (!storage || !key) return null;
  try {
    const raw = storage.getItem(key);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<StoredDraftEnvelope<T>>;
    if (!parsed || typeof parsed !== 'object' || parsed.data === undefined) {
      return null;
    }
    return {
      data: parsed.data,
      savedAt: typeof parsed.savedAt === 'number' ? parsed.savedAt : Date.now(),
    };
  } catch {
    return null;
  }
}

export function writeFormDraft<T>(
  key: string,
  data: T,
  storage: StorageLike | null = getDefaultStorage(),
): StoredDraftEnvelope<T> | null {
  if (!storage || !key) return null;
  const envelope: StoredDraftEnvelope<T> = {
    data,
    savedAt: Date.now(),
  };
  try {
    storage.setItem(key, JSON.stringify(envelope));
    return envelope;
  } catch {
    return null;
  }
}

export function clearFormDraft(
  key: string,
  storage: StorageLike | null = getDefaultStorage(),
): void {
  if (!storage || !key) return;
  try {
    storage.removeItem(key);
  } catch {
    // ignore storage errors
  }
}

export function formatDraftTimeRu(ts: number): string {
  try {
    return new Date(ts).toLocaleTimeString('ru-RU', {
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return '';
  }
}
