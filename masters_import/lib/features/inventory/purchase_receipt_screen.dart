import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/money_format.dart';
import '../../core/units.dart';
import '../../data/models/supplier.dart';
import '../../state/masters_store.dart';

/// Приёмка закупки (§5.6): сколько фактически приехало и куда легло.
///
/// Расхождение — не ошибка ввода, а штатный случай: недопоставку экран считает
/// вслух и показывает новый долг поставщику, иначе «приняли 8 из 10» выглядело
/// бы как прощённые 200 без следа в деньгах.
class PurchaseReceiptScreen extends StatefulWidget {
  const PurchaseReceiptScreen({super.key, this.purchaseId});

  /// Открыть сразу эту закупку; иначе экран показывает список непринятых.
  final String? purchaseId;

  @override
  State<PurchaseReceiptScreen> createState() => _PurchaseReceiptScreenState();
}

class _PurchaseReceiptScreenState extends State<PurchaseReceiptScreen> {
  String? _purchaseId;
  String? _locationId;
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, DateTime> _expiry = <String, DateTime>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<MastersStore>();
    _purchaseId = widget.purchaseId ?? _firstPending(store)?.id;
    _locationId = store.locations.firstOrNull?.id;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Purchase? _firstPending(MastersStore store) {
    for (final p in store.purchases) {
      if (!p.isReceived) return p;
    }
    return null;
  }

  List<PurchaseLine> get _lines {
    final id = _purchaseId;
    if (id == null) return const [];
    return context.read<MastersStore>().linesForPurchase(id);
  }

  TextEditingController _controllerFor(PurchaseLine line) {
    return _controllers.putIfAbsent(
      line.id,
      () => TextEditingController(
        text: formatQty(line.receivedQty ?? line.qty),
      ),
    );
  }

  double _receivedOf(PurchaseLine line) =>
      double.tryParse(
        (_controllers[line.id]?.text ?? '').trim().replaceAll(',', '.'),
      ) ??
      0;

  /// Сумма принятых строк — ровно тот долг, который останется после приёмки.
  int _receivedTotalCents() {
    int total = 0;
    for (final line in _lines) {
      total += (_receivedOf(line) * line.unitPriceCents).round();
    }
    return total;
  }

