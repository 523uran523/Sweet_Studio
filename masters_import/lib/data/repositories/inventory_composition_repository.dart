import 'package:sqflite/sqflite.dart';

import '../models/inventory_composition.dart';

class InventoryCompositionRepository {
  InventoryCompositionRepository(this._db);
  final Database _db;

  Future<List<InventoryCompositionLine>> getAll() async {
    final rows = await _db.query('inventory_compositions', orderBy: 'rowid');
    return rows.map(InventoryCompositionLine.fromMap).toList();
  }

  Future<List<InventoryCompositionLine>> forItem(String itemId) async {
    final rows = await _db.query(
      'inventory_compositions',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'rowid',
    );
    return rows.map(InventoryCompositionLine.fromMap).toList();
  }

  /// Replace the whole composition of [itemId] with [lines].
  Future<void> replaceForItem(
    String itemId,
    List<InventoryCompositionLine> lines,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'inventory_compositions',
        where: 'item_id = ?',
        whereArgs: [itemId],
      );
      for (final line in lines) {
        await txn.insert(
          'inventory_compositions',
          line.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
