// Критерий «5 минут» (§9.1 п.11 плана 2026-11-07).
//
// На чистой базе путь до закрытого заказа с посчитанной маржой должен
// укладываться в 5 действий интерфейса. Тест фиксирует этот путь на уровне
// стора: одно действие = один вызов, который делает интерфейс. Заведение
// позиции каталога в путь не входит — прайс мастер заполняет один раз,
// а не на каждый заказ.
//
// 1. createClient      — «Новый клиент»
// 2. createJob         — «Новый заказ» + название
// 3. addCatalogLine    — добавить позицию из каталога и сохранить форму
// 4. payObligation     — «Принять оплату» (способ оплаты)
// 5. setJobStatus      — «Закрыть заказ»

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/job.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;
  late MastersStore store;
  late SettingsController settings;

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
  });

  tearDown(() async {
    await appDb.close();
  });

  test('чистая база → закрытый заказ с маржой за 5 действий', () async {
    // Справочник: позиция каталога с ценой и себестоимостью. Не шаг заказа.
    final cake = await store.createInventoryItem(
      name: 'Торт «Медовик»',
      kind: 'good',
      unit: 'шт',
      sellPriceCents: 1200000,
      costCents: 450000,
    );

    // Действие 1 — клиент.
    final client = await store.createClient(name: 'Айгерим');
    // Действие 2 — заказ.
    final job = await store.createJob(clientId: client.id, title: 'Медовик 3 кг');
    // Действие 3 — позиция из каталога; итог формы считается при сохранении.
    await store.addCatalogLine(jobId: job.id, itemId: cake.id, quantity: 2);
    await store.recalcJobTotals(job.id);
    // Синхронизация обязательств после изменения суммы заказа.
    await store.syncJobObligations(job.id);

    expect(store.jobById(job.id)!.priceCents, 2400000);
    expect(store.jobMarginCents(job.id), 2400000 - 900000);

    // Действие 4 — оплата: обязательство заказа закрывается платежом.
    final obligation = store.openJobPaymentObligation(job.id);
    expect(obligation, isNotNull, reason: 'заказ обязан породить обязательство');
    await store.payObligation(
      obligation!.id,
      amountCents: obligation.remainingCents,
      accountId: store.accounts.first.id,
      paymentMethod: 'kaspi',
    );

    expect(store.paidForJob(job.id), 2400000);
    expect(store.openJobPaymentObligation(job.id), isNull);
    expect(
      store.moneyTransactions.firstWhere((t) => t.jobId == job.id).paymentMethod,
      'kaspi',
    );

    // Действие 5 — закрытие.
    await store.setJobStatus(job.id, JobStatus.done);
    await store.setJobStatus(job.id, JobStatus.closed);

    final closed = store.jobById(job.id)!;
    expect(closed.status, JobStatus.closed);
    expect(closed.finishedAt, isNotNull);
    expect(store.jobMarginCents(job.id), 1500000);
  });

  test('заказ с долгом закрывается и остаётся в дебиторке', () async {
    final client = await store.createClient(name: 'Данияр');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Набор капкейков',
      priceCents: 800000,
      costCents: 300000,
    );

    final obligation = store.openJobPaymentObligation(job.id)!;
    await store.payObligation(
      obligation.id,
      amountCents: 300000,
      accountId: store.accounts.first.id,
      paymentMethod: 'cash',
    );
    await store.setJobStatus(job.id, JobStatus.closed);

    expect(store.jobById(job.id)!.status, JobStatus.closed);
    expect(store.paidForJob(job.id), 300000);
    // Остаток 500 000 не пропадает: он виден как долг клиента.
    expect(store.clientDebtCents(client.id), 500000);
    expect(store.jobMarginCents(job.id), 500000);
  });

  test('маржа пустого заказа нулевая, а не случайная', () async {
    final client = await store.createClient(name: 'Олег');
    final job = await store.createJob(clientId: client.id, title: 'Заявка');

    expect(store.jobLines(job.id), isEmpty);
    expect(store.jobMarginCents(job.id), 0);
    expect(store.paidForJob(job.id), 0);
  });
}
