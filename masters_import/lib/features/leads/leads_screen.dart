import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/money_format.dart';
import '../../core/reminder_text.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/lead.dart';
import '../../state/masters_store.dart';
import '../jobs/job_detail_screen.dart';
import 'lead_detail_screen.dart';
import 'quotes_screen.dart';

/// Заявки (§5.4/§6.7): обращения, которые ещё не стали заказом.
///
/// Сегменты: Активные | Зависшие | Отказ | Конвертированы. «Зависшие» —
/// активные с наступившим следующим шагом (§Э3.1): их мастер видит отдельно,
/// потому что именно такие обращения теряются в переписке.
class LeadsScreen extends StatefulWidget {
  const LeadsScreen({super.key, this.initialSegment = 'active'});

  final String initialSegment;

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  late String _segment = widget.initialSegment;
  String _query = '';

  List<Lead> _visible(MastersStore store) {
    var list = switch (_segment) {
      'stale' => store.staleLeads(),
      'refused' => store.leadsByStatus('refused'),
      'converted' => store.leadsByStatus('converted'),
      _ => store.leadsByStatus('active')
        ..sort((a, b) {
          // Просроченные — наверху: их нужно закрывать первыми.
          final at = DateTime.now();
          final ao = a.isStaleAt(at) ? 0 : 1;
          final bo = b.isStaleAt(at) ? 0 : 1;
          if (ao != bo) return ao.compareTo(bo);
          final an = a.nextStepAt, bn = b.nextStepAt;
          if (an != null && bn != null) return an.compareTo(bn);
          if (an != null) return -1;
          if (bn != null) return 1;
          return b.createdAt.compareTo(a.createdAt);
        }),
    };
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (l) =>
                l.name.toLowerCase().contains(q) ||
                l.phone.contains(q) ||
                (l.request?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final funnel = store.leadsFunnel();
    final leads = _visible(store);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Заявки'),
        trailing: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          onPressed: () => _edit(null),
          child: const Icon(CupertinoIcons.plus_circle, size: 24),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CupertinoSlidingSegmentedControl<String>(
                groupValue: _segment,
                children: const {
                  'active': Text('Активные'),
                  'stale': Text('Зависшие'),
                  'refused': Text('Отказ'),
                  'converted': Text('Конверт.'),
                },
                onValueChanged: (value) {
                  if (value != null) setState(() => _segment = value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: CupertinoTextField(
                style: const TextStyle(fontSize: 15),
                placeholder: 'Имя, телефон или запрос',
                clearButtonMode: OverlayVisibilityMode.editing,
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 10, right: 6),
                  child: Icon(
                    CupertinoIcons.search,
                    size: 16,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (_segment == 'active' && funnel.stale > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ChipButton(
                    label: 'зависшие: ${funnel.stale}',
                    icon: CupertinoIcons.exclamationmark_circle,
                    color: colors.orange,
                    onPressed: () => setState(() => _segment = 'stale'),
                  ),
                ),
              ),
            Expanded(
              child: leads.isEmpty
                  ? EmptyState(
                      title: 'Заявок нет',
                      message: switch (_segment) {
                        'stale' =>
                          'Ни одна активная заявка не просрочена — следующий шаг по всем запланирован на будущее.',
                        'refused' => 'Отказов нет.',
                        'converted' =>
                          'Пока ни одна заявка не стала заказом.',
                        _ =>
                          'Добавьте обращение, запланируйте следующий шаг — и заявка не потеряется.',
                      },
                      actions: [
                        PrimaryButton(
                          label: 'Добавить заявку',
                          icon: CupertinoIcons.plus,
                          onPressed: () => _edit(null),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
                      itemCount: leads.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _LeadCard(lead: leads[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(Lead? lead) async => showLeadSheet(context, lead: lead);
}

/// Шит заявки — публичный, потому что править заявку нужно и из её карточки.
Future<void> showLeadSheet(BuildContext context, {Lead? lead}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => _LeadSheet(lead: lead),
  );
}

/// Карточка заявки: кто, что просит, бюджет и следующий шаг.
class _LeadCard extends StatelessWidget {
  const _LeadCard({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.read<MastersStore>();
    final now = DateTime.now();
    final stale = lead.isStaleAt(now);
    final dateFmt = DateFormat('d MMM', 'ru');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(builder: (_) => LeadDetailScreen(leadId: lead.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: CupertinoIcons.person_crop_circle,
                color: stale ? colors.orange : colors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.name.isEmpty ? lead.phone : lead.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: colors.label,
                      ),
                    ),
                    if (lead.phone.isNotEmpty)
                      Text(
                        '${lead.phone} · ${leadSourceLabel(lead.source)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.secondaryLabel,
                        ),
                      ),
                  ],
                ),
              ),
              OverflowMenuButton(
                title: lead.name,
                actions: [
                  CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _convert(context, store);
                    },
                    child: const Text('Создать заказ'),
                  ),
                  CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) => QuotesScreen(leadId: lead.id),
                        ),
                      );
                    },
                    child: const Text('КП'),
                  ),
                  if (lead.isActive)
                    CupertinoActionSheetAction(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _remind(context);
                      },
                      child: const Text('Напомнить'),
                    ),
                  if (lead.isActive)
                    CupertinoActionSheetAction(
                      isDestructiveAction: true,
                      onPressed: () {
                        Navigator.of(context).pop();
                        _refuse(context, store);
                      },
                      child: const Text('Отказ'),
                    ),
                ],
              ),
            ],
          ),
          if (lead.request != null && lead.request!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              lead.request!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: colors.label),
            ),
          ],
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (lead.budgetCents > 0)
                Pill(money(lead.budgetCents), icon: CupertinoIcons.money_dollar),
              if (lead.nextStepAt != null)
                Pill(
                  'шаг ${dateFmt.format(lead.nextStepAt!)}',
                  icon: CupertinoIcons.calendar,
                  color: stale ? colors.orange : null,
                ),
              if (stale)
                Pill(
                  'просрочено ${pluralRu(lead.daysOverdue(now), ['день', 'дня', 'дней'])}',
                  color: colors.red,
                  icon: CupertinoIcons.exclamationmark_triangle,
                ),
              if (lead.status == 'converted')
                Pill('в заказе', color: colors.green),
              if (lead.status == 'refused')
                Pill(lead.closeReason ?? 'отказ', color: colors.secondaryLabel),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _convert(BuildContext context, MastersStore store) async {
    final title = await _askText(
      context,
      title: 'Заказ по заявке',
      placeholder: 'Название заказа',
      initial: lead.request ?? lead.name,
    );
    if (title == null || !context.mounted) return;
    final job = await store.convertLeadToJob(
      lead.id,
      title: title,
      priceCents: lead.budgetCents,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => JobDetailScreen(jobId: job.id)),
    );
  }

  Future<void> _remind(BuildContext context) async {
    final result = await shareReminderText(
      leadFollowUpText(
        clientName: lead.name,
        leadTitle: lead.request ?? lead.name,
        nextStepAt: lead.nextStepAt ?? DateTime.now(),
      ),
    );
    if (!context.mounted) return;
    if (result == ReminderShareResult.copied) {
      await showAppAlert(
        context,
        title: 'Текст скопирован',
        message: 'Откройте WhatsApp/Telegram и вставьте.',
      );
    } else if (result == ReminderShareResult.failed) {
      await showAppAlert(context, title: 'Не удалось', message: 'Попробуйте ещё раз.');
    }
  }

  Future<void> _refuse(BuildContext context, MastersStore store) async {
    final reason = await _askText(
      context,
      title: 'Причина отказа',
      placeholder: 'дорого / не подходит срок',
    );
    if (reason == null || !context.mounted) return;
    await store.closeLead(lead.id, reason: reason);
  }
}