  Future<void> _pickPurchase() async {
    final store = context.read<MastersStore>();
    if (store.purchases.isEmpty) return;
    final id = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Закупка'),
        actions: [
          for (final purchase in store.purchases)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(purchase.id),
              child: Text(
                '${store.supplierName(purchase.supplierId)} · '
                '${money(purchase.totalCents)}'
                '${purchase.isReceived ? ' · принята' : ''}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (id == null || !mounted) return;
    setState(() {
      _purchaseId = id;
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      _expiry.clear();
    });
  }

  Future<void> _pickLocation() async {
    final store = context.read<MastersStore>();
    if (store.locations.isEmpty) return;
    final id = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('На какую точку'),
        actions: [
          for (final location in store.locations)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(location.id),
              child: Text(location.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (id != null) setState(() => _locationId = id);
  }

  Future<void> _pickExpiry(PurchaseLine line) async {
    var picked = _expiry[line.itemId] ??
        DateTime.now().add(const Duration(days: 7));
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 260,
        color: context.colors.card,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Готово'),
              ),
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
    if (!mounted) return;
    setState(() => _expiry[line.itemId] = DateTime(
      picked.year,
      picked.month,
      picked.day,
      23,
      59,
    ));
  }

  Future<void> _clearExpiry(PurchaseLine line) async {
    setState(() => _expiry.remove(line.itemId));
  }

  Future<void> _accept() async {
    final store = context.read<MastersStore>();
    final id = _purchaseId;
    if (id == null) return;
    final received = <String, double>{};
    for (final line in _lines) {
      final value = _receivedOf(line);
      if (value < 0) {
        await showAppAlert(
          context,
          title: 'Отрицательное количество',
          message: 'Принять меньше нуля нельзя.',
        );
        return;
      }
      received[line.itemId] = value;
    }
    setState(() => _busy = true);
    try {
      await store.receivePurchase(
        purchaseId: id,
        received: received,
        expiry: _expiry,
        locationId: _locationId,
      );
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (error) {
      if (mounted) {
        await showAppAlert(
          context,
          title: 'Не получилось',
          message: '${error.message}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final purchaseId = _purchaseId;
    final purchase = purchaseId == null
        ? null
        : store.purchases
            .where((p) => p.id == purchaseId)
            .cast<Purchase?>()
            .firstOrNull;
    final lines = purchaseId == null ? const <PurchaseLine>[] : _lines;
    final ordered = (purchase?.totalCents ?? 0);
    final accepted = _receivedTotalCents();
    final shortCents = ordered - accepted;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Приёмка'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(34, 34),
          onPressed: purchase == null ? null : _accept,
          child: Text(
            'Принять',
            style: TextStyle(
              color: purchase == null ? colors.tertiaryLabel : colors.accent,
            ),
          ),
        ),
      ),
      child: _busy
          ? const Center(child: CupertinoActivityIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
                children: [
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListRow(
                          title: 'Закупка',
                          subtitle: purchase == null
                              ? 'не выбрана'
                              : '${store.supplierName(purchase.supplierId)} · '
                                    '${money(purchase.totalCents)}'
                                    '${purchase.isReceived ? ' · уже принята' : ''}',
                          icon: CupertinoIcons.doc_on_clipboard,
                          trailing: const Icon(
                            CupertinoIcons.chevron_right,
                            size: 14,
                          ),
                          onTap: _pickPurchase,
                        ),
                        const Hairline(indent: 12),
                        ListRow(
                          title: 'Точка прихода',
                          subtitle: store.locationName(_locationId),
                          icon: CupertinoIcons.location,
                          trailing: const Icon(
                            CupertinoIcons.chevron_right,
                            size: 14,
                          ),
                          onTap: _pickLocation,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (purchase == null)
                    EmptyState(
                      title: 'Нет закупок',
                      message:
                          'Сначала запишите закупку — потом примите её по факту.',
                      art: Icon(
                        CupertinoIcons.doc_on_clipboard,
                        size: 48,
                        color: colors.tertiaryLabel,
                      ),
                    )
                  else ...[
                    SectionLabel('Принято по строкам'),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < lines.length; i++) ...[
                            if (i > 0) const Hairline(indent: 12),
                            _line(lines[i]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      child: Column(
                        children: [
                          KeyValueRow('Заказано', money(ordered)),
                          KeyValueRow(
                            'Принято',
                            money(accepted),
                            valueColor: colors.green,
                          ),
                          if (shortCents.abs() > 0)
                            KeyValueRow(
                              'Недопоставка',
                              money(shortCents),
                              valueColor: shortCents > 0
                                  ? colors.orange
                                  : colors.red,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                      child: Text(
                        shortCents.abs() <= 0
                            ? 'Долг поставщику не меняется.'
                            : 'Долг поставщику станет '
                                  '${money(accepted)} вместо ${money(ordered)}.',
                        style: TextStyle(
                          color: colors.secondaryLabel,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _line(PurchaseLine line) {
    final colors = context.colors;
    final store = context.read<MastersStore>();
    final expiry = _expiry[line.itemId];
    final short = _receivedOf(line) + 0.0001 < line.qty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                      store.itemName(line.itemId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'заказано ${formatQty(line.qty)} · '
                      '${money(line.unitPriceCents)} за ед.',
                      style: TextStyle(
                        color: colors.secondaryLabel,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: CupertinoTextField(
                  controller: _controllerFor(line),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (short)
                const Pill('недопоставка', color: CupertinoColors.systemOrange),
              const SizedBox(width: 6),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 26),
                onPressed: () => _pickExpiry(line),
                child: Text(
                  expiry == null
                      ? 'срок годности: не указан'
                      : 'срок: ${DateFormat('dd.MM.yyyy', 'ru').format(expiry)}',
                  style: TextStyle(fontSize: 12, color: colors.accent),
                ),
              ),
              if (expiry != null)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(28, 26),
                  onPressed: () => _clearExpiry(line),
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 13,
                    color: colors.secondaryLabel,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
