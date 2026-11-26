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

  test('recurring payment active state can be disabled and is skipped when due',
      () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final account = await store.createAccount(name: 'Cash', type: 'cash');
      final enabledPayment = await store.createRecurringPayment(
        name: 'Enabled Rent',
        amountCents: 1000,
        intervalDays: 30,
        accountId: account.id,
        nextDueAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final disabledPayment = await store.createRecurringPayment(
        name: 'Disabled Rent',
        amountCents: 1000,
        intervalDays: 30,
        accountId: account.id,
        nextDueAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      await store.updateRecurringPayment(disabledPayment.copyWith(active: false));

      final active = store.recurringPayments
          .where((p) => p.id == enabledPayment.id)
          .single
          .active;
      final inactive = store.recurringPayments
          .where((p) => p.id == disabledPayment.id)
          .single
          .active;
      expect(active, isTrue);
      expect(inactive, isFalse);

      final posted = await store.runDueRecurringPayments();
      expect(posted, 1);
      expect(store.totalBalanceCents(), -1000);
    } finally {
      await appDb.close();
    }
  });
}
