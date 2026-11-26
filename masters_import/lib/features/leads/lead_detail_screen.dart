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
import '../clients/client_detail_screen.dart';
import '../jobs/job_detail_screen.dart';
import 'leads_screen.dart';
import 'quotes_screen.dart';

/// Карточка заявки.
///
/// Здесь принимаются решения по заявке, поэтому кнопки — действия стора, а не
/// переходы: «Создать заказ» (конверсия), «КП», «Напомнить» (share), «Отказ».
class LeadDetailScreen extends StatelessWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final lead = store.leadById(leadId);
    if (lead == null) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(),
        child: Center(child: Text('Заявка не найдена')),
      );
    }
    final colors = context.colors;
    final client = lead.clientId == null
        ? null
        : store.clientById(lead.clientId!);
    final daysOver = lead.daysOverdue(DateTime.now());

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(client?.name ?? lead.name),
        trailing: OverflowMenuButton(
          title: lead.name,
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(context).pop();
                showLeadSheet(context, lead: lead);
              },
              child: const Text('Изменить'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                final navigator = Navigator.of(context);
                Navigator.of(context).pop();
                final ok = await showAppConfirm(
                  context,
                  title: 'Удалить заявку?',
                  message: 'Заявка и её КП исчезнут из истории.',
                  confirmLabel: 'Удалить',
                  destructive: true,
                );
                if (!ok) return;
                await store.deleteLead(lead.id);
                navigator.pop();
              },
              child: const Text('Удалить'),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lead.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: colors.label,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(
                        lead.statusLabel,
                        color: switch (lead.status) {
                          'converted' => colors.green,
                          'refused' => colors.secondaryLabel,
                          _ => colors.accent,
                        },
                      ),
                      if (daysOver > 0)
                        Pill(
                          'просрочено $daysOver ${daysWord(daysOver)}',
                          color: colors.orange,
                          icon: CupertinoIcons.exclamationmark_triangle_fill,
                        ),
                      Pill('источник: ${lead.sourceLabel}'),
                    ],
                  ),
                  if (lead.request != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      lead.request!,
                      style: TextStyle(fontSize: 14, color: colors.label),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Детали'),
            AppCard(
              child: Column(
                children: [
                  KeyValueRow(
                    'Клиент',
                    client == null
                        ? (lead.name.isEmpty ? '—' : lead.name)
                        : client.name,
                    onTap: client == null
                        ? null
                        : () => Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) =>
                                    ClientDetailScreen(clientId: client.id),
                              ),
                            ),
                  ),
                  const Hairline(indent: 4),
                  KeyValueRow('Телефон', lead.phone.isEmpty ? '—' : lead.phone),
                  const Hairline(indent: 4),
                  KeyValueRow(
                    'Бюджет',
                    lead.budgetCents > 0
                        ? money(lead.budgetCents)
                        : 'не указан',
                  ),
                  const Hairline(indent: 4),
                  KeyValueRow(
                    'Следующий шаг',
                    lead.nextStepAt == null
                        ? 'не назначен'
                        : DateFormat('d MMMM yyyy', 'ru').format(
                            lead.nextStepAt!,
                          ),
                    valueColor: daysOver > 0 ? colors.orange : null,
                  ),
                  if (lead.closeReason != null) ...[
                    const Hairline(indent: 4),
                    KeyValueRow('Причина отказа', lead.closeReason!),
                  ],
                  if (lead.note != null) ...[
                    const Hairline(indent: 4),
                    KeyValueRow('Заметка', lead.note!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel('Действия'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lead.isActive) ...[
                    PrimaryButton(
                      label: 'Создать заказ',
                      icon: CupertinoIcons.wrench,
                      onPressed: () => _convert(context, store, lead),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChipButton(
                          label: 'Напомнить',
                          icon: CupertinoIcons.paperplane,
                          onPressed: () => _remind(context, lead),
                        ),
                        ChipButton(
                          label: 'Назначить шаг',
                          icon: CupertinoIcons.calendar,
                          onPressed: () => _pickStep(context, store, lead),
                        ),
                        ChipButton(
                          label: 'Отказ',
                          icon: CupertinoIcons.xmark_circle,
                          color: colors.red,
                          onPressed: () => _refuse(context, store, lead),
                        ),
                      ],
                    ),
                  ] else if (lead.convertedJobId != null) ...[
                    PrimaryButton(
                      label: 'Открыть заказ',
                      icon: CupertinoIcons.arrow_right_circle,
                      onPressed: () => Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) =>
                              JobDetailScreen(jobId: lead.convertedJobId!),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListRow(
                    dense: true,
                    icon: CupertinoIcons.doc_text,
                    title: 'Коммерческие предложения',
                    subtitle: '${store.quotesForLead(lead.id).length} КП',
                    showChevron: true,
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => QuotesScreen(leadId: lead.id),
                      ),
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

  Future<void> _convert(
    BuildContext context,
    MastersStore store,
    Lead lead,
  ) async {
    final navigator = Navigator.of(context);
    final job = await store.convertLeadToJob(
      lead.id,
      title: lead.request ?? lead.name,
      priceCents: lead.budgetCents,
    );
    navigator.push(
      CupertinoPageRoute(builder: (_) => JobDetailScreen(jobId: job.id)),
    );
  }

  Future<void> _remind(BuildContext context, Lead lead) async {
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
      await showAppAlert(
        context,
        title: 'Не удалось',
        message: 'Попробуйте ещё раз.',
      );
    }
  }

  Future<void> _pickStep(
    BuildContext context,
    MastersStore store,
    Lead lead,
  ) async {
    final value = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (sheetContext) {
        var picked =
            lead.nextStepAt ?? DateTime.now().add(const Duration(days: 2));
        return Container(
          height: 300,
          color: context.colors.card,
          child: Column(
            children: [
              CupertinoButton(
                onPressed: () => Navigator.of(sheetContext).pop(picked),
                child: const Text('Сохранить'),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: picked,
                  use24hFormat: true,
                  onDateTimeChanged: (v) => picked = v,
                ),
              ),
            ],
          ),
        );
      },
    );
    if (value == null) return;
    await store.updateLead(lead.copyWith(nextStepAt: value));
  }

  Future<void> _refuse(
    BuildContext context,
    MastersStore store,
    Lead lead,
  ) async {
    final controller = TextEditingController();
    final reason = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Причина отказа'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'например: дорого',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            isDefaultAction: true,
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Отказать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;
    await store.closeLead(lead.id, reason: reason);
  }
}
