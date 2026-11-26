// receiptPath stores a device-local file path; only the string is exchanged in
// backups, the file itself is not synced across devices.
class MoneyTransaction {
  const MoneyTransaction({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.direction,
    required this.amountCents,
    this.category = '',
    this.note,
    this.clientId,
    this.jobId,
    this.shiftId,
    this.relatedTransactionId,
    this.reversesId,
    this.obligationId,
    required this.createdAt,
    this.voided = false,
    this.receiptPath,
    this.paymentMethod,
  });

  final String id;
  final String accountId;
  final String kind; // income, expense, sale, payment, refund, transfer, debt, adjustment, payroll
  final String direction; // in / out
  final int amountCents;
  final String category;
  final String? note;
  final String? clientId;
  final String? jobId;
  final String? shiftId;
  final String? relatedTransactionId;
  final String? reversesId; // id исходной операции, если это операция-возврат

  /// Погашаемое обязательство (`obligations.id`).
  ///
  /// Через него платёж попадает в `paid_cents` обязательства, и долг
  /// считается по остатку обязательств, а не сводкой по документам.
  final String? obligationId;
  final DateTime createdAt;
  final bool voided;
  final String? receiptPath;

  /// Способ оплаты: `cash` / `kaspi` / `card` / `transfer` / `other`.
  ///
  /// Пусто — не указан (старые записи и переводы между своими счетами).
  final String? paymentMethod;

  int get signedAmount => direction == 'in' ? amountCents : -amountCents;

  bool get isOrderPayment =>
      jobId != null &&
      (kind == 'payment' ||
          kind == 'sale' ||
          kind == 'client_payment' ||
          kind == 'refund' ||
          (kind == 'income' && reversesId != null));

  bool get isOrderRefund => isOrderPayment && direction == 'out';

  int get orderPaymentCents {
    if (voided || jobId == null) return 0;
    if (isOrderRefund) return -amountCents;
    if (direction == 'in' && (reversesId == null || isOrderPayment)) {
      return amountCents;
    }
    return 0;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'account_id': accountId,
    'kind': kind,
    'direction': direction,
    'amount_cents': amountCents,
    'category': category,
    'note': note,
    'client_id': clientId,
    'job_id': jobId,
    'shift_id': shiftId,
    'related_transaction_id': relatedTransactionId,
    'reverses_id': reversesId,
    'obligation_id': obligationId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'voided': voided ? 1 : 0,
    'receipt_path': receiptPath,
    'payment_method': paymentMethod,
  };

  factory MoneyTransaction.fromMap(Map<String, Object?> m) => MoneyTransaction(
    id: m['id'] as String,
    accountId: m['account_id'] as String,
    kind: m['kind'] as String,
    direction: m['direction'] as String,
    amountCents: m['amount_cents'] as int? ?? 0,
    category: m['category'] as String? ?? '',
    note: m['note'] as String?,
    clientId: m['client_id'] as String?,
    jobId: m['job_id'] as String?,
    shiftId: m['shift_id'] as String?,
    relatedTransactionId: m['related_transaction_id'] as String?,
    reversesId: m['reverses_id'] as String?,
    obligationId: m['obligation_id'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      m['created_at'] as int? ?? 0,
    ),
    voided: (m['voided'] as int? ?? 0) == 1,
    receiptPath: m['receipt_path'] as String?,
    paymentMethod: m['payment_method'] as String?,
  );

  MoneyTransaction copyWith({
    Object? obligationId = _unset,
    Object? paymentMethod = _unset,
  }) {
    return MoneyTransaction(
      id: id,
      accountId: accountId,
      kind: kind,
      direction: direction,
      amountCents: amountCents,
      category: category,
      note: note,
      clientId: clientId,
      jobId: jobId,
      shiftId: shiftId,
      relatedTransactionId: relatedTransactionId,
      reversesId: reversesId,
      obligationId: obligationId == _unset ? this.obligationId : obligationId as String?,
      paymentMethod: paymentMethod == _unset
          ? this.paymentMethod
          : paymentMethod as String?,
      createdAt: createdAt,
      voided: voided,
      receiptPath: receiptPath,
    );
  }

  static const Object _unset = Object();
}
