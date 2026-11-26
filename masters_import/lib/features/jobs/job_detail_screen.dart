import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/document_service.dart';

import 'package:open_filex/open_filex.dart';

import '../../core/deep_link_service.dart';
import '../../core/reminder_text.dart';
import '../../core/utils/app_utils.dart';
import '../../core/units.dart';
import '../../data/models/job.dart';
import '../../data/models/job_attachment.dart';
import '../../data/models/quote.dart';
import 'job_constants.dart';
import 'job_form_screen.dart';
import 'job_form_widgets.dart';
import 'cost_calculator_screen.dart';
import '../catalog/catalog_screen.dart';
import '../clients/client_credits.dart';
import '../leads/quotes_screen.dart';
import '../../state/masters_store.dart';
import '../../state/settings_controller.dart';
import '../../core/money_format.dart';

class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({super.key, required this.jobId});
  final String jobId;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  DateTime? _timerStart;
  Timer? _timer;
  int _elapsedSeconds = 0;
  List<JobAttachment> _attachments = const [];
  bool _busyAttachment = false;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    if (!mounted) return;
    final store = context.read<MastersStore>();
    final list = await store.attachmentsForJob(widget.jobId);
    if (mounted) setState(() => _attachments = list);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// История КП заказа (§12.4): если снимков ещё нет, первый создаётся из
  /// текущих строк — дальнейшие правки заказа его не меняют.
  Future<void> _openQuote(MastersStore store, Job job) async {
    final navigator = Navigator.of(context);
    final existing = store.quotesForJob(job.id);
    Quote target;
    if (existing.isEmpty) {
      target = await store.saveQuoteSnapshot(job.id);
    } else {
      target = existing.first;
    }
    final latest = store.quoteById(target.id) ?? target;
    navigator.push(
      CupertinoPageRoute(builder: (_) => QuotesScreen(jobId: job.id)),
    );
    // Единственный снимок показываем сразу: мастер ждёт документ, а не список
    // из одной строки.
    if (existing.isEmpty && latest.pdfPath == null && mounted) {
      await _saveQuotePdf(latest);
    }
  }

  Future<void> _saveQuotePdf(Quote quote) async {
    final bytes = await DocumentService.buildQuotePdf(quote);
    if (!mounted) return;
    final name =
        '${quote.number}-rev${quote.revision}-${quote.createdAt.millisecondsSinceEpoch}.pdf';
    final path = await DocumentService.savePdfPath(bytes, name);
    if (path != null) {
      await context.read<MastersStore>().setQuotePdfPath(quote.id, path);
    }
  }

  Future<void> _createDocument(MastersStore store, Job job) async {
    final type = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 220,
        color: context.colors.card,
        child: Column(
          children: [
            CupertinoButton(
              child: const Text('Квитанция'),
              onPressed: () => Navigator.of(ctx).pop('Квитанция'),
            ),
            CupertinoButton(
              child: const Text('Акт выполненных работ'),
              onPressed: () => Navigator.of(ctx).pop('Акт выполненных работ'),
            ),
            CupertinoButton(
              child: const Text('Счёт'),
              onPressed: () => Navigator.of(ctx).pop('Счёт'),
            ),
          ],
        ),
      ),
    );
    if (type == null) return;
    final bytes = await DocumentService.buildJobPdf(
      store: store,
      job: job,
      type: type,
    );
    final name =
        'document-${job.id.substring(0, 6)}-${DateTime.now().millisecondsSinceEpoch}.pdf';
    final ok = await DocumentService.savePdf(bytes, name);
    if (mounted && ok) {
      await showAppAlert(
        context,
        title: 'Готово',
        message: 'Документ сохранён.',
      );
    }
  }

  void _startTimer() {
    _timerStart = DateTime.now();
    _elapsedSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timerStart != null) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(_timerStart!).inSeconds;
        });
      }
    });
    setState(() {});
  }

  Future<void> _stopTimer(MastersStore store) async {
    _timer?.cancel();
    final start = _timerStart;
    if (start != null) {
      final minutes = DateTime.now().difference(start).inMinutes;
      if (minutes > 0 || _elapsedSeconds >= 30) {
        await store.addSession(
          jobId: widget.jobId,
          startedAt: start,
          endedAt: DateTime.now(),
          minutes: minutes < 1 && _elapsedSeconds >= 30 ? 1 : minutes,
        );
      }
    }
    _timerStart = null;
    _elapsedSeconds = 0;
    setState(() {});
  }

  Future<void> _addAttachment() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty || files.single.path == null) return;
    final store = context.read<MastersStore>();
    setState(() => _busyAttachment = true);
    try {
      await store.addJobAttachment(
        jobId: widget.jobId,
        sourcePath: files.single.path!,
      );
      await _loadAttachments();
    } finally {
      if (mounted) setState(() => _busyAttachment = false);
    }
  }

  Future<void> _removeAttachment(JobAttachment a) async {
    final ok = await showAppConfirm(
      context,
      title: 'Удалить вложение?',
      message: a.fileName,
      destructive: true,
      confirmLabel: 'Удалить',
    );
    if (!ok) return;
    await context.read<MastersStore>().deleteJobAttachment(a.id);
    await _loadAttachments();
  }

  Future<void> _addStage(MastersStore store) async {
    final title = await _promptText('Новый этап', 'Например: Замер');
    if (title == null || title.trim().isEmpty) return;
    await store.addStage(widget.jobId, title.trim());
  }

  Future<void> _acceptPayment(MastersStore store, Job job) async {
    final obligation = store.openJobPaymentObligation(job.id);
    // Сумма берётся из обязательства, когда оно есть: там уже учтены
    // частичные оплаты, а долг считается по остатку обязательства.
    final remaining = obligation != null
        ? obligation.remainingCents
        : job.priceCents - store.paidForJob(job.id);
    final amountStr = await _promptText(
      'Сумма оплаты',
      remaining > 0 ? (remaining / 100).toStringAsFixed(0) : '0',
    );
    final amount =
        ((double.tryParse((amountStr ?? '0').replaceAll(',', '.')) ?? 0) * 100)
            .round();
    if (amount <= 0) return;
    if (amount > remaining) {
      if (mounted) {
        await showAppAlert(
          context,
          title: 'Ошибка',
          message: 'Сумма не может превышать остаток.',
        );
      }
      return;
    }
    final accountId = await _pickAccount(store);
    if (accountId == null) return;
    final paymentMethod = await showPaymentMethodPicker(context);
    if (!mounted) return;
    try {
      if (obligation != null) {
        await store.payObligation(
          obligation.id,
          amountCents: amount,
          accountId: accountId,
          paymentMethod: paymentMethod,
        );
      } else {
        await store.addTransaction(
          accountId: accountId,
          kind: 'payment',
          direction: 'in',
          amountCents: amount,
          category: 'Оплата заказа',
          note: job.title,
          clientId: job.clientId,
          jobId: job.id,
          paymentMethod: paymentMethod,
        );
      }
    } catch (e) {
      if (mounted) {
        await showAppAlert(context, title: 'Ошибка', message: e.toString());
      }
    }
  }

  /// Готовит текст о доплате и отдаёт его системному share (§Э2.1).
  Future<void> _remindPayment(
    String clientName,
    Job job,
    int remainingCents,
    DateTime dueAt,
  ) async {
    final result = await shareReminderText(
      paymentReminderText(
        clientName: clientName,
        jobTitle: job.title,
        remainingCents: remainingCents,
        dueAt: dueAt,
      ),
    );
    if (!mounted) return;
    if (result == ReminderShareResult.copied) {
      await showAppAlert(
        context,
        title: 'Текст скопирован',
        message: 'Откройте WhatsApp/Telegram и вставьте.',
      );
    } else if (result == ReminderShareResult.failed) {
      await showAppAlert(
        context,
        title: 'Не удалось',
        message: 'Попробуйте ещё раз.',
      );
    }
  }

  Future<void> _showJobStatusPicker() async {
    final store = context.read<MastersStore>();
    final job = store.jobById(widget.jobId);
    if (job == null) return;
    final selected = await showCupertinoModalPopup<JobStatus?>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Статус заказа'),
        actions: [
          for (final s in jobStatuses)
            CupertinoActionSheetAction(
              isDefaultAction: job.status == s,
              onPressed: () => Navigator.of(ctx).pop(s),
              child: Text(s.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (selected == null || !mounted || selected == job.status) return;
    if (selected == JobStatus.closed) {
      await _closeJob(store, job);
    } else {
      await store.setJobStatus(job.id, selected);
    }
  }

  /// Оплата заказа клиентскими деньгами (§5.5): список активных кредитов,
  /// затем штатный шит списания, который гасит обязательство заказа.
  /// Возвращает true, если что-то списали.
  Future<bool> _payFromCredit(
    MastersStore store,
    Job job,
    int remaining,
  ) async {
    if (!context.read<SettingsController>().creditsEnabled) return false;
    final credits = store
        .clientCredits(job.clientId)
        .where((c) => c.isActive && c.remainingCents > 0)
        .toList();
    if (credits.isEmpty || !mounted) return false;

    final chosenId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Взять из денег клиента'),
        message: Text('Остаток к оплате: ${money(remaining)}'),
        actions: [
          for (final c in credits)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(c.id),
              child: Text(
                '${c.title.isEmpty ? c.kindLabel : c.title} · '
                '${money(c.remainingCents)}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (chosenId == null) return false;
    final before = store.clientCreditById(chosenId);
    if (before == null || !mounted) return false;

    await showUseCreditSheet(
      context,
      before,
      jobId: job.id,
      maxCents: remaining,
    );
    final after = store.clientCreditById(chosenId);
    return after != null && after.remainingCents < before.remainingCents;
  }

  Future<void> _closeJob(MastersStore store, Job job) async {
    try {
      var current = store.jobById(job.id) ?? job;
      var obligation = store.openJobPaymentObligation(current.id);
      var remaining = obligation != null
          ? obligation.remainingCents
          : (current.priceCents - store.paidForJob(current.id)) < 0
              ? 0
              : current.priceCents - store.paidForJob(current.id);

      if (current.priceCents <= 0 || remaining <= 0) {
        if (current.status != JobStatus.done) {
          await store.setJobStatus(current.id, JobStatus.done);
          current =
              store.jobById(current.id) ??
              current.copyWith(status: JobStatus.done);
        }
        await store.setJobStatus(current.id, JobStatus.closed);
        return;
      }

      // §5.5: у клиента есть активные деньги — предлагаем списать их раньше,
      // чем просить живую оплату.
      final credited = await _payFromCredit(store, current, remaining);
      if (credited && mounted) {
        current = store.jobById(current.id) ?? current;
        final left = (store.openJobPaymentObligation(current.id)
                ?.remainingCents ??
            current.priceCents - store.paidForJob(current.id))
            .clamp(0, 1 << 40);
        if (left <= 0) {
          if (current.status != JobStatus.done) {
            await store.setJobStatus(current.id, JobStatus.done);
            current = store.jobById(current.id) ?? current;
          }
          await store.setJobStatus(current.id, JobStatus.closed);
          return;
        }
        remaining = left;
        obligation = store.openJobPaymentObligation(current.id);
      }

      final choice = await showCupertinoDialog<String?>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Закрыть заказ?'),
          content: Text(
            'Остаток к оплате: ${money(remaining)}',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop('accept'),
              child: const Text('Принять остаток и закрыть'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop('debt'),
              child: const Text('Закрыть с долгом'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );

      if (choice == null || !mounted) return;

      if (choice == 'accept') {
        final accountId = await _pickAccount(store);
        if (accountId == null || !mounted) return;
        final amountStr = await _promptText(
          'Сумма оплаты',
          (remaining / 100).toStringAsFixed(0),
        );
        if (amountStr == null || !mounted) return;
        final amount =
            ((double.tryParse(amountStr.replaceAll(',', '.')) ?? 0) * 100)
                .round();
        if (amount <= 0 || amount > remaining) {
          await showAppAlert(
            context,
            title: 'Неверная сумма',
            message:
                'Сумма должна быть от 1 до ${money(remaining)}.',
          );
          return;
        }
        final paymentMethod = await showPaymentMethodPicker(context);
        if (!mounted) return;
        try {
          if (obligation != null) {
            await store.payObligation(
              obligation.id,
              amountCents: amount,
              accountId: accountId,
              paymentMethod: paymentMethod,
            );
          } else {
            await store.addTransaction(
              accountId: accountId,
              kind: 'payment',
              direction: 'in',
              amountCents: amount,
              category: 'Оплата заказа',
              note: current.title,
              clientId: current.clientId,
              jobId: current.id,
              paymentMethod: paymentMethod,
            );
          }
        } catch (e) {
          if (mounted) {
            await showAppAlert(
              context,
              title: 'Ошибка оплаты',
              message: e.toString(),
            );
          }
          return;
        }
        if (!mounted) return;
        if (store.paidForJob(current.id) >= current.priceCents) {
          if (current.status != JobStatus.done) {
            await store.setJobStatus(current.id, JobStatus.done);
          }
          await store.setJobStatus(current.id, JobStatus.closed);
        } else {
          await showAppAlert(
            context,
            title: 'Оплата принята',
            message:
                'Остаток не погашен полностью. Заказ остаётся неоплаченным.',
          );
        }
        return;
      }

      if (choice == 'debt') {
        if (current.status != JobStatus.done) {
          await store.setJobStatus(current.id, JobStatus.done);
        }
        await store.setJobStatus(current.id, JobStatus.closed);
        if (!mounted) return;
        await showAppAlert(
          context,
          title: 'Внимание',
          message:
              'Заказ закрыт с долгом. Неоплаченный остаток: ${money(remaining)}.',
        );
      }
    } catch (e) {
      if (mounted) {
        await showAppAlert(context, title: 'Ошибка', message: e.toString());
      }
    }
  }

  Future<void> _sendMessage(MastersStore store, Job job) async {
    final client = store.clientById(job.clientId);
    if (client == null || client.phone.isEmpty) {
      await showAppAlert(
        context,
        title: 'Нет телефона',
        message: 'Добавьте телефон клиента для сообщения.',
      );
      return;
    }
    final template = await showCupertinoModalPopup<String>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: Text(client.name),
        message: const Text('Выберите шаблон и канал'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('ready'),
            child: const Text('Заказ готов'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('pickup'),
            child: const Text('Можно забрать'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('progress'),
            child: const Text('Заказ в работе'),
          ),
          if (store.paidForJob(job.id) < job.priceCents)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(dialogContext).pop('pay'),
              child: const Text('Напоминание об оплате'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('whatsapp'),
            child: const Text('Написать в WhatsApp'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('telegram'),
            child: const Text('Написать в Telegram'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (template == null || !context.mounted) return;
    final debt = job.priceCents - store.paidForJob(job.id);
    final text = switch (template) {
      'ready' =>
        'Здравствуйте, ${client.name}! Ваш заказ "${job.title}" готов к выдаче.',
      'pickup' =>
        'Здравствуйте, ${client.name}! Вы можете забрать работу "${job.title}".',
      'progress' =>
        'Здравствуйте, ${client.name}! Работа "${job.title}" в процессе.',
      'pay' =>
        'Здравствуйте, ${client.name}! Осталось оплатить ${money(debt)} по заказу "${job.title}".',
      'whatsapp' => 'Здравствуйте, ${client.name}! По заказу "${job.title}".',
      'telegram' => 'Здравствуйте, ${client.name}! По заказу "${job.title}".',
      _ => '',
    };
    if (template == 'whatsapp') {
      await DeepLinkService.openWhatsApp(phone: client.phone, text: text);
      return;
    }
    if (template == 'telegram') {
      await DeepLinkService.openTelegram(text: text);
    }
  }

  Future<String?> _pickAccount(MastersStore store) async {
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

  Future<void> _addSessionManual(MastersStore store) async {
    final minStr = await _promptText('Время (минуты)', '60');
    final minutes = int.tryParse((minStr ?? '').trim()) ?? 0;
    if (minutes <= 0) return;
    final note = await _promptText('Заметка (необязательно)', '');
    await store.addSession(
      jobId: widget.jobId,
      startedAt: DateTime.now().subtract(Duration(minutes: minutes)),
      endedAt: DateTime.now(),
      minutes: minutes,
      note: note,
    );
  }

  Future<String?> _promptText(String title, String placeholder) async {
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
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<MastersStore>();
    final settings = context.watch<SettingsController>();
    final job = store.jobById(widget.jobId);
    if (job == null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Заказ')),
        child: const Center(child: Text('Не найден')),
      );
    }
    final client = store.clientById(job.clientId);
    final obj = store.objectById(job.objectId);
    final stages = store.stagesForJob(job.id);
    final lines = store.jobLines(job.id);
    final sessions = store.sessionsForJob(job.id);
    final todaySeconds = store.workSecondsForJobToday(job.id);
    final totalMin = store.totalMinutesForJob(job.id);
    final materialTotal = store.totalMaterialCents(job.id);
    final totalCost = job.costCents + materialTotal;
    final totalNet = lines.fold(0, (s, l) => s + l.totalCents - l.discountCents);
    final totalMargin = lines.fold(0, (s, l) => s + l.marginCents);
    final linesTotalCost = lines.fold(0, (s, l) => s + l.costTotalCents);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(job.title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Дублировать заказ (§Э1.2)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                final store = context.read<MastersStore>();
                final job = store.jobById(widget.jobId);
                if (job == null) return;
                try {
                  await store.duplicateJob(job.id);
                  if (mounted) {
                    showAppAlert(context,
                        title: 'Заказ скопирован',
                        message:
                            'Создан новый заказ с теми же строками и ценами.');
                  }
                } catch (_) {
                  if (mounted) {
                    showAppAlert(context,
                        title: 'Ошибка',
                        message: 'Не удалось дублировать заказ');
                  }
                }
              },
              child: const Icon(
                CupertinoIcons.doc_on_doc,
                size: 20,
                semanticLabel: 'Дублировать заказ',
              ),
            ),
            // Закрепить
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () async {
                await context.read<MastersStore>().setJobPinned(
                  job.id,
                  !job.pinned,
                );
              },
              child: Icon(
                job.pinned ? CupertinoIcons.star_fill : CupertinoIcons.star,
                color: job.pinned ? colors.accent : null,
                semanticLabel: job.pinned ? 'Открепить' : 'Закрепить',
              ),
            ),
            // Редактировать
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => JobFormScreen(jobId: job.id),
                ),
              ),
              child: const Icon(
                CupertinoIcons.pencil,
                semanticLabel: 'Редактировать',
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
          children: [
            // client / object
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client?.name ?? 'Без клиента',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                  if (client?.phone.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        client!.phone,
                        style: TextStyle(
                          color: colors.secondaryLabel,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (obj != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      obj.title,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (obj.address.isNotEmpty)
                      Text(
                        obj.address,
                        style: TextStyle(
                          color: colors.secondaryLabel,
                          fontSize: 12,
                        ),
                      ),
                  ],
                  if (job.note != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      job.note!,
                      style: TextStyle(
                        color:
                            job.status == JobStatus.done ||
                                job.status == JobStatus.closed
                            ? colors.tertiaryLabel
                            : colors.secondaryLabel,
                        fontSize: 14,
                        decoration:
                            job.status == JobStatus.done ||
                                job.status == JobStatus.closed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Pill(
                        job.priority.label,
                        color: _priorityColor(context, job.priority),
                      ),
                      if (settings.jobTagsEnabled &&
                          job.tags != null &&
                          job.tags!.trim().isNotEmpty)
                        for (final tag
                            in job.tags!
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty))
                          Pill(tag, color: _tagColor(tag)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Статус'),
            AppCard(
              child: SecondaryButton(
                label: 'Статус: ${job.status.label}',
                icon: CupertinoIcons.list_bullet,
                onPressed: () => _showJobStatusPicker(),
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Суммы'),
            AppCard(
              child: Column(
                children: [
                  _KV('Цена', '${money(job.priceCents)}'),
                  if (lines.isEmpty) ...[
                    _KV(
                      'Расход (введённый)',
                      '${money(job.costCents)}',
                    ),
                    _KV(
                      'Материалы',
                      '${money(materialTotal)}',
                    ),
                    _KV(
                      'Итого расход',
                      '${money(totalCost)}',
                    ),
                    _KV(
                      'Маржа',
                      '${money(job.priceCents - totalCost)}',
                    ),
                  ] else ...[
                    _KV('Себестоимость', '${money(linesTotalCost)}'),
                    _KV(
                      'Маржа',
                      '${money(job.priceCents - linesTotalCost)}',
                    ),
                  ],
                  _KV('Время', formatMinutes(totalMin)),
                  if (job.dueDate != null)
                    _KV('Срок', formatFullDate(job.dueDate!)),
                  if (settings.teamEnabled && job.assigneeId != null)
                    _KV(
                      'Исполнитель',
                      store.employeeById(job.assigneeId!)?.name ?? '—',
                    ),
                ],
              ),
            ),
            if (settings.calculatorEnabled) ...[
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Калькулятор цены',
                icon: CupertinoIcons.money_dollar,
                onPressed: () async {
                  final materialCount = store.materialsForJob(job.id).length;
                  final result = await Navigator.of(context)
                      .push<Map<String, int>>(
                        CupertinoPageRoute(
                          builder: (_) => CostCalculatorScreen(
                            jobId: job.id,
                            // Старый блок «Материалы» подхватываем как стартовую
                            // строку только если калькулятор этого заказа пуст.
                            initialMaterialsCents: materialCount > 0
                                ? 0
                                : materialTotal,
                          ),
                        ),
                      );
                  if (result == null || !mounted) return;
                  await store.updateJob(
                    job.copyWith(
                      priceCents: result['priceCents'] as int,
                      costCents: result['costCents'] as int,
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            SectionLabel(
              'Этапы (${stages.where((s) => s.done).length}/${stages.length})',
            ),
            AppCard(
              child: Column(
                children: [
                  ...stages.map(
                    (s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          CupertinoCheckbox(
                            value: s.done,
                            onChanged: (_) => store.toggleStage(s.id),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.title,
                              style: TextStyle(
                                color: s.done
                                    ? colors.secondaryLabel
                                    : colors.label,
                                decoration: s.done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => store.deleteStage(s.id),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 14,
                              color: colors.tertiaryLabel,
                              semanticLabel: 'Удалить',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SecondaryButton(
                    label: 'Добавить этап',
                    icon: CupertinoIcons.plus,
                    onPressed: () => _addStage(store),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Работы и товары (${lines.length})'),
            AppCard(
              child: Column(
                children: [
                  ...lines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${formatQty(line.quantity)} ${line.unit} × ${money(line.priceCents)}',
                              style: TextStyle(
                                color: colors.secondaryLabel,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${money(line.totalCents - line.discountCents)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => store.deleteMaterial(line.id),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 14,
                              color: colors.tertiaryLabel,
                              semanticLabel: 'Удалить',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (lines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Пусто. Добавьте позицию из каталога — цена и себестоимость подставятся сами.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.secondaryLabel,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (lines.isNotEmpty) ...[
                    const Hairline(),
                    const SizedBox(height: 4),
                    KeyValueRow(
                      'Итого',
                      money(lines.fold(0, (s, l) => s + l.totalCents - l.discountCents)),
                      dense: true,
                    ),
                    KeyValueRow(
                      'Себестоимость',
                      money(lines.fold(0, (s, l) => s + l.costTotalCents)),
                      dense: true,
                    ),
                    KeyValueRow(
                      'Маржа',
                      '${money(totalMargin)}${totalNet > 0 ? ' (${(totalMargin / totalNet * 100).round()}%)' : ''}',
                      valueColor: totalMargin > 0 ? colors.green : colors.orange,
                      emphasis: true,
                      dense: true,
                    ),
                  ],
                  // Pill низкой маржи (§Э1.3)
                  if (store.isLowMarginJob(widget.jobId) && lines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Pill(
                          'Низкая маржа',
                          color: colors.orange,
                          icon: CupertinoIcons.exclamationmark_triangle,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChipButton(
                            label: 'Пересмотреть цены',
                            icon: CupertinoIcons.chart_bar,
                            color: colors.orange,
                            onPressed: () async {
                              // Собираем названия позиций для фильтра каталога
                              final names = lines
                                  .map((l) => l.name)
                                  .toSet()
                                  .join(' ');
                              Navigator.of(context).push(
                                CupertinoPageRoute(
                                  builder: (_) => CatalogScreen(
                                    initialQuery: names,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  SecondaryButton(
                    label: 'Добавить из каталога',
                    icon: CupertinoIcons.cube_box,
                    dense: true,
                    onPressed: () async {
                      final picked = await showCatalogPicker(context);
                      if (picked == null || !mounted) return;
                      final item = picked.item;
                      await store.createJobLine(
                        widget.jobId,
                        itemId: item.id,
                        kind: item.kind == 'service' ? 'work' : 'good',
                        name: item.name,
                        qty: picked.quantity,
                        unit: item.unit,
                        priceCents: item.sellPriceCents,
                        costAtOrderCents:
                            item.kind == 'service' ? 0 : item.costCents,
                      );
                      await store.recalcJobTotals(widget.jobId);
                    },
                  ),
                  const SizedBox(height: 4),
                  SecondaryButton(
                    label: 'Свободная строка',
                    icon: CupertinoIcons.plus,
                    dense: true,
                    onPressed: () async {
                      final view = await showCupertinoModalPopup<JobLineView>(
                        context: context,
                        builder: (_) => const JobLineEditorSheet(),
                      );
                      if (view == null || !mounted) return;
                      await store.createJobLine(
                        widget.jobId,
                        kind: view.kind,
                        name: view.name,
                        qty: view.qty,
                        unit: view.unit,
                        priceCents: view.priceCents,
                        costAtOrderCents: view.costAtOrderCents,
                        discountCents: view.discountCents,
                      );
                      await store.recalcJobTotals(widget.jobId);
                    },
                  ),
                ],
              ),
            ),
            if (lines.isNotEmpty && lines.any((l) => l.itemId != null)) ...[
              const SizedBox(height: 16),
              SectionLabel('Состав по каталогу'),
              AppCard(
                child: Column(
                  children: [
                    for (final line in lines.where((l) => l.itemId != null)) ...[
                      if (line.itemId != null) ...[
                        Text(
                          '— ${line.name}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: colors.secondaryLabel,
                          ),
                        ),
                        for (final part in store.itemComposition(line.itemId!))
                          if (!part.isLabor && part.componentId != null)
                            KeyValueRow(
                              part.note == null
                                  ? part.componentId!
                                  : part.note!,
                              '${formatQty(line.quantity * part.qty)} ${store.inventoryItems.where((i) => i.id == part.componentId).firstOrNull?.unit ?? ''}',
                              dense: true,
                            ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    SecondaryButton(
                      label: 'Списать со склада',
                      icon: CupertinoIcons.cube_box,
                      dense: true,
                      onPressed: () async {
                        final confirmed = await showAppConfirm(
                          context,
                          title: 'Списать со склада',
                          message:
                              'Списать материалы заказа по составу каталога? '
                              'Остатки уменьшатся на требуемое количество.',
                          confirmLabel: 'Списать',
                          destructive: true,
                        );
                        if (!confirmed || !mounted) return;
                        try {
                          final written =
                              await store.writeOffJobMaterials(
                            widget.jobId,
                            lineIds: lines.map((l) => l.id).toList(),
                          );
                          if (!mounted) return;
                          await showAppAlert(
                            context,
                            title: 'Списано',
                            message:
                                'Записей движения: $written. Обновите склад.',
                          );
                        } catch (_) {
                          if (mounted) {
                            await showAppAlert(
                              context,
                              title: 'Ошибка списания',
                              message:
                                  'Не удалось обновить остаток. Проверьте журнал.',
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SectionLabel('Учёт времени'),
            AppCard(
              child: Column(
                children: [
                  if (_timerStart != null) ...[
                    Text(
                      _formatElapsed(_elapsedSeconds),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      label: 'Остановить',
                      icon: CupertinoIcons.stop,
                      onPressed: () => _stopTimer(store),
                    ),
                  ] else ...[
                    PrimaryButton(
                      label: 'Начать работу',
                      icon: CupertinoIcons.play,
                      onPressed: _startTimer,
                    ),
                  ],
                  const SizedBox(height: 10),
                  SecondaryButton(
                    label: 'Добавить сессию вручную',
                    icon: CupertinoIcons.plus,
                    onPressed: () => _addSessionManual(store),
                  ),
                  if (todaySeconds > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Наработано за день: ${formatMinutes(todaySeconds ~/ 60)}',
                          style: TextStyle(
                            color: colors.secondaryLabel,
                            fontSize: 13,
                          ),
                        ),
                        if (settings.hourRateCents > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '≈ ${money(((todaySeconds * settings.hourRateCents) / 3600).round())}',
                            style: TextStyle(
                              color: colors.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (sessions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...sessions.map(
                      (s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${DateFormat('d MMM', 'ru').format(s.startedAt)} • ${formatMinutes(s.minutes)}',
                                style: TextStyle(color: colors.label),
                              ),
                            ),
                            if (s.note != null && s.note!.isNotEmpty)
                              Text(
                                s.note!,
                                style: TextStyle(
                                  color: colors.secondaryLabel,
                                  fontSize: 12,
                                ),
                              ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => store.deleteSession(s.id),
                              child: Icon(
                                CupertinoIcons.xmark,
                                size: 14,
                                color: colors.tertiaryLabel,
                                semanticLabel: 'Удалить',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (store.paidForJob(job.id) > 0 || job.priceCents > 0) ...[
              SectionLabel('Оплата'),
              Builder(
                builder: (context) {
                  final obligation = store.openJobPaymentObligation(job.id);
                  final remaining = obligation != null
                      ? obligation.remainingCents
                      : (job.priceCents - store.paidForJob(job.id)).clamp(
                          0,
                          1 << 40,
                        );
                  return AppCard(
                    child: Column(
                      children: [
                        _KV(
                          'Оплачено',
                          '${money(store.paidForJob(job.id))}',
                        ),
                        _KV('Остаток', '${money(remaining)}'),
                        if (obligation != null)
                          _KV(
                            'Срок оплаты',
                            formatFullDate(obligation.dueAt),
                          ),
                        SecondaryButton(
                          label: 'Принять оплату',
                          icon: CupertinoIcons.money_dollar,
                          onPressed: () => _acceptPayment(store, job),
                        ),
                        // «Напомнить» (§Э2.1): тот же share sheet, что и в
                        // долгах — мастер отправляет текст в мессенджер сам.
                        if (remaining > 0) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ChipButton(
                              label: 'Напомнить',
                              icon: CupertinoIcons.paperplane,
                              onPressed: () => _remindPayment(
                                client?.name ?? 'Клиент',
                                job,
                                remaining,
                                obligation?.dueAt ??
                                    job.dueDate ??
                                    DateTime.now()
                                        .add(const Duration(days: 7)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            SectionLabel('Вложения (${_attachments.length})'),
            AppCard(
              child: Column(
                children: [
                  if (_attachments.isEmpty)
                    EmptyState(
                      title: 'Нет вложений',
                      message: 'Добавьте фото, смету или документ.',
                    ),
                  ..._attachments.map(
                    (a) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.doc,
                            color: context.colors.secondaryLabel,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              a.fileName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => OpenFilex.open(a.filePath),
                            child: const Icon(
                              CupertinoIcons.eye,
                              size: 18,
                              semanticLabel: 'Открыть',
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => _removeAttachment(a),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 16,
                              color: context.colors.tertiaryLabel,
                              semanticLabel: 'Удалить',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SecondaryButton(
                    label: _busyAttachment ? 'Добавление...' : 'Добавить файл',
                    icon: CupertinoIcons.plus,
                    onPressed: _busyAttachment ? () {} : _addAttachment,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Действия'),
            AppCard(
              child: Column(
                children: [
                  _ActionTile(
                    icon: job.archived
                        ? CupertinoIcons.tray_full
                        : CupertinoIcons.archivebox,
                    label: job.archived ? 'Восстановить' : 'В архив',
                    onTap: () => store.setArchived(job.id, !job.archived),
                  ),
                  Hairline(indent: 0),
                  SecondaryButton(
                    label: 'Создать документ (PDF)',
                    icon: CupertinoIcons.doc_text,
                    onPressed: () => _createDocument(store, job),
                  ),
                  Hairline(indent: 0),
                  SecondaryButton(
                    label: 'КП',
                    icon: CupertinoIcons.doc_on_clipboard,
                    onPressed: () => _openQuote(store, job),
                  ),
                  Hairline(indent: 0),
                  SecondaryButton(
                    label: 'Написать клиенту',
                    icon: CupertinoIcons.chat_bubble,
                    onPressed: () => _sendMessage(store, job),
                  ),
                  Hairline(indent: 0),
                  _ActionTile(
                    icon: CupertinoIcons.delete,
                    label: 'Удалить заказ',
                    destructive: true,
                    onTap: () async {
                      final ok = await showAppConfirm(
                        context,
                        title: 'Удалить заказ?',
                        message: 'Этапы, материалы и время тоже удалятся.',
                        destructive: true,
                        confirmLabel: 'Удалить',
                      );
                      if (!ok) return;
                      await store.deleteJob(job.id);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final h = m ~/ 60;
    final mm = m % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${mm.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _KV extends StatelessWidget {
  const _KV(this.keyLabel, this.value);
  final String keyLabel;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(keyLabel, style: TextStyle(color: colors.secondaryLabel)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = destructive ? colors.red : colors.accent;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 8),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: destructive ? colors.red : colors.label,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: colors.tertiaryLabel,
          ),
        ],
      ),
    );
  }
}

Color _priorityColor(BuildContext context, JobPriority priority) {
  final colors = context.colors;
  return switch (priority) {
    JobPriority.low => const Color(0xFF6B7A8F),
    JobPriority.medium => colors.orange,
    JobPriority.high => colors.red,
  };
}

Color _tagColor(String tag) {
  const palette = <Color>[
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
    Color(0xFF5AC8FA),
    Color(0xFFFFCC00),
    Color(0xFF8E8E93),
  ];
  final hash = tag.trim().codeUnits.fold<int>(
    0,
    (value, unit) => value * 31 + unit,
  );
  return palette[hash.abs() % palette.length];
}
