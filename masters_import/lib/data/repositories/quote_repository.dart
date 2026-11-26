import 'package:sqflite/sqflite.dart';

import '../models/quote.dart';

class QuoteRepository {
  QuoteRepository(this._db);

  final Database _db;

  Future<List<Quote>> getAll() async {
    final rows = await _db.query(
      'quotes',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return rows.map(Quote.fromMap).toList();
  }

  Future<void> save(Quote quote) async {
    await _db.insert(
      'quotes',
      quote.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Максимальная ревизия для номера; 0, если номера ещё нет.
  Future<int> maxRevision(String number) async {
    final rows = await _db.rawQuery(
      'SELECT MAX(revision) AS rev FROM quotes '
      'WHERE number = ? AND deleted_at IS NULL',
      [number],
    );
    return (rows.first['rev'] as num?)?.toInt() ?? 0;
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'quotes',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }
}
