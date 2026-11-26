// ignore_for_file: prefer_const_constructors
/// §1.1: автобэкап перед миграцией v22 + автовосстановление при падении.
///
/// Проверяет, что перед миграцией «фундамента» создаётся копия файла БД,
/// а сбой миграции не оставляет пользователя на полуобновлённой схеме:
/// база поднимается из копии, `user_version` остаётся прежним, данные целы.
///
/// Фикстура v21.db генерируется `migration_fixture_test.dart`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('migration_v22_rb_');
    // path_provider недоступен в unit-тестах — задаём директорию бэкапов явно.
    AppDatabase.backupsDirectoryOverride = tempDir.path;
  });

  tearDown(() async {
    AppDatabase.backupsDirectoryOverride = null;
    AppDatabase.testHaltHook = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Копия фикстуры v21 с клиентом, счётом, заказом и оплатой.
  Future<String> prepareV21WithData() async {
    final fixture = File(
      p.join(Directory.current.path, 'test', 'fixtures', 'dbs', 'v21.db'),
    );
    expect(
      fixture.existsSync(),
      isTrue,
      reason: 'Нет test/fixtures/dbs/v21.db — прогоните migration_fixture_test.',
    );
    final path = p.join(tempDir.path, 'masters.db');
    await fixture.copy(path);

    final db = await openDatabase(
      path,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert('clients', {
      'id': 'c1',
      'name': 'Клиент',
      'phone': '',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('accounts', {
      'id': 'a1',
      'name': 'Касса',
      'type': 'cash',
      'created_at': now,
    });
    await db.insert('jobs', {
      'id': 'j1',
      'client_id': 'c1',
      'title': 'Торт',
      'status': 'new',
      'price_cents': 100000,
      'cost_cents': 30000,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('money_transactions', {
      'id': 't1',
      'account_id': 'a1',
      'kind': 'client_payment',
      'direction': 'in',
      'amount_cents': 40000,
      'client_id': 'c1',
      'job_id': 'j1',
      'created_at': now,
    });

    await db.close();
    return path;
  }

  List<File> backupCopies() {
    final dir = Directory(p.join(tempDir.path, 'backups'));
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('pre_v22_'))
        .toList();
  }

  test('v21 -> v25: перед миграцией создаётся копия и помечается мигрированной',
      () async {
    final path = await prepareV21WithData();

    final app = await AppDatabase.open(path: path);
    try {
      expect(app.migrationHalted, isFalse);
      expect(
        (await app.database.rawQuery('PRAGMA user_version')).first.values.first,
        26,
      );
    } finally {
      await app.database.close();
    }

    final copies = backupCopies();
    expect(copies, hasLength(1), reason: 'одна копия на одну миграцию');
    expect(
      p.basename(copies.single.path),
      contains('.migrated.'),
      reason: 'после успешной миграции копия помечается .migrated.',
    );
  });

  test('база v25 открывается без создания копии', () async {
    final path = await prepareV21WithData();

    final first = await AppDatabase.open(path: path);
    await first.database.close();

    final second = await AppDatabase.open(path: path);
    try {
      expect(second.migrationHalted, isFalse);
      expect(
        (await second.database.rawQuery('PRAGMA user_version')).first.values.first,
        26,
      );
    } finally {
      await second.database.close();
    }

    // Копия осталась ровно одна — повторное открытие её не плодит.
    expect(backupCopies(), hasLength(1));
  });

  test('падение миграции: данные целы, версия прежняя, показывается алерт',
      () async {
    final path = await prepareV21WithData();

    // Роняем миграцию на том же месте, где роняет её foreign_key_check, —
    // то есть после бэкапа и бэкфилла, но до фиксации user_version.
    AppDatabase.testHaltHook = (int oldVersion) {
      throw StateError('v22: миграция прервана тестом (oldVersion=$oldVersion)');
    };

    final app = await AppDatabase.open(path: path);
    try {
      expect(
        app.migrationHalted,
        isTrue,
        reason: 'open() должен сообщить, что миграция не прошла',
      );

      final version =
          (await app.database.rawQuery('PRAGMA user_version')).first.values.first;
      expect(version, 21, reason: 'версия обязана остаться прежней');

      // Данные не потеряны и не «дочинены» наполовину.
      final jobs = await app.database.query('jobs');
      expect(jobs, hasLength(1));
      expect(jobs.single['title'], 'Торт');
      final transactions = await app.database.query('money_transactions');
      expect(transactions, hasLength(1));

      // Полуобновлённой схемы нет: таблиц v22 быть не должно.
      final tables = (await app.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'] as String).toSet();
      expect(tables.contains('obligations'), isFalse);
      expect(tables.contains('attribute_types'), isFalse);

      expect(
        await app.database.rawQuery('PRAGMA integrity_check'),
        isNotEmpty,
      );
    } finally {
      await app.database.close();
    }

    expect(backupCopies(), hasLength(1), reason: 'копия создана до падения');
    expect(
      p.basename(backupCopies().single.path),
      isNot(contains('.migrated.')),
      reason: 'неуспешная миграция не помечает копию',
    );
  });

  test('после успешного повторного запуска миграция доходит до v25', () async {
    final path = await prepareV21WithData();

    AppDatabase.testHaltHook = (_) => throw StateError('падение 1');
    final failed = await AppDatabase.open(path: path);
    expect(failed.migrationHalted, isTrue);
    await failed.database.close();
    AppDatabase.testHaltHook = null;

    // Следующий запуск: та же база, миграция больше не падает.
    final fixed = await AppDatabase.open(path: path);
    try {
      expect(fixed.migrationHalted, isFalse);
      expect(
        (await fixed.database.rawQuery('PRAGMA user_version')).first.values.first,
        26,
      );
      final jobs = await fixed.database.query('jobs');
      expect(jobs, hasLength(1), reason: 'данные пережили падение и миграцию');
      // Бэкфилл отработал: заказ 100000, оплачено 40000 → дебиторка.
      final obligations = await fixed.database.query('obligations');
      expect(obligations, hasLength(1));
      expect(obligations.single['amount_cents'], 100000);
      expect(obligations.single['paid_cents'], 40000);
    } finally {
      await fixed.database.close();
    }
  });
}
