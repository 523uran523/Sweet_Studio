// Транзакционное закрытие/переоткрытие периода и замороженные ведомости (B2).
//
// Проверяют: версии ведомостей, повторное закрытие без дублей, обязательную
// причину переоткрытия, пересчёт на версии +1 с сохранением расшифровки v1,
// датированные ставки, полуоткрытый интервал, предварительный статус и
// подтверждение, живой предпросмотр и сводку закрытого периода.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/employee.dart';
import 'package:masters/data/models/job.dart';
import 'package:masters/data/models/recurring_payment.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

Future<MastersStore> openMemoryStore() async {
  final db = await AppDatabase.open(path: inMemoryDatabasePath);
  addTearDown(db.close);
  final store = MastersStore(db, await SettingsController.load());
  addTearDown(store.dispose);
  await store.load();
  // Дефольный сотрудник «Я» не участвует в расчётах: в тестах — только
  // явно созданные сотрудники.
  final self = store.employees
      .where((e) => e.role == 'owner' && e.name == 'Я')
      .toList();
  if (self.isNotEmpty) await store.deleteEmployee(self.first.id);
  return store;
}

Future<PayrollPeriod> openMonth(MastersStore store) async {
  final now = DateTime.now();
  return store.createPayrollPeriod(
    name: 'Тестовый месяц',
    startAt: DateTime(now.year, now.month, 1),
    endAt: DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'закрытие фиксирует ведомость v1 confirmed и строки начислений',
    () async {
      final store = await openMemoryStore();
      final emp = await store.createEmployee(
        name: 'Почасовой Иван',
        payType: 'hourly',
        rateCents: 100000,
      );
      final period = await openMonth(store);
      await store.addTimeEntry(
        employeeId: emp.id,
        startedAt: DateTime.now(),
        minutes: 60,
      );
      await store.addEmployeePayment(
        employeeId: emp.id,
        type: 'bonus',
        amountCents: 50000,
      );

      final slips = await store.closePayrollPeriod(period.id);

      expect(store.payrollPeriods.single.isClosed, isTrue);
      expect(slips, hasLength(1));
      final slip = slips.single;
      expect(slip.version, 1);
      expect(slip.status, 'confirmed');
      expect(slip.needsReview, isFalse);
      expect(slip.minutes, 60);
      expect(slip.accruedCents, 100000);
      expect(slip.bonusCents, 50000);
      expect(slip.netCents, 150000);
      // Замороженная сумма совпадает с живым расчётом на момент закрытия.
      expect(
        store.earnedCentsForPeriod(emp.id, period.startAt, period.endAt),
        slip.accruedCents,
      );
      final lines = await store.accrualEntriesForPayslip(slip.id);
      expect(lines, hasLength(1));
      expect(lines.single.sourceKind, 'time_entry');
      expect(lines.single.accrualKind, 'hourly');
      expect(lines.single.amountCents, 100000);
      expect(lines.single.payslipId, slip.id);
    },
  );

  test(
    'повторное закрытие возвращает сохранённый результат без v2 и дублей',
    () async {
      final store = await openMemoryStore();
      final emp = await store.createEmployee(
        name: 'Иван',
        payType: 'hourly',
        rateCents: 100000,
      );
      final period = await openMonth(store);
      await store.addTimeEntry(
        employeeId: emp.id,
        startedAt: DateTime.now(),
        minutes: 60,
      );

      final first = await store.closePayrollPeriod(period.id);
      final second = await store.closePayrollPeriod(period.id);

      expect(second.map((s) => s.id), unorderedEquals(first.map((s) => s.id)));
      expect(store.payslipsForPeriod(period.id).map((s) => s.version), [1]);
      expect(store.payslips, hasLength(1));
      final lines = await store.accrualEntriesForPayslip(first.single.id);
      expect(lines, hasLength(1));
    },
  );

  test('переоткрытие без причины запрещено, с причиной — в аудит', () async {
    final store = await openMemoryStore();
    final emp = await store.createEmployee(
      name: 'Иван',
      payType: 'hourly',
      rateCents: 100000,
    );
    final period = await openMonth(store);
    await store.addTimeEntry(
      employeeId: emp.id,
      startedAt: DateTime.now(),
      minutes: 60,
    );
    await store.closePayrollPeriod(period.id);

    await expectLater(
      store.reopenPayrollPeriod(period.id, reason: ''),
      throwsArgumentError,
    );
    await expectLater(
      store.reopenPayrollPeriod(period.id, reason: '   '),
      throwsArgumentError,
    );
    expect(store.payrollPeriods.single.isClosed, isTrue);

    await store.reopenPayrollPeriod(period.id, reason: 'ошибка в табеле');
    expect(store.payrollPeriods.single.isClosed, isFalse);

    // Ведомости v1 сохранены.
    final slips = store.payslipsForPeriod(period.id);
    expect(slips, hasLength(1));
    expect(slips.single.version, 1);

    final entries = await store.auditEntriesFor('payroll_period', period.id);
    final reopen = entries.firstWhere(
      (e) => e['action'] == 'payroll_period.reopen',
    );
    final after = jsonDecode(reopen['after_json'] as String) as Map;
    expect(after['reason'], 'ошибка в табеле');
  });

  test(
    'повторное закрытие после переоткрытия даёт v2, v1 остаётся в истории',
    () async {
      final store = await openMemoryStore();
      final emp = await store.createEmployee(
        name: 'Иван',
        payType: 'hourly',
        rateCents: 100000,
      );
      final period = await openMonth(store);
      await store.addTimeEntry(
        employeeId: emp.id,
        startedAt: DateTime.now(),
        minutes: 60,
      );
      await store.closePayrollPeriod(period.id);

      await store.reopenPayrollPeriod(period.id, reason: 'добавили часы');
      await store.addTimeEntry(
        employeeId: emp.id,
        startedAt: DateTime.now(),
        minutes: 60,
      );
      await store.closePayrollPeriod(period.id);

      final slips = store.payslipHistoryForPeriod(period.id);
      expect(slips.map((s) => s.version), [2, 1]);
      final v1 = slips.firstWhere((s) => s.version == 1);
      final v2 = slips.firstWhere((s) => s.version == 2);
      expect(v1.accruedCents, 100000); // прошлая версия не менялась
      expect(v2.accruedCents, 200000);

      // Строки v1 мягко удалены, но читаются в расшифровке старой версии.
      final v1Lines = await store.accrualEntriesForPayslip(v1.id);
      expect(v1Lines, hasLength(1));
      expect(v1Lines.single.deletedAt, isNotNull);
      final v2Lines = await store.accrualEntriesForPayslip(v2.id);
      expect(v2Lines, hasLength(2));
      expect(v2Lines.every((l) => l.deletedAt == null), isTrue);

      // Последняя версия — v2.
      expect(store.latestPayslipFor(period.id, emp.id)?.version, 2);
    },
  );

  test('смена ставки внутри периода — разные ставки по строкам', () async {
    final store = await openMemoryStore();
    final emp = await store.createEmployee(
      name: 'Иван',
      payType: 'hourly',
      rateCents: 100000,
    );
    final period = await openMonth(store);
    // Первая запись раньше момента смены ставки — по старой ставке.
    await store.addTimeEntry(
      employeeId: emp.id,
      startedAt: DateTime.now().subtract(const Duration(seconds: 1)),
      minutes: 60,
    );
    final edited = emp.copyWith(rateCents: 130000);
    await store.updateEmployee(edited);
    // Вторая запись после смены ставки — по новой.
    await store.addTimeEntry(
      employeeId: emp.id,
      startedAt: DateTime.now(),
      minutes: 60,
    );

    final slips = await store.closePayrollPeriod(period.id);
    final slip = slips.single;
    expect(slip.accruedCents, 230000);

    final lines = await store.accrualEntriesForPayslip(slip.id);
    expect(lines.map((l) => l.rateCents), unorderedEquals([100000, 130000]));
    // История условий: первоначальная + изменённая.
    expect(
      store.payConditions.where((c) => c.employeeId == emp.id),
      hasLength(2),
    );
  });

  test('полуоткрытый интервал: конец периода включён, за ним — нет', () async {
    final store = await openMemoryStore();
    final emp = await store.createEmployee(
      name: 'Иван',
      payType: 'hourly',
      rateCents: 100000,
    );
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    final period = await store.createPayrollPeriod(
      name: 'Границы',
      startAt: start,
      endAt: end,
    );

    // Ровно конец периода (включён по полуоткрытому правилу).
    await store.addTimeEntry(employeeId: emp.id, startedAt: end, minutes: 60);
    // На 1 мс позже — уже следующий период.
    await store.addTimeEntry(
      employeeId: emp.id,
      startedAt: end.add(const Duration(milliseconds: 1)),
      minutes: 60,
    );
    // На 1 мс раньше начала.
    await store.addTimeEntry(
      employeeId: emp.id,
      startedAt: start.subtract(const Duration(milliseconds: 1)),
      minutes: 60,
    );

    final slips = await store.closePayrollPeriod(period.id);
    expect(slips.single.accruedCents, 100000);
    expect(slips.single.minutes, 60);
    // Хранимый end_at остаётся включённым 23:59:59.999 — та же принадлежность.
    expect(store.earnedCentsForPeriod(emp.id, start, end), 100000);
  });

  test(
    'предварительная ведомость: фолбэк ставки, подтверждение мастером',
    () async {
      final store = await openMemoryStore();
      final emp = await store.createEmployee(
        name: 'Иван',
        payType: 'hourly',
        rateCents: 100000,
      );
      final period = await openMonth(store);
      // Работа раньше первой записи условий — фолбэк, строка требует сверки.
      await store.addTimeEntry(
        employeeId: emp.id,
        startedAt: emp.createdAt.subtract(const Duration(hours: 1)),
        minutes: 60,
      );

      final slips = await store.closePayrollPeriod(period.id);
      final slip = slips.single;
      expect(slip.status, 'preliminary');
      expect(slip.needsReview, isTrue);
      expect(slip.reviewNote, isNotNull);
      expect(slip.accruedCents, 100000); // фолбэк на самую раннюю ставку

      final lines = await store.accrualEntriesForPayslip(slip.id);
      expect(lines.single.needsReview, isTrue);

      // Подтверждение — явное действие; повторное подтверждение не считается.
      expect(await store.confirmPreliminaryPayslips(period.id), 1);
      final confirmed = store.latestPayslipFor(period.id, emp.id)!;
      expect(confirmed.status, 'confirmed');
      expect(confirmed.needsReview, isFalse);
      expect(confirmed.reviewNote, isNull);
      expect(await store.confirmPreliminaryPayslips(period.id), 0);

      final audit = await store.auditEntriesFor('payslip', slip.id);
      expect(audit.any((e) => e['action'] == 'payslip.confirm'), isTrue);
    },
  );

  test('сводка закрытого периода берёт сохранённые суммы', () async {
    final store = await openMemoryStore();
    final emp = await store.createEmployee(
      name: 'Иван',
      payType: 'hourly',
      rateCents: 100000,
    );
    final period = await openMonth(store);
    await store.addTimeEntry(
      employeeId: emp.id,
      startedAt: DateTime.now(),
      minutes: 60,
    );
    await store.closePayrollPeriod(period.id);

    final rows = store.payrollSummaryForPeriod(period);
    expect(rows, hasLength(1));
    final row = rows.single;
    expect((row['employee'] as Employee).id, emp.id);
    expect(row['earned'], 100000);
    expect(row['net'], 100000);

    // Открытый период считается вживую.
    final open = await store.createPayrollPeriod(
      name: 'Следующий месяц',
      startAt: DateTime.now().add(const Duration(days: 30)),
      endAt: DateTime.now().add(const Duration(days: 60)),
    );
    final openRows = store.payrollSummaryForPeriod(open);
    expect(openRows.single['earned'], 0);
  });

  test('живой предпросмотр строк совпадает с закрытием', () async {
    final store = await openMemoryStore();
    final emp = await store.createEmployee(
      name: 'Иван',
      payType: 'hourly',
      rateCents: 100000,
    );
    final period = await openMonth(store);
    await store.addTimeEntry(
      employeeId: emp.id,
      startedAt: DateTime.now(),
      minutes: 30,
    );

    final preview = store.previewAccrualLines(
      emp.id,
      period.startAt,
      period.endAt,
    );
    expect(preview, hasLength(1));
    expect(preview.single.amountCents, 50000); // 30 мин × 1000 ₽/ч

    final slip = (await store.closePayrollPeriod(period.id)).single;
    expect(slip.accruedCents, preview.single.amountCents);
  });

  test(
    'сдельный тип: строка на завершённый заказ, табель не считается',
    () async {
      final store = await openMemoryStore();
      final client = await store.createClient(name: 'Клиент сдельщика');
      final emp = await store.createEmployee(
        name: 'Сдельщик',
        payType: 'piece',
        rateCents: 30000,
      );
      final period = await openMonth(store);
      await store.addTimeEntry(
        employeeId: emp.id,
        startedAt: DateTime.now(),
        minutes: 600,
      );
      await store.createJob(
        clientId: client.id,
        title: 'Работа 1',
        priceCents: 100000,
        assigneeId: emp.id,
        status: JobStatus.done,
      );
      await store.createJob(
        clientId: client.id,
        title: 'Работа 2',
        priceCents: 200000,
        assigneeId: emp.id,
        status: JobStatus.done,
      );

      final slip = (await store.closePayrollPeriod(period.id)).single;
      expect(slip.accruedCents, 60000); // 2 заказа × 300 ₽
      final lines = await store.accrualEntriesForPayslip(slip.id);
      expect(lines.every((l) => l.accrualKind == 'piece'), isTrue);
      expect(lines.map((l) => l.sourceKind).toSet(), {'job'});
    },
  );

  test('mixed: почасовые + процент, сдельных строк нет', () async {
    final store = await openMemoryStore();
    final client = await store.createClient(name: 'Клиент mixed');
    final emp = await store.createEmployee(
      name: 'Смешанный',
      payType: 'mixed',
      rateCents: 50000,
      percent: 10,
    );
    final period = await openMonth(store);
    await store.addTimeEntry(
      employeeId: emp.id,
      startedAt: DateTime.now(),
      minutes: 60,
    );
    await store.createJob(
      clientId: client.id,
      title: 'Работа',
      priceCents: 200000,
      assigneeId: emp.id,
      status: JobStatus.done,
    );

    final slip = (await store.closePayrollPeriod(period.id)).single;
    expect(slip.accruedCents, 70000); // 1 ч × 500 ₽ + 2000 × 10 %
    final lines = await store.accrualEntriesForPayslip(slip.id);
    expect(lines.map((l) => l.accrualKind).toSet(), {'hourly', 'percent'});
  });

  test('карточка сотрудника создаёт условия оплаты', () async {
    final store = await openMemoryStore();
    final emp = await store.createEmployee(
      name: 'Иван',
      payType: 'hourly',
      rateCents: 100000,
    );
    expect(store.payConditions, hasLength(1));
    expect(store.payConditions.single.validFrom, emp.createdAt);

    // То же значение — новая строка не создаётся.
    await store.updateEmployee(emp.copyWith(name: 'Иван П.'));
    expect(store.payConditions, hasLength(1));

    // Смена ставки — строка истории с новой датой действия.
    await store.updateEmployee(
      emp.copyWith(name: 'Иван П.', rateCents: 120000),
    );
    final conditions = store.payConditions;
    expect(conditions, hasLength(2));
    expect(conditions.last.rateCents, 120000);
    expect(conditions.first.rateCents, 100000);
  });

  test(
    'быстрая смена ставки в одном мс не ломает частичный уникальный индекс',
    () async {
      final store = await openMemoryStore();
      final emp = await store.createEmployee(
        name: 'Быстрый',
        payType: 'hourly',
        rateCents: 100000,
      );
      // Частая правка условия оплаты в одном и том же мс (тесты, пакетные
      // импорты) не должна уходить в UNIQUE-конфликт
      // (employee_id, valid_from).
      for (var i = 0; i < 5; i++) {
        await store.updateEmployee(emp.copyWith(rateCents: 100000 + i * 1000));
      }
      final conditions =
          store.payConditions.where((c) => c.employeeId == emp.id).toList()
            ..sort((a, b) => a.validFrom.compareTo(b.validFrom));
      expect(conditions, hasLength(5));
      // Все даты действия различаются.
      expect(
        conditions.map((c) => c.validFrom).toSet(),
        hasLength(conditions.length),
      );
    },
  );
}
