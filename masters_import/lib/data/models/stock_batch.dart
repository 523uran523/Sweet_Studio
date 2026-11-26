/// Партия товара на локации: сколько, по какой цене, когда истекает (§5.6, Э5).
///
/// Смысл — FEFO-списание и учёт себестоимости по закупкам. До Э5 остаток
/// был одним числом в `inventory_items.stock_qty`, и на нём нельзя было
/// ни списать «первым то, что протухнет», ни отличить муку из дешёвой
/// закупки от муки из дорогой.
///
/// Инвариант: сумма `qty` по партиям позиции на локации = `stock_levels.qty`.
/// Любое изменение партии идёт через store (`adjustStock` / приёмка /
/// FEFO-списание), а не напрямую через репозиторий.
class StockBatch {
  StockBatch({
    required this.id,
    required this.itemId,
    required this.locationId,
    required this.qty,
    this.expiresAt,
    this.unitCostCents = 0,
    this.purchaseId,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String itemId;
  final String locationId;

  /// Остаток партии. Положительное число; нулевые партии не хранятся.
  final double qty;

  /// Срок годности. `null` — срок не учитывается.
  final DateTime? expiresAt;

  /// Себестоимость единицы на момент приёмки.
  final int unitCostCents;

  /// Закупка, из которой пришла партия.
  final String? purchaseId;

  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  bool isExpiredAt(DateTime now) {
    final exp = expiresAt;
    if (exp == null) return false;
    return exp.isBefore(now);
  }

  bool isExpiringSoonAt(DateTime now, {int days = 1}) {
    final exp = expiresAt;
    if (exp == null) return false;
    if (exp.isBefore(now)) return false;
    final horizon = now.add(Duration(days: days));
    return !exp.isAfter(horizon);
  }

  StockBatch copyWith({
    Object? qty = _unset,
    Object? expiresAt = _unset,
    Object? unitCostCents = _unset,
    Object? purchaseId = _unset,
    Object? note = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return StockBatch(
      id: id,
      itemId: itemId,
      locationId: locationId,
      qty: qty == _unset ? this.qty : (qty as num).toDouble(),
      expiresAt: expiresAt == _unset ? this.expiresAt : expiresAt as DateTime?,
      unitCostCents: unitCostCents == _unset ? this.unitCostCents : (unitCostCents as num).toInt(),
      purchaseId: purchaseId == _unset ? this.purchaseId : purchaseId as String?,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      deviceId: deviceId == _unset ? this.deviceId : deviceId as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'item_id': itemId,
    'location_id': locationId,
    'qty': qty,
    'expires_at': expiresAt?.millisecondsSinceEpoch,
    'unit_cost_cents': unitCostCents,
    'purchase_id': purchaseId,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory StockBatch.fromMap(Map<String, Object?> m) => StockBatch(
    id: m['id'] as String,
    itemId: m['item_id'] as String,
    locationId: m['location_id'] as String,
    qty: (m['qty'] as num?)?.toDouble() ?? 0,
    expiresAt: m['expires_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['expires_at'] as num).toInt()),
    unitCostCents: (m['unit_cost_cents'] as num?)?.toInt() ?? 0,
    purchaseId: m['purchase_id'] as String?,
    note: m['note'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['created_at'] as num?)?.toInt() ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (m['updated_at'] as num?)?.toInt() ??
          (m['created_at'] as num?)?.toInt() ??
          0,
    ),
    deletedAt: m['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['deleted_at'] as num).toInt()),
    deviceId: m['device_id'] as String?,
  );

  static const Object _unset = Object();
}
