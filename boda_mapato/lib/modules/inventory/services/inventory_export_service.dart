import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/inv_customer.dart';
import '../models/inv_depot_models.dart';
import '../models/inv_sale.dart';
import '../../../services/localization_service.dart';

/// Area 11 export, and the Area 5 printed/shared receipt.
///
/// Every report already arrives as `columns` / `rows` / `meta` (see
/// [InvReport]), so one PDF writer and one Excel writer cover all 12 of them.
class InventoryExportService {
  const InventoryExportService();

  // --------------------------------------------------------------- reports

  Future<File> reportToPdf(InvReport report) async {
    final pw.Document doc = pw.Document();
    final List<String> headers =
        report.columns.map((InvReportColumn c) => c.label).toList();
    final List<List<String>> rows = report.rows
        .map((Map<String, dynamic> row) => report.columns
            .map((InvReportColumn c) => _cell(row[c.field]))
            .toList())
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              report.title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('${report.from} - ${report.to}',
                style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (_) => <pw.Widget>[
          if (rows.isEmpty)
            pw.Text(LocalizationService.instance.translate('no_data_for_period'))
          else
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerLeft,
            ),
        ],
      ),
    );

    return _write(doc, '${report.key}_${_stamp()}.pdf');
  }

  Future<File> reportToExcel(InvReport report) async {
    final xls.Excel book = xls.Excel.createExcel();
    final String sheetName =
        report.title.length > 28 ? report.title.substring(0, 28) : report.title;
    final xls.Sheet sheet = book[sheetName];
    book.setDefaultSheet(sheetName);
    // The library's default 'Sheet1' stays behind if not removed.
    if (book.sheets.containsKey('Sheet1') && sheetName != 'Sheet1') {
      book.delete('Sheet1');
    }

    sheet.appendRow(
      report.columns
          .map((InvReportColumn c) => xls.TextCellValue(c.label))
          .toList(),
    );
    for (final Map<String, dynamic> row in report.rows) {
      sheet.appendRow(
        report.columns
            .map((InvReportColumn c) => _excelCell(row[c.field]))
            .toList(),
      );
    }

    final List<int>? bytes = book.encode();
    if (bytes == null) {
      throw StateError('Could not encode the workbook');
    }

    final Directory dir = await getTemporaryDirectory();
    final File file = File('${dir.path}/${report.key}_${_stamp()}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> shareFile(File file, {String? subject}) =>
      Share.shareXFiles(<XFile>[XFile(file.path)], subject: subject);

  Future<void> printPdf(File file) => Printing.layoutPdf(
        onLayout: (_) => file.readAsBytes(),
      );

  // --------------------------------------------------------------- receipt

  /// One sale as a printable A6-ish receipt.
  Future<File> saleReceiptToPdf(
    InvSale sale, {
    InvCustomer? customer,
    String depotName = '',
    String depotPhone = '',
    String depotAddress = '',
  }) async {
    final pw.Document doc = pw.Document();
    final double balance = sale.total - sale.paidTotal;

    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(226, double.infinity,
            marginAll: 10), // ~80mm thermal-receipt width
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: <pw.Widget>[
            if (depotName.isNotEmpty)
              pw.Text(depotName,
                  style:
                      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            if (depotPhone.isNotEmpty)
              pw.Text(depotPhone, style: const pw.TextStyle(fontSize: 9)),
            if (depotAddress.isNotEmpty)
              pw.Text(depotAddress, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 6),
            pw.Divider(),
            _row(LocalizationService.instance.translate('receipt'), sale.number),
            _row(LocalizationService.instance.translate('receipt_date'),
                '${sale.createdAt.day}/${sale.createdAt.month}/${sale.createdAt.year}'),
            if (customer != null) _row(LocalizationService.instance.translate('customer'), customer.name),
            _row(LocalizationService.instance.translate('status'), sale.paymentStatus.toUpperCase()),
            pw.Divider(),
            pw.Table(
              columnWidths: const <int, pw.TableColumnWidth>{
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(2),
              },
              children: <pw.TableRow>[
                pw.TableRow(children: <pw.Widget>[
                  pw.Text(LocalizationService.instance.translate('export_item'),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(LocalizationService.instance.translate('qty_label'),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(LocalizationService.instance.translate('total'),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ]),
                ...sale.items.map(
                  (InvSaleItem item) => pw.TableRow(children: <pw.Widget>[
                    pw.Text(item.name, style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('${item.qty}',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(item.total.toStringAsFixed(0),
                        style: const pw.TextStyle(fontSize: 9)),
                  ]),
                ),
              ],
            ),
            pw.Divider(),
            _row(LocalizationService.instance.translate('subtotal'), sale.subtotal.toStringAsFixed(0)),
            if (sale.discount > 0)
              _row(LocalizationService.instance.translate('discount'), '-${sale.discount.toStringAsFixed(0)}'),
            if (sale.tax > 0) _row(LocalizationService.instance.translate('export_tax'), sale.tax.toStringAsFixed(0)),
            _row(LocalizationService.instance.translate('total'), sale.total.toStringAsFixed(0), bold: true),
            _row(LocalizationService.instance.translate('paid_payments'), sale.paidTotal.toStringAsFixed(0)),
            if (balance > 0.009)
              _row(LocalizationService.instance.translate('balance'), balance.toStringAsFixed(0), bold: true),
            pw.SizedBox(height: 8),
            pw.Text(LocalizationService.instance.translate('thank_you_for_your_business'),
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );

    return _write(doc, 'receipt_${sale.number}.pdf');
  }

  pw.Widget _row(String label, String value, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );

  // --------------------------------------------------------------- helpers

  Future<File> _write(pw.Document doc, String filename) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File('${dir.path}/$filename');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  String _stamp() {
    final DateTime now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _cell(dynamic value) {
    if (value == null) return '';
    if (value is num) {
      return value % 1 == 0
          ? value.toInt().toString()
          : value.toStringAsFixed(2);
    }
    final String text = value.toString();
    return text.length > 10 && text.contains('T')
        ? text.split('T').first
        : text;
  }

  xls.CellValue _excelCell(dynamic value) {
    if (value == null) return xls.TextCellValue('');
    if (value is int) return xls.IntCellValue(value);
    if (value is num) return xls.DoubleCellValue(value.toDouble());
    return xls.TextCellValue(_cell(value));
  }
}
