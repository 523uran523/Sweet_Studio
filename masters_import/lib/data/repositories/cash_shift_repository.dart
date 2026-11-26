import 'package:sqflite/sqflite.dart';
import '../models/cash_shift.dart';

class CashShiftRepository {
  CashShiftRepository(this._db);
  final Database _db;

  Future<List<CashShift>> getAll() async {
    final rows = await _db.query('cash_shifts', where: 'deleted_at IS NULL', orderBy: 'opened_at DESC');
    return rows.map(CashShift.fromMap).toList();
  }

  Future<CashShift?> openShift() async {
    final rows = await _db.query('cash_shifts',
        where: "status = 'open'", orderBy: 'opened_at DESC', limit: 1);
    if (rows.isEmpty) return null;
    return CashShift.fromMap(rows.first);
  }

  Future<void> save(CashShift s) async {
    await _db.insert('cash_shifts', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
}