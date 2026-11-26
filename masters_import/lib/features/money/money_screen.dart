import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/tax_radar_bar.dart';
import '../../app/ui.dart';
import '../../core/utils/app_utils.dart';
import '../../core/reminder_text.dart';
import '../employees/employees_screen.dart';
import '../clients/client_credits.dart';
import '../stats/stats_screen.dart';
import '../../data/models/money_transaction.dart';
import '../../data/models/obligation.dart';
import '../../data/models/recurring_payment.dart';
import '../../state/masters_store.dart';
import '../../state/settings_controller.dart';
import '../../core/money_format.dart';

class MoneyScreen extends StatefulWidget {
  const MoneyScreen({super.key});

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends State<MoneyScreen> {
  bool _busy = false;
  final _txSearchController = TextEditingController();
  String _directionFilter = 'all';
  String? _accountFilter;
  String _txQuery = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _recurringStatusFilter = 'all';
  int _selectedTab = 0; // 0: Операции, 1: Счета, 2: Категории, 3: План
  bool _taxRadarExpanded = false;

  String _money(int cents) => money(cents);

  Future<String?> _pickAccount() async {
    final store = context.read<MastersStore>();
    final accounts = store.accounts.where((a) => !a.archived).toList();
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        color: context.colors.card,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Отмена'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final a in accounts)
                    CupertinoButton(
                      onPressed: () => Navigator.of(ctx).pop(a.id),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(a.name),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(bool from) async {
    DateTime selected = from
        ? (_dateFrom ?? DateTime.now())
        : (_dateTo ?? DateTime.now());
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: context.colors.card,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Отмена'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                CupertinoButton(
                  child: const Text('Готово'),
                  onPressed: () {
                    final picked = DateTime(
                      selected.year,
                      selected.month,
                      selected.day,
                    );
                    Navigator.of(ctx).pop();
                    setState(() {
                      if (from) {
                        _dateFrom = picked;
                      } else {
                        _dateTo = picked;
                      }
                    });
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selected,
                onDateTimeChanged: (dt) => selected = dt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDateFilter() async {
    final action = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Период'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('from'),
            child: const Text('С даты'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('to'),
            child: const Text('По дату'),
          ),
          if (_dateFrom != null || _dateTo != null)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop('clear'),
              child: const Text('Очистить'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('all'),
            child: const Text('Все'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (action == 'from') {
      await _pickDate(true);
    } else if (action == 'to') {
      await _pickDate(false);
    } else if (action == 'clear' || action == 'all') {
      setState(() {
        _dateFrom = null;
        _dateTo = null;
      });
    }
  }

  String _formatDate() {
    final f = DateFormat('d MMM yyyy', 'ru');
    if (_dateFrom != null && _dateTo != null) {
      return '${f.format(_dateFrom!)} — ${f.format(_dateTo!)}';
    }
    if (_dateFrom != null) {
      return 'С ${f.format(_dateFrom!)}';
    }
    if (_dateTo != null) {
      return 'По ${f.format(_dateTo!)}';
    }
    return 'Период: все';
  }

  Future<void> _quickSale() async => _quickTransactionSheet(isIncome: true);

  Future<void> _addExpense() async => _quickTransactionSheet(isIncome: false);

  Future<void> _quickTransactionSheet({required bool isIncome}) async {
    final store = context.read<MastersStore>();
    if (store.accounts.isEmpty) {
      await showAppAlert(
        context,
        title: 'Нет счёта',
        message: 'Сначала создайте счёт в разделе «Счета»',
      );
      return;
    }
    final accountId = await _pickAccount();
    if (accountId == null || !mounted) return;
    final amountController = TextEditingController();
    final categoryController = TextEditingController(
      text: isIncome ? 'Продажа' : '',
    );
    final noteController = TextEditingController();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        color: context.colors.card,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isIncome ? 'Новая продажа' : 'Быстрый расход',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: amountController,
                placeholder: 'Сумма 0.00',
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
                controller: categoryController,
                placeholder: 'Категория',
                decoration: BoxDecoration(
                  color: const Color(0x00FFFFFF),
                  border: Border.all(color: context.colors.separator),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: noteController,
                placeholder: 'Комментарий',
                maxLines: 2,
                decoration: BoxDecoration(
                  color: const Color(0x00FFFFFF),
                  border: Border.all(color: context.colors.separator),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
              SecondaryButton(
                label: isIncome ? 'Провести' : 'Провести',
                icon: isIncome ? CupertinoIcons.plus : CupertinoIcons.minus,
                onPressed: () async {
                  final amount =
                      ((double.tryParse(
                                    amountController.text.trim().replaceAll(
                                      ',',
                                      '.',
                                    ),
                                  ) ??
                                  0) *
                              100)
                          .round();
                  if (amount <= 0) return;
                  final category = categoryController.text.trim().isEmpty
                      ? (isIncome ? 'Продажа' : '')
                      : categoryController.text.trim();
                  final note = noteController.text.trim().isEmpty
                      ? null
                      : noteController.text.trim();
                  await store.addTransaction(
                    accountId: accountId,
                    kind: isIncome ? 'sale' : 'expense',
                    direction: isIncome ? 'in' : 'out',
                    amountCents: amount,
                    category: category,
                    note: note,
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _transferBetweenAccounts() async {
    final store = context.read<MastersStore>();
    final accounts = store.accounts.where((a) => !a.archived).toList();
    if (accounts.length < 2) {
      if (!mounted) return;
      await showAppAlert(
        context,
        title: 'Перевод',
        message: 'Нужно минимум 2 счёта.',
      );
      return;
    }
    final amountStr = await _prompt('Сумма перевода', '0');
    if (amountStr == null) return;
    final amount =
        ((double.tryParse(amountStr.replaceAll(',', '.')) ?? 0) * 100).round();
    if (amount <= 0) return;

    final fromId = await _pickAccountExcluding(null);
    if (fromId == null || !mounted) return;
    final toId = await _pickAccountExcluding(fromId);
    if (toId == null || !mounted) return;
    final note = await _prompt('Комментарий', '');

    setState(() => _busy = true);
    try {
      await store.transferBetweenAccounts(fromId, toId, amount, note: note);
    } catch (e) {
      if (mounted) {
        await showAppAlert(context, title: 'Ошибка', message: e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickAccountExcluding(String? excludedId) async {
    final store = context.read<MastersStore>();
    final accounts = store.accounts
        .where((a) => !a.archived && a.id != excludedId)
        .toList();
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        color: context.colors.card,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Отмена'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final a in accounts)
                    CupertinoButton(
                      onPressed: () => Navigator.of(ctx).pop(a.id),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(a.name),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importTransactionsExcel() async {
    setState(() => _busy = true);
    try {
      final count = await context
          .read<MastersStore>()
          .importTransactionsFromExcel();
      if (!mounted) return;
      await showAppAlert(
        context,
        title: count > 0 ? 'Импорт завершён' : 'Импорт',
        message: count > 0
            ? 'Добавлено транзакций: $count.'
            : 'Не удалось добавить записи. Проверьте шаблон Excel (колонка amount обязательна).',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addRecurringPayment() async {
    final store = context.read<MastersStore>();
    if (store.accounts.isEmpty) {
      await showAppAlert(
        context,
        title: 'Нет счёта',
        message: 'Сначала создайте счёт в разделе «Счета»',
      );
      return;
    }
    final interval = await showCupertinoModalPopup<int>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Как часто платёж'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(7),
            child: const Text('Каждую неделю'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(14),
            child: const Text('Раз в 2 недели'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(30),
            child: const Text('Ежемесячно'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(90),
            child: const Text('Раз в квартал'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop(-1),
            child: const Text('Свой интервал'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (interval == null || !mounted) return;
    int step = interval == -1 ? 30 : interval;
    if (interval == -1) {
      final custom = await _prompt('Интервал, дней', '30');
      final parsed = int.tryParse((custom ?? '').trim());
      if (parsed == null || parsed <= 0 || !mounted) return;
      step = parsed;
    }
    final direction = await showCupertinoModalPopup<String>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Тип регулярного платежа'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('in'),
            child: const Text('Плановый приход'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('out'),
            child: const Text('Плановый расход'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (direction == null || !mounted) return;
    final name = await _prompt('Название платежа', 'ошибка');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final amountStr = await _prompt('Сумма', '0');
    if (amountStr == null || !mounted) return;
    final amount =
        ((double.tryParse(amountStr.replaceAll(',', '.')) ?? 0) * 100).round();
    if (amount <= 0) return;
    final category = await _prompt('Категория', 'регулярно') ?? 'регулярно';
    final accountId = await _pickAccount();
    if (accountId == null || !mounted) return;
    final now = DateTime.now();
    await store.createRecurringPayment(
      name: name.trim(),
      direction: direction,
      amountCents: amount,
      category: category.trim(),
      accountId: accountId,
      intervalDays: step,
      nextDueAt: now.add(Duration(days: step)),
      note: null,
    );
  }

  Future<void> _editRecurringPayment(RecurringPayment payment) async {
    final store = context.read<MastersStore>();
    final nameController = TextEditingController(text: payment.name);
    final intervalController = TextEditingController(
      text: payment.intervalDays.toString(),
    );
    final amountController = TextEditingController(
      text: (payment.amountCents / 100).toStringAsFixed(2),
    );
    final categoryController = TextEditingController(text: payment.category);
    var active = payment.active;
    var nextDue = DateTime(
      payment.nextDueAt.year,
      payment.nextDueAt.month,
      payment.nextDueAt.day,
    );

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          color: context.colors.card,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Редактирование регулярного платежа',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: nameController,
                  placeholder: 'Название',
                  decoration: BoxDecoration(
                    color: const Color(0x00FFFFFF),
                    border: Border.all(color: context.colors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: intervalController,
                  placeholder: 'Интервал, дней',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x00FFFFFF),
                    border: Border.all(color: context.colors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: amountController,
                  placeholder: 'Сумма 0.00',
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
                  controller: categoryController,
                  placeholder: 'Категория',
                  decoration: BoxDecoration(
                    color: const Color(0x00FFFFFF),
                    border: Border.all(color: context.colors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Активен'),
                    CupertinoSwitch(
                      value: active,
                      onChanged: (v) => setModalState(() => active = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Следующий платёж: '
                      '${nextDue.day.toString().padLeft(2, '0')}'
                      '.${nextDue.month.toString().padLeft(2, '0')}'
                      '.${nextDue.year}',
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        DateTime selected = nextDue;
                        await showCupertinoModalPopup<void>(
                          context: context,
                          builder: (pickerContext) => Container(
                            height: 300,
                            color: context.colors.card,
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    CupertinoButton(
                                      child: const Text('Отмена'),
                                      onPressed: () =>
                                          Navigator.of(pickerContext).pop(),
                                    ),
                                    CupertinoButton(
                                      child: const Text('Готово'),
                                      onPressed: () {
                                        final picked = DateTime(
                                          selected.year,
                                          selected.month,
                                          selected.day,
                                        );
                                        Navigator.of(pickerContext).pop();
                                        setModalState(() => nextDue = picked);
                                      },
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: CupertinoDatePicker(
                                    mode: CupertinoDatePickerMode.date,
                                    initialDateTime: selected,
                                    onDateTimeChanged: (dt) => selected = dt,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: const Text('Выбрать дату'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SecondaryButton(
                  label: 'Сохранить',
                  icon: CupertinoIcons.checkmark,
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    final interval =
                        int.tryParse(intervalController.text.trim()) ?? 0;
                    if (interval <= 0) return;
                    final amount =
                        ((double.tryParse(
                                      amountController.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    ) ??
                                    0) *
                                100)
                            .round();
                    if (amount <= 0) return;
                    final category = categoryController.text.trim();
                    await store.updateRecurringPayment(
                      payment.copyWith(
                        name: name,
                        intervalDays: interval,
                        amountCents: amount,
                        category: category,
                        active: active,
                        nextDueAt: DateTime(
                          nextDue.year,
                          nextDue.month,
                          nextDue.day,
                        ),
                      ),
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runDueRecurring() async {
    final store = context.read<MastersStore>();
    setState(() => _busy = true);
    try {
      final count = await store.runDueRecurringPayments();
      if (mounted) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: 'Проведено плановых платежей: $count',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newAccount() async {
    final name = await _prompt('Название счёта', '');
    if (name == null || name.trim().isEmpty) return;
    final type = await _pickType();
    if (type == null) return;
    if (!mounted) return;
    await context.read<MastersStore>().createAccount(
      name: name.trim(),
      type: type,
    );
  }

  List<Widget> _teamCards(MastersStore store, AppColors colors) {
    if (store.employees.isEmpty) {
      return [
        EmptyState(
          title: 'Нет сотрудников',
          message: 'Добавьте сотрудника, чтобы видеть начисления и выплаты.',
          art: Icon(
            CupertinoIcons.person_2,
            size: 36,
            color: const Color(0xFFB2B2B6),
          ),
        ),
      ];
    }
    final maxEarned = store.employees
        .map((e) => store.earnedCents(e.id))
        .fold<int>(1, (a, b) => b > a ? b : a)
        .clamp(1, 1 << 30);
    return [
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in store.employees) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                  Text(
                    _money(store.earnedCents(e.id)),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Начислено',
                    style: TextStyle(
                      color: colors.secondaryLabel,
                      fontSize: 11.5,
                    ),
                  ),
                  Text(
                    'К выплате ${_money(store.employeeBalanceOwed(e.id))}',
                    style: TextStyle(
                      color: colors.secondaryLabel,
                      fontSize: 11.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final earned = store.earnedCents(e.id);
                  final factor = earned <= 0 ? 0.0 : earned / maxEarned;
                  final paid = store
                      .paymentsForEmployee(e.id)
                      .where(
                        (p) =>
                            p.type == 'advance' ||
                            p.type == 'payout' ||
                            p.type == 'bonus',
                      )
                      .fold<int>(0, (s, p) => s + p.amountCents);
                  final paidFactor = earned <= 0 ? 0.0 : paid / earned;
                  return SizedBox(
                    height: 8,
                    width: constraints.maxWidth,
                    child: Stack(
                      children: [
                        Container(
                          height: 8,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: colors.tertiaryLabel.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          height: 8,
                          width: constraints.maxWidth * factor.clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        if (paidFactor > 0)
                          Container(
                            height: 8,
                            width:
                                (constraints.maxWidth *
                                    factor.clamp(0.0, 1.0)) *
                                paidFactor.clamp(0.0, 1.0),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ];
  }

  Future<String?> _pickType() async {
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 220,
        color: context.colors.card,
        child: Column(
          children: [
            CupertinoButton(
              child: const Text('Наличные'),
              onPressed: () => Navigator.of(ctx).pop('cash'),
            ),
            CupertinoButton(
              child: const Text('Карта'),
              onPressed: () => Navigator.of(ctx).pop('card'),
            ),
            CupertinoButton(
              child: const Text('банк'),
              onPressed: () => Navigator.of(ctx).pop('bank'),
            ),
            CupertinoButton(
              child: const Text('Кошелёк'),
              onPressed: () => Navigator.of(ctx).pop('wallet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openShift() async {
    final store = context.read<MastersStore>();
    if (store.openShift() != null) {
      await showAppAlert(
        context,
        title: 'Смена уже открыта',
        message: 'Сначала закройте текущую смену.',
      );
      return;
    }
    final accountId = await _pickAccount();
    if (accountId == null) return;
    final openingStr = await _prompt('Начальная сумма в кассе', '0');
    final opening =
        ((double.tryParse((openingStr ?? '0').replaceAll(',', '.')) ?? 0) * 100)
            .round();
    await store.openCashShift(accountId: accountId, openingCents: opening);
  }

  Future<void> _closeShift() async {
    final store = context.read<MastersStore>();
    final shift = store.openShift();
    if (shift == null) {
      await showAppAlert(
        context,
        title: 'Нет открытой смены',
        message: 'Откройте смену для учёта.',
      );
      return;
    }
    final closingStr = await _prompt('Фактическая сумма при закрытии', '0');
    final closing =
        ((double.tryParse((closingStr ?? '0').replaceAll(',', '.')) ?? 0) * 100)
            .round();
    final expected = store.expectedForShift(shift);
    final disc = closing - expected;
    if (!mounted) return;
    final ok = await showAppConfirm(
      context,
      title: 'Закрыть смену?',
      message:
          'Ожидается: ${_money(expected)}. : ${_money(closing)}. : ${_money(disc)}.',
      confirmLabel: 'Закрыть',
    );
    if (!ok) return;
    await store.closeCashShift(shift, closing);
  }

  Future<String?> _prompt(String title, String placeholder) async {
    final controller = TextEditingController();
    return showCupertinoDialog<String?>(
      context: context,
      builder: (dc) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
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
            child: const Text('АК'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTxSearch() async {
    _txSearchController.text = _txQuery;
    if (!mounted) return;
    final result = await showCupertinoDialog<String?>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Поиск'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: _txSearchController,
            placeholder: 'Поиск по категории/комментарию',
            autofocus: true,
            onSubmitted: (_) =>
                Navigator.of(dialogContext)
                    .pop(_txSearchController.text.trim()),
            decoration: BoxDecoration(
              color: context.colors.card,
              border: Border.all(color: context.colors.separator),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(_txSearchController.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _txQuery = result);
  }

  @override
  void dispose() {
    _txSearchController.dispose();
    super.dispose();
  }

  Future<void> _showTransactionDetail(MoneyTransaction t) async {
    final store = context.read<MastersStore>();
    MoneyTransaction current = t;
    final acc = store.accountById(t.accountId);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => StatefulBuilder(
        builder: (sbContext, setModalState) {
          final currentAcc = store.accountById(current.accountId) ?? acc;
          bool isImage(String path) {
            final lower = path.toLowerCase();
            return lower.endsWith('.jpg') ||
                lower.endsWith('.jpeg') ||
                lower.endsWith('.png') ||
                lower.endsWith('.gif') ||
                lower.endsWith('.webp') ||
                lower.endsWith('.heic');
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.72,
            color: context.colors.card,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    current.category.isEmpty ? current.kind : current.category,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _KV('Счёт', currentAcc?.name ?? '—'),
                  _KV(
                    'Сумма',
                    '${current.direction == 'in' ? '+' : '-'}${_money(current.amountCents)}',
                  ),
                  _KV('Тип', current.kind),
                  if (current.paymentMethod != null && current.paymentMethod!.isNotEmpty)
                    _KV(
                      'Оплата',
                      kPaymentMethods[current.paymentMethod!] ?? current.paymentMethod!,
                    ),
                  _KV(
                    'Дата',
                    DateFormat(
                      'd MMM yyyy, HH:mm',
                      'ru',
                    ).format(current.createdAt),
                  ),
                  if (current.note != null && current.note!.isNotEmpty)
                    _KV('Комментарий', current.note!),
                  const SizedBox(height: 12),
                  if (current.receiptPath != null &&
                      current.receiptPath!.isNotEmpty) ...[
                    if (isImage(current.receiptPath!))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(current.receiptPath!),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Открыть чек',
                            icon: CupertinoIcons.doc,
                            onPressed: () async {
                              await OpenFilex.open(current.receiptPath!);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SecondaryButton(
                            label: 'Удалить чек',
                            icon: CupertinoIcons.trash,
                            onPressed: () async {
                              final ok = await showAppConfirm(
                                context,
                                title: 'Удалить чек?',
                                message: 'Чек останется в системе.',
                                destructive: true,
                                confirmLabel: 'Удалить',
                              );
                              if (!ok || !mounted) return;
                              await store.removeReceipt(current.id);
                              final updated = store.moneyTransactions
                                  .firstWhere(
                                    (x) => x.id == current.id,
                                    orElse: () => current,
                                  );
                              setModalState(() => current = updated);
                            },
                          ),
                        ),
                      ],
                    ),
                  ] else
                    SecondaryButton(
                      label: 'Прикрепить чек',
                      icon: CupertinoIcons.paperclip,
                      onPressed: () async {
                        final files = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const [
                            'jpg',
                            'jpeg',
                            'png',
                            'gif',
                            'webp',
                            'heic',
                            'pdf',
                          ],
                        );
                        if (files.isEmpty) return;
                        final selectedPath = files.single.path;
                        if (selectedPath == null) return;
                        await store.attachReceipt(current.id, selectedPath);
                        final updated = store.moneyTransactions.firstWhere(
                          (x) => x.id == current.id,
                          orElse: () => current,
                        );
                        setModalState(() => current = updated);
                      },
                    ),
                  if (current.reversesId != null) ...[
                    _KV(
                      'Возврат операции',
                      current.reversesId!,
                      isLink: true,
                      onTap: () =>
                          _showTransactionDetailById(current.reversesId!),
                    ),
                    const SizedBox(height: 8),
                  ] else if (store.moneyTransactions.any(
                    (tx) => tx.reversesId == current.id,
                  )) ...[
                    _KV(
                      'Есть возврат',
                      'открыть',
                      isLink: true,
                      onTap: () {
                        final reversal = store.moneyTransactions.firstWhere(
                          (tx) => tx.reversesId == current.id,
                        );
                        _showTransactionDetailById(reversal.id);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 16),
                  if (!store.moneyTransactions.any(
                    (tx) => tx.reversesId == current.id,
                  ))
                    SecondaryButton(
                      label: 'Сделать возврат',
                      icon: CupertinoIcons.arrow_uturn_left,
                      onPressed: () async {
                        final ok = await showAppConfirm(
                          context,
                          title: 'Сделать возврат?',
                          message:
                              'Будет создана новая операция-возврат на ${_money(current.amountCents)}, исходная станет серой.',
                          destructive: false,
                          confirmLabel: 'Возвратить',
                        );
                        if (!ok || !mounted) return;
                        try {
                          await store.revertTransaction(current.id);
                        } catch (e) {
                          if (context.mounted) {
                            showCupertinoDialog<void>(
                              context: context,
                              builder: (ctx) => CupertinoAlertDialog(
                                title: const Text('Ошибка'),
                                content: Text(e.toString()),
                                actions: [
                                  CupertinoDialogAction(
                                    child: const Text('ОК'),
                                    onPressed: () => Navigator.of(ctx).pop(),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                        if (modalContext.mounted) {
                          Navigator.of(modalContext).pop();
                        }
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showTransactionDetailById(String id) async {
    final store = context.read<MastersStore>();
    final t = store.moneyTransactions.firstWhere(
      (tx) => tx.id == id,
      orElse: () => throw Exception('Transaction not found'),
    );
    await _showTransactionDetail(t);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final settings = context.watch<SettingsController>();
    final colors = context.colors;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayTx = store.moneyTransactions
        .where((t) => !t.voided && t.createdAt.isAfter(todayStart))
        .toList();
    final todayIncome = todayTx
        .where((t) => t.direction == 'in')
        .fold(0, (s, t) => s + t.amountCents);
    final todayExpense = todayTx
        .where((t) => t.direction == 'out')
        .fold(0, (s, t) => s + t.amountCents);
    final monthStart = DateTime(now.year, now.month, 1);
    final monthTx = store.moneyTransactions
        .where((t) => !t.voided && !t.createdAt.isBefore(monthStart))
        .toList();
    final monthIncome = monthTx
        .where((t) => t.direction == 'in')
        .fold(0, (s, t) => s + t.amountCents);
    final taxRate = settings.getActiveTaxRate();
    final taxAccountId = settings.taxAccountId;
    final radarYear = now.year;
    final radarMonthlyIncome = List<int>.filled(12, 0);
    final radarMonthlyExpense = List<int>.filled(12, 0);
    for (final t in store.moneyTransactions) {
      if (t.voided || t.createdAt.year != radarYear) continue;
      final mi = t.createdAt.month - 1;
      if (t.direction == 'in') {
        radarMonthlyIncome[mi] += t.amountCents;
      } else if (t.direction == 'out') {
        radarMonthlyExpense[mi] += t.amountCents;
      }
    }
    const radarMonthNames = [
      'Янв',
      'Фев',
      'Мар',
      'Апр',
      'Май',
      'Июн',
      'Июл',
      'Авг',
      'Сен',
      'Окт',
      'Ноя',
      'Дек',
    ];
    final reservedTax = taxRate <= 0
        ? 0
        : (monthIncome * taxRate / 100).round();
    final shift = store.openShift();

    final recurringFiltered = store.recurringPayments.where((p) {
      if (_recurringStatusFilter == 'active') return p.active;
      if (_recurringStatusFilter == 'disabled') return !p.active;
      return true;
    }).toList()..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
    final recurringGroups = <DateTime, List<RecurringPayment>>{};
    for (final p in recurringFiltered) {
      final key = DateTime(p.nextDueAt.year, p.nextDueAt.month);
      recurringGroups.putIfAbsent(key, () => []).add(p);
    }
    final recurringMonthKeys = recurringGroups.keys.toList()..sort();

    // debts
    int totalDebt = 0;
    final debtClients = <Map<String, dynamic>>[];
    for (final c in store.clients) {
      final debt = store.clientDebtCents(c.id);
      if (debt > 0) {
        totalDebt += debt;
        debtClients.add({'client': c, 'debt': debt});
      }
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Деньги'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OverflowMenuButton(
              title: 'Действия',
              actions: [
                CupertinoActionSheetAction(
                  onPressed: _transferBetweenAccounts,
                  child: const Text('Перевод между счетами'),
                ),
                CupertinoActionSheetAction(
                  onPressed: _importTransactionsExcel,
                  child: const Text('Импорт операций (Excel)'),
                ),
                if (settings.cashShiftEnabled)
                  CupertinoActionSheetAction(
                    onPressed: shift == null ? _openShift : _closeShift,
                    child: Text(
                      shift == null ? 'Открыть смену кассы' : 'Закрыть смену',
                    ),
                  ),
                CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(context).push(
                    CupertinoPageRoute(builder: (_) => const StatsScreen()),
                  ),
                  child: const Text('Аналитика (P&L)'),
                ),
              ],
            ),
            const SizedBox(width: 4),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: _newAccount,
              child: const Icon(CupertinoIcons.plus, semanticLabel: 'Новый счёт'),
            ),
          ],
        ),
      ),
      child: _busy
          ? const Center(child: CupertinoActivityIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: CupertinoSegmentedControl<int>(
                    children: const {
                      0: Text('Операции'),
                      1: Text('Счета'),
                      2: Text('Категории'),
                      3: Text('План'),
                    },
                    groupValue: _selectedTab,
                    onValueChanged: (v) => setState(() => _selectedTab = v),
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
                      children: [
                        if (settings.taxRadarEnabled &&
                            settings.npdLimitApplies) ...[
                          AppCard(
                            onTap: () => setState(
                              () => _taxRadarExpanded = !_taxRadarExpanded,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TaxRadarBar(
                                  incomeCents: store.annualIncomeCents(),
                                  limitCents: settings.taxIncomeLimitCents,
                                ),
                                if (_taxRadarExpanded) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Месяц',
                                          style: TextStyle(
                                            color: colors.secondaryLabel,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          'Доходы',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: colors.secondaryLabel,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          'Расходы',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: colors.secondaryLabel,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ...List.generate(12, (i) {
                                    final inc = radarMonthlyIncome[i];
                                    final exp = radarMonthlyExpense[i];
                                    if (inc == 0 && exp == 0) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(radarMonthNames[i]),
                                          ),
                                          SizedBox(
                                            width: 80,
                                            child: Text(
                                              _money(inc),
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                color: colors.green,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 80,
                                            child: Text(
                                              _money(exp),
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                color: colors.red,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (_selectedTab == 0) ...[
                          SectionLabel('Сегодня'),
                          AppCard(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                            child: Column(
                              children: [
                                KeyValueRow(
                                  'Выручка',
                                  _money(todayIncome),
                                  valueColor: todayIncome > 0
                                      ? colors.green
                                      : null,
                                  dense: true,
                                ),
                                KeyValueRow(
                                  'Расходы',
                                  _money(todayExpense),
                                  valueColor: todayExpense > 0
                                      ? colors.red
                                      : null,
                                  dense: true,
                                ),
                                const Hairline(),
                                KeyValueRow(
                                  'Прибыль',
                                  _money(todayIncome - todayExpense),
                                  emphasis: true,
                                  dense: true,
                                ),
                                KeyValueRow(
                                  'На счетах',
                                  _money(store.totalBalanceCents()),
                                  dense: true,
                                ),
                                KeyValueRow(
                                  'Прогноз за месяц',
                                  _money(store.forecastCashToEndOfMonth()),
                                  dense: true,
                                ),
                                if (taxRate > 0) ...[
                                  const Hairline(),
                                  KeyValueRow(
                                    'Налоговый резерв',
                                    '${_money(reservedTax)} · $taxRate%',
                                    dense: true,
                                  ),
                                  KeyValueRow(
                                    'Резерв (прогноз)',
                                    _money(
                                      store.forecastTaxReserveToEndOfMonth(),
                                    ),
                                    dense: true,
                                  ),
                                  KeyValueRow(
                                    'Свободно после резерва',
                                    _money(monthIncome - reservedTax),
                                    dense: true,
                                  ),
                                  if (taxAccountId != null)
                                    KeyValueRow(
                                      'Счёт кармана',
                                      store
                                              .accountById(taxAccountId)
                                              ?.name ??
                                          'неизвестный',
                                      dense: true,
                                    ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChipButton(
                                label: 'Продажа',
                                icon: CupertinoIcons.plus,
                                color: colors.green,
                                onPressed: _quickSale,
                              ),
                              ChipButton(
                                label: 'Расход',
                                icon: CupertinoIcons.minus,
                                color: colors.red,
                                onPressed: _addExpense,
                              ),
                              ChipButton(
                                label: 'Перевод',
                                icon: CupertinoIcons.arrow_left_right,
                                onPressed: _transferBetweenAccounts,
                              ),
                              ChipButton(
                                label: 'Импорт Excel',
                                icon: CupertinoIcons.doc_on_doc,
                                onPressed: _importTransactionsExcel,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (settings.cashShiftEnabled) ...[
                            SectionLabel('Смена кассы'),
                            AppCard(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                              child: shift == null
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Смена не открыта',
                                            style: TextStyle(
                                              color: colors.secondaryLabel,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        ChipButton(
                                          label: 'Открыть',
                                          icon: CupertinoIcons.play,
                                          onPressed: _openShift,
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        ListRow(
                                          title: 'Смена открыта',
                                          subtitle: DateFormat(
                                            'd MMM, HH:mm',
                                            'ru',
                                          ).format(shift.openedAt),
                                          icon: CupertinoIcons.lock_open,
                                          iconColor: colors.green,
                                          dense: true,
                                        ),
                                        KeyValueRow(
                                          'Ожидается в кассе',
                                          _money(
                                            store.expectedForShift(shift),
                                          ),
                                          dense: true,
                                        ),
                                        const SizedBox(height: 6),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: ChipButton(
                                            label: 'Закрыть смену',
                                            icon: CupertinoIcons.stop,
                                            color: colors.red,
                                            onPressed: _closeShift,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                        if (_selectedTab == 1) ...[
                          SectionLabel('Счета'),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${store.accounts.length} '
                                  '${accountsWord(store.accounts.length)} · '
                                  '${_money(store.totalBalanceCents())}',
                                  style: TextStyle(
                                    color: colors.secondaryLabel,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              ChipButton(
                                label: 'Добавить',
                                icon: CupertinoIcons.plus,
                                onPressed: _newAccount,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          AppCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < store.accounts.length; i++) ...[
                                  if (i > 0) const Hairline(indent: 12),
                                  ListRow(
                                    title: store.accounts[i].name,
                                    subtitle: store.accounts[i].type,
                                    icon: CupertinoIcons.creditcard,
                                    dense: true,
                                    trailing: Text(
                                      _money(
                                        store.balanceCents(
                                          store.accounts[i].id,
                                        ),
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_selectedTab == 2) ...[
                          SectionLabel('Категории'),
                          _buildCategoriesSection(store),
                          const SizedBox(height: 16),
                        ],
                        if (_selectedTab == 3) ...[
                          SectionLabel('План'),
                          _buildPlanSection(store),
                          const SizedBox(height: 16),
                        ],
                        // Вкладка "Операции" - продолжаем с платежей
                        if (_selectedTab == 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SectionLabel(
                                  'Регулярные платежи · '
                                  '${recurringFiltered.length}',
                                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                                ),
                              ),
                              ChipButton(
                                label: switch (_recurringStatusFilter) {
                                  'active' => 'Активные',
                                  'disabled' => 'Выключенные',
                                  _ => 'Все',
                                },
                                icon: CupertinoIcons.line_horizontal_3_decrease,
                                onPressed: () async {
                                  final v =
                                      await showCupertinoModalPopup<String>(
                                        context: context,
                                        builder: (dialogContext) =>
                                            CupertinoActionSheet(
                                              title: const Text('Статус'),
                                              actions: [
                                                CupertinoActionSheetAction(
                                                  onPressed: () => Navigator.of(
                                                    dialogContext,
                                                  ).pop('all'),
                                                  child: const Text('Все'),
                                                ),
                                                CupertinoActionSheetAction(
                                                  onPressed: () => Navigator.of(
                                                    dialogContext,
                                                  ).pop('active'),
                                                  child: const Text('Активные'),
                                                ),
                                                CupertinoActionSheetAction(
                                                  onPressed: () => Navigator.of(
                                                    dialogContext,
                                                  ).pop('disabled'),
                                                  child: const Text(
                                                    'Выключенные',
                                                  ),
                                                ),
                                              ],
                                              cancelButton:
                                                  CupertinoActionSheetAction(
                                                    onPressed: () => Navigator.of(
                                                      dialogContext,
                                                    ).pop(),
                                                    child: const Text('Отмена'),
                                                  ),
                                            ),
                                      );
                                  if (v != null) {
                                    setState(() => _recurringStatusFilter = v);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (recurringFiltered.isEmpty)
                            EmptyState(
                              title: 'Нет регулярных платежей',
                              message:
                                  'Добавьте регулярные расходы или поступления.',
                              art: Icon(
                                CupertinoIcons.repeat,
                                size: 36,
                                color: const Color(0xFFB2B2B6),
                              ),
                            )
                          else
                            AppCard(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                              child: Column(
                                children: [
                                  for (
                                    int gi = 0;
                                    gi < recurringMonthKeys.length;
                                    gi++
                                  ) ...[
                                    if (gi > 0) const SizedBox(height: 10),
                                    Text(
                                      DateFormat(
                                        'LLLL yyyy',
                                        'ru',
                                      ).format(recurringMonthKeys[gi]),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        letterSpacing: 0.4,
                                        color: colors.secondaryLabel,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    for (
                                      int pi = 0;
                                      pi <
                                          recurringGroups[recurringMonthKeys[gi]]!
                                              .length;
                                      pi++
                                    ) ...[
                                      if (pi > 0) const Hairline(),
                                      _recurringRow(
                                        store,
                                        recurringGroups[recurringMonthKeys[gi]]![pi],
                                        colors,
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChipButton(
                                label: 'Добавить платёж',
                                icon: CupertinoIcons.repeat,
                                onPressed: _addRecurringPayment,
                              ),
                              ChipButton(
                                label: 'Провести плановые',
                                icon: CupertinoIcons.play,
                                onPressed: _runDueRecurring,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (settings.teamEnabled) ...[
                            Row(
                              children: [
                                Expanded(child: SectionLabel('Команда')),
                                ChipButton(
                                  label: 'Все',
                                  icon: CupertinoIcons.person_2,
                                  onPressed: () => Navigator.of(context).push(
                                    CupertinoPageRoute(
                                      builder: (_) => const EmployeesScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            ..._teamCards(store, colors),
                            const SizedBox(height: 16),
                          ],
                          SectionLabel('Должны мне · ${_money(totalDebt)}'),
                          debtClients.isEmpty
                              ? EmptyState(
                                  title: 'Долгов нет',
                                  message: 'Все расчёты закрыты.',
                                  art: Icon(
                                    CupertinoIcons.checkmark_seal,
                                    size: 36,
                                    color: const Color(0xFFB2B2B6),
                                  ),
                                )
                              : AppCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Column(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < debtClients.length;
                                        i++
                                      ) ...[
                                        if (i > 0) const Hairline(indent: 12),
                                        ListRow(
                                          title:
                                              (debtClients[i]['client']
                                                      as dynamic)
                                                  .name,
                                          icon: CupertinoIcons.person,
                                          iconColor: colors.orange,
                                          dense: true,
                                          trailing: Text(
                                            _money(
                                              debtClients[i]['debt'] as int,
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                          const SizedBox(height: 8),
                          if (settings.creditsEnabled &&
                              store.clientCreditTotalCents > 0) ...[
                            AppCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: ListRow(
                                dense: true,
                                icon: CupertinoIcons.creditcard,
                                iconColor: colors.orange,
                                title: 'Обязательства перед клиентами',
                                subtitle:
                                    'получено и ещё не отработано · '
                                    '${countLabel(store.credits.where((c) => c.deletedAt == null && c.isActive).length, ['кредит', 'кредита', 'кредитов'])}',
                                trailing: Text(
                                  _money(store.clientCreditTotalCents),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                showChevron: true,
                                onTap: () => Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder: (_) =>
                                        const ClientCreditsScreen(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _txQuery.isEmpty
                                      ? '${store.moneyTransactions.length} '
                                            '${operationsWord(store.moneyTransactions.length)}'
                                      : 'Поиск: $_txQuery',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.secondaryLabel,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (_txQuery.isNotEmpty)
                                ChipButton(
                                  label: 'Сбросить',
                                  icon: CupertinoIcons.xmark,
                                  onPressed: () => setState(() {
                                    _txQuery = '';
                                    _txSearchController.clear();
                                  }),
                                )
                              else
                                ChipButton(
                                  label: 'Поиск',
                                  icon: CupertinoIcons.search,
                                  onPressed: _showTxSearch,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChipButton(
                                label: switch (_directionFilter) {
                                  'in' => 'Приходы',
                                  'out' => 'Расходы',
                                  _ => 'Все операции',
                                },
                                icon: CupertinoIcons.arrow_left_right,
                                onPressed: () async {
                                  final v = await showCupertinoModalPopup<String>(
                                    context: context,
                                    builder: (dialogContext) =>
                                        CupertinoActionSheet(
                                          title: const Text('Направление'),
                                          actions: [
                                            CupertinoActionSheetAction(
                                              onPressed: () => Navigator.of(
                                                dialogContext,
                                              ).pop('all'),
                                              child: const Text('Все'),
                                            ),
                                            CupertinoActionSheetAction(
                                              onPressed: () => Navigator.of(
                                                dialogContext,
                                              ).pop('in'),
                                              child: const Text('Приходы'),
                                            ),
                                            CupertinoActionSheetAction(
                                              onPressed: () => Navigator.of(
                                                dialogContext,
                                              ).pop('out'),
                                              child: const Text('Расходы'),
                                            ),
                                          ],
                                          cancelButton: CupertinoActionSheetAction(
                                            onPressed: () =>
                                                Navigator.of(dialogContext).pop(),
                                            child: const Text('Отмена'),
                                          ),
                                        ),
                                  );
                                  if (v != null) {
                                    setState(() => _directionFilter = v);
                                  }
                                },
                              ),
                              ChipButton(
                                label: _accountFilter == null
                                    ? 'Все счета'
                                    : (store
                                              .accountById(_accountFilter!)
                                              ?.name ??
                                          'Счёт'),
                                icon: CupertinoIcons.creditcard,
                                onPressed: () async {
                                  final v =
                                      await showCupertinoModalPopup<String?>(
                                        context: context,
                                        builder: (dialogContext) => Container(
                                          height: 280,
                                          color: context.colors.card,
                                          child: Column(
                                            children: [
                                              CupertinoButton(
                                                child: const Text('Все счета'),
                                                onPressed: () => Navigator.of(
                                                  dialogContext,
                                                ).pop('__all__'),
                                              ),
                                              Expanded(
                                                child: ListView(
                                                  children: [
                                                    for (final a
                                                        in store.accounts
                                                            .where(
                                                              (x) =>
                                                                  !x.archived,
                                                            ))
                                                      CupertinoButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                              dialogContext,
                                                            ).pop(a.id),
                                                        child: Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: Text(a.name),
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
                                    setState(() => _accountFilter = null);
                                  } else if (v != null) {
                                    setState(() => _accountFilter = v);
                                  }
                                },
                              ),
                              ChipButton(
                                label: _formatDate(),
                                icon: CupertinoIcons.calendar,
                                onPressed: _openDateFilter,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SectionLabel(
                            'Журнал · ${store.moneyTransactions.length}',
                          ),
                          store.moneyTransactions.isEmpty
                              ? EmptyState(
                                  title: 'Нет операций',
                                  message: 'Добавьте продажу или расход.',
                                  art: Icon(
                                    CupertinoIcons.doc_text,
                                    size: 36,
                                    color: const Color(0xFFB2B2B6),
                                  ),
                                )
                              : Column(
                                  children: store.moneyTransactions
                                      .where((t) {
                                        if (t.voided) return false;
                                        if (_directionFilter != 'all' &&
                                            t.direction != _directionFilter) {
                                          return false;
                                        }
                                        if (_accountFilter != null &&
                                            t.accountId != _accountFilter) {
                                          return false;
                                        }
                                        if (_dateFrom != null &&
                                            t.createdAt.isBefore(_dateFrom!)) {
                                          return false;
                                        }
                                        if (_dateTo != null) {
                                          final endOfDay = DateTime(
                                            _dateTo!.year,
                                            _dateTo!.month,
                                            _dateTo!.day + 1,
                                          );
                                          if (t.createdAt.isAfter(endOfDay)) {
                                            return false;
                                          }
                                        }
                                        final q = _txQuery.trim().toLowerCase();
                                        if (q.isNotEmpty) {
                                          final clientId = t.clientId;
                                          final jobId = t.jobId;
                                          final clientName = clientId == null
                                              ? ''
                                              : (store
                                                        .clientById(clientId)
                                                        ?.name ??
                                                    clientId);
                                          final accountName =
                                              store
                                                  .accountById(t.accountId)
                                                  ?.name ??
                                              t.accountId;
                                          final jobTitle = jobId == null
                                              ? ''
                                              : (store.jobById(jobId)?.title ??
                                                    jobId);
                                          final haystack = [
                                            t.category,
                                            if (t.category.trim().isEmpty)
                                              'Чек категории',
                                            t.note ?? '',
                                            t.kind,
                                            clientName,
                                            accountName,
                                            jobTitle,
                                          ].join(' ').toLowerCase();
                                          if (!haystack.contains(q)) {
                                            return false;
                                          }
                                        }
                                        return true;
                                      })
                                      .take(50)
                                      .map((t) {
                                        final acc = store.accountById(
                                          t.accountId,
                                        );
                                        final isReversal = t.reversesId != null;
                                        final alreadyReversed = store
                                            .moneyTransactions
                                            .any((tx) => tx.reversesId == t.id);
                                        final rowColor =
                                            alreadyReversed || isReversal
                                            ? colors.tertiaryLabel
                                            : null;
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: AppCard(
                                            onTap: () =>
                                                _showTransactionDetail(t),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            t.category.isEmpty
                                                                ? t.kind
                                                                : t.category,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: rowColor,
                                                            ),
                                                          ),
                                                          if (alreadyReversed) ...[
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            const Text(
                                                              '↩︎',
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Text(
                                                              'Возвращено',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: colors
                                                                    .tertiaryLabel,
                                                              ),
                                                            ),
                                                          ],
                                                          if (isReversal) ...[
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            GestureDetector(
                                                              onTap: () {
                                                                final originId =
                                                                    t.reversesId!;
                                                                Navigator.of(
                                                                  context,
                                                                ).pop();
                                                                _showTransactionDetailById(
                                                                  originId,
                                                                );
                                                              },
                                                              child: Text(
                                                                '↩ исходная',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: colors
                                                                      .accent,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      Text(
                                                        [
                                                          acc?.name ?? '',
                                                          if (t.note != null &&
                                                              t
                                                                  .note!
                                                                  .isNotEmpty)
                                                            t.note!,
                                                          DateFormat(
                                                            'd MMM, HH:mm',
                                                            'ru',
                                                          ).format(t.createdAt),
                                                        ].join(' • '),
                                                        style: TextStyle(
                                                          color: colors
                                                              .secondaryLabel,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  '${t.direction == 'in' ? '+' : '-'}${_money(t.amountCents)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        alreadyReversed ||
                                                            isReversal
                                                        ? colors.tertiaryLabel
                                                        : (t.direction == 'in'
                                                              ? colors.green
                                                              : colors.red),
                                                  ),
                                                ),
                                                if (alreadyReversed)
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: colors
                                                          .tertiaryLabel
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: const Text(
                                                      'Возвращено',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Color(
                                                          0xFFB2B2B6,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                else if (isReversal)
                                                  CupertinoButton(
                                                    padding: EdgeInsets.zero,
                                                    onPressed: () {
                                                      final originId =
                                                          t.reversesId!;
                                                      Navigator.of(context)
                                                          .pop();
                                                      _showTransactionDetailById(
                                                        originId,
                                                      );
                                                    },
                                                    child: Icon(
                                                      CupertinoIcons
                                                          .arrow_turn_down_right,
                                                      size: 14,
                                                      color: colors.label,
                                                    ),
                                                  )
                                                else
                                                  CupertinoButton(
                                                    padding: EdgeInsets.zero,
                                                    onPressed: () async {
                                                      final ok =
                                                          await showAppConfirm(
                                                            context,
                                                            title: 'Сделать возврат?',
                                                            message:
                                                                'Будет создана новая операция-возврат на ${_money(t.amountCents)}, исходная станет серой.',
                                                            destructive: false,
                                                            confirmLabel:
                                                                'Возвратить',
                                                          );
                                                      if (!ok || !mounted)
                                                        return;
                                                      try {
                                                        await store
                                                            .revertTransaction(
                                                              t.id,
                                                            );
                                                      } catch (e) {
                                                        if (context.mounted) {
                                                          showCupertinoDialog<
                                                            void
                                                          >(
                                                            context: context,
                                                            builder: (ctx) => CupertinoAlertDialog(
                                                              title: const Text(
                                                                'Ошибка',
                                                              ),
                                                              content: Text(
                                                                e.toString(),
                                                              ),
                                                              actions: [
                                                                CupertinoDialogAction(
                                                                  child:
                                                                      const Text(
                                                                        'ОК',
                                                                      ),
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                        ctx,
                                                                      ).pop(),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    },
                                                    child: Icon(
                                                      CupertinoIcons
                                                          .arrow_uturn_left,
                                                      size: 14,
                                                      color: colors.label,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      })
                                      .toList(),
                                ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _recurringRow(
    MastersStore store,
    RecurringPayment p,
    AppColors colors,
  ) {
    final due = p.nextDueAt;
    final dueText =
        '${due.day.toString().padLeft(2, '0')}.'
        '${due.month.toString().padLeft(2, '0')}.${due.year}';
    final everyN = p.intervalDays == 1
        ? 'каждый день'
        : 'каждые ${p.intervalDays} ${daysWord(p.intervalDays)}';
    return ListRow(
      title: p.name,
      subtitle:
          '${p.direction == 'in' ? 'Приход' : 'Расход'} · $everyN · $dueText',
      dense: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${p.direction == 'in' ? '+' : '−'}${_money(p.amountCents)}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: p.direction == 'in' ? colors.green : colors.red,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          OverflowMenuButton(
            size: 18,
            title: p.name,
            actions: [
              CupertinoActionSheetAction(
                onPressed: () => _editRecurringPayment(p),
                child: const Text('Изменить'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => store.updateRecurringPayment(
                  p.copyWith(active: !p.active),
                ),
                child: Text(p.active ? 'Выключить' : 'Включить'),
              ),
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () => store.deleteRecurringPayment(p.id),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection(MastersStore store) {
    final incomeCats = <String>{};
    final expenseCats = <String>{};
    for (final t in store.moneyTransactions) {
      if (t.category.isNotEmpty) {
        if (t.direction == 'in') {
          incomeCats.add(t.category);
        } else {
          expenseCats.add(t.category);
        }
      }
    }
    final incomeList = incomeCats.toList()..sort();
    final expenseList = expenseCats.toList()..sort();

    if (incomeList.isEmpty && expenseList.isEmpty) {
      return const EmptyState(
        title: 'Нет категорий',
        message: 'Категории появятся после добавления операций.',
        art: Icon(CupertinoIcons.tag, size: 36, color: Color(0xFFB2B2B6)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (incomeList.isNotEmpty) ...[
          _categoryGroup('Доходы', incomeList, context.colors.green),
          const SizedBox(height: 12),
        ],
        if (expenseList.isNotEmpty) ...[
          _categoryGroup('Расходы', expenseList, context.colors.red),
        ],
      ],
    );
  }

  Widget _categoryGroup(String title, List<String> categories, Color tint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: SectionLabel(title)),
            Text(
              '${categories.length} ${itemsWord(categories.length)}',
              style: TextStyle(
                color: context.colors.tertiaryLabel,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final category in categories)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: context.colors.tint(tint, 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: tint,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _counterpartyName(MastersStore store, Obligation o) {
    if (o.counterpartyType == 'client') {
      return store.clientById(o.counterpartyId ?? '')?.name ?? 'Клиент';
    }
    if (o.counterpartyType == 'supplier') {
      for (final s in store.suppliers) {
        if (s.id == o.counterpartyId) return s.name;
      }
      return 'Поставщик';
    }
    return o.kindLabel;
  }

  Future<void> _payObligationFlow(Obligation o) async {
    final store = context.read<MastersStore>();
    if (store.accounts.every((a) => a.archived)) {
      if (!mounted) return;
      await showAppAlert(
        context,
        title: 'Нет счёта',
        message: 'Сначала создайте счёт в разделе «Счета»',
      );
      return;
    }
    final amountStr = await _prompt(
      'Оплата · ${_money(o.remainingCents)}',
      (o.remainingCents / 100).toStringAsFixed(0),
    );
    if (amountStr == null) return;
    final amount =
        ((double.tryParse(amountStr.replaceAll(',', '.')) ?? 0) * 100).round();
    if (amount <= 0) return;
    final accountId = await _pickAccount();
    if (accountId == null || !mounted) return;
    final selectedMethod = await showPaymentMethodPicker(context);
    if (!mounted) return;

    try {
      await store.payObligation(
        o.id,
        amountCents: amount,
        accountId: accountId,
        paymentMethod: selectedMethod,
      );
    } catch (e) {
      if (mounted) {
        await showAppAlert(context, title: 'Ошибка', message: e.toString());
      }
    }
  }

  Future<void> _addPayableSheet() async {
    final store = context.read<MastersStore>();
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    var kind = 'other';
    var dueAt = DateTime.now().add(const Duration(days: 7));
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.72,
          color: context.colors.card,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Кому я должен',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: titleController,
                  placeholder: 'Название (аренда, налог, поставщик…)',
                  decoration: BoxDecoration(
                    color: const Color(0x00FFFFFF),
                    border: Border.all(color: context.colors.separator),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: amountController,
                  placeholder: 'Сумма 0.00',
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
                KeyValueRow(
                  'Категория',
                  Obligation(
                    id: '',
                    direction: 'payable',
                    kind: kind,
                    title: '',
                    amountCents: 0,
                    dueAt: dueAt,
                    createdAt: dueAt,
                    updatedAt: dueAt,
                  ).kindLabel,
                  onTap: () async {
                    final v = await showCupertinoModalPopup<String>(
                      context: builderContext,
                      builder: (ctx) => CupertinoActionSheet(
                        title: const Text('Категория'),
                        actions: [
                          for (final k in const [
                            'supplier_bill',
                            'tax',
                            'salary',
                            'rent',
                            'loan',
                            'other',
                          ])
                            CupertinoActionSheetAction(
                              onPressed: () => Navigator.of(ctx).pop(k),
                              child: Text(
                                Obligation(
                                  id: '',
                                  direction: 'payable',
                                  kind: k,
                                  title: '',
                                  amountCents: 0,
                                  dueAt: dueAt,
                                  createdAt: dueAt,
                                  updatedAt: dueAt,
                                ).kindLabel,
                              ),
                            ),
                        ],
                        cancelButton: CupertinoActionSheetAction(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Отмена'),
                        ),
                      ),
                    );
                    if (v != null) setModalState(() => kind = v);
                  },
                ),
                KeyValueRow(
                  'Срок',
                  DateFormat('d MMM yyyy', 'ru').format(dueAt),
                  onTap: () async {
                    DateTime selected = dueAt;
                    await showCupertinoModalPopup<void>(
                      context: builderContext,
                      builder: (pickerContext) => Container(
                        height: 300,
                        color: context.colors.card,
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                CupertinoButton(
                                  child: const Text('Отмена'),
                                  onPressed: () =>
                                      Navigator.of(pickerContext).pop(),
                                ),
                                CupertinoButton(
                                  child: const Text('Готово'),
                                  onPressed: () {
                                    Navigator.of(pickerContext).pop();
                                    setModalState(
                                      () => dueAt = DateTime(
                                        selected.year,
                                        selected.month,
                                        selected.day,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            Expanded(
                              child: CupertinoDatePicker(
                                mode: CupertinoDatePickerMode.date,
                                initialDateTime: selected,
                                onDateTimeChanged: (dt) => selected = dt,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                SecondaryButton(
                  label: 'Добавить',
                  icon: CupertinoIcons.plus,
                  onPressed: () async {
                    final title = titleController.text.trim();
                    final amount =
                        ((double.tryParse(
                                      amountController.text.trim().replaceAll(
                                        ',',
                                        '.',
                                      ),
                                    ) ??
                                    0) *
                                100)
                            .round();
                    if (title.isEmpty || amount <= 0) return;
                    await store.createPayable(
                      kind: kind,
                      title: title,
                      amountCents: amount,
                      dueAt: dueAt,
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _obligationRow(MastersStore store, Obligation o, AppColors colors) {
    final income = o.isIncome;
    final tint = income ? colors.green : colors.red;
    final overdue = o.isOverdue;
    final paidPart = o.paidCents > 0;
    return ListRow(
      title: o.title,
      subtitle:
          '${_counterpartyName(store, o)} · ${o.kindLabel} · '
          '${DateFormat('d MMM', 'ru').format(o.dueAt)}'
          '${paidPart ? ' · внесено ${_money(o.paidCents)}' : ''}',
      titleColor: overdue ? colors.red : null,
      dense: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _money(o.remainingCents),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: tint,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          OverflowMenuButton(
            size: 18,
            title: o.title,
            actions: [
              CupertinoActionSheetAction(
                onPressed: () => _payObligationFlow(o),
                child: Text(income ? 'Принять оплату' : 'Заплатить'),
              ),
              if (income && o.jobId != null)
                CupertinoActionSheetAction(
                  onPressed: () async {
                    final client = store.clientById(o.counterpartyId ?? '');
                    final job = o.jobId == null ? null : store.jobById(o.jobId!);
                    final paymentMethod = o.paymentMethod;
                    final result = await shareReminderText(
                      paymentReminderText(
                        clientName: client?.name ?? 'Клиент',
                        jobTitle: job?.title ?? o.title,
                        remainingCents: o.remainingCents,
                        dueAt: o.dueAt,
                        paymentMethod: paymentMethod,
                        paymentMethodLabels: kPaymentMethods,
                      ),
                    );
                    if (!mounted) return;
                    if (result == ReminderShareResult.shared) {
                      await showAppAlert(
                        context,
                        title: 'Отправлено',
                        message: 'Спасибо, напоминание отправлено.',
                      );
                    } else if (result == ReminderShareResult.copied) {
                      await showAppAlert(
                        context,
                        title: 'Текст скопирован',
                        message: 'Откройте WhatsApp/Telegram и вставьте.',
                      );
                    }
                  },
                  child: const Text('Напомнить клиенту'),
                ),
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () => store.cancelObligation(o.id),
                child: const Text('Отменить обязательство'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Детали кассового плана (§Э2.3): свёрнутый «Прогноз» разворачивается
  /// модалкой, чтобы на вкладке «План» не висела простыня цифр, когда
  /// разрыва нет и смотреть не на что.
  Future<void> _showCashPlanDetails(
    List<CashPlanDay> plan,
    int totalIn,
    int totalOut,
  ) async {
    final colors = context.colors;
    final balance = context.read<MastersStore>().totalBalanceCents();
    final eventDays =
        plan.where((d) => d.incoming > 0 || d.outgoing > 0).toList();

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => Container(
        height: 420,
        color: colors.card,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Закрыть'),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
                const Text(
                  'Кассовый план',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 64),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                children: [
                  KeyValueRow('Сейчас на счетах', _money(balance), emphasis: true),
                  KeyValueRow(
                    'Ожидается (дебиторка)',
                    '+${_money(totalIn)}',
                    valueColor: colors.green,
                  ),
                  KeyValueRow(
                    'К оплате (кредиторка)',
                    '−${_money(totalOut)}',
                    valueColor: colors.red,
                  ),
                  if (plan.isNotEmpty)
                    KeyValueRow(
                      'Прогноз на 6 недель',
                      _money(plan.last.balanceEnd),
                      emphasis: true,
                      valueColor:
                          plan.last.balanceEnd < 0 ? colors.red : null,
                    ),
                  if (eventDays.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SectionLabel('Дни с движениями'),
                    for (final d in eventDays)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 74,
                              child: Text(
                                DateFormat('d MMM', 'ru').format(d.date),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.secondaryLabel,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                d.incoming > 0 ? '+${_money(d.incoming)}' : '',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.green,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                d.outgoing > 0 ? '−${_money(d.outgoing)}' : '',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.red,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 92,
                              child: Text(
                                _money(d.balanceEnd),
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: d.isGap ? colors.red : colors.label,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanSection(MastersStore store) {
    final colors = context.colors;
    final receivables = store.receivables()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final payables = store.payables()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final totalIn = receivables.fold<int>(0, (s, o) => s + o.remainingCents);
    final totalOut = payables.fold<int>(0, (s, o) => s + o.remainingCents);
    final plan = store.cashPlan();
    CashPlanDay? firstGap;
    for (final d in plan) {
      if (d.isGap) {
        firstGap = d;
        break;
      }
    }

    // Компактный «Прогноз» (§Э2.3): разрыв — пилюля с датой, иначе одна
    // строка про запас. Остаток, дебиторка и разбивка по дням уходят в
    // модалку: без разрыва вкладка «План» не должна занимать экран.
    final weeks = (plan.length / 7).floor();
    final summary = firstGap != null
        ? 'разрыв ${DateFormat('d MMM', 'ru').format(firstGap.date)}'
        : plan.isEmpty
            ? 'Прогноз пуст'
            : 'Запас $weeks ${pluralRu(weeks, ['неделя', 'недели', 'недель'])}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: firstGap != null
                    ? Pill(
                        summary,
                        color: colors.orange,
                        icon: CupertinoIcons.exclamationmark_triangle_fill,
                      )
                    : Text(
                        summary,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: colors.secondaryLabel,
                        ),
                      ),
              ),
              ChipButton(
                label: 'Детали',
                icon: CupertinoIcons.list_bullet,
                color: firstGap != null ? colors.orange : colors.accent,
                onPressed: () => _showCashPlanDetails(plan, totalIn, totalOut),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SectionLabel(
                'Должны мне · ${receivables.length}',
                padding: EdgeInsets.zero,
              ),
            ),
            Text(
              _money(totalIn),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.green,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (receivables.isEmpty)
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Text(
              'Дебиторки нет — все заказы оплачены.',
              style: TextStyle(fontSize: 13, color: colors.secondaryLabel),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < receivables.length; i++) ...[
                  if (i > 0) const Hairline(indent: 12),
                  _obligationRow(store, receivables[i], colors),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SectionLabel(
                'Я должен · ${payables.length}',
                padding: EdgeInsets.zero,
              ),
            ),
            Text(
              _money(totalOut),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.red,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (payables.isEmpty)
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Text(
              'Кредиторки нет — расходных обязательств нет.',
              style: TextStyle(fontSize: 13, color: colors.secondaryLabel),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < payables.length; i++) ...[
                  if (i > 0) const Hairline(indent: 12),
                  _obligationRow(store, payables[i], colors),
                ],
              ],
            ),
          ),
        const SizedBox(height: 10),
        ChipButton(
          label: 'Добавить расходное обязательство',
          icon: CupertinoIcons.plus,
          color: colors.red,
          onPressed: _addPayableSheet,
        ),
      ],
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.label, this.value, {this.isLink = false, this.onTap});
  final String label;
  final String value;
  final bool isLink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return KeyValueRow(
      label,
      value,
      onTap: isLink ? onTap : null,
      valueColor: isLink && onTap != null ? context.colors.accent : null,
    );
  }
}

