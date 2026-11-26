import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';
import 'package:masters/data/models/job.dart';
import 'package:masters/state/masters_store.dart';
import 'package:masters/state/settings_controller.dart';
import 'package:masters/features/jobs/jobs_screen.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('JobSearchFilter', () {
    late MastersStore store;
    late AppDatabase db;

    setUp(() async {
      db = await AppDatabase.open(path: inMemoryDatabasePath);
      final settings = await SettingsController.load();
      store = MastersStore(db, settings);
      await store.load();
    });

    tearDown(() async {
      await db.close();
    });

    test('matches by title (case-insensitive)', () {
      final job = Job(
        id: '1',
        clientId: 'c1',
        title: 'Ремонт кондиционера',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(JobSearchFilter.matches(job, 'ремонт', store), isTrue);
      expect(JobSearchFilter.matches(job, 'КОНДИЦИОНЕРА', store), isTrue);
      expect(JobSearchFilter.matches(job, 'окно', store), isFalse);
    });

    test('matches by note', () {
      final job = Job(
        id: '1',
        clientId: 'c1',
        title: 'Заказ 1',
        note: 'Срочно починить к среде',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(JobSearchFilter.matches(job, 'среде', store), isTrue);
      expect(JobSearchFilter.matches(job, 'срочно', store), isTrue);
    });

    test('matches by tags', () {
      final job = Job(
        id: '1',
        clientId: 'c1',
        title: 'Заказ 1',
        tags: 'электрика,Срочно',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(JobSearchFilter.matches(job, 'электрика', store), isTrue);
      expect(JobSearchFilter.matches(job, 'СРОЧНО', store), isTrue);
    });

    test('matches by client name', () async {
      final client = await store.createClient(name: 'Иван Иванович');
      final job = Job(
        id: '1',
        clientId: client.id,
        title: 'Заказ 1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(JobSearchFilter.matches(job, 'Иван', store), isTrue);
      expect(JobSearchFilter.matches(job, 'иванович', store), isTrue);
      expect(JobSearchFilter.matches(job, 'Петр', store), isFalse);
    });

    test('matches by assignee name', () async {
      final emp = await store.createEmployee(name: 'Алексей');
      final job = Job(
        id: '1',
        clientId: 'c1',
        title: 'Заказ 1',
        assigneeId: emp.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(JobSearchFilter.matches(job, 'Алексей', store), isTrue);
      expect(JobSearchFilter.matches(job, 'алексей', store), isTrue);
    });

    test('matches by self assignee', () async {
      // Assuming selfEmployee is available or created.
      // Since selfEmployee is calculated in the store based on role 'owner' and name 'Я'.
      await store.createEmployee(name: 'Я', role: 'owner');
      final job = Job(
        id: '1',
        clientId: 'c1',
        title: 'Заказ 1',
        assigneeId: '__self__',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(JobSearchFilter.matches(job, 'Я', store), isTrue);
    });

    test('does not match unrelated query', () {
      final job = Job(
        id: '1',
        clientId: 'c1',
        title: 'Заказ 1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(JobSearchFilter.matches(job, 'несуществующий', store), isFalse);
    });
  });
}
