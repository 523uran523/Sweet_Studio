import 'package:sqflite/sqflite.dart';
import '../models/client.dart';

class ClientRepository {
  ClientRepository(this._db);
  final Database _db;

  Future<List<Client>> getAll() async {
    final rows = await _db.query('clients', where: 'deleted_at IS NULL', orderBy: 'name COLLATE NOCASE');
    return rows.map(Client.fromMap).toList();
  }

  Future<Client?> byId(String id) async {
    final rows = await _db.query('clients', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Client.fromMap(rows.first);
  }

  /// UPDATE вместо INSERT OR REPLACE: при включённых foreign keys REPLACE
  /// делает DELETE+INSERT, и `ON DELETE CASCADE` у jobs/objects/obligations
  /// удалял всё состояние клиента при каждом его редактировании.
  Future<void> save(Client client) async {
    final updated = await _db.update(
      'clients',
      client.toMap(),
      where: 'id = ?',
      whereArgs: [client.id],
    );
    if (updated == 0) {
      await _db.insert('clients', client.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('clients', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}