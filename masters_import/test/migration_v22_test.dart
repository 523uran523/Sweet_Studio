// ignore_for_file: prefer_const_constructors
// Миграция v21 -> v24 «фундамент»: аддитивные колонки, новые таблицы,
// разовый бэкфилл обязательств и себестоимости движений склада,
// хотфикс-колонки payment_method/legacy_paid, seed attribute_types.
//
// Фикстура v21.db генерируется `migration_fixture_test.dart`.

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
    tempDir = await Directory.systemTemp.createTemp('migration_v22_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Копия фикстуры v21 с демо-данными для проверки бэкфилла.
  Future<String> prepareV21WithData() async {
    final fixture = File(
      p.join(Directory.current.path, 'test', 'fixtures', 'dbs', 'v21.db'),
    );
    expect(
      fixture.existsSync(),
      isTrue,
      reason: 'Нет test/fixtures/dbs/v21.db — прогоните migration_fixture_test.',
    );
    final path = p.join(tempDir.path, 'v21.db');
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
    await db.insert('suppliers', {
      'id': 's1',
      'name': 'Поставщик',
      'phone': '',
      'created_at': now,
    });
    await db.insert('accounts', {
      'id': 'a1',
      'name': 'Касса',
      'type': 'cash',
      'created_at': now,
    });
    // Заказ 1000 ₽, оплачено 400 ₽ → дебиторка 600 ₽.
    await db.insert('jobs', {
      'id': 'j1',
      'client_id': 'c1',
      'title': 'Торт',
      'status': 'new',
      'price_cents': 100000,
      'cost_cents': 30000,
      'due_date': now + 86400000,
      'created_at': now,
      'updated_at': now,
    });
    // Заказ без оплаты и без цены — обязательство не создаётся.
    await db.insert('jobs', {
      'id': 'j2',
      'client_id': 'c1',
      'title': 'Без цены',
      'status': 'new',
      'price_cents': 0,
      'cost_cents': 0,
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
    // legacy-платёж: клиент c2 оплатил заказ j3 полностью без job_id.
    // Бэкап должен создать клиента, заказ и общий платёж (job_id=NULL).
    await db.insert('clients', {
      'id': 'c2',
      'name': 'Клиент с legacy',
      'phone': '',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('jobs', {
      'id': 'j3',
      'client_id': 'c2',
      'title': 'Капкейки',
      'status': 'new',
      'price_cents': 50000,
      'cost_cents': 10000,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('money_transactions', {
      'id': 't3',
      'account_id': 'a1',
      'kind': 'sale',
      'direction': 'in',
      'amount_cents': 50000,
      'client_id': 'c2',
      'job_id': null,
      'created_at': now,
    });
    // Закупка 500 ₽, оплачено 200 ₽ → кредиторка 300 ₽.
    await db.insert('purchases', {
      'id': 'p1',
      'supplier_id': 's1',
      'account_id': 'a1',
      'total_cents': 50000,
      'created_at': now,
    });
    await db.insert('money_transactions', {
      'id': 't2',
      'account_id': 'a1',
      'kind': 'purchase_payment',
      'direction': 'out',
      'amount_cents': 20000,
      'related_transaction_id': 'p1',
      'created_at': now,
    });
    // Движение склада с нулевой себестоимостью — бэкфилл подставит цену позиции.
    await db.insert('inventory_items', {
      'id': 'i1',
      'name': 'Мука',
      'kind': 'good',
      'cost_cents': 7000,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('stock_movements', {
      'id': 'm1',
      'item_id': 'i1',
      'type': 'in',
      'qty': 5,
      'created_at': now,
    });

    await db.close();
    return path;
  }

  test('v21 -> v24: колонки, таблицы, индексы, бэкфилл, хотфиксы', () async {
    final path = await prepareV21WithData();

    final db = await openDatabase(
      path,
      version: 24,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (d, from, to) => AppDatabase.upgradeSchema(d, from, to),
    );
    try {
      expect(
        (await db.rawQuery('PRAGMA user_version')).first.values.first,
        24,
        reason: 'user_version должен стать 24',
      );

      Future<Set<String>> columns(String table) async =>
          (await db.rawQuery('PRAGMA table_info($table)'))
              .map((r) => r['name'] as String)
              .toSet();

      final materialCols = await columns('materials');
      for (final column in [
        'item_id',
        'kind',
        'cost_at_order_cents',
        'discount_cents',
      ]) {
        expect(materialCols.contains(column), isTrue, reason: 'materials.$column');
      }
      final stockCols = await columns('stock_movements');
      for (final column in ['reason', 'ref_type', 'ref_id', 'location_id', 'unit_cost_cents']) {
        expect(stockCols.contains(column), isTrue, reason: 'stock_movements.$column');
      }
      expect((await columns('money_transactions')).contains('obligation_id'), isTrue);
      // Хотфикс v23: payment_method
      expect((await columns('money_transactions')).contains('payment_method'), isTrue, reason: 'money_transactions.payment_method');
      expect((await columns('obligations')).contains('payment_method'), isTrue, reason: 'obligations.payment_method');
      // legacy_paid
      expect((await columns('jobs')).contains('legacy_paid'), isTrue, reason: 'jobs.legacy_paid');
      expect((await columns('inventory_items')).contains('warranty_days'), isTrue);
      expect((await columns('job_stages')).contains('lead_hours'), isTrue);
      expect((await columns('jobs')).contains('delivered_at'), isTrue);

      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'] as String).toSet();
      for (final table in ['obligations', 'client_credits', 'entity_attributes', 'attribute_types']) {
        expect(tables.contains(table), isTrue, reason: 'нет таблицы $table');
      }
      final indexes = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      )).map((r) => r['name'] as String).toSet();
      for (final index in [
        'idx_materials_item',
        'idx_stock_moves_ref',
        'idx_oblig_due',
        'idx_oblig_job',
        'idx_oblig_counterparty',
        'idx_credits_client',
        'idx_attr_unique',
        'idx_attr_entity',
      ]) {
        expect(indexes.contains(index), isTrue, reason: 'нет индекса $index');
      }

      // Бэкфилл: дебиторка по заказу и кредиторка по закупке.
      final obligations = await db.query('obligations', orderBy: 'id');
      expect(obligations, hasLength(2), reason: 'два обязательства из истории');
      final jobObligation = obligations.firstWhere(
        (r) => r['kind'] == 'client_payment',
      );
      expect(jobObligation['direction'], 'receivable');
      expect(jobObligation['amount_cents'], 100000);
      expect(jobObligation['paid_cents'], 40000);
      expect(jobObligation['status'], 'partial');
      expect(jobObligation['job_id'], 'j1');
      expect(jobObligation['counterparty_id'], 'c1');

      // §1.2: заказ j3 оплачен общим платежом без job_id → долга нет,
      // но заказ помечен legacy_paid, чтобы UI объяснял «почему долга нет».
      expect(
        obligations.where((r) => r['job_id'] == 'j3'),
        isEmpty,
        reason: 'legacy-оплата не должна порождать ложную дебиторку',
      );
      final legacyJob = (await db.query(
        'jobs',
        where: 'id = ?',
        whereArgs: ['j3'],
      )).single;
      expect(legacyJob['legacy_paid'], 1);
      final normalJob = (await db.query(
        'jobs',
        where: 'id = ?',
        whereArgs: ['j1'],
      )).single;
      expect(normalJob['legacy_paid'], 0);

      final purchaseObligation = obligations.firstWhere(
        (r) => r['kind'] == 'supplier_bill',
      );
      expect(purchaseObligation['direction'], 'payable');
      expect(purchaseObligation['amount_cents'], 50000);
      expect(purchaseObligation['paid_cents'], 20000);
      expect(purchaseObligation['counterparty_type'], 'supplier');

      // Бэкфилл себестоимости движения.
      final movement = (await db.query(
        'stock_movements',
        where: 'id = ?',
        whereArgs: ['m1'],
      )).single;
      expect(movement['unit_cost_cents'], 7000);

      // Журнал: пакеты бэкфилла отмечены действием backup.migrate.
      final log = await db.query(
        'audit_log',
        where: 'action = ?',
        whereArgs: ['backup.migrate'],
      );
      expect(log, isNotEmpty, reason: 'бэкфилл пишет пакеты в audit_log');

      expect(
        await db.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
        reason: 'после миграции нарушений внешних ключей быть не должно',
      );
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).first.values.first,
        'ok',
      );

      // Seed attribute_types: минимум 10 записей.
      final attrTypes = await db.query('attribute_types');
      expect(attrTypes.length, greaterThanOrEqualTo(10), reason: 'seed attribute_types');
      final hasSize = attrTypes.any((r) => r['key'] == 'size');
      expect(hasSize, isTrue, reason: 'seed содержит size');
    } finally {
      await db.close();
    }
  });

  test('v23: триггеры новых таблиц из реестра, повторный бэкфилл, хотфиксы идемпотентны', () async {
    final path = await prepareV21WithData();

    final db = await openDatabase(
      path,
      version: 24,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (d, from, to) => AppDatabase.upgradeSchema(d, from, to),
    );
    try {
      final triggers = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger'",
      )).map((r) => r['name'] as String).toSet();
      for (final table in ['obligations', 'client_credits', 'entity_attributes']) {
        for (final op in ['insert', 'update', 'delete']) {
          expect(
            triggers.contains('audit_${table}_$op'),
            isTrue,
            reason: 'нет audit_${table}_$op',
          );
          expect(
            triggers.contains('sync_out_${table}_$op'),
            isTrue,
            reason: 'нет sync_out_${table}_$op',
          );
        }
      }

      // Повторный прогон шага не должен дублировать обязательства.
      final beforeObl = (await db.query('obligations')).length;
      final beforeAttr = (await db.query('attribute_types')).length;
      await AppDatabase.upgradeSchema(db, 21, 23);
      final afterObl = (await db.query('obligations')).length;
      final afterAttr = (await db.query('attribute_types')).length;
      expect(afterObl, beforeObl, reason: 'бэкфилл должен быть идемпотентным');
      expect(afterAttr, beforeAttr, reason: 'seed attribute_types идемпотентен');

      // Новая таблица попадает в очередь синхронизации через триггер.
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('obligations', {
        'id': 'o1',
        'direction': 'payable',
        'kind': 'rent',
        'title': 'Аренда',
        'amount_cents': 10000,
        'due_at': now,
        'created_at': now,
        'updated_at': now,
      });
      final queued = await db.query(
        'sync_outbox',
        where: 'table_name = ? AND row_id = ?',
        whereArgs: ['obligations', 'o1'],
      );
      expect(queued, hasLength(1));
    } finally {
      await db.close();
    }
  });
}
