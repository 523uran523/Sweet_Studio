/// Движение склада: единственный след изменения остатка.
///
/// `reason` и `ref*` появились в v22: без них списание нельзя отличить от
/// продажи, а движение — привязать к заказу или закупке. `unitCostCents` —
/// снимок себестоимости на момент движения, поэтому отчёт по потерям не
/// зависит от будущих правок цены позиции.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.itemId,
    required this.type,
    required this.qty,
    this.note,
    this.reason,
    this.refType,
    this.refId,
    this.locationId,
    this.unitCostCents = 0,
    required this.createdAt,
  });

  final String id;
  final String itemId;

  /// in, out, writeoff, adjust.
  final String type;

  /// Положительное число; направление задаёт [type].
  final double qty;

  final String? note;

  /// spoilage / breakage / sample / expiry / inventory / other.
  final String? reason;

  /// job / purchase / transfer / manual.
  final String? refType;

  final String? refId;

  /// `null` — основной склад (отдельные склады появятся в Э5).
  final String? locationId;

  final int unitCostCents;

  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'item_id': itemId,
    'type': type,
    'qty': qty,
    'note': note,
    'reason': reason,
    'ref_type': refType,
    'ref_id': refId,
    'location_id': locationId,
    'unit_cost_cents': unitCostCents,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory StockMovement.fromMap(Map<String, Object?> m) => StockMovement(
    id: m['id'] as String,
    itemId: m['item_id'] as String,
    type: m['type'] as String,
    qty: (m['qty'] as num?)?.toDouble() ?? 0,
    note: m['note'] as String?,
    reason: m['reason'] as String?,
    refType: m['ref_type'] as String?,
    refId: m['ref_id'] as String?,
    locationId: m['location_id'] as String?,
    unitCostCents: (m['unit_cost_cents'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      m['created_at'] as int? ?? 0,
    ),
  );
}
