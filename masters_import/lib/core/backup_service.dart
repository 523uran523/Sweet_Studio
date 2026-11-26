import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class BackupService {
  static Future<bool> saveJson(Map<String, dynamic> data) async {
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = Uint8List.fromList(utf8.encode(json));
    final name =
        'masters-backup-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.json';
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: 'Сохранить резервную копию',
    );
    return uri != null;
  }

  static Future<Map<String, dynamic>?> pickJson() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: 'Выбрать резервную копию',
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Не удалось прочитать файл копии.');
    }
    return decoded;
  }

  static Future<bool> saveCsv(List<List<dynamic>> rows) async {
    final csv = Csv.excel().encode(rows);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final name = 'masters-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.csv';
    final uri = await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: 'text/csv',
      dialogTitle: 'Сохранить таблицу',
    );
    return uri != null;
  }

  static Future<bool> saveExcel(
    List<List<dynamic>> rows, {
    String fileName = 'masters-import.xlsx',
    String sheetName = 'Data',
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel[sheetName];
      for (final row in rows) {
        sheet.appendRow(row.map(_toCellValue).toList());
      }
      final bytes = excel.encode();
      if (bytes == null) return false;
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        dialogTitle: 'Сохранить таблицу Excel',
      );
      return uri != null;
    } catch (_) {
      return false;
    }
  }

  /// Открывает .xlsx и возвращает строки. Пустые строки пропускаются.
  static Future<List<List<dynamic>>?> pickSpreadsheet() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        dialogTitle: 'Выбрать таблицу Excel',
      );
      if (file == null) return null;
      final bytes = Uint8List.fromList(await file.readAsBytes());
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return null;
      final sheet = excel.tables[excel.tables.keys.first]!;
      final rows = <List<dynamic>>[];
      for (final row in sheet.rows) {
        final cells = row.map((cell) {
          final value = cell?.value;
          if (value == null) return '';
          return value.toString();
        }).toList();
        if (cells.every((v) => v.toString().trim().isEmpty)) continue;
        rows.add(cells);
      }
      return rows;
    } catch (_) {
      return null;
    }
  }

  static CellValue _toCellValue(dynamic value) {
    final isNum = value is num;
    final isBool = value is bool;
    if (isNum || isBool) {
      return TextCellValue(value.toString());
    }
    return TextCellValue(value?.toString() ?? '');
  }
}
