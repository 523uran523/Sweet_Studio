import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/inventory_item.dart';
import 'package:masters/data/models/stock_location.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase db;
  late SettingsController settings;
  late MastersStore store;

  Future<void> openStore() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    settings = await SettingsController.load();
    store = MastersStore(db, settings);
    await store.load();
  }

  tearDown(() async {
    await db.close();
  });

  group('locations_flag_test', () {
    test('при выключенном флаге склад работает как раньше', () async {
      await openStore();
      expect(store.locationsEnabled, isFalse);

      final item = await store.createInventoryItem(
        name: 'Мука',
        costCents: 100,
      );

      await store.adjustStock(
        itemId: item.id,
        delta: 10,
        type: 'in',
        note: 'Тест',
        refType: 'manual',
      );

      final updatedItem = store.inventoryItems
          .where((i) => i.id == item.id)
          .cast<InventoryItem?>()
          .firstOrNull;
      expect(updatedItem!.stockQty, 10);

      expect(store.stockMovements.isNotEmpty, isTrue);
      final mov = store.stockMovements.first;
      expect(mov.itemId, item.id);
      expect(mov.type, 'in');
      expect(mov.qty, 10);

      expect(store.locations, isEmpty);
      expect(store.stockLevels, isEmpty);
      expect(store.batches, isEmpty);
    });

    test('при включении флага создаётся Основной склад и переносится остаток',
        () async {
      await openStore();

      final item = await store.createInventoryItem(
        name: 'Мука',
        stockQty: 5.5,
        costCents: 100,
      );

      await store.setLocationsEnabled(true);
      expect(store.locationsEnabled, isTrue);
      expect(store.locations, hasLength(1));
      final loc = store.locations.first;
      expect(loc.name, 'Основной склад');
      expect(loc.isDefault, isTrue);

      expect(store.stockLevels, hasLength(1));
      final level = store.stockLevels.first;
      expect(level.itemId, item.id);
      expect(level.qty, 5.5);
      expect(level.locationId, loc.id);

      expect(store.batches, hasLength(1));
      final batch = store.batches.first;
      expect(batch.itemId, item.id);
      expect(batch.qty, 5.5);
      expect(batch.locationId, loc.id);
      expect(batch.unitCostCents, 100);
    });

    test('ensureDefaultLocation идемпотентен', () async {
      await openStore();
      // Позиция с остатком: бэкфилл обязан перенести её ровно один раз.
      await store.createInventoryItem(name: 'Мука', stockQty: 4, costCents: 90);
      await store.setLocationsEnabled(true);

      expect(store.locations, hasLength(1));
      expect(store.batches, hasLength(1));

      await store.ensureDefaultLocation();
      await store.ensureDefaultLocation();
      expect(store.locations, hasLength(1));
      expect(store.batches, hasLength(1));
      expect(store.batches.first.qty, closeTo(4, 0.0001));
    });

    test('перемещение создаёт transfer и списывает/начисляет партии',
        () async {
      await openStore();
      await store.ensureDefaultLocation();
      final loc1 = store.locations.first;

      final item = await store.createInventoryItem(
        name: 'Сахар',
        costCents: 50,
      );

      await store.adjustStock(
        itemId: item.id,
        delta: 10,
        type: 'in',
        note: 'Приход',
        refType: 'manual',
      );

      final loc2 = await store.createLocation(name: 'Склад B');

      final transfer = await store.createStockTransfer(
        fromLocationId: loc1.id,
        toLocationId: loc2.id,
        lines: [
          {'itemId': item.id, 'qty': 3},
        ],
      );

      expect(store.transfers, hasLength(1));
      expect(store.transfers.first.id, transfer.id);

      final lines = store.transferLines(transfer.id);
      expect(lines, hasLength(1));
      expect(lines.first.itemId, item.id);
      expect(lines.first.qty, 3);

      // Остаток на loc1 уменьшился (10 → 7).
      expect(
        store.stockOnLocation(item.id, loc1.id),
        closeTo(7, 0.0001),
      );
      // На loc2 появился (0 → 3).
      expect(
        store.stockOnLocation(item.id, loc2.id),
        closeTo(3, 0.0001),
      );
    });

    test('FEFO-списание берёт истекающие первым', () async {
      await openStore();
      await store.ensureDefaultLocation();
      final loc = store.locations.first;

      final item = await store.createInventoryItem(
        name: 'Творог',
        costCents: 10,
      );

      final now = DateTime.now();
      await store.adjustStock(
        itemId: item.id,
        delta: 5,
        type: 'in',
        note: 'Партия 1',
        refType: 'manual',
        expiresAt: now.add(const Duration(days: 1)),
      );
      await store.adjustStock(
        itemId: item.id,
        delta: 5,
        type: 'in',
        note: 'Партия 2',
        refType: 'manual',
        expiresAt: now.add(const Duration(days: 30)),
      );

      expect(store.batches, hasLength(2));

      // Списываем 6 единиц — должна уйти партия 1 (5) + 1 из партии 2.
      await store.writeOffStock(
        itemId: item.id,
        qty: 6,
        reason: 'expiry',
      );

      // Осталась только партия 2 с qty=4.
      final remaining = store.batches.where((b) => b.qty > 0.0001).toList();
      expect(remaining, hasLength(1));
      expect(remaining.first.qty, closeTo(4, 0.0001));
      expect(
        remaining.first.expiresAt,
        now.add(const Duration(days: 30)),
      );

      final level = store.stockLevels
          .where((l) => l.itemId == item.id && l.locationId == loc.id)
          .cast<StockLevel?>()
          .firstOrNull;
      expect(level!.qty, closeTo(4, 0.0001));
    });

    test('приёмка закупки создаёт партию и уменьшает долг при недопоставке',
        () async {
      await openStore();
      await store.ensureDefaultLocation();
      final loc = store.locations.first;

      final item = await store.createInventoryItem(
        name: 'Сахар',
        costCents: 50,
      );
      final supplier = await store.createSupplier(name: 'Поставщик');

      final purchase = await store.createPurchase(
        supplierId: supplier.id,
        lines: [
          {'itemId': item.id, 'qty': 10, 'unitPriceCents': 50},
        ],
      );
      // Заказанная сумма — долг до приёмки.
      expect(store.supplierDebtCents(supplier.id), 500);

      // Приёмка: принимаем 8 из 10 (недопоставка).
      await store.receivePurchase(
        purchaseId: purchase.id,
        received: {item.id: 8},
        locationId: loc.id,
      );

      final batches = await store.stockBatches(item.id, locationId: loc.id);
      expect(batches, hasLength(1));
      expect(batches.first.qty, closeTo(8, 0.0001));
      expect(batches.first.unitCostCents, 50);
      expect(batches.first.purchaseId, purchase.id);

      final pl = store.linesForPurchase(purchase.id)
          .firstWhere((p) => p.itemId == item.id);
      expect(pl.receivedQty, 8);
      expect(pl.isShortAt(), isTrue);

      // Долг = Σ принятых строк × цену: 8 × 50 = 400, недопоставка прощена.
      expect(store.supplierDebtCents(supplier.id), 400);

      // Приход лёг и на склад, и в `stock_qty` — без двойного учёта.
      expect(store.stockOnLocation(item.id, loc.id), closeTo(8, 0.0001));
      final stocked = store.inventoryItems
          .where((i) => i.id == item.id)
          .cast<InventoryItem?>()
          .firstOrNull;
      expect(stocked!.stockQty, closeTo(8, 0.0001));
    });
  });
}
