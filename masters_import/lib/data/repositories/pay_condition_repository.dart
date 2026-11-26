import 'package:sqflite/sqflite.dart';

import '../models/pay_condition.dart';
import 'upsert.dart';

/// Условия оплаты с датой действия. Строка уникальна по
/// `(employee_id, valid_from)` — это защищает от двойной вставки одной и той
/// же даты при повторном сохранении карточки.
class PayConditionRepository {
  PayConditionRepository(this._db);
  final DatabaseExecutor _db;

  Future<List<PayCondition>> getAll() async {
    final rows = await _db.query(
      'pay_conditions',
      where: 'deleted_at IS NULL',
      orderBy: 'employee_id ASC, valid_from ASC',
    );
    return rows.map(PayCondition.fromMap).toList();
  }

  Future<List<PayCondition>> forEmployee(String employeeId) async {
    final rows = await _db.query(
      'pay_conditions',
      where: 'employee_id = ? AND deleted_at IS NULL',
      whereArgs: [employeeId],
      orderBy: 'valid_from ASC',
    );
    return rows.map(PayCondition.fromMap).toList();
  }

  /// Последняя строка условий, действующая на дату [on]
  /// (`valid_from <= on`). Если таких нет — самая ранняя строка сотрудника
  /// (с пометкой о недостающей истории делает вызывающий код).
  Future<PayCondition?> effectiveOn(String employeeId, DateTime on) async {
    final epoch = on.millisecondsSinceEpoch;
    final active = await _db.query(
      'pay_conditions',
      where: 'employee_id = ? AND deleted_at IS NULL AND valid_from <= ?',
      whereArgs: [employeeId, epoch],
      orderBy: 'valid_from DESC',
      limit: 1,
    );
    if (active.isNotEmpty) return PayCondition.fromMap(active.first);
    final earliest = await _db.query(
      'pay_conditions',
      where: 'employee_id = ? AND deleted_at IS NULL',
      whereArgs: [employeeId],
      orderBy: 'valid_from ASC',
      limit: 1,
    );
    if (earliest.isEmpty) return null;
    return PayCondition.fromMap(earliest.first);
  }

  Future<void> save(
    PayCondition condition, {
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await upsertRow(db, 'pay_conditions', {
      ...condition.toMap(),
      'updated_at': now,
    });
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'pay_conditions',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }
}
