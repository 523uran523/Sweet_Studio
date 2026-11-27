import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/calculator_core.dart';
import '../core/money_format.dart';
import '../core/notifications_core.dart';
import '../data/models.dart';
import '../state/studio_store.dart';
import '../ui/atelier_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenInventory,
    required this.onOpenFinance,
    required this.onOpenAlerts,
  });

  final VoidCallback onOpenInventory;
  final VoidCallback onOpenFinance;
  final VoidCallback onOpenAlerts;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _periodDays = 30; // 1 = today, 7, 30, 0 = all

  bool _inPeriod(String iso) {
    if (_periodDays == 0) return true;
    final today = todayIsoDate();
    final start = addDaysIso(today, -(_periodDays - 1));
    final dateOnly = iso.length >= 10 ? iso.substring(0, 10) : iso;
    return dateOnly.compareTo(start) >= 0;
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudioStore>();
    final p = store.palette;
    final hide = store.hideBalances;
    final curr = store.profile.currencySymbol;
    final today = todayIsoDate();
    final soonDate = addDaysIso(today, 3);

    final periodTx =
        store.moneyTransactions.where((t) => _inPeriod(t.occurredAt)).toList();
    final cashSummary = netCashTotals(periodTx);

    final recognizedOrders = store.orders.where((o) =>
        (o.status == OrderStatus.delivered || o.status == OrderStatus.closed) &&
        _inPeriod(o.dueDate ?? o.createdAt));
    final recognizedRevenue =
        recognizedOrders.fold<int>(0, (s, o) => s + o.priceCents);

    final accountsTotal =
        store.accounts.fold<int>(0, (s, a) => s + a.balanceCents);

    final receivables = store.orders
        .where((o) =>
            o.status != OrderStatus.cancelled && o.balanceDueCents > 0)
        .fold<int>(0, (s, o) => s + o.balanceDueCents);

    final upcomingPickups = store.orders
        .where((o) =>
            o.status != OrderStatus.delivered &&
            o.status != OrderStatus.closed &&
            o.status != OrderStatus.cancelled &&
            o.dueDate != null &&
            o.dueDate!.isNotEmpty &&
            o.dueDate!.compareTo(soonDate) <= 0)
        .toList()
      ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));

    final todayMinutes = store.timeEntries
        .where((e) => e.date == today)
        .fold<int>(0, (s, e) => s + e.minutes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (store.profile.isDemoMode) ...[
          AtelierCard(
            color: p.surfaceAlt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: p.primary, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Включены демо-данные',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Вы можете изучать расчёты, заказы и FEFO-партии на тестовом наборе или очистить его в 1 нажатие.',
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Очистить демо-данные?'),
                        content: const Text(
                          'Все тестовые рецепты, заказы, клиенты и операции будут удалены, останется чистая база с кассой «Наличные».',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Очистить'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await store.switchToCleanWorkspace();
                      if (context.mounted) {
                        showAtelierMessage(context, 'Чистая база готова к работе.');
                      }
                    }
                  },
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Очистить демо и начать с нуля'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Period selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final opt in [
                (1, 'Сегодня'),
                (7, '7 дней'),
                (30, '30 дней'),
                (0, 'Всё время'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(opt.$2),
                    selected: _periodDays == opt.$1,
                    onSelected: (_) => setState(() => _periodDays = opt.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2x2 metrics grid
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'Денежный поток',
                value: formatMoneyCents(
                  cashSummary.netCents,
                  hide: hide,
                  currencySymbol: curr,
                ),
                hint:
                    'Приход: ${formatMoneyCents(cashSummary.incomeCents, hide: hide, currencySymbol: curr)}',
                icon: Icons.account_balance_wallet_outlined,
                accentColor:
                    cashSummary.netCents >= 0 ? p.success : p.danger,
                onTap: widget.onOpenFinance,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                label: 'Признанная выручка',
                value: formatMoneyCents(
                  recognizedRevenue,
                  hide: hide,
                  currencySymbol: curr,
                ),
                hint: pluralOrders(recognizedOrders.length),
                icon: Icons.receipt_long_outlined,
                accentColor: p.primary,
                onTap: () => store.setTab(2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'На счетах',
                value: formatMoneyCents(
                  accountsTotal,
                  hide: hide,
                  currencySymbol: curr,
                ),
                hint: '${store.accounts.length} сч.',
                icon: Icons.savings_outlined,
                onTap: widget.onOpenFinance,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                label: 'К доплате',
                value: formatMoneyCents(
                  receivables,
                  hide: hide,
                  currencySymbol: curr,
                ),
                hint: 'Заказы с долгом',
                icon: Icons.schedule_outlined,
                accentColor: receivables > 0 ? p.warning : p.success,
                onTap: () => store.setTab(2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Work Timer card
        AtelierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, color: p.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Таймер работы на кухне',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'Сегодня: ${pluralMinutes(todayMinutes)}',
                    style: TextStyle(fontSize: 12, color: p.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    _formatDuration(store.totalTimerSeconds),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: store.timerRunning ? p.primary : null,
                        ),
                  ),
                  const Spacer(),
                  if (!store.timerRunning)
                    FilledButton.icon(
                      onPressed: () => store.startTimer(),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text(
                        store.accumulatedSeconds > 0 ? 'Продолжить' : 'Старт',
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => store.pauseTimer(),
                      icon: const Icon(Icons.pause, size: 18),
                      label: const Text('Пауза'),
                    ),
                  if (store.totalTimerSeconds > 0) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Сохранить время',
                      onPressed: () async {
                        final mins = await store.stopAndSaveTimer();
                        if (context.mounted) {
                          showAtelierMessage(
                            context,
                            mins > 0
                                ? 'Записано в табель: ${pluralMinutes(mins)}'
                                : 'Таймер сброшен',
                          );
                        }
                      },
                      icon: const Icon(Icons.stop),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Alerts preview
        if (store.alerts.isNotEmpty) ...[
          SectionHeader(
            title: 'Требует внимания (${store.alerts.length})',
            trailing: TextButton(
              onPressed: widget.onOpenAlerts,
              child: const Text('Все'),
            ),
          ),
          const SizedBox(height: 8),
          AtelierCard(
            onTap: widget.onOpenAlerts,
            child: Column(
              children: [
                for (var i = 0;
                    i < (store.alerts.length > 3 ? 3 : store.alerts.length);
                    i++) ...[
                  if (i > 0) const Divider(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        store.alerts[i].severity == AlertSeverity.critical
                            ? Icons.error_outline
                            : Icons.notifications_active_outlined,
                        size: 18,
                        color: store.alerts[i].severity == AlertSeverity.critical
                            ? p.danger
                            : p.warning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              store.alerts[i].title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              store.alerts[i].detail,
                              style: TextStyle(fontSize: 12, color: p.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Upcoming pickups
        SectionHeader(
          title: 'Ближайшие выдачи',
          subtitle: 'Заказы со сроком сегодня и в ближайшие 3 дня',
          trailing: TextButton(
            onPressed: () => store.setTab(2),
            child: const Text('К заказам'),
          ),
        ),
        const SizedBox(height: 8),
        if (upcomingPickups.isEmpty)
          EmptyAtelierState(
            icon: Icons.event_available_outlined,
            title: 'Ближайших выдач нет',
            description:
                'Добавьте заказ во вкладке «Заказы», чтобы видеть график выдач на главной.',
            actionLabel: 'Перейти к заказам',
            onAction: () => store.setTab(2),
          )
        else
          for (final ord in upcomingPickups.take(5)) ...[
            AtelierCard(
              onTap: () => store.setTab(2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${ord.orderNumber} · ${ord.clientName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (ord.dueDate != null &&
                                ord.dueDate!.compareTo(today) < 0)
                              StatusBadge(label: 'Просрочен', color: p.danger)
                            else if (ord.dueDate == today)
                              StatusBadge(label: 'Сегодня', color: p.warning),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          ord.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        ord.dueDate ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        formatMoneyCents(ord.priceCents,
                            hide: hide, currencySymbol: curr),
                        style: TextStyle(fontSize: 12, color: p.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

        const SizedBox(height: 10),
        SectionHeader(title: 'Быстрый переход'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.kitchen_outlined, size: 18),
              label: const Text('Кладовая и Производство'),
              onPressed: widget.onOpenInventory,
            ),
            ActionChip(
              avatar: const Icon(Icons.analytics_outlined, size: 18),
              label: const Text('Финансы и Аналитика'),
              onPressed: widget.onOpenFinance,
            ),
            ActionChip(
              avatar: const Icon(Icons.calculate_outlined, size: 18),
              label: const Text('Рецепты и Калькулятор'),
              onPressed: () => store.setTab(3),
            ),
          ],
        ),
      ],
    );
  }
}
