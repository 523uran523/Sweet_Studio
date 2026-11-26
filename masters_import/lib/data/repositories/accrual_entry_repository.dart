import 'package:sqflite/sqflite.dart';

import '../models/accrual_entry.dart';
import 'upsert.dart';

/// Строки начислений, по одной на источник.
///
/// Уникальный ключ `(source_kind, source_id, accrual_kind, employee_id)`
/// соблюдается индексом в базе; `insertIgnore` нужен закрытию периода,
/// которое обязано быть идемпотентным при повторной доставке.
class AccrualEntryRepository {
  AccrualEntryRepository(this._db);
  final DatabaseExecutor _db;

  Future<List<AccrualEntry>> getAll() async {
    final rows = await _db.query(
      'accrual_entries',
      where: 'deleted_at IS NULL',
      orderBy: 'occurred_at DESC',
    );
    return rows.map(AccrualEntry.fromMap).toList();
  }

  /// Все строки, включая мягко удалённые: нужны резервной копии, иначе
  /// расшифровка старой версии ведомости после восстановления окажется пустой.
  Future<List<AccrualEntry>> getAllIncludingDeleted() async {
    final rows = await _db.query('accrual_entries', orderBy: 'occurred_at DESC');
    return rows.map(AccrualEntry.fromMap).toList();
  }

  Future<List<AccrualEntry>> forEmployee(
    String employeeId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final where = StringBuffer('employee_id = ? AND deleted_at IS NULL');
    final args = <Object?>[employeeId];
    if (from != null) {
      where.write(' AND occurred_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.write(' AND occurred_at < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final rows = await _db.query(
      'accrual_entries',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'occurred_at ASC',
    );
    return rows.map(AccrualEntry.fromMap).toList();
  }

  Future<List<AccrualEntry>> forPayslip(String payslipId) async {
    final rows = await _db.query(
      'accrual_entries',
      where: 'payslip_id = ? AND deleted_at IS NULL',
      whereArgs: [payslipId],
      orderBy: 'occurred_at ASC',
    );
    return rows.map(AccrualEntry.fromMap).toList();
  }

  /// Все строки ведомости, включая мягко удалённые при пересчёте
  /// переоткрытого периода — для расшифровки исторической версии.
  Future<List<AccrualEntry>> forPayslipIncludingDeleted(
    String payslipId,
  ) async {
    final rows = await _db.query(
      'accrual_entries',
      where: 'payslip_id = ?',
      whereArgs: [payslipId],
      orderBy: 'occurred_at ASC',
    );
    return rows.map(AccrualEntry.fromMap).toList();
  }

  /// Мягко удаляет строки, привязанные к ведомостям периода, перед
  /// пересчётом после переоткрытия. Строки остаются в базе и в расшифровке
  /// своей ведомости; уникальный ключ (частичный индекс) освобождается.
  Future<int> softDeleteBoundToPeriod(
    String periodId,
    DateTime at, {
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? _db;
    final now = at.millisecondsSinceEpoch;
    return db.rawUpdate(
      'UPDATE accrual_entries SET deleted_at = ?, updated_at = ? '
      'WHERE payslip_id IN (SELECT id FROM payslips WHERE period_id = ?) '
      'AND deleted_at IS NULL',
      [now, now, periodId],
    );
  }

  /// Мягкое удаление строк, привязанных к конкретным ведомостям.
  /// Используется при пересчёте после переоткрытия: удаляем только по
  /// старым версиям, чтобы не задеть только что вставленные.
  Future<int> softDeleteBoundToPayslips(
    List<String> payslipIds,
    DateTime at, {
    DatabaseExecutor? txn,
  }) async {
    if (payslipIds.isEmpty) return 0;
    final db = txn ?? _db;
    final now = at.millisecondsSinceEpoch;
    final placeholders = List.filled(payslipIds.length, '?').join(', ');
    return db.rawUpdate(
      'UPDATE accrual_entries SET deleted_at = ?, updated_at = ? '
      'WHERE payslip_id IN ($placeholders) AND deleted_at IS NULL',
      [now, now, ...payslipIds],
    );
  }

  /// Идемпотентная вставка: дубль источника игнорируется, строка возвращает
  /// признак вставки.
  Future<bool> insertIgnore(
    AccrualEntry entry, {
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final changed = await db.insert('accrual_entries', {
      ...entry.toMap(),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return changed != 0;
  }

  Future<void> save(AccrualEntry entry) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await upsertRow(_db, 'accrual_entries', {
      ...entry.toMap(),
      'updated_at': now,
    });
  }

  /// Привязка строк к ведомости при закрытии периода.
  Future<void> attachToPayslip(List<String> entryIds, String payslipId) async {
    if (entryIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final placeholders = List.filled(entryIds.length, '?').join(', ');
    await _db.rawUpdate(
      'UPDATE accrual_entries SET payslip_id = ?, updated_at = ? '
      'WHERE id IN ($placeholders)',
      [payslipId, now, ...entryIds],
    );
  }
}
