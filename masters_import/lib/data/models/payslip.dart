/// Зафиксированная закрытым периодом ведомость одного сотрудника.
///
/// Зачем: до v26 закрытие ставило только `closed_at`, а экспорт пересчитывал
/// суммы заново — ставка менялась, и «уже закрытый час» менял сумму. Здесь
/// суммы зафиксированы строкой; редактирование закрытого периода идёт только
/// через переоткрытие со следующей версией.
class Payslip {
  const Payslip({
    required this.id,
    required this.periodId,
    required this.employeeId,
    required this.version,
    required this.status,
    required this.minutes,
    required this.accruedCents,
    required this.bonusCents,
    required this.penaltyCents,
    required this.advanceCents,
    required this.payoutCents,
    required this.netCents,
    required this.createdAt,
    this.note,
    this.reviewNote,
    this.needsReview = false,
    this.frozenAt,
    this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String periodId;
  final String employeeId;

  /// Номер версии внутри периода+сотрудник: повторное закрытие после
  /// переоткрытия создаёт версию +1, прежние остаются в истории.
  final int version;

  /// `preliminary` — предварительный расчёт (бэкфилл без исходного листка),
  /// `confirmed` — подтверждён мастером явно.
  final String status;
  final int minutes;
  final int accruedCents;
  final int bonusCents;
  final int penaltyCents;
  final int advanceCents;
  final int payoutCents;
  final int netCents;
  final DateTime createdAt;
  final String? note;

  /// Почему строка требует сверки (например, «нет исходной ведомости»).
  final String? reviewNote;
  final bool needsReview;

  /// Момент, когда ведомость была зафиксирована закрытием периода.
  final DateTime? frozenAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  bool get isConfirmed => status == 'confirmed';

  static const Object _unset = Object();

  Payslip copyWith({
    Object? id = _unset,
    Object? periodId = _unset,
    Object? employeeId = _unset,
    Object? version = _unset,
    Object? status = _unset,
    Object? minutes = _unset,
    Object? accruedCents = _unset,
    Object? bonusCents = _unset,
    Object? penaltyCents = _unset,
    Object? advanceCents = _unset,
    Object? payoutCents = _unset,
    Object? netCents = _unset,
    Object? note = _unset,
    Object? reviewNote = _unset,
    Object? needsReview = _unset,
    Object? frozenAt = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
    Object? createdAt = _unset,
  }) {
    return Payslip(
      id: id == _unset ? this.id : id as String,
      periodId: periodId == _unset ? this.periodId : periodId as String,
      employeeId: employeeId == _unset ? this.employeeId : employeeId as String,
      version: version == _unset ? this.version : version as int,
      status: status == _unset ? this.status : status as String,
      minutes: minutes == _unset ? this.minutes : minutes as int,
      accruedCents: accruedCents == _unset ? this.accruedCents : accruedCents as int,
      bonusCents: bonusCents == _unset ? this.bonusCents : bonusCents as int,
      penaltyCents: penaltyCents == _unset ? this.penaltyCents : penaltyCents as int,
      advanceCents: advanceCents == _unset ? this.advanceCents : advanceCents as int,
      payoutCents: payoutCents == _unset ? this.payoutCents : payoutCents as int,
      netCents: netCents == _unset ? this.netCents : netCents as int,
      note: note == _unset ? this.note : (note == null ? null : note as String),
      reviewNote: reviewNote == _unset
          ? this.reviewNote
          : (reviewNote == null ? null : reviewNote as String),
      needsReview: needsReview == _unset ? this.needsReview : needsReview as bool,
      frozenAt: frozenAt == _unset
          ? this.frozenAt
          : (frozenAt == null ? null : frozenAt as DateTime),
      updatedAt: updatedAt == _unset
          ? this.updatedAt
          : (updatedAt == null ? null : updatedAt as DateTime),
      deletedAt: deletedAt == _unset
          ? this.deletedAt
          : (deletedAt == null ? null : deletedAt as DateTime),
      deviceId: deviceId == _unset
          ? this.deviceId
          : (deviceId == null ? null : deviceId as String),
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'period_id': periodId,
    'employee_id': employeeId,
    'version': version,
    'status': status,
    'minutes': minutes,
    'accrued_cents': accruedCents,
    'bonus_cents': bonusCents,
    'penalty_cents': penaltyCents,
    'advance_cents': advanceCents,
    'payout_cents': payoutCents,
    'net_cents': netCents,
    'note': note,
    'review_note': reviewNote,
    'needs_review': needsReview ? 1 : 0,
    'frozen_at': frozenAt?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt?.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory Payslip.fromMap(Map<String, Object?> m) => Payslip(
    id: m['id'] as String,
    periodId: m['period_id'] as String,
    employeeId: m['employee_id'] as String,
    version: (m['version'] as num?)?.toInt() ?? 1,
    status: m['status'] as String? ?? 'preliminary',
    minutes: (m['minutes'] as num?)?.toInt() ?? 0,
    accruedCents: (m['accrued_cents'] as num?)?.toInt() ?? 0,
    bonusCents: (m['bonus_cents'] as num?)?.toInt() ?? 0,
    penaltyCents: (m['penalty_cents'] as num?)?.toInt() ?? 0,
    advanceCents: (m['advance_cents'] as num?)?.toInt() ?? 0,
    payoutCents: (m['payout_cents'] as num?)?.toInt() ?? 0,
    netCents: (m['net_cents'] as num?)?.toInt() ?? 0,
    note: m['note'] as String?,
    reviewNote: m['review_note'] as String?,
    needsReview: (m['needs_review'] as num?)?.toInt() == 1,
    frozenAt: m['frozen_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['frozen_at'] as num).toInt()),
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
