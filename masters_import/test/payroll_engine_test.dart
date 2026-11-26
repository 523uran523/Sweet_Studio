// Юнит-тесты чистого движка начислений (B1).
//
// Проверяют: датированные условия на дату источника, полуоткрытый интервал,
// правила piece/percent/mixed, пометку needsReview для исторического фолбэка.

import 'package:flutter_test/flutter_test.dart';
import 'package:masters/core/payroll_engine.dart';
import 'package:masters/data/models/job.dart';
import 'package:masters/data/models/pay_condition.dart';
import 'package:masters/data/models/time_entry.dart';

PayCondition cond(
  String id,
  String payType, {
  int rateCents = 0,
  double percent = 0,
  required DateTime validFrom,
}) {
  return PayCondition(
    id: id,
    employeeId: 'emp',
    payType: payType,
    rateCents: rateCents,
    percent: percent,
    validFrom: validFrom,
    createdAt: validFrom,
  );
}

TimeEntry time(String id, DateTime started, int minutes) => TimeEntry(
  id: id,
  employeeId: 'emp',
  startedAt: started,
  minutes: minutes,
  createdAt: started,
);

Job job(
  String id,
  JobStatus status,
  int priceCents, {
  required DateTime doneAt,
  bool archived = false,
}) => Job(
  id: id,
  clientId: 'c1',
  title: id,
  status: status,
  priceCents: priceCents,
  archived: archived,
  assigneeId: 'emp',
  finishedAt: doneAt,
  updatedAt: doneAt,
  createdAt: doneAt,
);

void main() {
  final start = DateTime(2025, 6);
  final endExclusive = DateTime(2025, 7);

  test('датированные условия: ставка меняется внутри периода', () {
    final conditions = [
      cond('c1', 'hourly', rateCents: 50000, validFrom: DateTime(2024)),
      cond('c2', 'hourly', rateCents: 80000, validFrom: DateTime(2025, 6, 20)),
    ];
    final lines = buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: conditions,
      timeEntries: [
        time('t1', DateTime(2025, 6, 10, 9), 60), // 500 ₽/ч
        time('t2', DateTime(2025, 6, 25, 9), 60), // 800 ₽/ч
      ],
      jobs: const [],
      defaultPayType: 'hourly',
    );

    expect(lines, hasLength(2));
    expect(lines[0].amountCents, 50000);
    expect(lines[0].payConditionId, 'c1');
    expect(lines[1].amountCents, 80000);
    expect(lines[1].payConditionId, 'c2');
    expect(lines.every((l) => !l.needsReview), isTrue);
  });

  test('работа раньше первой записи условий — фолбэк с needsReview', () {
    final conditions = [
      cond('c1', 'hourly', rateCents: 60000, validFrom: DateTime(2025, 6, 15)),
    ];
    final lines = buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: conditions,
      timeEntries: [time('t1', DateTime(2025, 6, 10, 9), 60)],
      jobs: const [],
      defaultPayType: 'hourly',
    );

    expect(lines, hasLength(1));
    expect(lines.single.amountCents, 60000); // самая ранняя запись
    expect(lines.single.needsReview, isTrue);
    expect(lines.single.payConditionId, 'c1');
  });

  test('условий нет вообще — нулевая строка с needsReview', () {
    final lines = buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: const [],
      timeEntries: [time('t1', DateTime(2025, 6, 10, 9), 60)],
      jobs: [job('j1', JobStatus.done, 100000, doneAt: DateTime(2025, 6, 11))],
      defaultPayType: 'hourly',
    );

    expect(lines, hasLength(1));
    expect(lines.single.amountCents, 0);
    expect(lines.single.payConditionId, isNull);
    expect(lines.single.needsReview, isTrue);
  });

  test('сдельный тип: одна строка на заказ, табель игнорируется', () {
    final conditions = [
      cond('c1', 'piece', rateCents: 30000, validFrom: DateTime(2024)),
    ];
    final lines = buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: conditions,
      timeEntries: [time('t1', DateTime(2025, 6, 10, 9), 120)],
      jobs: [
        job('j1', JobStatus.done, 100000, doneAt: DateTime(2025, 6, 11)),
        job('j2', JobStatus.closed, 200000, doneAt: DateTime(2025, 6, 25)),
        job('j3', JobStatus.nuevo, 100000, doneAt: DateTime(2025, 6, 12)),
        job(
          'j4',
          JobStatus.done,
          100000,
          doneAt: DateTime(2025, 6, 13),
          archived: true,
        ),
      ],
      defaultPayType: 'piece',
    );

    expect(lines, hasLength(2));
    expect(lines.every((l) => l.accrualKind == 'piece'), isTrue);
    expect(lines.map((l) => l.amountCents), everyElement(30000));
  });

  test('mixed: часы + процент, но не сдельная строка', () {
    final conditions = [
      cond(
        'c1',
        'mixed',
        rateCents: 50000,
        percent: 10,
        validFrom: DateTime(2024),
      ),
    ];
    final lines = buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: conditions,
      timeEntries: [time('t1', DateTime(2025, 6, 10, 9), 60)],
      jobs: [job('j1', JobStatus.done, 200000, doneAt: DateTime(2025, 6, 11))],
      defaultPayType: 'mixed',
    );

    expect(lines, hasLength(2));
    final byKind = {for (final l in lines) l.accrualKind: l};
    expect(byKind['hourly']!.amountCents, 50000);
    expect(byKind['percent']!.amountCents, 20000); // 200 000 × 10 %
    expect(byKind.containsKey('piece'), isFalse);
  });

  test('смешанный табель округляется на строке', () {
    final conditions = [
      cond('c1', 'hourly', rateCents: 55555, validFrom: DateTime(2024)),
    ];
    final lines = buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: conditions,
      // 45 минут × 555 ₽/ч: 55555 * 45 / 60 = 41666.25 → 41 666
      timeEntries: [time('t1', DateTime(2025, 6, 10, 9), 45)],
      jobs: const [],
      defaultPayType: 'hourly',
    );

    expect(lines.single.amountCents, 41666);
  });

  test('полуоткрытый интервал: границы включены/исключены', () {
    final conditions = [
      cond('c1', 'piece', rateCents: 30000, validFrom: DateTime(2024)),
    ];
    final lines = buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: conditions,
      timeEntries: [time('t1', start, 60)], // сдельщику табель не считается
      jobs: [
        job('j-start', JobStatus.done, 100000, doneAt: start), // включён
        job('j-end', JobStatus.done, 100000, doneAt: endExclusive), // исключён
        job(
          'j-before',
          JobStatus.done,
          100000,
          doneAt: start.subtract(const Duration(seconds: 1)),
        ),
      ],
      defaultPayType: 'piece',
    );

    expect(lines.map((l) => l.sourceId), ['j-start']);
  });

  test('salary считается почасовыми правилами', () {
    final conditions = [
      cond('c1', 'salary', rateCents: 60000, validFrom: DateTime(2024)),
    ];
    final lines = buildAccrualLines(
      start: start,
      endExclusive: endExclusive,
      conditions: conditions,
      timeEntries: [time('t1', DateTime(2025, 6, 10, 9), 120)],
      jobs: const [],
      defaultPayType: 'salary',
    );

    expect(lines.single.accrualKind, 'hourly');
    expect(lines.single.amountCents, 120000);
  });
}
