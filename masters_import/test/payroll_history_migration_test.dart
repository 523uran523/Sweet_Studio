// v26 «история начислений»: миграция v25 → v26 на настоящей копии базы.
//
// Проверяет план `docs/specs/2026-11-16-payroll-history-v26-migration.md`:
// - чистая установка v26 получает таблицы, индексы и аудит-триггеры;
// - переход с заполненной v25 переносит данные, закрытый период становится
//   preliminary-ведомостью v1 с пересчётом по текущим условиям, открытый
//   период ведомости не получает;
// - миграция идемпотентна и восстанавливается из pre_v26_ копии при сбое;
// - круг бэкапа: export → очистка новых таблиц → restore.
//
// Фикстура v21.db генерируется `migration_fixture_test.dart`; до v25 база
// догоняется текущим кодом через `AppDatabase.upgradeSchema`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('payroll_history_');
    AppDatabase.backupsDirectoryOverride = tempDir.path;
  });

  tearDown(() async {
    AppDatabase.backupsDirectoryOverride = null;
    AppDatabase.testHaltHook = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Собирает заполненную v25: фикстура v21 догоняется до схемы 25, затем
  /// добавляются сотрудники, табель, заказы, выплаты и два периода
  /// (один закрытый, один открытый).
  Future<String> prepareV25WithData() async {
    final fixture = File(
      p.join(Directory.current.path, 'test', 'fixtures', 'dbs', 'v21.db'),
    );
    expect(
      fixture.existsSync(),
      isTrue,
      reason:
          'Нет test/fixtures/dbs/v21.db — прогоните migration_fixture_test.',
    );
    final path = p.join(tempDir.path, 'masters.db');
    await fixture.copy(path);

    // До v25 базу догоняем текущим кодом, без обёртки AppDatabase.open —
    // нужно состояние именно v25 с пользовательскими данными.
    final v25 = await openDatabase(
      path,
      version: 25,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await AppDatabase.upgradeSchema(db, oldVersion, newVersion);
      },
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final d = DateTime.utc;
    await v25.insert('clients', {
      'id': 'c1',
      'name': 'Клиент Тест',
      'phone': '+7 900 000-00-00',
      'created_at': now,
      'updated_at': now,
    });
    await v25.insert('employees', {
      'id': 'e-hourly',
      'name': 'Иван Почасовой',
      'pay_type': 'hourly',
      'rate_cents': 50000,
      'percent': 0,
      'created_at': d(2024, 1, 10).millisecondsSinceEpoch,
    });
    await v25.insert('employees', {
      'id': 'e-piece',
      'name': 'Пётр Сдельный',
      'pay_type': 'piece',
      'rate_cents': 30000,
      'percent': 0,
      'created_at': d(2024, 2, 10).millisecondsSinceEpoch,
    });
    await v25.insert('employees', {
      'id': 'e-percent',
      'name': 'Сергей Процентный',
      'pay_type': 'percent',
      'rate_cents': 0,
      'percent': 10,
      'created_at': d(2024, 3, 10).millisecondsSinceEpoch,
    });

    // Табель Июня 2025 + одна запись вне периода.
    Future<void> insertTime(
      String id,
      String empId,
      DateTime started,
      int minutes,
    ) => v25.insert('time_entries', {
      'id': id,
      'employee_id': empId,
      'job_id': null,
      'started_at': started.millisecondsSinceEpoch,
      'minutes': minutes,
      'created_at': now,
    });
    await insertTime('t1', 'e-hourly', DateTime(2025, 6, 10, 9), 120);
    await insertTime('t2', 'e-hourly', DateTime(2025, 6, 12, 9), 60);
    await insertTime('t3', 'e-hourly', DateTime(2025, 1, 10, 9), 300);

    // Заказы: один сдельный (Пётр), один процентный (Сергей), один новый
    // и один архивный — оба в начисление не попадают.
    Future<void> insertJob(
      String id,
      String assignee,
      String status,
      int priceCents,
      int archived,
      DateTime doneAt,
    ) => v25.insert('jobs', {
      'id': id,
      'client_id': 'c1',
      'title': 'Заказ $id',
      'status': status,
      'price_cents': priceCents,
      'archived': archived,
      'assignee_id': assignee,
      'finished_at': doneAt.millisecondsSinceEpoch,
      'updated_at': doneAt.millisecondsSinceEpoch,
      'created_at': now,
    });
    await insertJob(
      'j-piece',
      'e-piece',
      'done',
      100000,
      0,
      DateTime(2025, 6, 20),
    );
    await insertJob(
      'j-percent',
      'e-percent',
      'closed',
      200000,
      0,
      DateTime(2025, 6, 25),
    );
    await insertJob(
      'j-new',
      'e-piece',
      'new',
      100000,
      0,
      DateTime(2025, 6, 21),
    );
    await insertJob(
      'j-archived',
      'e-piece',
      'done',
      100000,
      1,
      DateTime(2025, 6, 22),
    );

    // Выплаты Ивана в июне + одна вне периода.
    Future<void> insertPayment(
      String id,
      String type,
      int amount,
      DateTime at,
    ) => v25.insert('employee_payments', {
      'id': id,
      'employee_id': 'e-hourly',
      'type': type,
      'amount_cents': amount,
      'created_at': at.millisecondsSinceEpoch,
    });
    await insertPayment('pay-bonus', 'bonus', 10000, DateTime(2025, 6, 28));
    await insertPayment('pay-advance', 'advance', 5000, DateTime(2025, 6, 28));
    await insertPayment('pay-payout', 'payout', 7000, DateTime(2025, 6, 28));
    await insertPayment('pay-outside', 'advance', 99900, DateTime(2025, 3, 1));

    // Июнь — закрытый, июль — открытый.
    await v25.insert('payroll_periods', {
      'id': 'p-june',
      'name': 'Июнь 2025',
      'start_at': DateTime(2025, 6, 1).millisecondsSinceEpoch,
      'end_at': DateTime(2025, 6, 30, 23, 59, 59).millisecondsSinceEpoch,
      'closed_at': DateTime(2025, 7, 5).millisecondsSinceEpoch,
      'created_at': now,
      'updated_at': now,
    });
    await v25.insert('payroll_periods', {
      'id': 'p-july',
      'name': 'Июль 2025',
      'start_at': DateTime(2025, 7, 1).millisecondsSinceEpoch,
      'end_at': DateTime(2025, 7, 31, 23, 59, 59).millisecondsSinceEpoch,
      'closed_at': null,
      'created_at': now,
      'updated_at': now,
    });

    await v25.close();
    return path;
  }

  test('чистая v26: таблицы, уникальные индексы, аудит, бэкап', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final db = appDb.database;
      expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 26);

      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'] as String).toSet();
      expect(
        tables,
        containsAll(['pay_conditions', 'payslips', 'accrual_entries']),
      );

      final indexes = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      )).map((r) => r['name'] as String).toSet();
      expect(indexes, contains('uq_pay_conditions_emp_from'));
      expect(indexes, contains('uq_payslips_period_emp_version'));
      expect(indexes, contains('uq_accrual_entries_source'));

      // Аудиторские триггеры для новых таблиц существуют и пишут журнал.
      final triggers = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger'",
      )).map((r) => r['name'] as String).toSet();
      expect(
        triggers,
        containsAll([
          'audit_pay_conditions_insert',
          'audit_payslips_insert',
          'audit_accrual_entries_insert',
        ]),
      );

      await db.insert('employees', {
        'id': 'e-audit',
        'name': 'Аудитор Тест',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await db.insert('pay_conditions', {
        'id': 'cond-audit',
        'employee_id': 'e-audit',
        'pay_type': 'hourly',
        'rate_cents': 10000,
        'percent': 0,
        'valid_from': DateTime.now().millisecondsSinceEpoch,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final audit = await db.query(
        'audit_log',
        where: "entity = 'pay_conditions'",
      );
      expect(audit, isNotEmpty);

      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();
      final backup = store.backupData();
      expect(backup['version'], 10);
      expect(backup.containsKey('pay_conditions'), isTrue);
      expect(backup.containsKey('payslips'), isTrue);
      expect(backup.containsKey('accrual_entries'), isTrue);
    } finally {
      await appDb.close();
    }
  });

  test(
    'v25 → v26: данные сохранились, закрытый период — preliminary v1',
    () async {
      final path = await prepareV25WithData();

      final appDb = await AppDatabase.open(path: path);
      try {
        expect(appDb.migrationHalted, isFalse);
        expect(
          (await appDb.database.rawQuery('PRAGMA user_version'))
              .first
              .values
              .first,
          26,
        );

        // Исходные данные на месте.
        final clients = await appDb.database.query('clients');
        expect(clients, hasLength(1));
        final jobs = await appDb.database.query('jobs');
        expect(jobs, hasLength(4));
        final periods = await appDb.database.query('payroll_periods');
        expect(periods, hasLength(2));
        final payments = await appDb.database.query('employee_payments');
        expect(payments, hasLength(4));
        expect(
          await appDb.database.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );

        // По одной строке условий на сотрудника, valid_from = created_at.
        final conditions = await appDb.database.query(
          'pay_conditions',
          orderBy: 'employee_id',
        );
        expect(conditions, hasLength(3));
        for (final row in conditions) {
          final emp = await appDb.database.query(
            'employees',
            where: 'id = ?',
            whereArgs: [row['employee_id']],
          );
          expect(
            row['valid_from'],
            emp.single['created_at'],
            reason: 'valid_from обязан совпасть с created_at карточки',
          );
        }

        // Закрытый период: ведомости preliminary v1 с пересчётом по текущим
        // условиям. Открытый период — без ведомостей.
        final payslips = await appDb.database.query(
          'payslips',
          orderBy: 'employee_id',
        );
        expect(payslips, hasLength(3));
        final byEmployee = {
          for (final row in payslips) row['employee_id'] as String: row,
        };

        final hourly = byEmployee['e-hourly']!;
        expect(hourly['version'], 1);
        expect(hourly['status'], 'preliminary');
        expect(hourly['needs_review'], 1);
        expect(hourly['minutes'], 180);
        expect(hourly['accrued_cents'], 150000); // 180 мин × 500 ₽/ч
        expect(hourly['bonus_cents'], 10000);
        expect(hourly['advance_cents'], 5000);
        expect(hourly['payout_cents'], 7000);
        expect(hourly['net_cents'], 148000);

        final piece = byEmployee['e-piece']!;
        expect(piece['accrued_cents'], 30000); // 1 завершённый заказ × 300 ₽
        expect(piece['minutes'], 0);

        final percent = byEmployee['e-percent']!;
        expect(percent['accrued_cents'], 20000); // 200 000 × 10 %

        for (final row in payslips) {
          expect(row['period_id'], 'p-june');
        }
        final julyRows = await appDb.database.query(
          'payslips',
          where: 'period_id = ?',
          whereArgs: ['p-july'],
        );
        expect(julyRows, isEmpty);

        // Строки начислений восстанавливаются из источников закрытого периода,
        // вне периода записи не попадают.
        final accruals = await appDb.database.query(
          'accrual_entries',
          orderBy: 'source_kind, source_id, accrual_kind',
        );
        expect(accruals, hasLength(4));
        final total = accruals.fold<int>(
          0,
          (s, r) => s + (r['amount_cents'] as num).toInt(),
        );
        expect(total, 200000); // 150 000 + 30 000 + 20 000
        for (final row in accruals) {
          expect(row['needs_review'], 1);
          expect(row['payslip_id'], isNotNull);
        }
        final hourlyEntries = accruals
            .where((r) => r['accrual_kind'] == 'hourly')
            .toList();
        expect(hourlyEntries.map((r) => r['source_id']), ['t1', 't2']);

        // Идемпотентность: повторный проход v26 не дублирует строки.
        await AppDatabase.upgradeSchema(appDb.database, 25, 26);
        expect(await appDb.database.query('pay_conditions'), hasLength(3));
        expect(await appDb.database.query('payslips'), hasLength(3));
        expect(await appDb.database.query('accrual_entries'), hasLength(4));
      } finally {
        await appDb.close();
      }
    },
  );

  test(
    'сбой миграции: восстановление из pre_v26_, версия и данные целы',
    () async {
      final path = await prepareV25WithData();

      AppDatabase.testHaltHook = (int oldVersion) {
        throw StateError(
          'v26: миграция прервана тестом (oldVersion=$oldVersion)',
        );
      };

      final app = await AppDatabase.open(path: path);
      try {
        expect(app.migrationHalted, isTrue);
        expect(
          (await app.database.rawQuery('PRAGMA user_version'))
              .first
              .values
              .first,
          25,
          reason: 'версия обязана остаться прежней',
        );
        // Данные на месте, схемы v26 нет.
        expect(await app.database.query('clients'), hasLength(1));
        expect(await app.database.query('jobs'), hasLength(4));
        final tables = (await app.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'",
        )).map((r) => r['name'] as String).toSet();
        expect(tables.contains('payslips'), isFalse);
        expect(tables.contains('pay_conditions'), isFalse);
        expect(tables.contains('accrual_entries'), isFalse);

        // store.load() не должен падать на отсутствующих таблицах v26 —
        // иначе алерт «требуется восстановление» не дойдёт до пользователя.
        final settings = await SettingsController.load();
        final store = MastersStore(app, settings);
        await store.load();
        expect(store.payslips, isEmpty);
        expect(store.payConditions, isEmpty);
        expect(store.accrualEntriesForEmployee('e-hourly'), isEmpty);
      } finally {
        await app.database.close();
      }

      final backups = Directory(p.join(tempDir.path, 'backups'));
      final copies = backups
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('pre_v26_'))
          .toList();
      expect(copies, hasLength(1), reason: 'копия создана до падения');
      expect(p.basename(copies.single.path), isNot(contains('.migrated.')));
    },
  );

  test('круг бэкапа: export → очистка новых таблиц → restore', () async {
    final path = await prepareV25WithData();

    final appDb = await AppDatabase.open(path: path);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final backup = store.backupData();
      expect(backup['version'], 10);
      expect((backup['pay_conditions'] as List).length, 3);
      expect((backup['payslips'] as List).length, 3);
      expect((backup['accrual_entries'] as List).length, 4);

      // Стираем новые таблицы в неправильном порядке (как на устройстве
      // после ручного вмешательства) и восстанавливаем из копии.
      await appDb.database.delete('accrual_entries');
      await appDb.database.delete('payslips');
      await appDb.database.delete('pay_conditions');

      await store.restoreFromBackup(backup);

      expect(await appDb.database.query('pay_conditions'), hasLength(3));
      expect(await appDb.database.query('payslips'), hasLength(3));
      expect(await appDb.database.query('accrual_entries'), hasLength(4));
      expect(
        await appDb.database.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      // Геттеры store видят восстановленные строки.
      expect(store.payslips, hasLength(3));
      expect(store.payConditions, hasLength(3));
      expect(store.accrualEntriesForEmployee('e-hourly'), hasLength(2));
    } finally {
      await appDb.close();
    }
  });
}
