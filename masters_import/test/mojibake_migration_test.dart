// ignore_for_file: prefer_const_constructors
// Regression for schema v21: seeded strings that old builds stored already
// double-encoded must be repaired in place when the database is upgraded.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/core/sync_client.dart' show SyncRow;
import 'package:masters/data/app_database.dart';

/// 'Основной' written by the old build (UTF-8 bytes read back as CP1251).
const String brokenResource =
    '\u0420\u045B\u0421\u0403\u0420\u0405\u0420\u0455\u0420\u0406\u0420\u0405\u0420\u0455\u0420\u2116';

/// 'Наличные' in the same corrupted form.
const String brokenCash =
    '\u0420\u045C\u0420\u00B0\u0420\u00BB\u0420\u0451\u0421\u2021\u0420\u0405\u0421\u2039\u0420\u00B5';

void main() {
  late Directory tempDir;
  late String dbPath;
  late Database db;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mojibake_migration_');
    dbPath = p.join(tempDir.path, 'v20.db');
    // createBaseSchema already builds the complete current schema, so there is
    // nothing to migrate here: the database is opened at v20 and the tests run
    // only the 20 -> 21 step, exactly like a device that lived through v20.
    db = await openDatabase(
      dbPath,
      version: 20,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await AppDatabase.createBaseSchema(database);
      },
    );
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> seedCorruptedRows() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('booking_resources', {
      'id': 'res-1',
      'name': brokenResource,
      'color': '#007AFF',
      'archived': 0,
      'created_at': now,
    });
    await db.insert('accounts', {
      'id': 'acc-1',
      'name': brokenCash,
      'type': 'cash',
      'color': '#22C55E',
      'archived': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('clients', {
      'id': 'cli-1',
      'name': 'Иван Петров',
      'phone': '+996555111223',
      'note': 'Постоянный клиент',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('appointments', {
      'id': 'apt-1',
      'client_id': 'cli-1',
      'resource_id': 'res-1',
      'title': brokenResource,
      'start_at': now,
      'end_at': now + 3600000,
      'status': 'scheduled',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<String?> nameOf(String table, String id) async {
    final rows = await db.query(
      table,
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['name'] as String;
  }

  test('v20 -> v21 repairs corrupted names and keeps clean ones', () async {
    await seedCorruptedRows();

    await AppDatabase.upgradeSchema(db, 20, 21);

    expect(await nameOf('booking_resources', 'res-1'), 'Основной');
    expect(await nameOf('accounts', 'acc-1'), 'Наличные');
    // Clean Cyrillic must survive byte-for-byte.
    expect(await nameOf('clients', 'cli-1'), 'Иван Петров');

    final appointment = await db.query(
      'appointments',
      columns: ['title'],
      where: 'id = ?',
      whereArgs: ['apt-1'],
    );
    expect(appointment.first['title'], 'Основной');
  });

  test('repair leaves no audit noise and queues sync for changed rows', () async {
    await seedCorruptedRows();
    await db.delete('sync_outbox');
    await db.delete('audit_log');

    await AppDatabase.upgradeSchema(db, 20, 21);

    final auditRows = await db.query('audit_log');
    expect(auditRows, isEmpty, reason: 'repair must not write audit entries');

    final queued = (await db.query(
      'sync_outbox',
      columns: ['table_name'],
    )).map((row) => row['table_name'] as String).toSet();
    expect(queued, contains('booking_resources'));
    expect(queued, contains('accounts'));
    expect(queued, isNot(contains('clients')), reason: 'clean row untouched');
  });

  test('running the repair again changes nothing', () async {
    await seedCorruptedRows();
    await AppDatabase.upgradeSchema(db, 20, 21);
    await db.delete('sync_outbox');

    final changed = await AppDatabase.repairStoredMojibake(db);

    expect(changed, 0);
    expect(await db.query('sync_outbox'), isEmpty);
    expect(await nameOf('booking_resources', 'res-1'), 'Основной');
  });

  test('audit and sync triggers survive the repair', () async {
    await seedCorruptedRows();
    await AppDatabase.upgradeSchema(db, 20, 21);

    final triggers = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger'",
    )).map((row) => row['name'] as String).toSet();
    for (final name in [
      'audit_clients_insert',
      'audit_clients_update',
      'audit_money_transactions_update',
      'sync_out_clients_update',
      'sync_out_booking_resources_update',
    ]) {
      expect(triggers.contains(name), isTrue, reason: 'missing $name');
    }

    // Audit still records user edits after the repair.
    await db.update(
      'clients',
      {'name': 'Иван Петрович'},
      where: 'id = ?',
      whereArgs: ['cli-1'],
    );
    final audit = await db.query(
      'audit_log',
      where: 'entity = ?',
      whereArgs: ['clients'],
    );
    expect(audit, isNotEmpty);
  });

  test('integrity stays ok after the repair', () async {
    await seedCorruptedRows();
    await AppDatabase.upgradeSchema(db, 20, 21);

    final integrity = (await db.rawQuery('PRAGMA integrity_check'))
        .first
        .values
        .first
        .toString();
    expect(integrity.toLowerCase(), 'ok');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('rows pulled from the server are cleaned before they are stored', () async {
    final remotePath = p.join(tempDir.path, 'remote.db');
    final remote = await AppDatabase.open(path: remotePath);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final result = await remote.applySyncRows([
        SyncRow(
          table: 'booking_resources',
          id: 'res-remote',
          updatedAt: now,
          deviceId: 'other-device',
          deleted: false,
          data: <String, Object?>{
            'id': 'res-remote',
            'name': brokenResource,
            'color': '#007AFF',
            'archived': 0,
            'created_at': now,
          },
        ),
        SyncRow(
          table: 'clients',
          id: 'cli-remote',
          updatedAt: now,
          deviceId: 'other-device',
          deleted: false,
          data: <String, Object?>{
            'id': 'cli-remote',
            'name': 'Иван Петров',
            'phone': '',
            'created_at': now,
            'updated_at': now,
          },
        ),
      ]);

      expect(result.applied, 2);
      final rows = await remote.database.query(
        'booking_resources',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: ['res-remote'],
      );
      expect(rows.single['name'], 'Основной');
      final clean = await remote.database.query(
        'clients',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: ['cli-remote'],
      );
      expect(clean.single['name'], 'Иван Петров');
    } finally {
      await remote.close();
    }
  });
}
