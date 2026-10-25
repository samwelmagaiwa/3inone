import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_sale.dart';
import '../../providers/depot_provider.dart';
import '../salon/salon_sale_breakdown_card.dart';
import '../settings/receipt_header_screen.dart';

/// Full-screen thermal receipt viewer.
/// Settings are read live from [DepotProvider] so the receipt always reflects
/// the latest configuration saved by admin/manager.
class SaleReceiptScreen extends StatefulWidget {
  const SaleReceiptScreen({super.key, required this.sale});

  final InvSale sale;

  static Route<void> route(InvSale sale) => MaterialPageRoute<void>(
        builder: (_) => SaleReceiptScreen(sale: sale),
      );

  @override
  State<SaleReceiptScreen> createState() => _SaleReceiptScreenState();
}

class _SaleReceiptScreenState extends State<SaleReceiptScreen> {
  static const String _stars = '* * * * * * * * * * * * * * * * * * * * *';
  static const String _dots  = '. . . . . . . . . . . . . . . . . . . . .';

  final GlobalKey _receiptKey = GlobalKey();

  InvSale get sale => widget.sale;

  // Sanitise a setting value — treat missing, empty and literal "null" as ''.
  static String _s(Map<String, String> s, String key, [String fallback = '']) {
    final v = s[key]?.trim() ?? '';
    return (v == 'null' || v.isEmpty) ? fallback : v;
  }

  String _fmt(double v) => NumberFormat('#,##0').format(v);

  // ── Thermal 80mm plain text (48 chars wide) ─────────────────────────────────
  String _buildThermalText(Map<String, String> s) {
    final shopName = _s(s, 'depot_name', LocalizationService.instance.translate('your_shop'));
    final address  = _s(s, 'depot_address');
    final phone    = _s(s, 'depot_phone');
    final tin      = _s(s, 'receipt_tin');
    final footer   = _s(s, 'receipt_footer_note',
        LocalizationService.instance.translate('receipt_footer_default'));

    const w = 48;
    String c(String t) {
      if (t.length >= w) return t;
      final pad = (w - t.length) ~/ 2;
      return ' ' * pad + t;
    }
    String lr(String l, String r) {
      final gap = w - l.length - r.length;
      return gap > 0 ? l + ' ' * gap + r : '$l $r';
    }
    String line([String ch = '-']) => ch * w;

    final sb = StringBuffer();
    sb.writeln(c(shopName.toUpperCase()));
    if (address.isNotEmpty) sb.writeln(c(address));
    if (phone.isNotEmpty)   sb.writeln(c(LocalizationService.instance.translateWith('phone', <Object?>[phone])));
    if (tin.isNotEmpty)     sb.writeln(c('TIN: $tin'));
    sb.writeln(line('='));
    sb.writeln(c(LocalizationService.instance.translate('sale_receipt').toUpperCase()));
    sb.writeln(line('='));

    final custName  = sale.customerName?.isNotEmpty  == true ? sale.customerName!  : LocalizationService.instance.translate('walk_in_customer').toUpperCase();
    final custPhone = sale.customerPhone?.isNotEmpty == true ? sale.customerPhone! : null;
    sb.writeln(c(custName.toUpperCase()));
    if (custPhone != null) sb.writeln(c(custPhone));
    sb.writeln(line());

    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt);
    sb.writeln(lr(LocalizationService.instance.translateWith('number', <Object?>[sale.number]), dateStr));
    sb.writeln(line());

    // Items
    sb.writeln(lr('BIDHAA', LocalizationService.instance.translate('total').toUpperCase()));
    sb.writeln(line('-'));
    for (final item in sale.items) {
      final name = item.name.length > 28 ? item.name.substring(0, 28) : item.name;
      sb.writeln(name);
      final String unit = (item.unitName ?? '').isEmpty ? '' : ' ${item.unitName}';
      sb.writeln(lr('  ${item.qty}$unit x TZS ${_fmt(item.unitPrice)}',
          'TZS ${_fmt(item.total)}'));
    }
    sb.writeln(line());

    if (sale.discount > 0) sb.writeln(lr('${LocalizationService.instance.translate('discount')}:', '- TZS ${_fmt(sale.discount)}'));
    if (sale.tax > 0)      sb.writeln(lr('${LocalizationService.instance.translate('tax_vat')}:', 'TZS ${_fmt(sale.tax)}'));
    sb.writeln(lr('${LocalizationService.instance.translate('grand_total').toUpperCase()}:', 'TZS ${_fmt(sale.total)}'));
    sb.writeln(line('='));

    // Payments
    sb.writeln(c(LocalizationService.instance.translate('payments_section').toUpperCase()));
    sb.writeln(line('-'));
    if (sale.payments.isEmpty && sale.paidTotal > 0) {
      sb.writeln(lr('${LocalizationService.instance.translate('paid_3')}:', 'TZS ${_fmt(sale.paidTotal)}'));
    } else if (sale.payments.isEmpty) {
      sb.writeln(lr('${LocalizationService.instance.translate('payment_method_label')}:', '—'));
    } else {
      for (final p in sale.payments) {
        final method = _methodLabel(p.method);
        final dateP  = DateFormat('dd/MM/yy HH:mm').format(p.paidAt);
        sb.writeln(lr('$method ($dateP):', 'TZS ${_fmt(p.amount)}'));
      }
    }
    sb.writeln(lr('${LocalizationService.instance.translate('total_paid')}:', 'TZS ${_fmt(sale.paidTotal)}'));

    final change      = (sale.paidTotal - sale.total).clamp(0, double.infinity);
    final outstanding = (sale.total    - sale.paidTotal).clamp(0, double.infinity);
    if (change > 0)      sb.writeln(lr('${LocalizationService.instance.translate('change')}:', 'TZS ${_fmt(change as double)}'));
    if (outstanding > 0) sb.writeln(lr('${LocalizationService.instance.translate('balance_due').toUpperCase()}:', 'TZS ${_fmt(outstanding as double)}'));

    final status = sale.paymentStatus == 'paid' ? LocalizationService.instance.translate('ok_fully_paid').toUpperCase() :
                   sale.paymentStatus == 'debt'  ? LocalizationService.instance.translate('x_debt').toUpperCase() : LocalizationService.instance.translate('partial_2').toUpperCase();
    sb.writeln(line('='));
    sb.writeln(c(status));
    sb.writeln(line('='));
    sb.writeln(c(LocalizationService.instance.translate('thank_you_2').toUpperCase()));

