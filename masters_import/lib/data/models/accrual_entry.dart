/// Строка начисления: ровно одно начисление на один источник.
///
/// Источник — табельная запись (`time_entry`) или завершённый заказ
/// (`job`). Уникальный ключ `(source_kind, source_id, accrual_kind,
/// employee_id)` не даёт начислить за одну работу дважды при повторном
/// закрытии или повторной доставке события.
class AccrualEntry {
  const AccrualEntry({
    required this.id,
    required this.sourceKind,
    required this.sourceId,
    required this.accrualKind,
    required this.employeeId,
    required this.occurredAt,
    required this.payType,
    required this.amountCents,
    required this.createdAt,
    this.payConditionId,
    this.minutes = 0,
    this.basisPriceCents = 0,
    this.rateCents = 0,
    this.percent = 0,
    this.needsReview = false,
    this.payslipId,
    this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String sourceKind; // time_entry | job
  final String sourceId;
  final String accrualKind; // hourly | piece | percent
  final String employeeId;
  final DateTime occurredAt;
  final String payType; // тип оплаты сотрудника на дату
  final String? payConditionId; // условия, по которым считали
  final int minutes;
  final int basisPriceCents; // цена заказа (piece/percent)
  final int rateCents;
  final double percent;
  final int amountCents;
  final bool needsReview; // восстановлено из истории без исходной ведомости
  final String? payslipId; // присваивается при закрытии периода
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  Map<String, Object?> toMap() => {
    'id': id,
    'source_kind': sourceKind,
    'source_id': sourceId,
    'accrual_kind': accrualKind,
    'employee_id': employeeId,
    'pay_condition_id': payConditionId,
    'occurred_at': occurredAt.millisecondsSinceEpoch,
    'minutes': minutes,
    'basis_price_cents': basisPriceCents,
    'rate_cents': rateCents,
    'percent': percent,
    'pay_type': payType,
    'amount_cents': amountCents,
    'needs_review': needsReview ? 1 : 0,
    'payslip_id': payslipId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt?.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory AccrualEntry.fromMap(Map<String, Object?> m) => AccrualEntry(
    id: m['id'] as String,
    sourceKind: m['source_kind'] as String,
    sourceId: m['source_id'] as String,
    accrualKind: m['accrual_kind'] as String,
    employeeId: m['employee_id'] as String,
    payConditionId: m['pay_condition_id'] as String?,
    occurredAt: DateTime.fromMillisecondsSinceEpoch(
      (m['occurred_at'] as num?)?.toInt() ?? 0,
    ),
    minutes: (m['minutes'] as num?)?.toInt() ?? 0,
    basisPriceCents: (m['basis_price_cents'] as num?)?.toInt() ?? 0,
    rateCents: (m['rate_cents'] as num?)?.toInt() ?? 0,
    percent: (m['percent'] as num?)?.toDouble() ?? 0,
    payType: m['pay_type'] as String? ?? 'hourly',
    amountCents: (m['amount_cents'] as num?)?.toInt() ?? 0,
    needsReview: (m['needs_review'] as num?)?.toInt() == 1,
    payslipId: m['payslip_id'] as String?,
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