/// Простой ввод одной строки (название заказа, причина отказа).
Future<String?> _askText(
  BuildContext context, {
  required String title,
  String placeholder = '',
  String? initial,
}) async {
  final controller = TextEditingController(text: initial ?? '');
  final value = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          style: const TextStyle(fontSize: 15),
          autofocus: true,
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
          child: const Text('ОК'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

/// Шит создания/правки заявки.
class _LeadSheet extends StatefulWidget {
  const _LeadSheet({this.lead});

  final Lead? lead;

  @override
  State<_LeadSheet> createState() => _LeadSheetState();
}

class _LeadSheetState extends State<_LeadSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.lead?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.lead?.phone ?? '');
  late final TextEditingController _request =
      TextEditingController(text: widget.lead?.request ?? '');
  late final TextEditingController _budget = TextEditingController(
    text: widget.lead == null || widget.lead!.budgetCents == 0
        ? ''
        : (widget.lead!.budgetCents / 100).toStringAsFixed(0),
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.lead?.note ?? '');
  late String _source = widget.lead?.source ?? 'other';
  late DateTime? _nextStepAt = widget.lead?.nextStepAt;

  @override
  void dispose() {
    for (final c in [_name, _phone, _request, _budget, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty || _phone.text.trim().isNotEmpty;

  Future<void> _pickNextStep() async {
    var picked = _nextStepAt ?? DateTime.now().add(const Duration(days: 2));
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => Container(
        height: 260,
        color: context.colors.card,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Отмена'),
                ),
                CupertinoButton(
                  onPressed: () {
                    setState(() => _nextStepAt = picked);
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('ОК'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: picked,
                use24hFormat: true,
                onDateTimeChanged: (value) => picked = value,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final store = context.read<MastersStore>();
    final budget = int.tryParse(_budget.text.trim()) ?? 0;
    if (widget.lead == null) {
      await store.createLead(
        name: _name.text,
        phone: _phone.text,
        source: _source,
        request: _request.text,
        budgetCents: (budget <= 0 ? 0 : budget) * 100,
        nextStepAt: _nextStepAt,
        note: _note.text,
      );
    } else {
      await store.updateLead(
        widget.lead!.copyWith(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          source: _source,
          request: _request.text.trim(),
          budgetCents: (budget <= 0 ? 0 : budget) * 100,
          nextStepAt: _nextStepAt,
          note: _note.text.trim(),
        ),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dateFmt = DateFormat('d MMM yyyy, HH:mm', 'ru');

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: const SheetHandle()),
              const SizedBox(height: 14),
              Text(
                widget.lead == null ? 'Новая заявка' : 'Заявка',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: colors.label,
                ),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _name,
                placeholder: 'Имя',
                style: const TextStyle(fontSize: 15),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _phone,
                placeholder: 'Телефон',
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 15),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _request,
                placeholder: 'Что просит (торт на 15 кг, 20 ноября)',
                maxLines: 2,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final source in kLeadSources)
                    ChipButton(
                      label: leadSourceLabel(source),
                      color: _source == source ? colors.accent : null,
                      onPressed: () => setState(() => _source = source),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: _budget,
                placeholder: 'Бюджет, ₸',
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: ListRow(
                  dense: true,
                  icon: CupertinoIcons.calendar,
                  title: _nextStepAt == null
                      ? 'Следующий шаг'
                      : 'Шаг: ${dateFmt.format(_nextStepAt!)}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_nextStepAt != null)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          onPressed: () =>
                              setState(() => _nextStepAt = null),
                          child: const Icon(
                            CupertinoIcons.clear_circled,
                            size: 16,
                          ),
                        ),
                      const Icon(
                        CupertinoIcons.chevron_right,
                        size: 15,
                        color: CupertinoColors.systemGrey,
                      ),
                    ],
                  ),
                  onTap: _pickNextStep,
                ),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _note,
                placeholder: 'Заметка',
                maxLines: 2,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                label: 'Сохранить',
                enabled: _canSave,
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