    sb.writeln(c(footer));
    sb.writeln(line());
    return sb.toString();
  }

  String _methodLabel(String m) {
    switch (m.toLowerCase()) {
      case 'cash':          return LocalizationService.instance.translate('method_cash');
      case 'mobile_money':
      case 'mobile':        return LocalizationService.instance.translate('m_pesa_mobile');
      case 'bank_transfer':
      case 'bank':          return LocalizationService.instance.translate('payment_channel_bank');
      case 'cheque':        return LocalizationService.instance.translate('method_cheque');
      default:              return m;
    }
  }

  // ── PDF generation ── styled to match on-screen receipt ────────────────────
  Future<pw.Document> _buildPdf(Map<String, String> s) async {
    final shopName  = _s(s, 'depot_name', LocalizationService.instance.translate('your_shop'));
    final address   = _s(s, 'depot_address');
    final phone     = _s(s, 'depot_phone');
    final tin       = _s(s, 'receipt_tin');
    final footer    = _s(s, 'receipt_footer_note',
        LocalizationService.instance.translate('receipt_footer_default'));
    final showTin   = (s['receipt_show_tin'] ?? '1') == '1';

    final doc       = pw.Document();
    final regular   = pw.Font.helvetica();
    final bold      = pw.Font.helveticaBold();

    // Palette
    final ink       = PdfColor.fromHex('#0D0D0D');
    final muted     = PdfColor.fromHex('#555555');
    final lightGrey = PdfColor.fromHex('#F4F4F2');
    final redDark   = PdfColor.fromHex('#B71C1C');
    final redLight  = PdfColor.fromHex('#FFEBEE');
    final redBorder = PdfColor.fromHex('#EF9A9A');
    final greenDark = PdfColor.fromHex('#1B5E20');
    final greenLight= PdfColor.fromHex('#E8F5E9');
    final orangeDark= PdfColor.fromHex('#E65100');
    final orangeLight=PdfColor.fromHex('#FFF3E0');

    final custName  = sale.customerName?.isNotEmpty  == true
        ? sale.customerName!.toUpperCase() : LocalizationService.instance.translate('walk_in_customer').toUpperCase();
    final custPhone = sale.customerPhone?.isNotEmpty == true
        ? sale.customerPhone! : null;
    final dateStr   = DateFormat('dd MMM yyyy').format(sale.createdAt);
    final timeStr   = DateFormat('HH:mm').format(sale.createdAt);
    final change      = (sale.paidTotal - sale.total).clamp(0.0, double.infinity) as double;
    final outstanding = (sale.total - sale.paidTotal).clamp(0.0, double.infinity) as double;

    // ── Helpers ──────────────────────────────────────────────────────────────
    pw.TextStyle ts(double size, {bool b = false, PdfColor? color, double? height}) =>
        pw.TextStyle(font: b ? bold : regular, fontSize: size,
            color: color ?? ink, lineSpacing: height ?? 1.2);

    pw.Widget thick() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Divider(thickness: 1.5, color: ink),
        );

    pw.Widget thin() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Divider(thickness: 0.5, color: PdfColor.fromHex('#BBBBBB')),
        );

    // Left label + right value row
    pw.Widget row(String label, String value,
            {bool b = false, PdfColor? color, String? sub}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(label, style: ts(9, b: b, color: color ?? muted)),
                    if (sub != null)
                      pw.Text(sub, style: ts(7.5, color: PdfColor.fromHex('#999999'))),
                  ],
                ),
              ),
              pw.Text(value,
                  textAlign: pw.TextAlign.right,
                  style: ts(9, b: b, color: color ?? ink)),
            ],
          ),
        );

    // Section header banner (centred label between two rules)
    pw.Widget banner(String label) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Divider(thickness: 1, color: ink)),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8),
              child: pw.Text(label,
                  style: ts(9, b: true, color: ink),
                  textAlign: pw.TextAlign.center),
            ),
            pw.Expanded(child: pw.Divider(thickness: 1, color: ink)),
          ]),
        );

    // ── Page ─────────────────────────────────────────────────────────────────
    // 105 mm wide matches a typical phone receipt view; height auto-fits
    final pageH = (150.0 + sale.items.length * 18.0) * PdfPageFormat.mm;
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(105 * PdfPageFormat.mm, pageH,
          marginTop: 8 * PdfPageFormat.mm,
          marginBottom: 8 * PdfPageFormat.mm,
          marginLeft: 8 * PdfPageFormat.mm,
          marginRight: 8 * PdfPageFormat.mm),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [

          // ── Store header ─────────────────────────────────────────────────
          pw.Center(
            child: pw.Text(shopName.toUpperCase(),
                style: ts(20, b: true), textAlign: pw.TextAlign.center),
          ),
          if (address.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Center(child: pw.Text(address,
                style: ts(8, color: muted), textAlign: pw.TextAlign.center)),
          ],
          pw.SizedBox(height: 4),
          // Phone left — TIN right
          pw.Row(children: [
            if (phone.isNotEmpty)
              pw.Text(LocalizationService.instance.translateWith('phone', <Object?>[phone]), style: ts(9, b: true)),
            pw.Spacer(),
            if (showTin && tin.isNotEmpty)
              pw.Text('TIN: $tin', style: ts(9, b: true)),
          ]),
          thick(),

          // ── Receipt title ────────────────────────────────────────────────
          banner(LocalizationService.instance.translate('sale_receipt').toUpperCase()),

          // ── Customer ─────────────────────────────────────────────────────
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(custName,
              style: ts(13, b: true), textAlign: pw.TextAlign.center)),
          if (custPhone != null) ...[
            pw.SizedBox(height: 2),
            pw.Center(child: pw.Text(custPhone,
                style: ts(9, color: muted), textAlign: pw.TextAlign.center)),
          ],
          pw.SizedBox(height: 6),

          // ── Meta grid (2 × 2) ────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: lightGrey,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(LocalizationService.instance.translate('receipt_number_label'), style: ts(7.5, color: muted)),
                    pw.Text(sale.number, style: ts(9, b: true)),
                    pw.SizedBox(height: 4),
                    pw.Text(LocalizationService.instance.translate('receipt_time'), style: ts(7.5, color: muted)),
                    pw.Text(timeStr, style: ts(9, b: true)),
                  ],
                )),
                pw.Expanded(child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(LocalizationService.instance.translate('date'), style: ts(7.5, color: muted)),
                    pw.Text(dateStr, style: ts(9, b: true)),
                    pw.SizedBox(height: 4),
                    pw.Text(LocalizationService.instance.translate('payment_status_label'), style: ts(7.5, color: muted)),
                    pw.Text(
                      sale.paymentStatus == 'paid' ? LocalizationService.instance.translate('bill_paid')
                        : sale.paymentStatus == 'debt' ? LocalizationService.instance.translate('status_debt_label') : LocalizationService.instance.translate('bill_partial'),
                      style: ts(9, b: true,
                          color: sale.paymentStatus == 'paid' ? greenDark
                            : sale.paymentStatus == 'debt' ? redDark : orangeDark),
                    ),
                  ],
                )),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // ── Items table ──────────────────────────────────────────────────
          pw.Row(children: [
            pw.Expanded(child: pw.Text(LocalizationService.instance.translate('items_header'), style: ts(9, b: true))),
            pw.SizedBox(width: 30,
                child: pw.Text(LocalizationService.instance.translate('qty').toUpperCase(), style: ts(9, b: true),
                    textAlign: pw.TextAlign.center)),
            pw.SizedBox(width: 55,
                child: pw.Text(LocalizationService.instance.translate('total').toUpperCase(), style: ts(9, b: true),
                    textAlign: pw.TextAlign.right)),
          ]),
          thin(),
          ...sale.items.asMap().entries.map((e) {
            final item   = e.value;
            final shaded = e.key.isEven;
            return pw.Container(
              color: shaded ? lightGrey : PdfColors.white,
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(item.name, style: ts(9, b: true), maxLines: 2),
                      pw.Text('@ TZS ${_fmt(item.unitPrice)}${(item.unitName ?? '').isEmpty ? '' : ' / ${item.unitName}'}',
                          style: ts(7.5, color: muted)),
                    ],
                  )),
                  pw.SizedBox(width: 30,
                      child: pw.Center(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: pw.BoxDecoration(
                            color: ink,
                            borderRadius:
                                const pw.BorderRadius.all(pw.Radius.circular(3)),
                          ),
                          child: pw.Text('x${item.qty}',
                              style: ts(8, b: true, color: PdfColors.white),
                              textAlign: pw.TextAlign.center),
                        ),
                      )),
                  pw.SizedBox(width: 55,
                      child: pw.Text('TZS ${_fmt(item.total)}',
                          style: ts(9, b: true),
                          textAlign: pw.TextAlign.right)),
                ],
              ),
            );
          }),
          thin(),
          pw.SizedBox(height: 2),

          // ── Subtotals ────────────────────────────────────────────────────
          if (sale.discount > 0)
            row(LocalizationService.instance.translate('discount'), '- TZS ${_fmt(sale.discount)}', color: redDark),
          if (sale.tax > 0)
            row(LocalizationService.instance.translate('tax_vat'), 'TZS ${_fmt(sale.tax)}'),

          // Grand total
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text(LocalizationService.instance.translate('grand_total').toUpperCase(),
                  style: ts(14, b: true))),
              pw.Text('TZS ${_fmt(sale.total)}',
                  style: ts(14, b: true),
                  textAlign: pw.TextAlign.right),
            ]),
          ),
          thick(),

          // ── Payments ─────────────────────────────────────────────────────
          banner(LocalizationService.instance.translate('payments_section').toUpperCase()),
          if (sale.payments.isEmpty && sale.paidTotal > 0)
            row(LocalizationService.instance.translate('paid_3'), 'TZS ${_fmt(sale.paidTotal)}')
          else if (sale.payments.isEmpty)
            row(LocalizationService.instance.translate('payment_method_label'), '—')
          else
            ...sale.payments.map((p) => row(
                  _methodLabel(p.method),
                  'TZS ${_fmt(p.amount)}',
                  sub: DateFormat('dd/MM/yyyy HH:mm').format(p.paidAt),
                )),
          row(LocalizationService.instance.translate('total_paid'), 'TZS ${_fmt(sale.paidTotal)}', b: true),
          if (change > 0)
            row(LocalizationService.instance.translate('change'), 'TZS ${_fmt(change)}'),
          if (outstanding > 0) ...[
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: pw.BoxDecoration(
                color: redLight,
                border: pw.Border.all(color: redBorder),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text(LocalizationService.instance.translate('outstanding_balance'),
                    style: ts(9, color: redDark))),
                pw.Text('TZS ${_fmt(outstanding)}',
                    style: ts(9, b: true, color: redDark),
                    textAlign: pw.TextAlign.right),
              ]),
            ),
          ],
          pw.SizedBox(height: 6),

          // ── Status badge ─────────────────────────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 7),
            decoration: pw.BoxDecoration(
              color: sale.paymentStatus == 'paid' ? greenLight
                  : sale.paymentStatus == 'debt' ? redLight : orangeLight,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Text(
              sale.paymentStatus == 'paid'  ? LocalizationService.instance.translate('status_paid_label').toUpperCase()
                : sale.paymentStatus == 'debt' ? LocalizationService.instance.translate('status_debt_label').toUpperCase()
                : LocalizationService.instance.translate('bill_partial').toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: ts(13, b: true,
                  color: sale.paymentStatus == 'paid' ? greenDark
                    : sale.paymentStatus == 'debt' ? redDark : orangeDark),
            ),
          ),
          thick(),

          // ── Footer ───────────────────────────────────────────────────────
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text('${LocalizationService.instance.translate('thank_you_3').toUpperCase()}!',
              style: ts(14, b: true), textAlign: pw.TextAlign.center)),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(footer,
              style: ts(8, color: muted), textAlign: pw.TextAlign.center)),
          pw.SizedBox(height: 4),
          thin(),
        ],
      ),
    ));
    return doc;
  }

  // ── Capture on-screen receipt widget as PNG ────────────────────────────────
  Future<Uint8List?> _captureReceiptPng() async {
    final boundary = _receiptKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image   = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _shareReceiptImage() async {
    final png = await _captureReceiptPng();
    if (png == null) return;
    final tmp  = await getTemporaryDirectory();
    final file = File('${tmp.path}/Risiti-${sale.number}.png');
    await file.writeAsBytes(png);
    await Share.shareXFiles([XFile(file.path)], subject: LocalizationService.instance.translateWith('receipt_2', <Object?>[sale.number]));
  }

  Future<void> _printReceiptImage() async {
    final png = await _captureReceiptPng();
    if (png == null) return;
    final doc  = pw.Document();
    final img  = pw.MemoryImage(png);
    // Decode image size to decide whether to fit by width or height
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final imgW  = frame.image.width.toDouble();
    final imgH  = frame.image.height.toDouble();

    // A4 printable area with 5mm margins (in mm): 200 × 287
    const printW = 200.0;
    const printH = 287.0;
    final imgRatio  = imgW / imgH;
    final pageRatio = printW / printH;
    // If image is taller relative to page, fit by height; else fit by width
    final fit = imgRatio < pageRatio ? pw.BoxFit.fitHeight : pw.BoxFit.fitWidth;

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(5 * PdfPageFormat.mm),
      build: (_) => pw.Center(
        child: pw.Image(img, fit: fit),
      ),
    ));
    final bytes = await doc.save();
    await Printing.layoutPdf(
        onLayout: (_) async => bytes, name: 'Risiti-${sale.number}');
  }

  // ── Print options sheet ────────────────────────────────────────────────────
  void _showOptions(BuildContext context, Map<String, String> s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PrintOptionsSheet(
        onScreenPrint: () async {
          Navigator.pop(context);
          await _printReceiptImage();
        },
        onScreenShare: () async {
          Navigator.pop(context);
          await _shareReceiptImage();
        },
        onColoredPdf: () async {
          Navigator.pop(context);
          final doc = await _buildPdf(s);
          final bytes = await doc.save();
          await Printing.layoutPdf(onLayout: (_) async => bytes,
              name: 'Risiti-${sale.number}');
        },
        onThermal: () async {
          Navigator.pop(context);
          final text = _buildThermalText(s);
          final tmp  = await getTemporaryDirectory();
          final file = File('${tmp.path}/Risiti-${sale.number}-thermal.txt');
          await file.writeAsString(text);
          await Share.shareXFiles([XFile(file.path)],
              subject: LocalizationService.instance.translateWith('receipt_2', <Object?>[sale.number]),
              text: text);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    final loc  = context.watch<LocalizationService>();
    final s    = context.watch<DepotProvider>().settings;
    final auth = context.watch<AuthProvider>();
    // Saving depot/receipt settings is gated server-side by inv_manage_settings.
    final canConfigure = context.select<AuthProvider, UserPermissions>((AuthProvider a) => a.permissions).has('inv_manage_settings');

    final shopName   = _s(s, 'depot_name', LocalizationService.instance.translate('your_shop'));
    final tagline    = _s(s, 'receipt_tagline');
    final address    = _s(s, 'depot_address');
    final phone      = _s(s, 'depot_phone');
    final email      = _s(s, 'receipt_email');
    final website    = _s(s, 'receipt_website');
    final tin        = _s(s, 'receipt_tin');
    final footer     = _s(s, 'receipt_footer_note');
    final showBarcode= (s['receipt_show_barcode'] ?? '1') == '1';
    final showTin    = (s['receipt_show_tin']     ?? '1') == '1';

    return Scaffold(
      backgroundColor: const Color(0xFFDDDDDD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(loc.translate('sale_receipt'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15,
                    color: Colors.white, letterSpacing: 0.5)),
            Text(sale.number,
                style: const TextStyle(fontSize: 10, color: Colors.white54,
                    letterSpacing: 1)),
          ],
        ),
        centerTitle: true,
        actions: [
          if (canConfigure)
            _AppBarAction(
              icon: Icons.tune_rounded,
              tooltip: loc.translate('receipt_settings'),
              onTap: () => Navigator.of(context).push(ReceiptHeaderScreen.route()),
            ),
          _AppBarAction(
            icon: Icons.print_rounded,
            tooltip: loc.translate('print_share'),
            onTap: () => _showOptions(context, s),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(children: <Widget>[
          // A salon's owner sees what the service and the goods on this sale each earned (nobody else, and not on a shop's sale).
          SalonSaleBreakdownCard(saleId: sale.id),
          Center(
          child: RepaintBoundary(
            key: _receiptKey,
            child: _ReceiptPaper(
              sale: sale,
              shopName: shopName,
              tagline: tagline,
              shopAddress: address,
              shopPhone: phone,
              email: email,
              website: website,
              tin: tin,
              footerNote: footer,
              showBarcode: showBarcode,
              showTin: showTin,
              stars: _stars,
              dots: _dots,
            ),
          ),
        ),
        ]),
      ),
    );
  }
}

// ── Print options bottom sheet ─────────────────────────────────────────────────
class _PrintOptionsSheet extends StatelessWidget {
  const _PrintOptionsSheet({
    required this.onScreenPrint,
    required this.onScreenShare,
    required this.onColoredPdf,
    required this.onThermal,
  });
  final VoidCallback onScreenPrint;
  final VoidCallback onScreenShare;
  final VoidCallback onColoredPdf;
  final VoidCallback onThermal;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(loc.translate('print_share_options'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700,
                  fontSize: 15, letterSpacing: 0.5)),
          const SizedBox(height: 20),

          // ── Screen receipt (as configured) ───────────────────────────────
          _OptionTile(
            icon: Icons.phone_android_rounded,
            iconColor: const Color(0xFF9C27B0),
            title: loc.translate('print_receipt_current_view'),
            subtitle: loc.translate('print_receipt_current_view_sub'),
            onTap: onScreenPrint,
          ),
          const SizedBox(height: 10),
          _OptionTile(
            icon: Icons.image_rounded,
            iconColor: const Color(0xFF00BCD4),
            title: loc.translate('share_receipt_image'),
            subtitle: loc.translate('share_receipt_image_sub'),
            onTap: onScreenShare,
          ),
          const SizedBox(height: 10),

          // ── PDF ───────────────────────────────────────────────────────────
          _OptionTile(
            icon: Icons.picture_as_pdf_rounded,
            iconColor: const Color(0xFF4CAF50),
            title: loc.translate('print_share_colored_pdf'),
            subtitle: loc.translate('print_share_colored_pdf_sub'),
            onTap: onColoredPdf,
          ),
          const SizedBox(height: 10),

          // ── Thermal ───────────────────────────────────────────────────────
          _OptionTile(
            icon: Icons.receipt_long_outlined,
            iconColor: const Color(0xFFFF9800),
            title: loc.translate('thermal_80mm'),
            subtitle: loc.translate('thermal_80mm_sub'),
            onTap: onThermal,
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
            ],
          ),
        ),
      );
}

