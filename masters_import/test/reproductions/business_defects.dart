// Run explicitly to reproduce the open defects documented in
// docs/specs/2026-11-14-business-scenarios-audit.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late AppDatabase db;
  late MastersStore store;
  final day = DateTime(2026, 6, 15);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    store = MastersStore(db, await SettingsController.load());
    addTearDown(store.dispose);
    await store.load();
  });

  test('closed payroll retains historical earnings', () async {
    final employee = await store.createEmployee(
      name: 'Мастер А',
      payType: 'hourly',
      rateCents: 100000,
    );
    final end = day.add(const Duration(days: 1));
    await store.addTimeEntry(
      employeeId: employee.id,
      startedAt: day,
      minutes: 60,
    );
    final period = await store.createPayrollPeriod(
      name: 'Период А',
      startAt: day,
      endAt: end,
    );
    await store.closePayrollPeriod(period.id, at: end);
    expect(store.earnedCentsForPeriod(employee.id, day, end), 100000);
    await store.updateEmployee(employee.copyWith(rateCents: 130000));
    expect(store.earnedCentsForPeriod(employee.id, day, end), 100000);
  });

  test('repeating conversion of a lead preserves one job', () async {
    final lead = await store.createLead(name: 'Клиент Б');
    await store.convertLeadToJob(lead.id, title: 'Выезд');
    try {
      await store.convertLeadToJob(lead.id, title: 'Выезд');
    } on StateError {
      // Rejecting a repeated conversion also keeps the existing job.
    }
    expect(store.jobs.where((job) => job.leadId == lead.id), hasLength(1));
  });

  test('first delivery includes a converted lead and its job', () async {
    final lead = await store.createLead(name: 'Клиент выездного мастера');
    final job = await store.convertLeadToJob(lead.id, title: 'Выезд');
    final batch = await db.collectSyncBatch(deviceId: 'fixture-field');
    final directory = await Directory.systemTemp.createTemp('masters-lead-');
    addTearDown(() => directory.delete(recursive: true));
    final previousBackupPath = AppDatabase.backupsDirectoryOverride;
    AppDatabase.backupsDirectoryOverride = directory.path;
    addTearDown(
      () => AppDatabase.backupsDirectoryOverride = previousBackupPath,
    );
    final receiving = await AppDatabase.open(
      path: p.join(directory.path, 'office.db'),
    );
    addTearDown(receiving.close);
    await receiving.applySyncRows(batch.rows);

    final leads = await receiving.database.query('leads');
    final jobs = await receiving.database.query('jobs');
    expect(leads, hasLength(1));
    expect(jobs, hasLength(1));
    expect(leads.single['converted_job_id'], job.id);
    expect(jobs.single['lead_id'], lead.id);
  });
}
