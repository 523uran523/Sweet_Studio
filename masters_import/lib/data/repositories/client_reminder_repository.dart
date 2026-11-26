import 'package:sqflite/sqflite.dart';
import '../models/client_reminder.dart';

class ClientReminderRepository {
  ClientReminderRepository(this._db);
  final Database _db;

  Future<List<ClientReminder>> getAll({bool includeDone = true}) async {
    final where = includeDone ? null : "status = 'pending'";
    final rows = await _db.query('client_reminders', where: where, orderBy: 'due_at ASC');
    return rows.map(ClientReminder.fromMap).toList();
  }

  Future<List<ClientReminder>> forClient(String clientId) async {
    final rows = await _db.query('client_reminders',
        where: 'client_id = ? AND deleted_at IS NULL', whereArgs: [clientId], orderBy: 'due_at ASC');
    return rows.map(ClientReminder.fromMap).toList();
  }

  Future<void> save(ClientReminder r) async {
    await _db.insert('client_reminders', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('client_reminders', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}