/// Pill-shaped icon button for the receipt AppBar.
class _AppBarAction extends StatelessWidget {
  const _AppBarAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ),
        ),
      );
}

class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({
    required this.sale,
    required this.shopName,
    required this.tagline,
    required this.shopAddress,
    required this.shopPhone,
    required this.email,
    required this.website,
    required this.tin,
    required this.footerNote,
    required this.showBarcode,
    required this.showTin,
    required this.stars,
    required this.dots,
  });

  final InvSale sale;
  final String shopName;
  final String tagline;
  final String shopAddress;
  final String shopPhone;
  final String email;
  final String website;
  final String tin;
  final String footerNote;
  final bool showBarcode;
  final bool showTin;
  final String stars;
  final String dots;

  // ── Type scale ───────────────────────────────────────────────────────────
  static const TextStyle _body = TextStyle(
    fontFamily: 'Courier', fontSize: 12, color: Color(0xFF1A1A1A), height: 1.25,
  );
  static const TextStyle _bodyBold = TextStyle(
    fontFamily: 'Courier', fontSize: 12, fontWeight: FontWeight.w700,
    color: Color(0xFF1A1A1A), height: 1.25,
  );
  static const TextStyle _label = TextStyle(
    fontFamily: 'Courier', fontSize: 11, color: Color(0xFF333333), height: 1.2,
  );
  static const TextStyle _shopName = TextStyle(
    fontFamily: 'Courier', fontSize: 22, fontWeight: FontWeight.w900,
    letterSpacing: 3, color: Color(0xFF0D0D0D),
  );
  static const TextStyle _total = TextStyle(
    fontFamily: 'Courier', fontSize: 18, fontWeight: FontWeight.w900,
    color: Color(0xFF0D0D0D), height: 1.4,
  );
  static const TextStyle _starLine = TextStyle(
    fontFamily: 'Courier', fontSize: 10, color: Color(0xFF444444), letterSpacing: 1,
  );

  // Whole-number TZS format (no cents)
  String _fmt(double v) => NumberFormat('#,##0').format(v);

  String _statusLabel(LocalizationService loc) {
    switch (sale.paymentStatus) {
      case 'paid':    return '✓  ${loc.translate('status_paid_label')}';
      case 'debt':    return '✗  ${loc.translate('status_debt_label')}';
      case 'partial': return '◑  ${loc.translate('status_partial_label')}';
      default:        return sale.paymentStatus.toUpperCase();
    }
  }

  Color _statusColor() {
    switch (sale.paymentStatus) {
      case 'paid':    return const Color(0xFF1B5E20);
      case 'debt':    return const Color(0xFFB71C1C);
      default:        return const Color(0xFFE65100);
    }
  }

  Color _statusBg() {
    switch (sale.paymentStatus) {
      case 'paid':    return const Color(0xFFE8F5E9);
      case 'debt':    return const Color(0xFFFFEBEE);
      default:        return const Color(0xFFFFF3E0);
    }
  }

  String _methodLabel(String m, LocalizationService loc) {
    switch (m.toLowerCase()) {
      case 'cash':          return loc.translate('method_cash');
      case 'mobile_money':  return loc.translate('method_mobile_money');
      case 'mobile':        return loc.translate('method_mobile_money');
      case 'bank_transfer': return loc.translate('method_bank');
      case 'bank':          return loc.translate('method_bank');
      case 'cheque':        return loc.translate('method_cheque');
      default:              return m;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final double change      = (sale.paidTotal - sale.total).clamp(0, double.infinity);
    final double outstanding = (sale.total - sale.paidTotal).clamp(0, double.infinity);
    final dateStr  = DateFormat('dd MMM yyyy').format(sale.createdAt);
    final timeStr  = DateFormat('HH:mm').format(sale.createdAt);
    final custName  = sale.customerName?.isNotEmpty  == true ? sale.customerName!  : null;
    final custPhone = sale.customerPhone?.isNotEmpty == true ? sale.customerPhone! : null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(top: -10, left: 0, right: 0, child: _TornEdge(top: true)),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFFAFAF8),
            boxShadow: [
              BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6)),
              BoxShadow(color: Color(0x18000000), blurRadius: 40, offset: Offset(0, 20)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                // ── Store emblem + name (side by side) ───────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D0D),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Flexible(child: Text(shopName, style: _shopName, textAlign: TextAlign.left)),
                  ],
                ),
                if (tagline.isNotEmpty && tagline != 'null') ...[
                  const SizedBox(height: 3),
                  Text(tagline,
                      style: _label.copyWith(fontStyle: FontStyle.italic, letterSpacing: 1),
                      textAlign: TextAlign.center),
                ],
                // ── Phone (left) + TIN (right) on same row ───────────────
                if ((shopPhone.isNotEmpty && shopPhone != 'null') ||
                    (showTin && tin.isNotEmpty && tin != 'null')) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (shopPhone.isNotEmpty && shopPhone != 'null')
                        Row(children: [
                          const Icon(Icons.phone_rounded, size: 12, color: Color(0xFF0D0D0D)),
                          const SizedBox(width: 4),
                          Text(shopPhone,
                              style: const TextStyle(fontFamily: 'Courier', fontSize: 12,
                                  fontWeight: FontWeight.w800, color: Color(0xFF0D0D0D))),
                        ]),
                      const Spacer(),
                      if (showTin && tin.isNotEmpty && tin != 'null')
                        Text('TIN: $tin',
                            style: const TextStyle(fontFamily: 'Courier', fontSize: 12,
                                fontWeight: FontWeight.w800, color: Color(0xFF0D0D0D))),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                // Contact strip (address, email, website — phone & TIN shown above)
                _ContactLine(address: shopAddress, phone: '',
                    email: email, website: website, tin: ''),
                const SizedBox(height: 12),

                // ── Receipt title banner ──────────────────────────────────
                _SectionBanner(label: LocalizationService.instance.translate('sale_receipt').toUpperCase()),
                const SizedBox(height: 12),

                // ── Customer name (always shown, transparent bg) ─────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('👤', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              custName != null ? custName.toUpperCase() : LocalizationService.instance.translate('walk_in_customer').toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Courier', fontSize: 13,
                                fontWeight: FontWeight.w900, letterSpacing: 2,
                                color: Color(0xFF0D0D0D),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (custPhone != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.phone, size: 11, color: Color(0xFF555555)),
                            const SizedBox(width: 4),
                            Text(
                              custPhone,
                              style: const TextStyle(
                                fontFamily: 'Courier', fontSize: 11,
                                color: Color(0xFF555555), letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // ── Sale meta card (transparent) ─────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      _MetaPair(
                        left: _MetaCell(icon: '🧾', label: loc.translate('receipt_number'), value: sale.number),
                        right: _MetaCell(icon: '📅', label: loc.translate('receipt_date'), value: dateStr),
                      ),
                      const SizedBox(height: 6),
                      _MetaPair(
                        left: _MetaCell(icon: '⏰', label: loc.translate('receipt_time'), value: timeStr),
                        right: _MetaCell(
                          icon: '💳',
                          label: loc.translate('payment_status_label'),
                          value: sale.paymentStatus == 'paid' ? loc.translate('paid') :
                                 sale.paymentStatus == 'debt' ? loc.translate('debt') : loc.translate('status_partial_label'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Items header ──────────────────────────────────────────
                Row(children: [
                  Expanded(child: Text(loc.translate('items_header'), style: _body.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 11))),
                  Text(loc.translate('qty'), style: _label.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  SizedBox(width: 90, child: Text(loc.translate('total'), style: _label.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                ]),
                const SizedBox(height: 4),
                _DashedDivider(),
                const SizedBox(height: 4),

                // ── Items ────────────────────────────────────────────────
                ...sale.items.asMap().entries.map((e) => _ItemRowV2(
                  item: e.value,
                  shaded: e.key.isEven,
                  fmt: _fmt,
                  body: _body,
                  label: _label,
                )),
                const SizedBox(height: 6),
                _DashedDivider(),

                // ── Subtotals ─────────────────────────────────────────────
                if (sale.discount > 0 || sale.tax > 0) ...[
                  const SizedBox(height: 6),
                  if (sale.discount > 0)
                    _TotalsRow(label: loc.translate('discount'), value: '− TZS ${_fmt(sale.discount)}',
                        bold: false, color: const Color(0xFFB71C1C)),
                  if (sale.tax > 0)
                    _TotalsRow(label: loc.translate('tax_vat'), value: 'TZS ${_fmt(sale.tax)}', bold: false),
                ],

                // ── Grand total ───────────────────────────────────────────
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(loc.translate('grand_total'),
                          style: _total.copyWith(color: const Color(0xFF0D0D0D), fontSize: 14, letterSpacing: 1))),
                      Text('TZS ${_fmt(sale.total)}',
                          style: _total.copyWith(color: const Color(0xFF0D0D0D))),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // ── Payment section ───────────────────────────────────────
                _SectionBanner(label: loc.translate('payments_section')),
                const SizedBox(height: 4),
                // Individual payment rows (method + amount + date)
                if (sale.payments.isEmpty)
                  _TotalsRow(label: loc.translate('payment_method_label'), value: '—', bold: false)
                else
                  ...sale.payments.map((p) => _TotalsRow(
                        label: _methodLabel(p.method, loc),
                        value: 'TZS ${_fmt(p.amount)}',
                        bold: false,
                        sub: DateFormat('dd/MM/yyyy HH:mm').format(p.paidAt),
                      )),
                _TotalsRow(label: loc.translate('total_paid'), value: 'TZS ${_fmt(sale.paidTotal)}', bold: true),
                if (change > 0)
                  _TotalsRow(label: loc.translate('change'), value: 'TZS ${_fmt(change)}', bold: false),
                if (outstanding > 0) ...[
                  const SizedBox(height: 3),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFEF9A9A)),
                    ),
                    child: Row(
                      children: [
                        const Text('⚠', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        Expanded(child: Text(loc.translate('outstanding_balance'),
                            style: _label.copyWith(color: const Color(0xFFB71C1C)))),
                        Text('TZS ${_fmt(outstanding)}',
                            style: _bodyBold.copyWith(color: const Color(0xFFB71C1C))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),

                // ── Status stamp (transparent) ────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    _statusLabel(loc),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      color: _statusColor(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Thank you ─────────────────────────────────────────────
                Text(stars, style: _starLine, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('★  ${loc.translate('thank_you')}  ★',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Courier', fontSize: 14,
                      fontWeight: FontWeight.w900, letterSpacing: 4,
                      color: Color(0xFF0D0D0D),
                    )),
                const SizedBox(height: 4),
                Text(
                  footerNote.isNotEmpty
                      ? footerNote
                      : LocalizationService.instance.translate('receipt_footer_default_lines'),
                  style: _label.copyWith(fontSize: 10, height: 1.4, color: const Color(0xFF2A2A2A)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(stars, style: _starLine, textAlign: TextAlign.center),

                // ── Barcode (left) + QR code (right) ─────────────────────
                if (showBarcode) ...[
                  const SizedBox(height: 10),
                  _BarcodeQrRow(data: sale.number, label: _label),
                ],
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
        Positioned(bottom: -10, left: 0, right: 0, child: _TornEdge(top: false)),
      ],
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

/// Full-width dashed separator.
class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(double.infinity, 1),
        painter: const _DashedPainter(),
      );
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter({
    this.color = const Color(0xFFCCCCCC),
    this.dashLen = 5,
    this.gap = 4,
  });
  final Color color;
  final double dashLen, gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashLen, 0), paint);
      x += dashLen + gap;
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Bold section banner with side rules.
class _SectionBanner extends StatelessWidget {
  const _SectionBanner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFF0D0D0D), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Courier', fontSize: 11,
                fontWeight: FontWeight.w900, letterSpacing: 3,
                color: Color(0xFF0D0D0D),
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFF0D0D0D), thickness: 1)),
        ],
      );
}

