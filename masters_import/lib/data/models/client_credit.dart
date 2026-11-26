/// Клиентский кредит: депозит, абонемент, сертификат, залоговая стоимость (§5.5, Э4).
///
/// Смысл — не путать полученные деньги с выручкой. Поступление за кредит
/// увеличивает ДДС (`money_transactions` создаётся), но выручка признаётся
/// только при списании (оказании услуги). Остаток `remaining_cents` —
/// обязательство перед клиентом.
class ClientCredit {
  ClientCredit({
    required this.id,
    required this.clientId,
    required this.kind,
    required this.title,
    required this.amountCents,
    required this.remainingCents,
    this.unitsTotal,
    this.unitsLeft,
    this.expiresAt,
    this.status = 'active',
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;
  final String clientId;
  final String kind; // deposit / pass / certificate / rental_deposit
  final String title;
  final int amountCents;
  final int remainingCents;
  final int? unitsTotal;
  final int? unitsLeft;
  final DateTime? expiresAt;
  final String status; // active / expired / refunded
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  bool get isActive => status == 'active';
  bool isExpiredAt(DateTime now) =>
      isActive && expiresAt != null && expiresAt!.isBefore(now);

  String get kindLabel => switch (kind) {
    'deposit' => 'Депозит',
    'pass' => 'Абонемент',
    'certificate' => 'Сертификат',
    'rental_deposit' => 'Залог за аренду',
    _ => 'Другое',
  };

  ClientCredit copyWith({
    Object? clientId = _unset,
    Object? kind = _unset,
    Object? title = _unset,
    Object? amountCents = _unset,
    Object? remainingCents = _unset,
    Object? unitsTotal = _unset,
    Object? unitsLeft = _unset,
    Object? expiresAt = _unset,
    Object? status = _unset,
    Object? note = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return ClientCredit(
      id: id,
      clientId: clientId == _unset ? this.clientId : clientId as String,
      kind: kind == _unset ? this.kind : kind as String,
      title: title == _unset ? this.title : title as String,
      amountCents: amountCents == _unset
          ? this.amountCents
          : amountCents as int,
      remainingCents: remainingCents == _unset
          ? this.remainingCents
          : remainingCents as int,
      unitsTotal: unitsTotal == _unset ? this.unitsTotal : unitsTotal as int?,
      unitsLeft: unitsLeft == _unset ? this.unitsLeft : unitsLeft as int?,
      expiresAt: expiresAt == _unset ? this.expiresAt : expiresAt as DateTime?,
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
    'client_id': clientId,
    'kind': kind,
    'title': title,
    'amount_cents': amountCents,
    'remaining_cents': remainingCents,
    'units_total': unitsTotal,
    'units_left': unitsLeft,
    'expires_at': expiresAt?.millisecondsSinceEpoch,
    'status': status,
    'note': note,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory ClientCredit.fromMap(Map<String, Object?> m) => ClientCredit(
    id: m['id'] as String,
    clientId: m['client_id'] as String,
    kind: m['kind'] as String? ?? 'deposit',
    title: m['title'] as String? ?? '',
    amountCents: (m['amount_cents'] as num?)?.toInt() ?? 0,
    remainingCents: (m['remaining_cents'] as num?)?.toInt() ?? 0,
    unitsTotal: m['units_total'] as int?,
    unitsLeft: m['units_left'] as int?,
    expiresAt: m['expires_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['expires_at'] as num).toInt()),
    status: m['status'] as String? ?? 'active',
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
