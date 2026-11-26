import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';

/// Audit-триггеры строятся по фактическим колонкам таблицы, поэтому перед
/// `DROP COLUMN` их нужно снять: SQLite не даёт удалить колонку, на которую
/// ссылается триггер. При обновлении схемы триггеры создаются заново.
Future<void> _dropTriggersOf(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name = ?",
    [table],
  );
  for (final row in rows) {
    await db.execute('DROP TRIGGER IF EXISTS ${row['name']}');
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() {
    // no-op
  });

  test('loads database and store without errors', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();
      expect(store.isLoaded, isTrue);
      expect(store.clients, isEmpty);
      expect(store.employees.length, 1);
      expect(store.selfEmployee?.name, 'Я');
      final ver = (await appDb.database.rawQuery(
        'PRAGMA user_version',
      ))[0]['user_version'];
      expect(ver, 26);
    } finally {
      await appDb.close();
    }
  });

  test('schema v22 contains expected core tables and triggers', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final db = appDb.database;
      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'] as String).toSet();
      for (final t in [
        'clients',
        'jobs',
        'job_attachments',
        'money_transactions',
        'employees',
        'recurring_payments',
        'audit_log',
        'period_closures',
        'work_sessions',
        'sync_outbox',
      ]) {
        expect(tables.contains(t), isTrue, reason: 'missing table $t');
      }
      final triggers = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger'",
      )).map((r) => r['name'] as String).toSet();
      for (final t in ['clients', 'jobs', 'money_transactions']) {
        for (final op in ['insert', 'update', 'delete']) {
          final name = 'sync_out_${t}_$op';
          expect(triggers.contains(name), isTrue, reason: 'missing $name');
        }
      }
      final jobCols = (await db.rawQuery('PRAGMA table_info(jobs)'))
          .map((r) => r['name'] as String)
          .toSet();
      expect(jobCols.contains('pinned'), isTrue, reason: 'missing jobs.pinned');
      expect(
        jobCols.contains('calculator_state'),
        isTrue,
        reason: 'missing jobs.calculator_state',
      );

      final version = (await db.rawQuery(
        'PRAGMA user_version',
      ))[0]['user_version'];
      expect(version, 26);
    } finally {
      await appDb.close();
    }
  });

  test(
    'migrates v14 database to v22 (calculator_state + work_sessions + sync)',
    () async {
      // Create a fresh database at the new version, then rewind it to v14
      // (drop the new column and user_version) to simulate an existing v14 db.
      final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        final db = appDb.database;
        await _dropTriggersOf(db, 'jobs');
        await db.execute('ALTER TABLE jobs DROP COLUMN calculator_state');
        await db.execute('PRAGMA user_version = 14');
      } finally {
        await appDb.close();
      }

      // Reopening must run the full upgrade chain and restore the column.
      final reopened = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        final ver = (await reopened.database.rawQuery(
          'PRAGMA user_version',
        ))[0]['user_version'];
        expect(ver, 26);
        final cols = (await reopened.database.rawQuery(
          'PRAGMA table_info(jobs)',
        )).map((r) => r['name'] as String).toSet();
        expect(cols.contains('calculator_state'), isTrue);
        final tables = (await reopened.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        )).map((r) => r['name'] as String).toSet();
        expect(tables.contains('work_sessions'), isTrue);
      } finally {
        await reopened.close();
      }
    },
  );

  test('creates employee and computes zero balance', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      await store.createEmployee(
        name: 'Test',
        payType: 'hourly',
        rateCents: 1000,
      );
      expect(store.employees.length, 2);
      final employee = store.employees.firstWhere((e) => e.name == 'Test');
      expect(store.earnedCents(employee.id), 0);
      expect(store.employeeBalanceOwed(employee.id), 0);
    } finally {
      await appDb.close();
    }
  });

  test('migrates v11 database to v22 (job_attachments + calculator_state + work_sessions + sync)', () async {
    final dbPath = p.join(
      Directory.systemTemp.path,
      'masters_migration_test.db',
    );
    try {
      await File(dbPath).delete();
    } catch (_) {}
    final db11 = await AppDatabase.open(path: dbPath);
    final raw = db11.database;
    await raw.execute('DROP TABLE IF EXISTS job_attachments');
    await raw.execute('PRAGMA user_version = 11');
    await db11.close();

    final db12 = await AppDatabase.open(path: dbPath);
    try {
      final tables = (await db12.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'] as String).toSet();
      expect(tables.contains('job_attachments'), isTrue);
      final ver = (await db12.database.rawQuery(
        'PRAGMA user_version',
      ))[0]['user_version'];
      expect(ver, 26);
    } finally {
      await db12.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    }
  });

  test(
    'migrates v13 database to v22 (pinned + calculator_state + work_sessions + sync)',
    () async {
      final dbPath = p.join(
        Directory.systemTemp.path,
        'masters_migration_v14_test.db',
      );
      try {
        await File(dbPath).delete();
      } catch (_) {}
      final db14 = await AppDatabase.open(path: dbPath);
      final raw = db14.database;
      try {
        await raw.execute('ALTER TABLE jobs DROP COLUMN pinned');
      } catch (_) {}
      await raw.execute('PRAGMA user_version = 13');
      await db14.close();

      final db = await AppDatabase.open(path: dbPath);
      try {
        final cols = (await db.database.rawQuery('PRAGMA table_info(jobs)'))
            .map((r) => r['name'] as String)
            .toSet();
        expect(cols.contains('pinned'), isTrue, reason: 'missing jobs.pinned');
        expect(
          cols.contains('calculator_state'),
          isTrue,
          reason: 'missing jobs.calculator_state',
        );
        final ver = (await db.database.rawQuery(
          'PRAGMA user_version',
        ))[0]['user_version'];
        expect(ver, 26);
      } finally {
        await db.close();
        try {
          await File(dbPath).delete();
        } catch (_) {}
      }
    },
  );

  test('migrates v18 database to v22 (unified booking indexes + sync outbox)', () async {
    final dbPath = p.join(
      Directory.systemTemp.path,
      'masters_migration_v21_test.db',
    );
    try {
      await File(dbPath).delete();
    } catch (_) {}
    // Create a fresh db, then rewind to v18 to simulate an existing db.
    final db18 = await AppDatabase.open(path: dbPath);
    await db18.database.execute('PRAGMA user_version = 18');
    await db18.close();

    final db = await AppDatabase.open(path: dbPath);
    try {
      final ver = (await db.database.rawQuery(
        'PRAGMA user_version',
      ))[0]['user_version'];
      expect(ver, 26);
      final indexes = (await db.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      )).map((r) => r['name'] as String).toSet();
      expect(
        indexes.contains('idx_appts_start'),
        isTrue,
        reason: 'missing idx_appts_start after v21',
      );
      expect(
        indexes.contains('idx_jobs_due'),
        isTrue,
        reason: 'missing idx_jobs_due after v21',
      );
    } finally {
      await db.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    }
  });

  test('migrates v19 database to v22 (sync outbox + triggers)', () async {
    final dbPath = p.join(
      Directory.systemTemp.path,
      'masters_migration_sync_v21_test.db',
    );
    try {
      await File(dbPath).delete();
    } catch (_) {}
    // Create a fresh db, then rewind to v19 by removing the sync schema.
    final db19 = await AppDatabase.open(path: dbPath);
    final raw = db19.database;
    final triggers = await raw.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'sync_out_%'",
    );
    for (final row in triggers) {
      await raw.execute('DROP TRIGGER IF EXISTS ${row['name']}');
    }
    await raw.execute('DROP TABLE IF EXISTS sync_outbox');
    await raw.execute('PRAGMA user_version = 19');
    await db19.close();

    final db = await AppDatabase.open(path: dbPath);
    try {
      final ver = (await db.database.rawQuery(
        'PRAGMA user_version',
      ))[0]['user_version'];
      expect(ver, 26);
      final tables = (await db.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'] as String).toSet();
      expect(tables.contains('sync_outbox'), isTrue);

      // A local write must land in the outbox through the new triggers.
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.database.insert('clients', {
        'id': 'client-sync-1',
        'name': 'Sync client',
        'phone': '',
        'created_at': now,
        'updated_at': now,
      });
      final queued = await db.database.query(
        'sync_outbox',
        where: 'table_name = ? AND row_id = ?',
        whereArgs: ['clients', 'client-sync-1'],
      );
      expect(queued, hasLength(1), reason: 'insert trigger did not queue row');
    } finally {
      await db.close();
      try {
        await File(dbPath).delete();
      } catch (_) {}
    }
  });
}
