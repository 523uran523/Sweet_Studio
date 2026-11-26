import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/units.dart';
import '../../data/models/inventory_item.dart';
import '../../state/masters_store.dart';
import 'calculator_core.dart';
import '../../core/money_format.dart';

class CostCalculatorScreen extends StatefulWidget {
  const CostCalculatorScreen({
    super.key,
    this.initialMaterialsCents = 0,
    this.jobId,
    this.inventoryItemId,
  });

  final int initialMaterialsCents;

  /// Если задан — состояние калькулятора сохраняется/восстанавливается
  /// в jobs.calculator_state через MastersStore.
  final String? jobId;

  /// Если задан — калькулятор открыт для позиции склада: результат
  /// записывается в её себестоимость (и цену продажи).
  final String? inventoryItemId;

  @override
  State<CostCalculatorScreen> createState() => _CostCalculatorScreenState();
}

class _ResourceLine {
  _ResourceLine({
    String name = '',
    String qty = '1',
    required this.qtyUnit,
    required this.priceUnit,
    String price = '0',
    String loss = '0',
    this.inventoryItemId,
    this.writeOff = false,
  }) : nameController = TextEditingController(text: name),
       qtyController = TextEditingController(text: qty),
       priceController = TextEditingController(text: price),
       lossController = TextEditingController(text: loss);

  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  final TextEditingController lossController;
  String qtyUnit;
  String priceUnit;
  final String? inventoryItemId;

  /// Списывать ли эту строку со склада при применении.
  bool writeOff;

  /// Нетто-количество (без учёта потерь) в исходной единице.
  double get qty => _parse(qtyController.text);

  /// Эффективное (брутто) количество с учётом технологических потерь.
  /// null — если количество или процент потерь некорректны.
  double? get effectiveQty => effectiveQuantity(
        qtyText: qtyController.text,
        lossText: lossController.text,
      );

  bool get lossValid => effectiveQty != null;

  int get priceCents => (_parse(priceController.text) * 100).round();

  int get totalCents {
    final effective = effectiveQty;
    if (effective == null) return 0;
    return resourceLineTotalCents(
      qty: effective,
      qtyUnit: qtyUnit,
      priceCents: priceCents,
      priceUnit: priceUnit,
    );
  }

  /// Эффективное количество в единице склада (для списания/расчёта).
  double? qtyInStockUnit(InventoryItem item) {
    final effective = effectiveQty;
    if (effective == null) return null;
    return convertQty(effective, qtyUnit, item.unit);
  }

  /// Нетто-количество в единице склада (для пополнения/создания позиции).
  double? netQtyInStockUnit(InventoryItem item) =>
      convertQty(qty, qtyUnit, item.unit);

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
    lossController.dispose();
  }

  static double _parse(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
}

/// Результат выбора в листе позиций склада.
class _PickedStock {
  const _PickedStock(this.item);
  final InventoryItem item;
}

const String _kCustomRow = '__custom__';

class _CostCalculatorScreenState extends State<CostCalculatorScreen> {
  final List<_ResourceLine> _resources = [];
  final _laborHoursController = TextEditingController(text: '0');
  final _laborRateController = TextEditingController(text: '0');
  final _pieceworkController = TextEditingController(text: '0');
  final _overheadController = TextEditingController(text: '0');
  final _overheadFixedController = TextEditingController(text: '0');
  final _otherController = TextEditingController(text: '0');
  final _finishedDefectController = TextEditingController(text: '0');
  final _marginController = TextEditingController(text: '30');
  final _targetMarginController = TextEditingController(text: '30');
  final _fixedPriceController = TextEditingController(text: '0');
  final _packagingController = TextEditingController(text: '0');
  final _shippingController = TextEditingController(text: '0');
  final _storageController = TextEditingController(text: '0');
  final _returnShippingController = TextEditingController(text: '0');
  final _buyoutController = TextEditingController(text: '100');
  final _commissionController = TextEditingController(text: '0');
  final _advertisingController = TextEditingController(text: '0');
  final _acquiringController = TextEditingController(text: '0');
  PricingMode _pricingMode = PricingMode.markup;
  bool _busy = false;

