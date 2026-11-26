import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/document_service.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/accrual_entry.dart';
import '../../data/models/employee.dart';
import '../../data/models/payslip.dart';
import '../../data/models/recurring_payment.dart';
import '../../state/masters_store.dart';
import '../../core/money_format.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  bool _busy = false;
  String? _selectedEmployeeId;
  String _money(int cents) => money(cents);

  String _periodRange(PayrollPeriod period) =>
      '${DateFormat('dd.MM.yyyy', 'ru').format(period.startAt)} — '
      '${DateFormat('dd.MM.yyyy', 'ru').format(period.endAt)}';

  String _payslipStatus(Payslip slip) => slip.status == 'preliminary'
      ? 'Предварительно, требует сверки · версия ${slip.version}'
      : 'Подтверждено · версия ${slip.version}';

  String _percentLabel(double value) {
    final text = value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
    return text.replaceAll('.', ',');
  }

  String _accrualSource(MastersStore store, AccrualEntry entry) {
    final date = DateFormat('dd.MM.yyyy', 'ru').format(entry.occurredAt);
    if (entry.sourceKind == 'job') {
      final title = store.jobById(entry.sourceId)?.title.trim() ?? '';
      return title.isEmpty ? 'Заказ от $date' : 'Заказ «$title» от $date';
    }
    return 'Табель от $date';
  }

  String _accrualDetail(AccrualEntry entry) {
    final amount = money(entry.amountCents);
    final detail = switch (entry.accrualKind) {
      'hourly' => '${formatMinutes(entry.minutes)} × '
          '${money(entry.rateCents)}/ч',
      'piece' => '${money(entry.rateCents)} за заказ',
      'percent' => '${_percentLabel(entry.percent)} % от '
          '${money(entry.basisPriceCents)}',
      _ => '',
    };
    return detail.isEmpty ? amount : '$detail = $amount';
  }

  String _accrualLine(MastersStore store, AccrualEntry entry) {
    final review = entry.needsReview ? ' · требует сверки' : '';
    return '${_accrualSource(store, entry)} — ${_accrualDetail(entry)}$review';
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<String?> _prompt(
    String title,
    String placeholder, {
    String initial = '',
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) async {
    final controller = TextEditingController(text: initial);
    return showCupertinoDialog<String?>(
      context: context,
      builder: (dc) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            textCapitalization: textCapitalization,
            autofocus: true,
            decoration: BoxDecoration(
              color: context.colors.card,
              border: Border.all(color: context.colors.separator),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dc).pop(),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dc).pop(controller.text.trim()),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  Future<void> _newEmployee() async {
    final name = await _prompt(
      'Имя сотрудника',
      'Иван',
      textCapitalization: TextCapitalization.words,
    );
    if (name == null || name.trim().isEmpty) return;
    final payType = await _pickPayType();
    if (payType == null) return;
    final rateStr = await _prompt('Ставка ($moneySymbol/ч или за услугу)', '0') ?? '0';
    final percentStr = await _prompt('Процент от выручки', '0') ?? '0';
    final rate = ((double.tryParse(rateStr.replaceAll(',', '.')) ?? 0) * 100)
        .round();
    final percent = double.tryParse(percentStr.replaceAll(',', '.')) ?? 0;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<MastersStore>().createEmployee(
        name: name.trim(),
        payType: payType,
        rateCents: rate,
        percent: percent,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickPayType() async {
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 260,
        color: context.colors.card,
        child: Column(
          children: [
            CupertinoButton(
              child: const Text('Почасовая'),
              onPressed: () => Navigator.of(ctx).pop('hourly'),
            ),
            CupertinoButton(
              child: const Text('Сдельная (за услугу)'),
              onPressed: () => Navigator.of(ctx).pop('piece'),
            ),
            CupertinoButton(
              child: const Text('Процент от выручки'),
              onPressed: () => Navigator.of(ctx).pop('percent'),
            ),
            CupertinoButton(
              child: const Text('Оклад'),
              onPressed: () => Navigator.of(ctx).pop('salary'),
            ),
            CupertinoButton(
              child: const Text('Смешанная'),
              onPressed: () => Navigator.of(ctx).pop('mixed'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTime(String employeeId) async {
    final hoursStr = await _prompt('Часы работы', '8');
    final hours = double.tryParse((hoursStr ?? '').replaceAll(',', '.'));
    if (hours == null || hours <= 0) return;
    final note = await _prompt('Заметка', '');
    if (!mounted) return;
    final now = DateTime.now();
    setState(() => _busy = true);
    try {
      await context.read<MastersStore>().addTimeEntry(
        employeeId: employeeId,
        startedAt: now.subtract(Duration(minutes: (hours * 60).round())),
        endedAt: now,
        minutes: (hours * 60).round(),
        note: note,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPayment(String employeeId, String type, String label) async {
    final amountStr = await _prompt(label, '0');
    final amount =
        ((double.tryParse((amountStr ?? '').replaceAll(',', '.')) ?? 0) * 100)
            .round();
    if (amount <= 0) return;
    final note = await _prompt('Заметка', '');
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<MastersStore>().addEmployeePayment(
        employeeId: employeeId,
        type: type,
        amountCents: amount,
        note: note,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportEmployeePayslip(
    Employee employee,
    PayrollPeriod? period,
  ) async {
    final store = context.read<MastersStore>();
    final now = DateTime.now();
    final DateTime start;
    final DateTime end;
    final String title;
    if (period == null) {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
      title =
          'Расчётный листок: ${employee.name} • ${DateFormat('MMMM yyyy', 'ru').format(now)}';
    } else {
      start = period.startAt;
      end = period.endAt;
      title = 'Расчётный листок: ${employee.name} • ${period.name}';
    }
    final range =
        '${DateFormat('dd.MM.yyyy', 'ru').format(start)} — '
        '${DateFormat('dd.MM.yyyy', 'ru').format(end)}';

    // Закрытый период читаем из ведомости, а не пересчитываем: ставка могла
    // измениться после закрытия, и «уже закрытый час» не должен менять сумму.
    final history = period == null
        ? const <Payslip>[]
        : store.payslipHistoryForPeriod(period.id);
    final stored = period != null && period.isClosed
        ? store.latestPayslipFor(period.id, employee.id)
        : null;

    setState(() => _busy = true);
    try {
      final int earned;
      final int bonuses;
      final int penalties;
      final int advances;
      final int payouts;
      final int net;
      final int minutes;
      final String status;

      if (stored != null) {
        earned = stored.accruedCents;
        bonuses = stored.bonusCents;
        penalties = stored.penaltyCents;
        advances = stored.advanceCents;
        payouts = stored.payoutCents;
        net = stored.netCents;
        minutes = stored.minutes;
        status = _payslipStatus(stored);
      } else {
        final live = store.previewAccrualLines(employee.id, start, end);
        final totals = store.paymentTotalsForPeriod(employee.id, start, end);
        earned = live.fold<int>(0, (sum, line) => sum + line.amountCents);
        bonuses = totals['bonus'] ?? 0;
        penalties = totals['penalty'] ?? 0;
        advances = totals['advance'] ?? 0;
        payouts = totals['payout'] ?? 0;
        net = earned + bonuses - penalties - advances - payouts;
        minutes = live.fold<int>(0, (sum, line) => sum + line.minutes);
        if (period != null && period.isClosed) {
          status = 'Ведомость не найдена — расчёт вживую, предварительно';
        } else if (history.isNotEmpty) {
          status = 'Период переоткрыт — расчёт вживую, предварительно '
              '(в истории ${history.length} верс.)';
        } else {
          status = 'Период не закрыт — предварительный расчёт';
        }
      }

      final lines = <String>[
        'Сотрудник: ${employee.name}',
        'Период: $range',
        'Статус: $status',
        'Отработано: ${formatMinutes(minutes)}',
        'Заработано: ${money(earned)}',
        'Бонусы: ${money(bonuses)}',
        'Штрафы: ${money(penalties)}',
        'Авансы: ${money(advances)}',
        'Выплаты: ${money(payouts)}',
        'К выплате: ${money(net)}',
      ];

      if (stored != null) {
        if (stored.reviewNote != null &&
            stored.reviewNote!.trim().isNotEmpty) {
          lines
            ..add('Примечание: ${stored.reviewNote!.trim()}')
            ..add('');
        } else {
          lines.add('');
        }
        lines.add('Расшифровка начислений (сохранена при закрытии):');
        final entries = await store.accrualEntriesForPayslip(stored.id);
        if (entries.isEmpty) {
          lines.add('  Строк начислений нет.');
        } else {
          for (final entry in entries) {
            lines.add('  ${_accrualLine(store, entry)}');
          }
        }
      } else {
        lines
          ..add('')
          ..add(
            'Расшифровка станет доступна после закрытия периода: '
            'строки начислений фиксируются вместе с ведомостью.',
          );
      }

      final bytes = await DocumentService.buildEmployeePayslipPdf(
        title: title,
        lines: lines,
      );
      final versionSuffix = stored == null ? '' : '-v${stored.version}';
      final suggested =
          'payslip-${employee.id.substring(0, 6)}-${start.year}-${start.month}$versionSuffix.pdf';
      final ok = await DocumentService.savePdf(bytes, suggested);
      if (mounted && ok) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: stored == null
              ? 'Листок сохранён как предварительный.'
              : 'Листок сохранён: версия ${stored.version}.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPayslipPeriod(Employee employee) async {
    final store = context.read<MastersStore>();
    final periods = store.payrollPeriods.take(8).toList();
    if (periods.isEmpty) {
      await _exportEmployeePayslip(employee, null);
      return;
    }
    String periodLabel(PayrollPeriod period) {
      if (!period.isClosed) {
        return '${period.name} · открыт, предварительно';
      }
      final slips = store.payslipsForPeriod(period.id);
      if (slips.isEmpty) return '${period.name} · закрыт, ведомостей нет';
      var version = 0;
      for (final slip in slips) {
        if (slip.version > version) version = slip.version;
      }
      final preliminary = slips
          .where((slip) => slip.status == 'preliminary')
          .length;
      final status = preliminary > 0
          ? 'предварительно: $preliminary'
          : 'подтверждено';
      return '${period.name} · закрыт, v$version, $status';
    }

    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Выберите период'),
        message: const Text(
          'Закрытый период печатается из сохранённой ведомости. '
          'Открытый — предварительный расчёт вживую.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop('current'),
            child: const Text('Текущий месяц · предварительно'),
          ),
          for (final period in periods)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(dialogContext).pop(period.id),
              child: Text(periodLabel(period)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Отмена'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
    if (!mounted) return;
    if (selected == null) return;
    if (selected == 'current') {
      await _exportEmployeePayslip(employee, null);
    } else {
      final period = store.payrollPeriods.firstWhere(
        (p) => p.id == selected,
        orElse: () => store.payrollPeriods.first,
      );
      await _exportEmployeePayslip(employee, period);
    }
  }

  Future<void> _exportPayroll() async {
    final store = context.read<MastersStore>();
    final now = DateTime.now();
    // Если текущий месяц уже оформлен периодом, печатаем его: закрытый —
    // из ведомостей, открытый — вживую. Иначе сводка за месяц вживую.
    for (final period in store.payrollPeriods) {
      if (!now.isBefore(period.startAt) && !now.isAfter(period.endAt)) {
        await _exportPayrollPeriod(period);
        return;
      }
    }

    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    setState(() => _busy = true);
    try {
      final summary = store.payrollSummary(start, end);
      final rows = summary
          .map(
            (r) => <String, Object?>{
              'employeeName':
                  (r['employee'] as dynamic)?.name?.toString() ?? 'Сотрудник',
              'earned': r['earned'],
              'bonus': r['bonus'],
              'penalty': r['penalty'],
              'advance': r['advance'],
              'payout': r['payout'],
              'net': r['net'],
              'status': 'Предв. · вживую',
            },
          )
          .toList();
      final bytes = await DocumentService.buildPayrollPdf(
        title: 'Ведомость: ${DateFormat('MMMM yyyy', 'ru').format(now)}',
        subtitle: 'Период не закрыт: суммы пересчитаны вживую и являются '
            'предварительными.',
        summary: rows,
      );
      final ok = await DocumentService.savePdf(
        bytes,
        'payroll-${now.year}-${now.month}.pdf',
      );
      if (mounted && ok) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: 'Предварительная ведомость сохранена.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeCurrentPayrollPeriod() async {
    final store = context.read<MastersStore>();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    PayrollPeriod? current;
    for (final period in store.payrollPeriods) {
      if (!now.isBefore(period.startAt) && !now.isAfter(period.endAt)) {
        current = period;
        break;
      }
    }
    if (current != null && current.isClosed) {
      await showAppAlert(
        context,
        title: 'Месяц уже закрыт',
        message: 'Чтобы пересчитать суммы, переоткройте период в разделе '
            '«Периоды выплат» — причина попадёт в аудит.',
      );
      return;
    }
    final ok = await showAppConfirm(
      context,
      title: current == null ? 'Закрыть текущий месяц?' : 'Закрыть период?',
      message: 'Суммы будут зафиксированы в ведомостях. Изменение после '
          'закрытия — только через переоткрытие с причиной.',
      confirmLabel: 'Закрыть',
    );
    if (!ok) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final period =
          current ??
          await store.createPayrollPeriod(
            name: 'Месяц ${now.month}/${now.year}',
            startAt: start,
            endAt: end,
          );
      final slips = await store.closePayrollPeriod(period.id, at: now);
      if (!mounted) return;
      final preliminary = slips
          .where((slip) => slip.status == 'preliminary')
          .length;
      await showAppAlert(
        context,
        title: 'Период закрыт',
        message: slips.isEmpty
            ? 'Активных сотрудников нет — ведомости не созданы.'
            : preliminary > 0
            ? 'Предварительных ведомостей: $preliminary из ${slips.length}. '
                  'Проверьте суммы и подтвердите их в «Периодах».'
            : 'Ведомости зафиксированы. Для экспорта используйте кнопку PDF.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPayrollPeriod(PayrollPeriod period) async {
    final store = context.read<MastersStore>();
    setState(() => _busy = true);
    try {
      final summary = store.payrollSummaryForPeriod(period);
      final slips = store.payslipsForPeriod(period.id);
      var version = 0;
      for (final slip in slips) {
        if (slip.version > version) version = slip.version;
      }
      final preliminary = slips
          .where((slip) => slip.status == 'preliminary')
          .length;
      final rows = summary
          .map(
            (r) {
              final slip = r['payslip'] as Payslip?;
              final employee = r['employee'] as Employee?;
              return <String, Object?>{
                'employeeName': employee?.name ?? 'Сотрудник',
                'earned': r['earned'],
                'bonus': r['bonus'],
                'penalty': r['penalty'],
                'advance': r['advance'],
                'payout': r['payout'],
                'net': r['net'],
                'status': slip == null
                    ? (period.isClosed ? 'Нет ведомости' : null)
                    : slip.status == 'preliminary'
                    ? 'Предв. · v${slip.version}'
                    : 'Подтв. · v${slip.version}',
              };
            },
          )
          .toList();
      final String subtitle;
      if (!period.isClosed) {
        subtitle = 'Период не закрыт: суммы пересчитаны вживую и являются '
            'предварительными.';
      } else if (slips.isEmpty) {
        subtitle = 'Ведомости не найдены: суммы пересчитаны вживую и требуют '
            'сверки.';
      } else if (preliminary > 0) {
        subtitle = 'Ведомости: ${slips.length}, версия $version. '
            'Предварительных: $preliminary — требуется сверка и подтверждение.';
      } else {
        subtitle = 'Ведомости: ${slips.length}, версия $version. '
            'Все подтверждены.';
      }
      final bytes = await DocumentService.buildPayrollPdf(
        title: 'Ведомость: ${period.name}',
        subtitle: subtitle,
        summary: rows,
      );
      final suggested = 'payroll-${period.id.substring(0, 6)}.pdf';
      final ok = await DocumentService.savePdf(bytes, suggested);
      if (mounted && ok) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: preliminary > 0
              ? 'Ведомость сохранена. Предварительных: $preliminary.'
              : 'Ведомость сохранена.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showEmployeeActions() async {
    final choice = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Дополнительно'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('periods'),
            child: const Text('Периоды'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('closePeriod'),
            child: const Text('Закрыть период'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (choice == 'periods') {
      await _managePayrollPeriods();
    } else if (choice == 'closePeriod') {
      await _closeCurrentPayrollPeriod();
    }
  }

  Future<void> _managePayrollPeriods() async {
    final store = context.read<MastersStore>();
    if (store.payrollPeriods.isEmpty) {
      await _closeCurrentPayrollPeriod();
      return;
    }

    // Причина переоткрытия хранится в аудите. Показываем последнюю для
    // открытых периодов, у которых уже есть ведомости (значит, был пересчёт).
    final reopenReasons = <String, String>{};
    for (final period in store.payrollPeriods) {
      if (period.isClosed) continue;
      if (store.payslipHistoryForPeriod(period.id).isEmpty) continue;
      final entries = await store.auditEntriesFor(
        'payroll_period',
        period.id,
        limit: 30,
      );
      for (final entry in entries) {
        if (entry['action'] != 'payroll_period.reopen') continue;
        final raw = entry['after_json'];
        if (raw is String && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map && decoded['reason'] is String) {
              final reason = (decoded['reason'] as String).trim();
              if (reason.isNotEmpty) reopenReasons[period.id] = reason;
            }
          } catch (_) {
            // Старая запись без разбираемого JSON просто не показывается.
          }
        }
        break;
      }
    }
    if (!mounted) return;
    final colors = context.colors;

    Widget periodTile(
      BuildContext sheetContext,
      StateSetter setSheetState,
      PayrollPeriod period,
    ) {
      final slips = store.payslipsForPeriod(period.id);
      final history = store.payslipHistoryForPeriod(period.id);
      var version = 0;
      for (final slip in slips) {
        if (slip.version > version) version = slip.version;
      }
      final preliminary = slips
          .where((slip) => slip.status == 'preliminary')
          .length;
      final statusColor = !period.isClosed || preliminary > 0
          ? colors.orange
          : colors.green;
      final statusLabel = !period.isClosed
          ? 'Открыт'
          : preliminary > 0
          ? 'Предварительно'
          : 'Подтверждено';

      final details = period.isClosed
          ? slips.isEmpty
                ? 'Ведомостей нет — при экспорте будет расчёт вживую'
                : 'Ведомости: ${slips.length} · версия $version'
                      '${history.length > slips.length ? ' · история ${history.length}' : ''}'
                      '${preliminary > 0 ? ' · подтверждено ${slips.length - preliminary} из ${slips.length}' : ''}'
          : history.isEmpty
          ? 'Закрытие зафиксирует ведомости сотрудников'
          : 'Будет создана версия ${version + 1}; '
                'версия $version останется в истории';

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          period.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _periodRange(period),
                          style: TextStyle(
                            color: colors.secondaryLabel,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusPill(statusLabel, statusColor),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                details,
                style: TextStyle(color: colors.secondaryLabel, fontSize: 11),
              ),
              if (!period.isClosed && reopenReasons[period.id] != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Причина переоткрытия: ${reopenReasons[period.id]}',
                  style: TextStyle(color: colors.orange, fontSize: 11),
                ),
              ],
              if (preliminary > 0) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Сверьте суммы перед подтверждением.',
                        style: TextStyle(
                          color: colors.secondaryLabel,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        final ok = await showAppConfirm(
                          sheetContext,
                          title: 'Подтвердить ведомости?',
                          message: 'Предварительных: $preliminary из '
                              '${slips.length}. После подтверждения они '
                              'считаются сверенными; запись останется в аудите.',
                          confirmLabel: 'Подтвердить',
                        );
                        if (!ok) return;
                        final count = await store.confirmPreliminaryPayslips(
                          period.id,
                        );
                        if (!sheetContext.mounted) return;
                        setSheetState(() {});
                        await showAppAlert(
                          sheetContext,
                          title: 'Готово',
                          message: 'Подтверждено ведомостей: $count.',
                        );
                      },
                      child: Text(
                        'Подтвердить',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      if (period.isClosed) {
                        final reason = await _prompt(
                          'Причина переоткрытия',
                          'Например: ошибка в табеле',
                        );
                        if (reason == null) return;
                        if (reason.trim().isEmpty) {
                          if (sheetContext.mounted) {
                            await showAppAlert(
                              sheetContext,
                              title: 'Нужна причина',
                              message: 'Переоткрытие без причины запрещено: '
                                  'причина попадёт в аудит.',
                            );
                          }
                          return;
                        }
                        await store.reopenPayrollPeriod(
                          period.id,
                          reason: reason,
                        );
                        if (!sheetContext.mounted) return;
                        reopenReasons[period.id] = reason.trim();
                        setSheetState(() {});
                      } else {
                        final ok = await showAppConfirm(
                          sheetContext,
                          title: 'Закрыть период?',
                          message: 'Суммы будут зафиксированы. Изменение после '
                              'закрытия — только через переоткрытие с причиной.',
                          confirmLabel: 'Закрыть',
                        );
                        if (!ok) return;
                        final created = await store.closePayrollPeriod(
                          period.id,
                        );
                        if (!sheetContext.mounted) return;
                        setSheetState(() {});
                        final pending = created
                            .where((slip) => slip.status == 'preliminary')
                            .length;
                        await showAppAlert(
                          sheetContext,
                          title: 'Период закрыт',
                          message: created.isEmpty
                              ? 'Активных сотрудников нет — ведомости не созданы.'
                              : pending > 0
                              ? 'Предварительных ведомостей: $pending. '
                                    'Проверьте и подтвердите их.'
                              : 'Ведомости зафиксированы.',
                        );
                      }
                    },
                    child: Icon(
                      period.isClosed
                          ? CupertinoIcons.lock_open
                          : CupertinoIcons.lock,
                      size: 18,
                      semanticLabel: period.isClosed
                          ? 'Переоткрыть период'
                          : 'Закрыть период',
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _exportPayrollPeriod(period);
                    },
                    child: const Icon(
                      CupertinoIcons.doc_text,
                      size: 18,
                      semanticLabel: 'Экспорт',
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      final message = period.isClosed
                          ? 'Период «${period.name}» закрыт. Ведомости '
                                '(${slips.length}) останутся в базе, но период '
                                'исчезнет из списка, и открыть их из приложения '
                                'будет нельзя.'
                          : 'Период «${period.name}» будет удалён. '
                                'Сохранённые ведомости останутся в базе.';
                      final ok = await showAppConfirm(
                        sheetContext,
                        title: 'Удалить период?',
                        message: message,
                        destructive: true,
                        confirmLabel: 'Удалить',
                      );
                      if (!ok) return;
                      await store.deletePayrollPeriod(period.id);
                      if (!sheetContext.mounted) return;
                      setSheetState(() {});
                    },
                    child: Icon(
                      CupertinoIcons.trash,
                      size: 18,
                      color: colors.red,
                      semanticLabel: 'Удалить период',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          color: colors.card,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Расчётные периоды',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const SizedBox(height: 2),
                Text(
                  'Закрытый период хранит ведомости. Переоткрытие требует '
                  'причины и создаёт новую версию при повторном закрытии.',
                  style: TextStyle(color: colors.secondaryLabel, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      for (final period in store.payrollPeriods)
                        periodTile(sheetContext, setSheetState, period),
                    ],
                  ),
                ),
                CupertinoButton(
                  child: const Text('Готово'),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editEmployee(Employee e) async {
    final nameController = TextEditingController(text: e.name);
    final rateController = TextEditingController(
      text: (e.rateCents / 100).toStringAsFixed(0),
    );
    final percentController = TextEditingController(text: e.percent.toString());
    String payType = e.payType;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => StatefulBuilder(
        builder: (_, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          color: context.colors.card,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Редактирование сотрудника',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: nameController,
                  placeholder: 'Имя',
                  decoration: BoxDecoration(
                    color: const Color(0x00FFFFFF),
                    border: Border.all(color: context.colors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                CupertinoButton(
                  onPressed: () async {
                    final selected = await showCupertinoModalPopup<String>(
                      context: context,
                      builder: (dialogContext) => CupertinoActionSheet(
                        title: const Text('Тип оплаты'),
                        actions: [
                          for (final t in [
                            'hourly',
                            'piece',
                            'percent',
                            'salary',
                            'mixed',
                          ])
                            CupertinoActionSheetAction(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(t),
                              child: Text(t),
                            ),
                        ],
                        cancelButton: CupertinoActionSheetAction(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Отмена'),
                        ),
                      ),
                    );
                    if (selected != null) {
                      setModalState(() => payType = selected);
                    }
                  },
                  child: Text('Тип: $payType'),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: rateController,
                  placeholder: 'Ставка ($moneySymbol)',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x00FFFFFF),
                    border: Border.all(color: context.colors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: percentController,
                  placeholder: 'Процент',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x00FFFFFF),
                    border: Border.all(color: context.colors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                SecondaryButton(
                  label: 'Сохранить',
                  icon: CupertinoIcons.checkmark,
                  onPressed: () async {
                    final rate =
                        ((double.tryParse(
                                      rateController.text.replaceAll(',', '.'),
                                    ) ??
                                    0) *
                                100)
                            .round();
                    final percent =
                        double.tryParse(
                          percentController.text.replaceAll(',', '.'),
                        ) ??
                        e.percent;
                    final name = nameController.text.trim().isEmpty
                        ? e.name
                        : nameController.text.trim();
                    await context.read<MastersStore>().updateEmployee(
                      e.copyWith(
                        name: name,
                        payType: payType,
                        rateCents: rate,
                        percent: percent,
                      ),
                    );
                    if (modalContext.mounted) Navigator.of(modalContext).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(Employee e) async {
    if (e.role == 'owner' && e.name == 'Я') {
      await showAppAlert(
        context,
        title: 'Нельзя удалить профиль «Я»',
        message: 'Это исполнитель по умолчанию для заказов.',
      );
      return;
    }
    final ok = await showAppConfirm(
      context,
      title: 'Удалить сотрудника?',
      message: e.name,
      destructive: true,
      confirmLabel: 'Удалить',
    );
    if (!ok) return;
    if (!mounted) return;
    await context.read<MastersStore>().deleteEmployee(e.id);
    if (mounted && _selectedEmployeeId == e.id) {
      setState(() => _selectedEmployeeId = null);
    }
  }

  @override
  void dispose() {
    _selectedEmployeeId = null;
    super.dispose();
  }

  Widget _buildList(MastersStore store, AppColors colors, bool wide) {
    final employees = store.employees;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
      children: [
        Row(
          children: [
            Expanded(
              child: SectionLabel(
                '${employees.length} ${employeesWord(employees.length)}',
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
              ),
            ),
            OverflowMenuButton(
              title: 'Команда',
              actions: [
                CupertinoActionSheetAction(
                  onPressed: _closeCurrentPayrollPeriod,
                  child: const Text('Закрыть месяц'),
                ),
                CupertinoActionSheetAction(
                  onPressed: _managePayrollPeriods,
                  child: const Text('Периоды выплат'),
                ),
                CupertinoActionSheetAction(
                  onPressed: _exportPayroll,
                  child: const Text('Сводный PDF по сотрудникам'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            children: [
              for (var i = 0; i < employees.length; i++) ...[
                if (i > 0) const Hairline(indent: 12),
                _employeeRow(store, colors, employees[i], wide),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _employeeRow(
    MastersStore store,
    AppColors colors,
    Employee e,
    bool wide,
  ) {
    final earned = store.earnedCents(e.id);
    final owed = store.employeeBalanceOwed(e.id);
    final selected = _selectedEmployeeId == e.id;
    return ListRow(
      title: e.name,
      subtitle:
          '${e.payTypeLabel} · Заработано ${_money(earned)} · '
          'К выплате ${_money(owed)}',
      icon: CupertinoIcons.person,
      dense: true,
      titleColor: selected && wide ? colors.accent : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (owed > 0)
            Text(
              _money(owed),
              style: TextStyle(
                color: colors.orange,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          OverflowMenuButton(
            size: 18,
            title: e.name,
            actions: [
              CupertinoActionSheetAction(
                onPressed: () => _addTime(e.id),
                child: const Text('Добавить часы'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => _addPayment(e.id, 'advance', 'Авансы'),
                child: const Text('Аванс'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => _addPayment(e.id, 'bonus', 'Бонус'),
                child: const Text('Бонус'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => _addPayment(e.id, 'penalty', 'Штраф'),
                child: const Text('Штраф'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => _addPayment(e.id, 'payout', 'Выплата'),
                child: const Text('Выплата'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => _pickPayslipPeriod(e),
                child: const Text('PDF-листок за период'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => _editEmployee(e),
                child: const Text('Изменить'),
              ),
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () => _delete(e),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ],
      ),
      onTap: wide ? () => setState(() => _selectedEmployeeId = e.id) : null,
    );
  }

  Widget _buildDetail(MastersStore store, AppColors colors) {
    if (_selectedEmployeeId == null) {
      return EmptyState(
        title: 'Выберите сотрудника',
        message: 'Слева список сотрудников; справа — карточка.',
        art: Icon(
          CupertinoIcons.person_2,
          size: 48,
          color: colors.tertiaryLabel,
        ),
      );
    }
    Employee? e;
    for (final item in store.employees) {
      if (item.id == _selectedEmployeeId) {
        e = item;
        break;
      }
    }
    if (e == null) {
      return EmptyState(
        title: 'Выберите сотрудника',
        message: 'Слева список сотрудников; справа — карточка.',
        art: Icon(
          CupertinoIcons.person_2,
          size: 48,
          color: colors.tertiaryLabel,
        ),
      );
    }
    final employee = e;
    final earned = store.earnedCents(employee.id);
    final owed = store.employeeBalanceOwed(employee.id);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              employee.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const SizedBox(height: 2),
            Text(
              '${employee.payTypeLabel} · ставка ${_money(employee.rateCents)}',
              style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            const Hairline(),
            const SizedBox(height: 4),
            KeyValueRow('Заработано', _money(earned), dense: true),
            KeyValueRow(
              'К выплате',
              _money(owed),
              valueColor: owed > 0 ? colors.orange : null,
              emphasis: owed > 0,
              dense: true,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChipButton(
                  label: 'Часы',
                  icon: CupertinoIcons.clock,
                  onPressed: () => _addTime(employee.id),
                ),
                ChipButton(
                  label: 'Аванс',
                  icon: CupertinoIcons.money_dollar,
                  onPressed: () =>
                      _addPayment(employee.id, 'advance', 'Авансы'),
                ),
                ChipButton(
                  label: 'Бонус',
                  icon: CupertinoIcons.plus,
                  onPressed: () => _addPayment(employee.id, 'bonus', 'Бонус'),
                ),
                ChipButton(
                  label: 'Выплата',
                  icon: CupertinoIcons.arrow_right,
                  onPressed: () => _addPayment(employee.id, 'payout', 'Выплата'),
                ),
                ChipButton(
                  label: 'PDF-листок',
                  icon: CupertinoIcons.doc_text,
                  onPressed: () => _pickPayslipPeriod(employee),
                ),
                ChipButton(
                  label: 'Изменить',
                  icon: CupertinoIcons.pencil,
                  onPressed: () => _editEmployee(employee),
                ),
                ChipButton(
                  label: 'Удалить',
                  icon: CupertinoIcons.trash,
                  color: colors.red,
                  onPressed: () => _delete(employee),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final isWide = MediaQuery.of(context).size.width >= 720;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Команда'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showEmployeeActions,
              child: const Icon(CupertinoIcons.ellipsis_circle, semanticLabel: 'Дополнительно'),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _newEmployee,
              child: const Icon(CupertinoIcons.plus, semanticLabel: 'Добавить'),
            ),
          ],
        ),
      ),
      child: _busy
          ? const Center(child: CupertinoActivityIndicator())
          : SafeArea(
              child: store.employees.isEmpty
                  ? EmptyState(
                      title: 'Нет сотрудников',
                      message: 'Добавьте первого сотрудника.',
                      art: Icon(
                        CupertinoIcons.person_2,
                        size: 48,
                        color: colors.tertiaryLabel,
                      ),
                      actions: [
                        PrimaryButton(
                          label: 'Добавить сотрудника',
                          icon: CupertinoIcons.plus,
                          onPressed: _newEmployee,
                        ),
                      ],
                    )
                  : isWide
                  ? Row(
                      children: [
                        Expanded(child: _buildList(store, colors, true)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildDetail(store, colors)),
                      ],
                    )
                  : _buildList(store, colors, false),
            ),
    );
  }
}
