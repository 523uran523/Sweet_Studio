import { Workspace } from '../types/domain';

export const SUBSCRIPTION_PRICE_CENTS = 49900; // 499 ₽ / мес
export const TRIAL_DAYS = 14;
export const GRACE_DAYS = 7;

export type EffectiveSubscriptionStatus = 'trialing' | 'active' | 'grace' | 'expired';

export interface ResolvedSubscriptionState {
  effectiveStatus: EffectiveSubscriptionStatus;
  daysLeft: number;
  canWrite: boolean;
  canExport: boolean;
  expiresAt: string | null;
  graceEndsAt: string | null;
}

function addDays(isoDate: string, days: number): string {
  const base = new Date(`${isoDate.slice(0, 10)}T12:00:00Z`);
  if (Number.isNaN(base.getTime())) return isoDate.slice(0, 10);
  base.setUTCDate(base.getUTCDate() + days);
  return base.toISOString().slice(0, 10);
}

function diffDays(fromIso: string, toIso: string): number {
  const a = Date.parse(`${fromIso.slice(0, 10)}T00:00:00Z`);
  const b = Date.parse(`${toIso.slice(0, 10)}T00:00:00Z`);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return 0;
  return Math.ceil((b - a) / 86400000);
}

export function resolveSubscriptionState(
  workspace: Pick<
    Workspace,
    'plan' | 'subscriptionStatus' | 'trialEndsAt' | 'currentPeriodEnd' | 'graceEndsAt'
  >,
  nowIso: string = new Date().toISOString().slice(0, 10),
): ResolvedSubscriptionState {
  const today = nowIso.slice(0, 10);
  const rawEnd = workspace.currentPeriodEnd || workspace.trialEndsAt || null;

  // Legacy workspaces without subscription dates default to active trial
  if (!rawEnd) {
    return {
      effectiveStatus: workspace.subscriptionStatus === 'active' ? 'active' : 'trialing',
      daysLeft: TRIAL_DAYS,
      canWrite: true,
      canExport: true,
      expiresAt: addDays(today, TRIAL_DAYS),
      graceEndsAt: addDays(today, TRIAL_DAYS + GRACE_DAYS),
    };
  }

  const endDate = rawEnd.slice(0, 10);
  const graceDate = (workspace.graceEndsAt || addDays(endDate, GRACE_DAYS)).slice(0, 10);

  if (workspace.subscriptionStatus === 'expired' && today > graceDate) {
    return {
      effectiveStatus: 'expired',
      daysLeft: 0,
      canWrite: false,
      canExport: true,
      expiresAt: endDate,
      graceEndsAt: graceDate,
    };
  }

  if (today <= endDate) {
    return {
      effectiveStatus: workspace.plan === 'pro' || workspace.subscriptionStatus === 'active' ? 'active' : 'trialing',
      daysLeft: Math.max(0, diffDays(today, endDate)),
      canWrite: true,
      canExport: true,
      expiresAt: endDate,
      graceEndsAt: graceDate,
    };
  }

  if (today <= graceDate) {
    return {
      effectiveStatus: 'grace',
      daysLeft: Math.max(0, diffDays(today, graceDate)),
      canWrite: true,
      canExport: true,
      expiresAt: endDate,
      graceEndsAt: graceDate,
    };
  }

  return {
    effectiveStatus: 'expired',
    daysLeft: 0,
    canWrite: false,
    canExport: true,
    expiresAt: endDate,
    graceEndsAt: graceDate,
  };
}

export function computeNextBillingDates(
  currentEndIso?: string | null,
  months = 1,
  nowIso: string = new Date().toISOString().slice(0, 10),
): { currentPeriodEnd: string; graceEndsAt: string } {
  const today = nowIso.slice(0, 10);
  const anchor = currentEndIso && currentEndIso.slice(0, 10) > today ? currentEndIso.slice(0, 10) : today;
  const dt = new Date(`${anchor}T12:00:00Z`);
  dt.setUTCMonth(dt.getUTCMonth() + Math.max(1, months));
  const nextEnd = dt.toISOString().slice(0, 10);
  return {
    currentPeriodEnd: nextEnd,
    graceEndsAt: addDays(nextEnd, GRACE_DAYS),
  };
}
