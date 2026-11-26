import 'package:sqflite/sqflite.dart';

import '../models/stock_transfer.dart';
import 'upsert.dart';

/// Перемещения между локациями и их строки.
class StockTransferRepository {
  StockTransferRepository(this._db);

  final Database _db;

  Future<List<StockTransfer>> getAll({int limit = 500}) async {
    final rows = await _db.query(
      'transfers',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(StockTransfer.fromMap).toList();
  }

  Future<StockTransfer?> getById(String id) async {
    final rows = await _db.query(
      'transfers',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StockTransfer.fromMap(rows.first);
  }

  Future<void> save(StockTransfer transfer) async {
    await upsertRow(_db, 'transfers', transfer.toMap());
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'transfers',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Строки перемещения ──────────────────────────────────────────────

  Future<List<StockTransferLine>> linesForTransfer(String transferId) async {
    final rows = await _db.query(
      'transfer_lines',
      where: 'transfer_id = ? AND deleted_at IS NULL',
      whereArgs: [transferId],
      orderBy: 'created_at ASC',
    );
    return rows.map(StockTransferLine.fromMap).toList();
  }

  Future<List<StockTransferLine>> getAllLines({int limit = 20000}) async {
    final rows = await _db.query(
      'transfer_lines',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(StockTransferLine.fromMap).toList();
  }

  Future<void> saveLine(StockTransferLine line) async {
    await upsertRow(_db, 'transfer_lines', line.toMap());
  }

  Future<void> saveLines(Iterable<StockTransferLine> lines) async {
    final batch = _db.batch();
    for (final line in lines) {
      batch.insert(
        'transfer_lines',
        line.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteLinesForTransfer(String transferId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'transfer_lines',
      {'deleted_at': now, 'updated_at': now},
      where: 'transfer_id = ? AND deleted_at IS NULL',
      whereArgs: [transferId],
    );
  }
}
