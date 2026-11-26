import 'package:sqflite/sqflite.dart';
import '../models/appointment.dart';

class AppointmentRepository {
  AppointmentRepository(this._db);
  final Database _db;

  Future<List<Appointment>> getAll() async {
    final rows = await _db.query('appointments', where: 'deleted_at IS NULL', orderBy: 'start_at ASC');
    return rows.map(Appointment.fromMap).toList();
  }

  Future<List<Appointment>> forDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db.query('appointments',
        where: 'start_at >= ? AND start_at < ?',
        whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
        orderBy: 'start_at ASC');
    return rows.map(Appointment.fromMap).toList();
  }

  Future<void> save(Appointment a) async {
    await _db.insert('appointments', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update('appointments', {'deleted_at': now, 'updated_at': now}, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
  }
}