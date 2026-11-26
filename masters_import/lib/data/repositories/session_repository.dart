import 'package:sqflite/sqflite.dart';

import '../../data/models/job_items.dart' show WorkSession;

class SessionRepository {
  SessionRepository(this._db);
  final Database _db;

  Future<List<WorkSession>> getAll() async {
    final rows = await _db.query('work_sessions', orderBy: 'started_at DESC');
    return rows.map(WorkSession.fromMap).toList();
  }

  Future<List<WorkSession>> forJob(String jobId) async {
    final rows = await _db.query(
      'work_sessions',
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'started_at DESC',
    );
    return rows.map(WorkSession.fromMap).toList();
  }

  Future<int> insertSession(WorkSession session) async {
    return await _db.insert('work_sessions', {
      'job_id': session.jobId,
      'started_at': session.startedAt.millisecondsSinceEpoch,
      'ended_at': session.endedAt?.millisecondsSinceEpoch,
      'minutes': session.minutes,
      'paused_seconds': session.pausedSeconds,
      'note': session.note,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> save(WorkSession session) async {
    await _db.update(
      'work_sessions',
      {
        'job_id': session.jobId,
        'started_at': session.startedAt.millisecondsSinceEpoch,
        'ended_at': session.endedAt?.millisecondsSinceEpoch,
        'minutes': session.minutes,
        'paused_seconds': session.pausedSeconds,
        'note': session.note,
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('work_sessions', where: 'id = ?', whereArgs: [id]);
  }
}
