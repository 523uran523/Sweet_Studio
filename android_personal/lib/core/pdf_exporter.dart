import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../data/models.dart';
import 'money_format.dart';
import 'orders_core.dart';

enum PdfDocKind { invoice, act }

class PdfExporter {
  PdfExporter._();

  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _ensureFonts({
    ByteData? regularData,
    ByteData? boldData,
  }) async {
    if (_regularFont != null && _boldFont != null) return;
    final reg = regularData ??
        await rootBundle.load('assets/fonts/LiberationSans-Regular.ttf');
    final bold = boldData ??
        await rootBundle.load('assets/fonts/LiberationSans-Bold.ttf');
    _regularFont = pw.Font.ttf(reg);
    _boldFont = pw.Font.ttf(bold);
  }

  static Future<Uint8List> buildOrderPdfBytes({
    required Order order,
    required StudioProfile profile,
    Client? client,
    PdfDocKind kind = PdfDocKind.invoice,
    ByteData? regularFontOverride,
    ByteData? boldFontOverride,
  }) async {
    await _ensureFonts(
      regularData: regularFontOverride,
      boldData: boldFontOverride,
    );
    final regular = _regularFont!;
    final bold = _boldFont!;

    final doc = pw.Document();
    final items = getOrderItemsNormalized(order);
    final docTitle = kind == PdfDocKind.invoice
        ? 'Счёт-смета по заказу ${order.orderNumber}'
        : 'Акт оказанных услуг по заказу ${order.orderNumber}';
    final dateStr = todayIsoDate();

    final baseStyle = pw.TextStyle(font: regular, fontSize: 10);
    final boldStyle = pw.TextStyle(font: bold, fontSize: 10);
    final headerStyle = pw.TextStyle(font: bold, fontSize: 16);
    final subHeaderStyle = pw.TextStyle(
      font: regular,
      fontSize: 10,
      color: PdfColors.grey700,
    );

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell('№', boldStyle, align: pw.TextAlign.center),
          _cell('Наименование', boldStyle),
          _cell('Вес, г', boldStyle, align: pw.TextAlign.right),
          _cell('Кол-во', boldStyle, align: pw.TextAlign.right),
          _cell('Цена', boldStyle, align: pw.TextAlign.right),
          _cell('Сумма', boldStyle, align: pw.TextAlign.right),
        ],
      ),
    ];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final lineTotal = item.priceCents * (item.qty < 1 ? 1 : item.qty);
      rows.add(
        pw.TableRow(
          children: [
            _cell('${i + 1}', baseStyle, align: pw.TextAlign.center),
            _cell(item.recipeTitle, baseStyle),
            _cell(
              item.weightGrams > 0 ? '${item.weightGrams.round()}' : '—',
              baseStyle,
              align: pw.TextAlign.right,
            ),
            _cell('${item.qty}', baseStyle, align: pw.TextAlign.right),
            _cell(
              formatMoneyCents(
                item.priceCents,
                currencySymbol: profile.currencySymbol,
              ),
              baseStyle,
              align: pw.TextAlign.right,
            ),
            _cell(
              formatMoneyCents(
                lineTotal,
                currencySymbol: profile.currencySymbol,
              ),
              boldStyle,
              align: pw.TextAlign.right,
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(profile.studioName, style: headerStyle),
                  if (profile.slogan.isNotEmpty)
                    pw.Text(profile.slogan, style: subHeaderStyle),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Дата документа: $dateStr', style: baseStyle),
                  pw.Text(
                    'Статус: ${kOrderStatusLabelsRu[order.status] ?? ''}',
                    style: subHeaderStyle,
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(docTitle, style: pw.TextStyle(font: bold, fontSize: 13)),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Заказчик: ${order.clientName}', style: boldStyle),
                if (client?.phone != null && client!.phone!.isNotEmpty)
                  pw.Text('Телефон: ${client.phone}', style: baseStyle),
                if (order.dueDate != null && order.dueDate!.isNotEmpty)
                  pw.Text('Дата выдачи: ${order.dueDate}', style: baseStyle),
                if (order.deliveryAddress != null &&
                    order.deliveryAddress!.isNotEmpty)
                  pw.Text('Доставка / адрес: ${order.deliveryAddress}',
                      style: baseStyle),
                if (order.allergens != null && order.allergens!.isNotEmpty)
                  pw.Text('Аллергены / ограничения: ${order.allergens}',
                      style: baseStyle),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
            columnWidths: {
              0: const pw.FixedColumnWidth(26),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(52),
              3: const pw.FixedColumnWidth(46),
              4: const pw.FixedColumnWidth(72),
              5: const pw.FixedColumnWidth(78),
            },
            children: rows,
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 240,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (order.discountCents > 0)
                    _summaryRow(
                      'Скидка:',
                      '-${formatMoneyCents(order.discountCents, currencySymbol: profile.currencySymbol)}',
                      baseStyle,
                    ),
                  _summaryRow(
                    'Итого к оплате:',
                    formatMoneyCents(order.priceCents,
                        currencySymbol: profile.currencySymbol),
                    boldStyle,
                  ),
                  _summaryRow(
                    'Оплачено:',
                    formatMoneyCents(order.paidCents,
                        currencySymbol: profile.currencySymbol),
                    baseStyle,
                  ),
                  pw.Divider(color: PdfColors.grey400),
                  _summaryRow(
                    'Остаток к оплате:',
                    formatMoneyCents(order.balanceDueCents,
                        currencySymbol: profile.currencySymbol),
                    pw.TextStyle(font: bold, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (order.wishes != null && order.wishes!.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Пожелания по заказу:', style: boldStyle),
            pw.Text(order.wishes!, style: baseStyle),
          ],
          if (kind == PdfDocKind.act) ...[
            pw.SizedBox(height: 24),
            pw.Text(
              'Заказ выполнен в согласованном объёме, претензий по качеству и срокам стороны не имеют.',
              style: baseStyle,
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Исполнитель: _______________', style: baseStyle),
                pw.Text('Заказчик: _______________', style: baseStyle),
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static Future<File> saveOrderPdfToFile({
    required Order order,
    required StudioProfile profile,
    Client? client,
    PdfDocKind kind = PdfDocKind.invoice,
    Directory? outputDir,
  }) async {
    final bytes = await buildOrderPdfBytes(
      order: order,
      profile: profile,
      client: client,
      kind: kind,
    );
    final dir = outputDir ?? await getTemporaryDirectory();
    final pdfDir = Directory(p.join(dir.path, 'sweet_studio_pdf'));
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    final prefix = kind == PdfDocKind.invoice ? 'invoice' : 'act';
    final safeNum =
        order.orderNumber.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(p.join(pdfDir.path, '${prefix}_$safeNum.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> sharePdfFile(File file, {String? title}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: title ?? 'Документ SweetStudio',
      ),
    );
  }

  static Future<void> openPdfFile(File file) async {
    await OpenFilex.open(file.path);
  }

  static pw.Widget _cell(
    String text,
    pw.TextStyle style, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(text, style: style, textAlign: align),
    );
  }

  static pw.Widget _summaryRow(String label, String value, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }
}
