import 'package:sqflite/sqflite.dart';

import '../models/attribute_type.dart';

/// Доступ к справочнику типов параметров `attribute_types`.
class AttributeTypeRepository {
  AttributeTypeRepository(this._db);

  final Database _db;

  Future<List<AttributeType>> getAll() async {
    final rows = await _db.query('attribute_types', orderBy: 'key');
    return rows.map(AttributeType.fromMap).toList();
  }

  Future<void> save(AttributeType type) async {
    await _db.insert(
      'attribute_types',
      type.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
