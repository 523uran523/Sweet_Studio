class CashShift {
  const CashShift({
    required this.id,
    required this.accountId,
    required this.openedAt,
    this.closedAt,
    this.openingCents = 0,
    this.closingCents,
    this.expectedCents,
    this.discrepancyCents,
    this.note,
    this.status = 'open',
  });

  final String id;
  final String accountId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int openingCents;
  final int? closingCents;
  final int? expectedCents;
  final int? discrepancyCents;
  final String? note;
  final String status; // open / closed

  bool get isOpen => status == 'open';

  CashShift copyWith({
    Object? id = _unset,
    Object? accountId = _unset,
    Object? openedAt = _unset,
    Object? closedAt = _unset,
    Object? openingCents = _unset,
    Object? closingCents = _unset,
    Object? expectedCents = _unset,
    Object? discrepancyCents = _unset,
    Object? note = _unset,
    Object? status = _unset,
  }) {
    return CashShift(
      id: id == _unset ? this.id : id as String,
      accountId: accountId == _unset ? this.accountId : accountId as String,
      openedAt: openedAt == _unset ? this.openedAt : openedAt as DateTime,
      closedAt: closedAt == _unset ? this.closedAt : closedAt as DateTime?,
      openingCents: openingCents == _unset ? this.openingCents : openingCents as int,
      closingCents: closingCents == _unset ? this.closingCents : closingCents as int?,
      expectedCents: expectedCents == _unset ? this.expectedCents : expectedCents as int?,
      discrepancyCents: discrepancyCents == _unset ? this.discrepancyCents : discrepancyCents as int?,
      note: note == _unset ? this.note : note as String?,
      status: status == _unset ? this.status : status as String,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'opened_at': openedAt.millisecondsSinceEpoch,
        'closed_at': closedAt?.millisecondsSinceEpoch,
        'opening_cents': openingCents,
        'closing_cents': closingCents,
        'expected_cents': expectedCents,
        'discrepancy_cents': discrepancyCents,
        'note': note,
        'status': status,
      };

  factory CashShift.fromMap(Map<String, Object?> m) => CashShift(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        openedAt: DateTime.fromMillisecondsSinceEpoch(m['opened_at'] as int? ?? 0),
        closedAt: m['closed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['closed_at'] as int),
        openingCents: m['opening_cents'] as int? ?? 0,
        closingCents: m['closing_cents'] as int?,
        expectedCents: m['expected_cents'] as int?,
        discrepancyCents: m['discrepancy_cents'] as int?,
        note: m['note'] as String?,
        status: m['status'] as String? ?? 'open',
      );

  static const Object _unset = Object();
}
