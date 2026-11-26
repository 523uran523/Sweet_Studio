class RecurringPayment {
  const RecurringPayment({
    required this.id,
    required this.name,
    this.type = 'expense',
    required this.direction,
    required this.amountCents,
    this.category = '',
    this.accountId,
    this.intervalDays = 30,
    required this.nextDueAt,
    this.active = true,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String type; // expense, income, salary-like, other
  final String direction; // in or out
  final int amountCents;
  final String category;
  final String? accountId;
  final int intervalDays;
  final DateTime nextDueAt;
  final bool active;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get amount => amountCents / 100.0;

  RecurringPayment copyWith({
    Object? id = _unset,
    Object? name = _unset,
    Object? type = _unset,
    Object? direction = _unset,
    Object? amountCents = _unset,
    Object? category = _unset,
    Object? accountId = _unset,
    Object? intervalDays = _unset,
    Object? nextDueAt = _unset,
    Object? active = _unset,
    Object? note = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
  }) {
    return RecurringPayment(
      id: id == _unset ? this.id : id as String,
      name: name == _unset ? this.name : name as String,
      type: type == _unset ? this.type : type as String,
      direction: direction == _unset ? this.direction : direction as String,
      amountCents: amountCents == _unset ? this.amountCents : amountCents as int,
      category: category == _unset ? this.category : category as String,
      accountId: accountId == _unset ? this.accountId : accountId as String?,
      intervalDays: intervalDays ==_unset ? this.intervalDays : intervalDays as int,
      nextDueAt: nextDueAt == _unset ? this.nextDueAt : nextDueAt as DateTime,
      active: active == _unset ? this.active : active as bool,
      note: note == _unset ? this.note : note as String?,
      createdAt: createdAt == _unset ? this.createdAt : createdAt as DateTime,
      updatedAt: updatedAt == _unset ? this.updatedAt : updatedAt as DateTime,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'direction': direction,
        'amount_cents': amountCents,
        'category': category,
        'account_id': accountId,
        'interval_days': intervalDays < 1 ? 1 : intervalDays,
        'next_due_at': nextDueAt.millisecondsSinceEpoch,
        'active': active ? 1 : 0,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory RecurringPayment.fromMap(Map<String, Object?> m) => RecurringPayment(
        id: m['id'] as String,
        name: m['name'] as String,
        type: m['type'] as String? ?? 'expense',
        direction: m['direction'] as String? ?? 'out',
        amountCents: m['amount_cents'] as int? ?? 0,
        category: m['category'] as String? ?? '',
        accountId: m['account_id'] as String?,
        intervalDays: m['interval_days'] as int? ?? 30,
        nextDueAt: DateTime.fromMillisecondsSinceEpoch(m['next_due_at'] as int? ?? 0),
        active: (m['active'] as int? ?? 1) == 1,
        note: m['note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? (m['created_at'] as int? ?? 0)),
      );

  static const Object _unset = Object();
}

class PayrollPeriod {
  const PayrollPeriod({
    required this.id,
    required this.name,
    required this.startAt,
    required this.endAt,
    this.note,
    this.closedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime startAt;
  final DateTime endAt;
  final String? note;
  final DateTime? closedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isClosed => closedAt != null;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'start_at': startAt.millisecondsSinceEpoch,
        'end_at': endAt.millisecondsSinceEpoch,
        'note': note,
        'closed_at': closedAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory PayrollPeriod.fromMap(Map<String, Object?> m) => PayrollPeriod(
        id: m['id'] as String,
        name: m['name'] as String,
        startAt: DateTime.fromMillisecondsSinceEpoch(m['start_at'] as int? ?? 0),
        endAt: DateTime.fromMillisecondsSinceEpoch(m['end_at'] as int? ?? 0),
        note: m['note'] as String?,
        closedAt: m['closed_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['closed_at'] as int),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int? ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int? ?? (m['created_at'] as int? ?? 0)),
      );
}
