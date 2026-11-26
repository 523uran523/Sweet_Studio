import 'package:sqflite/sqflite.dart';
import '../models/time_entry.dart';

class TimeEntryRepository {
  TimeEntryRepository(this._db);
  final Database _db;

  Future<List<TimeEntry>> getAll() async {
    final rows = await _db.query('time_entries', where: 'deleted_at IS NULL', orderBy: 'started_at DESC');
    return rows.map(TimeEntry.fromMap).toList();
  }

  Future<List<TimeEntry>> forEmployee(String employeeId) async {
    final rows = await _db.query('time_entries',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'started_at DESC');
    return rows.map(TimeEntry.fromMap).toList();
  }

  Future<void> save(TimeEntry t) async {
    await _db.insert('time_entries', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('time_entries', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}

class EmployeePaymentRepository {
  EmployeePaymentRepository(this._db);
  final Database _db;

  Future<List<EmployeePayment>> getAll() async {
    final rows = await _db.query('employee_payments', where: 'deleted_at IS NULL', orderBy: 'created_at DESC');
    return rows.map(EmployeePayment.fromMap).toList();
  }

  Future<List<EmployeePayment>> forEmployee(String employeeId) async {
    final rows = await _db.query('employee_payments',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'created_at DESC');
    return rows.map(EmployeePayment.fromMap).toList();
  }

  Future<void> save(EmployeePayment p) async {
    await _db.insert('employee_payments', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('employee_payments', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}
