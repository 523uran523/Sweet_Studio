import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/utils/app_utils.dart';
import '../../state/masters_store.dart';
import '../../state/settings_controller.dart';
import '../jobs/job_detail_screen.dart';
import 'widgets/unified_calendar_view.dart';
import 'widgets/unified_kanban_view.dart';

/// Действия единого экрана, которые передаются вниз в виды.
class UnifiedBookingActions {
  const UnifiedBookingActions({
    required this.convertAppointmentToJob,
    required this.convertJobToAppointment,
  });

  /// «Сделать заказом» — запись с её слотом превращается в Job.
  final void Function(String appointmentId) convertAppointmentToJob;

  /// «Создать запись» — заказу назначается конкретное время.
  final void Function(String jobId) convertJobToAppointment;
}

/// Единый экран планирования: записи и заказы в одном канбане/календаре.
/// Данные остаются в родных таблицах — экран работает через адаптер
/// [UnifiedEvent] и методы агрегации [MastersStore].
class UnifiedBookingScreen extends StatefulWidget {
  const UnifiedBookingScreen({super.key});

  @override
  State<UnifiedBookingScreen> createState() => _UnifiedBookingScreenState();
}

class _UnifiedBookingScreenState extends State<UnifiedBookingScreen> {
  String _view = 'kanban';
  bool _busy = false;

