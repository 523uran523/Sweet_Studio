import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/utils/app_utils.dart';
import '../../core/document_service.dart';
import '../../data/models/job.dart';
import '../../data/models/money_transaction.dart';
import '../../state/masters_store.dart';

import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/money_format.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String _periodLabel() => switch (_period) {
    0 => 'Неделя',
    1 => 'Месяц',
    2 => 'Квартал',
    _ => 'Месяц',
  };

  Future<void> _showPeriodPicker() async {
    final result = await showCupertinoModalPopup<int>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Период аналитики'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(0),
            isDefaultAction: _period == 0,
            child: const Text('Неделя'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(1),
            isDefaultAction: _period == 1,
            child: const Text('Месяц'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(2),
            isDefaultAction: _period == 2,
            child: const Text('Квартал'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (result != null && mounted) setState(() => _period = result);
  }

  int _period = 1; // 0 week, 1 month, 2 quarter
  String? _employeeFilter;
  String? _tagFilter;

  DateTime _start(DateTime now) {
    if (_period == 0) {
      return DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 7));
    }
    if (_period == 1) return DateTime(now.year, now.month, 1);
    // quarter
    final qMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    return DateTime(now.year, qMonth, 1);
  }

  Future<void> _exportXlsx(
    int revenue,
    int expense,
    int profit,
    int jobRevenue,
    int jobCost,
    int jobMargin,
    int completedCount,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['P&L'];
    sheet.appendRow([TextCellValue('Показатель'), TextCellValue('Значение')]);
    sheet.appendRow([
      TextCellValue('Выручка'),
      DoubleCellValue(revenue / 100.0),
    ]);
    sheet.appendRow([
      TextCellValue('Расходы'),
      DoubleCellValue(expense / 100.0),
    ]);
    sheet.appendRow([
      TextCellValue('Прибыль'),
      DoubleCellValue(profit / 100.0),
    ]);
    sheet.appendRow([
      TextCellValue('Выручка заказов'),
      DoubleCellValue(jobRevenue / 100.0),
    ]);
    sheet.appendRow([
      TextCellValue('Расход заказов'),
      DoubleCellValue(jobCost / 100.0),
    ]);
    sheet.appendRow([
      TextCellValue('Маржа заказов'),
      DoubleCellValue(jobMargin / 100.0),
    ]);
    sheet.appendRow([
      TextCellValue('Завершённых заказов'),
      IntCellValue(completedCount),
    ]);
    final bytes = excel.save();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/masters-pnl.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'P&L отчёт Masters'),
    );
  }

  Future<void> _exportPnlPdf(
    int revenue,
    int expense,
    int profit,
    int jobRevenue,
    int jobCost,
    int jobMargin,
    int completedCount,
    Map<String, int> incomeCats,
    Map<String, int> expenseCats,
  ) async {
    final bytes = await DocumentService.buildPnlPdf(
      revenue: revenue,
      expense: expense,
      profit: profit,
      jobRevenue: jobRevenue,
      jobCost: jobCost,
      jobMargin: jobMargin,
      completedCount: completedCount,
      incomeCats: incomeCats,
      expenseCats: expenseCats,
    );
    final ok = await DocumentService.savePdf(bytes, 'masters-pnl.pdf');
    if (mounted && ok) {
      await showAppAlert(context, title: 'Готово', message: 'P&L сохранён.');
    }
  }

  Duration _duration(DateTime start, DateTime end) => end.difference(start);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final now = DateTime.now();
    final start = _start(now);
    final prevStart = start.subtract(_duration(start, now));

    bool inRange(MoneyTransaction t) =>
        !t.voided && !t.createdAt.isBefore(start) && !t.createdAt.isAfter(now);
    bool inPrev(MoneyTransaction t) =>
        !t.voided &&
        !t.createdAt.isBefore(prevStart) &&
        t.createdAt.isBefore(start);

    final tx = store.moneyTransactions.where(inRange).toList();
    final txPrev = store.moneyTransactions.where(inPrev).toList();

    // §12.1: выручка учитывает отложенные суммы и возвраты заказов.
    final revenue = store.recognizedRevenueCents(start, now);
    final revenuePrev = store.recognizedRevenueCents(prevStart, start);
    bool isExpense(MoneyTransaction t) =>
        t.direction == 'out' && !t.isOrderRefund;
    final expense = tx
        .where(isExpense)
        .fold(0, (s, t) => s + t.amountCents);
    final expensePrev = txPrev
        .where(isExpense)
        .fold(0, (s, t) => s + t.amountCents);
    final profit = revenue - expense;
    final profitPrev = revenuePrev - expensePrev;

    final completedJobs = store.jobs.where((j) {
      if (j.archived) {
        return false;
      }
      final d = j.finishedAt ?? j.updatedAt;
      if (!(j.status == JobStatus.done || j.status == JobStatus.closed) ||
          d.isBefore(start) ||
          d.isAfter(now)) {
        return false;
      }
      if (_employeeFilter != null && j.assigneeId != _employeeFilter) {
        return false;
      }
      if (_tagFilter != null &&
          (_tagFilter!.isEmpty ||
              !(j.tags ?? '')
                  .split(',')
                  .map((e) => e.trim())
                  .contains(_tagFilter))) {
        return false;
      }
      return true;
    }).toList();
    final jobRevenue = completedJobs.fold(0, (s, j) => s + j.priceCents);
    final jobCost = completedJobs.fold(
      0,
      (s, j) => s + j.costCents + store.totalMaterialCents(j.id),
    );
    final jobMargin = jobRevenue - jobCost;

    final incomeCats = <String, int>{};
    for (final t in tx.where((t) => t.direction == 'in')) {
      final key = t.category.isEmpty ? 'Без категории' : t.category;
      incomeCats[key] = (incomeCats[key] ?? 0) + t.amountCents;
    }
    final expenseCats = <String, int>{};
    for (final t in tx.where(isExpense)) {
      final key = t.category.isEmpty ? 'Без категории' : t.category;
      expenseCats[key] = (expenseCats[key] ?? 0) + t.amountCents;
    }

    final topClients = <String, int>{};
    final topServices = <String, int>{};
    final expenseByAccount = <String, int>{};
    for (final j in completedJobs) {
      topClients[j.clientId] = (topClients[j.clientId] ?? 0) + j.priceCents;
    }
    final sortedClients = topClients.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final staffRevenue = <String, int>{};
    for (final j in completedJobs) {
      final key = j.assigneeId ?? 'unassigned';
      staffRevenue[key] = (staffRevenue[key] ?? 0) + j.priceCents;
    }
    final sortedStaff = staffRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final weekdayRevenue = List<int>.filled(7, 0);
    final weekdayExpense = List<int>.filled(7, 0);
    for (final t in tx) {
      final idx = t.createdAt.weekday - 1;
      if (t.direction == 'in') {
        weekdayRevenue[idx] += t.amountCents;
      } else if (t.direction == 'out') {
        weekdayExpense[idx] += t.amountCents;
      }
    }
    for (final j in completedJobs) {
      topServices[j.title] =
          (topServices[j.title] ?? 0) +
          (j.priceCents - j.costCents - store.totalMaterialCents(j.id));
    }
    final topServicesList = topServices.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final t in tx.where(isExpense)) {
      final acc = store.accountById(t.accountId);
      final label = acc?.name ?? (t.accountId.isEmpty ? 'Счёт' : t.accountId);
      expenseByAccount[label] = (expenseByAccount[label] ?? 0) + t.amountCents;
    }
    final expenseByAccountList = expenseByAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxTopClients = sortedClients.isEmpty
        ? 0
        : sortedClients.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxTopServices = topServicesList.isEmpty
        ? 0
        : topServicesList.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxTopStaff = sortedStaff.isEmpty
        ? 0
        : sortedStaff.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxTopAccounts = expenseByAccountList.isEmpty
        ? 0
        : expenseByAccountList
              .map((e) => e.value)
              .reduce((a, b) => a > b ? a : b);
    final periodTrend = _buildPeriodTrend(start, now, tx);
    final monthlyBuckets = _buildMonthlyBuckets(store.moneyTransactions, now);
    final weekdayProfit = List.generate(
      7,
      (i) => weekdayRevenue[i] - weekdayExpense[i],
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Итоги'),
        trailing: OverflowMenuButton(
          title: 'Период аналитики',
          icon: CupertinoIcons.calendar,
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => setState(() => _period = 0),
              child: const Text('Неделя'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => setState(() => _period = 1),
              child: const Text('Месяц'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => setState(() => _period = 2),
              child: const Text('Квартал'),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChipButton(
                  label: _periodLabel(),
                  icon: CupertinoIcons.calendar,
                  onPressed: _showPeriodPicker,
                ),
                ChipButton(
                  label: _employeeFilter == null
                      ? 'Все сотрудники'
                      : (store.employeeById(_employeeFilter!)?.name ??
                            'Сотрудник'),
                  icon: CupertinoIcons.person_2,
                  onPressed: () async {
                    final v = await showCupertinoModalPopup<String?>(
                      context: context,
                      builder: (dialogContext) => Container(
                        height: 260,
                        color: context.colors.card,
                        child: Column(
                          children: [
                            CupertinoButton(
                              child: const Text('Все сотрудники'),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop('__all__'),
                            ),
                            Expanded(
                              child: ListView(
                                children: [
                                  for (final e in store.employees)
                                    CupertinoButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(e.id),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(e.name),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (v == '__all__') {
                      setState(() => _employeeFilter = null);
                    } else if (v != null) {
                      setState(() => _employeeFilter = v);
                    }
                  },
                ),
                ChipButton(
                  label: _tagFilter ?? 'Все теги',
                  icon: CupertinoIcons.tag,
                  onPressed: () async {
                    final tags =
                        store.jobs
                            .expand(
                              (j) => (j.tags ?? '')
                                  .split(',')
                                  .map((e) => e.trim()),
                            )
                            .where((e) => e.isNotEmpty)
                            .toSet()
                            .toList()
                          ..sort();
                    if (tags.isEmpty) return;
                    final v = await showCupertinoModalPopup<String?>(
                      context: context,
                      builder: (dialogContext) => Container(
                        height: 260,
                        color: context.colors.card,
                        child: Column(
                          children: [
                            CupertinoButton(
                              child: const Text('Все теги'),
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop('__all__'),
                            ),
                            Expanded(
                              child: ListView(
                                children: [
                                  for (final t in tags)
                                    CupertinoButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(t),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(t),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (v == '__all__') {
                      setState(() => _tagFilter = null);
                    } else if (v != null) {
                      setState(() => _tagFilter = v);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Прибыль',
                    value: _money(profit),
                    icon: CupertinoIcons.chart_bar,
                    tint: profit < 0 ? colors.red : colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'Маржа заказов',
                    value: _money(jobMargin),
                    icon: CupertinoIcons.chart_pie,
                    tint: colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Завершено заказов',
                    value: '${completedJobs.length}',
                    icon: CupertinoIcons.doc_text,
                    tint: colors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'Наработано времени',
                    value: _minutes(completedJobs, store),
                    icon: CupertinoIcons.clock,
                    tint: colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                children: [
                  KeyValueRow(
                    'Предыдущий период',
                    _money(profitPrev),
                    dense: true,
                  ),
                  KeyValueRow(
                    'Изменение прибыли',
                    '${profit - profitPrev >= 0 ? '+' : '−'}'
                    '${_money((profit - profitPrev).abs())} '
                    '(${_pct(profit, profitPrev)})',
                    valueColor: profit - profitPrev >= 0
                        ? colors.green
                        : colors.red,
                    dense: true,
                  ),
                  const Hairline(),
                  KeyValueRow(
                    'Сумма заказов',
                    _money(jobRevenue),
                    dense: true,
                  ),
                  KeyValueRow(
                    'Себестоимость',
                    _money(jobCost),
                    dense: true,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChipButton(
                        label: 'Экспорт Excel',
                        icon: CupertinoIcons.doc_on_doc,
                        onPressed: () => _exportXlsx(
                          revenue,
                          expense,
                          profit,
                          jobRevenue,
                          jobCost,
                          jobMargin,
                          completedJobs.length,
                        ),
                      ),
                      ChipButton(
                        label: 'Экспорт PDF',
                        icon: CupertinoIcons.doc_text,
                        onPressed: () => _exportPnlPdf(
                          revenue,
                          expense,
                          profit,
                          jobRevenue,
                          jobCost,
                          jobMargin,
                          completedJobs.length,
                          incomeCats,
                          expenseCats,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Доходы и расходы',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: colors.label,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _monthlyChart(colors, monthlyBuckets),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Доходы по категориям'),
            _categoryCard(colors, incomeCats, colors.green),
            const SizedBox(height: 16),
            SectionLabel('Расходы по категориям'),
            _categoryCard(colors, expenseCats, colors.red),
            const SizedBox(height: 16),
            SectionLabel('Топ клиентов'),
            _barList(
              entries: sortedClients.take(8).toList(),
              labelOf: (key) => store.clientById(key)?.name ?? 'Клиент',
              max: maxTopClients,
              color: colors.accent,
              emptyTitle: 'Нет данных',
              emptyMessage: 'Завершите заказы, чтобы увидеть статистику.',
              emptyIcon: CupertinoIcons.chart_bar,
            ),
            const SizedBox(height: 16),
            SectionLabel('Маржа по заказам'),
            _barList(
              entries: topServicesList.take(5).toList(),
              labelOf: (key) => key,
              max: maxTopServices,
              color: colors.purple,
              emptyTitle: 'Нет завершённых заказов',
              emptyMessage: 'Маржа появится после закрытия заказа.',
              emptyIcon: CupertinoIcons.doc_text,
            ),
            const SizedBox(height: 16),
            SectionLabel('Расходы по счетам'),
            _barList(
              entries: expenseByAccountList.take(5).toList(),
              labelOf: (key) => key,
              max: maxTopAccounts,
              color: colors.red,
              emptyTitle: 'Нет расходов',
              emptyMessage: 'Расходы за выбранный период появятся здесь.',
              emptyIcon: CupertinoIcons.minus_circle,
            ),
            const SizedBox(height: 16),
            SectionLabel('Динамика периода'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: periodTrend.isEmpty
                  ? EmptyState(
                      title: 'Нет данных',
                      message: 'Данные за период появятся здесь.',
                      art: Icon(
                        CupertinoIcons.chart_bar,
                        size: 36,
                        color: colors.tertiaryLabel,
                      ),
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(child: SizedBox.shrink()),
                            SizedBox(
                              width: 76,
                              child: Text(
                                'Доход',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: colors.tertiaryLabel,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 76,
                              child: Text(
                                'Расход',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: colors.tertiaryLabel,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 82,
                              child: Text(
                                'Итог',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: colors.tertiaryLabel,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        for (final bucket in periodTrend)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    bucket.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    _money(bucket.revenue),
                                    style: TextStyle(
                                      color: colors.green,
                                      fontSize: 12,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    _money(bucket.expense),
                                    style: TextStyle(
                                      color: colors.red,
                                      fontSize: 12,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                SizedBox(
                                  width: 82,
                                  child: Text(
                                    _money(bucket.profit),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: bucket.profit >= 0
                                          ? colors.label
                                          : colors.red,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            SectionLabel('По сотрудникам'),
            _barList(
              entries: sortedStaff,
              labelOf: (key) => key == 'unassigned'
                  ? 'Без исполнителя'
                  : store.employeeById(key)?.name ?? key,
              max: maxTopStaff,
              color: colors.orange,
              emptyTitle: 'Нет данных',
              emptyMessage: 'Здесь появится разбор по исполнителям.',
              emptyIcon: CupertinoIcons.person_2,
            ),
            const SizedBox(height: 16),
            SectionLabel('По дням недели'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                children: List.generate(7, (i) {
                  final label = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][i];
                  final profit = weekdayProfit[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: colors.secondaryLabel.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor:
                                    weekdayProfit.reduce(
                                          (a, b) => a.abs() > b.abs()
                                              ? a.abs()
                                              : b.abs(),
                                        ) ==
                                        0
                                    ? 0.0
                                    : (profit.abs() /
                                              weekdayProfit.reduce(
                                                (a, b) => a.abs() > b.abs()
                                                    ? a.abs()
                                                    : b.abs(),
                                              ))
                                          .clamp(0.0, 1.0),
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: profit >= 0
                                        ? colors.green
                                        : colors.red,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 78,
                          child: Text(
                            _money(profit),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Секция «подпись — сумма — доля»: строки выровнены, значение прижато
  /// вправо, под графиком проходит полоса пропорции.
  Widget _barList({
    required List<MapEntry<String, int>> entries,
    required String Function(String key) labelOf,
    required int max,
    required Color color,
    required String emptyTitle,
    required String emptyMessage,
    required IconData emptyIcon,
  }) {
    if (entries.isEmpty) {
      return AppCard(
        child: EmptyState(
          title: emptyTitle,
          message: emptyMessage,
          art: Icon(emptyIcon, size: 36, color: context.colors.tertiaryLabel),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            KeyValueRow(
              labelOf(entries[i].key),
              _money(entries[i].value),
              dense: true,
            ),
            const SizedBox(height: 3),
            _proportionBar(
              entries[i].value.toDouble(),
              max == 0 ? 1.0 : max.toDouble(),
              color,
            ),
          ],
        ],
      ),
    );
  }

  String _money(int cents) => money(cents);

  String _minutes(List<Job> jobs, MastersStore store) {
    final total = jobs.fold(0, (s, j) => s + store.totalMinutesForJob(j.id));
    return formatMinutes(total);
  }

  String _pct(int current, int prev) {
    if (prev == 0) return current == 0 ? '0%' : '∞';
    final p = ((current - prev) / prev * 100).toStringAsFixed(1);
    return '$p%';
  }

  Widget _monthlyChart(AppColors colors, List<_MonthlyBucket> buckets) {
    final maxBar = buckets
        .expand((b) => [b.revenue, b.expense])
        .fold<int>(0, (a, v) => v > a ? v : a);
    final total = buckets.fold<int>(0, (s, b) => s + b.revenue + b.expense);
    if (total == 0 || maxBar == 0) {
      return EmptyState(
        title: 'Нет данных',
        message: 'Операции за последние 6 месяцев появятся здесь.',
        art: Icon(
          CupertinoIcons.chart_bar,
          size: 36,
          color: colors.tertiaryLabel,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 132,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: buckets.map((b) {
              final revH = b.revenue == 0
                  ? 0.0
                  : (b.revenue / maxBar * 108.0).clamp(4.0, 108.0);
              final expH = b.expense == 0
                  ? 0.0
                  : (b.expense / maxBar * 108.0).clamp(4.0, 108.0);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _shortMoney(b.revenue),
                            style: TextStyle(
                              fontSize: 8,
                              color: colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _shortMoney(b.expense),
                            style: TextStyle(
                              fontSize: 8,
                              color: colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: 10,
                            height: revH,
                            decoration: BoxDecoration(
                              color: colors.green,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Container(
                            width: 10,
                            height: expH,
                            decoration: BoxDecoration(
                              color: colors.red,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: buckets
              .map(
                (b) => Expanded(
                  child: Text(
                    b.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.secondaryLabel,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  String _shortMoney(int cents) {
    final v = cents / 100.0;
    if (v == 0) return '';
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  Widget _proportionBar(
    double value,
    double max,
    Color color, {
    double height = 7,
  }) {
    final ratio = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(height),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: constraints.maxWidth * ratio,
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _categoryCard(AppColors colors, Map<String, int> cats, Color tint) {
    if (cats.isEmpty) {
      return AppCard(
        child: EmptyState(
          title: 'Нет данных',
          message: 'Нет операций в периоде.',
          art: Icon(
            CupertinoIcons.chart_bar,
            size: 36,
            color: colors.tertiaryLabel,
          ),
        ),
      );
    }
    final max = cats.values.reduce((a, b) => a > b ? a : b);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        children: cats.entries.map((e) {
          final v = max == 0 ? 0.0 : e.value / max;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        e.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _money(e.value),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ProgressBar(value: v, color: tint, height: 5),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PeriodTrend {
  const _PeriodTrend({
    required this.label,
    required this.revenue,
    required this.expense,
  }) : profit = revenue - expense;

  final String label;
  final int revenue;
  final int expense;
  final int profit;
}

List<_PeriodTrend> _buildPeriodTrend(
  DateTime start,
  DateTime now,
  List<MoneyTransaction> tx,
) {
  if (now.difference(start).inDays <= 7) {
    const labels = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    return List.generate(7, (i) {
      final day = start.add(Duration(days: i));
      final expected = DateTime(day.year, day.month, day.day);
      final revenue = tx
          .where(
            (t) =>
                t.direction == 'in' &&
                DateTime(
                      t.createdAt.year,
                      t.createdAt.month,
                      t.createdAt.day,
                    ) ==
                    expected,
          )
          .fold(0, (s, t) => s + t.amountCents);
      final expense = tx
          .where(
            (t) =>
                t.direction == 'out' &&
                DateTime(
                      t.createdAt.year,
                      t.createdAt.month,
                      t.createdAt.day,
                    ) ==
                    expected,
          )
          .fold(0, (s, t) => s + t.amountCents);
      return _PeriodTrend(
        label: labels[(day.weekday - 1)].toUpperCase(),
        revenue: revenue,
        expense: expense,
      );
    });
  }

  if (now.difference(start).inDays <= 45) {
    final buckets = <_PeriodTrend>[];
    DateTime cursor = start;
    int index = 1;
    while (!cursor.isAfter(now)) {
      final next = cursor.add(const Duration(days: 7));
      final end = next.isAfter(now)
          ? now
          : next.subtract(const Duration(milliseconds: 1));
      final revenue = tx
          .where(
            (t) =>
                t.direction == 'in' &&
                !t.createdAt.isBefore(cursor) &&
                !t.createdAt.isAfter(end),
          )
          .fold(0, (s, t) => s + t.amountCents);
      final expense = tx
          .where(
            (t) =>
                t.direction == 'out' &&
                !t.createdAt.isBefore(cursor) &&
                !t.createdAt.isAfter(end),
          )
          .fold(0, (s, t) => s + t.amountCents);
      buckets.add(
        _PeriodTrend(label: 'Нед. $index', revenue: revenue, expense: expense),
      );
      cursor = next;
      index++;
      if (cursor.isAfter(now)) break;
    }
    return buckets;
  }

  const monthNames = [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
  final months = <int>[];
  for (int m = start.month; m <= now.month; m++) {
    months.add(m);
  }
  return months.map((month) {
    final bucketStart = DateTime(start.year, month, 1);
    final bucketEnd = DateTime(start.year, month + 1, 0, 23, 59, 59, 999);
    final revenue = tx
        .where(
          (t) =>
              t.direction == 'in' &&
              !t.createdAt.isBefore(bucketStart) &&
              !t.createdAt.isAfter(bucketEnd),
        )
        .fold(0, (s, t) => s + t.amountCents);
    final expense = tx
        .where(
          (t) =>
              t.direction == 'out' &&
              !t.createdAt.isBefore(bucketStart) &&
              !t.createdAt.isAfter(bucketEnd),
        )
        .fold(0, (s, t) => s + t.amountCents);
    return _PeriodTrend(
      label: monthNames[month - 1],
      revenue: revenue,
      expense: expense,
    );
  }).toList();
}

class _MonthlyBucket {
  const _MonthlyBucket({
    required this.label,
    required this.revenue,
    required this.expense,
  });

  final String label;
  final int revenue;
  final int expense;
}

List<_MonthlyBucket> _buildMonthlyBuckets(
  List<MoneyTransaction> transactions,
  DateTime now,
) {
  const monthLabels = [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
  final result = <_MonthlyBucket>[];
  for (int i = 5; i >= 0; i--) {
    final monthDate = DateTime(now.year, now.month - i, 1);
    final start = DateTime(monthDate.year, monthDate.month, 1);
    final end = DateTime(
      monthDate.year,
      monthDate.month + 1,
      0,
      23,
      59,
      59,
      999,
    );
    final revenue = transactions
        .where(
          (t) =>
              !t.voided &&
              t.direction == 'in' &&
              !t.createdAt.isBefore(start) &&
              !t.createdAt.isAfter(end),
        )
        .fold<int>(0, (s, t) => s + t.amountCents);
    final expense = transactions
        .where(
          (t) =>
              !t.voided &&
              t.direction == 'out' &&
              !t.createdAt.isBefore(start) &&
              !t.createdAt.isAfter(end),
        )
        .fold<int>(0, (s, t) => s + t.amountCents);
    result.add(
      _MonthlyBucket(
        label: monthLabels[monthDate.month - 1],
        revenue: revenue,
        expense: expense,
      ),
    );
  }
  return result;
}