/// Compact contact line under shop name.
class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.address, required this.phone,
      required this.email, required this.website, required this.tin});
  final String address, phone, email, website, tin;

  @override
  Widget build(BuildContext context) {
    const ts = TextStyle(
      fontFamily: 'Courier', fontSize: 10, color: Color(0xFF2A2A2A), height: 1.6,
    );
    bool _ok(String v) => v.isNotEmpty && v != 'null';
    final parts = [
      if (_ok(address)) address,
      if (_ok(phone)) LocalizationService.instance.translateWith('phone', <Object?>[phone]),
      if (_ok(email)) email,
      if (_ok(website)) website,
      if (_ok(tin)) 'TIN: $tin',
    ];
    return Column(
      children: parts.map((p) => Text(p, style: ts, textAlign: TextAlign.center)).toList(),
    );
  }
}

/// One meta row: left cell — dashes — right cell spanning full width.
class _MetaPair extends StatelessWidget {
  const _MetaPair({required this.left, required this.right});
  final _MetaCell left, right;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left cell — label + value stacked
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${left.icon}  ${left.label}',
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 10,
                        color: Color(0xFF555555), fontWeight: FontWeight.w600)),
                Text(left.value,
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 12,
                        fontWeight: FontWeight.w900, color: Color(0xFF0D0D0D))),
              ],
            ),
            // Dashed connector
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CustomPaint(
                  size: const Size(double.infinity, 1),
                  painter: _DashedPainter(color: const Color(0xFF999999), dashLen: 4, gap: 4),
                ),
              ),
            ),
            // Right cell — label + value stacked, right-aligned
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${right.label}  ${right.icon}',
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 10,
                        color: Color(0xFF555555), fontWeight: FontWeight.w600)),
                Text(right.value,
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 12,
                        fontWeight: FontWeight.w900, color: Color(0xFF0D0D0D))),
              ],
            ),
          ],
        ),
      );
}

