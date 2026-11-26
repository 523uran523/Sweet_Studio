/// Плановый платёж: дебиторка с клиента, кредиторка поставщику, налог,
/// аренда, зарплата, кредит.
///
/// Обязательство хранит собственную сумму и прогресс оплаты, поэтому долг
/// считается по остатку (`amountCents - paidCents`), а не пересчитывается из
/// документов каждый раз.
class Obligation {
  Obligation({
    required this.id,
    required this.direction,
    required this.kind,
    this.counterpartyType,
    this.counterpartyId,
    this.jobId,
    required this.title,
    required this.amountCents,
    this.paidCents = 0,
    required this.dueAt,
    this.status = 'planned',
    this.accountId,
    this.note,
    this.paymentMethod,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
  });

  final String id;

  /// `receivable` — должны мне, `payable` — я должен.
  final String direction;

  /// `client_payment` / `supplier_bill` / `tax` / `salary` / `rent` / `loan` /
  /// `other`.
  final String kind;

  /// `client` / `supplier` / `employee` / `none`.
  final String? counterpartyType;
  final String? counterpartyId;

  /// Заказ, к которому привязан платёж (для дебиторки и списаний по заказу).
  final String? jobId;

  final String title;
  final int amountCents;
  final int paidCents;
  final DateTime dueAt;

  /// `planned` / `partial` / `paid` / `cancelled`.
  final String status;

  final String? accountId;
  final String? note;

  /// Способ оплаты: `cash` / `kaspi` / `card` / `transfer` / `other`.
  final String? paymentMethod;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;

  bool get isIncome => direction == 'receivable';

  int get remainingCents {
    final rest = amountCents - paidCents;
    return rest < 0 ? 0 : rest;
  }

  bool get isPaid => status == 'paid' || (amountCents > 0 && paidCents >= amountCents);

  bool get isClosed => isPaid || status == 'cancelled';

  bool isOpenAt(DateTime date) => !isClosed && !dueAt.isAfter(date);

  bool get isOverdue => isOpenAt(DateTime.now());

  String get statusLabel => switch (status) {
    'partial' => 'Частично',
    'paid' => 'Оплачено',
    'cancelled' => 'Отменено',
    _ => isOverdue ? 'Просрочено' : 'План',
  };

  String get kindLabel => switch (kind) {
    'client_payment' => 'Оплата клиента',
    'supplier_bill' => 'Поставщику',
    'tax' => 'Налог',
    'salary' => 'Зарплата',
    'rent' => 'Аренда',
    'loan' => 'Кредит',
    _ => 'Прочее',
  };

  Obligation copyWith({
    Object? direction = _unset,
    Object? kind = _unset,
    Object? counterpartyType = _unset,
    Object? counterpartyId = _unset,
    Object? jobId = _unset,
    Object? title = _unset,
    Object? amountCents = _unset,
    Object? paidCents = _unset,
    Object? dueAt = _unset,
    Object? status = _unset,
    Object? accountId = _unset,
    Object? note = _unset,
    Object? paymentMethod = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
    Object? deviceId = _unset,
  }) {
    return Obligation(
      id: id,
      direction: direction == _unset ? this.direction : direction as String,
      kind: kind == _unset ? this.kind : kind as String,
      counterpartyType: counterpartyType == _unset
          ? this.counterpartyType
          : counterpartyType as String?,
      counterpartyId: counterpartyId == _unset
          ? this.counterpartyId
          : counterpartyId as String?,
      jobId: jobId == _unset ? this.jobId : jobId as String?,
      title: title == _unset ? this.title : title as String,
      amountCents: amountCents == _unset
          ? this.amountCents
          : amountCents as int,
      paidCents: paidCents == _unset ? this.paidCents : paidCents as int,
      dueAt: dueAt == _unset ? this.dueAt : dueAt as DateTime,
      status: status == _unset ? this.status : status as String,
      accountId: accountId == _unset ? this.accountId : accountId as String?,
      note: note == _unset ? this.note : note as String?,
      paymentMethod: paymentMethod == _unset
          ? this.paymentMethod
          : paymentMethod as String?,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      deviceId: deviceId == _unset ? this.deviceId : deviceId as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'direction': direction,
    'kind': kind,
    'counterparty_type': counterpartyType,
    'counterparty_id': counterpartyId,
    'job_id': jobId,
    'title': title,
    'amount_cents': amountCents,
    'paid_cents': paidCents,
    'due_at': dueAt.millisecondsSinceEpoch,
    'status': status,
    'account_id': accountId,
    'note': note,
    'payment_method': paymentMethod,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'deleted_at': deletedAt?.millisecondsSinceEpoch,
    'device_id': deviceId,
  };

  factory Obligation.fromMap(Map<String, Object?> m) => Obligation(
    id: m['id'] as String,
    direction: m['direction'] as String? ?? 'receivable',
    kind: m['kind'] as String? ?? 'other',
    counterpartyType: m['counterparty_type'] as String?,
    counterpartyId: m['counterparty_id'] as String?,
    jobId: m['job_id'] as String?,
    title: m['title'] as String? ?? '',
    amountCents: (m['amount_cents'] as num?)?.toInt() ?? 0,
    paidCents: (m['paid_cents'] as num?)?.toInt() ?? 0,
    dueAt: DateTime.fromMillisecondsSinceEpoch(
      (m['due_at'] as num?)?.toInt() ?? 0,
    ),
    status: m['status'] as String? ?? 'planned',
    accountId: m['account_id'] as String?,
    note: m['note'] as String?,
    paymentMethod: m['payment_method'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['created_at'] as num?)?.toInt() ?? 0,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (m['updated_at'] as num?)?.toInt() ?? (m['created_at'] as num?)?.toInt() ?? 0,
    ),
    deletedAt: m['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['deleted_at'] as num).toInt()),
    deviceId: m['device_id'] as String?,
  );

  static const Object _unset = Object();
}
