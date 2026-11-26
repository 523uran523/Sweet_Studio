import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/appointment.dart';
import 'package:masters/data/models/inventory_composition.dart';
import 'package:masters/data/models/job.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<MastersStore> loadStore(AppDatabase db) async {
  final store = MastersStore(db, await SettingsController.load());
  addTearDown(store.dispose);
  await store.load();
  return store;
}

Future<MastersStore> openMemoryStore() async {
  final db = await AppDatabase.open(path: inMemoryDatabasePath);
  addTearDown(db.close);
  return loadStore(db);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final day = DateTime(2026, 6, 15);

  test('A: appliance repair retains cost and debt after completion', () async {
    final store = await openMemoryStore();
    final client = await store.createClient(name: 'Клиент мастерской А');
    final appliance = await store.createObject(
      clientId: client.id,
      title: 'Стиральная машина А',
    );
    final job = await store.createJob(
      clientId: client.id,
      objectId: appliance.id,
      title: 'Замена насоса',
      dueDate: day.add(const Duration(hours: 10)),
    );
    final diagnosis = await store.convertJobToAppointment(job.id);
    expect(diagnosis.clientId, client.id);
    expect(diagnosis.objectId, appliance.id);
    expect(diagnosis.startAt, job.dueDate);
    await store.setAppointmentStatus(diagnosis.id, AppointmentStatus.done);

    final pump = await store.createInventoryItem(
      name: 'Насос А',
      sellPriceCents: 240000,
      costCents: 150000,
    );
    await store.receiveStock(itemId: pump.id, qty: 2);
    await store.addMaterial(
      jobId: job.id,
      name: 'Диагностика и замена',
      priceCents: 160000,
    );
    await store.addCatalogLine(jobId: job.id, itemId: pump.id);
    await store.recalcJobTotals(job.id);
    await store.adjustStock(
      itemId: pump.id,
      delta: -1,
      type: 'writeoff',
      refType: 'job',
      refId: job.id,
    );
    await store.addSession(
      jobId: job.id,
      startedAt: diagnosis.startAt,
      minutes: 75,
    );
    await store.addTransaction(
      accountId: store.accounts.single.id,
      kind: 'payment',
      direction: 'in',
      amountCents: 175000,
      clientId: client.id,
      jobId: job.id,
    );
    await store.setJobStatus(job.id, JobStatus.done);

    expect(store.jobById(job.id)?.status, JobStatus.done);
    expect(store.jobById(job.id)?.priceCents, 400000);
    expect(store.totalMinutesForJob(job.id), 75);
    expect(store.inventoryItems.single.stockQty, 1);
    expect(store.jobCostCents(job.id), 150000);
    expect(store.jobMarginCents(job.id), 250000);
    expect(store.paidForJob(job.id), 175000);
    expect(store.receivableForJob(job.id), 225000);
    expect(store.clientDebtCents(client.id), 225000);
    expect(
      await store.auditEntries(),
      contains(containsPair('action', 'money.transaction.add')),
    );

    await store.duplicateJob(job.id);
    final repeat = store.jobs.singleWhere((entry) => entry.id != job.id);
    expect(repeat.clientId, client.id);
    expect(repeat.status, JobStatus.nuevo);
    expect(store.jobLines(repeat.id), hasLength(2));
    expect(store.paidForJob(repeat.id), 0);
    expect(store.totalMinutesForJob(repeat.id), 0);
    expect(store.inventoryItems.single.stockQty, 1);
  });

  test('B: field payment survives reopening and repeated delivery', () async {
    final directory = await Directory.systemTemp.createTemp('masters-field-');
    addTearDown(() => directory.delete(recursive: true));
    final previousBackupPath = AppDatabase.backupsDirectoryOverride;
    AppDatabase.backupsDirectoryOverride = directory.path;
    addTearDown(
      () => AppDatabase.backupsDirectoryOverride = previousBackupPath,
    );
    final path = p.join(directory.path, 'field.db');
    final initialDb = await AppDatabase.open(path: path);
    late final String jobId;
    late final String visitId;
    late final String paymentId;
    try {
      final store = await loadStore(initialDb);
      final lead = await store.createLead(
        name: 'Клиент выездного мастера Б',
        request: 'Протечка под раковиной',
        budgetCents: 320000,
      );
      final job = await store.convertLeadToJob(
        lead.id,
        title: 'Устранение протечки',
        dueAt: day.add(const Duration(hours: 11)),
      );
      jobId = job.id;
      expect(store.leadById(lead.id)?.convertedJobId, jobId);
      final visit = await store.convertJobToAppointment(jobId);
      visitId = visit.id;
      await expectLater(
        store.createAppointment(
          title: 'Другой выезд на этот слот',
          startAt: visit.startAt.add(const Duration(minutes: 15)),
          endAt: visit.endAt,
        ),
        throwsStateError,
      );
      await store.addMaterial(jobId: jobId, name: 'Уплотнение', kind: 'good');
      await store.addSession(
        jobId: jobId,
        startedAt: visit.startAt,
        minutes: 45,
      );
      final payment = await store.addTransaction(
        accountId: store.accounts.single.id,
        kind: 'payment',
        direction: 'in',
        amountCents: 320000,
        clientId: job.clientId,
        jobId: jobId,
      );
      paymentId = payment.id;
    } finally {
      await initialDb.close();
    }

    final reopenedDb = await AppDatabase.open(path: path);
    addTearDown(reopenedDb.close);
    final reopened = await loadStore(reopenedDb);
    expect(reopened.appointmentById(visitId)?.title, 'Устранение протечки');
    expect(reopened.jobLines(jobId).single.name, 'Уплотнение');
    expect(reopened.totalMinutesForJob(jobId), 45);
    expect(reopened.paidForJob(jobId), 320000);

    final batch = await reopenedDb.collectSyncBatch(deviceId: 'fixture-field');
    final receivingDb = await AppDatabase.open(
      path: p.join(directory.path, 'office.db'),
    );
    addTearDown(receivingDb.close);
    expect(batch.rows.where((row) => row.id == paymentId), hasLength(1));
    await receivingDb.applySyncRows(batch.rows);
    final receiving = await loadStore(receivingDb);
    expect(receiving.moneyTransactions.single.id, paymentId);
    expect(receiving.paidForJob(jobId), 320000);

    await receivingDb.applySyncRows(batch.rows);
    await receiving.load();
    expect(receiving.moneyTransactions.single.id, paymentId);
    expect(receiving.paidForJob(jobId), 320000);
    expect(receiving.receivableForJob(jobId), 0);
    expect(await receivingDb.integrityIssues(), isEmpty);
  });

  test('C: crew time, advance, purchases and payouts reconcile', () async {
    final store = await openMemoryStore();
    final client = await store.createClient(name: 'Клиент бригады В');
    final site = await store.createObject(
      clientId: client.id,
      title: 'Объект В',
    );
    final leadWorker = await store.createEmployee(
      name: 'Бригадир В',
      payType: 'hourly',
      rateCents: 95000,
    );
    final helper = await store.createEmployee(
      name: 'Помощник В',
      payType: 'hourly',
      rateCents: 64000,
    );
    final job = await store.createJob(
      clientId: client.id,
      objectId: site.id,
      assigneeId: leadWorker.id,
      title: 'Ремонт комнаты',
      priceCents: 2000000,
    );
    final stage = await store.addStage(job.id, 'Подготовка');
    await store.addStage(job.id, 'Отделка');
    await store.toggleStage(stage.id);
    final account = store.accounts.single;
    final advance = await store.addTransaction(
      accountId: account.id,
      kind: 'payment',
      direction: 'in',
      amountCents: 750000,
      clientId: client.id,
      jobId: job.id,
    );
    final primer = await store.createInventoryItem(name: 'Грунт', unit: 'л');
    final payrollStart = advance.createdAt.subtract(const Duration(days: 1));
    final payrollEnd = advance.createdAt.add(const Duration(days: 1));
    final purchase = await store.createPurchase(
      accountId: account.id,
      paidCents: 105000,
      lines: [
        {'itemId': primer.id, 'qty': 3, 'unitPriceCents': 35000},
      ],
    );
    await store.addTimeEntry(
      employeeId: leadWorker.id,
      jobId: job.id,
      startedAt: payrollStart,
      minutes: 180,
    );
    await store.addTimeEntry(
      employeeId: helper.id,
      jobId: job.id,
      startedAt: payrollStart,
      minutes: 150,
    );
    await store.addEmployeePayment(
      employeeId: leadWorker.id,
      type: 'advance',
      amountCents: 70000,
    );
    await store.addEmployeePayment(
      employeeId: leadWorker.id,
      type: 'payout',
      amountCents: 95000,
    );
    await store.addEmployeePayment(
      employeeId: helper.id,
      type: 'payout',
      amountCents: 60000,
    );
    await store.setJobStatus(job.id, JobStatus.done);
    final period = await store.createPayrollPeriod(
      name: 'Период В',
      startAt: payrollStart,
      endAt: payrollEnd,
    );
    await store.closePayrollPeriod(period.id);

    expect(store.payrollPeriods.single.isClosed, isTrue);
    expect(
      store.stagesForJob(job.id).where((stage) => stage.done),
      hasLength(1),
    );
    expect(
      store.earnedCentsForPeriod(leadWorker.id, period.startAt, period.endAt),
      285000,
    );
    expect(
      store.earnedCentsForPeriod(helper.id, period.startAt, period.endAt),
      160000,
    );
    expect(store.employeeBalanceOwed(leadWorker.id), 120000);
    expect(store.employeeBalanceOwed(helper.id), 100000);
    final payroll = store.payrollSummary(period.startAt, period.endAt);
    expect(
      payroll.map((row) => row['net']),
      unorderedEquals([0, 120000, 100000]),
    );
    expect(store.receivableForJob(job.id), 1250000);
    expect(store.inventoryItems.single.stockQty, 3);
    expect(purchase.totalCents, 105000);
    expect(store.moneyTransactions, hasLength(5));
    expect(store.balanceCents(account.id), 420000);

    await store.closePeriod(start: payrollStart, end: payrollEnd);
    await expectLater(
      store.addEmployeePayment(
        employeeId: helper.id,
        type: 'payout',
        amountCents: 10000,
      ),
      throwsStateError,
    );
    expect(store.moneyTransactions, hasLength(5));
  });

  test('D: workshop purchases materials and costs a finished order', () async {
    final store = await openMemoryStore();
    final client = await store.createClient(name: 'Клиент мастерской Г');
    final oil = await store.createInventoryItem(
      name: 'Масло для дерева',
      unit: 'л',
      costCents: 100000,
    );
    final shelf = await store.createInventoryItem(
      name: 'Деревянная полка',
      sellPriceCents: 300000,
    );
    await store.saveItemComposition(shelf.id, [
      InventoryCompositionLine(
        id: '',
        itemId: shelf.id,
        componentId: oil.id,
        qty: 0.5,
        priceCents: 100000,
      ),
    ]);
    final quantityBeforePurchase = store.inventoryItems
        .singleWhere((item) => item.id == oil.id)
        .stockQty;
    expect(quantityBeforePurchase, 0);
    final purchase = await store.createPurchase(
      lines: [
        {'itemId': oil.id, 'qty': 2.5, 'unitPriceCents': 100000},
      ],
    );
    final job = await store.createJob(clientId: client.id, title: 'Две полки');
    final line = await store.addCatalogLine(
      jobId: job.id,
      itemId: shelf.id,
      quantity: 2,
    );
    await store.recalcJobTotals(job.id);
    await store.writeOffJobMaterials(job.id, lineIds: [line.id]);
    await store.addTransaction(
      accountId: store.accounts.single.id,
      kind: 'payment',
      direction: 'in',
      amountCents: 600000,
      clientId: client.id,
      jobId: job.id,
    );
    await store.setJobStatus(job.id, JobStatus.closed);

    expect(purchase.totalCents, 250000);
    expect(
      store.inventoryItems.singleWhere((item) => item.id == oil.id).stockQty,
      1.5,
    );
    final usage = store
        .movementsForItem(oil.id)
        .singleWhere((entry) => entry.refId == job.id);
    expect(usage.qty, 1);
    expect(usage.unitCostCents, 100000);
    expect(store.jobCostCents(job.id), 100000);
    expect(store.jobMarginCents(job.id), 500000);
    expect(store.receivableForJob(job.id), 0);
    expect(store.jobById(job.id)?.status, JobStatus.closed);
  });

  test(
    'E: solo booking reschedule and cancellation with daily revenue',
    () async {
      final store = await openMemoryStore();
      final client = await store.createClient(
        name: 'Клиент частного мастера Д',
      );
      final originalStart = day.add(const Duration(hours: 9));
      final rescheduledStart = day.add(const Duration(hours: 11));
      final appointment = await store.createAppointment(
        clientId: client.id,
        title: 'Настройка инструмента',
        startAt: originalStart,
      );
      final cancelled = await store.createAppointment(
        clientId: client.id,
        title: 'Отдельная консультация',
        startAt: day.add(const Duration(hours: 14)),
      );
      await store.updateAppointment(
        appointment.copyWith(
          startAt: rescheduledStart,
          endAt: rescheduledStart.add(const Duration(hours: 1)),
        ),
      );
      await store.setAppointmentStatus(
        cancelled.id,
        AppointmentStatus.cancelled,
      );
      final repeat = await store.createAppointment(
        clientId: client.id,
        title: 'Повторная настройка',
        startAt: originalStart,
      );
      expect(store.appointmentsForDay(day).map((item) => item.id), [
        repeat.id,
        appointment.id,
        cancelled.id,
      ]);
      expect(
        store.appointmentById(cancelled.id)?.status,
        AppointmentStatus.cancelled,
      );
      await store.setAppointmentStatus(appointment.id, AppointmentStatus.done);
      await store.convertAppointmentToJob(appointment.id);
      final job = store.jobs.single;
      expect(job.clientId, client.id);
      expect(job.dueDate, rescheduledStart);
      expect(job.status, JobStatus.done);

      final payment = await store.addTransaction(
        accountId: store.accounts.single.id,
        kind: 'payment',
        direction: 'in',
        amountCents: 95000,
        clientId: client.id,
        jobId: job.id,
      );
      final paidAt = payment.createdAt;
      final dayStart = DateTime(paidAt.year, paidAt.month, paidAt.day);
      final dayEnd = DateTime(paidAt.year, paidAt.month, paidAt.day + 1);
      final monthStart = DateTime(paidAt.year, paidAt.month);
      final monthEnd = DateTime(paidAt.year, paidAt.month + 1);
      expect(store.recognizedRevenueCents(dayStart, dayEnd), 95000);
      expect(store.recognizedRevenueCents(monthStart, monthEnd), 95000);
      expect(
        store.recognizedRevenueCents(
          dayEnd,
          dayEnd.add(const Duration(days: 1)),
        ),
        0,
      );
    },
  );

  test(
    'backup replay and invalid restore preserve the original payment',
    () async {
      final store = await openMemoryStore();
      final client = await store.createClient(name: 'Клиент из теста бэкапа');
      final job = await store.createJob(
        clientId: client.id,
        title: 'Заказ из теста бэкапа',
        priceCents: 120000,
      );
      Future<void> pay(int amountCents) => store.addTransaction(
        accountId: store.accounts.single.id,
        kind: 'payment',
        direction: 'in',
        amountCents: amountCents,
        clientId: client.id,
        jobId: job.id,
      );
      await expectLater(pay(0), throwsArgumentError);
      expect(store.moneyTransactions, isEmpty);
      await pay(45000);

      final backup = store.backupData();
      final payments = store.moneyTransactions.single;
      final account = store.accounts.single;
      await store.mergeFromBackup(backup);
      await store.mergeFromBackup(backup);
      await expectLater(
        store.restoreFromBackup({'format': 'invalid', 'version': 9}),
        throwsFormatException,
      );
      expect(store.moneyTransactions.single.id, payments.id);
      expect(store.moneyTransactions.single.accountId, account.id);
      expect(store.moneyTransactions.single.jobId, job.id);
      expect(store.paidForJob(job.id), 45000);
      expect(store.receivableForJob(job.id), 75000);
      expect(store.totalBalanceCents(), 45000);
    },
  );
}