/// Data holder for a meta cell — no build needed, used by _MetaPair directly.
class _MetaCell {
  const _MetaCell({required this.icon, required this.label, required this.value});
  final String icon, label, value;
}

/// Alternating-shaded item row with qty pill.
class _ItemRowV2 extends StatelessWidget {
  const _ItemRowV2({required this.item, required this.shaded,
      required this.fmt, required this.body, required this.label});
  final InvSaleItem item;
  final bool shaded;
  final String Function(double) fmt;
  final TextStyle body, label;

  @override
  Widget build(BuildContext context) => Container(
        color: shaded ? const Color(0xFFF4F4F2) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Name + unit price
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: body.copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('@ TZS ${fmt(item.unitPrice)}${(item.unitName ?? '').isEmpty ? '' : ' / ${item.unitName}'}',
                      style: label.copyWith(fontSize: 10, color: const Color(0xFF444444))),
                ],
              ),
            ),
            // Qty pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('×${item.qty}',
                  style: const TextStyle(fontFamily: 'Courier',
                      fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            // Line total
            SizedBox(
              width: 90,
              child: Text('TZS ${fmt(item.total)}',
                  style: body.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

/// Label + value totals row.
class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.label, required this.value,
      required this.bold, this.color, this.sub});
  final String label, value;
  final bool bold;
  final Color? color;
  final String? sub; // optional sub-label (e.g. date of payment)

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF1A1A1A);
    final ts = TextStyle(fontFamily: 'Courier', fontSize: 12,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
        color: c, height: 1.2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ts.copyWith(
                    color: const Color(0xFF2A2A2A), fontWeight: FontWeight.w600)),
                if (sub != null)
                  Text(sub!, style: ts.copyWith(
                      fontSize: 9, color: const Color(0xFF888888),
                      fontWeight: FontWeight.w400)),
              ],
            ),
          ),
          Text(value, style: ts, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Side-by-side: Code 128 barcode on the left, QR code on the right.
/// Both encode the sale number so any scanner resolves to the same receipt.
class _BarcodeQrRow extends StatelessWidget {
  const _BarcodeQrRow({required this.data, required this.label});
  final String data;
  final TextStyle label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDDDDD)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left: Code 128 barcode ───────────────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: _Code128Barcode(data: data),
                ),
                const SizedBox(height: 4),
                Text(
                  data,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 9,
                    letterSpacing: 1.5,
                    color: Color(0xFF333333),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'BARCODE',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 8,
                    color: Color(0xFF999999),
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          // ── Separator ────────────────────────────────────────────────
          Container(
            width: 1,
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFFCCCCCC),
          ),
          // ── Right: QR code ───────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Column(
              children: [
                QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  size: 72,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0D0D0D),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF0D0D0D),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'QR CODE',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 8,
                    color: Color(0xFF999999),
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Proper Code 128B barcode renderer — encodes ASCII 32–127.
/// Bars and spaces are drawn from the standard Code 128 symbol table
/// so the result is scannable by any real barcode reader.
class _Code128Barcode extends StatelessWidget {
  const _Code128Barcode({required this.data});
  final String data;

