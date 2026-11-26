// Э0 «фундамент»: единая точка изменения остатка, себестоимость заказа
// по строкам и денежный формат из настроек.

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/core/money_format.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MoneyFormat', () {
    test('форматирует рубли с группой разрядов', () {
      const format = MoneyFormat();
      expect(format.format(0), '0 ₽');
      expect(format.format(120000), '1 200 ₽');
      expect(format.format(123456789), '1 234 567 ₽');
    });

    test('знак, знаки после запятой и разделители настраиваются', () {
      const usd = MoneyFormat(
        symbol: r'$',
        decimals: 2,
        groupSeparator: ',',
        decimalSeparator: '.',
        symbolAfter: false,
      );
      expect(usd.format(123456), r'$1,234.56');
      expect(usd.amount(123456), '1,234.56');

      const noSymbol = MoneyFormat(symbol: '');
      expect(noSymbol.format(-2500), '−25');
    });

    test('parse понимает разные способы ввода', () {
      const format = MoneyFormat();
      expect(format.parse('1 200'), 120000);
      expect(format.parse('1200,50'), 120050);
      expect(format.parse('1,200.50'), 120050);
      expect(format.parse('-300'), -30000);
      expect(format.parse('₽ 250'), 25000);
      expect(format.parse('abc'), isNull);
      expect(format.parse(''), isNull);
    });
  });

  group('adjustStock', () {
    late AppDatabase appDb;
    late MastersStore store;
    late SettingsController settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      appDb = await AppDatabase.open(path: inMemoryDatabasePath);
      settings = await SettingsController.load();
      store = MastersStore(appDb, settings);
      await store.load();
    });

    tearDown(() async {
      await appDb.close();
    });

    Future<String> createItem() async {
      final item = await store.createInventoryItem(
        name: 'Мука',
        kind: 'good',
        unit: 'кг',
        sellPriceCents: 10000,
        costCents: 4000,
        category: '',
        trackStock: true,
        minQty: 0,
      );
      return item.id;
    }

    test('приход и списание меняют остаток и пишут движение', () async {
      final itemId = await createItem();

      await store.adjustStock(
        itemId: itemId,
        delta: 10,
        type: 'in',
        refType: 'manual',
      );
      await store.adjustStock(
        itemId: itemId,
        delta: -3,
        type: 'writeoff',
        reason: 'spoilage',
      );

      final item = store.inventoryItems.firstWhere((i) => i.id == itemId);
      expect(item.stockQty, 7);

      final movements = store.movementsForItem(itemId);
      expect(movements, hasLength(2));
      expect(movements.first.type, 'writeoff');
      expect(movements.first.qty, 3);
      expect(movements.first.reason, 'spoilage');
      expect(movements.last.qty, 10);
      // Себестоимость на момент движения — снимок, а не ссылка на каталог.
      expect(movements.first.unitCostCents, 4000);
    });

    test('движение пишется в базу, а не только в память', () async {
      final itemId = await createItem();
      await store.adjustStock(itemId: itemId, delta: 5, type: 'in');

      final rows = await appDb.database.query(
        'stock_movements',
        where: 'item_id = ?',
        whereArgs: [itemId],
      );
      expect(rows, hasLength(1));
      expect(rows.first['ref_type'], isNull);
      expect(rows.first['unit_cost_cents'], 4000);
    });

    test('receiveStock считает средневзвешенную себестоимость', () async {
      final itemId = await createItem();
      await store.adjustStock(itemId: itemId, delta: 10, type: 'in');

      await store.receiveStock(
        itemId: itemId,
        qty: 10,
        unitPriceCents: 6000,
      );

      final item = store.inventoryItems.firstWhere((i) => i.id == itemId);
      expect(item.stockQty, 20);
      // (4000*10 + 6000*10) / 20 = 5000
      expect(item.costCents, 5000);
      final last = store.movementsForItem(itemId).first;
      expect(last.type, 'in');
      expect(last.unitCostCents, 6000);
    });

    test('createPurchase увеличивает остаток через adjustStock', () async {
      final itemId = await createItem();
      await store.createPurchase(
        supplierId: null,
        accountId: null,
        lines: [
          {'itemId': itemId, 'qty': 4.0, 'unitPriceCents': 5000},
        ],
      );

      final item = store.inventoryItems.firstWhere((i) => i.id == itemId);
      expect(item.stockQty, 4);
      final movement = store.movementsForItem(itemId).first;
      expect(movement.refType, 'purchase');
      expect(movement.refId, isNotNull);
      expect(movement.unitCostCents, 5000);
    });
  });

  group('jobCostCents', () {
    late AppDatabase appDb;
    late MastersStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      appDb = await AppDatabase.open(path: inMemoryDatabasePath);
      final settings = await SettingsController.load();
      store = MastersStore(appDb, settings);
      await store.load();
    });

    tearDown(() async {
      await appDb.close();
    });

    test('суммирует снимки себестоимости по строкам', () async {
      final client = await store.createClient(name: 'Клиент');
      final job = await store.createJob(
        clientId: client.id,
        title: 'Торт',
        priceCents: 300000,
        costCents: 99999,
      );
      // ignore: unnecessary_statements

      await store.addMaterial(
        jobId: job.id,
        name: 'Крем',
        quantity: 2,
        unit: 'кг',
        priceCents: 30000,
        costAtOrderCents: 10000,
      );
      await store.addMaterial(
        jobId: job.id,
        name: 'Корж',
        quantity: 3,
        unit: 'шт',
        priceCents: 20000,
        costAtOrderCents: 5000,
      );

      // 10000*2 + 5000*3 = 35000, ручная себестоимость игнорируется.
      expect(store.jobCostCents(job.id), 35000);
    });

    test('без строк возвращает ручную себестоимость заказа', () async {
      final client = await store.createClient(name: 'Клиент');
      final job = await store.createJob(
        clientId: client.id,
        title: 'Без строк',
        priceCents: 100000,
        costCents: 42000,
      );
      expect(store.jobCostCents(job.id), 42000);
    });
  });
}
