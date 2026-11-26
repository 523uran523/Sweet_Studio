import 'package:sqflite/sqflite.dart';
import '../models/account.dart';

class AccountRepository {
  AccountRepository(this._db);
  final Database _db;

  Future<List<Account>> getAll({bool includeArchived = false}) async {
    final rows = await _db.query('accounts',
        where: includeArchived ? null : 'archived = 0 AND deleted_at IS NULL',
        orderBy: 'name COLLATE NOCASE');
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> byId(String id) async {
    final rows = await _db.query('accounts', where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  Future<void> save(Account a) async {
    await _db.insert('accounts', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('accounts', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}