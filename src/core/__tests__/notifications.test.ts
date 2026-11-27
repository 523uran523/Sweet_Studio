import { describe, expect, it } from 'vitest';
import {
  buildTelegramShareUrl,
  buildWorkspaceAlerts,
  DEFAULT_NOTIFICATION_PREFS,
  formatTelegramDigestText,
} from '../notifications';
import { InventoryItem, LocationItem, Order, StockLot, WorkItem } from '../../types/domain';

const locations: LocationItem[] = [
  { id: 'loc_k', workspaceId: 'ws1', ownerId: 'u1', name: 'Цех', kind: 'kitchen', isDefault: true },
  { id: 'loc_s', workspaceId: 'ws1', ownerId: 'u1', name: 'Витрина', kind: 'store' },
];

const orders: Order[] = [
  {
    id: 'o_over',
    workspaceId: 'ws1',
    ownerId: 'u1',
    orderNumber: '№10',
    title: 'Наполеон',
    clientName: 'Иван',
    priceCents: 200000,
    costCents: 80000,
    paidCents: 100000,
    status: 'ready',
    dueDate: '2026-11-25',
    locationName: 'Цех',
  },
  {
    id: 'o_tom',
    workspaceId: 'ws1',
    ownerId: 'u1',
    orderNumber: '№11',
    title: 'Капкейки',
    clientName: 'Ольга',
    priceCents: 150000,
    costCents: 50000,
    paidCents: 150000,
    status: 'confirmed',
    dueDate: '2026-11-27',
    locationName: 'Витрина',
  },
  {
    id: 'o_done',
    workspaceId: 'ws1',
    ownerId: 'u1',
    orderNumber: '№12',
    title: 'Выданный торт',
    clientName: 'Пётр',
    priceCents: 250000,
    costCents: 90000,
    paidCents: 250000,
    status: 'delivered',
    dueDate: '2026-11-25',
    locationName: 'Цех',
  },
];

const workItems: WorkItem[] = [
  {
    id: 'w_over',
    workspaceId: 'ws1',
    ownerId: 'u1',
    type: 'task',
    title: 'Закупить коробки',
    assigneeName: 'Мария',
    locationName: 'Цех',
    dueDate: '2026-11-24',
    priority: 'high',
    stage: 'in_progress',
  },
];

const inventoryItems: InventoryItem[] = [
  {
    id: 'i_low',
    workspaceId: 'ws1',
    ownerId: 'u1',
    name: 'Сливки 33%',
    kind: 'raw',
    unit: 'л',
    qtyOnHand: 0,
    minQty: 3,
    avgCostCents: 45000,
    locationId: 'loc_k',
  },
];

const stockLots: StockLot[] = [
  {
    id: 'lot_exp',
    workspaceId: 'ws1',
    ownerId: 'u1',
    itemId: 'i_low',
    itemName: 'Сливки 33%',
    lotCode: 'L-99',
    unit: 'л',
    initialQty: 5,
    remainingQty: 2,
    unitCostCents: 45000,
    locationId: 'loc_s',
    expiresAt: '2026-11-28',
    status: 'active',
  },
];

describe('notifications & Telegram digest', () => {
  it('builds severity-sorted alerts across orders, tasks, stock, and expiry', () => {
    const alerts = buildWorkspaceAlerts({
      orders,
      workItems,
      inventoryItems,
      stockLots,
      todayIso: '2026-11-26',
      locations,
      prefs: DEFAULT_NOTIFICATION_PREFS,
    });

    // Should exclude delivered order o_done
    expect(alerts.some((a) => a.id.includes('o_done'))).toBe(false);
    expect(alerts.map((a) => a.id)).toEqual([
      'ord_overdue_o_over',
      'low_i_low',
      'task_overdue_w_over',
      'exp_lot_exp',
      'ord_tomorrow_o_tom',
    ]);
  });

  it('filters alerts by activeLocationId and notification preferences', () => {
    const storeOnly = buildWorkspaceAlerts({
      orders,
      workItems,
      inventoryItems,
      stockLots,
      todayIso: '2026-11-26',
      activeLocationId: 'loc_s',
      locations,
      prefs: DEFAULT_NOTIFICATION_PREFS,
    });
    expect(storeOnly.map((a) => a.id)).toEqual(['exp_lot_exp', 'ord_tomorrow_o_tom']);

    const ordersDisabled = buildWorkspaceAlerts({
      orders,
      workItems,
      inventoryItems,
      stockLots,
      todayIso: '2026-11-26',
      locations,
      prefs: { ...DEFAULT_NOTIFICATION_PREFS, notifyOrders: false, notifyTasks: false },
    });
    expect(ordersDisabled.every((a) => a.category === 'stock' || a.category === 'expiry')).toBe(true);
  });

  it('formats Telegram digest text and share link', () => {
    const alerts = buildWorkspaceAlerts({
      orders,
      workItems,
      inventoryItems,
      stockLots,
      todayIso: '2026-11-26',
      locations,
    });
    const text = formatTelegramDigestText({
      workspaceName: 'Ванильный Цех',
      alerts,
      todayIso: '2026-11-26',
    });
    expect(text).toContain('SweetStudio · Ванильный Цех (2026-11-26)');
    expect(text).toContain('Просрочена выдача №10');

    const url = buildTelegramShareUrl(text);
    expect(url.startsWith('https://t.me/share/url?')).toBe(true);
    expect(url).toContain(encodeURIComponent('Ванильный Цех'));
  });
});
