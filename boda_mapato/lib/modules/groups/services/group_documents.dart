import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../constants/theme_constants.dart';
import '../../../utils/server_message.dart';
import '../models/group_loan_models.dart';
import '../models/group_models.dart';
import '../models/group_receipt_models.dart';
import '../screens/groups_text.dart';
import 'groups_api.dart';

/// The documents of the Groups (Vikundi) service: a receipt (with a QR code that checks it), a member's statement with what is still owed,
/// and a loan statement with its repayment schedule. Made on the phone from what the server sent, shared as PDF. Plain Latin text only (the
/// PDF's built-in font has no other letters).
class GroupDocuments {
  const GroupDocuments._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor _muted = PdfColor.fromInt(0xFF666666);
  static const PdfColor _line = PdfColor.fromInt(0xFFCCCCCC);

  static pw.Widget _row(final String label, final String value, {final bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
          pw.SizedBox(width: 130, child: pw.Text(label, style: const pw.TextStyle(color: _muted, fontSize: 10))),
          pw.Expanded(child: pw.Text(value, style: pw.TextStyle(color: _ink, fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        ]),
      );

  static pw.Widget _table(final List<String> head, final List<List<String>> rows, {final Map<int, pw.TableColumnWidth>? widths}) => pw.Table(
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line, width: 0.5)),
        columnWidths: widths,
        children: <pw.TableRow>[
          pw.TableRow(children: <pw.Widget>[for (final String h in head) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2), child: pw.Text(h, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)))]),
          for (final List<String> r in rows)
            pw.TableRow(children: <pw.Widget>[for (final String c in r) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2), child: pw.Text(c, style: const pw.TextStyle(fontSize: 9, color: _ink)))]),
        ],
      );

  static pw.Widget _title(final String group, final String title) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
        pw.Text(group, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 2),
        pw.Text(title, style: const pw.TextStyle(fontSize: 12, color: _muted)),
        pw.Divider(color: _line),
      ]);

  static String _date(final String? iso) => dateLabel(iso);

  /// A receipt: who gave it, its number, what was paid and how, who verified it, and the QR code that checks it.
  static Future<Uint8List> receipt(final GroupReceipt r, {required final bool sw}) async {
    final GroupTransaction t = r.transaction;
    final pw.Document doc = pw.Document(title: t.receiptNumber ?? 'Receipt');
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
        _title(r.group, sw ? 'RISITI' : 'RECEIPT'),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
              _row(sw ? 'Namba ya risiti' : 'Receipt number', t.receiptNumber ?? '-', bold: true),
              if (t.memberName != null) _row(sw ? 'Mwanachama' : 'Member', '${t.memberName}${t.memberNumber == null ? '' : ' (${t.memberNumber})'}'),
              if (t.payee != null) _row(sw ? 'Aliyelipwa' : 'Paid to', t.payee!),
              _row(sw ? 'Kuhusu' : 'For', t.obligationLabel ?? categoryLabel(sw: sw, category: t.category)),
              _row(sw ? 'Kiasi' : 'Amount', tsh(t.amount), bold: true),
              _row(sw ? 'Tarehe' : 'Date', _date(t.verifiedAt ?? t.paidOn)),
              _row(sw ? 'Njia ya malipo' : 'Payment method', methodLabel(sw: sw, method: t.method)),
              if (t.externalRef != null) _row(sw ? 'Namba ya muamala' : 'Transaction reference', t.externalRef!),
              _row(sw ? 'Hali' : 'Status', r.reversed ? (sw ? 'IMEREKEBISHWA' : 'REVERSED') : (sw ? 'Imethibitishwa' : 'Verified')),
              if (t.verifiedByName != null) _row(sw ? 'Aliyethibitisha' : 'Verified by', t.verifiedByName!),
            ]),
          ),
          pw.SizedBox(width: 12),
          pw.Column(children: <pw.Widget>[
            pw.SizedBox(width: 90, height: 90, child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: r.verifyUrl)),
            pw.SizedBox(height: 4),
            pw.SizedBox(width: 90, child: pw.Text(sw ? 'Changanua kuthibitisha risiti hii' : 'Scan to check this receipt', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7, color: _muted))),
          ]),
        ]),
        pw.Spacer(),
        pw.Text(sw ? 'Risiti hii imetolewa na mfumo baada ya malipo kuthibitishwa.' : 'Issued by the system once the payment was verified.', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ]),
    ));
    return doc.save();
  }

  /// A member's statement: balances, what is owed (contributions, and loans when [loans] are given), and every verified movement.
  static Future<Uint8List> statement(
    final GroupStatementData d, {
    required final bool sw,
    required final String group,
    required final String memberName,
    final List<GroupLoan> loans = const <GroupLoan>[],
  }) async {
    final List<GroupLoan> running = loans.where((final GroupLoan l) => l.status == 'active').toList();
    final double loansOwed = running.fold<double>(0, (final double s, final GroupLoan l) => s + (l.outstanding ?? 0));
    final pw.Document doc = pw.Document(title: sw ? 'Taarifa ya fedha' : 'Statement');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => <pw.Widget>[
        _title(group, '${sw ? 'Taarifa ya fedha' : 'Statement'} - $memberName'),
        pw.Text('${sw ? 'Imetolewa' : 'Printed'} ${_date(DateTime.now().toIso8601String())}', style: const pw.TextStyle(fontSize: 9, color: _muted)),
        pw.SizedBox(height: 10),
        pw.Text(sw ? 'Salio' : 'Balances', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        for (final MapEntry<String, double> b in d.balances.entries) _row(categoryLabel(sw: sw, category: b.key), tsh(b.value)),
        pw.SizedBox(height: 10),
        pw.Text(sw ? 'Madeni yote' : 'Everything owed', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        _row(sw ? 'Michango' : 'Contributions', tsh(d.owingTotal)),
        if (loans.isNotEmpty) _row(sw ? 'Mikopo' : 'Loans', tsh(loansOwed)),
        _row(sw ? 'Jumla' : 'Total', tsh(d.owingTotal + loansOwed), bold: true),
        if (d.owing.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 6),
          _table(
            <String>[sw ? 'Mchango' : 'Contribution', sw ? 'Mwisho' : 'Due', sw ? 'Imebaki' : 'Left'],
            <List<String>>[for (final GroupObligation o in d.owing) <String>[o.title, _date(o.dueDate), tsh(o.remaining)]],
          ),
        ],
        if (running.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 6),
          _table(
            <String>[sw ? 'Mkopo' : 'Loan', sw ? 'Msingi uliobaki' : 'Principal left', sw ? 'Riba iliyobaki' : 'Interest left', sw ? 'Imepita muda' : 'Overdue', sw ? 'Jumla' : 'Total'],
            <List<String>>[
              for (final GroupLoan l in running) <String>[l.reference, tsh(l.outstandingPrincipal), tsh(l.outstandingInterest), tsh(l.arrears ?? 0), tsh(l.outstanding ?? 0)],
            ],
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Text(sw ? 'Malipo yaliyothibitishwa' : 'Verified payments', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        if (d.lines.isEmpty)
          pw.Text(sw ? 'Bado hakuna.' : 'None yet.', style: const pw.TextStyle(fontSize: 10, color: _muted))
        else
          _table(
            <String>[sw ? 'Tarehe' : 'Date', sw ? 'Kuhusu' : 'For', sw ? 'Risiti' : 'Receipt', sw ? 'Kiasi' : 'Amount', sw ? 'Salio' : 'Balance'],
            <List<String>>[
              for (final GroupTransaction t in d.lines)
                <String>[
                  _date(t.paidOn),
                  '${t.isReversal ? (sw ? 'Marekebisho: ' : 'Reversal: ') : ''}${t.obligationLabel ?? categoryLabel(sw: sw, category: t.category)}',
                  t.receiptNumber ?? '',
                  tsh(t.signedAmount),
                  d.balanceAfter[t.id] == null ? '' : tsh(d.balanceAfter[t.id]!),
                ],
            ],
            widths: <int, pw.TableColumnWidth>{0: const pw.FixedColumnWidth(60), 2: const pw.FixedColumnWidth(60), 3: const pw.FixedColumnWidth(80), 4: const pw.FixedColumnWidth(80)},
          ),
      ],
    ));
    return doc.save();
  }

  /// One loan: its terms and where it stands, and the repayment schedule.
  static Future<Uint8List> loanStatement(final GroupLoan l, {required final bool sw, required final String group}) async {
    final pw.Document doc = pw.Document(title: l.reference);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => <pw.Widget>[
        _title(group, '${sw ? 'Taarifa ya mkopo' : 'Loan statement'} ${l.reference}'),
        _row(sw ? 'Mwanachama' : 'Member', l.memberName ?? '-', bold: true),
        _row(sw ? 'Kiasi kilichokubaliwa' : 'Agreed amount', tsh(l.amountApproved ?? l.amountRequested)),
        _row(sw ? 'Muda' : 'Term', '${l.termMonths} ${sw ? 'miezi' : 'month(s)'}'),
        _row(sw ? 'Riba' : 'Interest', '${l.interestRate}% ${sw ? 'kwa mwezi' : 'a month'} - ${interestMethodLabel(sw: sw, method: l.interestMethod)}'),
        if (l.disbursedOn != null) _row(sw ? 'Kilitolewa' : 'Paid out on', _date(l.disbursedOn)),
        _row(sw ? 'Matumizi' : 'Purpose', l.purpose),
        pw.SizedBox(height: 8),
        pw.Text(sw ? 'Hali ya mkopo' : 'Where it stands', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        _row(sw ? 'Msingi uliolipwa' : 'Principal repaid', tsh(l.principalPaid)),
        _row(sw ? 'Riba iliyolipwa' : 'Interest paid', tsh(l.interestPaid)),
        _row(sw ? 'Msingi uliobaki' : 'Principal left', tsh(l.outstandingPrincipal)),
        _row(sw ? 'Riba iliyobaki' : 'Interest left', tsh(l.outstandingInterest)),
        if ((l.arrears ?? 0) > 0) _row(sw ? 'Imepita muda' : 'Overdue', tsh(l.arrears!)),
        if (l.nextDue != null) _row(sw ? 'Rejesho lijalo' : 'Next instalment', '${tsh(l.nextAmount ?? 0)} - ${_date(l.nextDue)}'),
        _row(sw ? 'Deni lote' : 'Total still owed', tsh(l.outstanding ?? 0), bold: true),
        if (l.instalments.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 12),
          pw.Text(sw ? 'Ratiba ya marejesho' : 'Repayment schedule', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          _table(
            <String>['#', sw ? 'Tarehe' : 'Due', sw ? 'Msingi' : 'Principal', sw ? 'Riba' : 'Interest', sw ? 'Jumla' : 'Total', sw ? 'Imelipwa' : 'Paid', sw ? 'Hali' : 'State'],
            <List<String>>[
              for (final GroupInstalment i in l.instalments)
                <String>['${i.number}', _date(i.dueDate), tsh(i.principalDue), tsh(i.interestDue), tsh(i.total), tsh(i.paid), i.state == null ? '' : obligationStateLabel(sw: sw, state: i.state!)],
            ],
            widths: <int, pw.TableColumnWidth>{0: const pw.FixedColumnWidth(24)},
          ),
        ],
      ],
    ));
    return doc.save();
  }

  /// Opens the phone's share sheet with the PDF.
  static Future<void> share(final Uint8List bytes, final String filename) => Printing.sharePdf(bytes: bytes, filename: filename);

  /// Fetches the receipt of payment [id], makes the PDF and shares it; says why when it cannot.
  static Future<void> shareReceipt(final BuildContext context, final GroupsApi api, final int id, {required final bool sw}) async {
    try {
      final GroupReceipt r = await api.receipt(id);
      final Uint8List bytes = await receipt(r, sw: sw);
      await share(bytes, '${r.transaction.receiptNumber ?? 'receipt'}.pdf');
    } on Exception catch (e) {
      if (context.mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }
}
