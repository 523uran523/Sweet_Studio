import { CashShift, Coupon, InventoryItem, PosSaleLine, Recipe, StockLot } from '../types/domain';

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
  if (coupon.clientId && coupon.clientId !== clientId) {
    return {
      valid: false,
      discountCents: 0,
      reason: clientId
        ? `Купон привязан к другому клиенту (${coupon.clientName || 'клиент'})`
        : `Выберите клиента (${coupon.clientName || 'владельца'}) для личного купона`,
    };
  }
  const discountCents =
    coupon.discountType === 'percent'
      ? Math.round((subtotalCents * Math.max(0, Math.min(100, coupon.discountValue))) / 100)
      : Math.min(subtotalCents, Math.max(0, coupon.discountValue));
  return { valid: true, discountCents };
}

export type PosScanResolution =
  | { kind: 'coupon'; coupon: Coupon; matchedCode: string }
  | { kind: 'inventory'; item: InventoryItem; matchedLot?: StockLot }
  | { kind: 'recipe'; recipe: Recipe }
  | { kind: 'unknown'; code: string };

function findCouponByCode(coupons: Coupon[], candidateUpper: string): Coupon | undefined {
  const matches = coupons.filter((c) => c.code.trim().toUpperCase() === candidateUpper);
  if (matches.length === 0) return undefined;
  return matches.find((c) => c.status === 'active') || matches[0];
}

export function resolvePosScannedCode(params: {
  rawCode: string;
  coupons: Coupon[];
  inventoryItems: InventoryItem[];
  stockLots: StockLot[];
  recipes: Recipe[];
}): PosScanResolution {
  const raw = params.rawCode.trim();
  if (!raw) return { kind: 'unknown', code: '' };

  const upper = raw.toUpperCase();
  const lower = raw.toLowerCase();

  // Structured QR prefixes: SWEETSTUDIO:<TYPE>:<VALUE>
  if (upper.startsWith('SWEETSTUDIO:COUPON:')) {
    const val = raw.slice('SWEETSTUDIO:COUPON:'.length).trim();
    const coupon =
      findCouponByCode(params.coupons, val.toUpperCase()) ||
      params.coupons.find((c) => c.id === val);
    if (coupon) return { kind: 'coupon', coupon, matchedCode: coupon.code };
    return { kind: 'unknown', code: raw };
  }

  if (upper.startsWith('SWEETSTUDIO:ITEM:')) {
    const val = raw.slice('SWEETSTUDIO:ITEM:'.length).trim();
    const valLower = val.toLowerCase();
    const item = params.inventoryItems.find(
      (i) => i.id === val || i.name.trim().toLowerCase() === valLower,
    );
    if (item) return { kind: 'inventory', item };
    return { kind: 'unknown', code: raw };
  }

  if (upper.startsWith('SWEETSTUDIO:LOT:')) {
    const val = raw.slice('SWEETSTUDIO:LOT:'.length).trim();
    const valUpper = val.toUpperCase();
    const lot =
      params.stockLots.find((l) => l.status === 'active' && l.lotCode.trim().toUpperCase() === valUpper) ||
      params.stockLots.find((l) => l.lotCode.trim().toUpperCase() === valUpper || l.id === val);
    if (lot) {
      const item = params.inventoryItems.find((i) => i.id === lot.itemId);
      if (item) return { kind: 'inventory', item, matchedLot: lot };
    }
    return { kind: 'unknown', code: raw };
  }

  if (upper.startsWith('SWEETSTUDIO:RECIPE:')) {
    const val = raw.slice('SWEETSTUDIO:RECIPE:'.length).trim();
    const valLower = val.toLowerCase();
    const recipe = params.recipes.find(
      (r) =>
        r.status !== 'archived' &&
        (r.id === val || r.title.trim().toLowerCase() === valLower),
    );
    if (recipe) return { kind: 'recipe', recipe };
    return { kind: 'unknown', code: raw };
  }

  // Legacy workspace-prefixed coupon QR format: "<WorkspaceName>:<CouponCode>"
  if (raw.includes(':')) {
    const suffix = raw.slice(raw.lastIndexOf(':') + 1).trim().toUpperCase();
    if (suffix) {
      const prefixedCoupon = findCouponByCode(params.coupons, suffix);
      if (prefixedCoupon) {
        return { kind: 'coupon', coupon: prefixedCoupon, matchedCode: prefixedCoupon.code };
      }
    }
  }

  // 1. Direct Coupon code match
  const directCoupon = findCouponByCode(params.coupons, upper);
  if (directCoupon) {
    return { kind: 'coupon', coupon: directCoupon, matchedCode: directCoupon.code };
  }

  // 2. StockLot lotCode or id match -> resolves to its InventoryItem
  const matchedLot =
    params.stockLots.find((l) => l.status === 'active' && l.lotCode.trim().toUpperCase() === upper) ||
    params.stockLots.find((l) => l.lotCode.trim().toUpperCase() === upper || l.id === raw);
  if (matchedLot) {
    const lotItem = params.inventoryItems.find((i) => i.id === matchedLot.itemId);
    if (lotItem) {
      return { kind: 'inventory', item: lotItem, matchedLot };
    }
  }

  // 3. InventoryItem id or exact name
  const directItem = params.inventoryItems.find(
    (i) => i.id === raw || i.name.trim().toLowerCase() === lower,
  );
  if (directItem) {
    return { kind: 'inventory', item: directItem };
  }

  // 4. Non-archived Recipe id or exact title
  const directRecipe = params.recipes.find(
    (r) =>
      r.status !== 'archived' &&
      (r.id === raw || r.title.trim().toLowerCase() === lower),
  );
  if (directRecipe) {
    return { kind: 'recipe', recipe: directRecipe };
  }

  return { kind: 'unknown', code: raw };
}

