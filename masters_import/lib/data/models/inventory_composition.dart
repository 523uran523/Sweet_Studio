/// Строка состава себестоимости товара (BOM): компонент со склада или
/// ручной труд. Итог по товару = сумма qty * price_cents всех строк.
class InventoryCompositionLine {
  const InventoryCompositionLine({
    required this.id,
    required this.itemId,
    this.componentId,
    this.isLabor = false,
    this.qty = 1,
    this.priceCents = 0,
    this.note,
  });

  final String id;
  final String itemId;
  final String? componentId; // NULL для ручного труда
  final bool isLabor;
  final double qty;
  final int priceCents;
  final String? note;

  int get totalCents => (qty * priceCents).round();

  InventoryCompositionLine copyWith({
    Object? id = _unset,
    Object? itemId = _unset,
    Object? componentId = _unset,
    Object? isLabor = _unset,
    Object? qty = _unset,
    Object? priceCents = _unset,
    Object? note = _unset,
  }) {
    return InventoryCompositionLine(
      id: id == _unset ? this.id : id as String,
      itemId: itemId == _unset ? this.itemId : itemId as String,
      componentId: componentId == _unset
          ? this.componentId
          : (componentId as String?),
      isLabor: isLabor == _unset ? this.isLabor : isLabor as bool,
      qty: qty == _unset ? this.qty : qty as double,
      priceCents: priceCents == _unset ? this.priceCents : priceCents as int,
      note: note == _unset ? this.note : (note as String?),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'item_id': itemId,
    'component_id': componentId,
    'is_labor': isLabor ? 1 : 0,
    'qty': qty,
    'price_cents': priceCents,
    'note': note,
  };

  factory InventoryCompositionLine.fromMap(Map<String, Object?> m) =>
      InventoryCompositionLine(
        id: m['id'] as String,
        itemId: m['item_id'] as String,
        componentId: m['component_id'] as String?,
        isLabor: (m['is_labor'] as int? ?? 0) == 1,
        qty: (m['qty'] as num?)?.toDouble() ?? 0,
        priceCents: m['price_cents'] as int? ?? 0,
        note: m['note'] as String?,
      );

  static const Object _unset = Object();
}
