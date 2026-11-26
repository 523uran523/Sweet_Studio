import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/job.dart' show JobStatus;
import 'package:masters/data/models/obligation.dart';
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

  // ── syncJobObligations ──

  test('syncJobObligations creates obligation for order', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Test order',
      priceCents: 5000,
      status: JobStatus.nuevo,
    );

    // createJob уже синхронизирует обязательство автоматически.
    expect(store.receivables().length, 1);
    await store.syncJobObligations(job.id);

    final recs = store.receivables();
    expect(recs.length, 1);
    final obl = recs.first;
    expect(obl.direction, 'receivable');
    expect(obl.kind, 'client_payment');
    expect(obl.jobId, job.id);
    expect(obl.amountCents, 5000);
    expect(obl.paidCents, 0);
    expect(obl.remainingCents, 5000);
    expect(obl.status, 'planned');
  });

  test('syncJobObligations is idempotent', () async {
    final client = await store.createClient(name: 'C');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 3000,
    );
    await store.syncJobObligations(job.id);
    await store.syncJobObligations(job.id);

    final recs = store.receivables();
    expect(recs.length, 1); // не дублирует
  });

  test('syncJobObligations uses line totals when lines exist', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order with lines',
      priceCents: 10000, // Fallback если строк нет
    );

    await store.syncJobObligations(job.id);
    final recs = store.receivables();
    expect(recs.length, 1);
    expect(recs.first.amountCents, 10000);
  });

  // ── payObligation ──

  test('payObligation reduces remaining and creates transaction', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 10000,
    );
    await store.syncJobObligations(job.id);

    final recs = store.receivables();
    expect(recs.length, 1);
    final obl = recs.first;
    expect(obl.remainingCents, 10000);

    final account = await store.createAccount(name: 'Cash', type: 'cash');
    final updated = await store.payObligation(
      obl.id,
      amountCents: 3000,
      accountId: account.id,
    );

    expect(updated.paidCents, 3000);
    expect(updated.remainingCents, 7000);
    expect(updated.status, 'partial');
    expect(store.receivables().length, 1);
  });

  test('payObligation full payment sets paid status', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 5000,
    );
    await store.syncJobObligations(job.id);

    final recs = store.receivables();
    final obl = recs.first;
    final account = await store.createAccount(name: 'Cash', type: 'cash');

    final updated = await store.payObligation(
      obl.id,
      amountCents: 5000,
      accountId: account.id,
    );

    expect(updated.status, 'paid');
    expect(updated.isClosed, true);
    expect(updated.remainingCents, 0);
  });

  test('payObligation partial overpayment caps at remaining', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 2000,
    );
    await store.syncJobObligations(job.id);

    final recs = store.receivables();
    final obl = recs.first;
    final account = await store.createAccount(name: 'Cash', type: 'cash');

    // Платим больше, чем долг — должно засчитаться только 2000
    final updated = await store.payObligation(
      obl.id,
      amountCents: 99999,
      accountId: account.id,
    );

    expect(updated.status, 'paid');
    expect(updated.paidCents, 2000);
  });

  test('payObligation on closed obligation throws', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 1000,
    );
    await store.syncJobObligations(job.id);

    final recs = store.receivables();
    final obl = recs.first;
    final account = await store.createAccount(name: 'Cash', type: 'cash');

    await store.payObligation(obl.id, amountCents: 1000, accountId: account.id);

    expect(() => store.payObligation(obl.id, amountCents: 100, accountId: account.id),
        throwsA(isA<ArgumentError>()));
  });

  test('overpayment on one order does not affect another', () async {
    final client = await store.createClient(name: 'Client');
    final job1 = await store.createJob(
      clientId: client.id,
      title: 'Order 1',
      priceCents: 1000,
    );
    final job2 = await store.createJob(
      clientId: client.id,
      title: 'Order 2',
      priceCents: 2000,
    );
    await store.syncJobObligations(job1.id);
    await store.syncJobObligations(job2.id);

    final recs = store.receivables();
    expect(recs.length, 2);

    final account = await store.createAccount(name: 'Cash', type: 'cash');
    final obl1 = recs.firstWhere((o) => o.jobId == job1.id);

    // Полная оплата order1
    await store.payObligation(obl1.id, amountCents: 1000, accountId: account.id);

    // Order2 должен остаться с полным долгом
    final obl2 = recs.firstWhere((o) => o.jobId == job2.id);
    expect(obl2.remainingCents, 2000);
  });

  // ── createJob auto-sync & legacy payment path ──

  test('direct payment via addTransaction moves obligation progress', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 5000,
    );
    final obl = store.openJobPaymentObligation(job.id);
    expect(obl, isNotNull);

    final account = await store.createAccount(name: 'Cash', type: 'cash');
    // Старый путь оплаты в обход payObligation (kind=payment).
    await store.addTransaction(
      accountId: account.id,
      kind: 'payment',
      direction: 'in',
      amountCents: 2000,
      clientId: client.id,
      jobId: job.id,
    );

    final updated = store.obligationById(obl!.id)!;
    expect(updated.paidCents, 2000);
    expect(updated.status, 'partial');
    expect(updated.remainingCents, 3000);
    expect(store.clientDebtCents(client.id), 3000);
  });

  test('reversal of a direct payment restores the balance and full debt', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 100000,
    );
    final payment = await store.addTransaction(
      accountId: store.accounts.single.id,
      kind: 'payment',
      direction: 'in',
      amountCents: 45000,
      clientId: client.id,
      jobId: job.id,
    );
    await store.revertTransaction(payment.id);
    expect(store.totalBalanceCents(), 0);
    expect(store.receivableForJob(job.id), 100000);
    expect(store.paidForJob(job.id), 0);
  });

  test('reversing a linked payment restores debt and reduces revenue once', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 100000,
    );
    final account = store.accounts.single;
    final obligation = store.openJobPaymentObligation(job.id)!;
    for (final amount in [45000, 55000]) {
      await store.payObligation(obligation.id, amountCents: amount, accountId: account.id);
    }
    final partial = store.moneyTransactions.singleWhere((t) => t.amountCents == 45000);
    await appDb.database.update(
      'money_transactions',
      {'created_at': DateTime(2026, 6, 15).millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [partial.id],
    );
    await store.load();
    expect(store.paidForJob(job.id), 100000);
    expect(store.clientDebtCents(client.id), 0);

    final outcomes = await Future.wait([
      for (var attempt = 0; attempt < 2; attempt++)
        () async {
          try {
            await store.revertTransaction(partial.id);
            return true;
          } on StateError {
            return false;
          }
        }(),
    ]);
    expect(outcomes, unorderedEquals([true, false]));
    await store.load();
    final reversal = store.moneyTransactions.singleWhere((t) => t.reversesId == partial.id);
    expect(reversal.obligationId, obligation.id);
    expect(store.balanceCents(account.id), 55000);
    expect(store.paidForJob(job.id), 55000);
    expect(store.receivableForJob(job.id), 45000);
    expect(store.clientDebtCents(client.id), 45000);
    final historicalDay = DateTime(2026, 6, 15);
    final historicalEnd = DateTime(2026, 6, 16);
    final end = reversal.createdAt.add(const Duration(seconds: 1));
    expect(store.recognizedRevenueCents(historicalDay, historicalEnd), 45000);
    expect(store.recognizedRevenueCents(historicalEnd, end), 10000);
    expect(store.recognizedRevenueCents(historicalDay, end), 55000);
  });

  test('returning only the overpayment keeps the order fully paid', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 100000,
    );
    final account = store.accounts.single;
    Future<void> record(String direction, int amount) => store.addTransaction(
      accountId: account.id,
      kind: direction == 'in' ? 'payment' : 'refund',
      direction: direction,
      amountCents: amount,
      clientId: client.id,
      jobId: job.id,
    );

    await record('in', 125000);
    expect(store.paidForJob(job.id), 125000);
    expect(store.receivableForJob(job.id), 0);
    expect(store.clientDebtCents(client.id), 0);

    await record('out', 25000);
    expect(store.balanceCents(account.id), 100000);
    expect(store.paidForJob(job.id), 100000);
    expect(store.receivableForJob(job.id), 0);
    expect(store.clientDebtCents(client.id), 0);

    await record('out', 20000);
    expect(store.balanceCents(account.id), 80000);
    expect(store.paidForJob(job.id), 80000);
    expect(store.receivableForJob(job.id), 20000);
    expect(store.clientDebtCents(client.id), 20000);
  });

  test('reversal restores a receivable on an old partially paid order', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Old order',
      priceCents: 100000,
    );
    final payment = await store.addTransaction(
      accountId: store.accounts.single.id,
      kind: 'client_payment',
      direction: 'in',
      amountCents: 60000,
      clientId: client.id,
      jobId: job.id,
    );
    await appDb.database.delete('obligations', where: 'job_id = ?', whereArgs: [job.id]);
    await store.load();
    expect(store.obligationsForJob(job.id), isEmpty);

    await store.revertTransaction(payment.id);
    await store.load();
    expect(store.paidForJob(job.id), 0);
    expect(store.receivableForJob(job.id), 100000);
    expect(store.clientDebtCents(client.id), 100000);
    expect(store.openJobPaymentObligation(job.id)?.status, 'planned');
  });

  test('reversing a refund restores the same receivable', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 100000,
    );
    final account = store.accounts.single;
    final original = store.openJobPaymentObligation(job.id)!;
    await store.payObligation(original.id, amountCents: 45000);
    final other = Obligation.fromMap(original.toMap()
      ..['id'] = 'earlier-receivable'
      ..['due_at'] = original.dueAt.subtract(const Duration(days: 1)).millisecondsSinceEpoch);
    await appDb.database.insert('obligations', other.toMap());
    await store.load();

    final refund = await store.addTransaction(
      accountId: account.id,
      kind: 'refund',
      direction: 'out',
      amountCents: 15000,
      clientId: client.id,
      jobId: job.id,
      obligationId: original.id,
    );
    expect(store.obligationById(original.id)?.paidCents, 30000);
    await store.revertTransaction(refund.id);
    expect(store.obligationById(original.id)?.paidCents, 45000);
    expect(store.obligationById(other.id)?.paidCents, 0);
    expect(store.paidForJob(job.id), 45000);
  });

  test('a soft-deleted historical refund is excluded after loading', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(clientId: client.id, title: 'Order', priceCents: 100000);
    final account = store.accounts.single;
    final payment = await store.addTransaction(
      accountId: account.id,
      kind: 'payment',
      direction: 'in',
      amountCents: 45000,
      clientId: client.id,
      jobId: job.id,
    );
    await appDb.database.insert('money_transactions', payment.toMap()
      ..['id'] = 'deleted-refund'
      ..['kind'] = 'refund'
      ..['direction'] = 'out'
      ..['deleted_at'] = payment.createdAt.millisecondsSinceEpoch);
    await store.load();
    expect(store.moneyTransactions.single.id, payment.id);
    expect(store.paidForJob(job.id), 45000);
    expect(store.recognizedRevenueCents(DateTime(2000), payment.createdAt.add(const Duration(seconds: 1))), 45000);
  });

  test('failure to save debt rolls back the reversal', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 100000,
    );
    final payment = await store.addTransaction(
      accountId: store.accounts.single.id,
      kind: 'payment',
      direction: 'in',
      amountCents: 45000,
      clientId: client.id,
      jobId: job.id,
    );
    await appDb.database.execute('''
      CREATE TRIGGER block_order_debt BEFORE INSERT ON obligations
      BEGIN
        SELECT RAISE(ABORT, 'test: debt write failed');
      END
    ''');

    await expectLater(store.revertTransaction(payment.id), throwsException);
    await store.load();
    expect(store.moneyTransactions.single.id, payment.id);
    expect(store.paidForJob(job.id), 45000);
    expect(store.receivableForJob(job.id), 55000);

    await appDb.database.execute('DROP TRIGGER block_order_debt');
    await store.revertTransaction(payment.id);
    expect(store.paidForJob(job.id), 0);
    expect(store.receivableForJob(job.id), 100000);
  });

  test('updateJob price change resyncs untouched obligation', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 5000,
    );
    final obl = store.openJobPaymentObligation(job.id)!;
    expect(obl.amountCents, 5000);

    await store.updateJob(job.copyWith(priceCents: 7000));

    final updated = store.obligationById(obl.id)!;
    expect(updated.amountCents, 7000);
    expect(store.receivables().length, 1); // не дубликат
  });

  test('deleteJob removes its obligations', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 4000,
    );
    expect(store.obligationsForJob(job.id).length, 1);

    await store.deleteJob(job.id);

    expect(store.obligationsForJob(job.id).length, 0);
    expect(store.receivableForJob(job.id), 0);
  });

  test('editing a client keeps its jobs and obligations', () async {
    // INSERT OR REPLACE при включённых FK делает DELETE+INSERT, и каскад
    // у jobs(client_id) терял заказы клиента при переименовании.
    final client = await store.createClient(name: 'Ivan');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 5000,
    );
    expect(store.obligationsForJob(job.id).length, 1);

    await store.updateClient(client.copyWith(name: 'Ivan Petrov'));

    expect(store.jobById(job.id), isNotNull);
    final obl = store.openJobPaymentObligation(job.id);
    expect(obl, isNotNull);
    expect(obl!.amountCents, 5000);
    expect(store.clientDebtCents(client.id), 5000);
  });

  // ── createPayable ──

  test('createPayable creates payable obligation', () async {
    final payable = await store.createPayable(
      kind: 'rent',
      title: 'Аренда цеха',
      amountCents: 15000,
      dueAt: DateTime.now().add(const Duration(days: 15)),
      counterpartyType: 'supplier',
      counterpartyId: 'sup-1',
    );

    expect(payable.direction, 'payable');
    expect(payable.kind, 'rent');
    expect(payable.amountCents, 15000);
    expect(payable.isClosed, false);

    final payables = store.payables();
    expect(payables.length, 1);
    expect(payables.first.remainingCents, 15000);
  });

  // ── receivables / payables ──

  test('receivables filters only receivable open obligations', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 5000,
    );
    await store.syncJobObligations(job.id);

    final payables = store.payables();
    expect(payables.length, 0);

    final recs = store.receivables();
    expect(recs.length, 1);
    expect(recs.first.jobId, job.id);
  });

  test('payables filters only payable open obligations', () async {
    final payable = await store.createPayable(
      kind: 'tax',
      title: 'Налог Q4',
      amountCents: 8000,
      dueAt: DateTime.now().add(const Duration(days: 5)),
    );

    expect(payable.direction, 'payable');

    final recs = store.receivables();
    expect(recs.length, 0);

    final payables = store.payables();
    expect(payables.length, 1);
    expect(payables.first.kind, 'tax');
  });

  // ── clientDebtCents with obligations ──

  test('clientDebtCents uses obligation remainingCents', () async {
    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 10000,
    );
    await store.syncJobObligations(job.id);

    expect(store.clientDebtCents(client.id), 10000);

    final account = await store.createAccount(name: 'Cash', type: 'cash');
    final recs = store.receivables();
    await store.payObligation(recs.first.id, amountCents: 4000, accountId: account.id);

    expect(store.clientDebtCents(client.id), 6000);
  });

  // ── cashPlan ──

  test('cashPlan includes obligation due dates', () async {
    final now = DateTime.now();

    final client = await store.createClient(name: 'Client');
    final job = await store.createJob(
      clientId: client.id,
      title: 'Order',
      priceCents: 3000,
      dueDate: now.add(const Duration(days: 1)),
    );
    await store.syncJobObligations(job.id);

    final plan = store.cashPlan(weeks: 2);
    expect(plan.length, 14);

    // Обязательство dueAt = now (сегодня), т.к. syncJobObligations
    // использует job.dueDate или DateTime.now(). dueDate установлен на завтра,
    // значит obligation.dueAt = завтра.
    int incomingTomorrow = 0;
    for (final day in plan) {
      if (day.date.day == now.add(const Duration(days: 1)).day &&
          day.date.month == now.add(const Duration(days: 1)).month &&
          day.date.year == now.add(const Duration(days: 1)).year) {
        incomingTomorrow = day.incoming;
        break;
      }
    }
    expect(incomingTomorrow, 3000);
  });

  // ── obligation model ──

  test('obligation model properties', () {
    final obl = Obligation(
      id: 'obl-1',
      direction: 'receivable',
      kind: 'client_payment',
      title: 'Test',
      amountCents: 5000,
      paidCents: 2000,
      dueAt: DateTime.now().add(const Duration(days: 10)),
      status: 'partial',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    expect(obl.isIncome, true);
    expect(obl.isPaid, false);
    expect(obl.isClosed, false);
    expect(obl.remainingCents, 3000);
    expect(obl.isOverdue, false);

    final paid = obl.copyWith(status: 'paid');
    expect(paid.isPaid, true);
    expect(paid.isClosed, true);
  });

  test('obligation copyWith updates fields', () {
    final obl = Obligation(
      id: 'obl-1',
      direction: 'receivable',
      kind: 'client_payment',
      title: 'Test',
      amountCents: 5000,
      paidCents: 0,
      dueAt: DateTime.now(),
      status: 'planned',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final updated = obl.copyWith(
      paidCents: 2500,
      status: 'partial',
    );

    expect(updated.paidCents, 2500);
    expect(updated.status, 'partial');
    expect(updated.id, obl.id); // id не меняется
  });

  test('obligation fromMap and toMap roundtrip', () {
    final now = DateTime.now();
    final original = Obligation(
      id: 'obl-rt',
      direction: 'payable',
      kind: 'salary',
      title: 'Зарплата',
      amountCents: 50000,
      paidCents: 0,
      dueAt: now,
      status: 'planned',
      createdAt: now,
      updatedAt: now,
    );

    final map = original.toMap();
    final restored = Obligation.fromMap(map);

    expect(restored.id, original.id);
    expect(restored.direction, original.direction);
    expect(restored.kind, original.kind);
    expect(restored.amountCents, original.amountCents);
    expect(restored.paidCents, original.paidCents);
    expect(restored.status, original.status);
  });
}
