import 'package:sqflite/sqflite.dart';

import '../models/payslip.dart';
import 'upsert.dart';

/// Зафиксированные закрытием периода ведомости.
///
/// Номер версии внутри `(period_id, employee_id)` растёт только через
/// закрытие после переоткрытия; старые версии остаются в таблице и в истории,
/// поэтому правка закрытой ведомости невозможна «тихой заменой».
class PayslipRepository {
  PayslipRepository(this._db);
  final DatabaseExecutor _db;

  Future<List<Payslip>> getAll() async {
    final rows = await _db.query(
      'payslips',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return rows.map(Payslip.fromMap).toList();
  }

  Future<List<Payslip>> forPeriod(String periodId) async {
    final rows = await _db.query(
      'payslips',
      where: 'period_id = ? AND deleted_at IS NULL',
      whereArgs: [periodId],
      orderBy: 'employee_id ASC, version DESC',
    );
    return rows.map(Payslip.fromMap).toList();
  }

  Future<List<Payslip>> forEmployee(String employeeId) async {
    final rows = await _db.query(
      'payslips',
      where: 'employee_id = ? AND deleted_at IS NULL',
      whereArgs: [employeeId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Payslip.fromMap).toList();
  }

  /// Максимальная версия ведомости сотрудника в периоде (0 — нет ни одной).
  Future<int> maxVersionFor(
    String periodId,
    String employeeId, {
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? _db;
    final rows = await db.query(
      'payslips',
      columns: ['MAX(version) AS v'],
      where: 'period_id = ? AND employee_id = ?',
      whereArgs: [periodId, employeeId],
    );
    final v = rows.first['v'];
    return (v as num?)?.toInt() ?? 0;
  }

  /// Последняя (максимальная) версия ведомости сотрудника в периоде.
  Future<Payslip?> latestFor(String periodId, String employeeId) async {
    final rows = await _db.query(
      'payslips',
      where: 'period_id = ? AND employee_id = ? AND deleted_at IS NULL',
      whereArgs: [periodId, employeeId],
      orderBy: 'version DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Payslip.fromMap(rows.first);
  }

  Future<void> save(
    Payslip payslip, {
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await upsertRow(db, 'payslips', {...payslip.toMap(), 'updated_at': now});
  }

  /// Все ведомости периода (включая мягко удалённые) — для пересчёта.
  Future<List<Payslip>> forPeriodIds(
    String periodId, {
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? _db;
    final rows = await db.query(
      'payslips',
      where: 'period_id = ?',
      whereArgs: [periodId],
      orderBy: 'version ASC',
    );
    return rows.map(Payslip.fromMap).toList();
  }
}
