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

  DateTime now() => DateTime.now().add(const Duration(seconds: 5));

  test('DoD: certificate 30.00 + write-off 12.00 -> revenue 12.00, debt 18.00', () async {
    final client = await store.createClient(name: 'Anna');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
    );
    await store.useClientCredit(creditId: credit.id, amountCents: 120_000);

    final to = now();
    expect(store.recognizedRevenueCents(DateTime(2000), to), 120_000);
    expect(store.clientCreditTotalCents, 180_000);
  });

  test('deposit alone is cash flow, not revenue', () async {
    final client = await store.createClient(name: 'Boris');
    await store.createClientCredit(
      clientId: client.id,
      kind: 'deposit',
      title: 'Депозит',
      amountCents: 500_000,
    );

    expect(store.moneyTransactions.first.direction, 'in');
    expect(store.recognizedRevenueCents(DateTime(2000), now()), 0);
    expect(store.clientCreditTotalCents, 500_000);
  });

  test('ordinary sale revenue is untouched by credits', () async {
    final client = await store.createClient(name: 'Vera');
    await store.addTransaction(
      accountId: store.accounts.first.id,
      kind: 'sale',
      direction: 'in',
      amountCents: 90_000,
      category: 'Продажа',
      clientId: client.id,
    );

    expect(store.recognizedRevenueCents(DateTime(2000), now()), 90_000);
  });

  test('write-off of an old deposit counts in the period it happened', () async {
    final client = await store.createClient(name: 'Gleb');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'pass',
      title: 'Абонемент',
      amountCents: 250_000,
      unitsTotal: 5,
    );
    await store.useClientCredit(
      creditId: credit.id,
      amountCents: 50_000,
      units: 1,
    );

    final to = now();
    expect(store.clientCreditRevenueCents(DateTime(2000), to), 50_000);
    expect(store.recognizedRevenueCents(DateTime(2000), to), 50_000);
  });

  test('refund is not revenue and is not deducted twice', () async {
    final client = await store.createClient(name: 'Diana');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
    );
    await store.useClientCredit(creditId: credit.id, amountCents: 120_000);
    await store.refundClientCredit(creditId: credit.id, amountCents: 100_000);

    // ДДС: +300 −100 = 200. Выручка: 120 (отработано). Обязательство: 80.
    expect(store.totalBalanceCents(), 200_000);
    expect(store.clientCreditTotalCents, 80_000);
    expect(store.recognizedRevenueCents(DateTime(2000), now()), 120_000);
  });

  test('expiry keeps cash and revenue, releases the obligation', () async {
    final client = await store.createClient(name: 'Max');
    await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    await store.load();

    expect(store.totalBalanceCents(), 300_000);
    expect(store.clientCreditTotalCents, 0);
    expect(store.recognizedRevenueCents(DateTime(2000), now()), 0);
  });

  test('deferred delta equals obligation growth of the period', () async {
    final client = await store.createClient(name: 'Igor');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'deposit',
      title: 'Депозит',
      amountCents: 400_000,
    );
    await store.useClientCredit(creditId: credit.id, amountCents: 150_000);

    // +400 при пополнении, −150 при списании.
    expect(store.deferredDeltaCents(DateTime(2000), now()), 250_000);
  });

  test('period bounds are exclusive at the end', () async {
    final client = await store.createClient(name: 'Nina');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
    );
    await store.useClientCredit(creditId: credit.id, amountCents: 120_000);

    final to = now();
    expect(store.recognizedRevenueCents(DateTime(2000), DateTime(2000)), 0);
    expect(store.recognizedRevenueCents(to, to), 0);
    expect(store.recognizedRevenueCents(DateTime(2000), to), 120_000);
  });

  test('revenue formula equals inflow minus obligation growth', () async {
    final client = await store.createClient(name: 'Oleg');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'pass',
      title: 'Абонемент',
      amountCents: 200_000,
      unitsTotal: 4,
    );
    await store.useClientCredit(
      creditId: credit.id,
      amountCents: 50_000,
      units: 1,
    );
    await store.addTransaction(
      accountId: store.accounts.first.id,
      kind: 'expense',
      direction: 'out',
      amountCents: 30_000,
      category: 'Расход',
    );

    final to = now();
    final from = DateTime(2000);
    final inflow = store.moneyTransactions
        .where((t) => !t.voided && t.direction == 'in' && t.createdAt.isBefore(to))
        .fold(0, (s, t) => s + t.amountCents);
    expect(
      store.recognizedRevenueCents(from, to),
      inflow - store.deferredDeltaCents(from, to),
    );
  });
}
