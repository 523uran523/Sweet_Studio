import 'package:sqflite/sqflite.dart';

import '../models/client_credit.dart';

class ClientCreditRepository {
  ClientCreditRepository(this._db);

  final Database _db;

  Future<List<ClientCredit>> getAll() async {
    return (await _db.query(
      'client_credits',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    )).map(ClientCredit.fromMap).toList();
  }

  Future<List<ClientCredit>> forClient(String clientId) async {
    return (await _db.query(
      'client_credits',
      where: 'client_id = ? AND deleted_at IS NULL',
      whereArgs: [clientId],
      orderBy: 'created_at DESC',
    )).map(ClientCredit.fromMap).toList();
  }

  Future<ClientCredit?> getById(String id) async {
    final rows = await _db.query(
      'client_credits',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : ClientCredit.fromMap(rows.first);
  }

  Future<void> save(ClientCredit credit) async {
    await _db.insert(
      'client_credits',
      credit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'client_credits',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
  }
}
