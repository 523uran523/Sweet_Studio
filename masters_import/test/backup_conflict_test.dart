import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masters/data/app_database.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const localClient = <String, Object?>{
    'id': 'c1',
    'name': 'Local Client',
    'phone': '',
    'note': 'local',
    'created_at': 1000,
    'updated_at': 1000,
  };

  Map<String, dynamic> backupWithClient(String name, String note) =>
      <String, dynamic>{
        'format': 'masters-backup',
        'version': 8,
        'clients': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'c1',
            'name': name,
            'phone': '',
            'note': note,
            'created_at': 1000,
            'updated_at': 1000,
          },
        ],
      };

  test('dry run reports conflict and keeps local row', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      await appDb.database.insert('clients', localClient);

      final result = await appDb.mergeSnapshot(
        backupWithClient('Remote Client', 'remote'),
        dryRun: true,
        applyConflictIds: <String>{},
      );

      expect(result.affected, 0);
      expect(result.keptLocal, 1);
      expect(result.conflicts, contains('clients:c1'));

      final rows = await appDb.database.query(
        'clients',
        where: 'id = ?',
        whereArgs: ['c1'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Local Client');
    } finally {
      await appDb.close();
    }
  });

  test('applies selected conflict and upserts remote row', () async {
    final appDb = await AppDatabase.open(path: inMemoryDatabasePath);
    try {
      await appDb.database.insert('clients', localClient);

      final result = await appDb.mergeSnapshot(
        backupWithClient('Remote Client', 'remote'),
        dryRun: false,
        applyConflictIds: <String>{'clients:c1'},
      );

      expect(result.affected, 1);
      expect(result.keptLocal, 0);
      expect(result.conflicts, contains('clients:c1'));

      final rows = await appDb.database.query(
        'clients',
        where: 'id = ?',
        whereArgs: ['c1'],
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Remote Client');
    } finally {
      await appDb.close();
    }
  });
}
