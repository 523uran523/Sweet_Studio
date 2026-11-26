/// Секции и шиты клиентских кредитов (§5.5, Э4).
///
/// Деньги клиента — депозиты, абонементы и сертификаты. Поступление живёт в
/// `money_transactions`, списание — только в `audit_log` (§12.1), поэтому
/// история движения читается из `store.creditHistory`.
library;

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/money_format.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/client_credit.dart';
import '../../data/models/credit_change.dart';
import '../../state/masters_store.dart';
import '../../state/settings_controller.dart';
import 'client_detail_screen.dart';

String creditStatusLabel(String status) => switch (status) {
  'active' => 'Активен',
  'used' => 'Использован',
  'refunded' => 'Возвращён',
  'expired' => 'Истёк',
  _ => status,
};

Color creditStatusColor(AppColors colors, String status) => switch (status) {
  'active' => colors.green,
  'used' => colors.accent,
  'refunded' => colors.orange,
  'expired' => colors.red,
  _ => colors.secondaryLabel,
};

/// «Деньги клиента»: обязательство + «Любимые позиции» (§6.8).
///
/// Кредиты прячутся под `module_credits`, любимые позиции — всегда: их считать
/// можно и без модуля, а владельцу они полезны в любом режиме.
class ClientMoneySection extends StatelessWidget {
  const ClientMoneySection({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<MastersStore>();
    final creditsEnabled = context.watch<SettingsController>().creditsEnabled;
    final favorites = store.favoritePositions(clientId);
    if (!creditsEnabled && favorites.isEmpty) return const SizedBox.shrink();
    final credits = store.clientCredits(clientId);
    final owed = credits
        .where((c) => c.isActive)
        .fold(0, (sum, c) => sum + c.remainingCents);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (favorites.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: KeyValueRow(
              'Любимые позиции',
              favorites.join(', '),
              dense: true,
            ),
          ),
        ],
        if (creditsEnabled) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SectionLabel(
                  credits.isEmpty
                      ? 'Деньги клиента'
                      : 'Деньги клиента · ${countLabel(credits.length, ['кредит', 'кредита', 'кредитов'])}',
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                ),
              ),
              ChipButton(
                label: 'Пополнить',
                icon: CupertinoIcons.plus,
                onPressed: () => showClientCreditSheet(context, clientId: clientId),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (credits.isEmpty)
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeyValueRow('Обязательство', money(0), dense: true),
                  const SizedBox(height: 6),
                  Text(
                    'Депозит, абонемент или сертификат: деньги приняты, услуга ещё не оказана.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.secondaryLabel,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: KeyValueRow(
                'Обязательство',
                money(owed),
                dense: true,
                emphasis: owed > 0,
                valueColor: owed > 0 ? colors.orange : null,
              ),
            ),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                children: [
                  for (var i = 0; i < credits.length; i++) ...[
                    if (i > 0) const Hairline(indent: 12),
                    _CreditRow(credit: credits[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _CreditRow extends StatelessWidget {
  const _CreditRow({required this.credit});

  final ClientCredit credit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dateFmt = DateFormat('d MMM yyyy', 'ru');

    final units = credit.unitsTotal == null
        ? null
        : '${credit.unitsLeft}/${credit.unitsTotal} посещений';
    final expiry = credit.expiresAt == null
        ? null
        : credit.isActive && credit.expiresAt!.isBefore(DateTime.now())
            ? 'срок ${dateFmt.format(credit.expiresAt!)} истёк'
            : 'до ${dateFmt.format(credit.expiresAt!)}';
    final subtitle = [
      credit.kindLabel,
      ?units,
      ?expiry,
      creditStatusLabel(credit.status),
    ].join(' · ');

    return ListRow(
      dense: true,
      icon: CupertinoIcons.creditcard,
      iconColor: creditStatusColor(colors, credit.status),
      title: credit.title.isEmpty ? credit.kindLabel : credit.title,
      subtitle: subtitle,
      trailing: Text(
        money(credit.remainingCents),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: credit.isActive ? colors.label : colors.tertiaryLabel,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      onTap: () => showClientCreditSheet(context, existing: credit),
      showChevron: true,
    );
  }
}

/// Шит кредита: создание и просмотр одного кредита с историей движений.
Future<void> showClientCreditSheet(
  BuildContext context, {
  String? clientId,
  ClientCredit? existing,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => _ClientCreditSheet(clientId: clientId, existing: existing),
  );
}

class _ClientCreditSheet extends StatefulWidget {
  const _ClientCreditSheet({this.clientId, this.existing});

  final String? clientId;
  final ClientCredit? existing;

  @override
  State<_ClientCreditSheet> createState() => _ClientCreditSheetState();
}

class _ClientCreditSheetState extends State<_ClientCreditSheet> {
  static const _kinds = ['deposit', 'pass', 'certificate', 'rental_deposit'];

  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : (widget.existing!.amountCents / 100).toStringAsFixed(0),
  );
  late final TextEditingController _units = TextEditingController(
    text: widget.existing?.unitsTotal?.toString() ?? '',
  );
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late String _kind = widget.existing?.kind ?? 'deposit';
  late DateTime? _expiresAt = widget.existing?.expiresAt;

  bool get _isCreate => widget.existing == null;

  @override
  void dispose() {
    for (final c in [_title, _amount, _units, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    var picked = _expiresAt ?? DateTime.now().add(const Duration(days: 90));
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
                    setState(() => _expiresAt = picked);
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('ОК'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: picked,
                onDateTimeChanged: (value) => picked = value,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final store = context.read<MastersStore>();
    final clientId = widget.clientId;
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (clientId == null || amount <= 0) return;
    final units = int.tryParse(_units.text.trim());
    await store.createClientCredit(
      clientId: clientId,
      kind: _kind,
      title: _title.text.trim().isEmpty ? _kindLabel(_kind) : _title.text,
      amountCents: amount * 100,
      unitsTotal: (units == null || units <= 0) ? null : units,
      expiresAt: _expiresAt,
      note: _note.text,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _kindLabel(String kind) => switch (kind) {
    'deposit' => 'Депозит',
    'pass' => 'Абонемент',
    'certificate' => 'Сертификат',
    'rental_deposit' => 'Залог за аренду',
    _ => 'Кредит',
  };

  Future<void> _use() async {
    final credit = widget.existing;
    if (credit == null) return;
    await showUseCreditSheet(context, credit);
  }

  Future<void> _refund() async {
    final store = context.read<MastersStore>();
    final credit = widget.existing;
    if (credit == null) return;
    final ok = await showAppConfirm(
      context,
      title: 'Вернуть деньги клиенту?',
      message:
          'Остаток ${money(credit.remainingCents)} уйдёт из кассы, '
          'обязательство закроется.',
      confirmLabel: 'Вернуть',
    );
    if (!ok) return;
    await store.refundClientCredit(
      creditId: credit.id,
      amountCents: credit.remainingCents,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final store = context.read<MastersStore>();
    final credit = widget.existing;
    if (credit == null) return;
    final ok = await showAppConfirm(
      context,
      title: 'Удалить кредит?',
      message: 'Запись скроется из карточки клиента; история останется в журнале.',
      destructive: true,
      confirmLabel: 'Удалить',
    );
    if (!ok) return;
    await store.deleteClientCredit(credit.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<MastersStore>();
    final credit = widget.existing;
    final dateFmt = DateFormat('d MMM yyyy', 'ru');
    final history = credit == null ? const <CreditChange>[] : store.creditHistory(credit.id);

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
                _isCreate ? 'Новый кредит' : (credit!.title.isEmpty ? credit.kindLabel : credit.title),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: colors.label,
                ),
              ),
              if (!_isCreate) ...[
                const SizedBox(height: 6),
                Text(
                  '${credit!.kindLabel} · ${creditStatusLabel(credit.status)} · остаток ${money(credit.remainingCents)}',
                  style: TextStyle(fontSize: 13.5, color: colors.secondaryLabel),
                ),
              ],
              const SizedBox(height: 12),
              if (_isCreate) ...[
                CupertinoTextField(
                  controller: _title,
                  placeholder: 'Название (сертификат на 3 занятия)',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final kind in _kinds)
                      ChipButton(
                        label: _kindLabel(kind),
                        color: _kind == kind ? colors.accent : null,
                        onPressed: () => setState(() => _kind = kind),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              CupertinoTextField(
                controller: _amount,
                placeholder: _isCreate ? 'Сумма пополнения' : money(credit?.amountCents ?? 0),
                enabled: _isCreate,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _units,
                placeholder: 'Посещений (для абонемента, необязательно)',
                enabled: _isCreate,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: ListRow(
                  dense: true,
                  icon: CupertinoIcons.calendar,
                  title: _expiresAt == null
                      ? 'Срок действия'
                      : 'Действует до ${dateFmt.format(_expiresAt!)}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isCreate && _expiresAt != null)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: Size.zero,
                          onPressed: () => setState(() => _expiresAt = null),
                          child: const Icon(
                            CupertinoIcons.clear_circled,
                            size: 16,
                          ),
                        ),
                      if (_isCreate)
                        const Icon(
                          CupertinoIcons.chevron_right,
                          size: 15,
                          color: CupertinoColors.systemGrey,
                        ),
                    ],
                  ),
                  onTap: _isCreate ? _pickExpiry : null,
                ),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: _note,
                placeholder: 'Заметка',
                enabled: _isCreate,
                maxLines: 2,
                style: const TextStyle(fontSize: 15),
              ),
              if (_isCreate) ...[
                const SizedBox(height: 14),
                PrimaryButton(
                  label: 'Пополнить',
                  icon: CupertinoIcons.plus,
                  onPressed: _canCreate ? _create : null,
                  enabled: _canCreate,
                ),
              ] else ...[
                const SizedBox(height: 14),
                if (credit!.isActive)
                  PrimaryButton(
                    label: 'Списать',
                    icon: CupertinoIcons.checkmark,
                    onPressed: _use,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (credit.remainingCents > 0 && credit.isActive)
                      Expanded(
                        child: ChipButton(
                          label: 'Вернуть остаток',
                          icon: CupertinoIcons.arrow_left,
                          onPressed: _refund,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChipButton(
                        label: 'Удалить',
                        icon: CupertinoIcons.trash,
                        color: colors.red,
                        onPressed: _delete,
                      ),
                    ),
                  ],
                ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SectionLabel('История · ${history.length}'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      children: [
                        for (var i = 0; i < history.length && i < 12; i++) ...[
                          if (i > 0) const Hairline(indent: 12),
                          _HistoryRow(change: history[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _canCreate =>
      widget.clientId != null && (int.tryParse(_amount.text.trim()) ?? 0) > 0;
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.change});

  final CreditChange change;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final date = DateFormat('d MMM yyyy, HH:mm', 'ru').format(change.moment);
    final delta = change.deltaCents;
    return ListRow(
      dense: true,
      icon: CupertinoIcons.clock,
      iconColor: delta < 0 ? colors.orange : colors.green,
      title: change.description,
      subtitle: date,
      trailing: Text(
        '${delta < 0 ? '−' : '+'}${money(delta.abs())}',
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: delta < 0 ? colors.red : colors.green,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Шит списания кредита: сумма и (для абонементов) посещения.
Future<void> showUseCreditSheet(
  BuildContext context,
  ClientCredit credit, {
  String? jobId,
  int? maxCents,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => _UseCreditSheet(credit: credit, jobId: jobId, maxCents: maxCents),
  );
}

class _UseCreditSheet extends StatefulWidget {
  const _UseCreditSheet({
    required this.credit,
    this.jobId,
    this.maxCents,
  });

  final ClientCredit credit;
  final String? jobId;
  final int? maxCents;

  @override
  State<_UseCreditSheet> createState() => _UseCreditSheetState();
}

class _UseCreditSheetState extends State<_UseCreditSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: (((widget.maxCents ?? widget.credit.remainingCents).clamp(0, widget.credit.remainingCents)) / 100)
        .toStringAsFixed(0),
  );
  late final TextEditingController _units =
      TextEditingController(text: widget.credit.unitsLeft == null ? '' : '1');

  @override
  void dispose() {
    _amount.dispose();
    _units.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final store = context.read<MastersStore>();
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final units = int.tryParse(_units.text.trim());
    await store.useClientCredit(
      creditId: widget.credit.id,
      amountCents: amount * 100,
      jobId: widget.jobId,
      units: (units == null || units <= 0) ? null : units,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final credit = widget.credit;

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
                'Списание с кредита',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: colors.label,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${credit.title.isEmpty ? credit.kindLabel : credit.title} · остаток ${money(credit.remainingCents)}',
                style: TextStyle(fontSize: 13.5, color: colors.secondaryLabel),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _amount,
                placeholder: 'Сумма списания',
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 15),
                onChanged: (_) => setState(() {}),
              ),
              if (credit.unitsLeft != null) ...[
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: _units,
                  placeholder: 'Посещений (осталось ${credit.unitsLeft})',
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 15),
                ),
              ],
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(
                  'Списание не трогает кассу: деньги пришли при пополнении. '
                  'Выручка вырастет ровно на списанную сумму.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: colors.secondaryLabel,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PrimaryButton(
                label: 'Списать',
                icon: CupertinoIcons.checkmark,
                onPressed: _canApply ? _apply : null,
                enabled: _canApply,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canApply => (int.tryParse(_amount.text.trim()) ?? 0) > 0;
}

/// Экран «Обязательства перед клиентами» из Деньг (§5.5 п.3).
class ClientCreditsScreen extends StatelessWidget {
  const ClientCreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<MastersStore>();
    final credits = store.credits
        .where((c) => c.deletedAt == null)
        .toList()
      ..sort((a, b) {
        final byActive = (b.isActive ? 1 : 0).compareTo(a.isActive ? 1 : 0);
        return byActive != 0 ? byActive : b.updatedAt.compareTo(a.updatedAt);
      });
    final total = credits
        .where((c) => c.isActive)
        .fold(0, (sum, c) => sum + c.remainingCents);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Обязательства')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            AppCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Перед клиентами',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  KeyValueRow('Обязательств', money(total), emphasis: total > 0),
                  KeyValueRow(
                    'Активных кредитов',
                    countLabel(credits.where((c) => c.isActive).length, ['кредит', 'кредита', 'кредитов']),
                    dense: true,
                  ),
                  KeyValueRow(
                    'Истекло',
                    '${credits.where((c) => c.status == 'expired').length}',
                    dense: true,
                    valueColor: credits.any((c) => c.status == 'expired') ? colors.red : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Это полученные деньги, которые ещё не отработаны. '
                    'Срок истёк — деньги остаются в кассе до вашего решения: '
                    'вернуть или признать выручкой.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: colors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (credits.isEmpty)
              const EmptyState(
                title: 'Обязательств нет',
                message: 'Депозиты и сертификаты появятся здесь после пополнения.',
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  children: [
                    for (var i = 0; i < credits.length; i++) ...[
                      if (i > 0) const Hairline(indent: 12),
                      _CreditTile(credit: credits[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.credit});

  final ClientCredit credit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.read<MastersStore>();
    final client = store.clientById(credit.clientId);
    final dateFmt = DateFormat('d MMM yyyy', 'ru');
    final expiry = credit.expiresAt == null
        ? null
        : '${creditStatusLabel(credit.status) == 'Истёк' ? 'срок истёк ' : 'до '}${dateFmt.format(credit.expiresAt!)}';

    return ListRow(
      dense: true,
      icon: CupertinoIcons.creditcard,
      iconColor: creditStatusColor(colors, credit.status),
      title: credit.title.isEmpty ? credit.kindLabel : credit.title,
      subtitle: [
        client?.name ?? 'клиент удалён',
        credit.kindLabel,
        if (credit.unitsLeft != null) '${credit.unitsLeft}/${credit.unitsTotal}',
        ?expiry,
      ].join(' · '),
      subtitleColor: credit.isActive ? null : colors.tertiaryLabel,
      trailing: Text(
        money(credit.remainingCents),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: credit.isActive ? colors.label : colors.tertiaryLabel,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      showChevron: true,
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => ClientDetailScreen(clientId: credit.clientId),
        ),
      ),
    );
  }
}
