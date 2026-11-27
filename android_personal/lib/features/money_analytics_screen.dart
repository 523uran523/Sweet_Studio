import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/calculator_core.dart';
import '../core/money_format.dart';
import '../core/orders_core.dart';
import '../data/models.dart';
import '../state/studio_store.dart';
import '../ui/atelier_widgets.dart';

class MoneyAnalyticsScreen extends StatefulWidget {
  const MoneyAnalyticsScreen({super.key});

  @override
  State<MoneyAnalyticsScreen> createState() => _MoneyAnalyticsScreenState();
}

class _MoneyAnalyticsScreenState extends State<MoneyAnalyticsScreen> {
  int _tab = 0; // 0 = Финансы, 1 = Аналитика
  int _periodDays = 30;

  bool _inPeriod(String iso) {
    if (_periodDays == 0) return true;
    final start = addDaysIso(todayIsoDate(), -(_periodDays - 1));
    final dateOnly = iso.length >= 10 ? iso.substring(0, 10) : iso;
    return dateOnly.compareTo(start) >= 0;
  }

  Future<void> _openNewAccountDialog(BuildContext context) async {
    final store = context.read<StudioStore>();
    final nameCtrl = TextEditingController();
    final balCtrl = TextEditingController(text: '0');
    var kind = AccountKind.card;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый счёт'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Название счёта *'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AccountKind>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Тип'),
              items: const [
                DropdownMenuItem(value: AccountKind.cash, child: Text('Наличные')),
                DropdownMenuItem(value: AccountKind.card, child: Text('Карта')),
                DropdownMenuItem(value: AccountKind.bank, child: Text('Банк / Счёт')),
              ],
              onChanged: (v) => kind = v ?? kind,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: balCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Начальный остаток, ₽'),
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
              if (nameCtrl.text.trim().isEmpty) return;
              await store.saveAccount(
                Account(
                  id: newId('acc'),
                  name: nameCtrl.text.trim(),
                  kind: kind,
                  balanceCents: parseRubToCents(balCtrl.text),
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTransactionDialog(
    BuildContext context,
    TransactionKind kind,
  ) async {
    final store = context.read<StudioStore>();
    if (store.accounts.isEmpty) return;
    final amountCtrl = TextEditingController();
    final catCtrl = TextEditingController(
      text: kind == TransactionKind.income ? 'Продажа' : 'Расходы кухни',
    );
    final noteCtrl = TextEditingController();
    var accountId = store.accounts.first.id;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(kind == TransactionKind.income ? 'Приход денег' : 'Расход денег'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Сумма, ₽ *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: catCtrl,
              decoration: const InputDecoration(labelText: 'Категория'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(labelText: 'Счёт'),
              items: store.accounts
                  .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              onChanged: (v) => accountId = v ?? accountId,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
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
                await store.addMoneyTransaction(
                  kind: kind,
                  category: catCtrl.text.trim().isEmpty
                      ? 'Операция'
                      : catCtrl.text.trim(),
                  amountCents: parseRubToCents(amountCtrl.text),
                  accountId: accountId,
                  note: noteCtrl.text.trim(),
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
    );
  }

  Future<void> _openTransferDialog(BuildContext context) async {
    final store = context.read<StudioStore>();
    if (store.accounts.length < 2) {
      showAtelierMessage(
        context,
        'Добавьте второй счёт, чтобы делать переводы.',
        isError: true,
      );
      return;
    }
    var fromId = store.accounts.first.id;
    var toId = store.accounts[1].id;
    final amountCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Перевод между счетами'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: fromId,
                decoration: const InputDecoration(labelText: 'Со счёта'),
                items: store.accounts
                    .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setDlg(() => fromId = v ?? fromId),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: toId,
                decoration: const InputDecoration(labelText: 'На счёт'),
                items: store.accounts
                    .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setDlg(() => toId = v ?? toId),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Сумма, ₽'),
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
                  await store.transferBetweenAccounts(
                    fromAccountId: fromId,
                    toAccountId: toId,
                    amountCents: parseRubToCents(amountCtrl.text),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showAtelierMessage(ctx, '$e', isError: true);
                }
              },
              child: const Text('Перевести'),
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
    final hide = store.hideBalances;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Финансы и Счета')),
              ButtonSegment(value: 1, label: Text('Аналитика')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(
          child: _tab == 0
              ? _buildFinanceTab(context, store, p, curr, hide)
              : _buildAnalyticsTab(context, store, p, curr, hide),
        ),
      ],
    );
  }

  Widget _buildFinanceTab(
    BuildContext context,
    StudioStore store,
    dynamic p,
    String curr,
    bool hide,
  ) {
    final reversedIds = netCashTotals(store.moneyTransactions).reversedIds;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        SectionHeader(
          title: 'Счета мастерской',
          trailing: TextButton.icon(
            onPressed: () => _openNewAccountDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Счёт'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: store.accounts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final acc = store.accounts[i];
              return SizedBox(
                width: 170,
                child: MetricTile(
                  label: acc.name,
                  value: formatMoneyCents(acc.balanceCents,
                      hide: hide, currencySymbol: curr),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () =>
                  _openTransactionDialog(context, TransactionKind.income),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Доход'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  _openTransactionDialog(context, TransactionKind.expense),
              icon: const Icon(Icons.remove, size: 18),
              label: const Text('Расход'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openTransferDialog(context),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Перевод'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionHeader(
          title: 'Журнал операций (${store.moneyTransactions.length})',
        ),
        const SizedBox(height: 8),
        if (store.moneyTransactions.isEmpty)
          EmptyAtelierState(
            icon: Icons.receipt_outlined,
            title: 'Операций по счетам пока нет',
            description:
                'Фиксируйте оплаты заказов, закупки сырья и переводы между счетами.',
          )
        else
          for (final tx in store.moneyTransactions) ...[
            AtelierCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.category,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: reversedIds.contains(tx.id)
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          '${tx.accountName}${tx.note != null && tx.note!.isNotEmpty ? ' · ${tx.note}' : ''}',
                          style: TextStyle(fontSize: 12, color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${tx.kind == TransactionKind.income ? '+' : (tx.kind == TransactionKind.expense ? '-' : '')}'
                        '${formatMoneyCents(tx.amountCents, hide: hide, currencySymbol: curr)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: tx.kind == TransactionKind.income
                              ? p.success
                              : (tx.kind == TransactionKind.expense
                                  ? p.danger
                                  : p.secondary),
                        ),
                      ),
                      if ((tx.kind == TransactionKind.income ||
                              tx.kind == TransactionKind.expense) &&
                          !reversedIds.contains(tx.id))
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                          ),
                          onPressed: () async {
                            try {
                              await store.reverseMoneyTransaction(tx.id);
                            } catch (e) {
                              if (context.mounted) {
                                showAtelierMessage(context, '$e', isError: true);
                              }
                            }
                          },
                          child: const Text('Сторно', style: TextStyle(fontSize: 12)),
                        ),
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

  Widget _buildAnalyticsTab(
    BuildContext context,
    StudioStore store,
    dynamic p,
    String curr,
    bool hide,
  ) {
    final periodTx =
        store.moneyTransactions.where((t) => _inPeriod(t.occurredAt)).toList();
    final cash = netCashTotals(periodTx);

    final recognizedOrders = store.orders
        .where((o) =>
            (o.status == OrderStatus.delivered ||
                o.status == OrderStatus.closed) &&
            _inPeriod(o.dueDate ?? o.createdAt))
        .toList();
    final recognizedRevenue =
        recognizedOrders.fold<int>(0, (s, o) => s + o.priceCents);
    final recognizedCost =
        recognizedOrders.fold<int>(0, (s, o) => s + o.costCents);
    final grossProfit = recognizedRevenue - recognizedCost;

    final receivables = store.orders
        .where(
            (o) => o.status != OrderStatus.cancelled && o.balanceDueCents > 0)
        .fold<int>(0, (s, o) => s + o.balanceDueCents);

    final inventoryValue = store.inventoryItems.fold<int>(
      0,
      (s, it) => s + (it.qtyOnHand * it.avgCostCents).round(),
    );

    final recipeStats = <String, ({String title, int count, int rev, int cost})>{};
    for (final ord in recognizedOrders) {
      for (final attr in attributeOrderToRecipes(ord, store.recipes)) {
        final prev = recipeStats[attr.key];
        recipeStats[attr.key] = prev == null
            ? (
                title: attr.title,
                count: attr.ordersCount,
                rev: attr.revenueCents,
                cost: attr.costCents
              )
            : (
                title: prev.title,
                count: prev.count + attr.ordersCount,
                rev: prev.rev + attr.revenueCents,
                cost: prev.cost + attr.costCents
              );
      }
    }
    final topRecipes = recipeStats.values.toList()
      ..sort((a, b) => b.rev.compareTo(a.rev));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final opt in [
                (7, '7 дней'),
                (30, '30 дней'),
                (90, '90 дней'),
                (0, 'Всё время'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(opt.$2),
                    selected: _periodDays == opt.$1,
                    onSelected: (_) => setState(() => _periodDays = opt.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AtelierCard(
          color: p.surfaceAlt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Два метода учёта не смешиваются:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '• Денежный поток = Поступления − Расходы по счетам за период (предоплаты, доплаты, закупки, возвраты).\n'
                '• Признанная выручка = Итог выданных и закрытых заказов за вычетом их себестоимости.',
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'Денежный поток',
                value: formatMoneyCents(cash.netCents,
                    hide: hide, currencySymbol: curr),
                hint:
                    '+${formatMoneyCents(cash.incomeCents, hide: hide, currencySymbol: curr)} / -${formatMoneyCents(cash.expenseCents, hide: hide, currencySymbol: curr)}',
                accentColor: cash.netCents >= 0 ? p.success : p.danger,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                label: 'Признанная выручка',
                value: formatMoneyCents(recognizedRevenue,
                    hide: hide, currencySymbol: curr),
                hint:
                    'Валовая прибыль: ${formatMoneyCents(grossProfit, hide: hide, currencySymbol: curr)}',
                accentColor: p.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'Дебиторка клиентов',
                value: formatMoneyCents(receivables,
                    hide: hide, currencySymbol: curr),
                hint: 'Неоплаченный остаток по заказам',
                accentColor: receivables > 0 ? p.warning : p.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                label: 'Оценка кладовой',
                value: formatMoneyCents(inventoryValue,
                    hide: hide, currencySymbol: curr),
                hint: '${store.inventoryItems.length} позиций',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionHeader(title: 'Топ рецептов по выручке'),
        const SizedBox(height: 8),
        if (topRecipes.isEmpty)
          const Text('Выдайте или закройте хотя бы один заказ для рейтинга рецептов.')
        else
          for (final r in topRecipes.take(5)) ...[
            AtelierCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${r.count} шт · себест. ${formatMoneyCents(r.cost, hide: hide, currencySymbol: curr)}',
                          style: TextStyle(fontSize: 12, color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatMoneyCents(r.rev, hide: hide, currencySymbol: curr),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }
}
