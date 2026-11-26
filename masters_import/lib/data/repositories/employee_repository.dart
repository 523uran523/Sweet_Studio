import 'package:sqflite/sqflite.dart';
import '../models/employee.dart';
import 'upsert.dart';

class EmployeeRepository {
  EmployeeRepository(this._db);
  final Database _db;

  Future<List<Employee>> getAll({bool includeArchived = false}) async {
    final rows = await _db.query('employees',
        where: includeArchived ? null : 'archived = 0 AND deleted_at IS NULL',
        orderBy: 'name COLLATE NOCASE');
    return rows.map(Employee.fromMap).toList();
  }

  Future<Employee?> byId(String id) async {
    final rows = await _db.query('employees', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Employee.fromMap(rows.first);
  }

  Future<void> save(Employee e) async {
    // Замена строки (INSERT OR REPLACE) — это DELETE + INSERT: каскад внешних
    // ключей удалял бы условия оплаты, ведомости и строки начислений при
    // обычном переименовании сотрудника. upsertRow обновляет на месте.
    await upsertRow(_db, 'employees', e.toMap());
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('employees', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}
