import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/tax_radar_bar.dart';
import '../../app/ui.dart';
import '../../core/deep_link_service.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/client.dart';
import '../../data/models/client_reminder.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/job.dart';
import '../../data/models/recurring_payment.dart';
import '../../state/masters_store.dart';
import '../../state/settings_controller.dart';
import '../jobs/job_detail_screen.dart';
import '../stats/stats_screen.dart';
import '../../core/money_format.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<MastersStore>().openWorkSession != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final settings = context.watch<SettingsController>();
    final colors = context.colors;
    final now = DateTime.now();
    final todayKey = dayKey(now);
    final active = store.jobs
        .where(
          (j) =>
              !j.archived &&
              (j.status == JobStatus.inProgress ||
                  j.status == JobStatus.waitingParts),
        )
        .toList();
    final dueToday = store.jobs
        .where(
          (j) =>
              !j.archived &&
              j.dueDate != null &&
              dayKey(j.dueDate!) == todayKey &&
              j.status != JobStatus.closed,
        )
        .toList();
    final newJobs = store.jobs
        .where((j) => !j.archived && j.status == JobStatus.nuevo)
        .toList();
    final dueRems = store.dueReminders();
    final lowStock = store.lowStockItems();
    final recurringDue = store.recurringPayments
        .where((p) => p.active && !p.nextDueAt.isAfter(DateTime.now()))
        .toList();
    final unpaid = store.jobs
        .where(
          (j) =>
              !j.archived &&
              j.status != JobStatus.closed &&
              store.paidForJob(j.id) < j.priceCents,
        )
        .toList();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Сегодня'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _quickAdd,
              child: const Icon(CupertinoIcons.plus, semanticLabel: 'Добавить'),
            ),
            const SizedBox(width: 2),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _openQuickMoney(context),
              child: Text(
                moneySymbol,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;
            if (active.isEmpty &&
                dueToday.isEmpty &&
                newJobs.isEmpty &&
                dueRems.isEmpty &&
                lowStock.isEmpty &&
                recurringDue.isEmpty &&
                unpaid.isEmpty) {
              return EmptyState(
                title: 'Всё спокойно',
                message:
                    'Нет активных заказов. Нажмите +, чтобы создать новый.',
                art: Icon(
                  CupertinoIcons.sun_max,
                  size: 48,
                  color: colors.tertiaryLabel,
                ),
                actions: [
                  PrimaryButton(
                    label: 'Начать: создать первый заказ',
                    icon: CupertinoIcons.plus,
                    onPressed: _quickAdd,
                  ),
                ],
              );
            }
            Widget buildSection(String title, List<Job> jobs) {
              if (jobs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel(title),
                  _jobListCard(context, store, jobs, colors),
                  const SizedBox(height: 16),
                ],
              );
            }

            if (!isLandscape) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
                children: [
                  _buildTodayTimerCard(store, context),
                  const SizedBox(height: 10),
                  _buildMonthCard(store, context),
                  const SizedBox(height: 10),
                  if (settings.taxRadarEnabled && settings.npdLimitApplies) ...[
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
                      child: TaxRadarBar(
                        compact: true,
                        incomeCents: store.annualIncomeCents(),
                        limitCents: settings.taxIncomeLimitCents,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _buildSummaryCards(store, colors),
                  const SizedBox(height: 16),
                  buildSection('В работе', active),
                  buildSection('Срок сегодня', dueToday),
                  buildSection('Новые', newJobs),
                  if (lowStock.isNotEmpty) ...[
                    SectionLabel('Низкий остаток'),
                    _stockCard(lowStock, colors),
                    const SizedBox(height: 16),
                  ],
                  if (recurringDue.isNotEmpty) ...[
                    SectionLabel('Регулярные платежи'),
                    _recurringCard(recurringDue, colors),
                    const SizedBox(height: 16),
                  ],
                  if (unpaid.isNotEmpty) buildSection('К оплате', unpaid),
                  if (dueRems.isNotEmpty) ...[
                    SectionLabel('Напоминания'),
                    ...dueRems.map(
                      (r) => _reminderCard(context, store, r, colors),
                    ),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 72),
                    children: [buildSection('В работе', active)],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 12, 16, 72),
                    children: [
                      buildSection('Срок сегодня', dueToday),
                      buildSection('Новые', newJobs),
                      if (dueRems.isNotEmpty) ...[
                        SectionLabel('Напоминания'),
                        ...dueRems.map(
                          (r) => _reminderCard(context, store, r, colors),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// «+ Заказ» на «Сегодня»: шит быстрого заказа (§Э1.1).
  ///
  /// Пустая база клиентов больше не блокирует создание — шит умеет завести
  /// клиента по имени, иначе путь «встретил клиента → записал заказ»
  /// разваливался ровно на первом клиенте.
  Future<void> _quickAdd() async {
    final store = context.read<MastersStore>();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _QuickOrderSheet(clients: store.clients),
    );
  }

  Widget _reminderCard(
    BuildContext context,
    MastersStore store,
    ClientReminder reminder,
    AppColors colors,
  ) {
    final client = store.clientById(reminder.clientId);
    final name = (client?.name.trim().isNotEmpty ?? false)
        ? client!.name.trim()
        : 'Клиент';
    final phone = client?.phone.trim() ?? '';
    final hasPhone = phone.isNotEmpty;
    final job = reminder.jobId == null ? null : store.jobById(reminder.jobId!);
    final message = _reminderMessage(reminder, name, job);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasPhone ? '$name · $phone' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryLabel,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(34, 34),
                  onPressed: () =>
                      store.setReminderStatus(reminder.id, ReminderStatus.done),
                  child: Icon(
                    CupertinoIcons.checkmark_circle,
                    size: 22,
                    color: colors.green,
                    semanticLabel: 'Выполнено',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                color: colors.secondaryLabel,
                fontSize: 12.5,
                height: 1.25,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            if (hasPhone)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChipButton(
                    label: 'WhatsApp',
                    icon: CupertinoIcons.chat_bubble,
                    color: colors.green,
                    onPressed: () async {
                      try {
                        await DeepLinkService.openWhatsApp(
                          phone: phone,
                          text: message,
                        );
                        await store.setReminderStatus(
                          reminder.id,
                          ReminderStatus.done,
                        );
                      } catch (_) {
                        // Platform launch errors are expected on web/simulator.
                      }
                    },
                  ),
                  ChipButton(
                    label: 'SMS',
                    icon: CupertinoIcons.chat_bubble_text,
                    onPressed: () async {
                      try {
                        await DeepLinkService.openSms(phone, message);
                        await store.setReminderStatus(
                          reminder.id,
                          ReminderStatus.done,
                        );
                      } catch (_) {
                        // Platform launch errors are expected on web/simulator.
                      }
                    },
                  ),
                ],
              )
            else
              Text(
                'Телефон не указан',
                style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(MastersStore store, AppColors colors) {
    final debt = store.clients.fold(
      0,
      (s, c) => s + store.clientDebtCents(c.id),
    );
    final lowStock = store.lowStockItems().length;
    final recurringDue = store.recurringPayments
        .where((p) => p.active && !p.nextDueAt.isAfter(DateTime.now()))
        .length;
    final attention = lowStock + recurringDue;
    final activeJobs = store.jobs
        .where((j) => !j.archived && j.status != JobStatus.closed)
        .length;
    final balance = store.totalBalanceCents();

    final jobsWord = ordersWord(activeJobs);
    final issuesWord = pluralRu(attention, ['повод', 'повода', 'поводов']);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyValueRow(
            'Свободно',
            _money(balance),
            valueColor: balance < 0 ? colors.red : colors.green,
            emphasis: true,
            dense: true,
          ),
          KeyValueRow(
            'Должны мне',
            _money(debt),
            valueColor: debt > 0 ? colors.orange : null,
            dense: true,
          ),
          KeyValueRow('В работе', '$activeJobs · $jobsWord', dense: true),
          KeyValueRow(
            'Требует внимания',
            attention == 0 ? 'Нет' : '$attention · $issuesWord',
            valueColor: attention > 0 ? colors.red : null,
            dense: true,
          ),
        ],
      ),
    );
  }

  /// Одна карточка на всю секцию: строки разделены волосяными линиями,
  /// поэтому список не превращается в стопку одинаковых плиток.
  Widget _jobListCard(
    BuildContext context,
    MastersStore store,
    List<Job> jobs,
    AppColors colors,
  ) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < jobs.length; i++) ...[
            if (i > 0) const Hairline(indent: 12),
            _jobRow(context, store, jobs[i], colors),
          ],
        ],
      ),
    );
  }

  Widget _jobRow(
    BuildContext context,
    MastersStore store,
    Job job,
    AppColors colors,
  ) {
    final client = store.clientById(job.clientId);
    final totalMin = store.totalMinutesForJob(job.id);
    final subtitle = [
      client?.name ?? 'Без клиента',
      if (job.dueDate != null) formatFullDate(job.dueDate!),
      if (totalMin > 0) formatMinutes(totalMin),
    ].join(' • ');

    // Pill низкой маржи (§Э1.3): показываем прямо в списке, чтобы мастер
    // заметил сигнал до перехода в карточку заказа.
    final lowMargin = store.isLowMarginJob(job.id);
    final trailing = lowMargin
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Pill('низкая маржа', color: colors.orange,
                  icon: CupertinoIcons.exclamationmark_triangle),
              const SizedBox(width: 6),
              Pill(job.status.label, color: colors.accent),
            ],
          )
        : Pill(job.status.label, color: colors.accent);

    return ListRow(
      title: job.title,
      subtitle: subtitle,
      dense: true,
      showChevron: true,
      trailing: trailing,
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => JobDetailScreen(jobId: job.id)),
      ),
    );
  }
}

