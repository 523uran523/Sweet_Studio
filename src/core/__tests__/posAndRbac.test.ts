import { describe, expect, it } from 'vitest';
import {
  computePosCartTotals,
  computeShiftDiscrepancyCents,
  computeShiftExpectedCashCents,
  evaluateCouponForSale,
  resolvePosScannedCode,
} from '../posCore';
import {
  filterVisibleRecipesForRole,
  getRolePermissions,
  resolveEffectiveRole,
} from '../rbac';
import { Coupon, InventoryItem, Recipe, StockLot, Workspace } from '../../types/domain';

describe('posCore & rbac', () => {
  it('computes POS cart totals, shift expected cash, and coupon validity', () => {
    const expected = computeShiftExpectedCashCents({
      openingCashCents: 100000,
      cashSalesCents: 250000,
      cashInCents: 0,
      cashOutCents: 30000,
      refundsCents: 20000,
    });
    expect(expected).toBe(300000);
    expect(computeShiftDiscrepancyCents(expected, 298000)).toBe(-2000);

    const coupon: Coupon = {
      id: 'cpn1',
      workspaceId: 'ws1',
      ownerId: 'owner_uid',
      code: 'SWEET10',
      discountType: 'percent',
      discountValue: 10,
      minOrderCents: 100000,
      status: 'active',
      expiresAt: '2026-12-31',
    };
    const couponCheck = evaluateCouponForSale({
      coupon,
      subtotalCents: 200000,
      todayIso: '2026-11-26',
    });
    expect(couponCheck.valid).toBe(true);
    expect(couponCheck.discountCents).toBe(20000);

    const cart = computePosCartTotals(
      [
        {
          id: 'line1',
          title: 'Эклеры',
          qty: 4,
          unit: 'шт',
          unitPriceCents: 50000,
          unitCostCents: 18000,
        },
      ],
      couponCheck.discountCents,
    );
    expect(cart.subtotalCents).toBe(200000);
    expect(cart.totalCents).toBe(180000);
    expect(cart.costCents).toBe(72000);

    const personalCoupon: Coupon = {
      ...coupon,
      id: 'cpn_personal',
      clientId: 'cli_alice',
      clientName: 'Алиса',
    };
    expect(
      evaluateCouponForSale({
        coupon: personalCoupon,
        subtotalCents: 200000,
        todayIso: '2026-11-26',
      }).valid,
    ).toBe(false);
    expect(
      evaluateCouponForSale({
        coupon: personalCoupon,
        subtotalCents: 200000,
        clientId: 'cli_alice',
        todayIso: '2026-11-26',
      }).valid,
    ).toBe(true);
  });

  it('resolves scanned QR codes and barcodes to coupons, stock lots, inventory items, and recipes', () => {
    const coupons: Coupon[] = [
      {
        id: 'cpn1',
        workspaceId: 'ws1',
        ownerId: 'owner_uid',
        code: 'SWEET-500',
        discountType: 'fixed',
        discountValue: 50000,
        status: 'active',
      },
    ];
    const inventoryItems: InventoryItem[] = [
      {
        id: 'inv_macaron',
        workspaceId: 'ws1',
        ownerId: 'owner_uid',
        name: 'Макарон фисташка',
        kind: 'finished',
        unit: 'шт',
        qtyOnHand: 24,
        avgCostCents: 6500,
      },
    ];
    const stockLots: StockLot[] = [
      {
        id: 'lot_01',
        workspaceId: 'ws1',
        ownerId: 'owner_uid',
        itemId: 'inv_macaron',
        itemName: 'Макарон фисташка',
        lotCode: 'LOT-2611-A',
        unit: 'шт',
        initialQty: 24,
        remainingQty: 24,
        unitCostCents: 6500,
        status: 'active',
      },
    ];
    const recipes: Recipe[] = [
      {
        id: 'rec_medovik',
        workspaceId: 'ws1',
        ownerId: 'owner_uid',
        title: 'Медовик классический',
        category: 'Торты',
        version: 1,
        status: 'approved',
        yieldGrams: 1200,
        costCents: 75000,
        recommendedPriceCents: 220000,
      },
      {
        id: 'rec_arch',
        workspaceId: 'ws1',
        ownerId: 'owner_uid',
        title: 'Архивный десерт',
        category: 'Торты',
        version: 1,
        status: 'archived',
        yieldGrams: 500,
        costCents: 30000,
        recommendedPriceCents: 90000,
      },
    ];

    expect(
      resolvePosScannedCode({
        rawCode: 'sweet-500',
        coupons,
        inventoryItems,
        stockLots,
        recipes,
      }),
    ).toMatchObject({ kind: 'coupon', matchedCode: 'SWEET-500' });

    expect(
      resolvePosScannedCode({
        rawCode: 'SweetStudio:SWEET-500',
        coupons,
        inventoryItems,
        stockLots,
        recipes,
      }),
    ).toMatchObject({ kind: 'coupon', matchedCode: 'SWEET-500' });

    expect(
      resolvePosScannedCode({
        rawCode: 'SWEETSTUDIO:COUPON:SWEET-500',
        coupons,
        inventoryItems,
        stockLots,
        recipes,
      }),
    ).toMatchObject({ kind: 'coupon', matchedCode: 'SWEET-500' });

    expect(
      resolvePosScannedCode({
        rawCode: 'lot-2611-a',
        coupons,
        inventoryItems,
        stockLots,
        recipes,
      }),
    ).toMatchObject({ kind: 'inventory', item: { id: 'inv_macaron' }, matchedLot: { id: 'lot_01' } });

    expect(
      resolvePosScannedCode({
        rawCode: 'inv_macaron',
        coupons,
        inventoryItems,
        stockLots,
        recipes,
      }),
    ).toMatchObject({ kind: 'inventory', item: { id: 'inv_macaron' } });

    expect(
      resolvePosScannedCode({
        rawCode: 'SWEETSTUDIO:RECIPE:rec_medovik',
        coupons,
        inventoryItems,
        stockLots,
        recipes,
      }),
    ).toMatchObject({ kind: 'recipe', recipe: { id: 'rec_medovik' } });

    expect(
      resolvePosScannedCode({
        rawCode: 'Архивный десерт',
        coupons,
        inventoryItems,
        stockLots,
        recipes,
      }),
    ).toEqual({ kind: 'unknown', code: 'Архивный десерт' });

    expect(
      resolvePosScannedCode({
        rawCode: '4607001234567',
        coupons,
        inventoryItems,
        stockLots,
        recipes,
      }),
    ).toEqual({ kind: 'unknown', code: '4607001234567' });
  });

  it('enforces RBAC permissions and recipe visibility by role', () => {
    const ws: Workspace = {
      id: 'ws1',
      name: 'Studio',
      ownerId: 'owner_uid',
      businessFormat: 'studio',
      themeIndex: 0,
    };

    expect(
      resolveEffectiveRole({
        userUid: 'owner_uid',
        workspace: ws,
        members: [],
      }).role,
    ).toBe('owner');

    const sellerPerms = getRolePermissions('seller');
    expect(sellerPerms.canAccessPos).toBe(true);
    expect(sellerPerms.canViewMoney).toBe(false);
    expect(sellerPerms.canViewCosts).toBe(false);
    expect(sellerPerms.allowedSections.has('pos')).toBe(true);
    expect(sellerPerms.allowedSections.has('money')).toBe(false);

    const recipes: Recipe[] = [
      {
        id: 'r1',
        workspaceId: 'ws1',
        ownerId: 'owner_uid',
        version: 1,
        title: 'Approved Cake',
        category: 'Торты',
        status: 'approved',
        yieldGrams: 1000,
        costCents: 50000,
        recommendedPriceCents: 150000,
        marginPercent: 66,
        ingredients: [],
      },
      {
        id: 'r2',
        workspaceId: 'ws1',
        ownerId: 'owner_uid',
        version: 1,
        title: 'Draft Secret',
        category: 'Торты',
        status: 'draft',
        yieldGrams: 1000,
        costCents: 50000,
        recommendedPriceCents: 150000,
        marginPercent: 66,
        ingredients: [],
      },
    ];

    expect(filterVisibleRecipesForRole(recipes, 'owner', null)).toHaveLength(2);
    expect(filterVisibleRecipesForRole(recipes, 'confectioner', null)).toHaveLength(1);
    expect(
      filterVisibleRecipesForRole(recipes, 'confectioner', {
        id: 'm1',
        workspaceId: 'ws1',
        ownerId: 'owner_uid',
        name: 'Мастер',
        role: 'confectioner',
        payType: 'hourly',
        active: true,
        allowedRecipeIds: ['r2'],
      }),
    ).toHaveLength(1);
  });
});

