import {
  InventoryItem,
  LocationItem,
  NavSectionId,
  Order,
  StockLot,
  WorkItem,
} from '../types/domain';
import { matchesLocationFilter } from './locations';

export type AlertCategory = 'orders' | 'tasks' | 'stock' | 'expiry';
export type AlertSeverity = 'critical' | 'warning' | 'info';

export interface WorkspaceAlert {
  id: string;
  category: AlertCategory;
  severity: AlertSeverity;
  title: string;
  detail: string;
  page: NavSectionId;
}

export interface NotificationPrefs {
  browserEnabled: boolean;
  notifyOrders: boolean;
  notifyTasks: boolean;
  notifyStock: boolean;
  notifyExpiry: boolean;
}

export const DEFAULT_NOTIFICATION_PREFS: NotificationPrefs = {
  browserEnabled: false,
  notifyOrders: true,
  notifyTasks: true,
  notifyStock: true,
  notifyExpiry: true,
};

export function notifPrefsKey(workspaceId: string): string {
  return `sweet_notif_prefs_${workspaceId}`;
}

export function readNotificationPrefs(workspaceId: string): NotificationPrefs {
  if (typeof window === 'undefined' || !workspaceId) {
    return { ...DEFAULT_NOTIFICATION_PREFS };
  }
  try {
    const raw = window.localStorage.getItem(notifPrefsKey(workspaceId));
    if (!raw) return { ...DEFAULT_NOTIFICATION_PREFS };
    const parsed = JSON.parse(raw) as Partial<NotificationPrefs>;
    return {
      browserEnabled: Boolean(parsed.browserEnabled),
      notifyOrders: parsed.notifyOrders !== false,
      notifyTasks: parsed.notifyTasks !== false,
      notifyStock: parsed.notifyStock !== false,
      notifyExpiry: parsed.notifyExpiry !== false,
    };
  } catch {
    return { ...DEFAULT_NOTIFICATION_PREFS };
  }
}

export function writeNotificationPrefs(
  workspaceId: string,
  prefs: NotificationPrefs,
): void {
  if (typeof window === 'undefined' || !workspaceId) return;
  try {
    window.localStorage.setItem(notifPrefsKey(workspaceId), JSON.stringify(prefs));
  } catch {
    // ignore storage quota errors
  }
}

function addDaysToIso(isoDate: string, days: number): string {
  const [y, m, d] = isoDate.split('-').map(Number);
  if (!y || !m || !d) {
    return new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
  }
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
}

