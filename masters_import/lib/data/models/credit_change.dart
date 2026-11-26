import 'dart:convert';

/// Запись аудита по клиентскому кредиту (§5.5, Э4).
///
/// Списание не создаёт второй `money_transactions` (§12.1: денег второй раз
/// не приходило), поэтому след операции живёт только в `audit_log`. Этот
/// класс — читатель этих записей: карточка кредита показывает историю по
/// audit-строкам, а не по выдуманной таблице движений.
class CreditChange {
  const CreditChange({
    required this.action,
    required this.entityId,
    required this.at,
    this.before,
    this.after,
    this.deviceId,
  });

  /// `credit.create` / `credit.use` / `credit.refund` / `credit.expire`.
  final String action;
  final String entityId;

  /// Снимки до и после: из них берётся сумма списания или возврата.
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
  final int at;
  final String? deviceId;

  DateTime get moment => DateTime.fromMillisecondsSinceEpoch(at);

  String get description => switch (action) {
    'credit.create' => 'Создан',
    'credit.use' => 'Списание',
    'credit.refund' => 'Возврат',
    'credit.expire' => 'Истёк срок',
    _ => action,
  };

  /// На сколько изменился остаток (отрицательное — списание).
  ///
  /// У `credit.create` снимка «до» нет: весь остаток появился этой операцией.
  int get deltaCents {
    final to = _cents(after?['remaining_cents']);
    if (to == null) return 0;
    final from = _cents(before?['remaining_cents']);
    if (from == null) return action == 'credit.create' ? to : 0;
    return to - from;
  }

  /// Сумма операции по модулю: для `credit.use`/`credit.refund`.
  int get amountCents => deltaCents.abs();

  static int? _cents(Object? value) => (value as num?)?.toInt();

  factory CreditChange.fromRow(Map<String, Object?> row) {
    return CreditChange(
      action: row['action'] as String? ?? '',
      entityId: row['entity_id'] as String? ?? '',
      before: _map(row['before_json']),
      after: _map(row['after_json']),
      at: (row['at'] as num?)?.toInt() ?? 0,
      deviceId: row['device_id'] as String?,
    );
  }

  static Map<String, Object?>? _map(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }
}
