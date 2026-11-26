import 'package:sqflite/sqflite.dart';
import '../models/stock_movement.dart';
import 'upsert.dart';

class StockMovementRepository {
  StockMovementRepository(this._db);
  final Database _db;

  Future<List<StockMovement>> forItem(String itemId) async {
    final rows = await _db.query('stock_movements',
        where: 'item_id = ?',
        whereArgs: [itemId],
        orderBy: 'created_at DESC');
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<List<StockMovement>> getAll() async {
    final rows = await _db.query('stock_movements', where: 'deleted_at IS NULL', orderBy: 'created_at DESC', limit: 100);
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<void> save(StockMovement m) async {
    await upsertRow(_db, 'stock_movements', m.toMap());
  }
}