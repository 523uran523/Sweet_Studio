import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/money_format.dart';
import '../core/units.dart';
import '../data/models.dart';
import '../state/studio_store.dart';
import '../ui/atelier_widgets.dart';

class InventoryProductionScreen extends StatefulWidget {
  const InventoryProductionScreen({super.key});

  @override
  State<InventoryProductionScreen> createState() =>
      _InventoryProductionScreenState();
}

class _InventoryProductionScreenState extends State<InventoryProductionScreen> {
  int _tab = 0; // 0 = Кладовая, 1 = Закупки, 2 = Производство
  InventoryKind? _kindFilter;
  String _search = '';

  Future<void> _openNewInventoryItem(BuildContext context) async {
    final store = context.read<StudioStore>();
    final nameCtrl = TextEditingController();
    final minCtrl = TextEditingController(text: '0');
    final costCtrl = TextEditingController(text: '0');
    final densityCtrl = TextEditingController();
    var kind = InventoryKind.raw;
    var unit = 'г';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Новая позиция кладовой'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Название *'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<InventoryKind>(
                        initialValue: kind,
                        decoration: const InputDecoration(labelText: 'Тип'),
                        items: InventoryKind.values
                            .map((k) => DropdownMenuItem(
                                  value: k,
                                  child: Text(kInventoryKindLabelsRu[k] ?? k.name),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDlg(() => kind = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        decoration: const InputDecoration(labelText: 'Ед.'),
                        items: kQtyUnits
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDlg(() => unit = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Мин. остаток'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: costCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Цена за $unit, ₽'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: densityCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Плотность г/мл (для перевода г↔мл)',
                    hintText: 'Например, 1.03 для молока',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final density = double.tryParse(
                    densityCtrl.text.trim().replaceAll(',', '.'));
                await store.saveInventoryItem(
                  InventoryItem(
                    id: newId('inv'),
                    name: nameCtrl.text.trim(),
                    kind: kind,
                    unit: unit,
                    qtyOnHand: 0,
                    minQty:
                        double.tryParse(minCtrl.text.replaceAll(',', '.')) ?? 0,
                    avgCostCents: parseRubToCents(costCtrl.text),
                    density: (density != null && density > 0) ? density : null,
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openItemDetails(
    BuildContext context,
    String itemId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Consumer<StudioStore>(
        builder: (ctx, store, _) {
          final item = store.inventoryItems
              .cast<InventoryItem?>()
              .firstWhere((e) => e!.id == itemId, orElse: () => null);
          if (item == null) return const SizedBox.shrink();
          final p = store.palette;
          final curr = store.profile.currencySymbol;
          final lots = store.stockLots
              .where((l) => l.itemId == item.id && l.remainingQty > 0)
              .toList();

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Остаток: ${formatQty(item.qtyOnHand, item.unit)} · ср. цена ${formatMoneyCents(item.avgCostCents, currencySymbol: curr)}/${item.unit}',
                    style: TextStyle(color: p.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _showReceiptLotDialog(ctx, store, item),
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        label: const Text('Приход партии'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showReconcileDialog(ctx, store, item),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Сверка остатка'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Активные партии (порядок FEFO)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (lots.isEmpty)
                    Text('Активных партий нет.', style: TextStyle(color: p.textMuted))
                  else
                    for (final lot in lots) ...[
                      AtelierCard(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${lot.lotCode} · ${formatQty(lot.remainingQty, lot.unit)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    lot.expiresAt != null && lot.expiresAt!.isNotEmpty
                                        ? 'Годен до ${lot.expiresAt}'
                                        : 'Без срока годности',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: (lot.expiresAt != null &&
                                              lot.expiresAt!.compareTo(todayIsoDate()) < 0)
                                          ? p.danger
                                          : p.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () => _showWriteOffDialog(ctx, store, lot),
                              child: const Text('Списать'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showReceiptLotDialog(
    BuildContext context,
    StudioStore store,
    InventoryItem item,
  ) async {
    final qtyCtrl = TextEditingController(text: '1000');
    final costCtrl = TextEditingController(text: '500');
    String? expiresAt = addDaysIso(todayIsoDate(), 14);
    var unit = item.unit;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Приход: ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Количество'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 86,
                    child: DropdownButtonFormField<String>(
                      initialValue: unit,
                      items: kQtyUnits
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) => setDlg(() => unit = v ?? unit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: costCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Общая стоимость, ₽'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 14)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setDlg(() => expiresAt = todayIsoDate(picked));
                  }
                },
                icon: const Icon(Icons.event, size: 16),
                label: Text('Срок годности: ${expiresAt ?? 'не указан'}'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await store.addStockLotReceipt(
                    itemId: item.id,
                    qty: double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0,
                    unit: unit,
                    totalCostCents: parseRubToCents(costCtrl.text),
                    expiresAt: expiresAt,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
                }
              },
              child: const Text('Оприходовать'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWriteOffDialog(
    BuildContext context,
    StudioStore store,
    StockLot lot,
  ) async {
    final qtyCtrl = TextEditingController(text: lot.remainingQty.toString());
    final reasonCtrl = TextEditingController(text: 'Списание брака / срока');
    var markExpired = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Списать партию ${lot.lotCode}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Количество (${lot.unit})'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Причина'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: markExpired,
                onChanged: (v) => setDlg(() => markExpired = v == true),
                title: const Text('Пометить партию просроченной'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await store.writeOffStockLot(
                    lotId: lot.id,
                    qty: double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0,
                    reason: reasonCtrl.text,
                    markExpired: markExpired,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
                }
              },
              child: const Text('Списать'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReconcileDialog(
    BuildContext context,
    StudioStore store,
    InventoryItem item,
  ) async {
    final qtyCtrl = TextEditingController(text: item.qtyOnHand.toString());
    final reasonCtrl = TextEditingController(text: 'Фактическая инвентаризация');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Сверка: ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  InputDecoration(labelText: 'Фактический остаток (${item.unit})'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Комментарий'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await store.reconcileInventoryItem(
                  itemId: item.id,
                  actualQty:
                      double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0,
                  reason: reasonCtrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
              }
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    );
  }

  Future<void> _openNewPurchaseDialog(BuildContext context) async {
    final store = context.read<StudioStore>();
    final supCtrl = TextEditingController(
      text: store.suppliers.isNotEmpty
          ? store.suppliers.first.name
          : 'Кондитерский маркет',
    );
    String? itemId =
        store.inventoryItems.isNotEmpty ? store.inventoryItems.first.id : null;
    final itemNameCtrl = TextEditingController(
      text: store.inventoryItems.isNotEmpty ? store.inventoryItems.first.name : '',
    );
    final qtyCtrl = TextEditingController(text: '1000');
    var unit = store.inventoryItems.isNotEmpty
        ? store.inventoryItems.first.unit
        : 'г';
    final priceCtrl = TextEditingController(text: '950');
    final deliveryCtrl = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Новая закупка'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: supCtrl,
                  decoration: const InputDecoration(labelText: 'Поставщик *'),
                ),
                const SizedBox(height: 8),
                if (store.inventoryItems.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: itemId,
                    decoration: const InputDecoration(labelText: 'Позиция кладовой'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Новая позиция')),
                      ...store.inventoryItems.map((i) => DropdownMenuItem(
                            value: i.id,
                            child: Text(i.name),
                          )),
                    ],
                    onChanged: (v) {
                      setDlg(() {
                        itemId = v;
                        if (v != null) {
                          final inv =
                              store.inventoryItems.firstWhere((e) => e.id == v);
                          itemNameCtrl.text = inv.name;
                          unit = inv.unit;
                        }
                      });
                    },
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: itemNameCtrl,
                  decoration: const InputDecoration(labelText: 'Название товара *'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Кол-во'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 86,
                      child: DropdownButtonFormField<String>(
                        initialValue: kQtyUnits.contains(unit) ? unit : 'г',
                        items: kQtyUnits
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) => setDlg(() => unit = v ?? unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Сумма товара, ₽'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: deliveryCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Доставка, ₽'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                if (itemNameCtrl.text.trim().isEmpty) return;
                await store.savePurchase(
                  Purchase(
                    id: newId('pur'),
                    supplierName: supCtrl.text.trim(),
                    itemId: itemId,
                    itemName: itemNameCtrl.text.trim(),
                    qty: double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0,
                    unit: unit,
                    priceCents: parseRubToCents(priceCtrl.text),
                    deliveryCents: parseRubToCents(deliveryCtrl.text),
                    expectedDate: todayIsoDate(),
                    expiresAt: addDaysIso(todayIsoDate(), 21),
                    status: PurchaseStatus.ordered,
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Создать заказ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _receivePurchaseDialog(
    BuildContext context,
    StudioStore store,
    Purchase pItem,
  ) async {
    var payFromAccount = true;
    var accountId = store.accounts.isNotEmpty ? store.accounts.first.id : '';
    final total = pItem.priceCents + pItem.deliveryCents;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Оприходовать закупку'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${pItem.itemName}: ${formatQty(pItem.qty, pItem.unit)} на сумму ${formatMoneyCents(total, currencySymbol: store.profile.currencySymbol)}',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: payFromAccount,
                onChanged: (v) => setDlg(() => payFromAccount = v == true),
                title: const Text('Списать оплату со счёта кассы'),
              ),
              if (payFromAccount && store.accounts.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Счёт оплаты'),
                  items: store.accounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setDlg(() => accountId = v ?? accountId),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await store.receivePurchase(
                    purchaseId: pItem.id,
                    accountId: accountId.isNotEmpty ? accountId : null,
                    payFromAccount: payFromAccount,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
                }
              },
              child: const Text('Оприходовать'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProductionDialog(BuildContext context) async {
    final store = context.read<StudioStore>();
    if (store.recipes.isEmpty) {
      showAtelierMessage(context, 'Сначала создайте рецепт.', isError: true);
      return;
    }
    var recipeId = store.recipes.first.id;
    final plannedCtrl =
        TextEditingController(text: store.recipes.first.yieldGrams.round().toString());
    final actualCtrl =
        TextEditingController(text: store.recipes.first.yieldGrams.round().toString());
    String expiresAt = addDaysIso(todayIsoDate(), 3);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Новый выпуск по рецепту'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: recipeId,
                  decoration: const InputDecoration(labelText: 'Рецепт'),
                  items: store.recipes
                      .map((r) => DropdownMenuItem(value: r.id, child: Text(r.title)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final rec = store.recipes.firstWhere((e) => e.id == v);
                    setDlg(() {
                      recipeId = v;
                      plannedCtrl.text = rec.yieldGrams.round().toString();
                      actualCtrl.text = rec.yieldGrams.round().toString();
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: plannedCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'План закладки, г'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: actualCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Фактический выход, г'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 3)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setDlg(() => expiresAt = todayIsoDate(picked));
                    }
                  },
                  icon: const Icon(Icons.event, size: 16),
                  label: Text('Срок годности: $expiresAt'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await store.completeProductionRun(
                    recipeId: recipeId,
                    plannedGrams:
                        double.tryParse(plannedCtrl.text.replaceAll(',', '.')) ?? 0,
                    actualGrams:
                        double.tryParse(actualCtrl.text.replaceAll(',', '.')) ?? 0,
                    expiresAt: expiresAt,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    showAtelierMessage(
                        context, 'Выпуск проведён: сырьё списано, партия оприходована.');
                  }
                } catch (e) {
                  if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
                }
              },
              child: const Text('Провести выпуск'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudioStore>();
    final p = store.palette;
    final curr = store.profile.currencySymbol;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Кладовая')),
                        ButtonSegment(value: 1, label: Text('Закупки')),
                        ButtonSegment(value: 2, label: Text('Выпуск')),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      if (_tab == 0) {
                        _openNewInventoryItem(context);
                      } else if (_tab == 1) {
                        _openNewPurchaseDialog(context);
                      } else {
                        _openProductionDialog(context);
                      }
                    },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_tab == 0) ...[
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Поиск по кладовой...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('Все'),
                          selected: _kindFilter == null,
                          onSelected: (_) => setState(() => _kindFilter = null),
                        ),
                      ),
                      for (final k in InventoryKind.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(kInventoryKindLabelsRu[k] ?? k.name),
                            selected: _kindFilter == k,
                            onSelected: (_) => setState(() => _kindFilter = k),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _tab == 0
              ? _buildInventoryTab(context, store, p, curr)
              : _tab == 1
                  ? _buildPurchasesTab(context, store, p, curr)
                  : _buildProductionTab(context, store, p, curr),
        ),
      ],
    );
  }

  Widget _buildInventoryTab(
    BuildContext context,
    StudioStore store,
    dynamic p,
    String curr,
  ) {
    final q = _search.trim().toLowerCase();
    final filtered = store.inventoryItems.where((it) {
      if (_kindFilter != null && it.kind != _kindFilter) return false;
      if (q.isNotEmpty && !it.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        AtelierCard(
          color: p.surfaceAlt,
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 18, color: p.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Правило FEFO: списание идёт строго с ближайших по сроку годности активных партий; просрочка и отрицательные остатки блокируются.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          EmptyAtelierState(
            icon: Icons.inventory_2_outlined,
            title: 'В кладовой пока пусто',
            description: 'Добавьте ингредиенты, упаковку или оформите закупку.',
            actionLabel: 'Добавить позицию',
            onAction: () => _openNewInventoryItem(context),
          )
        else
          for (final it in filtered) ...[
            AtelierCard(
              onTap: () => _openItemDetails(context, it.id),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${kInventoryKindLabelsRu[it.kind]} · ср. ${formatMoneyCents(it.avgCostCents, currencySymbol: curr)}/${it.unit}',
                          style: TextStyle(fontSize: 12, color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatQty(it.qtyOnHand, it.unit),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: (it.minQty > 0 && it.qtyOnHand <= it.minQty)
                              ? p.danger
                              : p.textPrimary,
                        ),
                      ),
                      if (it.minQty > 0 && it.qtyOnHand <= it.minQty)
                        StatusBadge(label: 'Мало', color: p.danger),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _buildPurchasesTab(
    BuildContext context,
    StudioStore store,
    dynamic p,
    String curr,
  ) {
    if (store.purchases.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyAtelierState(
            icon: Icons.local_shipping_outlined,
            title: 'Закупок пока нет',
            description:
                'Планируйте закупки у поставщиков и оприходуйте партии на склад в 1 действие без задвоения расхода.',
            actionLabel: 'Новая закупка',
            onAction: () => _openNewPurchaseDialog(context),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: store.purchases.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final pur = store.purchases[i];
        final total = pur.priceCents + pur.deliveryCents;
        return AtelierCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pur.itemName} (${formatQty(pur.qty, pur.unit)})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${pur.supplierName} · ${formatMoneyCents(total, currencySymbol: curr)}',
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              if (pur.status != PurchaseStatus.received)
                FilledButton.tonal(
                  onPressed: () => _receivePurchaseDialog(ctx, store, pur),
                  child: const Text('Оприходовать'),
                )
              else
                StatusBadge(label: 'Оприходовано', color: p.success),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductionTab(
    BuildContext context,
    StudioStore store,
    dynamic p,
    String curr,
  ) {
    if (store.productionRuns.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyAtelierState(
            icon: Icons.bakery_dining_outlined,
            title: 'Производственных выпусков нет',
            description:
                'Проведите выпуск полуфабриката или готового изделия: сырьё спишется по FEFO, а готовая партия появится в кладовой.',
            actionLabel: 'Провести выпуск',
            onAction: () => _openProductionDialog(context),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: store.productionRuns.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final run = store.productionRuns[i];
        return AtelierCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      run.recipeTitle,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Выход ${run.actualGrams.round()} г (план ${run.plannedGrams.round()} г) · себест. ${formatMoneyCents(run.totalCostCents, currencySymbol: curr)}',
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              if (run.status == ProductionStatus.completed)
                TextButton(
                  onPressed: () async {
                    try {
                      await store.reverseProductionRun(run.id);
                      if (ctx.mounted) {
                        showAtelierMessage(ctx, 'Выпуск сторнирован, сырьё возвращено.');
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        showAtelierMessage(ctx, '$e', isError: true);
                      }
                    }
                  },
                  child: const Text('Сторно'),
                )
              else
                StatusBadge(label: 'Сторнирован', color: p.danger),
            ],
          ),
        );
      },
    );
  }
}
