import 'package:sqflite/sqflite.dart';

import '../models/lead.dart';

class LeadRepository {
  LeadRepository(this._db);

  final Database _db;

  Future<List<Lead>> getAll() async {
    final rows = await _db.query(
      'leads',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return rows.map(Lead.fromMap).toList();
  }

  Future<void> save(Lead lead) async {
    await _db.insert(
      'leads',
      lead.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'leads',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }
}
