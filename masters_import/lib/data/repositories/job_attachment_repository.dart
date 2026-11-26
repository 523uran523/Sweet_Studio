import 'package:sqflite/sqflite.dart';

import '../models/job_attachment.dart';

class JobAttachmentRepository {
  JobAttachmentRepository(this._db);
  final Database _db;

  Future<List<JobAttachment>> forJob(String jobId) async {
    final rows = await _db.query(
      'job_attachments',
      where: 'job_id = ? AND deleted_at IS NULL',
      whereArgs: [jobId],
      orderBy: 'created_at DESC',
    );
    return rows.map(JobAttachment.fromMap).toList();
  }

  Future<void> save(JobAttachment a) async {
    await _db.insert('job_attachments', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('job_attachments', {'deleted_at': now, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
  }
}
