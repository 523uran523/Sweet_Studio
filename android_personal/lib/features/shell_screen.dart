import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/notifications_core.dart';
import '../state/studio_store.dart';
import '../ui/atelier_widgets.dart';
import 'dashboard_screen.dart';
import 'inventory_production_screen.dart';
import 'money_analytics_screen.dart';
import 'orders_clients_screen.dart';
import 'recipes_calculator_screen.dart';
import 'settings_help_screen.dart';
import 'work_hub_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _moreSubPage = 0; // 0 = Inventory, 1 = Finance, 2 = Settings & Help

  void _openMoreSection(StudioStore store, int subPage, int moreTabIdx) {
    setState(() => _moreSubPage = subPage);
    store.setTab(moreTabIdx);
  }

  void _showAlertsSheet(BuildContext context, StudioStore store) {
    final p = store.palette;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Напоминания мастерской',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (store.alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Срочных выдач, просроченных задач и критичных остатков сейчас нет.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: store.alerts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = store.alerts[i];
                    final col = a.severity == AlertSeverity.critical
                        ? p.danger
                        : (a.severity == AlertSeverity.warning
                            ? p.warning
                            : p.primary);
                    return AtelierCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.notifications_active_outlined,
                              color: col, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                Text(a.detail,
                                    style: TextStyle(
                                        fontSize: 12, color: p.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showGlobalSearch(BuildContext context, StudioStore store) {
    final ctrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final q = ctrl.text.trim().toLowerCase();
          final foundOrders = q.isEmpty
              ? const []
              : store.orders
                  .where((o) =>
                      '${o.orderNumber} ${o.clientName} ${o.title}'
                          .toLowerCase()
                          .contains(q))
                  .take(5)
                  .toList();
          final foundRecipes = q.isEmpty
              ? const []
              : store.recipes
                  .where((r) => r.title.toLowerCase().contains(q))
                  .take(5)
                  .toList();
          final foundInv = q.isEmpty
              ? const []
              : store.inventoryItems
                  .where((i) => i.name.toLowerCase().contains(q))
                  .take(5)
                  .toList();

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Поиск по заказам, рецептам, кладовой...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setModal(() {}),
                ),
                const SizedBox(height: 12),
                if (q.isEmpty)
                  const Text('Введите текст для поиска по всей базе.')
                else if (foundOrders.isEmpty &&
                    foundRecipes.isEmpty &&
                    foundInv.isEmpty)
                  const Text('Ничего не найдено.')
                else ...[
                  for (final o in foundOrders)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: Text('${o.orderNumber} · ${o.clientName}'),
                      subtitle: Text(o.title),
                      onTap: () {
                        Navigator.pop(ctx);
                        store.setTab(store.profile.hiddenModules.contains('work') ? 1 : 2);
                      },
                    ),
                  for (final r in foundRecipes)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(r.title),
                      subtitle: Text(r.category),
                      onTap: () {
                        Navigator.pop(ctx);
                        store.setTab(store.profile.hiddenModules.contains('work') ? 2 : 3);
                      },
                    ),
                  for (final inv in foundInv)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.kitchen_outlined),
                      title: Text(inv.name),
                      subtitle: Text('${inv.qtyOnHand} ${inv.unit}'),
                      onTap: () {
                        Navigator.pop(ctx);
                        final moreIdx =
                            store.profile.hiddenModules.contains('work') ? 3 : 4;
                        _openMoreSection(store, 0, moreIdx);
                      },
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudioStore>();
    final p = store.palette;
    final hidden = store.profile.hiddenModules;
    final showWork = !hidden.contains('work');
    final showInventory = !hidden.contains('inventory');
    final showFinance = !hidden.contains('finance');

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Главная',
      ),
      if (showWork)
        const NavigationDestination(
          icon: Icon(Icons.task_alt_outlined),
          selectedIcon: Icon(Icons.task_alt),
          label: 'Работа',
        ),
      const NavigationDestination(
        icon: Icon(Icons.shopping_bag_outlined),
        selectedIcon: Icon(Icons.shopping_bag),
        label: 'Заказы',
      ),
      const NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: 'Рецепты',
      ),
      const NavigationDestination(
        icon: Icon(Icons.grid_view_outlined),
        selectedIcon: Icon(Icons.grid_view),
        label: 'Ещё',
      ),
    ];

    final moreTabIdx = destinations.length - 1;
    final safeIndex = store.currentTabIndex.clamp(0, destinations.length - 1);

    // Ensure _moreSubPage points to an unhidden module or settings (2)
    var effectiveMoreSub = _moreSubPage;
    if (effectiveMoreSub == 0 && !showInventory) effectiveMoreSub = 2;
    if (effectiveMoreSub == 1 && !showFinance) effectiveMoreSub = 2;

    final pages = <Widget>[
      DashboardScreen(
        onOpenInventory: () =>
            _openMoreSection(store, showInventory ? 0 : 2, moreTabIdx),
        onOpenFinance: () =>
            _openMoreSection(store, showFinance ? 1 : 2, moreTabIdx),
        onOpenAlerts: () => _showAlertsSheet(context, store),
      ),
      if (showWork) const WorkHubScreen(),
      const OrdersClientsScreen(),
      const RecipesCalculatorScreen(),
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (showInventory)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Кладовая и Выпуск'),
                        selected: effectiveMoreSub == 0,
                        onSelected: (_) => setState(() => _moreSubPage = 0),
                      ),
                    ),
                  if (showFinance)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Финансы и Аналитика'),
                        selected: effectiveMoreSub == 1,
                        onSelected: (_) => setState(() => _moreSubPage = 1),
                      ),
                    ),
                  ChoiceChip(
                    label: const Text('Настройки, Бэкап, Справка'),
                    selected: effectiveMoreSub == 2,
                    onSelected: (_) => setState(() => _moreSubPage = 2),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: effectiveMoreSub == 0
                ? const InventoryProductionScreen()
                : (effectiveMoreSub == 1
                    ? const MoneyAnalyticsScreen()
                    : const SettingsHelpScreen()),
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.profile.studioName, overflow: TextOverflow.ellipsis),
            Text(
              store.profile.isDemoMode
                  ? 'На устройстве · Демо-данные'
                  : 'На устройстве · Офлайн',
              style: TextStyle(fontSize: 11, color: p.textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Поиск',
            onPressed: () => _showGlobalSearch(context, store),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: store.hideBalances ? 'Показать суммы' : 'Скрыть суммы',
            onPressed: store.toggleHideBalances,
            icon: Icon(
              store.hideBalances
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Уведомления',
            onPressed: () => _showAlertsSheet(context, store),
            icon: Badge.count(
              isLabelVisible: store.alerts.isNotEmpty,
              count: store.alerts.length,
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: safeIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: store.setTab,
        destinations: destinations,
      ),
    );
  }
}
