import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masters/data/app_database.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('tax radar store calculations', () {
    test('0 transactions => 0 income, 0 progress, full left', () async {
      final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        final settings = await SettingsController.load();
        await settings.setTaxIncomeLimitCents(100000);
        final store = MastersStore(appDb, settings);
        await store.load();
        expect(store.annualIncomeCents(), 0);
        expect(store.taxRadarProgress, 0.0);
        expect(store.taxRadarLeftCents, 100000);
      } finally {
        await appDb.close();
      }
    });

    test('50% scenario', () async {
      final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        final settings = await SettingsController.load();
        await settings.setTaxIncomeLimitCents(100000);
        final store = MastersStore(appDb, settings);
        await store.load();
        final account = await store.createAccount(name: 'Cash', type: 'cash');
        await store.addTransaction(
          accountId: account.id,
          kind: 'sale',
          direction: 'in',
          amountCents: 50000,
        );
        expect(store.annualIncomeCents(), 50000);
        expect(store.taxRadarProgress, closeTo(0.5, 1e-9));
        expect(store.taxRadarLeftCents, 50000);
      } finally {
        await appDb.close();
      }
    });

    test('100% scenario', () async {
      final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        final settings = await SettingsController.load();
        await settings.setTaxIncomeLimitCents(100000);
        final store = MastersStore(appDb, settings);
        await store.load();
        final account = await store.createAccount(name: 'Cash', type: 'cash');
        await store.addTransaction(
          accountId: account.id,
          kind: 'sale',
          direction: 'in',
          amountCents: 100000,
        );
        expect(store.annualIncomeCents(), 100000);
        expect(store.taxRadarProgress, closeTo(1.0, 1e-9));
        expect(store.taxRadarLeftCents, 0);
      } finally {
        await appDb.close();
      }
    });

    test('over limit is clamped', () async {
      final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        final settings = await SettingsController.load();
        await settings.setTaxIncomeLimitCents(100000);
        final store = MastersStore(appDb, settings);
        await store.load();
        final account = await store.createAccount(name: 'Cash', type: 'cash');
        await store.addTransaction(
          accountId: account.id,
          kind: 'sale',
          direction: 'in',
          amountCents: 150000,
        );
        expect(store.annualIncomeCents(), 150000);
        expect(store.taxRadarProgress, closeTo(1.0, 1e-9));
        expect(store.taxRadarLeftCents, 0);
      } finally {
        await appDb.close();
      }
    });

    test('voided transactions excluded', () async {
      final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
      try {
        final settings = await SettingsController.load();
        await settings.setTaxIncomeLimitCents(100000);
        final store = MastersStore(appDb, settings);
        await store.load();
        final account = await store.createAccount(name: 'Cash', type: 'cash');
        final tx = await store.addTransaction(
          accountId: account.id,
          kind: 'sale',
          direction: 'in',
          amountCents: 40000,
        );
        await store.voidTransaction(tx.id);
        expect(store.annualIncomeCents(), 0);
      } finally {
        await appDb.close();
      }
    });
  });

  test('settings tax radar toggle & limit', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    expect(settings.taxRadarEnabled, isTrue);
    expect(settings.taxIncomeLimitCents, 240000000);
    await settings.setTaxRadarEnabled(false);
    expect(settings.taxRadarEnabled, isFalse);
    await settings.setTaxRadarEnabled(true);
    expect(settings.taxRadarEnabled, isTrue);
    await settings.setTaxIncomeLimitCents(100000);
    expect(settings.taxIncomeLimitCents, 100000);
  });
}
