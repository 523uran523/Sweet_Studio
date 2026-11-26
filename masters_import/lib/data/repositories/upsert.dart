import 'package:sqflite/sqflite.dart';

/// Вставляет строку, а если `id` уже есть — обновляет существующую.
///
/// `ConflictAlgorithm.replace` для этого не годится: SQLite реализует
/// `INSERT OR REPLACE` как `DELETE` + `INSERT`, а с включённым
/// `PRAGMA foreign_keys` это либо отказ по `ON DELETE RESTRICT`
/// (`purchase_lines` → `inventory_items`), либо тихое каскадное удаление
/// дочерних строк (`purchase_lines`, `stock_levels`, `stock_batches`).
/// Первое роняло приёмку закупки, второе — переписывало склад.
Future<void> upsertRow(
  DatabaseExecutor db,
  String table,
  Map<String, Object?> row,
) async {
  final id = row['id'];
  final changed = await db.update(
    table,
    Map.of(row)..remove('id'),
    where: 'id = ?',
    whereArgs: [id],
  );
  if (changed == 0) await db.insert(table, row);
}
