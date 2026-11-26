import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/units.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/stock_location.dart';
import '../../state/masters_store.dart';

/// Перемещение между точками (§5.6).
///
/// Проводится сразу: перекладывание ящика — не намерение на неделю. Список
/// позиций показывает остаток источника, чтобы «вывезти 5 кг муки» не
/// превратилось в отрицательный остаток.
class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key, this.fromLocationId});

  final String? fromLocationId;

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  String? _fromId;
  String? _toId;
  final Map<String, double> _qty = <String, double>{};
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  String? _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<MastersStore>();
    _fromId = widget.fromLocationId ?? store.locations.firstOrNull?.id;
    _toId = store.locations
        .where((l) => l.id != _fromId)
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Позиции, которые есть на точке-источнике: везти нечего — нечего и выбирать.
  List<({InventoryItem item, double qty})> _available(MastersStore store) {
    final from = _fromId;
    if (from == null) return const [];
    final result = <({InventoryItem item, double qty})>[];
    for (final level in store.stockLevels) {
      if (level.locationId != from || level.qty <= 0) continue;
      final item = store.inventoryItems
          .where((i) => i.id == level.itemId && !i.archived)
          .cast<InventoryItem?>()
          .firstOrNull;
      if (item == null) continue;
      result.add((item: item, qty: level.qty));
    }
    result.sort((a, b) => a.item.name.compareTo(b.item.name));
    return result;
  }

  void _setQty(String itemId, String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;
    setState(() => _qty[itemId] = value);
  }

  Future<void> _save() async {
    final store = context.read<MastersStore>();
    final from = _fromId;
    final to = _toId;
    if (from == null || to == null) return;
    final lines = _qty.entries
        .where((e) => e.value > 0)
        .map((e) => <String, Object?>{'itemId': e.key, 'qty': e.value})
        .toList();
    if (lines.isEmpty) {
      await showAppAlert(
        context,
        title: 'Пустое перемещение',
        message: 'Укажите количество хотя бы по одной позиции.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await store.createStockTransfer(
        fromLocationId: from,
        toLocationId: to,
        lines: lines,
        note: _note,
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

  Future<void> _pickFrom() async {
    final store = context.read<MastersStore>();
    final id = await _pickLocation(
      store.locations.where((l) => l.id != _toId).toList(),
      title: 'Откуда',
    );
    if (id == null || !mounted) return;
    setState(() {
      _fromId = id;
      // Источник сменился — остатки другие, количества могли стать лишними.
      _qty.clear();
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      if (_toId == id) {
        _toId = store.locations.where((l) => l.id != id).firstOrNull?.id;
      }
    });
  }

  Future<void> _pickTo() async {
    final store = context.read<MastersStore>();
    final id = await _pickLocation(
      store.locations.where((l) => l.id != _fromId).toList(),
      title: 'Куда',
    );
    if (id == null || !mounted) return;
    setState(() => _toId = id);
  }

  Future<String?> _pickLocation(
    List<StockLocation> options, {
    required String title,
  }) {
    if (options.isEmpty) return Future.value(null);
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final location in options)
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
  }

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note ?? '');
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Комментарий'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(controller: controller, autofocus: true),
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
    if (value != null) setState(() => _note = value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final available = _available(store);
    final total = _qty.values.where((v) => v > 0).length;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Перемещение'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(34, 34),
          onPressed: total == 0 ? null : _save,
          child: Text(
            'Провести',
            style: TextStyle(
              color: total == 0 ? colors.tertiaryLabel : colors.accent,
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
                          title: 'Откуда',
                          subtitle: store.locationName(_fromId),
                          icon: CupertinoIcons.arrow_left,
                          trailing: const Icon(
                            CupertinoIcons.chevron_right,
                            size: 14,
                          ),
                          onTap: _pickFrom,
                        ),
                        const Hairline(indent: 12),
                        ListRow(
                          title: 'Куда',
                          subtitle: store.locationName(_toId),
                          icon: CupertinoIcons.arrow_right,
                          trailing: const Icon(
                            CupertinoIcons.chevron_right,
                            size: 14,
                          ),
                          onTap: _pickTo,
                        ),
                        const Hairline(indent: 12),
                        ListRow(
                          title: 'Комментарий',
                          subtitle: _note ?? 'не указан',
                          icon: CupertinoIcons.text_alignleft,
                          trailing: const Icon(
                            CupertinoIcons.chevron_right,
                            size: 14,
                          ),
                          onTap: _editNote,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_toId == null)
                    EmptyState(
                      title: 'Нужна вторая точка',
                      message:
                          'Перемещение имеет смысл, когда точек хотя бы две.',
                      art: Icon(
                        CupertinoIcons.location,
                        size: 48,
                        color: colors.tertiaryLabel,
                      ),
                    )
                  else if (available.isEmpty)
                    EmptyState(
                      title: 'На этой точке пусто',
                      message: 'Сначала привезите сюда позиции.',
                      art: Icon(
                        CupertinoIcons.cube_box,
                        size: 48,
                        color: colors.tertiaryLabel,
                      ),
                    )
                  else ...[
                    SectionLabel('Что вывезти'),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < available.length; i++) ...[
                            if (i > 0) const Hairline(indent: 12),
                            _line(available[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _line(({InventoryItem item, double qty}) entry) {
    final colors = context.colors;
    final item = entry.item;
    final available = entry.qty;
    final controller = _controllers.putIfAbsent(
      item.id,
      () => TextEditingController(text: _qty[item.id]?.toString() ?? ''),
    );
    final planned = _qty[item.id] ?? 0;
    final over = planned > available;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  'на точке ${formatQty(available)} ${item.unit}',
                  style: TextStyle(
                    color: over ? colors.red : colors.secondaryLabel,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: CupertinoTextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              placeholder: '0',
              onChanged: (value) => _setQty(item.id, value),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            item.unit,
            style: TextStyle(
              color: colors.secondaryLabel,
              fontSize: 12.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
