import 'package:sqflite/sqflite.dart';

import '../models/entity_attribute.dart';

class EntityAttributeRepository {
  EntityAttributeRepository(this._db);
  final Database _db;

  Future<List<EntityAttribute>> getAll() async {
    final rows = await _db.query(
      'entity_attributes',
      where: 'deleted_at IS NULL',
      orderBy: 'entity_type, entity_id, sort_order',
    );
    return rows.map(EntityAttribute.fromMap).toList();
  }

  Future<void> save(EntityAttribute attribute) async {
    await _db.insert(
      'entity_attributes',
      attribute.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'entity_attributes',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }
}
