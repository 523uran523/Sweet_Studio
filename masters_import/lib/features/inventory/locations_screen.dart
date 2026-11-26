import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/units.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/stock_batch.dart';
import '../../data/models/stock_location.dart';
import '../../state/masters_store.dart';
import 'stock_transfer_screen.dart';

/// Учёт по точкам (§5.6, Э5): список локаций, их остатки и истекающие партии.
///
/// Экран доступен только под `module_locations`: при выключенном флаге склад
/// остаётся однозначным и точка здесь ничего не добавила бы (§12.2).
class LocationsScreen extends StatefulWidget {
  const LocationsScreen({super.key, this.focusLocationId});

  /// Точка, чей остаток раскрыть сразу — переход из карточки позиции.
  final String? focusLocationId;

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final Set<String> _expanded = <String>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusLocationId != null) _expanded.add(widget.focusLocationId!);
  }

  Future<T?> _guarded<T>(Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _prompt(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: title,
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

  Future<void> _newLocation() async {
    final name = await _prompt('Название точки');
    if (name == null || name.isEmpty || !mounted) return;
    await _guarded(() => context.read<MastersStore>().createLocation(name: name));
  }

  Future<void> _rename(StockLocation location) async {
    final name = await _prompt('Название точки', initial: location.name);
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _guarded(
      () => context.read<MastersStore>().updateLocation(
        location.id,
        name: name.trim(),
      ),
    );
  }

  Future<void> _delete(StockLocation location) async {
    final ok = await showAppConfirm(
      context,
      title: 'Удалить точку?',
      message: location.name,
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final store = context.read<MastersStore>();
    setState(() => _busy = true);
    try {
      await store.deleteLocation(location.id);
    } on ArgumentError catch (error) {
      if (mounted) {
        await showAppAlert(
          context,
          title: 'Нельзя удалить',
          message: '${error.message}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transfer(MastersStore store, {String? fromLocationId}) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => StockTransferScreen(fromLocationId: fromLocationId),
      ),
    );
  }

  /// Позиции точки с остатком выше нуля — содержимое карточки.
  List<({StockLevel level, InventoryItem item})> _contents(
    MastersStore store,
    String locationId,
  ) {
    final result = <({StockLevel level, InventoryItem item})>[];
    for (final level in store.stockLevels) {
      if (level.locationId != locationId || level.qty <= 0) continue;
      final item = store.inventoryItems
          .where((i) => i.id == level.itemId)
          .cast<InventoryItem?>()
          .firstOrNull;
      if (item == null || item.archived) continue;
      result.add((level: level, item: item));
    }
    result.sort((a, b) => a.item.name.compareTo(b.item.name));
    return result;
  }

  int _kinds(MastersStore store, String locationId) =>
      _contents(store, locationId).length;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final expiring = store.expiringBatches(days: 3);
    final expired = store.batches
        .where((b) => b.qty > 0 && b.isExpiredAt(DateTime.now()))
        .toList();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Точки склада'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: () => _transfer(store),
              child: const Icon(
                CupertinoIcons.arrow_left_right,
                semanticLabel: 'Перемещение',
              ),
            ),
            const SizedBox(width: 4),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: _newLocation,
              child: const Icon(CupertinoIcons.plus, semanticLabel: 'Новая точка'),
            ),
          ],
        ),
      ),
      child: _busy
          ? const Center(child: CupertinoActivityIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 72),
                children: [
                  if (expired.isNotEmpty) ...[
                    SectionLabel('Просрочено · ${expired.length}'),
                    _BatchesCard(
                      store: store,
                      batches: expired,
                      tone: colors.red,
                      caption: 'списать нельзя',
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (expiring.isNotEmpty) ...[
                    SectionLabel('Истекает · ${expiring.length}'),
                    _BatchesCard(
                      store: store,
                      batches: expiring,
                      tone: colors.orange,
                      caption: 'ближе всего по сроку',
                    ),
                    const SizedBox(height: 16),
                  ],
                  SectionLabel('Точки · ${store.locations.length}'),
                  if (store.locations.isEmpty)
                    EmptyState(
                      title: 'Нет точек',
                      message:
                          'Добавьте точку — остатки распределятся по ним, а '
                          'перемещение покажет, где что лежит.',
                      art: Icon(
                        CupertinoIcons.location,
                        size: 48,
                        color: colors.tertiaryLabel,
                      ),
                      actions: [
                        PrimaryButton(
                          label: 'Добавить точку',
                          icon: CupertinoIcons.plus,
                          onPressed: _newLocation,
                        ),
                      ],
                    )
                  else
                    for (final location in store.locations) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          onTap: () => setState(() {
                            if (!_expanded.remove(location.id)) {
                              _expanded.add(location.id);
                            }
                          }),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                location.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            if (location.isDefault) ...[
                                              const SizedBox(width: 6),
                                              const Pill('основной'),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_kinds(store, location.id)} '
                                          '${itemsWord(_kinds(store, location.id))}'
                                          ' · ${_belowLabel(store, location.id)}',
                                          style: TextStyle(
                                            color: colors.secondaryLabel,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(32, 32),
                                    onPressed: () => _showActions(location),
                                    child: Icon(
                                      CupertinoIcons.ellipsis_circle,
                                      size: 19,
                                      color: colors.secondaryLabel,
                                      semanticLabel: 'Действия',
                                    ),
                                  ),
                                ],
                              ),
                              if (_expanded.contains(location.id)) ...[
                                const Hairline(indent: 4),
                                _contentsBody(store, location),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                ],
              ),
            ),
    );
  }

  String _belowLabel(MastersStore store, String locationId) {
    final count = store.belowMinOnLocation(locationId).length;
    return count == 0 ? 'всего в норме' : 'мало: $count';
  }

  Widget _contentsBody(MastersStore store, StockLocation location) {
    final colors = context.colors;
    final contents = _contents(store, location.id);
    final below = store.belowMinOnLocation(location.id);
    final belowIds = below.map((g) => g.item.id).toSet();

    if (contents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: Text(
          'Точка пуста.',
          style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
        ),
      );
    }

    return Column(
      children: [
        for (final entry in contents)
          ListRow(
            dense: true,
            title: entry.item.name,
            subtitle: belowIds.contains(entry.item.id)
                ? 'мало · минимум ${formatQty(store.minQtyOnLocation(entry.item, location.id))} ${entry.item.unit}'
                : null,
            icon: CupertinoIcons.cube_box,
            iconColor:
                belowIds.contains(entry.item.id) ? colors.red : colors.secondaryLabel,
            trailing: Text(
              '${formatQty(entry.level.qty)} ${entry.item.unit}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: belowIds.contains(entry.item.id)
                    ? colors.red
                    : colors.label,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        if (store.locations.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: SecondaryButton(
              label: 'Вывезти с этой точки',
              icon: CupertinoIcons.arrow_right,
              onPressed: () => _transfer(store, fromLocationId: location.id),
            ),
          ),
      ],
    );
  }

  Future<void> _showActions(StockLocation location) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => CupertinoActionSheet(
        title: Text(location.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(modalContext).pop();
              _rename(location);
            },
            child: const Text('Переименовать'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(modalContext).pop();
              _transfer(context.read<MastersStore>(),
                  fromLocationId: location.id);
            },
            child: const Text('Переместить отсюда'),
          ),
          if (!location.isDefault)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(modalContext).pop();
                _delete(location);
              },
              child: const Text('Удалить'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(modalContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
  }
}

/// Список партий с подписью «что с ними не так».
class _BatchesCard extends StatelessWidget {
  const _BatchesCard({
    required this.store,
    required this.batches,
    required this.tone,
    required this.caption,
  });

  final MastersStore store;
  final List<StockBatch> batches;
  final Color tone;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < batches.length && i < 8; i++) ...[
            if (i > 0) const Hairline(indent: 12),
            ListRow(
              dense: true,
              title: store.itemName(batches[i].itemId),
              subtitle: '${store.locationName(batches[i].locationId)} · $caption',
              icon: CupertinoIcons.clock,
              iconColor: tone,
              trailing: Text(
                formatQty(batches[i].qty),
                style: TextStyle(
                  color: tone,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          if (batches.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Text(
                'и ещё ${batches.length - 8}',
                style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
