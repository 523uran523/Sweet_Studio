import { describe, expect, it } from 'vitest';
import {
  clearFormDraft,
  orderDraftKey,
  readFormDraft,
  recipeDraftKey,
  sanitizeDraftPhotoUrl,
  StorageLike,
  writeFormDraft,
} from '../../utils/draftStorage';

function createMemoryStorage(shouldThrow = false): StorageLike {
  const map = new Map<string, string>();
  return {
    getItem: (k) => map.get(k) ?? null,
    setItem: (k, v) => {
      if (shouldThrow) throw new Error('QuotaExceededError');
      map.set(k, v);
    },
    removeItem: (k) => {
      map.delete(k);
    },
  };
}

describe('draftStorage helpers', () => {
  it('writes, reads, and clears order and recipe drafts', () => {
    const store = createMemoryStorage();
    const key = orderDraftKey('ws_1');
    expect(recipeDraftKey('ws_1')).toBe('sweet_draft_recipe_ws_1');

    const saved = writeFormDraft(key, { title: 'Медовик', weight: 2000 }, store);
    expect(saved).not.toBeNull();

    const loaded = readFormDraft<{ title: string; weight: number }>(key, store);
    expect(loaded?.data.title).toBe('Медовик');
    expect(loaded?.data.weight).toBe(2000);

    clearFormDraft(key, store);
    expect(readFormDraft(key, store)).toBeNull();
  });

  it('handles storage quota errors safely and strips huge inline images', () => {
    const throwingStore = createMemoryStorage(true);
    expect(writeFormDraft('k', { a: 1 }, throwingStore)).toBeNull();

    const small = 'data:image/jpeg;base64,abc';
    expect(sanitizeDraftPhotoUrl(small)).toBe(small);

    const huge = `data:image/png;base64,${'A'.repeat(200_000)}`;
    expect(sanitizeDraftPhotoUrl(huge)).toBe('');
  });
});
