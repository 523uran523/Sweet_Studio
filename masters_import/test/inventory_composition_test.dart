import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/inventory_composition.dart';
import 'package:masters/data/repositories/inventory_composition_repository.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('create composition updates item cost to sum of lines', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final item = await store.createInventoryItem(
        name: 'Мастерская',
        costCents: 0,
      );
      final comp = await store.createInventoryItem(
        name: 'Фанера',
        costCents: 5000,
      );
      final lines = [
        InventoryCompositionLine(
          id: 'l1',
          itemId: item.id,
          componentId: comp.id,
          isLabor: false,
          qty: 2,
          priceCents: 5000,
        ),
        InventoryCompositionLine(
          id: 'l2',
          itemId: item.id,
          isLabor: true,
          qty: 1,
          priceCents: 3000,
        ),
      ];
      final total = await store.saveItemComposition(item.id, lines);
      expect(total, 13000); // 2*5000 + 1*3000
      final updated = store.inventoryItems.where((i) => i.id == item.id).first;
      expect(updated.costCents, 13000);
      expect(store.compositionCostCents(item.id), 13000);
      expect(store.itemComposition(item.id).length, 2);
    } finally {
      await appDb.close();
    }
  });

  test('re-save replaces composition (not appends)', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final item = await store.createInventoryItem(name: 'Стол');
      final comp1 = await store.createInventoryItem(
        name: 'Доска',
        costCents: 1000,
      );
      final lines1 = [
        InventoryCompositionLine(
          id: '',
          itemId: item.id,
          componentId: comp1.id,
          qty: 3,
          priceCents: 1000,
        ),
      ];
      await store.saveItemComposition(item.id, lines1);
      expect(store.itemComposition(item.id).length, 1);

      // Re-save with different lines
      final lines2 = [
        InventoryCompositionLine(
          id: '',
          itemId: item.id,
          isLabor: true,
          qty: 1,
          priceCents: 2000,
        ),
      ];
      await store.saveItemComposition(item.id, lines2);
      expect(store.itemComposition(item.id).length, 1);
      expect(store.itemComposition(item.id).first.isLabor, true);
      expect(store.compositionCostCents(item.id), 2000);
    } finally {
      await appDb.close();
    }
  });

  test('labor rows count in composition total', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final item = await store.createInventoryItem(name: 'Стул');
      final lines = [
        InventoryCompositionLine(
          id: '',
          itemId: item.id,
          isLabor: true,
          qty: 1.5,
          priceCents: 10000,
          note: 'Сборка',
        ),
      ];
      final total = await store.saveItemComposition(item.id, lines);
      expect(total, 15000); // 1.5 * 10000
      final line = store.itemComposition(item.id).single;
      expect(line.isLabor, true);
      expect(line.note, 'Сборка');
      expect(line.totalCents, 15000);
    } finally {
      await appDb.close();
    }
  });

  test('composition persists in database via repository', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final item = await store.createInventoryItem(name: 'Стол', costCents: 0);

      // Use the repository directly to verify it works
      final repo = InventoryCompositionRepository(appDb.database);
      await repo.replaceForItem(item.id, [
        InventoryCompositionLine(
          id: 'test-repo',
          itemId: item.id,
          isLabor: true,
          qty: 2,
          priceCents: 5000,
        ),
      ]);
      final rows = await repo.forItem(item.id);
      expect(rows.length, 1);
      expect(rows[0].totalCents, 10000);
    } finally {
      await appDb.close();
    }
  });
}
