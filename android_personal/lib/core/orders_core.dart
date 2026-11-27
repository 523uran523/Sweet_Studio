import '../data/models.dart';

class OrderItemsTotals {
  const OrderItemsTotals({
    required this.totalWeightGrams,
    required this.basePriceCents,
    required this.baseCostCents,
  });

  final double totalWeightGrams;
  final int basePriceCents;
  final int baseCostCents;
}

List<OrderItem> getOrderItemsNormalized(Order order) {
  if (order.items.isNotEmpty) return order.items;
  final fallbackTitle = (order.recipeTitle != null && order.recipeTitle!.isNotEmpty)
      ? order.recipeTitle!
      : (order.title.isNotEmpty ? order.title : 'Изделие');
  return [
    OrderItem(
      id: 'legacy_${order.id}',
      recipeId: order.recipeId ?? '',
      recipeTitle: fallbackTitle,
      qty: 1,
      weightGrams: order.weightGrams > 0 ? order.weightGrams : 0,
      priceCents: order.priceCents > 0 ? order.priceCents : 0,
      costCents: order.costCents > 0 ? order.costCents : 0,
    ),
  ];
}

OrderItemsTotals computeOrderItemsTotals(List<OrderItem> items) {
  double totalWeight = 0;
  var basePrice = 0;
  var baseCost = 0;
  for (final item in items) {
    final qty = item.qty < 1 ? 1 : item.qty;
    totalWeight += item.weightGrams * qty;
    basePrice += item.priceCents * qty;
    baseCost += item.costCents * qty;
  }
  return OrderItemsTotals(
    totalWeightGrams: totalWeight.roundToDouble(),
    basePriceCents: basePrice,
    baseCostCents: baseCost,
  );
}

String buildOrderSummaryTitle(List<OrderItem> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) {
    final first = items.first;
    final suffix = first.qty > 1 ? ' ×${first.qty}' : '';
    final full = '${first.recipeTitle}$suffix';
    return full.length > 160 ? full.substring(0, 160) : full;
  }
  final joined = items
      .map((i) => '${i.recipeTitle}${i.qty > 1 ? ' ×${i.qty}' : ''}')
      .join(' + ');
  return joined.length > 160 ? joined.substring(0, 160) : joined;
}

class OrderSummary {
  const OrderSummary({
    required this.count,
    required this.totalWeightGrams,
    required this.summaryText,
  });

  final int count;
  final int totalWeightGrams;
  final String summaryText;
}

OrderSummary summarizeOrderItems(Order order) {
  final items = order.items.isNotEmpty
      ? order.items
      : ((order.recipeTitle != null && order.recipeTitle!.isNotEmpty) ||
              order.weightGrams > 0)
          ? getOrderItemsNormalized(order)
          : const <OrderItem>[];
  if (items.isEmpty) {
    return OrderSummary(
      count: 0,
      totalWeightGrams: order.weightGrams.round(),
      summaryText: '',
    );
  }
  final totalWeight = items.fold<int>(
    0,
    (s, i) => s + (i.weightGrams * (i.qty < 1 ? 1 : i.qty)).round(),
  );
  if (items.length == 1) {
    final only = items.first;
    final qtyLabel = only.qty > 1 ? ' × ${only.qty}' : '';
    final weightLabel = totalWeight > 0 ? ' · $totalWeight г' : '';
    return OrderSummary(
      count: only.qty,
      totalWeightGrams: totalWeight,
      summaryText: '${only.recipeTitle}$qtyLabel$weightLabel',
    );
  }
  final preview = items
      .take(3)
      .map((i) => '${i.recipeTitle}${i.qty > 1 ? ' ×${i.qty}' : ''}')
      .join(', ');
  final tail = items.length > 3 ? ' + ещё ${items.length - 3}' : '';
  final weightLabel = totalWeight > 0 ? ' · $totalWeight г' : '';
  return OrderSummary(
    count: items.fold<int>(0, (s, i) => s + (i.qty < 1 ? 1 : i.qty)),
    totalWeightGrams: totalWeight,
    summaryText: '${items.length} поз. ($preview$tail)$weightLabel',
  );
}

class RecipeAttribution {
  const RecipeAttribution({
    required this.key,
    required this.title,
    required this.ordersCount,
    required this.revenueCents,
    required this.costCents,
  });

  final String key;
  final String title;
  final int ordersCount;
  final int revenueCents;
  final int costCents;
}

List<RecipeAttribution> attributeOrderToRecipes(
  Order order,
  List<Recipe> recipes,
) {
  final items = order.items.isNotEmpty
      ? order.items
      : ((order.recipeId != null && order.recipeId!.isNotEmpty) ||
              (order.recipeTitle != null && order.recipeTitle!.isNotEmpty))
          ? getOrderItemsNormalized(order)
          : const <OrderItem>[];
  if (items.isEmpty) return const [];

  final lineGrosses = items
      .map((i) => (i.priceCents * (i.qty < 1 ? 1 : i.qty)).clamp(0, 1 << 50))
      .toList();
  final totalGross = lineGrosses.fold<int>(0, (s, v) => s + v);

  var allocated = 0;
  final out = <RecipeAttribution>[];
  for (var idx = 0; idx < items.length; idx++) {
    final item = items[idx];
    final qty = item.qty < 1 ? 1 : item.qty;
    Recipe? rec;
    if (item.recipeId.isNotEmpty) {
      for (final r in recipes) {
        if (r.id == item.recipeId) {
          rec = r;
          break;
        }
      }
    }
    rec ??= recipes.cast<Recipe?>().firstWhere(
          (r) =>
              r!.title.trim().toLowerCase() ==
              item.recipeTitle.trim().toLowerCase(),
          orElse: () => null,
        );

    final key = rec?.id ??
        (item.recipeId.isNotEmpty
            ? item.recipeId
            : (item.recipeTitle.isNotEmpty ? item.recipeTitle : 'other'));
    final title = rec?.title ??
        (item.recipeTitle.isNotEmpty ? item.recipeTitle : 'Изделие');

    int revShare;
    if (idx == items.length - 1) {
      revShare = (order.priceCents - allocated) < 0
          ? 0
          : (order.priceCents - allocated);
    } else if (totalGross > 0) {
      revShare = ((order.priceCents * lineGrosses[idx]) / totalGross).round();
    } else {
      revShare = (order.priceCents / items.length).round();
    }
    allocated += revShare;

    final lineCost = (items.length == 1 && order.costCents > 0)
        ? order.costCents
        : (item.costCents * qty).clamp(0, 1 << 50);

    out.add(
      RecipeAttribution(
        key: key,
        title: title,
        ordersCount: qty,
        revenueCents: revShare,
        costCents: lineCost,
      ),
    );
  }
  return out;
}
