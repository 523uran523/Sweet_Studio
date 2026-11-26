
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  Supplier copyWith({
    Object? id = _unset,
    Object? name = _unset,
    Object? phone = _unset,
    Object? note = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
  }) {
    return Supplier(
      id: id == _unset ? this.id : id as String,
      name: name == _unset ? this.name : name as String,
      phone: phone == _unset ? this.phone : phone as String,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Supplier.fromMap(Map<String, Object?> m) => Supplier(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String? ?? '',
        note: m['note'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? (m['created_at'] as int? ?? 0)),
      );

  static const Object _unset = Object();
}

class Purchase {
  const Purchase({
    required this.id,
    this.supplierId,
    this.accountId,
    required this.totalCents,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.receivedAt,
  });

  final String id;
  final String? supplierId;
  final String? accountId;
  final int totalCents;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Когда закупку приняли (§5.6, Э5). `null` — приёмки не было: закупка
  /// считается оплаченной «как раньше», по строкам и платежам.
  final DateTime? receivedAt;

  /// Принята ли хотя бы часть строк.
  bool get isReceived => receivedAt != null;

  Map<String, Object?> toMap() => {
        'id': id,
        'supplier_id': supplierId,
        'account_id': accountId,
        'total_cents': totalCents,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'received_at': receivedAt?.millisecondsSinceEpoch,
      };

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
        id: m['id'] as String,
        supplierId: m['supplier_id'] as String?,
        accountId: m['account_id'] as String?,
        totalCents: m['total_cents'] as int? ?? 0,
        note: m['note'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? (m['created_at'] as int? ?? 0)),
        receivedAt: m['received_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (m['received_at'] as num).toInt(),
              ),
      );

  Purchase copyWith({
    Object? receivedAt = _unset,
  }) {
    return Purchase(
      id: id,
      supplierId: supplierId,
      accountId: accountId,
      totalCents: totalCents,
      note: note,
      createdAt: createdAt,
      updatedAt: updatedAt,
      receivedAt: receivedAt == _unset
          ? this.receivedAt
          : receivedAt as DateTime?,
    );
  }

  /// Копия с пересчитанной суммой (приёмка-недопоставка, §5.6).
  ///
  /// `copyWith` намеренно не трогает `totalCents` — сумма неизменяема, чтобы
  /// долг поставщику не правился «на глаз». Приёмка меняет именно её, поэтому
  /// отдельный метод, а не ещё один параметр `copyWith`.
  Purchase copyTotal(int totalCents) => Purchase(
        id: id,
        supplierId: supplierId,
        accountId: accountId,
        totalCents: totalCents,
        note: note,
        createdAt: createdAt,
        updatedAt: updatedAt,
        receivedAt: receivedAt,
      );

  static const Object _unset = Object();
}

class PurchaseLine {
  const PurchaseLine({
    required this.id,
    required this.purchaseId,
    required this.itemId,
    required this.qty,
    this.unitPriceCents = 0,
    this.receivedQty,
  });

  final String id;
  final String purchaseId;
  final String itemId;
  final double qty;
  final int unitPriceCents;

  /// Сколько приняли из заказанного (§5.6, Э5). `null` — приёмки не было;
  /// `receivedQty < qty` — недопоставка, долг поставщику пересчитывается.
  final double? receivedQty;

  /// Недопоставлено ли: приёмка была и принято меньше заказанного.
  bool isShortAt({double eps = 0.0001}) {
    final got = receivedQty;
    if (got == null) return false;
    return got + eps < qty;
  }

  double shortageQty({double eps = 0.0001}) {
    final got = receivedQty;
    if (got == null) return 0;
    final missing = qty - got;
    return missing <= eps ? 0 : missing;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'purchase_id': purchaseId,
        'item_id': itemId,
        'qty': qty,
        'unit_price_cents': unitPriceCents,
        'received_qty': receivedQty,
      };

  factory PurchaseLine.fromMap(Map<String, Object?> m) => PurchaseLine(
        id: m['id'] as String,
        purchaseId: m['purchase_id'] as String,
        itemId: m['item_id'] as String,
        qty: (m['qty'] as num?)?.toDouble() ?? 0,
        unitPriceCents: m['unit_price_cents'] as int? ?? 0,
        receivedQty: (m['received_qty'] as num?)?.toDouble(),
      );

  PurchaseLine copyWith({
    Object? qty = _unset,
    Object? unitPriceCents = _unset,
    Object? receivedQty = _unset,
  }) {
    return PurchaseLine(
      id: id,
      purchaseId: purchaseId,
      itemId: itemId,
      qty: qty == _unset ? this.qty : (qty as num).toDouble(),
      unitPriceCents: unitPriceCents == _unset
          ? this.unitPriceCents
          : (unitPriceCents as num).toInt(),
      receivedQty: receivedQty == _unset
          ? this.receivedQty
          : (receivedQty as num?)?.toDouble(),
    );
  }

  static const Object _unset = Object();
}
