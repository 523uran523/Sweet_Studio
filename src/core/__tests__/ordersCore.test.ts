import { describe, expect, it } from 'vitest';
import {
  attributeOrderToRecipes,
  buildOrderSummaryTitle,
  computeOrderItemsTotals,
  getOrderItemsNormalized,
  summarizeOrderItems,
} from '../ordersCore';
import { Order, OrderItem, Recipe } from '../../types/domain';

const sampleRecipes: Recipe[] = [
  {
    id: 'rec_cake',
    workspaceId: 'ws1',
    ownerId: 'u1',
    title: 'Медовик ягодный',
    category: 'Торты',
    version: 1,
    status: 'approved',
    yieldGrams: 1500,
    laborHours: 2,
    costCents: 110000,
    recommendedPriceCents: 350000,
  },
  {
    id: 'rec_cup',
    workspaceId: 'ws1',
    ownerId: 'u1',
    title: 'Ванильные капкейки',
    category: 'Капкейки',
    version: 1,
    status: 'approved',
    yieldGrams: 480,
    laborHours: 1,
    costCents: 45000,
    recommendedPriceCents: 120000,
  },
];

describe('ordersCore multi-item calculations', () => {
  it('falls back to legacy single-recipe order fields when items array is absent', () => {
    const legacyOrder: Order = {
      id: 'ord_legacy',
      workspaceId: 'ws1',
      ownerId: 'u1',
      orderNumber: '№101',
      title: 'Медовик ягодный',
      clientName: 'Анна',
      recipeId: 'rec_cake',
      recipeTitle: 'Медовик ягодный',
      weightGrams: 2000,
      priceCents: 420000,
      costCents: 140000,
      paidCents: 200000,
      status: 'confirmed',
    };

    const normalized = getOrderItemsNormalized(legacyOrder);
    expect(normalized).toHaveLength(1);
    expect(normalized[0]).toMatchObject({
      recipeId: 'rec_cake',
      recipeTitle: 'Медовик ягодный',
      qty: 1,
      weightGrams: 2000,
      priceCents: 420000,
      costCents: 140000,
    });

    const summary = summarizeOrderItems(legacyOrder);
    expect(summary.count).toBe(1);
    expect(summary.totalWeightGrams).toBe(2000);
    expect(summary.summaryText).toContain('Медовик ягодный');
    expect(summary.summaryText).toContain('2000 г');
  });

  it('computes totals and summary across multi-item order', () => {
    const items: OrderItem[] = [
      {
        id: 'i1',
        recipeId: 'rec_cake',
        recipeTitle: 'Медовик ягодный',
        qty: 1,
        weightGrams: 1500,
        priceCents: 350000,
        costCents: 110000,
      },
      {
        id: 'i2',
        recipeId: 'rec_cup',
        recipeTitle: 'Ванильные капкейки',
        qty: 2,
        weightGrams: 480,
        priceCents: 120000,
        costCents: 45000,
      },
    ];

    const totals = computeOrderItemsTotals(items);
    expect(totals.totalWeightGrams).toBe(1500 + 2 * 480);
    expect(totals.basePriceCents).toBe(350000 + 2 * 120000);
    expect(totals.baseCostCents).toBe(110000 + 2 * 45000);

    expect(buildOrderSummaryTitle(items)).toBe(
      'Медовик ягодный + Ванильные капкейки ×2',
    );

    const summary = summarizeOrderItems({
      id: 'ord_multi',
      title: 'Набор',
      items,
      weightGrams: totals.totalWeightGrams,
      priceCents: totals.basePriceCents,
      costCents: totals.baseCostCents,
    });
    expect(summary.count).toBe(3);
    expect(summary.totalWeightGrams).toBe(2460);
    expect(summary.summaryText).toContain('2 поз.');
  });

  it('attributes discounted multi-item revenue proportionally without rounding drift', () => {
    const items: OrderItem[] = [
      {
        id: 'i1',
        recipeId: 'rec_cake',
        recipeTitle: 'Медовик ягодный',
        qty: 1,
        weightGrams: 1500,
        priceCents: 300000,
        costCents: 100000,
      },
      {
        id: 'i2',
        recipeId: 'rec_cup',
        recipeTitle: 'Ванильные капкейки',
        qty: 2,
        weightGrams: 480,
        priceCents: 100000,
        costCents: 35000,
      },
    ];

    // Total gross = 300000 + 200000 = 500000; 10% coupon => priceCents = 450000
    const order: Order = {
      id: 'ord_disc',
      workspaceId: 'ws1',
      ownerId: 'u1',
      orderNumber: '№105',
      title: 'Медовик ягодный + Ванильные капкейки ×2',
      clientName: 'Елена',
      items,
      weightGrams: 2460,
      priceCents: 450000,
      costCents: 170000,
      paidCents: 450000,
      discountCents: 50000,
      status: 'delivered',
    };

    const attrs = attributeOrderToRecipes(order, sampleRecipes);
    expect(attrs).toHaveLength(2);
    expect(attrs[0]).toMatchObject({
      key: 'rec_cake',
      ordersCount: 1,
      revenueCents: 270000,
      costCents: 100000,
      laborHoursTotal: 2,
    });
    expect(attrs[1]).toMatchObject({
      key: 'rec_cup',
      ordersCount: 2,
      revenueCents: 180000,
      costCents: 70000,
      laborHoursTotal: 2,
    });
    expect(attrs[0].revenueCents + attrs[1].revenueCents).toBe(450000);
  });
});
