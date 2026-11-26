import 'package:sqflite/sqflite.dart';
import '../models/booking_resource.dart';

class BookingResourceRepository {
  BookingResourceRepository(this._db);
  final Database _db;

  Future<List<BookingResource>> getAll({bool includeArchived = false}) async {
    final rows = await _db.query('booking_resources',
        where: includeArchived ? null : 'archived = 0 AND deleted_at IS NULL',
        orderBy: 'name COLLATE NOCASE');
    return rows.map(BookingResource.fromMap).toList();
  }

  Future<void> save(BookingResource r) async {
    await _db.insert('booking_resources', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
}