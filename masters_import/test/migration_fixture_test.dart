// ignore_for_file: prefer_const_constructors
// This file generates DB fixtures for schema versions 1..21.
// Run with: flutter test test/migration_fixture_test.dart
// Generates fixtures in test/fixtures/dbs/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';

/// Minimal v1 schema: only clients, objects, jobs, job_stages, materials.
/// This is used to generate fixtures at exact schema versions.
Future<void> createMinimalV1Schema(Database db) async {
  await db.execute('''
    CREATE TABLE clients (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      note TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE objects (
      id TEXT PRIMARY KEY,
      client_id TEXT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      address TEXT NOT NULL DEFAULT '',
      note TEXT,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_objects_client ON objects(client_id)');

  await db.execute('''
    CREATE TABLE jobs (
      id TEXT PRIMARY KEY,
      client_id TEXT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
      object_id TEXT REFERENCES objects(id) ON DELETE SET NULL,
      title TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'new',
      priority TEXT NOT NULL DEFAULT 'medium',
      price_cents INTEGER NOT NULL DEFAULT 0,
      cost_cents INTEGER NOT NULL DEFAULT 0,
      due_date INTEGER,
      started_at INTEGER,
      finished_at INTEGER,
      note TEXT,
      archived INTEGER NOT NULL DEFAULT 0,
      tags TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_jobs_client ON jobs(client_id)');
  await db.execute('CREATE INDEX idx_jobs_object ON jobs(object_id)');
  await db.execute('CREATE INDEX idx_jobs_status ON jobs(status)');
  await db.execute('CREATE INDEX idx_jobs_due ON jobs(due_date)');
  await db.execute('CREATE INDEX idx_jobs_archived ON jobs(archived)');

  await db.execute('''
    CREATE TABLE job_stages (
      id TEXT PRIMARY KEY,
      job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      done INTEGER NOT NULL DEFAULT 0,
      sort_order REAL NOT NULL DEFAULT 0
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_stages_job ON job_stages(job_id, sort_order)',
  );

  await db.execute('''
    CREATE TABLE materials (
      id TEXT PRIMARY KEY,
      job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 1,
      unit TEXT NOT NULL DEFAULT 'шт',
      price_cents INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_materials_job ON materials(job_id)');

  await db.execute('''
    CREATE TABLE work_sessions (
      id INTEGER PRIMARY KEY,
      job_id TEXT NULL,
      started_at INTEGER,
      paused_seconds INTEGER NOT NULL DEFAULT 0,
      ended_at INTEGER,
      minutes INTEGER NOT NULL DEFAULT 0,
      note TEXT
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_wsessions_job ON work_sessions(job_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_wsessions_started ON work_sessions(started_at)',
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DB schema fixtures v1..v21', () {
    late String fixturesDir;

    setUp(() async {
      fixturesDir = p.join(Directory.current.path, 'test', 'fixtures', 'dbs');
      final dir = Directory(fixturesDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    });

    // Generate fixtures for versions 1..21
    for (int v = 1; v <= 21; v++) {
      test('generates fixture v$v.db', () async {
        final dbPath = p.join(fixturesDir, 'v$v.db');
        final file = File(dbPath);

        // Existing committed fixture: verify it instead of regenerating it.
        // This keeps normal test runs (including migration_upgrade_test) race-free.
        if (await file.exists()) {
          final verifyDb = await openDatabase(dbPath);
          final version = (await verifyDb.rawQuery('PRAGMA user_version'))
              .first
              .values
              .first;
          await verifyDb.close();
          expect(version, v, reason: 'v$v.db should have user_version=$v');
          return;
        }

        // Open database at version 1 (minimal v1 schema only)
        final db = await openDatabase(
          dbPath,
          version: 1,
          onCreate: (db, version) async {
            await createMinimalV1Schema(db);
          },
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
        );

        // Run migrations incrementally: each step runs with the correct
        // oldVersion so the DB is in its proper pre-state before that step.
        if (v > 1) {
          await AppDatabase.upgradeSchema(db, 1, v);
        }

        // Set user_version to match target schema version
        await db.execute('PRAGMA user_version = $v');

        await db.close();

        // Verify fixture was created
        expect(
          await file.exists(),
          isTrue,
          reason: 'fixture v$v.db should exist',
        );

        // Verify version
        final verifyDb = await openDatabase(dbPath);
        final version = (await verifyDb.rawQuery(
          'PRAGMA user_version',
        ))[0]['user_version'];
        await verifyDb.close();

        expect(version, v, reason: 'v$v.db should have user_version=$v');
      });
    }
  });
}
