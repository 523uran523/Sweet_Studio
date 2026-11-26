import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../app/tax_radar_bar.dart';
import '../../core/backup_service.dart';
import '../../core/reminder_service.dart';
import '../../core/app_biometric.dart';
import '../../core/update_service.dart';
import '../../data/models/job.dart';
import '../../state/masters_store.dart';
import '../../state/settings_controller.dart';
import '../jobs/job_constants.dart';
import 'sync_card.dart';
import '../../core/money_format.dart';

/// Настройки разложены по шести группам: каждая группа — отдельная
/// подвкладка, поэтому экран не превращается в простыню на 2000 строк.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _sections = <(String, IconData)>[
    ('Работа', CupertinoIcons.settings_solid),
    ('Деньги', CupertinoIcons.money_dollar),
    ('Вид', CupertinoIcons.paintbrush),
    ('Защита', CupertinoIcons.lock),
    ('Данные', CupertinoIcons.archivebox),
    ('Обновления', CupertinoIcons.cloud_download),
  ];

  int _section = 0;
  bool _busy = false;
  bool _auditBusy = false;
  bool _updateBusy = false;
  bool _mirrorBusy = false;
  UpdateInfo? _updateInfo;
  String _updateStatus = '';
  String _mirrorStatus = '';
  bool _mirrorInitialized = false;
  final _tagController = TextEditingController();
  final _objectTermController = TextEditingController();
  final _clientTermController = TextEditingController();
  final _mirrorUrlController = TextEditingController();

  @override
  void dispose() {
    _tagController.dispose();
    _objectTermController.dispose();
    _clientTermController.dispose();
    _mirrorUrlController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_mirrorInitialized) {
      _mirrorInitialized = true;
      final settings = context.read<SettingsController>();
      _mirrorUrlController.text = settings.updateMirrorUrl;
      _objectTermController.text = settings.objectTerm;
      _clientTermController.text = settings.clientTerm;
    }
  }

  // ─────────────────────────── ввод значения ───────────────────────────

  Future<String?> _promptValue(
    String title,
    String initial, {
    bool obscure = false,
    bool numeric = false,
  }) {
    final controller = TextEditingController(text: initial);
    return showCupertinoDialog<String?>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            obscureText: obscure,
            autofocus: true,
            keyboardType: numeric ? TextInputType.number : null,
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
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── работа ───────────────────────────

  Future<void> _applyPreset(String preset) async {
    await context.read<SettingsController>().applyConfigPreset(preset);
    if (mounted) setState(() {});
  }

  /// Включает или выключает учёт по точкам (§5.6, §12.2).
  ///
  /// Идёт через store, а не через `SettingsController` напрямую: при первом
  /// включении тот заводит «Основной склад» и переносит на него текущие
  /// остатки, и владельцу нужно это показать — иначе он решит, что склад
  /// появился «из воздуха».
  Future<void> _setLocations(bool value) async {
    final store = context.read<MastersStore>();
    await store.setLocationsEnabled(value);
    if (!mounted) return;
    if (value) {
      await showAppAlert(
        context,
        title: 'Учёт по точкам',
        message:
            'Создан «Основной склад», текущие остатки перенесены на него. '
            'Добавить точки и оформить перемещение можно на экране «Склад».',
      );
    }
  }

  Future<void> _saveTerms() async {
    final settings = context.read<SettingsController>();
    await settings.setObjectTerm(_objectTermController.text.trim());
    await settings.setClientTerm(_clientTermController.text.trim());
    if (!mounted) return;
    await showAppAlert(
      context,
      title: 'Готово',
      message: 'Термины сохранены.',
    );
  }

  Widget _workSection(SettingsController settings) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
      children: [
        SectionLabel('Режим работы'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _CheckRow(
                title: 'Только заказы (дедлайны)',
                checked: settings.workMode == 'orders',
                onTap: () => settings.setWorkMode('orders'),
              ),
              const Hairline(),
              _CheckRow(
                title: 'Только записи (календарь)',
                checked: settings.workMode == 'appointments',
                onTap: () => settings.setWorkMode('appointments'),
              ),
              const Hairline(),
              _CheckRow(
                title: 'Оба потока (гибрид)',
                checked: settings.workMode == 'hybrid',
                onTap: () => settings.setWorkMode('hybrid'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Что показывать'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SwitchRow(
                title: 'Калькулятор цен',
                value: settings.calculatorEnabled,
                onChanged: settings.setCalculatorEnabled,
              ),
              const Hairline(),
              _SwitchRow(
                title: 'Сотрудники и зарплата',
                value: settings.teamEnabled,
                onChanged: settings.setTeamEnabled,
              ),
              const Hairline(),
              _SwitchRow(
                title: 'Заявки и КП',
                value: settings.leadsEnabled,
                onChanged: settings.setLeadsEnabled,
              ),
              const Hairline(),
              _SwitchRow(
                title: 'Депозиты и сертификаты',
                value: settings.creditsEnabled,
                onChanged: settings.setCreditsEnabled,
              ),
              const Hairline(),
              _SwitchRow(
                title: 'Несколько точек',
                value: settings.locationsEnabled,
                onChanged: (value) => _setLocations(value),
              ),
              const Hairline(),
              _SwitchRow(
                title: 'Теги в заказах',
                value: settings.jobTagsEnabled,
                onChanged: settings.setJobTagsEnabled,
              ),
              const Hairline(),
              _SwitchRow(
                title: 'Смена кассы',
                value: settings.cashShiftEnabled,
                onChanged: settings.setCashShiftEnabled,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Колонки канбана'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < kanbanColumns.length; i++) ...[
                if (i > 0) const Hairline(),
                _CheckRow(
                  title: kanbanColumns[i].label,
                  checked: settings.kanbanColumnEnabled(kanbanColumns[i].key),
                  onTap: () => _toggleKanbanColumn(kanbanColumns[i].key),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Теги заказов'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _tagController,
                      placeholder: 'Новый тег',
                      padding: const EdgeInsets.all(10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChipButton(
                    label: 'Добавить',
                    icon: CupertinoIcons.plus,
                    onPressed: () async {
                      await settings.addJobTag(_tagController.text);
                      _tagController.clear();
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
              if (settings.jobTags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in settings.jobTags)
                      GestureDetector(
                        onTap: () async {
                          await settings.removeJobTag(tag);
                          if (mounted) setState(() {});
                        },
                        child: Pill(tag, icon: CupertinoIcons.xmark),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Термины и ставка'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoTextField(
                controller: _objectTermController,
                placeholder: 'Термин объекта',
                padding: const EdgeInsets.all(10),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _clientTermController,
                placeholder: 'Термин клиента',
                padding: const EdgeInsets.all(10),
              ),
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'Сохранить термины',
                icon: CupertinoIcons.checkmark,
                onPressed: _saveTerms,
              ),
              const SizedBox(height: 12),
              const Hairline(),
              const SizedBox(height: 12),
              KeyValueRow(
                'Ставка за час',
                '${money(settings.hourRateCents)}',
                emphasis: true,
                onTap: _editHourRate,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Типовые конфигурации'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChipButton(
              label: 'Соло-мастер',
              icon: CupertinoIcons.person,
              onPressed: () => _applyPreset('solo'),
            ),
            ChipButton(
              label: 'Мастер + бригада',
              icon: CupertinoIcons.person_2,
              onPressed: () => _applyPreset('team'),
            ),
            ChipButton(
              label: 'Мастер + клиенты',
              icon: CupertinoIcons.person_crop_circle_badge_plus,
              onPressed: () => _applyPreset('clients'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleKanbanColumn(String key) async {
    final settings = context.read<SettingsController>();
    final next = <String>[...settings.kanbanColumns];
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    await settings.setKanbanColumns(next);
    if (mounted) setState(() {});
  }

  Future<void> _editHourRate() async {
    final settings = context.read<SettingsController>();
    final v = await _promptValue(
      'Ставка за час, ${moneySymbol}',
      settings.hourRateCents.toString(),
      numeric: true,
    );
    if (v == null || !mounted) return;
    await settings.setHourRateCents(int.tryParse(v) ?? 0);
    if (mounted) setState(() {});
  }

  // ─────────────────────────── деньги ───────────────────────────

  String _taxFlag(String country) => switch (country.toUpperCase()) {
    'RU' => '🇷🇺',
    'KZ' => '🇰🇿',
    'US' => '🇺🇸',
    _ => '🌐',
  };

  Future<void> _editTaxProfile({TaxProfile? existing}) async {
    final countryController = TextEditingController(
      text: existing?.country ?? '',
    );
    final nameController = TextEditingController(text: existing?.name ?? '');
    final rateController = TextEditingController(
      text: existing?.ratePercent.toString() ?? '',
    );

    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(existing == null ? 'Налоговый профиль' : 'Профиль'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              CupertinoTextField(
                controller: countryController,
                placeholder: 'Страна (RU, KZ, US)',
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: BoxDecoration(
                  color: context.colors.card,
                  border: Border.all(color: context.colors.separator),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: nameController,
                placeholder: 'Название (например, УСН 6%)',
                decoration: BoxDecoration(
                  color: context.colors.card,
                  border: Border.all(color: context.colors.separator),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: rateController,
                placeholder: 'Ставка % (0-100)',
                keyboardType: TextInputType.number,
                decoration: BoxDecoration(
                  color: context.colors.card,
                  border: Border.all(color: context.colors.separator),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final country = countryController.text.trim().toUpperCase();
    final name = nameController.text.trim();
    final rate = int.tryParse(rateController.text.trim()) ?? 0;
    if (country.isEmpty || name.isEmpty) {
      await showAppAlert(
        context,
        title: 'Ошибка',
        message: 'Заполните страну и название.',
      );
      return;
    }

    final settings = context.read<SettingsController>();
    if (existing == null) {
      await settings.addTaxProfile(
        TaxProfile(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          country: country,
          name: name,
          ratePercent: rate.clamp(0, 100),
        ),
      );
    } else {
      await settings.updateTaxProfile(
        existing.copyWith(
          country: country,
          name: name,
          ratePercent: rate.clamp(0, 100),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  Widget _moneySection(SettingsController settings, MastersStore store) {
    final colors = context.colors;
    final taxPocketId = settings.taxAccountId;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
      children: [
        SectionLabel('Налоговые профили'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final profile in settings.taxProfiles) ...[
                if (profile.id != settings.taxProfiles.first.id)
                  const Hairline(),
                _TaxProfileRow(
                  profile: profile,
                  flag: _taxFlag(profile.country),
                  isActive: profile.id == settings.activeTaxProfileId,
                  onTap: () => _editTaxProfile(existing: profile),
                  onDelete: () async {
                    final ok = await showAppConfirm(
                      context,
                      title: 'Удалить профиль?',
                      message:
                          '${profile.country}, ${profile.name} (${profile.ratePercent}%)',
                      destructive: true,
                      confirmLabel: 'Удалить',
                    );
                    if (!ok || !mounted) return;
                    final removed = await settings.removeTaxProfile(profile.id);
                    if (!mounted) return;
                    if (!removed) {
                      await showAppAlert(
                        context,
                        title: 'Нельзя удалить',
                        message: 'Это активный профиль. Сначала выберите другой.',
                      );
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ChipButton(
              label: 'Добавить профиль',
              icon: CupertinoIcons.plus,
              onPressed: () => _editTaxProfile(),
            ),
            const SizedBox(width: 10),
            ChipButton(
              label: taxPocketId == null
                  ? 'Счёт-карман: нет'
                  : 'Карман: ${store.accountById(taxPocketId)?.name ?? '—'}',
              icon: CupertinoIcons.money_dollar_circle,
              onPressed: () => _pickTaxAccount(store),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionLabel('Налоговый радар (НПД)'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyValueRow(
                'Учитывать лимит 2,4 млн ${moneySymbol}/год',
                settings.taxRadarEnabled ? 'вкл' : 'выкл',
                onTap: () async {
                  await settings.setTaxRadarEnabled(!settings.taxRadarEnabled);
                  if (mounted) setState(() {});
                },
              ),
              KeyValueRow(
                'Лимит дохода',
                '${money(settings.taxIncomeLimitCents)}',
                onTap: () async {
                  final v = await _promptValue(
                    'Лимит дохода, ${moneySymbol}',
                    settings.taxIncomeLimitCents.toString(),
                    numeric: true,
                  );
                  if (v == null || !mounted) return;
                  await settings.setTaxIncomeLimitCents(
                    int.tryParse(v) ?? settings.taxIncomeLimitCents,
                  );
                  if (mounted) setState(() {});
                },
              ),
              if (settings.taxRadarEnabled && settings.npdLimitApplies) ...[
                const SizedBox(height: 8),
                TaxRadarBar(
                  incomeCents: store.annualIncomeCents(),
                  limitCents: settings.taxIncomeLimitCents,
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'При превышении лимита нужно зарегистрировать ИП или сменить схему.',
                style: TextStyle(fontSize: 12, color: colors.secondaryLabel),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Касса'),
        AppCard(
          padding: EdgeInsets.zero,
          child: _SwitchRow(
            title: 'Показывать смены кассы',
            value: settings.cashShiftEnabled,
            onChanged: settings.setCashShiftEnabled,
          ),
        ),
      ],
    );
  }

  Future<void> _pickTaxAccount(MastersStore store) async {
    final settings = context.read<SettingsController>();
    final choice = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Счёт-карман для налогов'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('__none__'),
            child: const Text('Без кармана'),
          ),
          for (final account in store.accounts.where((a) => !a.archived))
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(account.id),
              child: Text(account.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (choice == null) return;
    await settings.setTaxAccount(choice == '__none__' ? null : choice);
    if (mounted) setState(() {});
  }

  // ─────────────────────────── вид ───────────────────────────

  Future<void> _pickTheme() async {
    final settings = context.read<SettingsController>();
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Тема оформления'),
        actions: [
          for (final mode in AppThemeMode.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(mode.name),
              child: Text(mode.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await settings.setThemeMode(
      AppThemeMode.values.firstWhere(
        (mode) => mode.name == choice,
        orElse: () => settings.themeMode,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickReminderTime(SettingsController settings) async {
    var selected = DateTime(
      2024,
      1,
      1,
      settings.reminderHour,
      settings.reminderMinute,
    );
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => Container(
        height: 300,
        color: context.colors.card,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Отмена'),
                  onPressed: () => Navigator.of(modalContext).pop(),
                ),
                CupertinoButton(
                  child: const Text('Готово'),
                  onPressed: () async {
                    await settings.setReminder(
                      true,
                      hour: selected.hour,
                      minute: selected.minute,
                    );
                    await ReminderService.scheduleDaily(
                      selected.hour,
                      selected.minute,
                    );
                    if (modalContext.mounted) Navigator.of(modalContext).pop();
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: selected,
                onDateTimeChanged: (dt) => selected = dt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appearanceSection(SettingsController settings) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
      children: [
        SectionLabel('Оформление'),
        AppCard(
          child: Column(
            children: [
              KeyValueRow(
                'Тема',
                settings.themeMode.label,
                emphasis: true,
                onTap: _pickTheme,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Вкладки'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < _navTabLabels.length; i++) ...[
                if (i > 0) const Hairline(),
                _SwitchRow(
                  title: _navTabLabels[i],
                  value: settings.isTabVisible(i),
                  onChanged: (v) => settings.toggleTabVisible(i, visible: v),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Напоминания'),
        AppCard(
          child: Column(
            children: [
              KeyValueRow(
                'Ежедневное напоминание',
                settings.reminderEnabled ? 'вкл' : 'выкл',
                onTap: () async {
                  final next = !settings.reminderEnabled;
                  await settings.setReminder(next);
                  if (next) {
                    await ReminderService.scheduleDaily(
                      settings.reminderHour,
                      settings.reminderMinute,
                    );
                  } else {
                    await ReminderService.cancel();
                  }
                  if (mounted) setState(() {});
                },
              ),
              if (settings.reminderEnabled)
                KeyValueRow(
                  'Время',
                  '${settings.reminderHour.toString().padLeft(2, '0')}:'
                      '${settings.reminderMinute.toString().padLeft(2, '0')}',
                  valueColor: colors.accent,
                  onTap: () => _pickReminderTime(settings),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── защита ───────────────────────────

  Future<void> _managePin() async {
    final settings = context.read<SettingsController>();
    if (settings.hasAppPin) {
      final current = await _promptValue(
        'Текущий PIN (4-6 цифр)',
        '',
        obscure: true,
        numeric: true,
      );
      if (!mounted) return;
      if (current == null || !settings.verifyAppPin(current)) {
        await showAppAlert(context, title: 'Ошибка', message: 'PIN не совпал.');
        return;
      }
    }
    final next = await _promptValue(
      'Новый PIN (пусто — убрать)',
      '',
      obscure: true,
      numeric: true,
    );
    if (next == null || !mounted) return;
    await settings.setAppPin(next.isEmpty ? null : next);
    if (!mounted) return;
    await showAppAlert(
      context,
      title: 'Готово',
      message: next.isEmpty ? 'PIN отключён.' : 'PIN установлен.',
    );
    if (mounted) setState(() {});
  }

  Future<void> _checkDataIntegrity() async {
    setState(() => _busy = true);
    try {
      final issues = await context.read<MastersStore>().checkDataIntegrity();
      if (!mounted) return;
      await showAppAlert(
        context,
        title: issues.isEmpty ? 'Проверка завершена' : 'Нарушения целостности',
        message: issues.isEmpty ? 'Нарушений не найдено.' : issues.join('\n'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeCurrentPeriod() async {
    final now = DateTime.now();
    final store = context.read<MastersStore>();
    try {
      await store.closePeriod(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
        note: 'Закрытие месяца из настроек',
      );
      if (!mounted) return;
      await showAppAlert(
        context,
        title: 'Период закрыт',
        message:
            'Месяц закрыт для редактирования. Записи сохранены, период можно переоткрыть.',
      );
    } catch (e) {
      if (!mounted) return;
      await showAppAlert(context, title: 'Не удалось закрыть', message: '$e');
    }
  }

  Future<void> _reopenLastClosedPeriod() async {
    final store = context.read<MastersStore>();
    if (store.closedPeriods.isEmpty) {
      if (!mounted) return;
      await showAppAlert(
        context,
        title: 'Закрытых периодов нет',
        message: 'Сначала закройте период.',
      );
      return;
    }
    try {
      await store.reopenPeriod(store.closedPeriods.first.id);
      if (!mounted) return;
      await showAppAlert(
        context,
        title: 'Период открыт',
        message: 'Последний закрытый период снова доступен для правок.',
      );
    } catch (e) {
      if (!mounted) return;
      await showAppAlert(context, title: 'Не удалось открыть', message: '$e');
    }
  }

  Widget _securitySection(SettingsController settings) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
      children: [
        SectionLabel('Блокировка'),
        AppCard(
          child: Column(
            children: [
              KeyValueRow(
                'PIN-код',
                settings.hasAppPin ? 'установлен' : 'не задан',
                valueColor: settings.hasAppPin
                    ? colors.green
                    : colors.secondaryLabel,
                onTap: _managePin,
              ),
              if (settings.hasAppPin)
                KeyValueRow(
                  'Сменить или убрать',
                  'изменить',
                  valueColor: colors.accent,
                  onTap: _managePin,
                ),
              FutureBuilder<bool>(
                future: AppBiometricService.isAvailable(),
                builder: (context, snapshot) {
                  if (!(snapshot.data ?? false)) {
                    return const SizedBox.shrink();
                  }
                  return _SwitchRow(
                    title: 'Разблокировка биометрией',
                    value: settings.biometricEnabled,
                    onChanged: settings.setBiometricEnabled,
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Закрытые периоды'),
        AppCard(
          child: Column(
            children: [
              KeyValueRow(
                'Закрыто периодов',
                '${context.watch<MastersStore>().closedPeriods.length}',
              ),
              const SizedBox(height: 6),
              SecondaryButton(
                label: 'Закрыть текущий месяц',
                icon: CupertinoIcons.lock_shield,
                onPressed: _closeCurrentPeriod,
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Переоткрыть последний период',
                icon: CupertinoIcons.lock_open,
                onPressed: _reopenLastClosedPeriod,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Целостность'),
        AppCard(
          child: Column(
            children: [
              SecondaryButton(
                label: _busy ? 'Проверка...' : 'Проверить данные',
                icon: CupertinoIcons.shield_fill,
                onPressed: _busy ? null : _checkDataIntegrity,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── данные ───────────────────────────

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final data = context.read<MastersStore>().backupData();
      final ok = await BackupService.saveJson(data);
      if (mounted && ok) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: 'Резервная копия сохранена.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final choice = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Восстановить копию?'),
        content: const Text(
          'Полная замена удалит текущие данные. Объединение сохранит локальные изменения и добавит недостающие записи из файла.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop('merge'),
            child: const Text('Объединить'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop('replace'),
            child: const Text('Заменить всё'),
          ),
        ],
      ),
    );
    if (choice == null || choice == 'cancel' || !mounted) return;

    final store = context.read<MastersStore>();
    setState(() => _busy = true);
    try {
      final data = await BackupService.pickJson();
      if (data == null) return;
      if (choice == 'replace') {
        await store.restoreFromBackup(data);
        if (mounted) {
          await showAppAlert(
            context,
            title: 'Готово',
            message: 'Копия полностью восстановлена.',
          );
        }
        return;
      }

      final preview = await store.mergeFromBackup(
        data,
        dryRun: true,
        applyConflictIds: const <String>{},
      );
      if (!mounted) return;
      if (preview.conflicts.isEmpty) {
        final applied = await store.mergeFromBackup(data);
        if (mounted) {
          await showAppAlert(
            context,
            title: 'Объединение завершено',
            message:
                'Добавлено/обновлено: ${applied.affected}, сохранено локально: ${applied.keptLocal}',
          );
        }
        return;
      }

      final selected = await _showImportConflictsModal(preview.conflicts);
      if (selected == null) {
        if (mounted) {
          await showAppAlert(
            context,
            title: 'Отменено',
            message: 'Изменения не применены.',
          );
        }
        return;
      }
      final applied = await store.mergeFromBackup(
        data,
        applyConflictIds: selected,
      );
      if (mounted) {
        await showAppAlert(
          context,
          title: 'Объединение завершено',
          message:
              'Добавлено/обновлено: ${applied.affected}, сохранено локально: ${applied.keptLocal}',
        );
      }
    } catch (e) {
      if (mounted) {
        await showAppAlert(context, title: 'Ошибка', message: '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Set<String>?> _showImportConflictsModal(List<String> conflicts) {
    final selected = <String>{...conflicts};
    return showCupertinoDialog<Set<String>?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) => CupertinoAlertDialog(
          title: const Text('Обнаружены конфликты'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Совпали по дате: ${conflicts.length}.'),
                const SizedBox(height: 8),
                for (final conflict in conflicts)
                  Row(
                    children: [
                      CupertinoCheckbox(
                        value: selected.contains(conflict),
                        onChanged: (value) => setModalState(() {
                          if (value == true) {
                            selected.add(conflict);
                          } else {
                            selected.remove(conflict);
                          }
                        }),
                      ),
                      Expanded(child: Text(conflict)),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () =>
                  Navigator.of(dialogContext).pop(Set<String>.from(selected)),
              child: const Text('Применить выбранные'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(<String>{}),
              child: const Text('Оставить локальные'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final store = context.read<MastersStore>();
    setState(() => _busy = true);
    try {
      final rows = <List<dynamic>>[
        [
          'Заказ',
          'Клиент',
          'Статус',
          'Цена',
          'Расход',
          'Время (мин)',
          'Дедлайн',
        ],
        for (final job in store.jobs)
          [
            job.title,
            store.clientById(job.clientId)?.name ?? '',
            job.status.label,
            (job.priceCents / 100).toStringAsFixed(2),
            (job.costCents / 100).toStringAsFixed(2),
            store.totalMinutesForJob(job.id),
            job.dueDate == null
                ? ''
                : job.dueDate!.toIso8601String().substring(0, 10),
          ],
      ];
      final ok = await BackupService.saveExcel(
        rows,
        fileName: 'masters.xlsx',
        sheetName: 'Orders',
      );
      if (mounted && ok) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: 'Таблица сохранена.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearData() async {
    final ok = await showAppConfirm(
      context,
      title: 'Очистить данные?',
      message: 'Все заказы, клиенты и объекты будут удалены.',
      destructive: true,
      confirmLabel: 'Очистить',
    );
    if (!ok || !mounted) return;
    await context.read<MastersStore>().clearAll();
    if (!mounted) return;
    await showAppAlert(context, title: 'Готово', message: 'Данные очищены.');
  }

  Future<void> _showAuditLog() async {
    setState(() => _auditBusy = true);
    List<Map<String, Object?>> entries;
    try {
      entries = await context.read<MastersStore>().auditEntries(limit: 100);
    } finally {
      if (mounted) setState(() => _auditBusy = false);
    }
    if (!mounted) return;
    final filterController = TextEditingController();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final filter = filterController.text.trim().toLowerCase();
          final rows = filter.isEmpty
              ? entries
              : entries
                    .where(
                      (e) =>
                          '${e['action']} ${e['entity']} ${e['entity_id'] ?? ''}'
                              .toLowerCase()
                              .contains(filter),
                    )
                    .toList();
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            color: context.colors.card,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const Text(
                    'Журнал аудита',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: filterController,
                    placeholder: 'Фильтр по действию или сущности',
                    onChanged: (_) => setModalState(() {}),
                    padding: const EdgeInsets.all(10),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: rows.isEmpty
                        ? const EmptyState(
                            title: 'Записей нет',
                            message: 'Действия появятся, когда начнёте работать с данными.',
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final e = rows[i];
                              final at = e['at'] is int
                                  ? DateTime.fromMillisecondsSinceEpoch(
                                      e['at'] as int,
                                    )
                                  : DateTime.now();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: AppCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  onTap: () => _showAuditDetail(e),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e['action']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${e['entity']} ${e['entity_id'] ?? ''}',
                                        style: TextStyle(
                                          color: context.colors.secondaryLabel,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '${at.day}.${at.month}.${at.year} ${at.hour}:'
                                        '${at.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          color: context.colors.tertiaryLabel,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  SecondaryButton(
                    label: 'Закрыть',
                    icon: CupertinoIcons.xmark,
                    onPressed: () => Navigator.of(modalContext).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    filterController.dispose();
  }

  Future<void> _showAuditDetail(Map<String, Object?> e) async {
    final at = e['at'] is int
        ? DateTime.fromMillisecondsSinceEpoch(e['at'] as int)
        : DateTime.now();
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(e['action']?.toString() ?? 'Детали аудита'),
        content: SingleChildScrollView(
          child: Text(
            'entity: ${e['entity']}\n'
            'entity_id: ${e['entity_id'] ?? '—'}\n'
            'actor: ${e['actor'] ?? '—'}\n'
            'device: ${e['device_id'] ?? '—'}\n'
            'time: ${at.toLocal()}\n\n'
            'before:\n${e['before_json'] ?? '—'}\n\n'
            'after:\n${e['after_json'] ?? '—'}',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _dataSection() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
      children: [
        SectionLabel('Резервная копия'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListRow(
                dense: true,
                icon: CupertinoIcons.cloud_download,
                title: 'Экспорт JSON',
                subtitle: 'Снимок всех данных',
                showChevron: true,
                onTap: _busy ? null : _exportBackup,
              ),
              const Hairline(indent: 12),
              ListRow(
                dense: true,
                icon: CupertinoIcons.cloud_upload,
                title: 'Восстановить JSON',
                subtitle: 'Замена или объединение',
                showChevron: true,
                onTap: _busy ? null : _importBackup,
              ),
              const Hairline(indent: 12),
              ListRow(
                dense: true,
                icon: CupertinoIcons.table,
                title: 'Экспорт в Excel',
                subtitle: 'Заказы для внешних отчётов',
                showChevron: true,
                onTap: _busy ? null : _exportCsv,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Облако'),
        const SyncCard(),
        const SizedBox(height: 16),
        SectionLabel('Журнал'),
        AppCard(
          padding: EdgeInsets.zero,
          child: ListRow(
            dense: true,
            icon: CupertinoIcons.doc_text_search,
            title: _auditBusy ? 'Загрузка...' : 'Журнал действий',
            subtitle: 'Кто и когда менял данные',
            showChevron: true,
            onTap: _auditBusy ? null : _showAuditLog,
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Опасные действия'),
        AppCard(
          padding: EdgeInsets.zero,
          child: ListRow(
            dense: true,
            icon: CupertinoIcons.trash,
            iconColor: context.colors.red,
            title: 'Очистить все данные',
            titleColor: context.colors.red,
            showChevron: true,
            onTap: _clearData,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── обновления ───────────────────────────

  Future<void> _checkForUpdates() async {
    setState(() {
      _updateBusy = true;
      _updateStatus = 'Проверка обновлений...';
    });
    try {
      final settings = context.read<SettingsController>();
      final update = await UpdateService(
        mirrorUrl: settings.updateMirrorUrl,
        isMirrorEnabled: settings.updateMirrorEnabled,
        channel: settings.updateChannel,
      ).checkForUpdate();
      if (!mounted) return;
      setState(() {
        _updateInfo = update;
        _updateStatus = update.updateAvailable
            ? 'Доступно: ${update.latestVersionName} (код ${update.latestVersionCode})'
            : 'У вас актуальная версия.';
      });
      if (update.updateAvailable) {
        final proceed = await showAppConfirm(
          context,
          title: 'Доступно обновление',
          message: '${update.changelog}\n\nУстановить сейчас?',
          confirmLabel: 'Скачать и установить',
        );
        if (proceed && mounted) await _downloadAndInstallUpdate(update);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _updateStatus = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  Future<void> _checkMirror() async {
    final settings = context.read<SettingsController>();
    final url = _mirrorUrlController.text.trim();
    await settings.setUpdateMirrorUrl(url);
    setState(() {
      _mirrorBusy = true;
      _mirrorStatus = 'Проверка зеркала...';
    });
    try {
      final update = await UpdateService(
        mirrorUrl: url,
        isMirrorEnabled: true,
        channel: settings.updateChannel,
      ).checkForUpdate(mirrorOnly: true);
      if (!mounted) return;
      setState(() {
        _mirrorStatus = update.updateAvailable
            ? 'Доступно: ${update.latestVersionName} (код ${update.latestVersionCode})'
            : 'На зеркале новее нет.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mirrorStatus = 'Ошибка зеркала: $e');
    } finally {
      if (mounted) setState(() => _mirrorBusy = false);
    }
  }

  Future<void> _downloadAndInstallUpdate(UpdateInfo update) async {
    setState(() {
      _updateBusy = true;
      _updateStatus = 'Скачивание APK...';
    });
    try {
      final file = await UpdateService().downloadVerifiedApk(
        update,
        onProgress: (received, total) {
          if (!mounted) return;
          final mb = (received / (1024 * 1024)).toStringAsFixed(1);
          setState(() => _updateStatus = 'Скачивание APK: $mb МБ');
        },
      );
      if (!mounted) return;
      setState(() => _updateStatus = 'Запуск установщика...');
      await UpdateService().installApk(file);
      if (mounted) {
        setState(() => _updateStatus = 'Подтвердите установку в Android.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _updateStatus = 'Ошибка установки: $e');
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  Widget _updateSection(SettingsController settings) {
    final colors = context.colors;
    final info = _updateInfo;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
      children: [
        SectionLabel('Канал обновлений'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _CheckRow(
                title: 'Стабильный',
                checked: settings.updateChannel == 'stable',
                onTap: () => settings.setUpdateChannel('stable'),
              ),
              const Hairline(),
              _CheckRow(
                title: 'Бета',
                checked: settings.updateChannel == 'beta',
                onTap: () => settings.setUpdateChannel('beta'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Проверка'),
        AppCard(
          child: Column(
            children: [
              KeyValueRow(
                'Текущая сборка',
                info == null ? '—' : '${info.currentVersionCode}',
              ),
              if (info != null && info.updateAvailable)
                KeyValueRow(
                  'Доступно',
                  '${info.latestVersionName} (${info.latestVersionCode})',
                  valueColor: colors.green,
                ),
              if (_updateStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _updateStatus,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.secondaryLabel,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: _updateBusy ? 'Проверка...' : 'Проверить обновления',
                icon: CupertinoIcons.cloud_download,
                onPressed: _updateBusy ? null : _checkForUpdates,
              ),
              if (info != null && info.updateAvailable) ...[
                const SizedBox(height: 8),
                PrimaryButton(
                  label: 'Установить ${info.latestVersionName}',
                  icon: CupertinoIcons.arrow_down_circle,
                  onPressed: _updateBusy
                      ? null
                      : () => _downloadAndInstallUpdate(info),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionLabel('Зеркало в локальной сети'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyValueRow(
                'Зеркало включено',
                settings.updateMirrorEnabled ? 'вкл' : 'выкл',
                onTap: () async {
                  await settings.setUpdateMirrorEnabled(
                    !settings.updateMirrorEnabled,
                  );
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _mirrorUrlController,
                placeholder: 'http://192.168.1.112:8080',
                padding: const EdgeInsets.all(10),
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: _mirrorBusy ? 'Проверка...' : 'Проверить зеркало',
                icon: CupertinoIcons.wifi,
                onPressed: _mirrorBusy ? null : _checkMirror,
              ),
              if (_mirrorStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _mirrorStatus,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.secondaryLabel,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── сборка ───────────────────────────

  static const _navTabLabels = [
    'Сегодня',
    'Клиенты',
    'События',
    'Деньги',
    'Склад',
    'Ещё',
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final store = context.watch<MastersStore>();

    final body = switch (_section) {
      0 => _workSection(settings),
      1 => _moneySection(settings, store),
      2 => _appearanceSection(settings),
      3 => _securitySection(settings),
      4 => _dataSection(),
      _ => _updateSection(settings),
    };

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Настройки')),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                children: [
                  for (var i = 0; i < _sections.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _SectionChip(
                      label: _sections[i].$1,
                      icon: _sections[i].$2,
                      selected: _section == i,
                      onTap: () => setState(() => _section = i),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Чип-переключатель группы настроек.
class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? colors.tint(colors.accent, 0.16)
              : colors.cardElevated,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? colors.accent : colors.separator,
            width: selected ? 1.2 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? colors.accent : colors.secondaryLabel,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.accent : colors.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка «название + переключатель» внутри карточки.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Строка «название + галочка выбора одного из вариантов».
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.title,
    required this.checked,
    required this.onTap,
  });

  final String title;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Expanded(child: Text(title)),
            if (checked)
              Icon(CupertinoIcons.checkmark, size: 17, color: colors.accent),
          ],
        ),
      ),
    );
  }
}

/// Строка налогового профиля: выбор активного, правка, удаление.
class _TaxProfileRow extends StatelessWidget {
  const _TaxProfileRow({
    required this.profile,
    required this.flag,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  final TaxProfile profile;
  final String flag;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isActive
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    size: 19,
                    color: isActive ? colors.accent : colors.tertiaryLabel,
                  ),
                  const SizedBox(width: 9),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$flag ${profile.country} · ${profile.name}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isActive ? colors.accent : colors.label,
                        ),
                      ),
                      Text(
                        '${profile.ratePercent}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            minimumSize: Size.zero,
            onPressed: isActive ? null : onDelete,
            child: Icon(
              CupertinoIcons.trash,
              size: 17,
              color: isActive ? colors.tertiaryLabel : colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