  // Code 128B symbol widths (11 modules each, guard patterns at start/end)
  // Each entry: 6 elements = bar,space,bar,space,bar,space widths in modules
  static const List<List<int>> _symbols = [
    [2,1,2,2,2,2],[2,2,2,1,2,2],[2,2,2,2,2,1],[1,2,1,2,2,3],[1,2,1,3,2,2], // 0–4
    [1,3,1,2,2,2],[1,2,2,2,1,3],[1,2,2,3,1,2],[1,3,2,2,1,2],[2,2,1,2,1,3], // 5–9
    [2,2,1,3,1,2],[2,3,1,2,1,2],[1,1,2,2,3,2],[1,2,2,1,3,2],[1,2,2,2,3,1], // 10–14
    [1,1,3,2,2,2],[1,2,3,1,2,2],[1,2,3,2,2,1],[2,2,3,2,1,1],[2,2,1,1,3,2], // 15–19
    [2,2,1,2,3,1],[2,1,3,2,1,2],[2,2,3,1,1,2],[3,1,2,1,3,1],[3,1,1,2,2,2], // 20–24
    [3,2,1,1,2,2],[3,2,1,2,2,1],[3,1,2,2,1,2],[3,2,2,1,1,2],[3,2,2,2,1,1], // 25–29
    [2,1,2,1,2,3],[2,1,2,3,2,1],[2,3,2,1,2,1],[1,1,1,3,2,3],[1,3,1,1,2,3], // 30–34
    [1,3,1,3,2,1],[1,1,2,3,1,3],[1,3,2,1,1,3],[2,1,1,3,1,3],[1,1,3,1,2,3], // 35–39
    [1,1,3,3,2,1],[1,3,3,1,2,1],[2,1,3,1,1,3],[2,3,1,1,1,3],[2,3,1,3,1,1], // 40–44
    [1,1,2,1,3,3],[1,1,2,3,3,1],[1,3,2,1,3,1],[1,1,3,1,3,2],[1,1,3,2,3,1], // 45–49
    [1,3,3,1,1,2],[1,3,1,2,1,3],[1,2,2,1,1,3],[1,2,2,3,1,1],[1,3,2,3,1,1], // 50–54
    [2,1,1,1,2,3],[2,1,1,3,2,1],[2,3,1,1,2,1],[1,1,1,1,3,3],[1,1,1,3,3,1], // 55–59
    [1,1,3,1,1,3],[1,3,1,1,1,3],[1,3,1,3,1,1],[2,1,1,1,3,2],[2,1,3,1,1,2], // 60–64
    [2,1,1,2,1,3],[2,1,1,3,1,2],[3,1,1,1,1,3],[3,1,1,3,1,1],[3,3,1,1,1,1], // 65–69
    [2,2,1,4,1,1],[4,3,1,1,1,1],[1,1,1,2,4,2],[1,2,1,1,4,2],[1,2,1,2,4,1], // 70–74
    [1,1,4,2,1,2],[1,2,4,1,1,2],[1,2,4,2,1,1],[4,1,1,2,1,2],[4,2,1,1,1,2], // 75–79
    [4,2,1,2,1,1],[2,1,4,1,1,2],[2,1,1,4,1,2],[4,1,1,1,1,2],[4,1,1,2,1,1], // 80–84  (value 84 = 'T')
    [1,1,1,4,2,2],[1,1,2,4,2,1],[1,2,1,4,2,1],[1,1,4,2,2,1],[1,2,4,1,2,1], // 85–89
    [1,2,4,2,2,0],[4,1,2,1,1,2],[4,1,2,2,1,1],[4,2,2,1,1,1],[2,1,2,1,4,1], // 90–94
    [2,1,4,1,2,1],[3,1,2,1,1,2],[3,1,1,2,1,2],[3,1,1,2,1,2],[3,2,1,1,1,2], // 95–99
    [3,2,1,2,1,1],[2,1,1,2,3,2],[2,1,3,2,1,2],[2,3,1,2,1,1],[2,1,2,2,1,1], // 100–104
  ];

