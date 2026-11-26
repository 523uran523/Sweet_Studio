import { MoneyTransaction } from '../types/domain';
import { priceBaseOf, qtyBaseOf } from './units';

export type PricingMode = 'markup' | 'targetMargin' | 'fixedPrice';

export interface CalculatorTotals {
  materialsCents: number;
  laborCents: number;
  otherCents: number;
  overheadCents: number;
  costCents: number;
  priceCents: number;
  validPrice: boolean;
  productionCostCents: number;
  sellingCostCents: number;
  pieceworkCents: number;
  finishedDefectCents: number;
  finishedDefectValid: boolean;
  storageCents: number;
  returnShippingCents: number;
  buyoutPercent: number;
  effectiveShippingCents: number;
  buyoutValid: boolean;
  breakEvenCents: number | null;
  roiPercent: number | null;
  baseCents: number;
  marginCents: number;
}

export interface CalculatorInput {
  materialsCents: number;
  laborHours: number;
  laborRateCents: number;
  pieceworkCents?: number;
  otherCents: number;
  overheadPercent: number;
  overheadFixedCents?: number;
  marginPercent: number;
  pricingMode?: PricingMode;
  targetMarginPercent?: number;
  fixedPriceCents?: number;
  packagingCents?: number;
  shippingCents?: number;
  storageCents?: number;
  returnShippingCents?: number;
  buyoutPercent?: number;
  commissionPercent?: number;
  advertisingPercent?: number;
  acquiringPercent?: number;
  finishedDefectPercent?: number;
}

/**
 * Ported directly from Masters lib/features/jobs/calculator_core.dart.
 */
export function resourceLineTotalCents(params: {
  qty: number;
  qtyUnit: string;
  priceCents: number;
  priceUnit: string;
}): number {
  const { qty, qtyUnit, priceCents, priceUnit } = params;
  if (qty <= 0 || priceCents === 0) return 0;
  const priceBase = priceBaseOf(priceUnit);
  if (priceBase <= 0) return 0;
  const total = ((qty * qtyBaseOf(qtyUnit)) / priceBase) * priceCents;
  if (!Number.isFinite(total)) return 0;
  return Math.round(total);
}

/**
 * Gross quantity accounting for technological loss %: net / (1 - loss / 100).
 */
export function effectiveQuantity(qty: number, lossPercent: number): number | null {
  if (!Number.isFinite(qty) || qty < 0) return null;
  if (!Number.isFinite(lossPercent) || lossPercent < 0 || lossPercent >= 100) return null;
  const effective = (qty * 100) / (100 - lossPercent);
  return Number.isFinite(effective) ? effective : null;
}

