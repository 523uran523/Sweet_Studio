import 'package:sqflite/sqflite.dart';
import '../../data/models/job_items.dart' show MaterialItem;

class MaterialRepository {
  MaterialRepository(this._db);
  final Database _db;

  Future<List<MaterialItem>> getAll() async {
    final rows = await _db.query('materials', where: 'deleted_at IS NULL', orderBy: 'job_id, created_at ASC');
    return rows.map(MaterialItem.fromMap).toList();
  }

  Future<List<MaterialItem>> forJob(String jobId) async {
    final rows = await _db.query('materials',
        where: 'job_id = ? AND deleted_at IS NULL', whereArgs: [jobId], orderBy: 'created_at ASC');
    return rows.map(MaterialItem.fromMap).toList();
  }

  Future<void> save(MaterialItem item) async {
    await _db.insert('materials', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('materials', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}