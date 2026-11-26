import 'package:sqflite/sqflite.dart';

import '../models/stock_location.dart';
import 'upsert.dart';

/// Локации и материализованные остатки позиций на них.
///
/// Остаток (`stock_levels`) — производная от партий, поэтому здесь только
/// запись и чтение; пересчёт `qty` делает store, где он видит и партии, и
/// `inventory_items.stock_qty`.
class StockLocationRepository {
  StockLocationRepository(this._db);

  final Database _db;

  Future<List<StockLocation>> getAll() async {
    final rows = await _db.query(
      'locations',
      where: 'deleted_at IS NULL',
      orderBy: 'is_default DESC, name COLLATE NOCASE',
    );
    return rows.map(StockLocation.fromMap).toList();
  }

  Future<StockLocation?> byId(String id) async {
    final rows = await _db.query(
      'locations',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StockLocation.fromMap(rows.first);
  }

  /// «Основной склад» бэкфилла §12.2, если он уже создан.
  Future<StockLocation?> defaultLocation() async {
    final rows = await _db.query(
      'locations',
      where: 'is_default = 1 AND deleted_at IS NULL',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StockLocation.fromMap(rows.first);
  }

  Future<void> save(StockLocation location) async {
    await upsertRow(_db, 'locations', location.toMap());
  }

  /// Мягкое удаление. «Основной склад» не удаляется: на него указывают
  /// остатки и партии, а без него инвариант «остаток = Σ партий» потерял бы
  /// точку отсчёта.
  Future<bool> delete(String id) async {
    final existing = await byId(id);
    if (existing == null || existing.isDefault) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'locations',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  // ── Остатки по локациям ─────────────────────────────────────────────

  Future<List<StockLevel>> getAllLevels() async {
    final rows = await _db.query(
      'stock_levels',
      where: 'deleted_at IS NULL',
      orderBy: 'item_id ASC',
    );
    return rows.map(StockLevel.fromMap).toList();
  }

  Future<StockLevel?> level(String itemId, String locationId) async {
    final rows = await _db.query(
      'stock_levels',
      where:
          'item_id = ? AND location_id = ? AND deleted_at IS NULL',
      whereArgs: [itemId, locationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return StockLevel.fromMap(rows.first);
  }

  /// Порог минимум на точке.
  ///
  /// Строку остатка создаёт вызывающий (store), потому что id генерирует он
  /// же: репозиторий не придумывает первичные ключи.
  Future<void> saveLevel(StockLevel level) async {
    await upsertRow(_db, 'stock_levels', level.toMap());
  }

  Future<void> deleteLevel(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'stock_levels',
      {'deleted_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
