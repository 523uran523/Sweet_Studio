import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../data/app_database.dart';
import 'media_store.dart';
import 'money_format.dart';

class BackupValidationException implements Exception {
  BackupValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.dbFileName,
    required this.dbSha256,
    required this.recordCounts,
    required this.mediaChecksums,
  });

  final int formatVersion;
  final int schemaVersion;
  final String appVersion;
  final String createdAt;
  final String dbFileName;
  final String dbSha256;
  final Map<String, int> recordCounts;
  final Map<String, String> mediaChecksums;

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'createdAt': createdAt,
        'dbFileName': dbFileName,
        'dbSha256': dbSha256,
        'recordCounts': recordCounts,
        'mediaChecksums': mediaChecksums,
      };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final countsRaw = json['recordCounts'];
    final counts = <String, int>{};
    if (countsRaw is Map) {
      for (final entry in countsRaw.entries) {
        if (entry.value is num) {
          counts[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }
    final mediaRaw = json['mediaChecksums'];
    final media = <String, String>{};
    if (mediaRaw is Map) {
      for (final entry in mediaRaw.entries) {
        media[entry.key.toString()] = entry.value.toString();
      }
    }
    return BackupManifest(
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 0,
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      appVersion: (json['appVersion'] ?? '') as String,
      createdAt: (json['createdAt'] ?? '') as String,
      dbFileName: (json['dbFileName'] ?? 'sweet_studio.db') as String,
      dbSha256: (json['dbSha256'] ?? '') as String,
      recordCounts: counts,
      mediaChecksums: media,
    );
  }
}

class BackupInspection {
  const BackupInspection({
    required this.manifest,
    required this.stagingDir,
    required this.extractedDbFile,
    required this.mediaCount,
    required this.totalMediaBytes,
  });

  final BackupManifest manifest;
  final Directory stagingDir;
  final File extractedDbFile;
  final int mediaCount;
  final int totalMediaBytes;

  Future<void> dispose() async {
    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }
  }
}

class BackupService {
  static const int currentFormatVersion = 1;
  static const String appVersion = '1.0.0+1';

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static Future<File> createBackupZip({
    required AppDatabase db,
    required MediaStore mediaStore,
    required Directory outputDir,
  }) async {
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final counts = await db.getRecordCounts();
    final dbBytes = await db.exportDatabaseBytes();
    final dbHash = sha256Hex(dbBytes);

    final mediaFiles = await mediaStore.listMediaFilenames();
    final mediaChecksums = <String, String>{};
    final archive = Archive();

    archive.addFile(
      ArchiveFile('sweet_studio.db', dbBytes.length, dbBytes),
    );

    for (final filename in mediaFiles) {
      final f = mediaStore.resolvePhotoFile(filename);
      if (f == null || !await f.exists()) continue;
      final bytes = await f.readAsBytes();
      final rel = 'media/$filename';
      mediaChecksums[rel] = sha256Hex(bytes);
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
    }

    final nowIso = DateTime.now().toIso8601String();
    final manifest = BackupManifest(
      formatVersion: currentFormatVersion,
      schemaVersion: AppDatabase.schemaVersion,
      appVersion: appVersion,
      createdAt: nowIso,
      dbFileName: 'sweet_studio.db',
      dbSha256: dbHash,
      recordCounts: counts,
      mediaChecksums: mediaChecksums,
    );

    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    final stamp = todayIsoDate();
    final outFile = File(
      p.join(outputDir.path, 'sweet_studio_backup_$stamp.zip'),
    );
    await outFile.writeAsBytes(zipBytes, flush: true);
    await db.updateLastBackupAt(nowIso);
    return outFile;
  }

