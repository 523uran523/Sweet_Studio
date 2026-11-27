import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'money_format.dart';

class MediaStore {
  MediaStore(this.rootDir);

  final Directory rootDir;

  Directory get mediaDir => Directory(p.join(rootDir.path, 'media'));

  static Future<MediaStore> createDefault() async {
    final docDir = await getApplicationDocumentsDirectory();
    final store = MediaStore(docDir);
    await store.ensureReady();
    return store;
  }

  Future<void> ensureReady() async {
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
  }

  String normalizeFilename(String rawPath) {
    var clean = rawPath.replaceAll('\\', '/').trim();
    if (clean.startsWith('media/')) {
      clean = clean.substring('media/'.length);
    }
    clean = p.basename(clean);
    return clean.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  Future<String> savePhotoFromFile(
    String sourcePath, {
    String? preferredName,
  }) async {
    await ensureReady();
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Исходное фото не найдено', sourcePath);
    }
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    final safeExt = (ext.isEmpty || ext.length > 5) ? 'jpg' : ext;
    final bytes = await source.readAsBytes();
    return savePhotoBytes(
      bytes,
      ext: safeExt,
      preferredName: preferredName,
    );
  }

  Future<String> savePhotoBytes(
    Uint8List bytes, {
    String ext = 'jpg',
    String? preferredName,
  }) async {
    await ensureReady();
    final safeExt = ext.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final baseName = preferredName != null && preferredName.trim().isNotEmpty
        ? normalizeFilename(preferredName)
        : '${newId('photo')}.${safeExt.isEmpty ? 'jpg' : safeExt}';
    final target = File(p.join(mediaDir.path, baseName));
    await target.writeAsBytes(bytes, flush: true);
    return baseName;
  }

  File? resolvePhotoFile(String? storedName) {
    if (storedName == null || storedName.trim().isEmpty) return null;
    final clean = normalizeFilename(storedName);
    if (clean.isEmpty) return null;
    final file = File(p.join(mediaDir.path, clean));
    if (!file.existsSync()) return null;
    return file;
  }

  Future<void> deletePhoto(String? storedName) async {
    if (storedName == null || storedName.trim().isEmpty) return;
    final clean = normalizeFilename(storedName);
    if (clean.isEmpty) return;
    final file = File(p.join(mediaDir.path, clean));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<String>> listMediaFilenames() async {
    if (!await mediaDir.exists()) return const [];
    final out = <String>[];
    await for (final entity in mediaDir.list(followLinks: false)) {
      if (entity is File) {
        out.add(p.basename(entity.path));
      }
    }
    out.sort();
    return out;
  }

  Future<int> totalMediaBytes() async {
    if (!await mediaDir.exists()) return 0;
    var total = 0;
    await for (final entity in mediaDir.list(followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> clearAllMedia() async {
    if (await mediaDir.exists()) {
      await mediaDir.delete(recursive: true);
    }
    await mediaDir.create(recursive: true);
  }
}