  UnifiedBookingActions get _actions => UnifiedBookingActions(
    convertAppointmentToJob: _convertAppointmentToJob,
    convertJobToAppointment: _convertJobToAppointment,
  );

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final title = switch (settings.workMode) {
      'appointments' => 'События',
      'hybrid' => 'События',
      _ => 'События',
    };

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _view == 'kanban' ? _showCalendar : _showKanban,
              child: Icon(
                _view == 'kanban'
                    ? CupertinoIcons.calendar
                    : CupertinoIcons.square_grid_2x2_fill,
                semanticLabel: 'Переключить вид',
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _quickAdd,
              child: const Icon(CupertinoIcons.plus, semanticLabel: 'Создать'),
            ),
          ],
        ),
      ),
      child: _busy
          ? const Center(child: CupertinoActivityIndicator())
          : SafeArea(
              child: _view == 'kanban'
                  ? UnifiedKanbanView(actions: _actions)
                  : UnifiedCalendarView(actions: _actions),
            ),
    );
  }

  void _showKanban() => setState(() => _view = 'kanban');
  void _showCalendar() => setState(() => _view = 'calendar');

  /// «+»: в чистом режиме — сразу своё действие, в гибриде — меню выбора.
  Future<void> _quickAdd() async {
    final settings = context.read<SettingsController>();
    switch (settings.workMode) {
      case 'appointments':
        await _newAppointment();
        break;
      case 'hybrid':
        final choice = await showCupertinoModalPopup<String?>(
          context: context,
          builder: (dialogContext) => CupertinoActionSheet(
            title: const Text('Создать'),
            actions: [
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(dialogContext).pop('appt'),
                child: const Text('Запись'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(dialogContext).pop('job'),
                child: const Text('Заказ'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
          ),
        );
        if (!mounted) return;
        if (choice == 'appt') {
          await _newAppointment();
        } else if (choice == 'job') {
          await _newJob();
        }
        break;
      default:
        await _newJob();
    }
  }

  Future<String?> _promptText(
    String title,
    String placeholder, {
    String initial = '',
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

  Future<String?> _pickClient() async {
    final store = context.read<MastersStore>();
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Клиент'),
        actions: [
          for (final c in [
            ...store.clients,
          ]..sort((a, b) => a.name.compareTo(b.name)))
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(dialogContext).pop(c.id),
              child: Text(c.name),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('__new__'),
            child: const Text('Новый клиент'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  Future<String?> _newClient() async {
    final store = context.read<MastersStore>();
    final name = await _promptText('Имя клиента', 'Иван');
    if (!mounted) return null;
    if (name == null || name.isEmpty) return null;
    final phone = await _promptText('Телефон', 'Телефон');
    if (!mounted) return null;
    final client = await store.createClient(
      name: name,
      phone: phone?.trim() ?? '',
    );
    if (!mounted) return null;
    return client.id;
  }

  Future<String?> _pickResource() async {
    final store = context.read<MastersStore>();
    final resources = store.bookingResources.where((r) => !r.archived).toList();
    if (resources.isEmpty) return null;
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Ресурс'),
        actions: [
          for (final r in resources)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(dialogContext).pop(r.id),
              child: Text(r.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    DateTime selected = initial;
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
                  onPressed: () => Navigator.of(modalContext).pop(),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: selected,
                onDateTimeChanged: (dt) => selected = dt,
              ),
            ),
          ],
        ),
      ),
    );
    return selected;
  }

  Future<DateTime?> _pickDate(DateTime initial) async {
    DateTime selected = initial;
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
                  onPressed: () => Navigator.of(modalContext).pop(),
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
    return selected;
  }

  Future<void> _newAppointment() async {
    final store = context.read<MastersStore>();
    final title = await _promptText('Название записи', 'Замена масла');
    if (!mounted || title == null || title.isEmpty) return;

    String? clientId;
    if (store.clients.isNotEmpty) {
      final picked = await _pickClient();
      if (!mounted) return;
      if (picked == null) return;
      clientId = picked == '__new__' ? await _newClient() : picked;
      if (!mounted || clientId == null) return;
    }

    final resourceId = await _pickResource();
    if (!mounted) return;
    final start = await _pickDateTime(DateTime.now());
    if (!mounted || start == null) return;
    final end = await _pickDateTime(start.add(const Duration(hours: 1)));
    if (!mounted || end == null) return;
    final note = await _promptText('Заметка', '');
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await store.createAppointment(
        title: title,
        startAt: start,
        endAt: end,
        clientId: clientId,
        resourceId: resourceId,
        note: note,
      );
    } on StateError catch (e) {
      if (mounted) {
        await showAppAlert(context, title: 'Конфликт', message: e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newJob() async {
    final store = context.read<MastersStore>();
    final title = await _promptText('Название заказа', 'Заказ');
    if (!mounted || title == null || title.isEmpty) return;

    final picked = await _pickClient();
    if (!mounted || picked == null) return;
    final clientId = picked == '__new__' ? await _newClient() : picked;
    if (!mounted || clientId == null) return;

    final due = await _pickDate(DateTime.now());
    if (!mounted || due == null) return;

    setState(() => _busy = true);
    try {
      final job = await store.createJob(
        title: title,
        clientId: clientId,
        dueDate: DateTime(due.year, due.month, due.day, 18, 0),
        assigneeId: store.selfEmployee?.id,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => JobDetailScreen(jobId: job.id)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convertAppointmentToJob(String appointmentId) async {
    final store = context.read<MastersStore>();
    final a = store.appointmentById(appointmentId);
    if (a == null) return;
    final ok = await showAppConfirm(
      context,
      title: 'Сделать заказом?',
      message:
          'Запись «${a.title}» станет заказом с дедлайном ${dayKey(a.startAt)}. Запись будет удалена.',
      confirmLabel: 'Сделать заказом',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await store.convertAppointmentToJob(appointmentId);
      if (mounted) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: 'Заказ создан, запись удалена.',
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        await showAppAlert(context, title: 'Ошибка', message: e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convertJobToAppointment(String jobId) async {
    final store = context.read<MastersStore>();
    final j = store.jobById(jobId);
    if (j == null) return;
    final ok = await showAppConfirm(
      context,
      title: 'Назначить время?',
      message: j.dueDate == null
          ? 'Для заказа «${j.title}» будет создана запись через час. Заказ останется.'
          : 'Для заказа «${j.title}» будет создана запись на время дедлайна. Заказ останется.',
      confirmLabel: 'Создать запись',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await store.convertJobToAppointment(jobId);
      if (mounted) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: 'Запись создана.',
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        await showAppAlert(context, title: 'Конфликт', message: e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
