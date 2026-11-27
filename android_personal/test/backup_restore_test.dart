import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sweet_studio_personal/core/backup_service.dart';
import 'package:sweet_studio_personal/core/media_store.dart';
import 'package:sweet_studio_personal/data/app_database.dart';

void main() {
  sqfliteFfiInit();

  test('ZIP backup export, SHA-256 tamper rejection, and full restore with media', () async {
    final sandbox = await Directory.systemTemp.createTemp('ss_backup_test_');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    final dbPath = p.join(sandbox.path, 'sweet_studio.db');
    final db = await AppDatabase.openAtPath(dbPath, factory: databaseFactoryFfi);
    final media = MediaStore(Directory(p.join(sandbox.path, 'app_docs')));
    final exportDir = Directory(p.join(sandbox.path, 'exports'));
    final tempDir = Directory(p.join(sandbox.path, 'tmp'));
    await tempDir.create(recursive: true);

    await db.seedDemoData(todayIso: '2026-05-01');
    final savedPhoto = await media.savePhotoBytes(
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      ext: 'jpg',
      preferredName: 'cake_demo.jpg',
    );
    final firstRec = (await db.getRecipes()).first;
    await db.upsertRecipe(firstRec.copyWith(photoPath: savedPhoto));

    final zipFile = await BackupService.createBackupZip(
      db: db,
      mediaStore: media,
      outputDir: exportDir,
    );
    expect(await zipFile.exists(), isTrue);

    // 1. Tamper with ZIP archive and confirm validation rejects without touching active DB
    final rawZip = await zipFile.readAsBytes();
    final decoded = ZipDecoder().decodeBytes(rawZip);
    final tamperedArchive = Archive();
    for (final f in decoded) {
      if (f.name == 'sweet_studio.db') {
        final altered = List<int>.from(f.content as List<int>);
        altered[altered.length - 1] ^= 0xFF;
        tamperedArchive.addFile(ArchiveFile(f.name, altered.length, altered));
      } else {
        final content = f.content as List<int>;
        tamperedArchive.addFile(ArchiveFile(f.name, content.length, content));
      }
    }
    final tamperedZip = File(p.join(exportDir.path, 'tampered.zip'));
    await tamperedZip.writeAsBytes(ZipEncoder().encode(tamperedArchive));

    await expectLater(
      () => BackupService.inspectBackupZip(
        zipPath: tamperedZip.path,
        tempRoot: tempDir,
        dbFactory: databaseFactoryFfi,
      ),
      throwsA(isA<BackupValidationException>()),
    );

    // 2. Clear active workspace completely, then restore from valid ZIP
    await db.clearAllBusinessData(isDemoMode: false);
    await media.clearAllMedia();
    expect(await db.getRecipes(), isEmpty);
    expect(media.resolvePhotoFile(savedPhoto), isNull);

    final inspection = await BackupService.inspectBackupZip(
      zipPath: zipFile.path,
      tempRoot: tempDir,
      dbFactory: databaseFactoryFfi,
    );
    expect(inspection.manifest.recordCounts['recipes'], 3);
    expect(inspection.mediaCount, 1);

    await BackupService.restoreFromInspection(
      inspection: inspection,
      targetDb: db,
      targetMedia: media,
      tempRoot: tempDir,
    );
    await inspection.dispose();

    expect((await db.getRecipes()).length, 3);
    expect((await db.getOrders()).length, 2);
    final restoredPhoto = media.resolvePhotoFile(savedPhoto);
    expect(restoredPhoto, isNotNull);
    expect(await restoredPhoto!.readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(await db.checkIntegrity(), isEmpty);

    await db.close();
  });
}
