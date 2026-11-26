import 'package:sqflite/sqflite.dart';
import '../models/work_object.dart';

class ObjectRepository {
  ObjectRepository(this._db);
  final Database _db;

  Future<List<WorkObject>> getAll() async {
    final rows = await _db.query('objects', where: 'deleted_at IS NULL', orderBy: 'title COLLATE NOCASE');
    return rows.map(WorkObject.fromMap).toList();
  }

  Future<List<WorkObject>> byClient(String clientId) async {
    final rows = await _db.query('objects',
        where: 'client_id = ? AND deleted_at IS NULL', whereArgs: [clientId], orderBy: 'title COLLATE NOCASE');
    return rows.map(WorkObject.fromMap).toList();
  }

  Future<WorkObject?> byId(String id) async {
    final rows = await _db.query('objects', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return WorkObject.fromMap(rows.first);
  }

  /// UPDATE вместо INSERT OR REPLACE: REPLACE при включённых foreign keys
  /// делает DELETE+INSERT, и каскады по объекту теряли связанные записи при
  /// редактировании.
  Future<void> save(WorkObject obj) async {
    final updated = await _db.update(
      'objects',
      obj.toMap(),
      where: 'id = ?',
      whereArgs: [obj.id],
    );
    if (updated == 0) {
      await _db.insert('objects', obj.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('objects', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}