String _money(int cents) => money(cents);
String _hms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '$h ч $m мин';
  return '$m мин $s с';
}

Widget _legendDot(AppColors colors, Color dot, String label) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
    ),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(color: colors.secondaryLabel, fontSize: 12)),
  ],
);

/// Компактный список низкого остатка: одна карточка вместо стопки плиток.
Widget _stockCard(List<InventoryItem> items, AppColors colors) {
  return AppCard(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Hairline(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.cube,
                  size: 15,
                  color: colors.secondaryLabel,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${items[i].stockQty.toStringAsFixed(items[i].stockQty % 1 == 0 ? 0 : 2)} ${items[i].unit}',
                  style: TextStyle(
                    color: colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

/// Компактный список регулярных платежей к оплате.
Widget _recurringCard(List<RecurringPayment> payments, AppColors colors) {
  return AppCard(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
    child: Column(
      children: [
        for (var i = 0; i < payments.length; i++) ...[
          if (i > 0) const Hairline(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    payments[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _money(payments[i].amountCents),
                  style: TextStyle(
                    color: colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _buildTodayTimerCard(MastersStore store, BuildContext context) {
  final colors = context.colors;
  final open = store.openWorkSession;
  final todaySeconds = store.workSecondsToday();
  final running = open != null;

  return AppCard(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              running ? CupertinoIcons.timer : CupertinoIcons.clock,
              size: 16,
              color: running ? colors.green : colors.secondaryLabel,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                running ? 'Смена идёт' : 'Смена закрыта',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
            if (running)
              Text(
                _hms(store.workSeconds(open)),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: colors.green,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (running) ...[
          Text(
            open.jobId == null
                ? 'Без привязки к заказу'
                : (store.jobById(open.jobId!)?.title ?? 'Заказ удалён'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Стоп',
                  icon: CupertinoIcons.stop,
                  dense: true,
                  onPressed: () => store.stopWorkSession(open.id),
                ),
              ),
            ],
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Начать смену',
                  icon: CupertinoIcons.play,
                  dense: true,
                  onPressed: () => _pickJobAndStart(context),
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        KeyValueRow('Сегодня наработано', _hms(todaySeconds), dense: true),
      ],
    ),
  );
}

Future<void> _pickJobAndStart(BuildContext context) async {
  final store = context.read<MastersStore>();
  final activeJobs = store.jobs.where((j) => !j.archived).toList();
  if (activeJobs.isEmpty) {
    await store.startWorkSession(jobId: null);
    return;
  }
  final choice = await showCupertinoModalPopup<String?>(
    context: context,
    builder: (dialogContext) => CupertinoActionSheet(
      title: const Text('Начать отсчет'),
      message: const Text('Выберите заказ или начните без привязки к заказу.'),
      actions: [
        for (final job in activeJobs)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(job.id),
            child: Text(job.title),
          ),
        CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop('__none__'),
          child: const Text('Без заказа'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(dialogContext).pop(null),
        child: const Text('Отмена'),
      ),
    ),
  );
  if (choice == null) return;
  await store.startWorkSession(jobId: choice == '__none__' ? null : choice);
}

Future<void> _openQuickMoney(BuildContext context) async {
  final store = context.read<MastersStore>();
  final accounts = store.accounts.where((a) => !a.archived).toList();
  if (accounts.isEmpty) {
    await showAppAlert(
      context,
      title: 'Нет счетов',
      message: 'Сначала добавьте счёт.',
    );
    return;
  }
  final kind = await showCupertinoModalPopup<String?>(
    context: context,
    builder: (dialogContext) => CupertinoActionSheet(
      title: const Text('Быстрые деньги'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop('sale'),
          child: const Text('Продажа / доход'),
        ),
        CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop('expense'),
          child: const Text('Расход'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(dialogContext).pop(null),
        child: const Text('Отмена'),
      ),
    ),
  );
  if (kind == null) return;
  final isIncome = kind == 'sale';
  String? selectedId = accounts.first.id;
  final amountController = TextEditingController();
  final ok = await showCupertinoModalPopup<bool?>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setSheetState) => CupertinoAlertDialog(
        title: Text(isIncome ? 'Продажа / доход' : 'Расход'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoTextField(
              controller: amountController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              placeholder: 'Сумма',
            ),
            const SizedBox(height: 10),
            ...accounts.map(
              (a) => CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setSheetState(() => selectedId = a.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selectedId == a.id
                          ? context.colors.accent
                          : context.colors.tertiaryLabel,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: selectedId == a.id
                        ? context.colors.accent.withValues(alpha: 0.10)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selectedId == a.id)
                        const Icon(
                          CupertinoIcons.checkmark,
                          size: 14,
                          color: CupertinoColors.activeBlue,
                        ),
                      Text(a.name),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Готово'),
            isDefaultAction: true,
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final amount =
      ((double.tryParse(amountController.text.trim().replaceAll(',', '.')) ??
                  0) *
              100)
          .round();
  if (amount <= 0 || selectedId == null) return;
  final accountId = selectedId!;
  try {
    await store.addTransaction(
      accountId: accountId,
      kind: isIncome ? 'sale' : 'expense',
      direction: isIncome ? 'in' : 'out',
      amountCents: amount,
      category: isIncome ? 'Продажа' : '',
    );
  } catch (e) {
    await showAppAlert(context, title: 'Ошибка', message: e.toString());
  }
}

Widget _buildMonthCard(MastersStore store, BuildContext context) {
  final colors = context.colors;
  final settings = context.watch<SettingsController>();
  final now = DateTime.now();
  final tx = store.moneyTransactions
      .where(
        (t) =>
            !t.voided &&
            t.createdAt.year == now.year &&
            t.createdAt.month == now.month,
      )
      .toList();
  final income = tx
      .where((t) => t.direction == 'in')
      .fold(0, (s, t) => s + t.amountCents);
  final expense = tx
      .where((t) => t.direction == 'out')
      .fold(0, (s, t) => s + t.amountCents);
  final taxRate = settings.getActiveTaxRate();
  final taxReserve = taxRate > 0 ? (income * taxRate / 100).round() : 0;
  final profit = income - expense - taxReserve;
  final weekStart = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 6));
  final weekTx = store.moneyTransactions
      .where((t) => !t.voided && !t.createdAt.isBefore(weekStart))
      .toList();
  final weekIncome = weekTx
      .where((t) => t.direction == 'in')
      .fold(0, (s, t) => s + t.amountCents);
  final weekExpense = weekTx
      .where((t) => t.direction == 'out')
      .fold(0, (s, t) => s + t.amountCents);
  final weekProfit = weekIncome - weekExpense;
  final activeProfile = settings.activeTaxProfile;

  return AppCard(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    onTap: () =>
        Navigator.of(context)
            .push(CupertinoPageRoute(builder: (_) => const StatsScreen())),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Сводка',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            _legendDot(colors, colors.green, 'Доходы'),
            const SizedBox(width: 10),
            _legendDot(colors, colors.red, 'Расходы'),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: colors.tertiaryLabel,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _DonutRing(
                income: income,
                expense: expense,
                profit: profit,
                label: 'Месяц',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DonutRing(
                income: weekIncome,
                expense: weekExpense,
                profit: weekProfit,
                label: '7 дней',
              ),
            ),
          ],
        ),
        if (taxRate > 0) ...[
          const SizedBox(height: 8),
          const Hairline(),
          const SizedBox(height: 6),
          KeyValueRow(
            'Налоговый резерв${activeProfile != null ? ' (${activeProfile.country})' : ''}',
            '${_money(taxReserve)} · $taxRate%',
            dense: true,
          ),
        ],
      ],
    ),
  );
}

class _DonutRing extends StatelessWidget {
  const _DonutRing({
    required this.income,
    required this.expense,
    required this.profit,
    required this.label,
  });

  final int income;
  final int expense;
  final int profit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final empty = income + expense <= 0;
    final centerText = empty
        ? '—'
        : (profit >= 0 ? '+${_money(profit)}' : '−${_money(-profit)}');
    final centerStyle = empty
        ? TextStyle(
            color: colors.secondaryLabel,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          )
        : TextStyle(
            color: profit >= 0 ? colors.green : colors.red,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          );
    return Center(
      child: Column(
        children: [
          SizedBox(
            height: 92,
            width: 92,
            child: CustomPaint(
              painter: _DonutRingPainter(
                income: income,
                expense: expense,
                incomeColor: colors.green,
                expenseColor: colors.red,
                trackColor: colors.separator,
                empty: empty,
              ),
              child: Center(
                child: Text(
                  centerText,
                  style: centerStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: colors.secondaryLabel, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DonutRingPainter extends CustomPainter {
  const _DonutRingPainter({
    required this.income,
    required this.expense,
    required this.incomeColor,
    required this.expenseColor,
    required this.trackColor,
    required this.empty,
  });

  final int income;
  final int expense;
  final Color incomeColor;
  final Color expenseColor;
  final Color trackColor;
  final bool empty;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1;
    final strokeWidth = radius * 0.28;
    final circleRadius = radius - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: circleRadius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    if (empty) {
      paint.color = trackColor;
      canvas.drawCircle(center, circleRadius, paint);
      return;
    }
    final total = income + expense;
    final start = -pi / 2;
    final incomeSweep = (income / total) * 2 * pi;
    if (incomeSweep > 0) {
      paint.color = incomeColor;
      canvas.drawArc(rect, start, incomeSweep, false, paint);
    }
    final expenseSweep = 2 * pi - incomeSweep;
    if (expenseSweep > 0) {
      paint.color = expenseColor;
      canvas.drawArc(rect, start + incomeSweep, expenseSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutRingPainter old) =>
      old.income != income ||
      old.expense != expense ||
      old.incomeColor != incomeColor ||
      old.expenseColor != expenseColor ||
      old.trackColor != trackColor ||
      old.empty != empty;
}

String _reminderMessage(ClientReminder reminder, String clientName, Job? job) {
  final detail = reminder.body?.trim();
  final jobTitle = job?.title.trim();
  final subject = (detail != null && detail.isNotEmpty)
      ? detail
      : reminder.title;
  switch (reminder.type) {
    case 'appointment':
      final label = (jobTitle != null && jobTitle.isNotEmpty)
          ? jobTitle
          : subject;
      return 'Здравствуйте, $clientName. Запись: $label.';
    case 'warranty':
      final label = (jobTitle != null && jobTitle.isNotEmpty)
          ? jobTitle
          : subject;
      return 'Здравствуйте, $clientName. Напоминаю о сервисном обслуживании по работе "$label".';
    default:
      return 'Здравствуйте, $clientName. Напоминаю: $subject.';
  }
}

/// Шит быстрого заказа (§Э1.1): клиент + название + одна строка.
///
/// Не отдельный экран, а модалка поверх «Сегодня»: заказ рождается с одной
/// строкой, остальное мастер добирает в карточке.
class _QuickOrderSheet extends StatefulWidget {
  const _QuickOrderSheet({required this.clients});

  final List<Client> clients;

  @override
  State<_QuickOrderSheet> createState() => _QuickOrderSheetState();
}

class _QuickOrderSheetState extends State<_QuickOrderSheet> {
  final _titleCtrl = TextEditingController();
  final _newClientCtrl = TextEditingController();
  final _lineNameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  /// Выбранный существующий клиент; `null` — создаём нового.
  String? _clientId;
  int _priceCents = 0;
  bool _saving = false;

  bool get _creatingClient => _newClientCtrl.text.trim().isNotEmpty;

  bool get _canSave =>
      !_saving &&
      _titleCtrl.text.trim().isNotEmpty &&
      (_creatingClient || _clientId != null);

  @override
  void initState() {
    super.initState();
    _clientId = widget.clients.isEmpty ? null : widget.clients.first.id;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _newClientCtrl.dispose();
    _lineNameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final store = context.read<MastersStore>();
    try {
      final title = _titleCtrl.text.trim();
      final clientId = _creatingClient
          ? (await store.createClient(name: _newClientCtrl.text)).id
          : _clientId!;
      final job = await store.createJob(clientId: clientId, title: title);

      // Строка опциональна: без цены заказ остаётся пустой заготовкой.
      final lineName = _lineNameCtrl.text.trim().isEmpty
          ? title
          : _lineNameCtrl.text.trim();
      if (_priceCents > 0) {
        await store.addMaterial(
          jobId: job.id,
          name: lineName,
          quantity: 1,
          priceCents: _priceCents,
          kind: 'work',
        );
        await store.recalcJobTotals(job.id);
      }

      if (!mounted) return;
      // Закрываем шит и сразу открываем карточку: там добавляются строки,
      // срок и детали, которые в быстрый заказ сознательно не брали.
      Navigator.of(context).pop();
      Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => JobDetailScreen(jobId: job.id)),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showAppAlert(
          context,
          title: 'Не получилось',
          message: 'Проверьте заполненные поля и попробуйте ещё раз.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        color: colors.card,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                    Text(
                      'Быстрый заказ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.label,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _canSave ? _save : null,
                      child: Text(
                        'Создать',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _canSave ? colors.accent : colors.tertiaryLabel,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SectionLabel('Клиент'),
              if (widget.clients.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.clients.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final client = widget.clients[i];
                      // Новое имя отменяет выбор: иначе непонятно, к какому
                      // клиенту уйдёт заказ.
                      final selected =
                          !_creatingClient && client.id == _clientId;
                      return CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _saving
                            ? null
                            : () {
                                _newClientCtrl.clear();
                                setState(() => _clientId = client.id);
                              },
                        child: ChipButton(
                          label: client.name.trim().isEmpty
                              ? 'Без имени'
                              : client.name.trim(),
                          color: selected ? colors.accent : colors.secondaryLabel,
                        ),
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: CupertinoTextField(
                  controller: _newClientCtrl,
                  placeholder: widget.clients.isEmpty
                      ? 'Имя нового клиента'
                      : '…или новый клиент по имени',
                  textCapitalization: TextCapitalization.words,
                  enabled: !_saving,
                  style: TextStyle(color: colors.label),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SectionLabel('Заказ'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: CupertinoTextField(
                  controller: _titleCtrl,
                  placeholder: 'Что делаем',
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  enabled: !_saving,
                  style: TextStyle(color: colors.label),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoTextField(
                        controller: _lineNameCtrl,
                        placeholder: 'Позиция (по названию заказа)',
                        textCapitalization: TextCapitalization.sentences,
                        enabled: !_saving,
                        style: TextStyle(color: colors.label),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 130,
                      child: CupertinoTextField(
                        controller: _priceCtrl,
                        placeholder: 'Цена, ${moneySymbol}',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        enabled: !_saving,
                        style: TextStyle(color: colors.label),
                        onChanged: (value) =>
                            setState(() => _priceCents = currentMoneyFormat.parse(value) ?? 0),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: PrimaryButton(
                  label: _saving ? 'Создаю…' : 'Создать заказ',
                  icon: CupertinoIcons.plus,
                  onPressed: _canSave ? _save : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
