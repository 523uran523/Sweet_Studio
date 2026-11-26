// ignore_for_file: prefer_const_constructors
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Migration upgrade regression v1..v25', () {
    late String fixturesDir;
    late Directory tempDir;

    setUp(() async {
      fixturesDir = p.join(Directory.current.path, 'test', 'fixtures', 'dbs');
      tempDir = await Directory.systemTemp.createTemp('migration_upgrade_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    for (int v = 1; v <= 19; v++) {
      test('upgrades v$v fixture to v25', () async {
        final fixturePath = p.join(fixturesDir, 'v$v.db');
        final fixtureFile = File(fixturePath);
        expect(
          fixtureFile.existsSync(),
          isTrue,
          reason: 'Fixture v$v.db not found. Run migration_fixture_test first.',
        );

        final tempPath = p.join(tempDir.path, 'migration_test_v$v.db');
        final tempFile = File(tempPath);
        if (tempFile.existsSync()) await tempFile.delete();
        await fixtureFile.copy(tempPath);

        late Database db;
        try {
          db = await openDatabase(
            tempPath,
            version: 25,
            onConfigure: (database) async {
              await database.execute('PRAGMA foreign_keys = ON');
            },
            onUpgrade: (database, oldVersion, newVersion) async {
              await AppDatabase.upgradeSchema(database, oldVersion, newVersion);
            },
          );

          expect(
            (await db.rawQuery('PRAGMA user_version')).first.values.first,
            25,
            reason: 'v$v -> v25: user_version should be 25',
          );

          final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'",
          )).map((r) => r['name'] as String).toSet();

          for (final table in [
            'jobs',
            'work_sessions',
            'money_transactions',
            'inventory_compositions',
            'obligations',
            'entity_attributes',
            'attribute_types',
          ]) {
            expect(
              tables.contains(table),
              isTrue,
              reason: 'v$v -> v25: missing $table',
            );
          }

          final jobCols = (await db.rawQuery('PRAGMA table_info(jobs)'))
              .map((r) => r['name'] as String)
              .toSet();
          expect(
            jobCols.contains('pinned'),
            isTrue,
            reason: 'v$v -> v25: missing jobs.pinned',
          );
          expect(
            jobCols.contains('calculator_state'),
            isTrue,
            reason: 'v$v -> v25: missing jobs.calculator_state',
          );
          expect(
            jobCols.contains('legacy_paid'),
            isTrue,
            reason: 'v$v -> v25: missing jobs.legacy_paid',
          );

          final txCols = (await db.rawQuery(
            'PRAGMA table_info(money_transactions)',
          )).map((r) => r['name'] as String).toSet();
          expect(
            txCols.contains('reverses_id'),
            isTrue,
            reason: 'v$v -> v25: missing money_transactions.reverses_id',
          );
          expect(
            txCols.contains('payment_method'),
            isTrue,
            reason: 'v$v -> v25: missing money_transactions.payment_method',
          );
          expect(
            txCols.contains('obligation_id'),
            isTrue,
            reason: 'v$v -> v25: missing money_transactions.obligation_id',
          );

          final obligCols = (await db.rawQuery(
            'PRAGMA table_info(obligations)',
          )).map((r) => r['name'] as String).toSet();
          expect(
            obligCols.contains('payment_method'),
            isTrue,
            reason: 'v$v -> v25: missing obligations.payment_method',
          );

          expect(
            tables.contains('sync_outbox'),
            isTrue,
            reason: 'v$v -> v25: missing sync_outbox',
          );

          // Э5 (v25): склад по точкам должен появиться при апгрейде с любой
          // версии, иначе включённый флаг «Несколько точек» упрётся в
          // no such table у пользователя, который не пересоздавал БД.
          for (final table in [
            'locations',
            'stock_levels',
            'stock_batches',
            'transfers',
            'transfer_lines',
          ]) {
            expect(
              tables.contains(table),
              isTrue,
              reason: 'v$v -> v25: missing $table',
            );
          }
          final purchaseCols = (await db.rawQuery(
            'PRAGMA table_info(purchases)',
          )).map((r) => r['name'] as String).toSet();
          expect(
            purchaseCols.contains('received_at'),
            isTrue,
            reason: 'v$v -> v25: missing purchases.received_at',
          );
          final purchaseLineCols = (await db.rawQuery(
            'PRAGMA table_info(purchase_lines)',
          )).map((r) => r['name'] as String).toSet();
          expect(
            purchaseLineCols.contains('received_qty'),
            isTrue,
            reason: 'v$v -> v25: missing purchase_lines.received_qty',
          );

          // Пункт 6 чек-листа §9.1: каждая новая таблица реестра обязана попасть
          // в sync_outbox и audit_log, иначе точка у пользователя перестанет
          // синхронизироваться молча.
          final triggers = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='trigger'",
          )).map((r) => r['name'] as String).toSet();
          for (final table in [
            'locations',
            'stock_levels',
            'stock_batches',
            'transfers',
            'transfer_lines',
          ]) {
            for (final op in ['insert', 'update', 'delete']) {
              expect(
                triggers.contains('sync_out_${table}_$op'),
                isTrue,
                reason: 'v$v -> v25: missing sync_out_${table}_$op',
              );
              expect(
                triggers.contains('audit_${table}_$op'),
                isTrue,
                reason: 'v$v -> v25: missing audit_${table}_$op',
              );
            }
          }

          for (final table in ['clients', 'jobs', 'money_transactions', 'obligations']) {
            for (final op in ['insert', 'update', 'delete']) {
              final name = 'sync_out_${table}_$op';
              expect(
                triggers.contains(name),
                isTrue,
                reason: 'v$v -> v25: missing $name',
              );
            }
          }

          final indexes = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index'",
          )).map((r) => r['name'] as String).toSet();
          expect(
            indexes.contains('idx_appts_start'),
            isTrue,
            reason: 'v$v -> v25: missing idx_appts_start',
          );
          expect(
            indexes.contains('idx_jobs_due'),
            isTrue,
            reason: 'v$v -> v25: missing idx_jobs_due',
          );

          final integrity = (await db.rawQuery('PRAGMA integrity_check'))
              .first
              .values
              .first
              .toString();
          expect(
            integrity.toLowerCase(),
            'ok',
            reason: 'v$v -> v25: integrity_check failed',
          );

          final fkViolations = await db.rawQuery('PRAGMA foreign_key_check');
          expect(
            fkViolations,
            isEmpty,
            reason: 'v$v -> v25: foreign_key_check has violations',
          );
        } finally {
          try {
            await db.close();
          } catch (_) {}
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      });
    }
  });
}
