import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/inventory_composition.dart';
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

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    settings = await SettingsController.load();
    store = MastersStore(db, settings);
    await store.load();
    await store.setLocationsEnabled(true);
  });

  tearDown(() async {
    await db.close();
  });

  /// Инвариант DoD: остаток точки по позиции равен сумме её партий.
  void expectLevelEqualsBatches(String itemId, String locationId) {
    final sum = store.batches
        .where((b) => b.itemId == itemId && b.locationId == locationId)
        .fold<double>(0, (s, b) => s + b.qty);
    expect(
      store.stockOnLocation(itemId, locationId),
      closeTo(sum, 0.0001),
      reason: 'остаток точки должен равняться сумме партий',
    );
  }

  group('stock_batches_test', () {
    test('остаток по локациям = сумма партий после прихода и расхода',
        () async {
      final loc = store.locations.first;
      final flour = await store.createInventoryItem(name: 'Мука', costCents: 60);

      await store.adjustStock(
        itemId: flour.id,
        delta: 5,
        type: 'in',
        refType: 'manual',
        locationId: loc.id,
      );
      await store.adjustStock(
        itemId: flour.id,
        delta: 3,
        type: 'in',
        refType: 'manual',
        locationId: loc.id,
      );
      expectLevelEqualsBatches(flour.id, loc.id);
      expect(store.stockOnLocation(flour.id, loc.id), closeTo(8, 0.0001));

      await store.adjustStock(
        itemId: flour.id,
        delta: -2,
        type: 'out',
        refType: 'manual',
        locationId: loc.id,
      );
      expectLevelEqualsBatches(flour.id, loc.id);
      expect(store.stockOnLocation(flour.id, loc.id), closeTo(6, 0.0001));

      // Полное списание: уровень обнуляется, а не остаётся «из воздуха».
      await store.writeOffStock(itemId: flour.id, qty: 6);
      expectLevelEqualsBatches(flour.id, loc.id);
      expect(store.stockOnLocation(flour.id, loc.id), closeTo(0, 0.0001));
      expect(store.batches.where((b) => b.itemId == flour.id), isEmpty);
    });

    test('партии на разных точках не смешиваются', () async {
      final loc1 = store.locations.first;
      final loc2 = await store.createLocation(name: 'Витрина');
      final sugar = await store.createInventoryItem(
        name: 'Сахар',
        costCents: 40,
      );

      await store.adjustStock(
        itemId: sugar.id,
        delta: 10,
        type: 'in',
        refType: 'manual',
        locationId: loc1.id,
      );
      await store.adjustStock(
        itemId: sugar.id,
        delta: 4,
        type: 'in',
        refType: 'manual',
        locationId: loc2.id,
      );

      expect(store.stockOnLocation(sugar.id, loc1.id), closeTo(10, 0.0001));
      expect(store.stockOnLocation(sugar.id, loc2.id), closeTo(4, 0.0001));
      expectLevelEqualsBatches(sugar.id, loc1.id);
      expectLevelEqualsBatches(sugar.id, loc2.id);

      // Расход с витрины не трогает склад.
      await store.adjustStock(
        itemId: sugar.id,
        delta: -4,
        type: 'out',
        refType: 'manual',
        locationId: loc2.id,
      );
      expect(store.stockOnLocation(sugar.id, loc1.id), closeTo(10, 0.0001));
      expect(store.stockOnLocation(sugar.id, loc2.id), closeTo(0, 0.0001));
    });

    test('FEFO: истекающая партия списывается первой', () async {
      final loc = store.locations.first;
      final now = DateTime.now().copyWith(microsecond: 0);
      final curd = await store.createInventoryItem(name: 'Творог', costCents: 90);

      // Намеренно сначала дальний срок: порядок задаёт срок, а не приход.
      await store.adjustStock(
        itemId: curd.id,
        delta: 2,
        type: 'in',
        refType: 'manual',
        locationId: loc.id,
        unitCostCents: 20,
        expiresAt: now.add(const Duration(days: 20)),
      );
      await store.adjustStock(
        itemId: curd.id,
        delta: 2,
        type: 'in',
        refType: 'manual',
        locationId: loc.id,
        unitCostCents: 10,
        expiresAt: now.add(const Duration(days: 2)),
      );

      final queue = await store.stockBatches(curd.id, locationId: loc.id);
      expect(queue.first.expiresAt, now.add(const Duration(days: 2)),
          reason: 'ближайший срок должен быть первым');

      await store.adjustStock(
        itemId: curd.id,
        delta: -3,
        type: 'out',
        refType: 'manual',
        locationId: loc.id,
      );

      final left = store.batches.where((b) => b.itemId == curd.id).toList();
      expect(left, hasLength(1));
      expect(left.single.expiresAt, now.add(const Duration(days: 20)));
      expect(left.single.qty, closeTo(1, 0.0001));
      expectLevelEqualsBatches(curd.id, loc.id);
    });

    test('истёкшая партия не списывается обычным расходом', () async {
      final loc = store.locations.first;
      final now = DateTime.now().copyWith(microsecond: 0);
      final butter = await store.createInventoryItem(
        name: 'Масло',
        costCents: 300,
      );
      await store.adjustStock(
        itemId: butter.id,
        delta: 4,
        type: 'in',
        refType: 'manual',
        locationId: loc.id,
        expiresAt: now.subtract(const Duration(days: 1)),
      );

      // Списываем то, чего по сроку уже нет: партии остаются, уровень — нет.
      await store.adjustStock(
        itemId: butter.id,
        delta: -1,
        type: 'out',
        refType: 'manual',
        locationId: loc.id,
      );

      final batch = store.batches.firstWhere((b) => b.itemId == butter.id);
      expect(batch.qty, closeTo(4, 0.0001),
          reason: 'просрочку списывают отдельно, а не в составе расхода');
      expect(batch.isExpiredAt(now), isTrue);
      expect(store.expiringBatches(days: 3, at: now), isEmpty,
          reason: 'истёкшая партия — не «истекающая»');
    });

    test('productionPlan раскрывает состав и считает дефицит', () async {
      final loc = store.locations.first;
      final flour = await store.createInventoryItem(
        name: 'Мука',
        unit: 'кг',
        costCents: 60,
      );
      final cake = await store.createInventoryItem(
        name: 'Торт',
        costCents: 0,
      );
      await store.saveItemComposition(cake.id, [
        InventoryCompositionLine(
          id: '',
          itemId: cake.id,
          componentId: flour.id,
          qty: 2,
          priceCents: 60,
        ),
      ]);

      // На точке 4 кг муки: на 3 торта (6 кг) не хватает 2 кг.
      await store.adjustStock(
        itemId: flour.id,
        delta: 4,
        type: 'in',
        refType: 'manual',
        locationId: loc.id,
      );

      final client = await store.createClient(name: 'Клиент');
      final job = await store.createJob(
        clientId: client.id,
        title: 'Торты на день рождения',
        dueDate: DateTime.now(),
      );
      await store.addCatalogLine(jobId: job.id, itemId: cake.id, quantity: 3);

      final plan = await store.productionPlan(DateTime.now());
      final need = plan.where((n) => n.item.id == flour.id).toList();
      expect(need, hasLength(1));
      expect(need.single.planQty, closeTo(6, 0.0001));
      expect(need.single.inStock, closeTo(4, 0.0001));
      expect(need.single.short, closeTo(2, 0.0001));
      expect(need.single.reason, 'plan');
    });

    test('productionPlan пуст, когда сырья хватает', () async {
      final loc = store.locations.first;
      final flour = await store.createInventoryItem(
        name: 'Мука',
        unit: 'кг',
        costCents: 60,
      );
      await store.adjustStock(
        itemId: flour.id,
        delta: 10,
        type: 'in',
        refType: 'manual',
        locationId: loc.id,
      );

      final client = await store.createClient(name: 'Клиент');
      final job = await store.createJob(
        clientId: client.id,
        title: 'Заказ',
        dueDate: DateTime.now(),
      );
      await store.addMaterial(
        jobId: job.id,
        name: 'Мука',
        quantity: 3,
        itemId: flour.id,
        kind: 'material',
      );

      final plan = await store.productionPlan(DateTime.now());
      expect(plan.where((n) => n.item.id == flour.id), isEmpty);
    });

    test('productionPlan добавляет позиции ниже минимума', () async {
      final loc = store.locations.first;
      final eggs = await store.createInventoryItem(
        name: 'Яйцо',
        costCents: 12,
        minQty: 10,
      );
      await store.adjustStock(
        itemId: eggs.id,
        delta: 3,
        type: 'in',
        refType: 'manual',
        locationId: loc.id,
      );

      final plan = await store.productionPlan(DateTime.now());
      final gap = plan.where((n) => n.item.id == eggs.id).toList();
      expect(gap, hasLength(1));
      expect(gap.single.reason, 'min');
      expect(gap.single.short, closeTo(7, 0.0001));
    });

    test('productionPlan пуст при выключенном флаге', () async {
      await store.setLocationsEnabled(false);
      final plan = await store.productionPlan(DateTime.now());
      expect(plan, isEmpty);
    });
  });
}
