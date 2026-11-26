import 'package:sqflite/sqflite.dart';
import '../models/inventory_item.dart';
import 'upsert.dart';

class InventoryItemRepository {
  InventoryItemRepository(this._db);
  final Database _db;

  Future<List<InventoryItem>> getAll({bool includeArchived = false}) async {
    final rows = await _db.query('inventory_items',
        where: includeArchived ? null : 'archived = 0 AND deleted_at IS NULL',
        orderBy: 'name COLLATE NOCASE');
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<InventoryItem?> byId(String id) async {
    final rows = await _db.query('inventory_items', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return InventoryItem.fromMap(rows.first);
  }

  Future<void> save(InventoryItem item) async {
    await upsertRow(_db, 'inventory_items', item.toMap());
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('inventory_items', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}