export function buildWorkspaceAlerts(params: {
  orders: Order[];
  workItems: WorkItem[];
  inventoryItems: InventoryItem[];
  stockLots: StockLot[];
  todayIso?: string;
  activeLocationId?: string;
  locations?: LocationItem[];
  prefs?: NotificationPrefs;
}): WorkspaceAlert[] {
  const {
    orders,
    workItems,
    inventoryItems,
    stockLots,
    todayIso = new Date().toISOString().slice(0, 10),
    activeLocationId = '',
    locations = [],
    prefs = DEFAULT_NOTIFICATION_PREFS,
  } = params;

  const tomorrowIso = addDaysToIso(todayIso, 1);
  const soonIso = addDaysToIso(todayIso, 3);
  const alerts: WorkspaceAlert[] = [];

  if (prefs.notifyOrders) {
    for (const ord of orders) {
      if (
        ord.status === 'delivered' ||
        ord.status === 'closed' ||
        ord.status === 'cancelled' ||
        !ord.dueDate
      ) {
        continue;
      }
      if (
        activeLocationId &&
        !matchesLocationFilter({
          entityLocationName: ord.locationName,
          activeLocationId,
          locations,
        })
      ) {
        continue;
      }
      if (ord.dueDate < todayIso) {
        alerts.push({
          id: `ord_overdue_${ord.id}`,
          category: 'orders',
          severity: 'critical',
          title: `Просрочена выдача ${ord.orderNumber}: ${ord.title}`,
          detail: `${ord.clientName} · срок ${ord.dueDate}`,
          page: 'orders',
        });
      } else if (ord.dueDate === todayIso) {
        alerts.push({
          id: `ord_today_${ord.id}`,
          category: 'orders',
          severity: 'warning',
          title: `Выдача сегодня ${ord.orderNumber}: ${ord.title}`,
          detail: ord.clientName,
          page: 'orders',
        });
      } else if (ord.dueDate === tomorrowIso) {
        alerts.push({
          id: `ord_tomorrow_${ord.id}`,
          category: 'orders',
          severity: 'info',
          title: `Выдача завтра ${ord.orderNumber}: ${ord.title}`,
          detail: `${ord.clientName} · ${ord.dueDate}`,
          page: 'orders',
        });
      }
    }
  }

  if (prefs.notifyTasks) {
    for (const task of workItems) {
      if (task.stage === 'done' || !task.dueDate || task.type === 'order') continue;
      if (
        activeLocationId &&
        !matchesLocationFilter({
          entityLocationName: task.locationName,
          activeLocationId,
          locations,
        })
      ) {
        continue;
      }
      if (task.dueDate < todayIso) {
        alerts.push({
          id: `task_overdue_${task.id}`,
          category: 'tasks',
          severity: 'warning',
          title: `Просрочена задача: ${task.title}`,
          detail: `${task.assigneeName || 'Исполнитель'} · срок ${task.dueDate}`,
          page: 'work',
        });
      }
    }
  }

  if (prefs.notifyStock) {
    for (const item of inventoryItems) {
      if (
        activeLocationId &&
        !matchesLocationFilter({
          entityLocationId: item.locationId,
          activeLocationId,
          locations,
        })
      ) {
        continue;
      }
      if (item.minQty && item.qtyOnHand <= item.minQty) {
        alerts.push({
          id: `low_${item.id}`,
          category: 'stock',
          severity: item.qtyOnHand <= 0 ? 'critical' : 'warning',
          title: `Низкий остаток: ${item.name}`,
          detail: `${item.qtyOnHand} ${item.unit} (мин. ${item.minQty})`,
          page: 'inventory',
        });
      }
    }
  }

  if (prefs.notifyExpiry) {
    for (const lot of stockLots) {
      if (
        activeLocationId &&
        !matchesLocationFilter({
          entityLocationId: lot.locationId,
          activeLocationId,
          locations,
        })
      ) {
        continue;
      }
      if (lot.status === 'active' && lot.expiresAt && lot.expiresAt <= soonIso) {
        alerts.push({
          id: `exp_${lot.id}`,
          category: 'expiry',
          severity: lot.expiresAt < todayIso ? 'critical' : 'warning',
          title:
            lot.expiresAt < todayIso
              ? `Просрочена партия: ${lot.itemName}`
              : `Истекает срок партии: ${lot.itemName}`,
          detail: `${lot.lotCode} · до ${lot.expiresAt}`,
          page: 'inventory',
        });
      }
    }
  }

  const orderRank: Record<AlertSeverity, number> = {
    critical: 0,
    warning: 1,
    info: 2,
  };
  return alerts.sort((a, b) => orderRank[a.severity] - orderRank[b.severity]);
}

export function formatTelegramDigestText(params: {
  workspaceName: string;
  alerts: WorkspaceAlert[];
  todayIso?: string;
}): string {
  const { workspaceName, alerts, todayIso = new Date().toISOString().slice(0, 10) } = params;
  const header = `SweetStudio · ${workspaceName} (${todayIso})`;
  if (alerts.length === 0) {
    return `${header}\nВсе выдачи, задачи и остатки в норме.`;
  }
  const lines = alerts.slice(0, 15).map((a) => `• ${a.title} (${a.detail})`);
  const more =
    alerts.length > 15 ? `\n...и ещё ${alerts.length - 15} предупреждений в приложении.` : '';
  return `${header}\nНапоминания (${alerts.length}):\n${lines.join('\n')}${more}`;
}

export function buildTelegramShareUrl(text: string): string {
  return `https://t.me/share/url?url=${encodeURIComponent(' ')}&text=${encodeURIComponent(text)}`;
}
