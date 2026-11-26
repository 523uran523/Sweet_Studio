import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import '../lib/data/app_database.dart';
import '../lib/state/masters_store.dart';
import '../lib/state/settings_controller.dart';

Future<MastersStore> _openStore(String dbPath) async {
  final appDb = await AppDatabase.open(path: dbPath);
  final settings = await SettingsController.load();
  final store = MastersStore(appDb, settings);
  await store.load();
  return store;
}

void main() {
  late Directory dir;
  late String dbPath;
  final List<AppDatabase> _dbs = <AppDatabase>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('masters_calc_state_test');
    dbPath = p.join(dir.path, 'calc_state.db');
  });

  tearDownAll(() async {
    for (final db in _dbs) {
      try {
        await db.close();
      } catch (_) {}
    }
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<AppDatabase> _trackedDb() async {
    final db = await AppDatabase.open(path: dbPath);
    _dbs.add(db);
    return db;
  }

  /// Минимальная строка jobs (FK на clients), необходимая для UPDATE колонки.
  Future<void> _ensureJob(String jobId) async {
    final db = await _trackedDb();
    try {
      await db.database.insert('clients', {
        'id': 'c-$jobId',
        'name': 'Клиент',
        'phone': '',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.database.insert('jobs', {
        'id': jobId,
        'client_id': 'c-$jobId',
        'title': 'Работа',
        'status': 'new',
        'priority': 'medium',
        'price_cents': 0,
        'cost_cents': 0,
        'tags': '',
        'created_at': 1,
        'updated_at': 1,
      });
    } finally {
      await db.close();
    }
  }

  test('состояние калькулятора сохраняется по jobId и восстанавливается', () async {
    const jobId = 'job-calc-1';
    const state = '{"schema":1,"resources":[{"name":"Кирпич","qty":"10","qtyUnit":"шт","price":"45","priceUnit":"за шт"}]}';

    await _ensureJob(jobId);

    final store = await _openStore(dbPath);

    // Другая задача — пусто.
    expect(await store.calculatorStateForJob('job-other'), isNull);

    // Дебаунс: значение сразу доступно из памяти.
    store.saveCalculatorState(jobId, state);
    expect(await store.calculatorStateForJob(jobId), state);

    // Форсированная запись в БД.
    await store.flushCalculatorState(jobId);

    // Прямая проверка колонки jobs.calculator_state через новое соединение.
    final checkDb = await _trackedDb();
    try {
      final rows = await checkDb.database.query(
        'jobs',
        columns: ['calculator_state'],
        where: 'id = ?',
        whereArgs: [jobId],
      );
      expect(rows.isNotEmpty, isTrue, reason: 'job row missing');
      expect(rows.first['calculator_state'], state);
    } finally {
      await checkDb.close();
    }

    // Новое хранилище на той же БД читает состояние из БД.
    final store2 = await _openStore(dbPath);
    expect(await store2.calculatorStateForJob(jobId), state);

    // Перезапись: побеждает последнее значение.
    store2.saveCalculatorState(jobId, '{"schema":1}');
    store2.saveCalculatorState(jobId, '{"schema":1,"resources":[]}');
    await store2.flushCalculatorState(jobId);
    expect(await store2.calculatorStateForJob(jobId), '{"schema":1,"resources":[]}');
    final checkDb2 = await _trackedDb();
    try {
      final rows = await checkDb2.database.query(
        'jobs',
        columns: ['calculator_state'],
        where: 'id = ?',
        whereArgs: [jobId],
      );
      expect(rows.first['calculator_state'], '{"schema":1,"resources":[]}');
    } finally {
      await checkDb2.close();
    }
  });

  test('состояние попадает в БД через дебаунс без flush', () async {
    const jobId = 'job-calc-2';
    await _ensureJob(jobId);
    final store = await _openStore(dbPath);

    store.saveCalculatorState(jobId, '{"schema":1}');
    expect(await store.calculatorStateForJob(jobId), '{"schema":1}');

    await Future.delayed(const Duration(milliseconds: 600));

    final store2 = await _openStore(dbPath);
    expect(await store2.calculatorStateForJob(jobId), '{"schema":1}');
  });
}
