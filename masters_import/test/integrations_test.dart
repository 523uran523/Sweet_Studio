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

  test('transfer between accounts keeps total balance unchanged', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final source = store.accounts.first;
      final target = await store.createAccount(name: 'Bank', type: 'bank');

      // Give the source account some money first.
      await store.addTransaction(
        accountId: source.id,
        kind: 'income',
        direction: 'in',
        amountCents: 1000,
        category: 'Test',
      );

      final totalBefore = store.totalBalanceCents();
      final sourceBefore = store.balanceCents(source.id);
      final targetBefore = store.balanceCents(target.id);

      await store.transferBetweenAccounts(source.id, target.id, 350);

      expect(store.balanceCents(source.id), sourceBefore - 350);
      expect(store.balanceCents(target.id), targetBefore + 350);
      expect(store.totalBalanceCents(), totalBefore);
      expect(store.moneyTransactions.any((t) => t.kind == 'transfer'), isTrue);
    } finally {
      await appDb.close();
    }
  });

  test('employee advance and payout are reflected in money journal', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final employee = await store.createEmployee(name: 'Anna', payType: 'hourly');
      await store.addEmployeePayment(
        employeeId: employee.id,
        type: 'advance',
        amountCents: 200,
        note: 'advance for shifts',
      );
      await store.addEmployeePayment(
        employeeId: employee.id,
        type: 'payout',
        amountCents: 100,
        note: 'weekly payout',
      );

      final txs = store.moneyTransactions.where((t) => t.kind == 'employee_payment').toList();
      expect(txs.length, 2);
      expect(store.totalBalanceCents(), -300);
      expect(store.employeeBalanceOwed(employee.id), isA<int>());
    } finally {
      await appDb.close();
    }
  });

  test('integrity check on a fresh database is clean', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      await appDb.integrityIssues();
      final issues = await appDb.integrityIssues();
      expect(issues, isEmpty);
    } finally {
      await appDb.close();
    }
  });
}
