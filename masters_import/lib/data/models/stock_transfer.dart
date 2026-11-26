/// Перемещение между локациями (§5.6, Э5).
///
/// Документ, а не движение: `stock_movements` с `refType = 'transfer'` —
/// это следствие, а `transfers` хранит намерение (откуда, куда, что именно).
/// Пока `status = 'planned'`, остатки не тронуты; списание и приход
/// происходят при `completeTransfer`.
library;

class StockTransfer {
  StockTransfer({
    required this.id,
    required this.fromLocationId,
    required this.toLocationId,
    this.status = 'planned',
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String fromLocationId;
  final String toLocationId;

  /// planned / completed / cancelled.
  final String status;

  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  bool get isPlanned => status == 'planned';
  bool get isCompleted => status == 'completed';

  String get statusLabel => switch (status) {
    'completed' => 'выполнено',
    'cancelled' => 'отменено',
    _ => 'план',
  };

  StockTransfer copyWith({
    Object? toLocationId = _unset,
    Object? status = _unset,
    Object? note = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return StockTransfer(
      id: id,
      fromLocationId: fromLocationId,
      toLocationId: toLocationId == _unset
          ? this.toLocationId
          : toLocationId as String,
      status: status == _unset ? this.status : status as String,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      deviceId: deviceId == _unset ? this.deviceId : deviceId as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'from_location_id': fromLocationId,
    'to_location_id': toLocationId,
    'status': status,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory StockTransfer.fromMap(Map<String, Object?> m) => StockTransfer(
    id: m['id'] as String,
    fromLocationId: m['from_location_id'] as String? ?? '',
    toLocationId: m['to_location_id'] as String? ?? '',
    status: m['status'] as String? ?? 'planned',
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

/// Строка перемещения: какая позиция и сколько.
///
/// `qty` — количество в единицах позиции (`kg`, `шт`); списание из локации
/// идёт FEFO по партиям этой позиции, поэтому строка не хранит id партий.
class StockTransferLine {
  StockTransferLine({
    required this.id,
    required this.transferId,
    required this.itemId,
    required this.qty,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String transferId;
  final String itemId;
  final double qty;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  StockTransferLine copyWith({
    Object? transferId = _unset,
    Object? itemId = _unset,
    Object? qty = _unset,
    Object? note = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return StockTransferLine(
      id: id,
      transferId: transferId == _unset ? this.transferId : transferId as String,
      itemId: itemId == _unset ? this.itemId : itemId as String,
      qty: qty == _unset ? this.qty : (qty as num).toDouble(),
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      deviceId: deviceId == _unset ? this.deviceId : deviceId as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'transfer_id': transferId,
    'item_id': itemId,
    'qty': qty,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory StockTransferLine.fromMap(Map<String, Object?> m) =>
      StockTransferLine(
        id: m['id'] as String,
        transferId: m['transfer_id'] as String,
        itemId: m['item_id'] as String,
        qty: (m['qty'] as num?)?.toDouble() ?? 0,
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
            : DateTime.fromMillisecondsSinceEpoch(
                (m['deleted_at'] as num).toInt(),
              ),
        deviceId: m['device_id'] as String?,
      );

  static const Object _unset = Object();
}
