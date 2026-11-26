import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/appointment.dart';
import 'package:masters/data/models/job.dart';
import 'package:masters/data/models/unified_event.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';

Future<(AppDatabase, MastersStore)> openStore() async {
  final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
  final settings = await SettingsController.load();
  final store = MastersStore(appDb, settings);
  await store.load();
  return (appDb, store);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('UnifiedEvent mapping', () {
    test('fromJob maps fields and kanban key', () {
      final job = Job(
        id: 'j1',
        clientId: 'c1',
        title: 'Реставрация',
        dueDate: DateTime(2026, 11, 5, 18),
        status: JobStatus.waitingParts,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );
      final e = UnifiedEvent.fromJob(job);
      expect(e.id, 'j1');
      expect(e.kind, UnifiedEventKind.job);
      expect(e.isJob, isTrue);
      expect(e.clientId, 'c1');
      expect(e.title, 'Реставрация');
      expect(e.startTime, DateTime(2026, 11, 5, 18));
      expect(e.statusLabel, 'Ждёт детали');
      expect(e.kanbanKey, 'in_progress');
      expect(e.job, same(job));
      expect(e.appointment, isNull);
    });

    test('job without dueDate falls back to startedAt/createdAt', () {
      final job = Job(
        id: 'j2',
        clientId: 'c1',
        title: 'Без срока',
        startedAt: DateTime(2026, 11, 2, 9),
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );
      expect(UnifiedEvent.fromJob(job).startTime, DateTime(2026, 11, 2, 9));
      expect(
        UnifiedEvent.fromJob(job.copyWith(startedAt: null)).startTime,
        DateTime(2026, 11, 1),
      );
    });

    test('closed job is flagged as history', () {
      final job = Job(
        id: 'jc',
        clientId: 'c1',
        title: 'Закрыт',
        status: JobStatus.closed,
        dueDate: DateTime(2026, 11, 5),
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );
      expect(UnifiedEvent.fromJob(job).isClosed, isTrue);
      expect(
        UnifiedEvent.fromJob(job.copyWith(status: JobStatus.done)).isClosed,
        isFalse,
      );
    });

    test('fromAppointment maps all statuses to kanban keys', () {
      Appointment make(AppointmentStatus s) => Appointment(
        id: 'a',
        title: 't',
        startAt: DateTime(2026, 11, 3, 10),
        endAt: DateTime(2026, 11, 3, 11),
        status: s,
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );
      expect(
        UnifiedEvent.fromAppointment(make(AppointmentStatus.scheduled))
            .kanbanKey,
        'nuevo',
      );
      expect(
        UnifiedEvent.fromAppointment(make(AppointmentStatus.confirmed))
            .kanbanKey,
        'in_progress',
      );
      expect(
        UnifiedEvent.fromAppointment(make(AppointmentStatus.done)).kanbanKey,
        'done',
      );
      expect(
        UnifiedEvent.fromAppointment(make(AppointmentStatus.cancelled))
            .kanbanKey,
        'done',
      );
      expect(
        UnifiedEvent.fromAppointment(make(AppointmentStatus.noShow)).kanbanKey,
        'done',
      );
      expect(
        UnifiedEvent.fromAppointment(make(AppointmentStatus.confirmed)).endTime,
        DateTime(2026, 11, 3, 11),
      );
    });

    test('column → appointment status reverse mapping', () {
      expect(
        UnifiedEvent.appointmentStatusForColumn('nuevo'),
        AppointmentStatus.scheduled,
      );
      expect(
        UnifiedEvent.appointmentStatusForColumn('in_progress'),
        AppointmentStatus.confirmed,
      );
      expect(
        UnifiedEvent.appointmentStatusForColumn('done'),
        AppointmentStatus.done,
      );
    });
  });

  group('store unified events (integration)', () {
    test('concurrent lead conversion returns the same order', () async {
      final (db, store) = await openStore();
      try {
        final lead = await store.createLead(name: 'Заявка', budgetCents: 10000);
        final jobs = await Future.wait([
          store.convertLeadToJob(lead.id, title: 'Заказ'),
          store.convertLeadToJob(lead.id, title: 'Заказ'),
        ]);
        expect(jobs.first.id, jobs.last.id);
        await store.load();
        expect(store.jobs.where((job) => job.leadId == lead.id), hasLength(1));
        expect(store.obligationsForJob(jobs.first.id), hasLength(1));
        expect(store.leadById(lead.id)?.convertedJobId, jobs.first.id);
      } finally {
        await db.close();
      }
    });

    test('failed lead conversion rolls back the client and order', () async {
      final (db, store) = await openStore();
      try {
        final lead = await store.createLead(name: 'Заявка', budgetCents: 10000);
        await db.database.execute('''
          CREATE TRIGGER reject_lead_obligation BEFORE INSERT ON obligations
          BEGIN SELECT RAISE(ABORT, 'test failure'); END
        ''');
        await expectLater(store.convertLeadToJob(lead.id, title: 'Заказ'), throwsException);
        await store.load();
        expect(store.jobs.where((job) => job.leadId == lead.id), isEmpty);
        expect(store.clients.where((client) => client.name == 'Заявка'), isEmpty);
        expect(store.leadById(lead.id)?.convertedJobId, isNull);
        await db.database.execute('DROP TRIGGER reject_lead_obligation');
        final job = await store.convertLeadToJob(lead.id, title: 'Заказ');
        expect(store.obligationsForJob(job.id), hasLength(1));
      } finally {
        await db.close();
      }
    });
    test('booking handles adjacent slots, cancellation and reactivation', () async {
      final (db, store) = await openStore();
      try {
        final start = DateTime(2026, 6, 15, 10);
        final first = await store.createAppointment(title: 'Первый', startAt: start);
        final second = await store.createAppointment(
          title: 'Второй',
          startAt: start.add(const Duration(hours: 1)),
        );
        await expectLater(
          store.updateAppointment(second.copyWith(
            startAt: start.add(const Duration(minutes: 30)),
            endAt: start.add(const Duration(hours: 1, minutes: 30)),
          )),
          throwsStateError,
        );
        expect(store.appointmentById(second.id)!.startAt, second.startAt);
        await store.setAppointmentStatus(first.id, AppointmentStatus.cancelled);
        final replacement = await store.createAppointment(title: 'Замена', startAt: start);
        await expectLater(
          store.setAppointmentStatus(first.id, AppointmentStatus.scheduled),
          throwsStateError,
        );
        expect(store.appointmentById(first.id)!.status, AppointmentStatus.cancelled);
        await store.load();
        expect(store.appointmentById(replacement.id), isNotNull);
        expect(store.appointmentById(first.id)!.status, AppointmentStatus.cancelled);
      } finally {
        await db.close();
      }
    });

    test('week with 5 appointments + 5 jobs shows in both views', () async {
      final (db, store) = await openStore();
      try {
        final client = await store.createClient(name: 'Неделя: Клиент');
        final weekStart = DateTime(2026, 11, 2, 0, 0);
        final weekEnd = weekStart.add(const Duration(days: 7));

        for (var i = 0; i < 5; i++) {
          await store.createAppointment(
            title: 'Неделя: Запись $i',
            startAt: DateTime(2026, 11, 2 + i, 10),
            endAt: DateTime(2026, 11, 2 + i, 11),
            clientId: client.id,
          );
        }
        for (var i = 0; i < 5; i++) {
          await store.createJob(
            title: 'Неделя: Заказ $i',
            clientId: client.id,
            dueDate: DateTime(2026, 11, 2 + i, 18),
          );
        }

        // Календарь: диапазон недели даёт 10 отсортированных событий.
        final events = store.getEventsForRange(weekStart, weekEnd);
        expect(events.length, 10);
        expect(events.where((e) => e.isAppointment).length, 5);
        expect(events.where((e) => e.isJob).length, 5);
        for (var i = 1; i < events.length; i++) {
          expect(
            events[i].startTime.isBefore(events[i - 1].startTime),
            isFalse,
          );
        }

        // Канбан: колонки собирают свои события.
        final byColumn = <String, int>{'nuevo': 0, 'in_progress': 0, 'done': 0};
        for (final e in events) {
          byColumn[e.kanbanKey] = (byColumn[e.kanbanKey] ?? 0) + 1;
        }
        expect(byColumn['nuevo'], 10); // записи scheduled + заказы nuevo

        // Вне диапазона событий нет.
        expect(
          store.getEventsForRange(DateTime(2026, 12, 1), DateTime(2026, 12, 8)),
          isEmpty,
        );

        // Заказ без срока не попадает в календарь.
        final noDate = await store.createJob(
          title: 'Неделя: Без дедлайна',
          clientId: client.id,
        );
        expect(noDate.dueDate, isNull);
        expect(
          store
              .getEventsForRange(weekStart, weekEnd)
              .where((e) => e.id == noDate.id),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    });

    test(
      'conversion appointment → job creates job, deletes appointment',
      () async {
        final (db, store) = await openStore();
        try {
          final client = await store.createClient(name: 'Конверсия: Клиент');
          final appt = await store.createAppointment(
            title: 'Конверсия: Запись',
            startAt: DateTime(2026, 11, 5, 10),
            endAt: DateTime(2026, 11, 5, 11),
            clientId: client.id,
          );
          await store.convertAppointmentToJob(appt.id);

          expect(store.appointmentById(appt.id), isNull);
          final job = store.jobs.singleWhere(
            (j) => j.title == 'Конверсия: Запись',
          );
          expect(job.clientId, client.id);
          expect(job.dueDate, DateTime(2026, 11, 5, 10));
          expect(job.status, JobStatus.nuevo);
          expect(job.note, contains('Из записи'));
        } finally {
          await db.close();
        }
      },
    );

    test(
      'conversion without client throws StateError, keeps appointment',
      () async {
        final (db, store) = await openStore();
        try {
          final appt = await store.createAppointment(
            title: 'Конверсия: Без клиента',
            startAt: DateTime(2026, 11, 5, 10),
          );
          await expectLater(
            store.convertAppointmentToJob(appt.id),
            throwsA(isA<StateError>()),
          );
          expect(store.appointmentById(appt.id), isNotNull);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'conversion job → appointment creates appointment, keeps job',
      () async {
        final (db, store) = await openStore();
        try {
          final client = await store.createClient(name: 'Время: Клиент');
          final job = await store.createJob(
            title: 'Время: Заказ',
            clientId: client.id,
            dueDate: DateTime(2026, 11, 6, 15),
          );
          final appt = await store.convertJobToAppointment(job.id);
          expect(appt.title, 'Время: Заказ');
          expect(appt.startAt, DateTime(2026, 11, 6, 15));
          expect(appt.endAt, DateTime(2026, 11, 6, 16));
          expect(appt.note, contains('Из заказа'));
          expect(store.jobById(job.id), isNotNull);
        } finally {
          await db.close();
        }
      },
    );

    test('job → appointment conflicts on busy resource slot', () async {
      final (db, store) = await openStore();
      try {
        final client = await store.createClient(name: 'Конфликт: Клиент');
        expect(store.defaultResource(), isNotNull);
        await store.createAppointment(
          title: 'Конфликт: Занято',
          startAt: DateTime(2026, 11, 7, 10),
          endAt: DateTime(2026, 11, 7, 11),
          clientId: client.id,
        );
        final job = await store.createJob(
          title: 'Конфликт: Заказ',
          clientId: client.id,
          dueDate: DateTime(2026, 11, 7, 10),
        );
        await expectLater(
          store.convertJobToAppointment(job.id),
          throwsA(isA<StateError>()),
        );
      } finally {
        await db.close();
      }
    });

    test('setAppointmentStatus persists', () async {
      final (db, store) = await openStore();
      try {
        final appt = await store.createAppointment(
          title: 'Статус: Запись',
          startAt: DateTime(2026, 11, 8, 10),
        );
        await store.setAppointmentStatus(appt.id, AppointmentStatus.confirmed);
        expect(
          store.appointmentById(appt.id)!.status,
          AppointmentStatus.confirmed,
        );
      } finally {
        await db.close();
      }
    });
  });
}
