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

  test('load() marks overdue credits expired', () async {
    final client = await store.createClient(name: 'Anna');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Просрочен',
      amountCents: 300_000,
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(credit.status, 'active');

    await store.load();

    expect(store.clientCreditById(credit.id)!.status, 'expired');
  });

  test('expireCredits returns the number of switched credits', () async {
    final client = await store.createClient(name: 'Boris');
    await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Первый',
      amountCents: 100_000,
      expiresAt: DateTime.now().subtract(const Duration(days: 5)),
    );
    await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Второй',
      amountCents: 200_000,
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Живой',
      amountCents: 300_000,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );

    final expired = await store.expireCredits();

    expect(expired, 2);
    expect(
      store.credits.where((c) => c.status == 'expired').map((c) => c.title).toSet(),
      {'Первый', 'Второй'},
    );
  });

  test('expired credit leaves the balance alone', () async {
    final client = await store.createClient(name: 'Vera');
    await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    final balance = store.totalBalanceCents();
    final txCount = store.moneyTransactions.length;

    await store.expireCredits();

    expect(store.totalBalanceCents(), balance);
    expect(store.moneyTransactions.length, txCount);
  });

  test('expired credit stops being an obligation', () async {
    final client = await store.createClient(name: 'Gleb');
    await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(store.clientCreditTotalCents, 300_000);

    await store.expireCredits();

    expect(store.clientCreditTotalCents, 0);
  });

  test('expiry cannot be spent', () async {
    final client = await store.createClient(name: 'Diana');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    await store.expireCredits();

    final used = await store.useClientCredit(
      creditId: credit.id,
      amountCents: 100_000,
    );

    expect(used, 0);
    expect(store.clientCreditById(credit.id)!.remainingCents, 300_000);
  });

  test('expiry is recorded in the audit history', () async {
    final client = await store.createClient(name: 'Max');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'pass',
      title: 'Абонемент',
      amountCents: 250_000,
      unitsTotal: 5,
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    await store.expireCredits();

    final history = store.creditHistory(credit.id);
    expect(history.map((c) => c.action), contains('credit.expire'));
    // Обязательство снято, но деньги остались: delta по remaining = 0.
    expect(
      history.firstWhere((c) => c.action == 'credit.expire').deltaCents,
      0,
    );
  });

  test('expireCredits is idempotent', () async {
    final client = await store.createClient(name: 'Igor');
    await store.createClientCredit(
      clientId: client.id,
      kind: 'certificate',
      title: 'Сертификат',
      amountCents: 300_000,
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    expect(await store.expireCredits(), 1);
    expect(await store.expireCredits(), 0);
    expect(store.creditHistory(store.credits.single.id).length, 2);
  });

  test('credit without a date never expires', () async {
    final client = await store.createClient(name: 'Nina');
    final credit = await store.createClientCredit(
      clientId: client.id,
      kind: 'deposit',
      title: 'Депозит',
      amountCents: 400_000,
    );

    await store.load();

    expect(store.clientCreditById(credit.id)!.status, 'active');
    expect(store.clientCreditTotalCents, 400_000);
  });
}
