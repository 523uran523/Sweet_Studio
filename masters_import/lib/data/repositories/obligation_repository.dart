import 'package:sqflite/sqflite.dart';
import '../models/obligation.dart';

class ObligationRepository {
  ObligationRepository(this._db);
  final DatabaseExecutor _db;

  Future<List<Obligation>> getAll({bool includeCancelled = false}) async {
    final where = includeCancelled
        ? 'deleted_at IS NULL'
        : 'deleted_at IS NULL AND status != \'cancelled\'';
    final rows = await _db.query(
      'obligations',
      where: where,
      orderBy: 'due_at ASC',
    );
    return rows.map(Obligation.fromMap).toList();
  }

  Future<List<Obligation>> forJob(String jobId) async {
    final rows = await _db.query(
      'obligations',
      where: 'job_id = ? AND deleted_at IS NULL',
      whereArgs: [jobId],
      orderBy: 'due_at ASC',
    );
    return rows.map(Obligation.fromMap).toList();
  }

  Future<List<Obligation>> forCounterparty(String type, String id) async {
    final rows = await _db.query(
      'obligations',
      where: 'counterparty_type = ? AND counterparty_id = ? AND deleted_at IS NULL',
      whereArgs: [type, id],
      orderBy: 'due_at ASC',
    );
    return rows.map(Obligation.fromMap).toList();
  }

  Future<Obligation?> byId(String id) async {
    final rows = await _db.query(
      'obligations',
      where: "id = ? AND deleted_at IS NULL",
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Obligation.fromMap(rows.first);
  }

  Future<void> save(Obligation obligation) async {
    await _db.insert(
      'obligations',
      obligation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'obligations',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Удалить все обязательства для заказа (при удалении заказа).
  Future<void> deleteForJob(String jobId) async {
    await _db.delete(
      'obligations',
      where: 'job_id = ?',
      whereArgs: [jobId],
    );
  }
}
