import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/document_service.dart';
import '../../core/money_format.dart';
import '../../data/models/quote.dart';
import '../../state/masters_store.dart';

/// История КП (§12.4).
///
/// Список — по заказу или по заявке: мастер приходит в КП либо из карточки
/// заказа («Отправить КП» / «История КП»), либо из карточки заявки. Каждая
/// строка — конкретная ревизия со своим снимком, поэтому «открыть» всегда
/// отдаёт ровно тот документ, который уходил клиенту.
class QuotesScreen extends StatelessWidget {
  const QuotesScreen({super.key, this.jobId, this.leadId});

  final String? jobId;
  final String? leadId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final quotes = jobId != null
        ? store.quotesForJob(jobId!)
        : store.quotesForLead(leadId ?? '');

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: const Text('Коммерческие предложения')),
      child: SafeArea(
        child: quotes.isEmpty
            ? EmptyState(
                title: 'КП ещё нет',
                message:
                    'Снимок создаётся из строк заказа: номер, ревизия, итог и '
                    'срок действия фиксируются, и правка заказа документ не меняет.',
                actions: [
                  if (jobId != null)
                    PrimaryButton(
                      label: 'Создать КП из заказа',
                      icon: CupertinoIcons.doc_on_clipboard,
                      onPressed: () => _create(context, store),
                    ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  if (jobId != null) ...[
                    PrimaryButton(
                      label: 'Новая ревизия',
                      icon: CupertinoIcons.doc_on_clipboard,
                      onPressed: () => _create(context, store),
                    ),
                    const SizedBox(height: 14),
                  ],
                  for (final quote in quotes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _QuoteCard(quote: quote),
                    ),
                  if (quotes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Старые ревизии хранятся: клиент видит ровно то, что '
                        'согласовывал.',
                        style: TextStyle(fontSize: 12.5, color: colors.secondaryLabel),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _create(BuildContext context, MastersStore store) async {
    if (jobId == null) return;
    final quote = await store.saveQuoteSnapshot(jobId!);
    if (!context.mounted) return;
    await _savePdf(context, store, quote);
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.read<MastersStore>();
    final dateFmt = DateFormat('d MMM yyyy', 'ru');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${quote.number} · ред. ${quote.revision}',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: colors.label,
                  ),
                ),
              ),
              Pill(
                quote.statusLabel,
                color: switch (quote.status) {
                  'accepted' => colors.green,
                  'rejected' => colors.red,
                  _ => colors.accent,
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          KeyValueRow('Итог', money(quote.totalCents), emphasis: true, dense: true),
          KeyValueRow(
            'Создано',
            dateFmt.format(quote.createdAt),
            dense: true,
          ),
          if (quote.validUntil != null)
            KeyValueRow(
              'Действительно до',
              dateFmt.format(quote.validUntil!),
              valueColor: quote.isExpired ? colors.orange : null,
              dense: true,
            ),
          if (quote.sentAt != null)
            KeyValueRow('Отправлено', dateFmt.format(quote.sentAt!), dense: true),
          KeyValueRow('Позиций', '${quote.lines.length}', dense: true),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChipButton(
                label: 'Открыть PDF',
                icon: CupertinoIcons.doc_text,
                onPressed: () => _openPdf(context, store),
              ),
              ChipButton(
                label: 'Сохранить заново',
                icon: CupertinoIcons.square_arrow_down,
                onPressed: () => _savePdf(context, store, quote),
              ),
              if (quote.status == 'draft')
                ChipButton(
                  label: 'Отправлено',
                  icon: CupertinoIcons.paperplane,
                  onPressed: () => store.markQuoteSent(quote.id),
                ),
              if (quote.status != 'accepted')
                ChipButton(
                  label: 'Принято',
                  icon: CupertinoIcons.checkmark,
                  color: colors.green,
                  onPressed: () => store.setQuoteStatus(quote.id, 'accepted'),
                ),
              ChipButton(
                label: 'Удалить',
                icon: CupertinoIcons.trash,
                color: colors.red,
                onPressed: () => _delete(context, store),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPdf(BuildContext context, MastersStore store) async {
    if (quote.pdfPath == null) {
      // PDF не генерируем «на лету» из заказа: снимок мог быть создан давно,
      // и мастер должен видеть именно тот документ, а не его пересборку.
      await _savePdf(context, store, quote);
      return;
    }
    final file = File(quote.pdfPath!);
    if (!await file.exists()) {
      if (!context.mounted) return;
      await showAppAlert(
        context,
        title: 'Файл потерян',
        message: 'PDF был удалён с устройства. Сохраните снимок заново.',
      );
      return;
    }
    await OpenFilex.open(quote.pdfPath!);
  }

  Future<void> _delete(BuildContext context, MastersStore store) async {
    final ok = await showAppConfirm(
      context,
      title: 'Удалить ${quote.number} ред. ${quote.revision}?',
      message: 'Снимок исчезнет из истории этого заказа.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok) return;
    await store.deleteQuote(quote.id);
  }
}

/// Рендерит снимок в PDF и предлагает сохранить; путь кладём на КП.
Future<void> _savePdf(
  BuildContext context,
  MastersStore store,
  Quote quote,
) async {
  final bytes = await DocumentService.buildQuotePdf(quote);
  if (!context.mounted) return;
  final name =
      '${quote.number}-rev${quote.revision}-${quote.createdAt.millisecondsSinceEpoch}.pdf';
  final path = await DocumentService.savePdfPath(bytes, name);
  if (path != null) await store.setQuotePdfPath(quote.id, path);
  if (!context.mounted) return;
  await showAppAlert(
    context,
    title: 'Готово',
    message: path == null
        ? 'Сохранение отменено — снимок остался в истории.'
        : 'КП сохранено: ${quote.number}, ревизия ${quote.revision}.',
  );
}

