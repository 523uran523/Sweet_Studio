// Э1 `catalog-order-lines`: маржа заказа.
//
// Главное обещание Э1: маржа = Σ(цена − снимок себестоимости) по строкам, а
// правка цены или себестоимости в каталоге не переписывает прошлые заказы.

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/inventory_composition.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;
  late MastersStore store;
  late SettingsController settings;
  late String clientId;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    settings = await SettingsController.load();
    store = MastersStore(appDb, settings);
    await store.load();
    clientId = (await store.createClient(name: 'Клиент')).id;
  });

  tearDown(() async {
    await appDb.close();
  });

  group('маржа по строкам', () {
    test('сумма маржи = Σ(цена − себестоимость − скидка)', () async {
      final job = await store.createJob(clientId: clientId, title: 'Заказ');
      final cake = await store.createInventoryItem(
        name: 'Торт',
        kind: 'good',
        unit: 'кг',
        sellPriceCents: 200000,
        costCents: 80000,
      );

      await store.addCatalogLine(
        jobId: job.id,
        itemId: cake.id,
        quantity: 2,
      ); // 400 000 − 160 000
      await store.createJobLine(
        job.id,
        kind: 'work',
        name: 'Доставка',
        qty: 1,
        priceCents: 50000,
        costAtOrderCents: 10000,
        discountCents: 5000,
      ); // 50 000 − 5 000 − 10 000

      expect(store.jobMarginCents(job.id), 400000 - 160000 + 35000);
    });

    test('правка цены товара в каталоге не меняет маржу прошлых заказов', () async {
      final item = await store.createInventoryItem(
        name: 'Торт «Клубника»',
        kind: 'good',
        unit: 'шт',
        sellPriceCents: 240000,
        costCents: 100000,
      );
      final oldJob = await store.createJob(clientId: clientId, title: 'Прошлый');
      await store.addCatalogLine(jobId: oldJob.id, itemId: item.id);
      final oldMargin = store.jobMarginCents(oldJob.id);
      expect(oldMargin, 140000);

      // Новый прайс: подорожали и закуп, и продажа.
      await store.updateInventoryItem(
        item.copyWith(sellPriceCents: 320000, costCents: 180000),
      );

      expect(store.jobMarginCents(oldJob.id), oldMargin);

      final newJob = await store.createJob(clientId: clientId, title: 'Новый');
      await store.addCatalogLine(jobId: newJob.id, itemId: item.id);
      expect(store.jobMarginCents(newJob.id), 140000);
    });

    test('снятие со склада по средней себестоимости не трогает строки заказа', () async {
      final item = await store.createInventoryItem(
        name: 'Мука',
        kind: 'good',
        unit: 'кг',
        sellPriceCents: 12000,
        costCents: 6000,
      );
      final job = await store.createJob(clientId: clientId, title: 'Заказ');
      await store.addCatalogLine(
        jobId: job.id,
        itemId: item.id,
        quantity: 5,
      );
      final marginBefore = store.jobMarginCents(job.id);

      await store.receiveStock(
        itemId: item.id,
        qty: 10,
        unitPriceCents: 9000,
      );

      expect(store.inventoryItems.firstWhere((i) => i.id == item.id).costCents,
          greaterThan(6000));
      expect(store.jobMarginCents(job.id), marginBefore);
    });

    test('заказ без строк считает маржу по ручному вводу', () async {
      final job = await store.createJob(
        clientId: clientId,
        title: 'Наклад',
        priceCents: 90000,
        costCents: 40000,
      );

      expect(store.jobLines(job.id), isEmpty);
      expect(store.jobMarginCents(job.id), 50000);
      expect(store.jobCostCents(job.id), 40000);
    });

    test('recalcJobTotals не трогает заказ без строк', () async {
      final job = await store.createJob(
        clientId: clientId,
        title: 'Наклад',
        priceCents: 70000,
        costCents: 20000,
      );

      await store.recalcJobTotals(job.id);

      final stored = store.jobById(job.id)!;
      expect(stored.priceCents, 70000);
      expect(stored.costCents, 20000);
    });

    test('итог заказа = Σ строк после recalc', () async {
      final job = await store.createJob(
        clientId: clientId,
        title: 'Заказ',
        priceCents: 1,
        costCents: 1,
      );
      final item = await store.createInventoryItem(
        name: 'Услуга',
        kind: 'service',
        unit: 'услуга',
        sellPriceCents: 45000,
        costCents: 0,
      );
      await store.addCatalogLine(jobId: job.id, itemId: item.id, quantity: 3);

      await store.recalcJobTotals(job.id);

      final stored = store.jobById(job.id)!;
      expect(stored.priceCents, 135000);
      expect(stored.costCents, 0);
    });
  });

  group('списание материалов заказа по составу', () {
    test('дробный расход сохраняется в остатке и движении', () async {
      final wood = await store.createInventoryItem(name: 'Доска', unit: 'м');
      await store.receiveStock(itemId: wood.id, qty: 2);
      final shelf = await store.createInventoryItem(name: 'Полка');
      await store.saveItemComposition(shelf.id, [
        InventoryCompositionLine(
          id: '',
          itemId: shelf.id,
          componentId: wood.id,
          qty: 0.75,
          priceCents: 10000,
        ),
      ]);
      final job = await store.createJob(clientId: clientId, title: 'Полка');
      final line = await store.addCatalogLine(jobId: job.id, itemId: shelf.id);
      await store.writeOffJobMaterials(job.id, lineIds: [line.id]);
      expect(store.movementsForItem(wood.id).first.qty, 0.75);
      expect(store.inventoryItems.firstWhere((item) => item.id == wood.id).stockQty, 1.25);
      await store.load();
      expect(store.movementsForItem(wood.id).first.qty, 0.75);
      expect(store.inventoryItems.firstWhere((item) => item.id == wood.id).stockQty, 1.25);
    });

    test('расход = количество строки × количество компонента', () async {
      final flour = await store.createInventoryItem(
        name: 'Мука',
        kind: 'good',
        unit: 'кг',
        sellPriceCents: 0,
        costCents: 6000,
      );
      await store.adjustStock(itemId: flour.id, delta: 10, type: 'in');
      final cake = await store.createInventoryItem(
        name: 'Торт',
        kind: 'good',
        unit: 'шт',
        sellPriceCents: 240000,
        costCents: 0,
      );
      await store.saveItemComposition(cake.id, [
        InventoryCompositionLine(
          id: '',
          itemId: '',
          componentId: flour.id,
          qty: 0.4,
          priceCents: 6000,
        ),
        const InventoryCompositionLine(
          id: 'labor',
          itemId: 'ignored',
          isLabor: true,
          qty: 1,
          priceCents: 30000,
        ),
      ]);

      final job = await store.createJob(clientId: clientId, title: 'Заказ');
      final line = await store.addCatalogLine(
        jobId: job.id,
        itemId: cake.id,
        quantity: 5,
      );

      final written = await store.writeOffJobMaterials(
        job.id,
        lineIds: [line.id],
      );

      // 5 тортов × 0.4 кг = 2 кг муки; ручной труд не списывается.
      expect(written, 1);
      expect(
        store.inventoryItems.firstWhere((i) => i.id == flour.id).stockQty,
        8,
      );
      final movement = store.movementsForItem(flour.id).first;
      expect(movement.type, 'writeoff');
      expect(movement.refType, 'job');
      expect(movement.refId, job.id);
    });

    test('строка вне списка не списывается', () async {
      final flour = await store.createInventoryItem(name: 'Мука');
      await store.adjustStock(itemId: flour.id, delta: 4, type: 'in');
      final cake = await store.createInventoryItem(
        name: 'Торт',
        sellPriceCents: 100000,
      );
      await store.saveItemComposition(cake.id, [
        InventoryCompositionLine(
          id: '',
          itemId: '',
          componentId: flour.id,
          qty: 1,
          priceCents: 6000,
        ),
      ]);
      final job = await store.createJob(clientId: clientId, title: 'Заказ');
      await store.addCatalogLine(jobId: job.id, itemId: cake.id);

      final written = await store.writeOffJobMaterials(job.id, lineIds: const []);

      expect(written, 0);
      expect(store.inventoryItems.firstWhere((i) => i.id == flour.id).stockQty,
          4);
    });
  });
}
