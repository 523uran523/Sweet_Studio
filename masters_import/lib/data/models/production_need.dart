import 'inventory_item.dart';

/// Строка «Плана производства» (§6.9): чего не хватает на день.
///
/// Это расчётная величина, а не запись в БД — поэтому без `id`/`toMap`.
/// Экрану нужны все четыре числа: «надо», «есть» и «не хватает» отвечают на
/// разные вопросы, а `reason` объясняет, почему строка вообще появилась.
class ProductionNeed {
  const ProductionNeed({
    required this.item,
    required this.planQty,
    required this.inStock,
    required this.short,
    required this.reason,
  });

  final InventoryItem item;

  /// Сколько требуется по заказам (или порог минимума, если `reason == 'min'`).
  final double planQty;

  /// Остаток на точке, с которой считался план.
  final double inStock;

  /// Дефицит: `planQty - inStock`, всегда > 0.
  final double short;

  /// `plan` — по составу заказов, `min` — позиция просела ниже минимума.
  final String reason;

  String get reasonLabel => reason == 'min' ? 'Ниже минимума' : 'По заказам';
}
