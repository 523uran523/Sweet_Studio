import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../data/models.dart';
import 'money_format.dart';

enum AlertCategory { orders, tasks, stock, expiry }

enum AlertSeverity { critical, warning, info }

class StudioAlert {
  const StudioAlert({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.detail,
  });

  final String id;
  final AlertCategory category;
  final AlertSeverity severity;
  final String title;
  final String detail;
}

List<StudioAlert> buildStudioAlerts({
  required List<Order> orders,
  required List<WorkItem> workItems,
  required List<InventoryItem> inventoryItems,
  required List<StockLot> stockLots,
  required StudioProfile profile,
  String? todayIso,
}) {
  final today = todayIso ?? todayIsoDate();
  final tomorrow = addDaysIso(today, 1);
  final soon = addDaysIso(today, 3);
  final alerts = <StudioAlert>[];

  if (profile.notifyOrders) {
    for (final ord in orders) {
      if (ord.status == OrderStatus.delivered ||
          ord.status == OrderStatus.closed ||
          ord.status == OrderStatus.cancelled ||
          ord.dueDate == null ||
          ord.dueDate!.isEmpty) {
        continue;
      }
      if (ord.dueDate!.compareTo(today) < 0) {
        alerts.add(
          StudioAlert(
            id: 'ord_overdue_${ord.id}',
            category: AlertCategory.orders,
            severity: AlertSeverity.critical,
            title: 'Просрочена выдача ${ord.orderNumber}: ${ord.title}',
            detail: '${ord.clientName} · срок ${ord.dueDate}',
          ),
        );
      } else if (ord.dueDate == today) {
        alerts.add(
          StudioAlert(
            id: 'ord_today_${ord.id}',
            category: AlertCategory.orders,
            severity: AlertSeverity.warning,
            title: 'Выдача сегодня ${ord.orderNumber}: ${ord.title}',
            detail: ord.clientName,
          ),
        );
      } else if (ord.dueDate == tomorrow) {
        alerts.add(
          StudioAlert(
            id: 'ord_tomorrow_${ord.id}',
            category: AlertCategory.orders,
            severity: AlertSeverity.info,
            title: 'Выдача завтра ${ord.orderNumber}: ${ord.title}',
            detail: '${ord.clientName} · ${ord.dueDate}',
          ),
        );
      }
    }
  }

  if (profile.notifyTasks) {
    for (final task in workItems) {
      if (task.stage == WorkStage.done ||
          task.type == WorkItemType.order ||
          task.dueDate == null ||
          task.dueDate!.isEmpty) {
        continue;
      }
      if (task.dueDate!.compareTo(today) < 0) {
        alerts.add(
          StudioAlert(
            id: 'task_overdue_${task.id}',
            category: AlertCategory.tasks,
            severity: AlertSeverity.warning,
            title: 'Просрочена задача: ${task.title}',
            detail: 'Срок ${task.dueDate}',
          ),
        );
      }
    }
  }

  if (profile.notifyStock) {
    for (final item in inventoryItems) {
      if (item.minQty > 0 && item.qtyOnHand <= item.minQty) {
        alerts.add(
          StudioAlert(
            id: 'low_${item.id}',
            category: AlertCategory.stock,
            severity:
                item.qtyOnHand <= 0 ? AlertSeverity.critical : AlertSeverity.warning,
            title: 'Низкий остаток: ${item.name}',
            detail: '${item.qtyOnHand} ${item.unit} (мин. ${item.minQty})',
          ),
        );
      }
    }
  }

  if (profile.notifyExpiry) {
    for (final lot in stockLots) {
      if (lot.status == StockLotStatus.active &&
          lot.remainingQty > 0 &&
          lot.expiresAt != null &&
          lot.expiresAt!.isNotEmpty &&
          lot.expiresAt!.compareTo(soon) <= 0) {
        final expired = lot.expiresAt!.compareTo(today) < 0;
        alerts.add(
          StudioAlert(
            id: 'exp_${lot.id}',
            category: AlertCategory.expiry,
            severity: expired ? AlertSeverity.critical : AlertSeverity.warning,
            title: expired
                ? 'Просрочена партия: ${lot.itemName}'
                : 'Истекает срок партии: ${lot.itemName}',
            detail: '${lot.lotCode} · до ${lot.expiresAt}',
          ),
        );
      }
    }
  }

  int rank(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.critical:
        return 0;
      case AlertSeverity.warning:
        return 1;
      case AlertSeverity.info:
        return 2;
    }
  }

  alerts.sort((a, b) => rank(a.severity).compareTo(rank(b.severity)));
  return alerts;
}

class LocalReminderService {
  LocalReminderService._();
  static final LocalReminderService instance = LocalReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const settings = InitializationSettings(android: androidSettings);
    try {
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      // Safe no-op in headless unit tests where platform channels don't exist
    }
  }

  Future<bool> requestPermission() async {
    await init();
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> areNotificationsEnabled() async {
    await init();
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidImpl?.areNotificationsEnabled();
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showSummaryNotification({
    required String studioName,
    required List<StudioAlert> alerts,
  }) async {
    if (alerts.isEmpty) return false;
    await init();
    try {
      final enabled = await areNotificationsEnabled();
      if (!enabled) return false;

      const androidDetails = AndroidNotificationDetails(
        'sweet_studio_reminders',
        'Напоминания SweetStudio',
        channelDescription:
            'Выдачи заказов, просроченные задачи и остатки на устройстве',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const details = NotificationDetails(android: androidDetails);
      final first = alerts.first;
      final body = alerts.length == 1
          ? '${first.title} (${first.detail})'
          : '${first.title} и ещё ${alerts.length - 1} напоминаний';
      await _plugin.show(
        1001,
        'SweetStudio · $studioName',
        body,
        details,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showTestNotification(String studioName) async {
    await init();
    try {
      final enabled = await areNotificationsEnabled();
      if (!enabled) return false;
      const androidDetails = AndroidNotificationDetails(
        'sweet_studio_reminders',
        'Напоминания SweetStudio',
        channelDescription:
            'Выдачи заказов, просроченные задачи и остатки на устройстве',
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.show(
        1002,
        'SweetStudio · $studioName',
        'Локальные напоминания работают на этом устройстве',
        const NotificationDetails(android: androidDetails),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
