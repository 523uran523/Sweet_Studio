import { WorkItem, WorkRecurrence } from '../types/domain';

export const RECURRENCE_LABELS_RU: Record<WorkRecurrence, string> = {
  none: 'Без повтора',
  daily: 'Ежедневно',
  weekly: 'Еженедельно',
  biweekly: 'Раз в 2 недели',
  monthly: 'Ежемесячно',
};

function parseIsoParts(iso?: string): { y: number; m: number; d: number } | null {
  if (!iso || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return null;
  const [y, m, d] = iso.split('-').map(Number);
  if (!y || !m || !d) return null;
  return { y, m, d };
}

function formatUtcDate(dt: Date): string {
  const y = dt.getUTCFullYear();
  const m = String(dt.getUTCMonth() + 1).padStart(2, '0');
  const d = String(dt.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function computeNextDueDate(
  currentIso: string | undefined,
  recurrence: WorkRecurrence,
  fallbackTodayIso: string = new Date().toISOString().slice(0, 10),
): string {
  const baseParts = parseIsoParts(currentIso) || parseIsoParts(fallbackTodayIso) || {
    y: new Date().getUTCFullYear(),
    m: new Date().getUTCMonth() + 1,
    d: new Date().getUTCDate(),
  };

  if (recurrence === 'daily') {
    const dt = new Date(Date.UTC(baseParts.y, baseParts.m - 1, baseParts.d + 1));
    return formatUtcDate(dt);
  }
  if (recurrence === 'weekly') {
    const dt = new Date(Date.UTC(baseParts.y, baseParts.m - 1, baseParts.d + 7));
    return formatUtcDate(dt);
  }
  if (recurrence === 'biweekly') {
    const dt = new Date(Date.UTC(baseParts.y, baseParts.m - 1, baseParts.d + 14));
    return formatUtcDate(dt);
  }
  if (recurrence === 'monthly') {
    // Target month, clamping day-of-month to avoid spilling into following month (e.g. Jan 31 -> Feb 28)
    const targetMonthZeroBased = baseParts.m; // next month since m is 1-based
    const targetYear = baseParts.y + Math.floor(targetMonthZeroBased / 12);
    const normalizedMonth = targetMonthZeroBased % 12;
    const lastDayOfTargetMonth = new Date(
      Date.UTC(targetYear, normalizedMonth + 1, 0),
    ).getUTCDate();
    const clampedDay = Math.min(baseParts.d, lastDayOfTargetMonth);
    return formatUtcDate(new Date(Date.UTC(targetYear, normalizedMonth, clampedDay)));
  }

  return formatUtcDate(new Date(Date.UTC(baseParts.y, baseParts.m - 1, baseParts.d)));
}

export interface NextRecurringOccurrencePlan {
  seriesId: string;
  currentIndex: number;
  nextIndex: number;
  nextDueDate: string;
  nextPayload: {
    type: WorkItem['type'];
    sourceId?: string;
    title: string;
    assigneeName: string;
    locationName: string;
    dueDate: string;
    priority: WorkItem['priority'];
    stage: 'queue';
    tags: string[];
    recurrence: WorkRecurrence;
    seriesId: string;
    occurrenceIndex: number;
  };
}

/**
 * Computes the next WorkItem occurrence when a recurring task is completed,
 * enforcing idempotency by checking existing seriesId + occurrenceIndex in workItems.
 */
export function planNextRecurringWorkItem(
  completedItem: WorkItem,
  existingItems: WorkItem[],
  todayIso: string = new Date().toISOString().slice(0, 10),
): NextRecurringOccurrencePlan | null {
  const rec = completedItem.recurrence || 'none';
  if (rec === 'none') return null;

  const seriesId = completedItem.seriesId || completedItem.id;
  const currentIndex = completedItem.occurrenceIndex ?? 1;
  const nextIndex = currentIndex + 1;

  const alreadyExists = existingItems.some(
    (w) => (w.seriesId || w.id) === seriesId && (w.occurrenceIndex ?? 1) === nextIndex,
  );
  if (alreadyExists) return null;

  const nextDueDate = computeNextDueDate(completedItem.dueDate, rec, todayIso);
  const nextPayload: NextRecurringOccurrencePlan['nextPayload'] = {
    type: completedItem.type,
    title: completedItem.title.slice(0, 160),
    assigneeName: (completedItem.assigneeName || 'Владелец').slice(0, 120),
    locationName: (completedItem.locationName || 'Основная студия').slice(0, 120),
    dueDate: nextDueDate,
    priority: completedItem.priority,
    stage: 'queue',
    tags: Array.isArray(completedItem.tags) ? completedItem.tags.slice(0, 10) : [],
    recurrence: rec,
    seriesId,
    occurrenceIndex: nextIndex,
  };
  if (completedItem.sourceId) {
    nextPayload.sourceId = completedItem.sourceId;
  }

  return {
    seriesId,
    currentIndex,
    nextIndex,
    nextDueDate,
    nextPayload,
  };
}
