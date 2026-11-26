import { describe, expect, it } from 'vitest';
import {
  computeCalculatorTotals,
  effectiveQuantity,
  netCashTotals,
  resourceLineTotalCents,
} from '../calculatorCore';
import { MoneyTransaction } from '../../types/domain';

describe('calculatorCore', () => {
  it('computes resource line totals across compatible units', () => {
    // 3 кг крема по 600 ₽/кг = 1800 ₽ (180 000 коп.)
    expect(
      resourceLineTotalCents({
        qty: 3,
        qtyUnit: 'кг',
        priceCents: 60000,
        priceUnit: 'за кг',
      }),
    ).toBe(180000);

    // 250 г по 240 ₽/100 г = 600 ₽ (60 000 коп.)
    expect(
      resourceLineTotalCents({
        qty: 250,
        qtyUnit: 'г',
        priceCents: 24000,
        priceUnit: 'за 100 г',
      }),
    ).toBe(60000);
  });

  it('computes markup pricing for cake cream golden example (1800 ₽ + 80% = 3240 ₽)', () => {
    const res = computeCalculatorTotals({
      materialsCents: 180000,
      laborHours: 0,
      laborRateCents: 0,
      otherCents: 0,
      overheadPercent: 0,
      marginPercent: 80,
      pricingMode: 'markup',
    });

    expect(res.validPrice).toBe(true);
    expect(res.costCents).toBe(180000);
    expect(res.priceCents).toBe(324000);
    expect(res.marginCents).toBe(144000);
  });

  it('computes targetMargin mode including acquiring fee shortfall guard', () => {
    const res = computeCalculatorTotals({
      materialsCents: 100000,
      laborHours: 2,
      laborRateCents: 50000,
      otherCents: 0,
      overheadPercent: 10,
      marginPercent: 0,
      pricingMode: 'targetMargin',
      targetMarginPercent: 30,
      acquiringPercent: 2.5,
      packagingCents: 15000,
    });

    expect(res.validPrice).toBe(true);
    // Target margin (30%) should be met or exceeded after fees
    const actualMarginPct = (res.marginCents / res.priceCents) * 100;
    expect(actualMarginPct).toBeGreaterThanOrEqual(29.99);
    expect(res.breakEvenCents).not.toBeNull();
    expect(res.priceCents).toBeGreaterThan(res.breakEvenCents!);
    expect(res.roiPercent).toBeGreaterThan(0);
  });

  it('handles fixedPrice, defect rate, and partial buyout return shipping', () => {
    const res = computeCalculatorTotals({
      materialsCents: 100000,
      laborHours: 1,
      laborRateCents: 50000,
      otherCents: 0,
      overheadPercent: 0,
      marginPercent: 0,
      pricingMode: 'fixedPrice',
      fixedPriceCents: 300000,
      finishedDefectPercent: 10,
      shippingCents: 40000,
      returnShippingCents: 20000,
      buyoutPercent: 80,
    });

    expect(res.finishedDefectValid).toBe(true);
    expect(res.finishedDefectCents).toBeGreaterThan(0);
    expect(res.buyoutValid).toBe(true);
    // (40000 + 20000 * 0.2) / 0.8 = 44000 / 0.8 = 55000
    expect(res.effectiveShippingCents).toBe(55000);
    expect(res.priceCents).toBe(300000);
  });

  it('calculates effective gross quantity with technological loss %', () => {
    const gross = effectiveQuantity(900, 10);
    expect(gross).toBeCloseTo(1000, 6);
    expect(effectiveQuantity(100, 100)).toBeNull();
    expect(effectiveQuantity(-10, 5)).toBeNull();
  });

  it('aggregates netCashTotals with reversals and ignores transfers', () => {
    const txs: MoneyTransaction[] = [
      {
        id: 't1',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        kind: 'income',
        category: 'Заказы',
        amountCents: 500000,
        accountId: 'acc1',
        occurredAt: '2026-11-01',
      },
      {
        id: 't2',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        kind: 'expense',
        category: 'Сырьё',
        amountCents: 150000,
        accountId: 'acc1',
        occurredAt: '2026-11-02',
      },
      {
        id: 't3',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        kind: 'reversal',
        category: 'Сторно',
        amountCents: 150000,
        accountId: 'acc1',
        occurredAt: '2026-11-02',
        reversesId: 't2',
      },
      {
        id: 't4',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        kind: 'transfer',
        category: 'Перевод',
        amountCents: 100000,
        accountId: 'acc1',
        occurredAt: '2026-11-03',
      },
    ];

    const summary = netCashTotals(txs);
    expect(summary.incomeCents).toBe(500000);
    expect(summary.expenseCents).toBe(0);
    expect(summary.netCents).toBe(500000);
    expect(summary.reversedIds.has('t2')).toBe(true);
  });
});