  // Code 128B start symbol (value 104), stop pattern
  static const List<int> _start = [2,1,1,4,1,2];
  static const List<int> _stop  = [2,3,3,1,1,1,2]; // 7 elements for stop+terminator

  List<bool> _encode(String s) {
    final bits = <bool>[];

    void addSymbol(List<int> widths) {
      bool bar = true; // starts with bar
      for (final w in widths) {
        for (int i = 0; i < w; i++) bits.add(bar);
        bar = !bar;
      }
    }

    // Start B
    addSymbol(_start);

    int checksum = 104; // start B value
    int pos = 1;
    for (final ch in s.runes) {
      final idx = ch - 32; // Code 128B: space=0 … ~=94, delete=95
      if (idx < 0 || idx >= _symbols.length) continue;
      checksum += idx * pos;
      pos++;
      addSymbol(_symbols[idx]);
    }

    // Check character
    addSymbol(_symbols[checksum % 103]);

    // Stop
    bool bar = true;
    for (final w in _stop) {
      for (int i = 0; i < w; i++) bits.add(bar);
      bar = !bar;
    }

    return bits;
  }

  @override
  Widget build(BuildContext context) {
    // Limit encoded string length to keep receipt-width barcode readable
    final encoded = data.length > 20 ? data.substring(0, 20) : data;
    final bits = _encode(encoded);

    return LayoutBuilder(
      builder: (_, constraints) {
        final barW = constraints.maxWidth / bits.length;
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _Code128Painter(bits: bits, barWidth: barW),
        );
      },
    );
  }
}

