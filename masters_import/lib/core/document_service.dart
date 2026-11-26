import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'utils/app_utils.dart';
import '../data/models/job.dart';
import '../data/models/quote.dart';
import '../state/masters_store.dart';
import '../core/money_format.dart';

class DocumentService {
  static Future<Uint8List> buildJobPdf({
    required MastersStore store,
    required Job job,
    required String type,
  }) async {
    final pdf = pw.Document();
    final client = store.clientById(job.clientId);
    final obj = store.objectById(job.objectId);
    final materials = store.materialsForJob(job.id);
    final sessionsMinutes = store.totalMinutesForJob(job.id);
    final paid = store.paidForJob(job.id);
    final created = DateTime.now();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                type,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                '№ ${job.id}  от ${DateFormat('dd.MM.yyyy', 'ru').format(created)}',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Клиент: ${client?.name ?? '—'}',
                style: const pw.TextStyle(fontSize: 12),
              ),
              if (client != null && client.phone.isNotEmpty)
                pw.Text(
                  'Телефон: ${client.phone}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              if (obj != null)
                pw.Text(
                  'Объект: ${obj.title}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              if (job.note != null)
                pw.Text(
                  'Заметка: ${job.note!}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Заказ: ${job.title}',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              if (materials.isNotEmpty) ...[
                pw.Text(
                  'Материалы',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.TableHelper.fromTextArray(
                  headers: ['Наименование', 'Кол-во', 'Ед.', 'Цена', 'Сумма'],
                  data: [
                    for (final m in materials)
                      [
                        m.name,
                        m.quantity.toStringAsFixed(m.quantity % 1 == 0 ? 0 : 2),
                        m.unit,
                        (m.priceCents / 100).toStringAsFixed(2),
                        (m.totalCents / 100).toStringAsFixed(2),
                      ],
                  ],
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  headerStyle: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
              ],
              pw.Text(
                'Время работ: ${formatMinutes(sessionsMinutes)}',
                style: const pw.TextStyle(fontSize: 12),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Итого к оплате',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Text(
                    money(job.priceCents),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Уже оплачено')),
                  pw.Text(money(paid)),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Остаток')),
                  pw.Text(
                    money((job.priceCents - paid)),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Спасибо за обращение!',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> buildPayrollPdf({
    required String title,
    String? subtitle,
    required List<Map<String, Object?>> summary,
  }) async {
    final pdf = pw.Document();
    // Статус печатаем только для закрытых периодов: у живой сводки его нет.
    final hasStatus = summary.any((row) => row['status'] != null);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (subtitle != null) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: [
                  'Сотрудник',
                  'Зарплата',
                  'Бонусы',
                  'Штрафы',
                  'Аванс',
                  'Выплата',
                  'К выплате',
                  if (hasStatus) 'Статус',
                ],
                data: [
                  for (final row in summary)
                    [
                      (row['employeeName'] ??
                              row['employee']?.toString() ??
                              '?')
                          .toString(),
                      money((row['earned'] as int?) ?? 0),
                      money((row['bonus'] as int?) ?? 0),
                      money((row['penalty'] as int?) ?? 0),
                      money((row['advance'] as int?) ?? 0),
                      money((row['payout'] as int?) ?? 0),
                      money((row['net'] as int?) ?? 0),
                      if (hasStatus) (row['status'] ?? '').toString(),
                    ],
                ],
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> buildPnlPdf({
    String title = 'P&L',
    int revenue = 0,
    int expense = 0,
    int profit = 0,
    int jobRevenue = 0,
    int jobCost = 0,
    int jobMargin = 0,
    int completedCount = 0,
    Object? incomeCats,
    Object? expenseCats,
    Object? incomeCategories,
    Object? expenseCategories,
    Object? income,
    Object? expenses,
    List<Map<String, Object?>>? incomeRows,
    List<Map<String, Object?>>? expenseRows,
  }) async {
    final pdf = pw.Document();
    final inc = _categoryMapFrom(
      incomeCats ?? incomeCategories ?? income,
      incomeRows,
    );
    final exp = _categoryMapFrom(
      expenseCats ?? expenseCategories ?? expenses,
      expenseRows,
    );
    final incSorted = inc.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final expSorted = exp.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    String money(int cents) => (cents / 100).toStringAsFixed(2);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          8.5 * PdfPageFormat.inch,
          11 * PdfPageFormat.inch,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: const ['Показатель', 'Значение'],
                data: [
                  ['Выручка', money(revenue)],
                  ['Расходы', money(expense)],
                  ['Прибыль', money(profit)],
                  ['Выручка заказов', money(jobRevenue)],
                  ['Расход заказов', money(jobCost)],
                  ['Маржа заказов', money(jobMargin)],
                  ['Завершённых заказов', completedCount.toString()],
                ],
                cellStyle: const pw.TextStyle(fontSize: 10),
                headerStyle: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Доходы по категориям',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                headers: const ['Название', 'Сумма'],
                data: [
                  for (final e in incSorted) [e.key, money(e.value)],
                ],
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Расходы по категориям',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.TableHelper.fromTextArray(
                headers: const ['Название', 'Сумма'],
                data: [
                  for (final e in expSorted) [e.key, money(e.value)],
                ],
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static Map<String, int> _categoryMapFrom(
    Object? value,
    List<Map<String, Object?>>? rows,
  ) {
    final out = <String, int>{};
    if (value is Map) {
      value.forEach((k, v) {
        out[k.toString()] = (out[k.toString()] ?? 0) + _toInt(v);
      });
    } else if (value is List) {
      for (final item in value) {
        if (item is Map) {
          final key =
              (item['name'] ??
                      item['category'] ??
                      item['title'] ??
                      item['label'] ??
                      item['Название'] ??
                      '?')
                  .toString();
          final raw =
              item['amount'] ??
              item['value'] ??
              item['sum'] ??
              item['total'] ??
              0;
          out[key] = (out[key] ?? 0) + _toInt(raw);
        }
      }
    }
    if (rows != null) {
      for (final row in rows) {
        final key =
            (row['name'] ??
                    row['category'] ??
                    row['title'] ??
                    row['label'] ??
                    row['Название'] ??
                    '?')
                .toString();
        final raw =
            row['amount'] ?? row['value'] ?? row['sum'] ?? row['total'] ?? 0;
        out[key] = (out[key] ?? 0) + _toInt(raw);
      }
    }
    return out;
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString()) ??
        ((double.tryParse(value.toString()) ?? 0) * 100).round();
  }

  static Future<Uint8List> buildEmployeePayslipPdf({
    required String title,
    required List<String> lines,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              for (final line in lines)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(line, style: const pw.TextStyle(fontSize: 12)),
                ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  /// КП из снимка (§12.4). Рендерится только из `snapshotJson`, поэтому
  /// повторная генерация того же снимка отдаёт тот же документ, даже если
  /// заказ уже отредактирован.
  static Future<Uint8List> buildQuotePdf(Quote quote) async {
    final decoded = jsonDecode(quote.snapshotJson);
    final map = decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
    final lines = quote.lines;
    final created = DateTime.fromMillisecondsSinceEpoch(
      (map['createdAt'] as num?)?.toInt() ?? quote.createdAt.millisecondsSinceEpoch,
    );
    final validUntil = map['validUntil'] == null
        ? quote.validUntil
        : DateTime.fromMillisecondsSinceEpoch((map['validUntil'] as num).toInt());

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Коммерческое предложение',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                '№ ${quote.number} · ред. ${quote.revision} от '
                '${DateFormat('dd.MM.yyyy', 'ru').format(created)}',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 12),
              if ((map['clientName'] as String?)?.isNotEmpty ?? false)
                pw.Text(
                  'Клиент: ${map['clientName']}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              if ((map['clientPhone'] as String?)?.isNotEmpty ?? false)
                pw.Text(
                  'Телефон: ${map['clientPhone']}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              if ((map['jobTitle'] as String?)?.isNotEmpty ?? false) ...[
                pw.SizedBox(height: 10),
                pw.Text(
                  '${map['jobTitle']}',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                ),
              ],
              pw.SizedBox(height: 12),
              if (lines.isNotEmpty)
                pw.TableHelper.fromTextArray(
                  headers: const ['Наименование', 'Кол-во', 'Ед.', 'Цена', 'Сумма'],
                  data: [
                    for (final l in lines)
                      [
                        (l['name'] ?? '').toString(),
                        ((l['quantity'] as num?) ?? 1).toStringAsFixed(
                          ((l['quantity'] as num?) ?? 1) % 1 == 0 ? 0 : 2,
                        ),
                        (l['unit'] ?? 'шт').toString(),
                        money(((l['priceCents'] as num?) ?? 0).toInt()),
                        money(((l['totalCents'] as num?) ?? 0).toInt()),
                      ],
                  ],
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  headerStyle: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              pw.SizedBox(height: 14),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Итого',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Text(
                    money(quote.totalCents),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              if (validUntil != null) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  'Предложение действительно до '
                  '${DateFormat('dd.MM.yyyy', 'ru').format(validUntil)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
              pw.SizedBox(height: 18),
              pw.Text(
                'Спасибо за обращение!',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<bool> savePdf(Uint8List bytes, String suggestedName) async {
    return await savePdfPath(bytes, suggestedName) != null;
  }

  /// Тот же диалог сохранения, но возвращает выбранный путь (или `null`,
  /// если пользователь отменил). Нужен КП: путь кладётся на снимок, чтобы
  /// потом открыть ровно тот файл, что отдавали клиенту.
  static Future<String?> savePdfPath(
    Uint8List bytes,
    String suggestedName,
  ) async {
    final uri = await FilePicker.saveFile(
      fileName: suggestedName,
      bytes: bytes,
      mimeType: 'application/pdf',
      dialogTitle: 'Сохранить документ',
    );
    if (uri == null || kIsWeb) return null;
    return uri.toFilePath();
  }
}
