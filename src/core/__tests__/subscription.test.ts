import { describe, expect, it } from 'vitest';
import {
  computeNextBillingDates,
  resolveSubscriptionState,
  SUBSCRIPTION_PRICE_CENTS,
} from '../subscription';

describe('subscription', () => {
  it('resolves trialing -> active -> grace -> expired transitions', () => {
    expect(SUBSCRIPTION_PRICE_CENTS).toBe(49900);

    const trialing = resolveSubscriptionState(
      {
        plan: 'trial',
        subscriptionStatus: 'trialing',
        trialEndsAt: '2026-11-20',
        graceEndsAt: '2026-11-27',
      },
      '2026-11-10',
    );
    expect(trialing.effectiveStatus).toBe('trialing');
    expect(trialing.daysLeft).toBe(10);
    expect(trialing.canWrite).toBe(true);
    expect(trialing.canExport).toBe(true);

    const active = resolveSubscriptionState(
      {
        plan: 'pro',
        subscriptionStatus: 'active',
        currentPeriodEnd: '2026-12-10',
        graceEndsAt: '2026-12-17',
      },
      '2026-11-10',
    );
    expect(active.effectiveStatus).toBe('active');
    expect(active.daysLeft).toBe(30);
    expect(active.canWrite).toBe(true);

    const grace = resolveSubscriptionState(
      {
        plan: 'pro',
        subscriptionStatus: 'active',
        currentPeriodEnd: '2026-11-05',
        graceEndsAt: '2026-11-12',
      },
      '2026-11-10',
    );
    expect(grace.effectiveStatus).toBe('grace');
    expect(grace.daysLeft).toBe(2);
    expect(grace.canWrite).toBe(true);
    expect(grace.canExport).toBe(true);

    const expired = resolveSubscriptionState(
      {
        plan: 'pro',
        subscriptionStatus: 'past_due',
        currentPeriodEnd: '2026-11-01',
        graceEndsAt: '2026-11-08',
      },
      '2026-11-10',
    );
    expect(expired.effectiveStatus).toBe('expired');
    expect(expired.daysLeft).toBe(0);
    expect(expired.canWrite).toBe(false);
    expect(expired.canExport).toBe(true);
  });

  it('defaults legacy workspaces without dates to writable trial', () => {
    const legacy = resolveSubscriptionState({}, '2026-11-10');
    expect(legacy.effectiveStatus).toBe('trialing');
    expect(legacy.canWrite).toBe(true);
    expect(legacy.canExport).toBe(true);
  });

  it('computes next billing dates with grace window', () => {
    const next = computeNextBillingDates('2026-11-15', 1, '2026-11-10');
    expect(next.currentPeriodEnd).toBe('2026-12-15');
    expect(next.graceEndsAt).toBe('2026-12-22');
  });
});
