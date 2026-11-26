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

  test('merge duplicate client reassigns all linked rows', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      final settings = await SettingsController.load();
      final store = MastersStore(appDb, settings);
      await store.load();

      final source = await store.createClient(
        name: 'Source Client',
        phone: '1234567890',
      );
      final target = await store.createClient(name: 'Target Client', phone: '');

      final object = await store.createObject(
        clientId: source.id,
        title: 'Object 1',
      );
      final job = await store.createJob(
        clientId: source.id,
        objectId: object.id,
        title: 'Job 1',
      );
      final appointment = await store.createAppointment(
        title: 'Appointment 1',
        clientId: source.id,
      );
      final reminder = await store.createReminder(
        clientId: source.id,
        title: 'Reminder 1',
        dueAt: DateTime.now().add(const Duration(days: 1)),
      );
      final account = await store.createAccount(name: 'Cash', type: 'cash');
      final tx = await store.addTransaction(
        accountId: account.id,
        kind: 'payment',
        direction: 'in',
        amountCents: 1000,
        clientId: source.id,
        jobId: job.id,
      );

      await store.mergeClientInto(sourceId: source.id, targetId: target.id);

      expect(store.clients.any((c) => c.id == source.id), isFalse);
      expect(store.clients.any((c) => c.id == target.id), isTrue);

      final movedObject = store.objects.firstWhere((o) => o.id == object.id);
      expect(movedObject.clientId, target.id);

      final movedJob = store.jobs.firstWhere((j) => j.id == job.id);
      expect(movedJob.clientId, target.id);

      final movedAppointment = store.appointments.firstWhere(
        (a) => a.id == appointment.id,
      );
      expect(movedAppointment.clientId, target.id);

      final movedReminder = store.reminders.firstWhere(
        (r) => r.id == reminder.id,
      );
      expect(movedReminder.clientId, target.id);

      final movedTx = store.moneyTransactions.firstWhere((t) => t.id == tx.id);
      expect(movedTx.clientId, target.id);
      expect(movedTx.jobId, job.id);
    } finally {
      await appDb.close();
    }
  });
}
