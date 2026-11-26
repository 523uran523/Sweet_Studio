/// Условия оплаты с датой начала действия (история начислений).
///
/// Зачем: ставка и тип оплаты раньше жили одной строкой в `employees`,
/// поэтому правка карточки переписывала прошлое. Здесь каждая строка —
/// «таким сотрудник был с этой даты».
class PayCondition {
  const PayCondition({
    required this.id,
    required this.employeeId,
    required this.payType,
    required this.rateCents,
    required this.percent,
    required this.validFrom,
    required this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String employeeId;
  final String payType; // hourly, piece, percent, salary, mixed
  final int rateCents;
  final double percent;
  final DateTime validFrom;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  Map<String, Object?> toMap() => {
    'id': id,
    'employee_id': employeeId,
    'pay_type': payType,
    'rate_cents': rateCents,
    'percent': percent,
    'valid_from': validFrom.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt?.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory PayCondition.fromMap(Map<String, Object?> m) => PayCondition(
    id: m['id'] as String,
    employeeId: m['employee_id'] as String,
    payType: m['pay_type'] as String? ?? 'hourly',
    rateCents: (m['rate_cents'] as num?)?.toInt() ?? 0,
    percent: (m['percent'] as num?)?.toDouble() ?? 0,
    validFrom: DateTime.fromMillisecondsSinceEpoch(
      (m['valid_from'] as num?)?.toInt() ?? 0,
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['created_at'] as num?)?.toInt() ?? 0,
    ),
    updatedAt: m['updated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as num).toInt()),
    deletedAt: m['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['deleted_at'] as num).toInt()),
    deviceId: m['device_id'] as String?,
  );
}
