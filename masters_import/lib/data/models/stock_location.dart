/// Локация: точка, цех или склад (§5.6, Э5).
///
/// Пока `module_locations` выключен (§12.2), остаток живёт в единственном
/// «Основном складе» и `locationId` в движениях остаётся `null`. При первом
/// включении флага `store.ensureDefaultLocation()` создаёт эту локацию и
/// привязывает к ней текущие остатки — идемпотентно.
class StockLocation {
  StockLocation({
    required this.id,
    required this.name,
    this.kind = 'warehouse',
    this.isDefault = false,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String name;

  /// warehouse / workshop / store.
  final String kind;

  /// «Основной склад»: создаётся бэкфиллом, не удаляется.
  final bool isDefault;

  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  String get kindLabel => switch (kind) {
    'workshop' => 'Цех',
    'store' => 'Магазин',
    _ => 'Склад',
  };

  StockLocation copyWith({
    Object? name = _unset,
    Object? kind = _unset,
    Object? isDefault = _unset,
    Object? note = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return StockLocation(
      id: id,
      name: name == _unset ? this.name : name as String,
      kind: kind == _unset ? this.kind : kind as String,
      isDefault: isDefault == _unset ? this.isDefault : isDefault as bool,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      deviceId: deviceId == _unset ? this.deviceId : deviceId as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'kind': kind,
    'is_default': isDefault ? 1 : 0,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory StockLocation.fromMap(Map<String, Object?> m) => StockLocation(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    kind: m['kind'] as String? ?? 'warehouse',
    isDefault: (m['is_default'] as num?)?.toInt() == 1,
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

/// Остаток позиции на конкретной локации.
///
/// Держится как материализованная сумма партий (`stock_batches.qty`) и
/// пересчитывается в store при каждом изменении партий. `minQty` — порог
/// именно для этой точки: на витрине минимум один, на складе другой.
class StockLevel {
  StockLevel({
    required this.id,
    required this.itemId,
    required this.locationId,
    required this.qty,
    this.minQty = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String itemId;
  final String locationId;
  final double qty;
  final double minQty;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  bool get isBelowMin => minQty > 0 && qty < minQty;

  StockLevel copyWith({
    Object? qty = _unset,
    Object? minQty = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return StockLevel(
      id: id,
      itemId: itemId,
      locationId: locationId,
      qty: qty == _unset ? this.qty : (qty as num).toDouble(),
      minQty: minQty == _unset ? this.minQty : (minQty as num).toDouble(),
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
    'min_qty': minQty,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory StockLevel.fromMap(Map<String, Object?> m) => StockLevel(
    id: m['id'] as String,
    itemId: m['item_id'] as String,
    locationId: m['location_id'] as String,
    qty: (m['qty'] as num?)?.toDouble() ?? 0,
    minQty: (m['min_qty'] as num?)?.toDouble() ?? 0,
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
