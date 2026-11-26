import { describe, expect, it } from 'vitest';
import { computeLocationBreakdown, matchesLocationFilter } from '../locations';
import { InventoryItem, LocationItem, Order, PosSale } from '../../types/domain';

const locations: LocationItem[] = [
  {
    id: 'loc_kitchen',
    workspaceId: 'ws1',
    ownerId: 'u1',
    name: 'Кухня-цех',
    kind: 'kitchen',
    isDefault: true,
  },
  {
    id: 'loc_store',
    workspaceId: 'ws1',
    ownerId: 'u1',
    name: 'Витрина Центр',
    kind: 'store',
  },
];

describe('locations filtering & breakdown', () => {
  it('matches items by locationId, fallback locationName, and assigns legacy empty location to default', () => {
    expect(
      matchesLocationFilter({
        entityLocationId: 'loc_store',
        activeLocationId: '',
        locations,
      }),
    ).toBe(true);

    expect(
      matchesLocationFilter({
        entityLocationId: 'loc_store',
        activeLocationId: 'loc_store',
        locations,
      }),
    ).toBe(true);

    expect(
      matchesLocationFilter({
        entityLocationId: 'loc_store',
        activeLocationId: 'loc_kitchen',
        locations,
      }),
    ).toBe(false);

    expect(
      matchesLocationFilter({
        entityLocationName: 'витрина центр',
        activeLocationId: 'loc_store',
        locations,
      }),
    ).toBe(true);

    // Legacy unassigned item belongs to default location, not secondary store
    expect(
      matchesLocationFilter({
        activeLocationId: 'loc_kitchen',
        locations,
      }),
    ).toBe(true);
    expect(
      matchesLocationFilter({
        activeLocationId: 'loc_store',
        locations,
      }),
    ).toBe(false);
  });

  it('computes revenue and inventory value breakdown across locations', () => {
    const orders: Order[] = [
      {
        id: 'o1',
        workspaceId: 'ws1',
        ownerId: 'u1',
        orderNumber: '№1',
        title: 'Медовик',
        clientName: 'Анна',
        priceCents: 300000,
        costCents: 120000,
        paidCents: 300000,
        items: [
          {
            id: 'item_o1',
            recipeId: 'rec1',
            recipeTitle: 'Медовик',
            qty: 1,
            weightGrams: 1500,
            priceCents: 300000,
            costCents: 120000,
          },
        ],
        status: 'delivered',
        locationName: 'Кухня-цех',
      },
    ];
    const posSales: PosSale[] = [
      {
        id: 'p1',
        workspaceId: 'ws1',
        ownerId: 'u1',
        receiptNumber: 'Ч-1001',
        locationId: 'loc_store',
        locationName: 'Витрина Центр',
        cashierName: 'Мария',
        paymentMethod: 'card',
        accountId: 'acc1',
        lines: [
          {
            id: 'l1',
            title: 'Эклер',
            qty: 2,
            unit: 'шт',
            unitPriceCents: 25000,
            unitCostCents: 10000,
          },
        ],
        subtotalCents: 50000,
        discountCents: 0,
        totalCents: 50000,
        costCents: 20000,
        status: 'completed',
        occurredAt: '2026-11-26T10:00:00Z',
      },
    ];
    const inventoryItems: InventoryItem[] = [
      {
        id: 'i1',
        workspaceId: 'ws1',
        ownerId: 'u1',
        name: 'Сливки',
        kind: 'raw',
        unit: 'кг',
        qtyOnHand: 5,
        avgCostCents: 60000,
        locationId: 'loc_kitchen',
      },
      {
        id: 'i2',
        workspaceId: 'ws1',
        ownerId: 'u1',
        name: 'Эклер готовый',
        kind: 'finished',
        unit: 'шт',
        qtyOnHand: 10,
        avgCostCents: 10000,
        locationId: 'loc_store',
      },
    ];

    const rows = computeLocationBreakdown({
      locations,
      orders,
      posSales,
      inventoryItems,
    });

    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      locationId: 'loc_kitchen',
      revenueCents: 300000,
      ordersCount: 1,
      posCount: 0,
      inventoryValueCents: 300000,
    });
    expect(rows[1]).toMatchObject({
      locationId: 'loc_store',
      revenueCents: 50000,
      ordersCount: 0,
      posCount: 1,
      inventoryValueCents: 100000,
    });
  });
});
