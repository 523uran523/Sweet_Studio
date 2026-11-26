import { Order, TimeEntry, WorkspaceMember } from '../types/domain';

/**
 * Ported from Masters lib/core/payroll_calc.dart & payroll_engine.dart.
 * Pure calculation in integer cents with deterministic rounding.
 */
export function hourlyAccrualCents(minutes: number, rateCents: number): number {
  if (minutes <= 0 || rateCents <= 0) return 0;
  return Math.round((minutes / 60) * rateCents);
}

export function percentAccrualCents(basisPriceCents: number, percent: number): number {
  if (basisPriceCents <= 0 || percent <= 0) return 0;
  return Math.round((basisPriceCents * percent) / 100);
}

export interface ComputedMemberPayroll {
  memberId: string;
  memberName: string;
  payType: string;
  minutes: number;
  ordersCount: number;
  amountCents: number;
  needsReview: boolean;
}

export function computeWorkspacePayrollPreview(params: {
  startDate: string;
  endDate: string;
  members: WorkspaceMember[];
  timeEntries: TimeEntry[];
  orders: Order[];
}): ComputedMemberPayroll[] {
  const { startDate, endDate, members, timeEntries, orders } = params;
  const startMs = Date.parse(`${startDate}T00:00:00Z`);
  const endMs = Date.parse(`${endDate}T23:59:59Z`);

  const inRange = (iso?: string): boolean => {
    if (!iso) return false;
    const ms = Date.parse(iso.length === 10 ? `${iso}T12:00:00Z` : iso);
    if (!Number.isFinite(ms)) return false;
    return ms >= startMs && ms <= endMs;
  };

  return members
    .filter((m) => m.active)
    .map((m) => {
      const memberEntries = timeEntries.filter(
        (t) =>
          (t.employeeId === m.id || t.employeeName === m.name) &&
          inRange(t.startedAt),
      );
      const memberOrders = orders.filter(
        (o) =>
          o.assigneeName === m.name &&
          (o.status === 'delivered' || o.status === 'closed' || o.status === 'ready') &&
          inRange(o.dueDate || new Date().toISOString().slice(0, 10)),
      );

      const totalMinutes = memberEntries.reduce((s, t) => s + (t.minutes || 0), 0);
      const rateCents = m.rateCents ?? 0;
      const pct = m.percent ?? 0;
      let amountCents = 0;

      if (m.payType === 'hourly' || m.payType === 'salary' || m.payType === 'mixed') {
        amountCents += hourlyAccrualCents(totalMinutes, rateCents);
      }
      if (m.payType === 'piece') {
        amountCents += memberOrders.length * rateCents;
      }
      if (m.payType === 'percent' || m.payType === 'mixed') {
        for (const o of memberOrders) {
          amountCents += percentAccrualCents(o.priceCents, pct);
        }
      }

      const needsReview =
        (m.payType === 'hourly' && rateCents === 0 && totalMinutes > 0) ||
        (m.payType === 'piece' && rateCents === 0 && memberOrders.length > 0) ||
        (m.payType === 'percent' && pct === 0 && memberOrders.length > 0);

      return {
        memberId: m.id,
        memberName: m.name,
        payType: m.payType,
        minutes: totalMinutes,
        ordersCount: memberOrders.length,
        amountCents,
        needsReview,
      };
    });
}
