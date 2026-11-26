import 'package:sqflite/sqflite.dart';

import '../models/stock_batch.dart';
import 'upsert.dart';

/// Партии товара.
///
/// FEFO-порядок задаётся здесь, а не в вызывающем коде: SQLite сортирует
/// `NULL` в `expires_at` **первым** при `ASC`, поэтому без явного признака
/// «срока нет» партии-несъедобное (оборудование, упаковка) списывались бы
/// раньше истекающих. `(expires_at IS NULL)` ставит их в конец очереди.
class StockBatchRepository {
  StockBatchRepository(this._db);

  final Database _db;

  static const String _fefo =
      '(expires_at IS NULL) ASC, expires_at ASC, created_at ASC';

  /// Годные к списанию партии позиции на локации, FEFO.
  ///
  /// Истёкшие не исключаются на уровне запроса: их видно в интерфейсе
  /// (`Pill «истекла»`), но списание их блокирует store.
  Future<List<StockBatch>> forItemAndLocation(
    String itemId,
    String locationId,
  ) async {
    final rows = await _db.query(
      'stock_batches',
      where:
          'item_id = ? AND location_id = ? AND qty > 0 AND deleted_at IS NULL',
      whereArgs: [itemId, locationId],
      orderBy: _fefo,
    );
    return rows.map(StockBatch.fromMap).toList();
  }

  /// Все непустые партии позиции на всех локациях, FEFO.
  Future<List<StockBatch>> forItem(String itemId) async {
    final rows = await _db.query(
      'stock_batches',
      where: 'item_id = ? AND qty > 0 AND deleted_at IS NULL',
      whereArgs: [itemId],
      orderBy: _fefo,
    );
    return rows.map(StockBatch.fromMap).toList();
  }

  Future<List<StockBatch>> getAll({int limit = 20000}) async {
    final rows = await _db.query(
      'stock_batches',
      where: 'qty > 0 AND deleted_at IS NULL',
      orderBy: _fefo,
      limit: limit,
    );
    return rows.map(StockBatch.fromMap).toList();
  }

  Future<void> save(StockBatch batch) async {
    await upsertRow(_db, 'stock_batches', batch.toMap());
  }

  /// Мягкое удаление: нулевые партии остаются в схеме, чтобы история
  /// перемещений и ссылок на закупку не «ломалась» на отсутствующую строку.
  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'stock_batches',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
