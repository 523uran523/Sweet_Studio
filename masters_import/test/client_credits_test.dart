import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/job.dart' show JobStatus;
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

  test('createClientCredit books money in and opens an obligation', () async {
    final client = await store.createClient(name: 'Anna');
    final before = store.moneyTransactions.length;

    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
    );

    expect(credit.remainingCents, 300_000);
    expect(credit.status, 'active');
    expect(store.clientCreditTotalCents, 300_000);

    // Поступление — одна транзакция `in`.
    expect(store.moneyTransactions.length, before + 1);
    final tx = store.moneyTransactions.first;
    expect(tx.direction, 'in');
    expect(tx.amountCents, 300_000);
    expect(tx.clientId, client.id);
  });

  test('useClientCredit does not create a second transaction', () async {
    final client = await store.createClient(name: 'Boris');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'deposit',
      title: 'Депозит',
      amountCents: 500_000,
    );
    final txCount = store.moneyTransactions.length;
    final balance = store.totalBalanceCents();

    final used = await store.useClientCredit(
      creditId: credit.id,
      amountCents: 120_000,
    );

    expect(used, 120_000);
    expect(store.moneyTransactions.length, txCount);
    expect(store.totalBalanceCents(), balance);
    expect(store.clientCreditById(credit.id)!.remainingCents, 380_000);
    expect(store.clientCreditTotalCents, 380_000);
  });

  test('useClientCredit writes to audit history only', () async {
    final client = await store.createClient(name: 'Vera');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
    );
    await store.useClientCredit(
      creditId: credit.id,
      amountCents: 120_000,
    );

    final history = store.creditHistory(credit.id);
    expect(history.map((c) => c.action), containsAll(['credit.create', 'credit.use']));
    expect(
      history.firstWhere((c) => c.action == 'credit.use').deltaCents,
      -120_000,
    );
  });

  test('useClientCredit decrements units_left for a pass', () async {
    final client = await store.createClient(name: 'Gleb');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'pass',
      title: 'Абонемент 5 посещений',
      amountCents: 250_000,
      unitsTotal: 5,
    );
    expect(credit.unitsLeft, 5);

    await store.useClientCredit(
      creditId: credit.id,
      amountCents: 50_000,
      units: 1,
    );
    expect(store.clientCreditById(credit.id)!.unitsLeft, 4);

    await store.useClientCredit(
      creditId: credit.id,
      amountCents: 50_000,
      units: 1,
    );
    expect(store.clientCreditById(credit.id)!.unitsLeft, 3);
    expect(store.clientCreditById(credit.id)!.status, 'active');
  });

  test('useClientCredit settles the job receivable', () async {
    final client = await store.createClient(name: 'Diana');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Заказ',
      priceCents: 120_000,
      status: JobStatus.nuevo,
    );
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
    );

    await store.useClientCredit(
      creditId: credit.id,
      amountCents: 120_000,
      jobId: job.id,
    );

    // Списания нет в `money_transactions` (§12.1), поэтому `paidForJob` остаётся 0 —
    // заказ гасится через обязательство.
    expect(store.paidForJob(job.id), 0);
    final obl = store.obligationsForJob(job.id).first;
    expect(obl.paidCents, 120_000);
    expect(obl.status, 'paid');
    expect(store.receivables().where((o) => o.jobId == job.id), isEmpty);
  });

  test('useClientCredit never spends more than the balance', () async {
    final client = await store.createClient(name: 'Max');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'deposit',
      title: 'Депозит',
      amountCents: 100_000,
    );

    final used = await store.useClientCredit(
      creditId: credit.id,
      amountCents: 250_000,
    );

    expect(used, 100_000);
    expect(store.clientCreditById(credit.id)!.remainingCents, 0);
  });

  test('refundClientCredit moves money out and closes the obligation', () async {
    final client = await store.createClient(name: 'Igor');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'deposit',
      title: 'Депозит',
      amountCents: 200_000,
    );
    final balanceAfterIn = store.totalBalanceCents();

    await store.refundClientCredit(
      creditId: credit.id,
      amountCents: 200_000,
    );

    expect(store.totalBalanceCents(), balanceAfterIn - 200_000);
    expect(store.clientCreditTotalCents, 0);
    final refunded = store.clientCreditById(credit.id)!;
    expect(refunded.remainingCents, 0);
    expect(refunded.status, 'refunded');
    expect(store.moneyTransactions.first.direction, 'out');
  });

  test('credits survive reload because state lives in the database', () async {
    final client = await store.createClient(name: 'Nina');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
    );
    await store.useClientCredit(creditId: credit.id, amountCents: 120_000);

    await store.load();

    expect(store.clientCreditById(credit.id)!.remainingCents, 180_000);
    expect(store.creditHistory(credit.id).length, 2);
  });

  test('clientCredits lists only this client and hides deleted', () async {
    final anna = await store.createClient(name: 'Anna');
    final boris = await store.createClient(name: 'Boris');
    await store.createClientCredit(
      clientId: anna.id,
      kind: 'deposit',
      title: 'Анне',
      amountCents: 100_000,
    );
    final second = await store.createClientCredit(
      clientId: boris.id,
      kind: 'deposit',
      title: 'Борису',
      amountCents: 200_000,
    );
    await store.deleteClientCredit(second.id);

    expect(store.clientCredits(anna.id).single.title, 'Анне');
    expect(store.clientCredits(boris.id), isEmpty);
    expect(store.clientCreditTotalCents, 100_000);
  });
}