export function computeCalculatorTotals(input: CalculatorInput): CalculatorTotals {
  const {
    materialsCents,
    laborHours,
    laborRateCents,
    pieceworkCents = 0,
    otherCents,
    overheadPercent,
    overheadFixedCents = 0,
    marginPercent,
    pricingMode = 'markup',
    targetMarginPercent = 30,
    fixedPriceCents = 0,
    packagingCents = 0,
    shippingCents = 0,
    storageCents = 0,
    returnShippingCents = 0,
    buyoutPercent = 100,
    commissionPercent = 0,
    advertisingPercent = 0,
    acquiringPercent = 0,
    finishedDefectPercent = 0,
  } = input;

  const hours = Number.isFinite(laborHours) && laborHours > 0 ? laborHours : 0;
  const rate = laborRateCents < 0 ? 0 : laborRateCents;
  const piecework = pieceworkCents < 0 ? 0 : pieceworkCents;
  const labor = Math.round(hours * rate) + piecework;
  const other = otherCents < 0 ? 0 : otherCents;
  const base = materialsCents + labor + other;

  const defectValid =
    Number.isFinite(finishedDefectPercent) &&
    finishedDefectPercent >= 0 &&
    finishedDefectPercent < 100;
  const defectCost =
    defectValid && finishedDefectPercent > 0
      ? Math.ceil(base / (1 - finishedDefectPercent / 100)) - base
      : 0;

  const overheadPct =
    Number.isFinite(overheadPercent) && overheadPercent > 0 ? overheadPercent : 0;
  const overheadFixed = overheadFixedCents < 0 ? 0 : overheadFixedCents;
  const overhead = Math.round((base * overheadPct) / 100) + overheadFixed;
  const productionCost = base + defectCost + overhead;

  const storage = storageCents < 0 ? 0 : storageCents;
  const returnCost = returnShippingCents < 0 ? 0 : returnShippingCents;
  const buyoutValid =
    Number.isFinite(buyoutPercent) && buyoutPercent > 0 && buyoutPercent <= 100;
  const buyoutRate = buyoutValid ? buyoutPercent / 100 : 1;
  const effectiveShippingRaw = buyoutValid
    ? ((shippingCents < 0 ? 0 : shippingCents) + returnCost * (1 - buyoutRate)) /
      buyoutRate
    : 0;
  const effectiveShipping = Number.isFinite(effectiveShippingRaw)
    ? Math.ceil(effectiveShippingRaw)
    : 0;

  const fixedCosts =
    (packagingCents < 0 ? 0 : packagingCents) + effectiveShipping + storage;
  const costsBeforeFees = productionCost + fixedCosts;

  const percentages = [commissionPercent, advertisingPercent, acquiringPercent];
  const validFees =
    percentages.every((v) => Number.isFinite(v) && v >= 0) &&
    percentages.reduce((sum, v) => sum + v, 0) < 100;
  const feeRate = validFees
    ? percentages.reduce((sum, v) => sum + v, 0) / 100
    : 0;

  const marginPct = Number.isFinite(marginPercent) ? marginPercent : 0;
  const validMargin =
    pricingMode !== 'targetMargin' ||
    (Number.isFinite(targetMarginPercent) &&
      targetMarginPercent >= 0 &&
      targetMarginPercent / 100 + feeRate < 1);

  const validPrice = validFees && validMargin && defectValid && buyoutValid;

  let raw = 0;
  if (pricingMode === 'markup') {
    raw = validFees
      ? Math.round((costsBeforeFees * (1 + marginPct / 100)) / (1 - feeRate))
      : 0;
  } else if (pricingMode === 'targetMargin') {
    raw = validPrice
      ? Math.ceil(costsBeforeFees / (1 - feeRate - targetMarginPercent / 100))
      : 0;
  } else {
    raw = fixedPriceCents;
  }

  let price = raw < 0 ? 0 : raw;
  if (pricingMode === 'targetMargin' && validPrice && feeRate > 0) {
    const fee = Math.round(price * feeRate);
    const shortfall =
      costsBeforeFees + fee + (price * targetMarginPercent) / 100 - price;
    if (shortfall > 0) {
      price += Math.ceil(
        (shortfall + 0.5) / (1 - feeRate - targetMarginPercent / 100),
      );
    }
  }

  const fees = Math.round(price * feeRate);
  const sellingCosts = fixedCosts + fees;
  const totalCost = productionCost + sellingCosts;
  const breakEvenCents =
    validPrice && feeRate < 1
      ? Math.ceil(costsBeforeFees / (1 - feeRate))
      : null;
  const roiPercent =
    validPrice && totalCost > 0
      ? ((price - totalCost) / totalCost) * 100
      : null;

  return {
    materialsCents,
    laborCents: labor,
    otherCents: other,
    overheadCents: overhead,
    costCents: totalCost,
    priceCents: price,
    validPrice,
    productionCostCents: productionCost,
    sellingCostCents: sellingCosts,
    pieceworkCents: piecework,
    finishedDefectCents: defectCost,
    finishedDefectValid: defectValid,
    storageCents: storage,
    returnShippingCents: returnCost,
    buyoutPercent,
    effectiveShippingCents: effectiveShipping,
    buyoutValid,
    breakEvenCents,
    roiPercent,
    baseCents: base,
    marginCents: price - totalCost,
  };
}

/**
 * Aggregate income & expense from MoneyTransactions while honoring reversal signs
 * against the original transaction's kind (reversing an expense decreases expenses;
 * reversing an income decreases income; transfers are neutral).
 */
export function netCashTotals(transactions: MoneyTransaction[]): {
  incomeCents: number;
  expenseCents: number;
  netCents: number;
  reversedIds: Set<string>;
} {
  const txMap = new Map<string, MoneyTransaction>();
  const reversedIds = new Set<string>();
  for (const t of transactions) {
    txMap.set(t.id, t);
    if (t.kind === 'reversal' && t.reversesId) {
      reversedIds.add(t.reversesId);
    }
  }

  let incomeCents = 0;
  let expenseCents = 0;
  for (const t of transactions) {
    if (t.kind === 'income') {
      incomeCents += t.amountCents;
    } else if (t.kind === 'expense') {
      expenseCents += t.amountCents;
    } else if (t.kind === 'reversal') {
      const orig = t.reversesId ? txMap.get(t.reversesId) : undefined;
      if (orig?.kind === 'expense') {
        expenseCents -= t.amountCents;
      } else {
        incomeCents -= t.amountCents;
      }
    }
  }

  return {
    incomeCents,
    expenseCents,
    netCents: incomeCents - expenseCents,
    reversedIds,
  };
}