  static Future<BackupInspection> inspectBackupZip({
    required String zipPath,
    required Directory tempRoot,
    DatabaseFactory? dbFactory,
  }) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw BackupValidationException('Файл резервной копии не найден.');
    }

    final bytes = await zipFile.readAsBytes();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw BackupValidationException(
        'Архив повреждён или не является ZIP-файлом.',
      );
    }

    final staging = Directory(
      p.join(tempRoot.path, newId('backup_stage')),
    );
    await staging.create(recursive: true);

    try {
      for (final file in archive) {
        if (!file.isFile) continue;
        final normalized = p.posix.normalize(file.name.replaceAll('\\', '/'));
        if (normalized.startsWith('..') || p.posix.isAbsolute(normalized)) {
          throw BackupValidationException(
            'Недопустимый путь внутри архива: ${file.name}',
          );
        }
        final outFile = File(p.joinAll([staging.path, ...normalized.split('/')]));
        await outFile.parent.create(recursive: true);
        final content = file.content as List<int>;
        await outFile.writeAsBytes(content, flush: true);
      }

      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw BackupValidationException(
          'В архиве отсутствует manifest.json — это не резервная копия SweetStudio.',
        );
      }

      Map<String, dynamic> manifestJson;
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException();
        }
        manifestJson = decoded;
      } catch (_) {
        throw BackupValidationException('manifest.json повреждён.');
      }

      final manifest = BackupManifest.fromJson(manifestJson);
      if (manifest.formatVersion != currentFormatVersion) {
        throw BackupValidationException(
          'Неподдерживаемая версия формата копии (${manifest.formatVersion}).',
        );
      }
      if (manifest.schemaVersion <= 0 ||
          manifest.schemaVersion > AppDatabase.schemaVersion) {
        throw BackupValidationException(
          'Копия создана более новой версией приложения (схема ${manifest.schemaVersion}, текущая ${AppDatabase.schemaVersion}). Обновите приложение.',
        );
      }

      final dbName = p.basename(manifest.dbFileName);
      final extractedDb = File(p.join(staging.path, dbName));
      if (!await extractedDb.exists()) {
        throw BackupValidationException('В архиве отсутствует файл базы данных.');
      }

      final dbBytes = await extractedDb.readAsBytes();
      final actualDbHash = sha256Hex(dbBytes);
      if (actualDbHash != manifest.dbSha256) {
        throw BackupValidationException(
          'Контрольная сумма базы данных не совпадает. Файл повреждён или изменён.',
        );
      }

      var mediaBytesTotal = 0;
      for (final entry in manifest.mediaChecksums.entries) {
        final relParts = entry.key.replaceAll('\\', '/').split('/');
        final mediaFile = File(p.joinAll([staging.path, ...relParts]));
        if (!await mediaFile.exists()) {
          throw BackupValidationException(
            'В копии отсутствует медиафайл ${entry.key}.',
          );
        }
        final mBytes = await mediaFile.readAsBytes();
        if (sha256Hex(mBytes) != entry.value) {
          throw BackupValidationException(
            'Повреждён медиафайл ${entry.key} (неверная контрольная сумма).',
          );
        }
        mediaBytesTotal += mBytes.length;
      }

      final integrityErrors = await AppDatabase.validateExternalDatabaseFile(
        extractedDb.path,
        dbFactory: dbFactory,
      );
      if (integrityErrors.isNotEmpty) {
        throw BackupValidationException(
          'База в копии не прошла проверку целостности: ${integrityErrors.first}',
        );
      }

      return BackupInspection(
        manifest: manifest,
        stagingDir: staging,
        extractedDbFile: extractedDb,
        mediaCount: manifest.mediaChecksums.length,
        totalMediaBytes: mediaBytesTotal,
      );
    } catch (e) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      rethrow;
    }
  }

  static Future<void> restoreFromInspection({
    required BackupInspection inspection,
    required AppDatabase targetDb,
    required MediaStore targetMedia,
    required Directory tempRoot,
  }) async {
    final safetyDir = Directory(
      p.join(tempRoot.path, newId('pre_restore_safety')),
    );
    await safetyDir.create(recursive: true);

    Uint8List? prevDbBytes;
    final prevMedia = <String, Uint8List>{};

    try {
      prevDbBytes = await targetDb.exportDatabaseBytes();
      await File(p.join(safetyDir.path, 'prev.db'))
          .writeAsBytes(prevDbBytes, flush: true);

      for (final name in await targetMedia.listMediaFilenames()) {
        final f = targetMedia.resolvePhotoFile(name);
        if (f != null && await f.exists()) {
          prevMedia[name] = await f.readAsBytes();
        }
      }

      final incomingDbBytes = await inspection.extractedDbFile.readAsBytes();
      await targetDb.replaceDatabaseWithBytes(incomingDbBytes);

      await targetMedia.clearAllMedia();
      for (final rel in inspection.manifest.mediaChecksums.keys) {
        final relParts = rel.replaceAll('\\', '/').split('/');
        final srcFile = File(p.joinAll([inspection.stagingDir.path, ...relParts]));
        if (await srcFile.exists()) {
          final bytes = await srcFile.readAsBytes();
          final filename = p.basename(rel);
          await targetMedia.savePhotoBytes(
            bytes,
            preferredName: filename,
          );
        }
      }

      final issues = await targetDb.checkIntegrity();
      if (issues.isNotEmpty) {
        throw BackupValidationException(
          'После восстановления выявлена ошибка БД: ${issues.first}',
        );
      }
    } catch (e) {
      if (prevDbBytes != null) {
        try {
          await targetDb.replaceDatabaseWithBytes(prevDbBytes);
          await targetMedia.clearAllMedia();
          for (final entry in prevMedia.entries) {
            await targetMedia.savePhotoBytes(
              entry.value,
              preferredName: entry.key,
            );
          }
        } catch (_) {}
      }
      rethrow;
    } finally {
      if (await safetyDir.exists()) {
        await safetyDir.delete(recursive: true);
      }
    }
  }
}
