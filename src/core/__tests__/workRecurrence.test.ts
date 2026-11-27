import { describe, expect, it } from 'vitest';
import { computeNextDueDate, planNextRecurringWorkItem } from '../workRecurrence';
import { WorkItem } from '../../types/domain';

describe('workRecurrence scheduling and idempotency', () => {
  it('computes UTC-safe next due dates for daily, weekly, biweekly, and monthly', () => {
    expect(computeNextDueDate('2026-11-26', 'daily')).toBe('2026-11-27');
    expect(computeNextDueDate('2026-11-26', 'weekly')).toBe('2026-12-03');
    expect(computeNextDueDate('2026-11-26', 'biweekly')).toBe('2026-12-10');

    // End-of-month clamping: Jan 31 -> Feb 28 (non-leap) and Feb 29 (leap)
    expect(computeNextDueDate('2026-01-31', 'monthly')).toBe('2026-02-28');
    expect(computeNextDueDate('2024-01-31', 'monthly')).toBe('2024-02-29');
    expect(computeNextDueDate('2026-12-15', 'monthly')).toBe('2027-01-15');
  });

  it('plans next occurrence on completion and prevents duplicates in the same series', () => {
    const task: WorkItem = {
      id: 'wi_1',
      workspaceId: 'ws1',
      ownerId: 'u1',
      type: 'task',
      title: 'Ревизия молочной продукции',
      assigneeName: 'Мария',
      locationName: 'Основная кухня',
      dueDate: '2026-11-26',
      priority: 'high',
      stage: 'done',
      tags: ['склад'],
      recurrence: 'weekly',
    };

    const plan = planNextRecurringWorkItem(task, [task], '2026-11-26');
    expect(plan).not.toBeNull();
    expect(plan?.seriesId).toBe('wi_1');
    expect(plan?.currentIndex).toBe(1);
    expect(plan?.nextIndex).toBe(2);
    expect(plan?.nextDueDate).toBe('2026-12-03');
    expect(plan?.nextPayload).toMatchObject({
      title: 'Ревизия молочной продукции',
      dueDate: '2026-12-03',
      stage: 'queue',
      recurrence: 'weekly',
      seriesId: 'wi_1',
      occurrenceIndex: 2,
    });

    // If occurrence #2 already exists, planNextRecurringWorkItem must return null (idempotent)
    const duplicateGuard = planNextRecurringWorkItem(
      task,
      [
        task,
        {
          id: 'wi_2',
          workspaceId: 'ws1',
          ownerId: 'u1',
          ...plan!.nextPayload,
        },
      ],
      '2026-11-26',
    );
    expect(duplicateGuard).toBeNull();
  });

  it('returns null when recurrence is none or unset', () => {
    const oneOff: WorkItem = {
      id: 'wi_single',
      workspaceId: 'ws1',
      ownerId: 'u1',
      type: 'task',
      title: 'Разовое поручение',
      priority: 'normal',
      stage: 'done',
    };
    expect(planNextRecurringWorkItem(oneOff, [oneOff])).toBeNull();
  });
});
