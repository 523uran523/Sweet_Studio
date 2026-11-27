import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/money_format.dart';
import '../core/orders_core.dart';
import '../core/pdf_exporter.dart';
import '../data/draft_storage.dart';
import '../data/models.dart';
import '../state/studio_store.dart';
import '../ui/atelier_widgets.dart';

class OrdersClientsScreen extends StatefulWidget {
  const OrdersClientsScreen({super.key});

  @override
  State<OrdersClientsScreen> createState() => _OrdersClientsScreenState();
}

class _OrdersClientsScreenState extends State<OrdersClientsScreen> {
  int _tab = 0; // 0 = Заказы, 1 = Клиенты
  int _orderFilter = 0; // 0 = Все, 1 = Активные, 2 = Готовые, 3 = Завершённые
  String _search = '';

  Future<void> _openOrderEditor(BuildContext context, {Order? existing}) async {
    final store = context.read<StudioStore>();
    Map<String, dynamic>? savedDraft;
    if (existing == null) {
      savedDraft = await store.drafts.loadJson(DraftStorage.orderDraftKey);
    }

    String clientId = existing?.clientId ??
        (savedDraft?['clientId'] as String? ??
            (store.clients.isNotEmpty ? store.clients.first.id : ''));
    final clientNameCtrl = TextEditingController(
      text: existing?.clientName ??
          (savedDraft?['clientName'] as String? ??
              (store.clients.isNotEmpty ? store.clients.first.name : '')),
    );
    final orderNumberCtrl = TextEditingController(
      text: existing?.orderNumber ??
          (savedDraft?['orderNumber'] as String? ??
              '№${store.orders.length + 101}'),
    );
    var dueDate = existing?.dueDate ??
        (savedDraft?['dueDate'] as String? ?? addDaysIso(todayIsoDate(), 2));
    final addressCtrl = TextEditingController(
      text: existing?.deliveryAddress ??
          (savedDraft?['deliveryAddress'] as String? ?? ''),
    );
    final wishesCtrl = TextEditingController(
      text: existing?.wishes ?? (savedDraft?['wishes'] as String? ?? ''),
    );
    final allergensCtrl = TextEditingController(
      text: existing?.allergens ?? (savedDraft?['allergens'] as String? ?? ''),
    );
    final discountCtrl = TextEditingController(
      text: centsToRubInput(existing?.discountCents ??
          ((savedDraft?['discountCents'] as num?)?.toInt() ?? 0)),
    );
    var status = existing?.status ?? OrderStatus.confirmed;

    List<OrderItem> items = existing != null
        ? List<OrderItem>.from(getOrderItemsNormalized(existing))
        : (savedDraft?['items'] is List
            ? (savedDraft!['items'] as List)
                .whereType<Map<String, dynamic>>()
                .map(OrderItem.fromJson)
                .toList()
            : <OrderItem>[]);

    if (items.isEmpty && store.recipes.isNotEmpty && existing == null && savedDraft == null) {
      final firstRec = store.recipes.first;
      items.add(
        OrderItem(
          id: newId('oi'),
          recipeId: firstRec.id,
          recipeTitle: firstRec.title,
          qty: 1,
          weightGrams: firstRec.yieldGrams,
          priceCents: firstRec.recommendedPriceCents,
          costCents: firstRec.costCents,
        ),
      );
    }

    void persistDraft() {
      if (existing != null) return;
      store.drafts.saveJson(DraftStorage.orderDraftKey, {
        'clientId': clientId,
        'clientName': clientNameCtrl.text,
        'orderNumber': orderNumberCtrl.text,
        'dueDate': dueDate,
        'deliveryAddress': addressCtrl.text,
        'wishes': wishesCtrl.text,
        'allergens': allergensCtrl.text,
        'discountCents': parseRubToCents(discountCtrl.text),
        'items': items.map((e) => e.toJson()).toList(),
      });
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final totals = computeOrderItemsTotals(items);
          final discount = parseRubToCents(discountCtrl.text);
          final finalPrice =
              (totals.basePriceCents - discount) < 0 ? 0 : (totals.basePriceCents - discount);

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          existing == null ? 'Новый заказ' : 'Редактировать заказ',
                          style: Theme.of(ctx)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (existing == null && savedDraft != null)
                        TextButton(
                          onPressed: () async {
                            await store.drafts.clearKey(DraftStorage.orderDraftKey);
                            clientNameCtrl.clear();
                            addressCtrl.clear();
                            wishesCtrl.clear();
                            allergensCtrl.clear();
                            discountCtrl.text = '0';
                            setModalState(() => items = []);
                          },
                          child: const Text('Сбросить черновик'),
                        ),
                    ],
                  ),
                  if (existing == null && savedDraft != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Черновик восстановлен автоматически — сохраняется на устройстве при каждом изменении.',
                        style: TextStyle(fontSize: 12, color: store.palette.primary),
                      ),
                    ),
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: orderNumberCtrl,
                          decoration: const InputDecoration(labelText: 'Номер'),
                          onChanged: (_) => persistDraft(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime.tryParse(dueDate) ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setModalState(() => dueDate = todayIsoDate(picked));
                              persistDraft();
                            }
                          },
                          icon: const Icon(Icons.event, size: 16),
                          label: Text('Выдача: $dueDate'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (store.clients.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue:
                          store.clients.any((c) => c.id == clientId) ? clientId : '',
                      decoration: const InputDecoration(labelText: 'Клиент из базы'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Указать вручную')),
                        ...store.clients.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            )),
                      ],
                      onChanged: (v) {
                        setModalState(() {
                          clientId = v ?? '';
                          final found = store.clients
                              .cast<Client?>()
                              .firstWhere((c) => c!.id == clientId, orElse: () => null);
                          if (found != null) {
                            clientNameCtrl.text = found.name;
                            if ((found.address ?? '').isNotEmpty &&
                                addressCtrl.text.isEmpty) {
                              addressCtrl.text = found.address!;
                            }
                            if ((found.allergens ?? '').isNotEmpty &&
                                allergensCtrl.text.isEmpty) {
                              allergensCtrl.text = found.allergens!;
                            }
                          }
                        });
                        persistDraft();
                      },
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: clientNameCtrl,
                    decoration: const InputDecoration(labelText: 'Имя заказчика *'),
                    onChanged: (_) => persistDraft(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Позиции заказа',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final defaultRec = store.recipes.isNotEmpty
                              ? store.recipes.first
                              : null;
                          setModalState(() {
                            items.add(
                              OrderItem(
                                id: newId('oi'),
                                recipeId: defaultRec?.id ?? '',
                                recipeTitle: defaultRec?.title ?? 'Десерт на заказ',
                                qty: 1,
                                weightGrams: defaultRec?.yieldGrams ?? 1000,
                                priceCents: defaultRec?.recommendedPriceCents ?? 350000,
                                costCents: defaultRec?.costCents ?? 180000,
                              ),
                            );
                          });
                          persistDraft();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Добавить позицию'),
                      ),
                    ],
                  ),
                  for (var idx = 0; idx < items.length; idx++) ...[
                    _OrderItemRowEditor(
                      key: ValueKey(items[idx].id),
                      item: items[idx],
                      recipes: store.recipes,
                      currency: store.profile.currencySymbol,
                      onChanged: (next) {
                        setModalState(() => items[idx] = next);
                        persistDraft();
                      },
                      onRemove: () {
                        setModalState(() => items.removeAt(idx));
                        persistDraft();
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: discountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Скидка (₽)'),
                          onChanged: (_) {
                            setModalState(() {});
                            persistDraft();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<OrderStatus>(
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Статус'),
                          items: OrderStatus.values
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(kOrderStatusLabelsRu[s] ?? s.name),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => status = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(labelText: 'Доставка / Самовывоз'),
                    onChanged: (_) => persistDraft(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: wishesCtrl,
                    decoration: const InputDecoration(labelText: 'Пожелания и надпись'),
                    onChanged: (_) => persistDraft(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: allergensCtrl,
                    decoration: const InputDecoration(labelText: 'Аллергены'),
                    onChanged: (_) => persistDraft(),
                  ),
                  const SizedBox(height: 12),
                  AtelierCard(
                    color: store.palette.surfaceAlt,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Вес / объём: ${totals.totalWeightGrams.round()} г'),
                            Text(
                              'Себест.: ${formatMoneyCents(totals.baseCostCents, currencySymbol: store.profile.currencySymbol)}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Итого по заказу:',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              formatMoneyCents(
                                finalPrice,
                                currencySymbol: store.profile.currencySymbol,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: store.palette.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () async {
                      if (clientNameCtrl.text.trim().isEmpty || items.isEmpty) {
                        showAtelierMessage(
                          ctx,
                          'Укажите заказчика и хотя бы одну позицию.',
                          isError: true,
                        );
                        return;
                      }
                      final summaryTitle = buildOrderSummaryTitle(items);
                      final ord = Order(
                        id: existing?.id ?? newId('ord'),
                        orderNumber: orderNumberCtrl.text.trim().isEmpty
                            ? '№${store.orders.length + 101}'
                            : orderNumberCtrl.text.trim(),
                        title: summaryTitle,
                        clientId: clientId.isNotEmpty ? clientId : null,
                        clientName: clientNameCtrl.text.trim(),
                        items: items,
                        recipeId: items.first.recipeId,
                        recipeTitle: items.first.recipeTitle,
                        weightGrams: totals.totalWeightGrams,
                        priceCents: finalPrice,
                        costCents: totals.baseCostCents,
                        prepaymentCents: existing?.prepaymentCents ?? 0,
                        paidCents: existing?.paidCents ?? 0,
                        discountCents: discount,
                        status: status,
                        dueDate: dueDate,
                        deliveryAddress: addressCtrl.text.trim(),
                        wishes: wishesCtrl.text.trim(),
                        allergens: allergensCtrl.text.trim(),
                        stockDeducted: existing?.stockDeducted ?? false,
                        favorite: existing?.favorite ?? false,
                        createdAt: existing?.createdAt ??
                            DateTime.now().toIso8601String(),
                      );
                      await store.saveOrder(ord);
                      if (existing == null) {
                        await store.drafts.clearKey(DraftStorage.orderDraftKey);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(existing == null ? 'Сохранить заказ' : 'Обновить заказ'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openOrderDetails(BuildContext context, String orderId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Consumer<StudioStore>(
        builder: (ctx, store, _) {
          final order = store.orders
              .cast<Order?>()
              .firstWhere((o) => o!.id == orderId, orElse: () => null);
          if (order == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Заказ удалён.'),
            );
          }
          final p = store.palette;
          final curr = store.profile.currencySymbol;
          final items = getOrderItemsNormalized(order);
          final client = order.clientId != null
              ? store.clients
                  .cast<Client?>()
                  .firstWhere((c) => c!.id == order.clientId, orElse: () => null)
              : null;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${order.orderNumber} · ${order.clientName}',
                          style: Theme.of(ctx)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Редактировать',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openOrderEditor(context, existing: order);
                        },
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusBadge(
                        label: kOrderStatusLabelsRu[order.status] ?? '',
                        color: p.primary,
                      ),
                      if (order.dueDate != null && order.dueDate!.isNotEmpty)
                        StatusBadge(label: 'Выдача: ${order.dueDate}', color: p.secondary),
                      StatusBadge(
                        label: order.stockDeducted
                            ? 'Склад списан'
                            : 'Склад не списан',
                        color: order.stockDeducted ? p.success : p.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AtelierCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Состав заказа (цены зафиксированы на момент заказа)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        for (final it in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${it.recipeTitle} × ${it.qty} (${(it.weightGrams * it.qty).round()} г)',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  formatMoneyCents(it.priceCents * it.qty,
                                      currencySymbol: curr),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Итого / Оплачено / Долг:'),
                            Text(
                              '${formatMoneyCents(order.priceCents, currencySymbol: curr)} / ${formatMoneyCents(order.paidCents, currencySymbol: curr)} / ${formatMoneyCents(order.balanceDueCents, currencySymbol: curr)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<OrderStatus>(
                    initialValue: order.status,
                    decoration: const InputDecoration(labelText: 'Изменить статус'),
                    items: OrderStatus.values
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(kOrderStatusLabelsRu[s] ?? s.name),
                            ))
                        .toList(),
                    onChanged: (v) async {
                      if (v != null) await store.updateOrderStatus(order.id, v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _showOrderPaymentDialog(ctx, store, order),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text('Принять оплату'),
                      ),
                      if (client != null && client.depositCents > 0 && order.balanceDueCents > 0)
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await store.payOrderWithDeposit(orderId: order.id);
                              if (ctx.mounted) {
                                showAtelierMessage(ctx, 'Оплата зачтена с депозита клиента.');
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                showAtelierMessage(ctx, '$e', isError: true);
                              }
                            }
                          },
                          icon: const Icon(Icons.savings_outlined, size: 18),
                          label: Text(
                            'С депозита (${formatMoneyCents(client.depositCents, currencySymbol: curr)})',
                          ),
                        ),
                      if (order.paidCents > 0)
                        OutlinedButton.icon(
                          onPressed: () => _showOrderRefundDialog(ctx, store, order),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Возврат'),
                        ),
                      OutlinedButton.icon(
                        onPressed: order.stockDeducted
                            ? null
                            : () async {
                                try {
                                  await store.deductOrderStockFefo(order.id);
                                  if (ctx.mounted) {
                                    showAtelierMessage(
                                        ctx, 'Остатки списаны по FEFO.');
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    showAtelierMessage(ctx, '$e', isError: true);
                                  }
                                }
                              },
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: Text(
                          order.stockDeducted
                              ? 'Сырьё списано'
                              : 'Списать по FEFO',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionHeader(title: 'Документы PDF (A4, кириллица)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _exportAndSharePdf(
                            ctx,
                            store,
                            order,
                            client,
                            PdfDocKind.invoice,
                          ),
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          label: const Text('Счёт-смета PDF'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _exportAndSharePdf(
                            ctx,
                            store,
                            order,
                            client,
                            PdfDocKind.act,
                          ),
                          icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                          label: const Text('Акт PDF'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportAndSharePdf(
    BuildContext context,
    StudioStore store,
    Order order,
    Client? client,
    PdfDocKind kind,
  ) async {
    try {
      final file = await PdfExporter.saveOrderPdfToFile(
        order: order,
        profile: store.profile,
        client: client,
        kind: kind,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(kind == PdfDocKind.invoice
              ? 'Счёт-смета сформирована'
              : 'Акт сформирован'),
          content: Text('Файл сохранён локально:\n${file.path}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await PdfExporter.openPdfFile(file);
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Открыть'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await PdfExporter.sharePdfFile(
                  file,
                  title: '${order.orderNumber} · ${order.clientName}',
                );
              },
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Поделиться'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showAtelierMessage(context, 'Ошибка PDF: $e', isError: true);
      }
    }
  }

  Future<void> _showOrderPaymentDialog(
    BuildContext context,
    StudioStore store,
    Order order,
  ) async {
    final defaultAmt =
        order.balanceDueCents > 0 ? order.balanceDueCents : order.priceCents;
    final amountCtrl = TextEditingController(text: centsToRubInput(defaultAmt));
    var accountId = store.accounts.isNotEmpty ? store.accounts.first.id : '';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Принять оплату'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Сумма (₽)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Счёт поступления'),
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
                  await store.recordOrderPayment(
                    orderId: order.id,
                    accountId: accountId,
                    amountCents: parseRubToCents(amountCtrl.text),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
                }
              },
              child: const Text('Провести'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOrderRefundDialog(
    BuildContext context,
    StudioStore store,
    Order order,
  ) async {
    final amountCtrl =
        TextEditingController(text: centsToRubInput(order.paidCents));
    final reasonCtrl = TextEditingController();
    var accountId = store.accounts.isNotEmpty ? store.accounts.first.id : '';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Возврат клиенту'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Сумма возврата (₽)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Счёт списания'),
                items: store.accounts
                    .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setDlg(() => accountId = v ?? accountId),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Причина'),
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
                  await store.refundOrderPayment(
                    orderId: order.id,
                    accountId: accountId,
                    amountCents: parseRubToCents(amountCtrl.text),
                    reason: reasonCtrl.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
                }
              },
              child: const Text('Вернуть'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openClientEditor(BuildContext context, {Client? existing}) async {
    final store = context.read<StudioStore>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final addrCtrl = TextEditingController(text: existing?.address ?? '');
    final prefCtrl = TextEditingController(text: existing?.preferences ?? '');
    final allCtrl = TextEditingController(text: existing?.allergens ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null ? 'Новый клиент' : 'Карточка клиента',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Имя клиента *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(labelText: 'Адрес доставки'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: prefCtrl,
                decoration: const InputDecoration(labelText: 'Предпочтения'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: allCtrl,
                decoration: const InputDecoration(labelText: 'Аллергены'),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  await store.saveClient(
                    Client(
                      id: existing?.id ?? newId('cli'),
                      name: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      address: addrCtrl.text.trim(),
                      preferences: prefCtrl.text.trim(),
                      allergens: allCtrl.text.trim(),
                      depositCents: existing?.depositCents ?? 0,
                      favorite: existing?.favorite ?? false,
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Сохранить клиента'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTopUpDepositDialog(
    BuildContext context,
    StudioStore store,
    Client client,
  ) async {
    final amountCtrl = TextEditingController(text: '1000');
    var accountId = store.accounts.isNotEmpty ? store.accounts.first.id : '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Пополнить депозит: ${client.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Сумма (₽)'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(labelText: 'Счёт'),
              items: store.accounts
                  .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              onChanged: (v) => accountId = v ?? accountId,
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
                await store.topUpClientDeposit(
                  clientId: client.id,
                  accountId: accountId,
                  amountCents: parseRubToCents(amountCtrl.text),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
              }
            },
            child: const Text('Пополнить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudioStore>();
    final p = store.palette;
    final curr = store.profile.currencySymbol;
    final q = _search.trim().toLowerCase();

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
                      segments: [
                        ButtonSegment(
                          value: 0,
                          label: Text('Заказы (${store.orders.length})'),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text('Клиенты (${store.clients.length})'),
                        ),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _tab == 0
                        ? _openOrderEditor(context)
                        : _openClientEditor(context),
                    tooltip: _tab == 0 ? 'Новый заказ' : 'Новый клиент',
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: _tab == 0
                      ? 'Поиск по номеру, клиенту или составу...'
                      : 'Поиск клиента по имени или телефону...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              if (_tab == 0) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final opt in [
                        (0, 'Все'),
                        (1, 'Активные'),
                        (2, 'Готовые'),
                        (3, 'Закрытые'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(opt.$2),
                            selected: _orderFilter == opt.$1,
                            onSelected: (_) =>
                                setState(() => _orderFilter = opt.$1),
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
              ? _buildOrdersList(context, store, q, p, curr)
              : _buildClientsList(context, store, q, p, curr),
        ),
      ],
    );
  }

  Widget _buildOrdersList(
    BuildContext context,
    StudioStore store,
    String q,
    dynamic p,
    String curr,
  ) {
    final filtered = store.orders.where((o) {
      if (q.isNotEmpty) {
        final hay = '${o.orderNumber} ${o.clientName} ${o.title}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (_orderFilter == 1) {
        return o.status != OrderStatus.delivered &&
            o.status != OrderStatus.closed &&
            o.status != OrderStatus.cancelled;
      }
      if (_orderFilter == 2) return o.status == OrderStatus.ready;
      if (_orderFilter == 3) {
        return o.status == OrderStatus.delivered ||
            o.status == OrderStatus.closed ||
            o.status == OrderStatus.cancelled;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyAtelierState(
            icon: Icons.shopping_bag_outlined,
            title: 'Заказов пока нет',
            description:
                'Создайте первый заказ с несколькими позициями, предоплатой и печатной сметой в PDF.',
            actionLabel: 'Создать заказ',
            onAction: () => _openOrderEditor(context),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final o = filtered[i];
        final summary = summarizeOrderItems(o);
        return AtelierCard(
          onTap: () => _openOrderDetails(ctx, o.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${o.orderNumber} · ${o.clientName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    formatMoneyCents(
                      o.priceCents,
                      hide: store.hideBalances,
                      currencySymbol: curr,
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                summary.summaryText.isNotEmpty ? summary.summaryText : o.title,
                style: TextStyle(fontSize: 13, color: p.textMuted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusBadge(
                    label: kOrderStatusLabelsRu[o.status] ?? '',
                    color: p.primary,
                  ),
                  if (o.dueDate != null && o.dueDate!.isNotEmpty)
                    StatusBadge(label: 'Срок ${o.dueDate}', color: p.secondary),
                  if (o.balanceDueCents > 0)
                    StatusBadge(
                      label:
                          'Долг ${formatMoneyCents(o.balanceDueCents, hide: store.hideBalances, currencySymbol: curr)}',
                      color: p.warning,
                    )
                  else
                    StatusBadge(label: 'Оплачен', color: p.success),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClientsList(
    BuildContext context,
    StudioStore store,
    String q,
    dynamic p,
    String curr,
  ) {
    final filtered = store.clients.where((c) {
      if (q.isEmpty) return true;
      return '${c.name} ${c.phone ?? ''}'.toLowerCase().contains(q);
    }).toList();

    if (filtered.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyAtelierState(
            icon: Icons.people_outline,
            title: 'Список клиентов пуст',
            description:
                'Добавляйте постоянных клиентов, их аллергены, адреса и депозиты.',
            actionLabel: 'Добавить клиента',
            onAction: () => _openClientEditor(context),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final c = filtered[i];
        final clientOrders = store.orders
            .where((o) =>
                o.clientId == c.id ||
                o.clientName.toLowerCase() == c.name.toLowerCase())
            .toList();
        return AtelierCard(
          onTap: () => _openClientEditor(ctx, existing: c),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  StatusBadge(
                    label:
                        'Депозит: ${formatMoneyCents(c.depositCents, hide: store.hideBalances, currencySymbol: curr)}',
                    color: c.depositCents > 0 ? p.success : p.secondary,
                  ),
                ],
              ),
              if (c.phone != null && c.phone!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(c.phone!, style: TextStyle(fontSize: 12, color: p.textMuted)),
                ),
              if (c.allergens != null && c.allergens!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Аллергены: ${c.allergens}',
                    style: TextStyle(fontSize: 12, color: p.danger),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    pluralOrders(clientOrders.length),
                    style: TextStyle(fontSize: 12, color: p.textMuted),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showTopUpDepositDialog(ctx, store, c),
                    icon: const Icon(Icons.add_card, size: 16),
                    label: const Text('Пополнить депозит'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderItemRowEditor extends StatefulWidget {
  const _OrderItemRowEditor({
    super.key,
    required this.item,
    required this.recipes,
    required this.currency,
    required this.onChanged,
    required this.onRemove,
  });

  final OrderItem item;
  final List<Recipe> recipes;
  final String currency;
  final ValueChanged<OrderItem> onChanged;
  final VoidCallback onRemove;

  @override
  State<_OrderItemRowEditor> createState() => _OrderItemRowEditorState();
}

class _OrderItemRowEditorState extends State<_OrderItemRowEditor> {
  late TextEditingController _titleCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.item.recipeTitle);
    _qtyCtrl = TextEditingController(text: widget.item.qty.toString());
    _weightCtrl =
        TextEditingController(text: widget.item.weightGrams.round().toString());
    _priceCtrl =
        TextEditingController(text: centsToRubInput(widget.item.priceCents));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _qtyCtrl.dispose();
    _weightCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _emit(OrderItem next) => widget.onChanged(next);

  @override
  Widget build(BuildContext context) {
    return AtelierCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: widget.recipes.isNotEmpty
                    ? DropdownButtonFormField<String>(
                        initialValue: widget.recipes
                                .any((r) => r.id == widget.item.recipeId)
                            ? widget.item.recipeId
                            : '',
                        decoration: const InputDecoration(
                          labelText: 'Рецепт',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('Свободная позиция')),
                          ...widget.recipes.map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(r.title, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (val) {
                          final rec = widget.recipes
                              .cast<Recipe?>()
                              .firstWhere((r) => r!.id == val, orElse: () => null);
                          if (rec != null) {
                            _titleCtrl.text = rec.title;
                            _weightCtrl.text = rec.yieldGrams.round().toString();
                            _priceCtrl.text =
                                centsToRubInput(rec.recommendedPriceCents);
                            _emit(OrderItem(
                              id: widget.item.id,
                              recipeId: rec.id,
                              recipeTitle: rec.title,
                              qty: widget.item.qty,
                              weightGrams: rec.yieldGrams,
                              priceCents: rec.recommendedPriceCents,
                              costCents: rec.costCents,
                            ));
                          } else {
                            _emit(OrderItem(
                              id: widget.item.id,
                              recipeId: '',
                              recipeTitle: _titleCtrl.text,
                              qty: widget.item.qty,
                              weightGrams: widget.item.weightGrams,
                              priceCents: widget.item.priceCents,
                              costCents: widget.item.costCents,
                            ));
                          }
                        },
                      )
                    : TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Название позиции',
                          isDense: true,
                        ),
                        onChanged: (v) => _emit(OrderItem(
                          id: widget.item.id,
                          recipeId: widget.item.recipeId,
                          recipeTitle: v,
                          qty: widget.item.qty,
                          weightGrams: widget.item.weightGrams,
                          priceCents: widget.item.priceCents,
                          costCents: widget.item.costCents,
                        )),
                      ),
              ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Шт', isDense: true),
                  onChanged: (v) {
                    final q = (int.tryParse(v) ?? 1).clamp(1, 999);
                    _emit(OrderItem(
                      id: widget.item.id,
                      recipeId: widget.item.recipeId,
                      recipeTitle: _titleCtrl.text,
                      qty: q,
                      weightGrams: widget.item.weightGrams,
                      priceCents: widget.item.priceCents,
                      costCents: widget.item.costCents,
                    ));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Вес, г', isDense: true),
                  onChanged: (v) {
                    final w = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    _emit(OrderItem(
                      id: widget.item.id,
                      recipeId: widget.item.recipeId,
                      recipeTitle: _titleCtrl.text,
                      qty: widget.item.qty,
                      weightGrams: w,
                      priceCents: widget.item.priceCents,
                      costCents: widget.item.costCents,
                    ));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Цена, ₽', isDense: true),
                  onChanged: (v) {
                    final p = parseRubToCents(v);
                    _emit(OrderItem(
                      id: widget.item.id,
                      recipeId: widget.item.recipeId,
                      recipeTitle: _titleCtrl.text,
                      qty: widget.item.qty,
                      weightGrams: widget.item.weightGrams,
                      priceCents: p,
                      costCents: widget.item.costCents,
                    ));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
