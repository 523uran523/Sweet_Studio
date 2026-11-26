// Э1 `catalog-order-lines`: строки заказа из каталога.
//
// Проверяет, что позиция каталога становится строкой заказа со снимком цены и
// себестоимости, а итог заказа пересчитывается по строкам.

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/inventory_item.dart';
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

  Future<InventoryItem> createGood({
    String name = 'Торт «Клубника»',
    int sellPriceCents = 240000,
    int costCents = 100000,
    String unit = 'шт',
    String kind = 'good',
  }) {
    return store.createInventoryItem(
      name: name,
      kind: kind,
      unit: unit,
      sellPriceCents: sellPriceCents,
      costCents: costCents,
      trackStock: kind == 'good',
    );
  }

  Future<String> createJob() async {
    final job = await store.createJob(clientId: clientId, title: 'Заказ');
    return job.id;
  }

  group('строки заказа из каталога', () {
    test('позиция подставляет цену, единицу и снимок себестоимости', () async {
      final item = await createGood(unit: 'кг', sellPriceCents: 180000, costCents: 70000);
      final jobId = await createJob();

      final line = await store.addCatalogLine(
        jobId: jobId,
        itemId: item.id,
        quantity: 2,
      );

      expect(line.itemId, item.id);
      expect(line.kind, 'good');
      expect(line.unit, 'кг');
      expect(line.priceCents, 180000);
      expect(line.costAtOrderCents, 70000);
      expect(line.quantity, 2);
      expect(line.totalCents, 360000);
      expect(line.costTotalCents, 140000);
      expect(store.jobLines(jobId), hasLength(1));
    });

    test('услуга не несёт себестоимости в строке', () async {
      final service = await createGood(
        name: 'Диагностика',
        kind: 'service',
        sellPriceCents: 300000,
        costCents: 0,
      );
      final jobId = await createJob();

      final line = await store.createJobLine(
        jobId,
        itemId: service.id,
        kind: 'work',
      );

      expect(line.kind, 'work');
      expect(line.priceCents, 300000);
      expect(line.costAtOrderCents, 0);
      expect(line.marginCents, 300000);
    });

    test('редактирование строки обновляет итог заказа', () async {
      final item = await createGood();
      final jobId = await createJob();
      final line = await store.addCatalogLine(jobId: jobId, itemId: item.id);
      await store.recalcJobTotals(jobId);

      expect(store.jobById(jobId)!.priceCents, 240000);
      expect(store.jobById(jobId)!.costCents, 100000);

      await store.updateJobLine(line.id, qty: 3, discountCents: 10000);
      await store.recalcJobTotals(jobId);

      final job = store.jobById(jobId)!;
      expect(job.priceCents, 240000 * 3 - 10000);
      expect(job.costCents, 100000 * 3);
      expect(store.jobCostCents(jobId), 300000);
    });

    test('удаление строки пересчитывает стоимость заказа', () async {
      final item = await createGood();
      final jobId = await createJob();
      final first = await store.addCatalogLine(jobId: jobId, itemId: item.id);
      await store.addCatalogLine(jobId: jobId, itemId: item.id, quantity: 2);
      await store.recalcJobTotals(jobId);
      expect(store.jobCostCents(jobId), 300000);

      await store.deleteMaterial(first.id);
      await store.recalcJobTotals(jobId);

      expect(store.jobLines(jobId), hasLength(1));
      expect(store.jobCostCents(jobId), 200000);
    });

    test('свободная строка без позиции каталога сохраняется', () async {
      final jobId = await createJob();

      final line = await store.createJobLine(
        jobId,
        kind: 'work',
        name: 'Выезд мастера',
        qty: 1,
        unit: 'услуга',
        priceCents: 150000,
        costAtOrderCents: 40000,
      );

      expect(line.itemId, isNull);
      expect(line.marginCents, 110000);
      expect(store.jobLines(jobId).single.name, 'Выезд мастера');
    });
  });
}
