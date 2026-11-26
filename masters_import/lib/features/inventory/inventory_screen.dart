import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../app/ui.dart';
import '../../core/units.dart';
import '../../core/utils/app_utils.dart';
import '../../data/models/inventory_composition.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/supplier.dart';
import '../../state/masters_store.dart';
import '../catalog/catalog_screen.dart';
import '../jobs/cost_calculator_screen.dart';
import 'inventory_composition_screen.dart';
import 'locations_screen.dart';
import 'purchase_receipt_screen.dart';
import 'stock_transfer_screen.dart';
import '../../core/money_format.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  bool _busy = false;
  final _searchController = TextEditingController();
  String _invQuery = '';
  String _invFilter = 'all';

  Future<String?> _prompt(
    String title,
    String placeholder, {
    String? initial,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    return showCupertinoDialog<String?>(
      context: context,
      builder: (dc) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            textCapitalization: textCapitalization,
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

  Future<void> _showSearch() async {
    _searchController.text = _invQuery;
    if (!mounted) return;
    final result = await showCupertinoDialog<String?>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Поиск'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: _searchController,
            placeholder: 'Поиск по складу',
            autofocus: true,
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(_searchController.text.trim()),
            decoration: BoxDecoration(
              color: context.colors.card,
              border: Border.all(color: context.colors.separator),
              borderRadius: BorderRadius.circular(8),
            ),
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
                Navigator.of(dialogContext).pop(_searchController.text.trim()),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _invQuery = result);
  }

  List<InventoryItem> _filteredInventory(MastersStore store) {
    var list = store.inventoryItems.where((i) => !i.archived).toList();
    final q = _invQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (i) =>
                i.name.toLowerCase().contains(q) ||
                i.unit.toLowerCase().contains(q) ||
                i.category.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_invFilter == 'good') {
      list = list.where((i) => i.kind == 'good').toList();
    }
    if (_invFilter == 'service') {
      list = list.where((i) => i.kind == 'service').toList();
    }
    if (_invFilter == 'low') {
      list = list.where((i) => i.lowStock).toList();
    }
    return list;
  }

  Future<void> _pickInventoryFilter() async {
    final v = await showCupertinoModalPopup<String>(
      context: context,
      builder: (dialogContext) => CupertinoActionSheet(
        title: const Text('Фильтр склада'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('all'),
            child: const Text('Все позиции'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('good'),
            child: const Text('Только товары'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('service'),
            child: const Text('Только услуги'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(dialogContext).pop('low'),
            child: const Text('Мало на складе'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (v != null) setState(() => _invFilter = v);
  }

  Future<void> _newItem() async {
    final draft = await showCupertinoModalPopup<InventoryItem>(
      context: context,
      builder: (_) => _ItemEditorSheet(),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<MastersStore>().createInventoryItem(
        name: draft.name,
        kind: draft.kind,
        unit: draft.unit,
        sellPriceCents: draft.sellPriceCents,
        costCents: draft.costCents,
        trackStock: draft.trackStock,
        minQty: draft.minQty,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receiveStock(InventoryItem item) async {
    final qtyStr = await _prompt('Поступление, кол-во (${item.unit})', '1');
    final qty = double.tryParse((qtyStr ?? '').replaceAll(',', '.'));
    if (qty == null || qty <= 0) return;
    final costStr =
        await _prompt(
          'Цена за ед. (${moneySymbol})',
          (item.costCents / 100).toStringAsFixed(0),
        ) ??
        '0';
    final unitPriceCents =
        ((double.tryParse(costStr.trim().replaceAll(',', '.')) ?? 0) * 100)
            .round();
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<MastersStore>().receiveStock(
        itemId: item.id,
        qty: qty,
        unitPriceCents: unitPriceCents,
        note: 'Закупка',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeOff(InventoryItem item) async {
    final qtyStr = await _prompt('Списание, кол-во (${item.unit})', '1');
    final qty = double.tryParse((qtyStr ?? '').replaceAll(',', '.'));
    if (qty == null || qty <= 0) return;
    final reason = await _prompt('Причина', 'Брак/списание') ?? 'Списание';
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<MastersStore>().writeOffStock(
        itemId: item.id,
        qty: qty,
        note: reason,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importInventoryExcel() async {
    setState(() => _busy = true);
    try {
      final count = await context
          .read<MastersStore>()
          .importInventoryFromExcel();
      if (!mounted) return;
      await showAppAlert(
        context,
        title: count > 0 ? 'Импорт завершён' : 'Импорт',
        message: count > 0 ? 'Добавлено товаров/услуг: $count.' : 'Не удалось добавить записи. Нужен столбец name; проверьте файл Excel.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newSupplier() async {
    final name = await _prompt('Имя поставщика', 'ООО Поставщик');
    if (name == null || name.trim().isEmpty) return;
    final phone = await _prompt('Телефон', '') ?? '';
    if (!mounted) return;
    await context.read<MastersStore>().createSupplier(
      name: name.trim(),
      phone: phone.trim(),
    );
  }

  Future<void> _recordPurchase() async {
    final store = context.read<MastersStore>();
    if (store.suppliers.isEmpty) {
      await showAppAlert(
        context,
        title: 'Нет поставщиков',
        message: 'Сначала добавьте поставщика.',
      );
      return;
    }
    final supplierId = await _pickSupplier(store);
    if (supplierId == null || !mounted) return;
    final itemId = await _pickInventoryItem(store);
    if (itemId == null || !mounted) return;
    final qtyStr = await _prompt('Количество', '1');
    final qty = double.tryParse((qtyStr ?? '').trim().replaceAll(',', '.'));
    if (qty == null || qty <= 0 || !mounted) return;
    final priceStr = await _prompt('Цена за ед.', '0');
    final price =
        ((double.tryParse((priceStr ?? '0').replaceAll(',', '.')) ?? 0) * 100)
            .round();
    if (price <= 0 || !mounted) return;
    final note = await _prompt('Комментарий', '');
    if (!mounted) return;
    final accountId = await _pickAccount(store);
    if (accountId == null || !mounted) return;
    final paidStr = await _prompt('Оплачено сейчас (0 = долг)', '0');
    final paid =
        ((double.tryParse((paidStr ?? '0').replaceAll(',', '.')) ?? 0) * 100)
            .round();
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await store.createPurchase(
        supplierId: supplierId,
        accountId: paid > 0 ? accountId : null,
        paidCents: paid,
        note: note,
        lines: [
          {'itemId': itemId, 'qty': qty, 'unitPriceCents': price},
        ],
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSupplierDetail(Supplier supplier) async {
    final store = context.read<MastersStore>();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        color: context.colors.card,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                supplier.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Долг: ${_money(store.supplierDebtCents(supplier.id))}',
                style: TextStyle(color: context.colors.secondaryLabel),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final purchase in store.purchasesForSupplier(
                      supplier.id,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '#${purchase.id.substring(0, 6)} · ${_money(purchase.totalCents)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () async {
                                  Navigator.of(modalContext).pop();
                                  await _paySupplier(supplier);
                                },
                                child: const Text(
                                  'Оплатить',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (store.purchasesForSupplier(supplier.id).isEmpty)
                      EmptyState(
                        title: 'Нет закупок',
                        message: 'Запишите первую закупку для поставщика.',
                      ),
                  ],
                ),
              ),
              SecondaryButton(
                label: 'Закрыть',
                icon: CupertinoIcons.xmark,
                onPressed: () => Navigator.of(modalContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _paySupplier(Supplier supplier) async {
    final store = context.read<MastersStore>();
    if (store.accounts.isEmpty) {
      await showAppAlert(
        context,
        title: 'Нет счёта',
        message: 'Сначала создайте счёт в разделе Деньги.',
      );
      return;
    }
    final purchases = store.purchasesForSupplier(supplier.id);
    String? selectedPurchaseId;
    if (purchases.length == 1) {
      selectedPurchaseId = purchases.first.id;
    } else if (purchases.length > 1) {
      selectedPurchaseId = await showCupertinoModalPopup<String?>(
        context: context,
        builder: (ctx) => Container(
          height: 260,
          color: context.colors.card,
          child: ListView(
            children: [
              CupertinoButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Общая оплата (без привязки)'),
              ),
              for (final purchase in purchases)
                CupertinoButton(
                  onPressed: () => Navigator.of(ctx).pop(purchase.id),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Закупка ${purchase.id.substring(0, 6)} · ${_money(purchase.totalCents)}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final amountStr = await _prompt('Сумма оплаты', '0');
    final amount =
        ((double.tryParse((amountStr ?? '').replaceAll(',', '.')) ?? 0) * 100)
            .round();
    if (amount <= 0 || !mounted) return;
    final accountId = await _pickAccount(store);
    if (accountId == null || !mounted) return;
    final note = await _prompt('Комментарий', '') ?? '';
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final supplierPurchases = store.purchasesForSupplier(supplier.id);
      final purchaseId =
          selectedPurchaseId ??
          (supplierPurchases.isEmpty ? null : supplierPurchases.first.id);
      await store.paySupplier(
        supplierId: supplier.id,
        amountCents: amount,
        accountId: accountId,
        purchaseId: purchaseId,
        note: note.trim().isEmpty ? null : note.trim(),
      );
      if (mounted) {
        await showAppAlert(
          context,
          title: 'Готово',
          message: 'Оплата поставщику проведена.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final ok = await showAppConfirm(
      context,
      title: 'Удалить поставщика?',
      message: supplier.name,
      destructive: true,
      confirmLabel: 'Удалить',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<MastersStore>().deleteSupplier(supplier.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickSupplier(MastersStore store) async {
    final suppliers = store.suppliers;
    if (suppliers.isEmpty) return null;
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 220,
        color: context.colors.card,
        child: ListView(
          children: [
            for (final supplier in suppliers)
              CupertinoButton(
                onPressed: () => Navigator.of(ctx).pop(supplier.id),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(supplier.name),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickInventoryItem(MastersStore store) async {
    final items = store.inventoryItems.where((i) => !i.archived).toList();
    if (items.isEmpty) return null;
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 220,
        color: context.colors.card,
        child: ListView(
          children: [
            for (final item in items)
              CupertinoButton(
                onPressed: () => Navigator.of(ctx).pop(item.id),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(item.name),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickAccount(MastersStore store) async {
    final accounts = store.accounts.where((a) => !a.archived).toList();
    if (accounts.isEmpty) return null;
    return showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) => Container(
        height: 220,
        color: context.colors.card,
        child: ListView(
          children: [
            for (final account in accounts)
              CupertinoButton(
                onPressed: () => Navigator.of(ctx).pop(account.id),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(account.name),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openLocations() {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const LocationsScreen()),
    );
  }

  void _openTransfer() {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const StockTransferScreen()),
    );
  }

  void _openReceipt({String? purchaseId}) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => PurchaseReceiptScreen(purchaseId: purchaseId),
      ),
    );
  }

  String _money(int cents) => money(cents);

  Future<void> _delete(InventoryItem item) async {
    final ok = await showAppConfirm(
      context,
      title: 'Удалить позицию?',
      message: item.name,
      destructive: true,
      confirmLabel: 'Удалить',
    );
    if (!ok) return;
    if (!mounted) return;
    await context.read<MastersStore>().deleteInventoryItem(item.id);
  }

  Future<void> _editItem(InventoryItem item) async {
    final edited = await showCupertinoModalPopup<InventoryItem>(
      context: context,
      builder: (_) => _ItemEditorSheet(item: item),
    );
    if (edited == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<MastersStore>().updateInventoryItem(edited);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Карточка позиции: быстрые операции в одном листе вместо цепочки диалогов.
  Future<void> _showItemSheet(InventoryItem item) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(item.name),
        message: Text(
          [
            '${item.kind == 'service' ? 'Услуга' : 'Товар'} · ${item.unit}',
            if (item.trackStock)
              'Остаток: ${formatQty(item.stockQty)} ${item.unit}',
            'Себестоимость: ${_money(item.costCents)} · '
                'продажа: ${_money(item.sellPriceCents)}',
          ].join('\n'),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('edit'),
            child: const Text('Редактировать'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('calculator'),
            child: const Text('Рассчитать себестоимость'),
          ),
          if (item.trackStock) ...[
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('receive'),
              child: const Text('Поступление'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop('writeoff'),
              child: const Text('Списание'),
            ),
          ],
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('history'),
            child: const Text('История движений'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop('composition'),
            child: const Text('Состав стоимости'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop('delete'),
            child: const Text('Удалить позицию'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _editItem(item);
      case 'calculator':
        await _openCalculator(item);
      case 'receive':
        await _receiveStock(item);
      case 'writeoff':
        await _writeOff(item);
      case 'history':
        await _showItemHistory(item);
      case 'composition':
        _openComposition(item);
      case 'delete':
        await _delete(item);
    }
  }

  /// Единый калькулятор в режиме склада: результат пишется в позицию.
  Future<void> _openCalculator(InventoryItem item) async {
    await Navigator.of(context).push<Map<String, int>>(
      CupertinoPageRoute(
        builder: (_) => CostCalculatorScreen(inventoryItemId: item.id),
      ),
    );
  }

  void _openComposition(InventoryItem item) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => InventoryCompositionScreen(itemId: item.id),
      ),
    );
  }

  /// Компактный блок «Состав стоимости» под ценой: список строк
  /// (компонент × кол-во — сумма строки) и итог. Скрыт, если состава нет.
  List<Widget> _compositionBlock(MastersStore store, InventoryItem item) {
    final colors = context.colors;
    final lines = store.itemComposition(item.id);
    return [
      Text(
        'Состав стоимости',
        style: TextStyle(
          color: colors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      for (final line in lines)
        Text(
          _compositionLineLabel(store, line),
          style: TextStyle(color: colors.secondaryLabel, fontSize: 11),
        ),
      Text(
        'Итого: ${_money(store.compositionCostCents(item.id))}',
        style: TextStyle(
          color: colors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }

  /// Строка вида «Доска × 2 — 200 ₽» или «Ручной труд: сборка × 1 — 500 ₽».
  String _compositionLineLabel(
    MastersStore store,
    InventoryCompositionLine line,
  ) {
    final qty = line.qty % 1 == 0
        ? line.qty.toInt().toString()
        : line.qty.toString();
    String name;
    if (line.isLabor || line.componentId == null) {
      final note = line.note;
      name = (note == null || note.isEmpty)
          ? 'Ручной труд'
          : 'Ручной труд: $note';
    } else {
      name = 'Товар удалён';
      for (final i in store.inventoryItems) {
        if (i.id == line.componentId) {
          name = i.name;
          break;
        }
      }
    }
    return '$name × $qty — ${_money(line.totalCents)}';
  }

  Future<void> _showItemHistory(InventoryItem item) async {
    final store = context.read<MastersStore>();
    final movements =
        store.stockMovements.where((m) => m.itemId == item.id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (modalContext) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        color: context.colors.card,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\u0418\u0441\u0442\u043e\u0440\u0438\u044f \u0434\u0432\u0438\u0436\u0435\u043d\u0438\u0439',
                style: TextStyle(color: context.colors.secondaryLabel),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: movements.isEmpty
                    ? EmptyState(
                        title: '\u041d\u0435\u0442 \u0434\u0432\u0438\u0436\u0435\u043d\u0438\u0439',
                        message: '\u041f\u043e\u0441\u0442\u0443\u043f\u043b\u0435\u043d\u0438\u044f \u0438 \u0441\u043f\u0438\u0441\u0430\u043d\u0438\u044f \u043f\u043e\u044f\u0432\u044f\u0442\u0441\u044f \u0437\u0434\u0435\u0441\u044c \u043f\u043e\u0441\u043b\u0435 \u043e\u043f\u0435\u0440\u0430\u0446\u0438\u0439.',
                      )
                    : ListView(
                        children: movements.map((movement) {
                          String typeLabel(String type) {
                            switch (type) {
                              case 'in':
                                return '\u041f\u043e\u0441\u0442\u0443\u043f\u043b\u0435\u043d\u0438\u0435';
                              case 'out':
                                return '\u0420\u0430\u0441\u0445\u043e\u0434';
                              case 'writeoff':
                                return '\u0421\u043f\u0438\u0441\u0430\u043d\u0438\u0435';
                              case 'adjust':
                                return '\u041a\u043e\u0440\u0440\u0435\u043a\u0442\u0438\u0440\u043e\u0432\u043a\u0430';
                              default:
                                return type;
                            }
                          }

                          final signed =
                              (movement.type == 'in' ||
                                  movement.type == 'adjust')
                              ? movement.qty
                              : -movement.qty;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${typeLabel(movement.type)}${movement.note == null || movement.note!.trim().isEmpty ? '' : ' \u00b7 ${movement.note}'}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat(
                                            'dd.MM.yyyy HH:mm',
                                            'ru',
                                          ).format(movement.createdAt),
                                          style: TextStyle(
                                            color:
                                                context.colors.secondaryLabel,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${signed >= 0 ? '+' : ''}${signed.abs().toStringAsFixed(signed.abs() % 1 == 0 ? 0 : 2)} ${item.unit}',
                                    style: TextStyle(
                                      color: signed >= 0
                                          ? context.colors.label
                                          : context.colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
              SecondaryButton(
                label: '\u0417\u0430\u043a\u0440\u044b\u0442\u044c',
                icon: CupertinoIcons.xmark,
                onPressed: () => Navigator.of(modalContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MastersStore>();
    final colors = context.colors;
    final low = store.lowStockItems();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Склад'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OverflowMenuButton(
              title: 'Склад',
              actions: [
                if (store.locationsEnabled)
                  CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openLocations();
                    },
                    child: const Text('Точки и остатки'),
                  ),
                if (store.locationsEnabled)
                  CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openTransfer();
                    },
                    child: const Text('Перемещение между точками'),
                  ),
                if (store.locationsEnabled)
                  CupertinoActionSheetAction(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openReceipt();
                    },
                    child: const Text('Приёмка закупки'),
                  ),
                CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const CatalogScreen(),
                      ),
                    );
                  },
                  child: const Text('Каталог и услуги'),
                ),
                CupertinoActionSheetAction(
                  onPressed: _recordPurchase,
                  child: const Text('Записать закупку'),
                ),
                CupertinoActionSheetAction(
                  onPressed: _newSupplier,
                  child: const Text('Новый поставщик'),
                ),
                CupertinoActionSheetAction(
                  onPressed: _importInventoryExcel,
                  child: const Text('Импорт из Excel'),
                ),
              ],
            ),
            const SizedBox(width: 4),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(34, 34),
              onPressed: _newItem,
              child: const Icon(
                CupertinoIcons.plus,
                semanticLabel: 'Новая позиция',
              ),
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
                  if (store.locationsEnabled) ...[
                    _locationsEntry(store, colors),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: SectionLabel(
                          'Поставщики · ${store.suppliers.length}',
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                        ),
                      ),
                      ChipButton(
                        label: 'Закупка',
                        icon: CupertinoIcons.doc_on_clipboard,
                        onPressed: _recordPurchase,
                      ),
                      const SizedBox(width: 8),
                      ChipButton(
                        label: 'Добавить',
                        icon: CupertinoIcons.person_badge_plus,
                        onPressed: _newSupplier,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (store.suppliers.isEmpty)
                    EmptyState(
                      title: 'Нет поставщиков',
                      message:
                          'Добавьте поставщика, чтобы учитывать закупки и долги.',
                      art: Icon(
                        CupertinoIcons.person_2,
                        size: 36,
                        color: colors.tertiaryLabel,
                      ),
                    )
                  else
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < store.suppliers.length; i++) ...[
                            if (i > 0) const Hairline(indent: 12),
                            _supplierRow(store, colors, store.suppliers[i]),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (low.isNotEmpty) ...[
                    SectionLabel('Низкий остаток · ${low.length}'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < low.length; i++) ...[
                            if (i > 0) const Hairline(indent: 12),
                            ListRow(
                              title: low[i].name,
                              subtitle:
                                  'Минимум ${formatQty(low[i].minQty)} '
                                  '${low[i].unit}',
                              icon: CupertinoIcons.cube,
                              iconColor: colors.red,
                              dense: true,
                              trailing: Text(
                                '${formatQty(low[i].stockQty)} ${low[i].unit}',
                                style: TextStyle(
                                  color: colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _invQuery.isEmpty
                              ? '${_filteredInventory(store).length} '
                                    '${itemsWord(_filteredInventory(store).length)} · '
                                    'себестоимость ${_money(store.inventoryItems.fold<int>(0, (sum, i) => sum + (i.trackStock ? (i.costCents * i.stockQty).round() : 0)))}'
                              : 'Поиск: $_invQuery',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.secondaryLabel,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_invQuery.isNotEmpty)
                        ChipButton(
                          label: 'Сбросить',
                          icon: CupertinoIcons.xmark,
                          onPressed: () => setState(() {
                            _invQuery = '';
                            _searchController.clear();
                          }),
                        )
                      else
                        ChipButton(
                          label: 'Поиск',
                          icon: CupertinoIcons.search,
                          onPressed: _showSearch,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChipButton(
                        label: switch (_invFilter) {
                          'good' => 'Товары',
                          'service' => 'Услуги',
                          'low' => 'Мало',
                          _ => 'Все позиции',
                        },
                        icon: CupertinoIcons.line_horizontal_3_decrease,
                        onPressed: _pickInventoryFilter,
                      ),
                      ChipButton(
                        label: 'Импорт Excel',
                        icon: CupertinoIcons.doc_on_doc,
                        onPressed: _importInventoryExcel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (store.inventoryItems.isEmpty)
                    EmptyState(
                      title: 'Нет позиций',
                      message: 'Добавьте товар или услугу.',
                      art: Icon(
                        CupertinoIcons.cube,
                        size: 48,
                        color: colors.tertiaryLabel,
                      ),
                      actions: [
                        PrimaryButton(
                          label: 'Добавить позицию',
                          icon: CupertinoIcons.plus,
                          onPressed: _newItem,
                        ),
                      ],
                    )
                  else if (_filteredInventory(store).isEmpty)
                    EmptyState(
                      title: 'Ничего не найдено',
                      message: _invQuery.isEmpty
                          ? 'В этом фильтре нет позиций. Смените фильтр.'
                          : 'По запросу «$_invQuery» позиций нет.',
                      art: Icon(
                        CupertinoIcons.search,
                        size: 48,
                        color: colors.tertiaryLabel,
                      ),
                      actions: [
                        SecondaryButton(
                          label: 'Сбросить фильтры',
                          icon: CupertinoIcons.xmark,
                          onPressed: () => setState(() {
                            _invQuery = '';
                            _invFilter = 'all';
                            _searchController.clear();
                          }),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: _filteredInventory(store).map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                            onTap: () => _showItemSheet(item),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${item.kind == 'service' ? 'Услуга' : 'Товар'} · '
                                        '${_money(item.costCents)} → '
                                        '${_money(item.sellPriceCents)}',
                                        style: TextStyle(
                                          color: colors.secondaryLabel,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      if (item.trackStock)
                                        Text(
                                          'Остаток ${formatQty(item.stockQty)} ${item.unit}'
                                          '${item.stockQty < 0 ? ' · отрицательный' : (item.lowStock ? ' · мало' : '')}',
                                          style: TextStyle(
                                            color:
                                                item.stockQty < 0 ||
                                                    item.lowStock
                                                ? colors.red
                                                : colors.secondaryLabel,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      if (store
                                          .itemComposition(item.id)
                                          .isNotEmpty)
                                        ..._compositionBlock(store, item),
                                    ],
                                  ),
                                ),
                                CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(32, 32),
                                  onPressed: () => _openCalculator(item),
                                  child: Icon(
                                    CupertinoIcons.function,
                                    size: 18,
                                    color: colors.accent,
                                    semanticLabel: 'Калькулятор',
                                  ),
                                ),
                                CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(32, 32),
                                  onPressed: () => _showItemSheet(item),
                                  child: Icon(
                                    CupertinoIcons.ellipsis_circle,
                                    size: 19,
                                    color: colors.secondaryLabel,
                                    semanticLabel: 'Действия',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
    );
  }

  /// Блок «Точки» под флагом `module_locations`: сводка по остаткам,
  /// истекающим партиям и перемещениям одним входом, чтобы не раздувать
  /// список склада.
  Widget _locationsEntry(MastersStore store, AppColors colors) {
    final expiring = store.expiringBatches();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: _openLocations,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.location_circle, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Точки · ${store.locations.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 16, color: colors.tertiaryLabel),
            ],
          ),
          if (expiring.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Истекают или истекли партии: ${expiring.length}',
              style: TextStyle(color: colors.orange, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChipButton(
                label: 'Перемещение',
                icon: CupertinoIcons.arrow_left_right,
                onPressed: _openTransfer,
              ),
              ChipButton(
                label: 'Приёмка',
                icon: CupertinoIcons.square_arrow_down,
                onPressed: _openReceipt,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _supplierRow(
    MastersStore store,
    AppColors colors,
    Supplier supplier,
  ) {
    final debt = store.supplierDebtCents(supplier.id);
    return ListRow(
      title: supplier.name,
      subtitle: debt > 0 ? 'Долг ${_money(debt)}' : 'Без долга',
      subtitleColor: debt > 0 ? colors.orange : null,
      icon: CupertinoIcons.person_2,
      dense: true,
      trailing: OverflowMenuButton(
        size: 18,
        title: supplier.name,
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => _paySupplier(supplier),
            child: const Text('Оплатить'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => _showSupplierDetail(supplier),
            child: const Text('История закупок'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => _deleteSupplier(supplier),
            child: const Text('Удалить'),
          ),
        ],
      ),
      onTap: () => _showSupplierDetail(supplier),
    );
  }
}

/// Лист создания/редактирования позиции склада: все поля сразу,
/// без цепочки отдельных диалогов. Возвращает готовый [InventoryItem].
class _ItemEditorSheet extends StatefulWidget {
  const _ItemEditorSheet({this.item});

  final InventoryItem? item;

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _sell;
  late final TextEditingController _cost;
  late final TextEditingController _min;
  late String _unit;
  late String _kind;
  late bool _trackStock;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _sell = TextEditingController(
      text: ((item?.sellPriceCents ?? 0) / 100).toStringAsFixed(
        (item?.sellPriceCents ?? 0) % 100 == 0 ? 0 : 2,
      ),
    );
    _cost = TextEditingController(
      text: ((item?.costCents ?? 0) / 100).toStringAsFixed(
        (item?.costCents ?? 0) % 100 == 0 ? 0 : 2,
      ),
    );
    _min = TextEditingController(
      text: formatQty(item?.minQty ?? 0),
    );
    _unit = item?.unit ?? 'шт';
    _kind = item?.kind ?? 'good';
    _trackStock = item?.trackStock ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _sell.dispose();
    _cost.dispose();
    _min.dispose();
    super.dispose();
  }

  double _parse(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

  int _cents(String value) => (_parse(value) * 100).round();

  Future<void> _pickUnit() async {
    final extra = kUnitOptions.contains(_unit) ? null : _unit;
    final unit = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Единица измерения'),
        actions: [
          for (final option in [...kUnitOptions, ?extra])
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(sheetContext).pop(option),
              child: Text(
                option,
                style: TextStyle(
                  fontWeight: option == _unit
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
    if (unit != null) setState(() => _unit = unit);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    final base = widget.item;
    final result = base == null
        ? InventoryItem(
            id: '',
            name: name,
            kind: _kind,
            unit: _unit,
            sellPriceCents: _cents(_sell.text),
            costCents: _cents(_cost.text),
            trackStock: _trackStock,
            minQty: _parse(_min.text),
            createdAt: now,
            updatedAt: now,
          )
        : base.copyWith(
            name: name,
            kind: _kind,
            unit: _unit,
            sellPriceCents: _cents(_sell.text),
            costCents: _cents(_cost.text),
            trackStock: _trackStock,
            minQty: _parse(_min.text),
          );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canSave = _name.text.trim().isNotEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Позиция' : 'Новая позиция',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: canSave ? _submit : null,
                    child: Text(
                      _isEdit ? 'Сохранить' : 'Добавить',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: canSave ? colors.accent : colors.tertiaryLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  AppCard(
                    child: Column(
                      children: [
                        CupertinoTextField(
                          controller: _name,
                          placeholder: 'Наименование',
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        CupertinoSlidingSegmentedControl<String>(
                          groupValue: _kind,
                          children: const {
                            'good': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Товар'),
                            ),
                            'service': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Услуга'),
                            ),
                          },
                          onValueChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _kind = value;
                              if (value == 'service') _trackStock = false;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              'Единица',
                              style: TextStyle(color: colors.secondaryLabel),
                            ),
                            const Spacer(),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: _pickUnit,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _unit,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    CupertinoIcons.chevron_down,
                                    size: 12,
                                    color: colors.secondaryLabel,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        _SheetField(
                          label: 'Себестоимость',
                          controller: _cost,
                          suffix: '${moneySymbol}',
                          placeholder: '0',
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        _SheetField(
                          label: 'Цена продажи',
                          controller: _sell,
                          suffix: '${moneySymbol}',
                          placeholder: '0',
                          onChanged: () => setState(() {}),
                        ),
                        if (_cents(_cost.text) > 0 &&
                            _cents(_sell.text) > 0) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                'Маржа',
                                style: TextStyle(
                                  color: colors.secondaryLabel,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_marginLabel()} · ${_marginPercent()}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _marginCents() >= 0
                                      ? colors.green
                                      : colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Учитывать остаток',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    _trackStock
                                        ? 'Поступления и списания меняют остаток'
                                        : 'Остаток не ведётся (услуги, работы)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.secondaryLabel,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CupertinoSwitch(
                              value: _trackStock,
                              onChanged: (value) =>
                                  setState(() => _trackStock = value),
                            ),
                          ],
                        ),
                        if (_trackStock) ...[
                          const SizedBox(height: 12),
                          _SheetField(
                            label: 'Мин. остаток',
                            controller: _min,
                            suffix: _unit,
                            placeholder: '0',
                            onChanged: () => setState(() {}),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_isEdit && widget.item != null && widget.item!.trackStock) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Текущий остаток: ${formatQty(widget.item!.stockQty)} ${widget.item!.unit}. '
                      'Изменить его можно через поступление или списание.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.tertiaryLabel,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _marginCents() => _cents(_sell.text) - _cents(_cost.text);

  String _marginLabel() => '${money(_marginCents())}';

  String _marginPercent() {
    final cost = _cents(_cost.text);
    if (cost <= 0) return '—';
    final pct = _marginCents() / cost * 100;
    return '${pct.toStringAsFixed(pct.abs() >= 100 ? 0 : 1)}%';
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.suffix,
    this.placeholder,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? suffix;
  final String? placeholder;

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
          width: 140,
          child: CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