  InventoryItem? get _stockTarget {
    final id = widget.inventoryItemId;
    if (id == null) return null;
    for (final item in context.read<MastersStore>().inventoryItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool get _isStockMode => widget.inventoryItemId != null;

  @override
  void initState() {
    super.initState();
    if (_isStockMode) {
      _seedFromStockItem();
    } else if (widget.initialMaterialsCents > 0) {
      _resources.add(
        _ResourceLine(
          name: 'Материалы',
          qty: '1',
          qtyUnit: 'шт',
          price: (widget.initialMaterialsCents / 100).toStringAsFixed(2),
          priceUnit: 'за шт',
        ),
      );
    }
    _restoreIfNeeded();
  }

  /// Режим склада: подставить состав позиции (BOM), если он есть,
  /// иначе одну строку с её себестоимостью.
  void _seedFromStockItem() {
    final item = _stockTarget;
    if (item == null) return;
    final store = context.read<MastersStore>();
    final composition = store.itemComposition(item.id);
    if (composition.isEmpty) {
      if (item.costCents > 0) {
        _resources.add(
          _ResourceLine(
            name: item.name,
            qty: '1',
            qtyUnit: item.unit,
            price: (item.costCents / 100).toStringAsFixed(2),
            priceUnit: defaultPriceUnit(item.unit),
            inventoryItemId: item.id,
          ),
        );
      }
      return;
    }
    for (final line in composition) {
      if (line.isLabor || line.componentId == null) {
        _resources.add(
          _ResourceLine(
            name: line.note?.trim().isNotEmpty == true
                ? line.note!.trim()
                : 'Ручной труд',
            qty: formatQty(line.qty),
            qtyUnit: 'шт',
            price: (line.priceCents / 100).toStringAsFixed(2),
            priceUnit: 'за шт',
          ),
        );
        continue;
      }
      InventoryItem? component;
      for (final candidate in store.inventoryItems) {
        if (candidate.id == line.componentId) {
          component = candidate;
          break;
        }
      }
      _resources.add(
        _ResourceLine(
          name: component?.name ?? 'Компонент удалён',
          qty: formatQty(line.qty),
          qtyUnit: component?.unit ?? 'шт',
          price: (line.priceCents / 100).toStringAsFixed(2),
          priceUnit: defaultPriceUnit(component?.unit ?? 'шт'),
          inventoryItemId: component?.id,
          writeOff: component?.trackStock ?? false,
        ),
      );
    }
  }

  Future<void> _restoreIfNeeded() async {
    final jobId = widget.jobId;
    if (jobId == null || !mounted) return;
    final store = Provider.of<MastersStore>(context, listen: false);
    final json = await store.calculatorStateForJob(jobId);
    if (!mounted || json == null) return;
    final data = _decodeState(json);
    if (data == null) return;
    _applySaved(data);
    setState(() {});
  }

  Map<String, dynamic>? _decodeState(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['schema'] != 1) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  void _applySaved(Map<String, dynamic> data) {
    for (final r in _resources) {
      r.dispose();
    }
    _resources.clear();
    final rawResources = data['resources'];
    if (rawResources is List) {
      for (final entry in rawResources) {
        if (entry is! Map) continue;
        final map = entry.cast<String, dynamic>();
        final qtyUnit = (map['qtyUnit'] is String && (map['qtyUnit'] as String).isNotEmpty)
            ? map['qtyUnit'] as String
            : 'шт';
        final allowed = priceUnitsFor(qtyUnit);
        final priceUnit =
            (map['priceUnit'] is String && allowed.contains(map['priceUnit']))
            ? map['priceUnit'] as String
            : defaultPriceUnit(qtyUnit);
        _resources.add(
          _ResourceLine(
            name: (map['name'] as String?) ?? '',
            qty: (map['qty'] as String?) ?? '1',
            qtyUnit: qtyUnit,
            price: (map['price'] as String?) ?? '0',
            priceUnit: priceUnit,
            loss: (map['loss'] as String?) ?? '0',
            inventoryItemId: map['inventoryItemId'] as String?,
            writeOff: map['writeOff'] == true,
          ),
        );
      }
    }
    final labor = data['labor'] is Map
        ? (data['labor'] as Map).cast<String, dynamic>()
        : null;
    _laborHoursController.text = (labor?['hours'] as String?) ?? '0';
    _laborRateController.text = (labor?['rate'] as String?) ?? '0';
    _pieceworkController.text = (data['piecework'] as String?) ?? '0';
    _overheadController.text = (data['overhead'] as String?) ?? '0';
    _overheadFixedController.text =
        (data['overheadFixed'] as String?) ?? '0';
    _otherController.text = (data['other'] as String?) ?? '0';
    _finishedDefectController.text = (data['finishedDefect'] as String?) ?? '0';
    _marginController.text = (data['margin'] as String?) ?? '30';
    _targetMarginController.text = (data['targetMargin'] as String?) ?? '30';
    _fixedPriceController.text = (data['fixedPrice'] as String?) ?? '0';
    _packagingController.text = (data['packaging'] as String?) ?? '0';
    _shippingController.text = (data['shipping'] as String?) ?? '0';
    _storageController.text = (data['storage'] as String?) ?? '0';
    _returnShippingController.text =
        (data['returnShipping'] as String?) ?? '0';
    _buyoutController.text = (data['buyout'] as String?) ?? '100';
    _commissionController.text = (data['commission'] as String?) ?? '0';
    _advertisingController.text = (data['advertising'] as String?) ?? '0';
    _acquiringController.text = (data['acquiring'] as String?) ?? '0';
    _pricingMode = PricingMode.values.where((mode) => mode.name == data['pricingMode']).firstOrNull ?? PricingMode.markup;
  }

  @override
  void dispose() {
    for (final r in _resources) {
      r.dispose();
    }
    _laborHoursController.dispose();
    _laborRateController.dispose();
    _pieceworkController.dispose();
    _overheadController.dispose();
    _overheadFixedController.dispose();
    _otherController.dispose();
    _finishedDefectController.dispose();
    _marginController.dispose();
    _targetMarginController.dispose();
    _fixedPriceController.dispose();
    _packagingController.dispose();
    _shippingController.dispose();
    _storageController.dispose();
    _returnShippingController.dispose();
    _buyoutController.dispose();
    _commissionController.dispose();
    _advertisingController.dispose();
    _acquiringController.dispose();
    final jobId = widget.jobId;
    if (jobId != null) {
      unawaited(
        Provider.of<MastersStore>(
          context,
          listen: false,
        ).flushCalculatorState(jobId),
      );
    }
    super.dispose();
  }

  double _d(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

  double _percent(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? double.nan;

  int get _materialsCents => _resources.fold(0, (sum, r) => sum + r.totalCents);

  /// Все строки имеют корректное количество и процент потерь.
  bool get _resourcesValid => _resources.every((r) => r.lossValid);

  CalculatorTotals get _totals => computeCalculatorTotals(
    materialsCents: _materialsCents,
    laborHours: _d(_laborHoursController.text),
    laborRateCents: (_d(_laborRateController.text) * 100).round(),
    pieceworkCents: (_d(_pieceworkController.text) * 100).round(),
    otherCents: (_d(_otherController.text) * 100).round(),
    overheadPercent: _d(_overheadController.text),
    overheadFixedCents: (_d(_overheadFixedController.text) * 100).round(),
    finishedDefectPercent: _percent(_finishedDefectController.text),
    marginPercent: _d(_marginController.text),
    pricingMode: _pricingMode,
    targetMarginPercent: _d(_targetMarginController.text),
    fixedPriceCents: (_d(_fixedPriceController.text) * 100).round(),
    packagingCents: (_d(_packagingController.text) * 100).round(),
    shippingCents: (_d(_shippingController.text) * 100).round(),
    storageCents: (_d(_storageController.text) * 100).round(),
    returnShippingCents: (_d(_returnShippingController.text) * 100).round(),
    buyoutPercent: _percent(_buyoutController.text),
    commissionPercent: _d(_commissionController.text),
    advertisingPercent: _d(_advertisingController.text),
    acquiringPercent: _d(_acquiringController.text),
  );

  void _markDirty() {
    setState(() {});
    final jobId = widget.jobId;
    if (jobId != null) {
      Provider.of<MastersStore>(
        context,
        listen: false,
      ).saveCalculatorState(jobId, jsonEncode(_snapshot()));
    }
  }

  Map<String, dynamic> _snapshot() => {
    'schema': 1,
    'resources': _resources.map((r) {
      return {
        'name': r.nameController.text,
        'qty': r.qtyController.text,
        'qtyUnit': r.qtyUnit,
        'price': r.priceController.text,
        'priceUnit': r.priceUnit,
        'loss': r.lossController.text,
        if (r.inventoryItemId != null) 'inventoryItemId': r.inventoryItemId,
        if (r.writeOff) 'writeOff': true,
      };
    }).toList(),
    'labor': {
      'role': 'work',
      'hours': _laborHoursController.text,
      'rate': _laborRateController.text,
    },
    'piecework': _pieceworkController.text,
    'overhead': _overheadController.text,
    'overheadFixed': _overheadFixedController.text,
    'other': _otherController.text,
    'finishedDefect': _finishedDefectController.text,
    'margin': _marginController.text,
    'pricingMode': _pricingMode.name,
    'targetMargin': _targetMarginController.text,
    'fixedPrice': _fixedPriceController.text,
    'packaging': _packagingController.text,
    'shipping': _shippingController.text,
    'storage': _storageController.text,
    'returnShipping': _returnShippingController.text,
    'buyout': _buyoutController.text,
    'commission': _commissionController.text,
    'advertising': _advertisingController.text,
    'acquiring': _acquiringController.text,
  };

  String _money(int cents) => money(cents);

  void _addResource() {
    setState(
      () => _resources.add(_ResourceLine(qtyUnit: 'шт', priceUnit: 'за шт')),
    );
    _markDirty();
  }

  void _removeResource(int index) {
    final line = _resources.removeAt(index);
    line.dispose();
    _markDirty();
  }

  Future<void> _pickOption({
    required String title,
    required List<String> items,
    required String current,
    required ValueChanged<String> onChanged,
  }) async {
    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final item in items)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(item),
              child: Text(
                item,
                style: TextStyle(
                  fontWeight: item == current
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (result != null && result != current) {
      onChanged(result);
    }
  }

  Future<void> _pickQtyUnit(_ResourceLine line) async {
    final extra = line.qtyUnit.isNotEmpty && !kQtyUnits.contains(line.qtyUnit)
        ? [line.qtyUnit]
        : const <String>[];
    await _pickOption(
      title: 'Единица количества',
      items: [...kQtyUnits, ...extra],
      current: line.qtyUnit,
      onChanged: (value) {
        setState(() {
          line.qtyUnit = value;
          final allowed = priceUnitsFor(value);
          if (!allowed.contains(line.priceUnit)) {
            line.priceUnit = defaultPriceUnit(value);
          }
        });
        _markDirty();
      },
    );
  }

  Future<void> _pickPriceUnit(_ResourceLine line) async {
    final allowed = priceUnitsFor(line.qtyUnit);
    await _pickOption(
      title: 'Цена за',
      items: allowed,
      current: line.priceUnit,
      onChanged: (value) {
        setState(() => line.priceUnit = value);
        _markDirty();
      },
    );
  }

  /// Лист выбора позиции склада с поиском и вариантом «Своя строка».
  Future<void> _openStockPicker() async {
    final store = context.read<MastersStore>();
    final items = store.inventoryItems.where((i) => !i.archived).toList();
    if (items.isEmpty) {
      await showAppAlert(
        context,
        title: 'Склад пуст',
        message:
            'Добавьте позиции на складе или создайте свою строку расчёта.',
      );
      _addResource();
      return;
    }
    final result = await showCupertinoModalPopup<Object>(
      context: context,
      builder: (sheetContext) => _StockPickerSheet(items: items),
    );
    if (result == null || !mounted) return;
    if (result is _PickedStock) {
      _applyInventoryItem(result.item);
    } else if (result == _kCustomRow) {
      _addResource();
    }
  }

  void _applyInventoryItem(InventoryItem item) {
    final existing = _resources.indexWhere(
      (r) => r.inventoryItemId == item.id,
    );
    if (existing >= 0) {
      final line = _resources[existing];
      final current = line.qty;
      line.qtyController.text = formatQty(current <= 0 ? 1 : current + 1);
      _markDirty();
      return;
    }
    final empty = _resources.indexWhere(
      (r) => r.nameController.text.trim().isEmpty && r.inventoryItemId == null,
    );
    final price = item.costCents > 0 ? item.costCents : item.sellPriceCents;
    final line = _ResourceLine(
      name: item.name,
      qty: '1',
      qtyUnit: item.unit,
      price: (price / 100).toStringAsFixed(2),
      priceUnit: defaultPriceUnit(item.unit),
      inventoryItemId: item.id,
      writeOff: item.trackStock,
    );
    if (empty >= 0) {
      _resources[empty].dispose();
      _resources[empty] = line;
    } else {
      _resources.add(line);
    }
    _markDirty();
  }

  /// «На склад»: создать позицию или обновить себестоимость существующей.
  Future<void> _saveToStock(_ResourceLine line) async {
    final name = line.nameController.text.trim();
    if (name.isEmpty) {
      await showAppAlert(context, title: 'Нет названия', message: 'Введите наименование строки.');
      return;
    }
    final store = context.read<MastersStore>();
    final total = line.totalCents;
    final existing = _lineItem(store, line);
    setState(() => _busy = true);
    try {
      if (existing != null) {
        final stockQty = line.netQtyInStockUnit(existing);
        await store.updateInventoryItem(
          existing.copyWith(
            name: name,
            costCents: line.priceCents,
            stockQty: stockQty == null
                ? existing.stockQty
                : existing.stockQty + stockQty,
          ),
        );
      } else {
        final duplicate = store.inventoryItems.where(
          (i) => i.name.trim().toLowerCase() == name.toLowerCase(),
        );
        if (duplicate.isNotEmpty) {
          final item = duplicate.first;
          await store.updateInventoryItem(
            item.copyWith(
              unit: line.qtyUnit,
              costCents: line.priceCents,
              sellPriceCents: line.priceCents,
            ),
          );
        } else {
          await store.createInventoryItem(
            name: name,
            unit: line.qtyUnit,
            sellPriceCents: line.priceCents,
            costCents: line.priceCents,
            trackStock: false,
          );
        }
      }
      HapticFeedback.lightImpact();
      if (!mounted) return;
      await showAppAlert(
        context,
        title: 'Сохранено на склад',
        message: total > 0
            ? '$name — себестоимость ${_money(line.priceCents)}.'
            : '$name — позиция создана.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Списать количество строки со склада.
  Future<void> _writeOffLine(_ResourceLine line) async {
    final store = context.read<MastersStore>();
    final item = _lineItem(store, line);
    if (item == null) return;
    if (line.effectiveQty == null) {
      await showAppAlert(
        context,
        title: 'Проверьте потери',
        message:
            'Укажите количество и процент потерь от 0 до 100% (не включая 100%).',
      );
      return;
    }
    final qty = line.qtyInStockUnit(item);
    if (qty == null || qty <= 0) {
      await showAppAlert(
        context,
        title: 'Единицы не совпадают',
        message:
            'Количество указано в «${line.qtyUnit}», а склад ведётся в «${item.unit}».',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await store.writeOffStock(
        itemId: item.id,
        qty: qty,
        note: widget.jobId == null ? 'Калькулятор' : 'Материалы заказа',
      );
      HapticFeedback.lightImpact();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Пополнить склад на количество строки по указанной цене.
  Future<void> _receiveLine(_ResourceLine line) async {
    final store = context.read<MastersStore>();
    final item = _lineItem(store, line);
    if (item == null) return;
    final qty = line.netQtyInStockUnit(item);
    if (qty == null || qty <= 0) {
      await showAppAlert(
        context,
        title: 'Единицы не совпадают',
        message:
            'Количество указано в «${line.qtyUnit}», а склад ведётся в «${item.unit}».',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await store.receiveStock(
        itemId: item.id,
        qty: qty,
        unitPriceCents: line.priceCents,
        note: 'Поступление из калькулятора',
      );
      HapticFeedback.lightImpact();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InventoryItem? _lineItem(MastersStore store, _ResourceLine line) {
    final id = line.inventoryItemId;
    if (id == null) return null;
    for (final item in store.inventoryItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _showLineActions(_ResourceLine line) async {
    final store = context.read<MastersStore>();
    final item = _lineItem(store, line);
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(
          line.nameController.text.trim().isEmpty
              ? 'Строка расчёта'
              : line.nameController.text.trim(),
        ),
        message: item == null
            ? const Text('Строка не связана с позицией склада')
            : Text('Остаток: ${formatQty(item.stockQty)} ${item.unit}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('save'),
            child: const Text('Сохранить на склад'),
          ),
          if (item != null) ...[
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('writeoff'),
              child: const Text('Списать со склада'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('receive'),
              child: const Text('Пополнить склад'),
            ),
          ],
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop('delete'),
            child: const Text('Удалить строку'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'save':
        await _saveToStock(line);
      case 'writeoff':
        await _writeOffLine(line);
      case 'receive':
        await _receiveLine(line);
      case 'delete':
        final index = _resources.indexOf(line);
        if (index >= 0) _removeResource(index);
    }
  }

  /// Переносит расчёт в заказ одной строкой и списывает помеченные материалы.
  ///
  /// Строка — услуга: посчитанная цена и себестоимость фиксируются снимком,
  /// чтобы последующая правка себестоимости на складе не переписала заказ.
  Future<void> _addToJob() async {
    final jobId = widget.jobId;
    if (jobId == null) return;
    if (!_resourcesValid) {
      await showAppAlert(
        context,
        title: 'Проверьте потери',
        message:
            'У одной из строк некорректное количество или процент потерь от 0 до 100% (не включая 100%).',
      );
      return;
    }
    final totals = _totals;
    final store = context.read<MastersStore>();
    setState(() => _busy = true);
    try {
      await store.createJobLine(
        jobId,
        kind: 'work',
        name: _resources.isEmpty
            ? 'Расчёт по калькулятору'
            : (_resources.first.nameController.text.trim().isEmpty
                  ? 'Расчёт по калькулятору'
                  : _resources.first.nameController.text.trim()),
        qty: 1,
        unit: 'услуга',
        priceCents: totals.priceCents,
        costAtOrderCents: totals.costCents,
      );
      await store.recalcJobTotals(jobId);
      for (final line in _resources.where((r) => r.writeOff)) {
        final item = _lineItem(store, line);
        if (item == null) continue;
        final qty = line.qtyInStockUnit(item);
        if (qty == null || qty <= 0) continue;
        await store.adjustStock(
          itemId: item.id,
          delta: -qty,
          type: 'writeoff',
          reason: 'order',
          refType: 'job',
          refId: jobId,
          note: 'Материалы заказа (калькулятор)',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await showAppAlert(
      context,
      title: 'Добавлено в заказ',
      message: 'Строка на ${money(totals.priceCents)} появилась в заказе.',
    );
  }

  Future<void> _apply() async {
    if (!_resourcesValid) {
      await showAppAlert(
        context,
        title: 'Проверьте потери',
        message:
            'У одной из строк некорректное количество или процент потерь от 0 до 100% (не включая 100%).',
      );
      return;
    }
    final totals = _totals;
    final store = context.read<MastersStore>();
    final stockTarget = _stockTarget;
    if (stockTarget != null) {
      setState(() => _busy = true);
      try {
        await store.updateInventoryItem(
          stockTarget.copyWith(
            costCents: totals.costCents,
            sellPriceCents: totals.priceCents > 0
                ? totals.priceCents
                : stockTarget.sellPriceCents,
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop({
          'costCents': totals.costCents,
          'priceCents': totals.priceCents,
        });
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    final toWriteOff = _resources
        .where((r) => r.writeOff && r.inventoryItemId != null)
        .toList();
    if (toWriteOff.isNotEmpty) {
      setState(() => _busy = true);
      try {
        for (final line in toWriteOff) {
          final item = _lineItem(store, line);
          if (item == null) continue;
          final qty = line.qtyInStockUnit(item);
          if (qty == null || qty <= 0) continue;
          await store.writeOffStock(
            itemId: item.id,
            qty: qty,
            note: 'Материалы заказа',
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop({
      'costCents': totals.costCents,
      'priceCents': totals.priceCents,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final store = context.watch<MastersStore>();
    final totals = _totals;
    final title = _isStockMode ? 'Себестоимость' : 'Калькулятор';

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _busy || !totals.validPrice || !_resourcesValid
              ? null
              : _apply,
          child: Text(_isStockMode ? 'Сохранить' : 'Применить'),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _SummaryCard(totals: totals),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: SectionLabel('Ресурсы и материалы')),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _openStockPicker,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(CupertinoIcons.cube_box, size: 16),
                          SizedBox(width: 6),
                          Text('Со склада', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_resources.isEmpty)
                  AppCard(
                    child: Column(
                      children: [
                        Text(
                          'Добавьте материалы со склада или свою строку.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.secondaryLabel,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'Добавить строку',
                          icon: CupertinoIcons.add,
                          onPressed: _addResource,
                        ),
                      ],
                    ),
                  )
                else
                  AppCard(
                    child: Column(
                      children: [
                        for (var i = 0; i < _resources.length; i++) ...[
                          _buildResourceRow(store, _resources[i], i),
                          if (i != _resources.length - 1) const Hairline(),
                        ],
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'Добавить строку',
                          icon: CupertinoIcons.add,
                          onPressed: _addResource,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const SectionLabel('Работа'),
                AppCard(
                  child: Column(
                    children: [
                      _NumberRow(
                        label: 'Часы',
                        controller: _laborHoursController,
                        suffix: 'ч',
                        onChanged: _markDirty,
                      ),
                      const SizedBox(height: 10),
                      _NumberRow(
                        label: 'Ставка',
                        controller: _laborRateController,
                        prefix: '${moneySymbol}',
                        suffix: '/ч',
                        onChanged: _markDirty,
                      ),
                      const SizedBox(height: 10),
                      _NumberRow(
                        label: 'Сдельная оплата',
                        controller: _pieceworkController,
                        suffix: moneySymbol,
                        onChanged: _markDirty,
                      ),
                      const SizedBox(height: 12),
                      _AmountRow(
                        label: 'Затраты на работу',
                        value: _money(totals.laborCents),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionLabel('Расходы на продажу'),
                AppCard(
                  child: Column(
                    children: [
                      _NumberRow(label: 'Упаковка', controller: _packagingController, suffix: moneySymbol, onChanged: _markDirty),
                      const SizedBox(height: 10),
                      _NumberRow(label: 'Доставка', controller: _shippingController, suffix: moneySymbol, onChanged: _markDirty),
                      const SizedBox(height: 10),
                      _NumberRow(label: 'Хранение', controller: _storageController, suffix: moneySymbol, onChanged: _markDirty),
                      const SizedBox(height: 10),
                      _NumberRow(label: 'Возвратная доставка', controller: _returnShippingController, suffix: moneySymbol, onChanged: _markDirty),
                      const SizedBox(height: 10),
                      _NumberRow(label: 'Прогноз выкупа', controller: _buyoutController, suffix: '%', onChanged: _markDirty),
                      if (!totals.buyoutValid)
                        Text(
                          'Прогноз выкупа: укажите конечное число больше 0 и не более 100%.',
                          style: TextStyle(color: colors.red),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Прогноз на одну успешную продажу: (доставка + возвратная доставка × (1 − выкуп)) / выкуп. Финансовые записи и движения склада не создаются.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.tertiaryLabel,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _NumberRow(label: 'Комиссия', controller: _commissionController, suffix: '%', onChanged: _markDirty),
                      const SizedBox(height: 10),
                      _NumberRow(label: 'Реклама', controller: _advertisingController, suffix: '%', onChanged: _markDirty),
                      const SizedBox(height: 10),
                      _NumberRow(label: 'Эквайринг', controller: _acquiringController, suffix: '%', onChanged: _markDirty),
                      const SizedBox(height: 10),
                      _AmountRow(label: 'Доставка с учётом возвратов', value: _money(totals.effectiveShippingCents)),
                      const SizedBox(height: 8),
                      _AmountRow(label: 'Итого расходы на продажу', value: _money(totals.sellingCostCents)),
                      const SizedBox(height: 8),
                      const Text('Оценка на единицу. Комиссия, реклама и эквайринг рассчитываются от цены продажи.'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionLabel('Накладные и цена'),
                AppCard(
                  child: Column(
                    children: [
                      _NumberRow(
                        label: 'Прочие расходы',
                        controller: _otherController,
                        prefix: '${moneySymbol}',
                        onChanged: _markDirty,
                      ),
                      const SizedBox(height: 10),
                      _NumberRow(
                        label: 'Накладные',
                        controller: _overheadController,
                        suffix: '%',
                        onChanged: _markDirty,
                      ),
                      const SizedBox(height: 10),
                      _NumberRow(
                        label: 'Накладные на единицу',
                        controller: _overheadFixedController,
                        prefix: '$moneySymbol',
                        onChanged: _markDirty,
                      ),
                      const SizedBox(height: 10),
                      _NumberRow(
                        label: 'Брак готовых изделий',
                        controller: _finishedDefectController,
                        suffix: '%',
                        onChanged: _markDirty,
                      ),
                      if (!totals.finishedDefectValid)
                        const Text('Укажите процент брака от 0 до 100%, не включая 100%.'),
                      const SizedBox(height: 10),
                      _AmountRow(label: 'Затраты из-за брака', value: _money(totals.finishedDefectCents)),
                      const SizedBox(height: 10),
                      CupertinoSlidingSegmentedControl<PricingMode>(
                        groupValue: _pricingMode,
                        children: const {
                          PricingMode.markup: Text('Наценка'),
                          PricingMode.targetMargin: Text('Маржа'),
                          PricingMode.fixedPrice: Text('Цена'),
                        },
                        onValueChanged: (mode) {
                          if (mode == null) return;
                          _pricingMode = mode;
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: 10),
                      _NumberRow(
                        label: switch (_pricingMode) {
                          PricingMode.markup => 'Наценка к себестоимости',
                          PricingMode.targetMargin => 'Доля прибыли в цене',
                          PricingMode.fixedPrice => 'Цена продажи',
                        },
                        controller: switch (_pricingMode) {
                          PricingMode.markup => _marginController,
                          PricingMode.targetMargin => _targetMarginController,
                          PricingMode.fixedPrice => _fixedPriceController,
                        },
                        suffix: _pricingMode == PricingMode.fixedPrice ? moneySymbol : '%',
                        onChanged: _markDirty,
                      ),
                      if (!totals.validPrice &&
                          totals.finishedDefectValid &&
                          totals.buyoutValid)
                        const Text('Сумма процентов расходов и целевой маржи должна быть меньше 100%.'),
                      const SizedBox(height: 14),
                      _AmountRow(
                        label: 'Производственная себестоимость',
                        value: _money(totals.productionCostCents),
                      ),
                      const SizedBox(height: 6),
                      _AmountRow(
                        label: 'Затраты с продажей',
                        value: _money(totals.costCents),
                      ),
                      const SizedBox(height: 6),
                      _AmountRow(
                        label: 'Цена',
                        value: _money(totals.priceCents),
                        strong: true,
                      ),
                      const SizedBox(height: 6),
                      _AmountRow(
                        label: 'Безубыточная цена',
                        value: totals.breakEvenCents == null
                            ? '—'
                            : _money(totals.breakEvenCents!),
                      ),
                      const SizedBox(height: 6),
                      _AmountRow(
                        label: 'ROI',
                        value: totals.roiPercent == null
                            ? '—'
                            : '${totals.roiPercent!.toStringAsFixed(1)}%',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.jobId != null) ...[
                  SecondaryButton(
                    label: 'Добавить в заказ строкой',
                    icon: CupertinoIcons.plus_circle,
                    onPressed: _busy || !totals.validPrice || !_resourcesValid
                        ? null
                        : _addToJob,
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  _isStockMode
                      ? 'Сохранение запишет себестоимость и цену в позицию склада.'
                      : 'Материалы со включённой отметкой спишутся со склада при применении.',
                  style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CupertinoActivityIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceRow(MastersStore store, _ResourceLine line, int index) {
    final colors = context.colors;
    final item = _lineItem(store, line);
    final remainder = item == null
        ? null
        : 'Остаток: ${formatQty(item.stockQty)} ${item.unit}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: line.nameController,
                  placeholder: 'Наименование',
                  onChanged: (_) => _markDirty(),
                ),
              ),
              const SizedBox(width: 6),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showLineActions(line),
                child: Icon(
                  CupertinoIcons.ellipsis_circle,
                  size: 22,
                  color: colors.secondaryLabel,
                  semanticLabel: 'Действия со строкой',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: CupertinoTextField(
                  controller: line.qtyController,
                  placeholder: 'Кол-во',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: CupertinoTextField(
                  controller: line.priceController,
                  placeholder: 'Цена',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${moneySymbol}', style: TextStyle(color: colors.secondaryLabel)),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              'Потери %',
              style: TextStyle(
                fontSize: 12,
                color: colors.secondaryLabel,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: CupertinoTextField(
                  controller: line.lossController,
                  placeholder: 'Потери, %',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    line.lossValid
                        ? 'С учётом потерь: ${formatQty(line.effectiveQty!)} ${line.qtyUnit}'
                        : 'Укажите количество и потери от 0 до 100% (без 100%).',
                    style: TextStyle(
                      fontSize: 12,
                      color: line.lossValid ? colors.tertiaryLabel : colors.red,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _unitChip(
                text: line.qtyUnit,
                onTap: () => _pickQtyUnit(line),
              ),
              const SizedBox(width: 6),
              _unitChip(
                text: line.priceUnit,
                onTap: () => _pickPriceUnit(line),
              ),
              const Spacer(),
              Text(
                _money(line.totalCents),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (remainder != null || item != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (remainder != null)
                  Text(
                    remainder,
                    style: TextStyle(
                      color: item != null && item.lowStock
                          ? colors.orange
                          : colors.tertiaryLabel,
                      fontSize: 12,
                    ),
                  ),
                const Spacer(),
                if (item != null)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() => line.writeOff = !line.writeOff);
                      _markDirty();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          line.writeOff
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          size: 16,
                          color: line.writeOff
                              ? colors.accent
                              : colors.tertiaryLabel,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Списать',
                          style: TextStyle(
                            fontSize: 12,
                            color: line.writeOff
                                ? colors.accent
                                : colors.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (item == null)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _removeResource(index),
                    child: Icon(
                      CupertinoIcons.xmark,
                      size: 16,
                      color: colors.tertiaryLabel,
                      semanticLabel: 'Удалить',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _unitChip({required String text, required VoidCallback onTap}) {
    final colors = context.colors;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colors.cardElevated,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(width: 3),
            Icon(
              CupertinoIcons.chevron_down,
              size: 11,
              color: colors.secondaryLabel,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals});

  final CalculatorTotals totals;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: _SummaryValue(
              label: 'Затраты всего',
              value: money(totals.costCents),
              color: colors.label,
            ),
          ),
          Container(width: 0.5, height: 34, color: colors.separator),
          Expanded(
            child: _SummaryValue(
              label: 'Цена',
              value: money(totals.priceCents),
              color: colors.accent,
            ),
          ),
          Container(width: 0.5, height: 34, color: colors.separator),
          Expanded(
            child: _SummaryValue(
              label: 'Маржа',
              value: money(totals.marginCents),
              color: totals.marginCents >= 0 ? colors.green : colors.red,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.colors.secondaryLabel,
          ),
        ),
      ],
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.prefix,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: colors.secondaryLabel, fontSize: 15),
          ),
        ),
        SizedBox(
          width: 132,
          child: CupertinoTextField(
            controller: controller,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: prefix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      prefix!,
                      style: TextStyle(color: colors.secondaryLabel),
                    ),
                  ),
            suffix: suffix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      suffix!,
                      style: TextStyle(color: colors.secondaryLabel),
                    ),
                  ),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: strong ? 17 : 14,
            color: strong ? colors.accent : colors.label,
          ),
        ),
      ],
    );
  }
}

/// Лист выбора позиции склада: поиск по названию, остаток и цена.
class _StockPickerSheet extends StatefulWidget {
  const _StockPickerSheet({required this.items});

  final List<InventoryItem> items;

  @override
  State<_StockPickerSheet> createState() => _StockPickerSheetState();
}

class _StockPickerSheetState extends State<_StockPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<InventoryItem> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items
        .where(
          (i) =>
              i.name.toLowerCase().contains(q) ||
              i.category.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = _filtered;
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            const SheetHandle(),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Позиции склада',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Закрыть'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Поиск по названию',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'Ничего не найдено',
                        style: TextStyle(color: colors.secondaryLabel),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Hairline(),
                      itemBuilder: (_, index) {
                        final item = items[index];
                        final price = item.costCents > 0
                            ? item.costCents
                            : item.sellPriceCents;
                        return CupertinoListTile(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          title: Text(item.name),
                          subtitle: Text(
                            item.trackStock
                                ? 'Остаток: ${formatQty(item.stockQty)} ${item.unit}'
                                : 'Без учёта остатка',
                            style: TextStyle(
                              fontSize: 12,
                              color: item.lowStock
                                  ? colors.orange
                                  : colors.secondaryLabel,
                            ),
                          ),
                          trailing: Text(
                            '${money(price)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () =>
                              Navigator.of(context).pop(_PickedStock(item)),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SecondaryButton(
                label: 'Своя строка',
                icon: CupertinoIcons.add,
                onPressed: () => Navigator.of(context).pop(_kCustomRow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
