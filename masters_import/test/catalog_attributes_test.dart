// Э1 `catalog-order-lines`: атрибуты сущностей (entity_attributes).
//
// Каталог живёт на параметрах: вес, вкус, размер заводятся без миграции схемы,
// поэтому проверка идёт на живом store, а не на «заглушке» маппинга.

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
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

  group('атрибуты позиции каталога', () {
    test('ключ/значение сохраняются и читаются', () async {
      final item = await store.createInventoryItem(
        name: 'Торт «Красный бархат»',
        kind: 'good',
        unit: 'кг',
        sellPriceCents: 220000,
      );

      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: 'вес',
        valueText: '1.5 кг',
        sortOrder: 1,
      );
      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: 'вкус',
        valueText: 'ваниль',
        sortOrder: 0,
      );

      final attributes = store.attributesOf('item', item.id);
      expect(attributes, hasLength(2));
      // Порядок — по sortOrder, а не по дате создания.
      expect(attributes.first.key, 'вкус');
      expect(store.attributeValue('item', item.id, 'вес'), '1.5 кг');
    });

    test('повторная запись того же ключа обновляет значение', () async {
      final item = await store.createInventoryItem(name: 'Пирожное');

      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: 'размер',
        valueText: 'S',
      );
      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: 'размер',
        valueText: 'L',
      );

      expect(store.attributesOf('item', item.id), hasLength(1));
      expect(store.attributeValue('item', item.id, 'размер'), 'L');
    });

    test('числовое значение читается как текст', () async {
      final item = await store.createInventoryItem(name: 'Торт');
      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: 'порций',
        valueNum: 12,
      );

      expect(store.attributeValue('item', item.id, 'порций'), '12.0');
    });

    test('удаление атрибута скрывает его, но не другие', () async {
      final item = await store.createInventoryItem(name: 'Торт');
      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: 'вес',
        valueText: '2 кг',
      );
      final doomed = store.attributesOf('item', item.id).single;
      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: 'вкус',
        valueText: 'шоколад',
      );

      await store.deleteAttribute(doomed.id);

      expect(store.attributesOf('item', item.id), hasLength(1));
      expect(store.attributeValue('item', item.id, 'вес'), isNull);
      expect(store.attributeValue('item', item.id, 'вкус'), 'шоколад');
    });

    test('пустой ключ не создавает запись', () async {
      final item = await store.createInventoryItem(name: 'Торт');
      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: '   ',
        valueText: 'что-то',
      );

      expect(store.attributesOf('item', item.id), isEmpty);
    });

    test('отметка «популярное» ставится и снимается', () async {
      final item = await store.createInventoryItem(name: 'Чизкейк');
      expect(store.isItemPopular(item.id), isFalse);

      await store.setItemPopular(item.id, true);
      expect(store.isItemPopular(item.id), isTrue);

      await store.setItemPopular(item.id, false);
      expect(store.isItemPopular(item.id), isFalse);
    });

    test('атрибуты не текущего заказа не попадают в выборку', () async {
      final first = await store.createInventoryItem(name: 'Первый');
      final second = await store.createInventoryItem(name: 'Второй');
      await store.setAttribute(
        entityType: 'item',
        entityId: first.id,
        key: 'вес',
        valueText: '1 кг',
      );

      expect(store.attributesOf('item', second.id), isEmpty);
      expect(store.attributesOf('job', first.id), isEmpty);
    });
  });

  group('атрибуты заказа', () {
    test('параметры заказа живут отдельно от позиции каталога', () async {
      final item = await store.createInventoryItem(
        name: 'Торт',
        sellPriceCents: 200000,
      );
      await store.setAttribute(
        entityType: 'item',
        entityId: item.id,
        key: 'вкус',
        valueText: 'ваниль',
      );
      final job = await store.createJob(clientId: clientId, title: 'Заказ');
      await store.addCatalogLine(jobId: job.id, itemId: item.id);
      await store.setAttribute(
        entityType: 'job',
        entityId: job.id,
        key: 'адрес',
        valueText: 'ул. Мира 3',
      );

      expect(store.attributeValue('job', job.id, 'вкус'), isNull);
      expect(store.attributeValue('job', job.id, 'адрес'), 'ул. Мира 3');
      expect(store.attributeValue('item', item.id, 'вкус'), 'ваниль');
    });
  });
}
