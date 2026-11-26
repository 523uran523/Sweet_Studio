import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masters/data/app_database.dart';
import 'package:masters/data/schema_tables.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDatabase> freshDb() => AppDatabase.open(path: inMemoryDatabasePath);

  Future<MastersStore> freshStore(AppDatabase appDb) async {
    final settings = await SettingsController.load();
    final store = MastersStore(appDb, settings);
    await store.load();
    return store;
  }

  test('backup covers every registry table', () async {
    final appDb = await freshDb();
    try {
      final store = await freshStore(appDb);

      final client = await store.createClient(name: 'Клиент Реестр');
      final item = await store.createInventoryItem(name: 'Материал Реестр');
      final supplier = await store.createSupplier(name: 'Поставщик Реестр');
      await store.createPurchase(
        supplierId: supplier.id,
        lines: [
          {'itemId': item.id, 'qty': 3.0, 'unitPriceCents': 1500},
        ],
      );
      final object = await store.createObject(
        clientId: client.id,
        title: 'Объект Реестр',
      );
      await store.createJob(
        clientId: client.id,
        objectId: object.id,
        title: 'Заказ Реестр',
      );

      final backup = store.backupData();
      expect(backup['format'], 'masters-backup');
      expect(backup['version'], 10);

      // Каждая таблица реестра должна быть представлена ключом в JSON.
      final existing = await appDb.existingTables();
      for (final mapping in kBackupTables) {
        expect(
          backup.containsKey(mapping.key),
          isTrue,
          reason: 'backup missing key ${mapping.key} (table ${mapping.table})',
        );
        final rows = backup[mapping.key];
        expect(rows, isA<List>(), reason: 'key ${mapping.key} is not a list');
        if (!existing.contains(mapping.table)) continue;
        // Для существующих таблиц список не должен терять строки.
        // Мы проверяем только те таблицы, в которые сами записали.
      }

      // Проверяем, что конкретные созданные записи попали в бэкап.
      final clientsRows = backup['clients'] as List;
      expect(
        clientsRows.any((r) => r['id'] == client.id),
        isTrue,
        reason: 'client not in backup',
      );
      final itemsRows = backup['inventory_items'] as List;
      expect(
        itemsRows.any((r) => r['id'] == item.id),
        isTrue,
        reason: 'inventory item not in backup',
      );
      final purchasesRows = backup['purchases'] as List;
      expect(purchasesRows, hasLength(1), reason: 'purchase not in backup');
      final purchaseLinesRows = backup['purchase_lines'] as List;
      expect(
        purchaseLinesRows,
        hasLength(1),
        reason: 'purchase line not in backup',
      );
      final stockRows = backup['stock_movements'] as List;
      expect(
        stockRows,
        hasLength(1),
        reason: 'stock movement not in backup',
      );
    } finally {
      await appDb.close();
    }
  });

  test('restore keeps rows and skip orphans', () async {
    final appDb = await freshDb();
    try {
      final store = await freshStore(appDb);

      final client = await store.createClient(name: 'Клиент Restore');
      final object = await store.createObject(
        clientId: client.id,
        title: 'Объект Restore',
      );
      await store.createJob(
        clientId: client.id,
        objectId: object.id,
        title: 'Заказ Restore',
      );

      final backup = store.backupData();

      // Портим бэкап: добавляем объект-сироту без клиента.
      final objectsRows = (backup['objects'] as List).cast<Map<String, Object?>>();
      objectsRows.add(<String, Object?>{
        'id': 'orphan-object',
        'client_id': 'missing-client',
        'title': 'Orphan Object',
        'address': '',
        'note': null,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Очищаем баз�� вручную, чтобы restore работал с пустыми таблицами.
      await appDb.database.delete('job_stages');
      await appDb.database.delete('jobs');
      await appDb.database.delete('objects');
      await appDb.database.delete('clients');
      await store.load();

      await store.restoreFromBackup(backup);

      expect(
        store.clients.any((c) => c.id == client.id),
        isTrue,
        reason: 'client lost after restore',
      );
      expect(
        store.objects.any((o) => o.id == object.id),
        isTrue,
        reason: 'object lost after restore',
      );
      expect(
        store.objects.any((o) => o.id == 'orphan-object'),
        isFalse,
        reason: 'orphan object restored',
      );
    } finally {
      await appDb.close();
    }
  });

  test('merge does not duplicate rows', () async {
    final appDb = await freshDb();
    try {
      final store = await freshStore(appDb);

      final client = await store.createClient(name: 'Клиент Merge');
      final backup = store.backupData();

      // Мержим те же данные — количество строк не должно вырасти.
      final result = await store.mergeFromBackup(backup);
      expect(result.conflicts, isEmpty);

      final clients = await appDb.database.query(
        'clients',
        where: 'id = ?',
        whereArgs: [client.id],
      );
      expect(clients, hasLength(1), reason: 'client duplicated after merge');
    } finally {
      await appDb.close();
    }
  });

  test('every registry table has audit and sync triggers', () async {
    final appDb = await freshDb();
    try {
      final db = appDb.database;
      final triggers = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger'",
      )).map((r) => r['name'] as String).toSet();

      // Audit-триггеры для всех таблиц из kAuditedTables, которые существуют.
      final existing = await appDb.existingTables();
      for (final table in kAuditedTables) {
        if (!existing.contains(table)) continue;
        for (final op in ['insert', 'update', 'delete']) {
          final name = 'audit_${table}_$op';
          expect(triggers.contains(name), isTrue, reason: 'missing $name');
        }
      }

      // Sync-триггеры для всех таблиц из kSyncedTables, которые существуют.
      for (final table in kSyncedTables) {
        if (!existing.contains(table)) continue;
        for (final op in ['insert', 'update', 'delete']) {
          final name = 'sync_out_${table}_$op';
          expect(triggers.contains(name), isTrue, reason: 'missing $name');
        }
      }
    } finally {
      await appDb.close();
    }
  });
}
