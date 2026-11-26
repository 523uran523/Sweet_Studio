import { CashShift, Coupon, PosSaleLine } from '../types/domain';

export function computeShiftExpectedCashCents(shift: Pick<
  CashShift,
  'openingCashCents' | 'cashSalesCents' | 'cashInCents' | 'cashOutCents' | 'refundsCents'
>): number {
  return (
    (shift.openingCashCents || 0) +
    (shift.cashSalesCents || 0) +
    (shift.cashInCents || 0) -
    (shift.cashOutCents || 0) -
    (shift.refundsCents || 0)
  );
}

export function computeShiftDiscrepancyCents(
  expectedCashCents: number,
  actualCashCents: number,
): number {
  return actualCashCents - expectedCashCents;
}

export function computePosCartTotals(
  lines: PosSaleLine[],
  discountCents: number,
): {
  subtotalCents: number;
  discountCents: number;
  totalCents: number;
  costCents: number;
} {
  const subtotalCents = lines.reduce(
    (sum, line) => sum + Math.round(line.qty * line.unitPriceCents),
    0,
  );
  const costCents = lines.reduce(
    (sum, line) => sum + Math.round(line.qty * line.unitCostCents),
    0,
  );
  const safeDiscount = Math.min(subtotalCents, Math.max(0, Math.round(discountCents)));
  return {
    subtotalCents,
    discountCents: safeDiscount,
    totalCents: Math.max(0, subtotalCents - safeDiscount),
    costCents,
  };
}

export function evaluateCouponForSale(params: {
  coupon: Coupon;
  subtotalCents: number;
  clientId?: string;
  todayIso: string;
}): { valid: boolean; discountCents: number; reason?: string } {
  const { coupon, subtotalCents, clientId, todayIso } = params;
  if (coupon.status !== 'active') {
    return { valid: false, discountCents: 0, reason: 'Купон уже погашен или деактивирован' };
  }
  if (coupon.expiresAt && coupon.expiresAt < todayIso) {
    return { valid: false, discountCents: 0, reason: 'Срок действия купона истёк' };
  }
  if (coupon.minOrderCents && subtotalCents < coupon.minOrderCents) {
    return {
      valid: false,
      discountCents: 0,
      reason: `Минимальная сумма чека для купона — ${Math.round(coupon.minOrderCents / 100)} ₽`,
    };
  }
  if (coupon.clientId && clientId && coupon.clientId !== clientId) {
    return {
      valid: false,
      discountCents: 0,
      reason: `Купон привязан к другому клиенту (${coupon.clientName || 'клиент'})`,
    };
  }
  const discountCents =
    coupon.discountType === 'percent'
      ? Math.round((subtotalCents * Math.max(0, Math.min(100, coupon.discountValue))) / 100)
      : Math.min(subtotalCents, Math.max(0, coupon.discountValue));
  return { valid: true, discountCents };
}