class _Code128Painter extends CustomPainter {
  const _Code128Painter({required this.bits, required this.barWidth});
  final List<bool> bits;
  final double barWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final darkPaint = Paint()..color = const Color(0xFF0D0D0D);
    double x = 0;
    for (final isDark in bits) {
      if (isDark) {
        canvas.drawRect(Rect.fromLTWH(x, 0, barWidth, size.height), darkPaint);
      }
      x += barWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _Code128Painter old) =>
      old.bits != bits || old.barWidth != barWidth;
}

/// Torn paper edge — top or bottom.
class _TornEdge extends StatelessWidget {
  const _TornEdge({required this.top});
  final bool top;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(double.infinity, 18),
        painter: _TornEdgePainter(top: top),
      );
}

class _TornEdgePainter extends CustomPainter {
  const _TornEdgePainter({required this.top});
  final bool top;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFFAFAF8);
    final path = Path();
    final rng = math.Random(top ? 1 : 2);

    if (top) {
      path.moveTo(0, 18);
      double x = 0;
      while (x < size.width) {
        final w = 6 + rng.nextDouble() * 10;
        final h = 4 + rng.nextDouble() * 10;
        path.lineTo(x + w / 2, h);
        path.lineTo(x + w, 18);
        x += w;
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      double x = size.width;
      while (x > 0) {
        final w = 6 + rng.nextDouble() * 10;
        final h = 4 + rng.nextDouble() * 10;
        path.lineTo(x - w / 2, size.height - h);
        path.lineTo(x - w, 0);
        x -= w;
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
