import { Order, OrderItem, Recipe } from '../types/domain';

/**
 * Normalizes an Order to an explicit non-empty list of OrderItems when possible,
 * preserving backward compatibility with legacy single-recipe orders.
 */
export function getOrderItemsNormalized(order: Pick<
  Order,
  'id' | 'title' | 'items' | 'recipeId' | 'recipeTitle' | 'weightGrams' | 'priceCents' | 'costCents'
>): OrderItem[] {
  if (Array.isArray(order.items) && order.items.length > 0) {
    return order.items;
  }
  const fallbackTitle = order.recipeTitle || order.title || 'Изделие';
  return [
    {
      id: `legacy_${order.id}`,
      recipeId: order.recipeId || '',
      recipeTitle: fallbackTitle,
      qty: 1,
      weightGrams: Math.max(0, Number(order.weightGrams) || 0),
      priceCents: Math.max(0, Math.round(order.priceCents || 0)),
      costCents: Math.max(0, Math.round(order.costCents || 0)),
    },
  ];
}

export function computeOrderItemsTotals(items: OrderItem[]): {
  totalWeightGrams: number;
  basePriceCents: number;
  baseCostCents: number;
} {
  let totalWeightGrams = 0;
  let basePriceCents = 0;
  let baseCostCents = 0;
  for (const item of items) {
    const qty = Math.max(1, Number(item.qty) || 1);
    totalWeightGrams += Math.round((Number(item.weightGrams) || 0) * qty);
    basePriceCents += Math.round((Number(item.priceCents) || 0) * qty);
    baseCostCents += Math.round((Number(item.costCents) || 0) * qty);
  }
  return { totalWeightGrams, basePriceCents, baseCostCents };
}

export function summarizeOrderItems(
  order: Pick<
    Order,
    'id' | 'title' | 'items' | 'recipeId' | 'recipeTitle' | 'weightGrams' | 'priceCents' | 'costCents'
  >,
): {
  count: number;
  totalWeightGrams: number;
  summaryText: string;
} {
  const items =
    Array.isArray(order.items) && order.items.length > 0
      ? order.items
      : order.recipeTitle || order.weightGrams
        ? getOrderItemsNormalized(order)
        : [];
  if (items.length === 0) {
    return {
      count: 0,
      totalWeightGrams: Number(order.weightGrams) || 0,
      summaryText: '',
    };
  }
  const totalWeightGrams = items.reduce(
    (s, item) => s + Math.round((item.weightGrams || 0) * Math.max(1, item.qty || 1)),
    0,
  );
  if (items.length === 1) {
    const only = items[0];
    const qtyLabel = only.qty > 1 ? ` × ${only.qty}` : '';
    const weightLabel = totalWeightGrams > 0 ? ` · ${totalWeightGrams} г` : '';
    return {
      count: only.qty,
      totalWeightGrams,
      summaryText: `${only.recipeTitle}${qtyLabel}${weightLabel}`,
    };
  }
  const titlesPreview = items
    .slice(0, 3)
    .map((i) => `${i.recipeTitle}${i.qty > 1 ? ` ×${i.qty}` : ''}`)
    .join(', ');
  const tail = items.length > 3 ? ` + ещё ${items.length - 3}` : '';
  const weightLabel = totalWeightGrams > 0 ? ` · ${totalWeightGrams} г` : '';
  return {
    count: items.reduce((s, i) => s + Math.max(1, i.qty || 1), 0),
    totalWeightGrams,
    summaryText: `${items.length} поз. (${titlesPreview}${tail})${weightLabel}`,
  };
}

export function buildOrderSummaryTitle(items: OrderItem[]): string {
  if (items.length === 0) return '';
  if (items.length === 1) {
    const first = items[0];
    return `${first.recipeTitle}${first.qty > 1 ? ` ×${first.qty}` : ''}`.slice(0, 160);
  }
  const joined = items
    .map((i) => `${i.recipeTitle}${i.qty > 1 ? ` ×${i.qty}` : ''}`)
    .join(' + ');
  return joined.slice(0, 160);
}

export interface RecipeOrderAttribution {
  key: string;
  title: string;
  ordersCount: number;
  revenueCents: number;
  costCents: number;
  laborHoursTotal: number;
}

/**
 * Distributes an order's recognized revenue, cost, and labor hours across all its items.
 */
export function attributeOrderToRecipes(
  order: Order,
  recipes: Recipe[],
): RecipeOrderAttribution[] {
  const items = Array.isArray(order.items) && order.items.length > 0
    ? order.items
    : order.recipeId || order.recipeTitle
      ? getOrderItemsNormalized(order)
      : [];
  if (items.length === 0) return [];

  const lineGrosses = items.map((item) => Math.max(0, item.priceCents * Math.max(1, item.qty || 1)));
  const totalGross = lineGrosses.reduce((s, v) => s + v, 0);

  let allocatedRevenue = 0;
  return items.map((item, idx) => {
    const qty = Math.max(1, item.qty || 1);
    const rec =
      (item.recipeId ? recipes.find((r) => r.id === item.recipeId) : undefined) ||
      recipes.find((r) => r.title.trim().toLowerCase() === item.recipeTitle.trim().toLowerCase());
    const key = rec?.id || item.recipeId || item.recipeTitle || 'other';
    const title = rec?.title || item.recipeTitle || 'Рецепт';

    let revShare: number;
    if (idx === items.length - 1) {
      revShare = Math.max(0, order.priceCents - allocatedRevenue);
    } else if (totalGross > 0) {
      revShare = Math.round((order.priceCents * lineGrosses[idx]) / totalGross);
    } else {
      revShare = Math.round(order.priceCents / items.length);
    }
    allocatedRevenue += revShare;

    const lineCost =
      items.length === 1 && order.costCents > 0
        ? order.costCents
        : Math.max(0, Math.round(item.costCents * qty));

    const scalePerUnit =
      rec && rec.yieldGrams > 0 && item.weightGrams > 0
        ? item.weightGrams / rec.yieldGrams
        : 1;
    const laborHoursTotal = (rec?.laborHours ?? 1.5) * scalePerUnit * qty;

    return {
      key,
      title,
      ordersCount: qty,
      revenueCents: revShare,
      costCents: lineCost,
      laborHoursTotal,
    };
  });
}
