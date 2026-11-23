import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../constants/theme_constants.dart';
import '../../../utils/server_message.dart';
import '../models/group_loan_models.dart';
import '../models/group_models.dart';
import '../models/group_receipt_models.dart';
import '../models/group_records_models.dart';
import '../models/group_voting_models.dart';
import '../screens/groups_text.dart';
import '../screens/widgets/groups_ui.dart';
import 'docx_writer.dart';
import 'group_doc.dart';
import 'groups_api.dart';

/// The documents of the Groups (Vikundi) service: a receipt (with a QR code that checks it), a member's statement with what is still owed,
/// a loan statement with its repayment schedule, the group's report and the voting report. Each is described once as a [GroupDoc] from what
/// the server sent, then made on the phone as a PDF, a picture (when it fits one page) or a Word file, and shared. PDF text is plain Latin
/// (its built-in font has no other letters); the Word file keeps every letter.
class GroupDocuments {
  const GroupDocuments._();

  static const PdfColor _ink = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor _muted = PdfColor.fromInt(0xFF666666);
  static const PdfColor _line = PdfColor.fromInt(0xFFCCCCCC);

  static String _date(final String? iso) => dateLabel(iso);

  // ------------------------------------------------------------------------------------------------ the documents, as content

  /// A receipt: who gave it, its number, what was paid and how, who verified it, and the QR code that checks it.
  static GroupDoc receiptDoc(final GroupReceipt r, {required final bool sw}) {
    final GroupTransaction t = r.transaction;
    return GroupDoc(
      group: r.group,
      title: sw ? 'RISITI' : 'RECEIPT',
      small: true,
      fileName: t.receiptNumber ?? 'receipt',
      blocks: <DocBlock>[
        DocRows(<DocRow>[
          DocRow(sw ? 'Namba ya risiti' : 'Receipt number', t.receiptNumber ?? '-', bold: true),
          if (t.memberName != null) DocRow(sw ? 'Mwanachama' : 'Member', '${t.memberName}${t.memberNumber == null ? '' : ' (${t.memberNumber})'}'),
          if (t.payee != null) DocRow(sw ? 'Aliyelipwa' : 'Paid to', t.payee!),
          DocRow(sw ? 'Kuhusu' : 'For', t.obligationLabel ?? categoryLabel(sw: sw, category: t.category)),
          DocRow(sw ? 'Kiasi' : 'Amount', tsh(t.amount), bold: true),
          DocRow(sw ? 'Tarehe' : 'Date', _date(t.verifiedAt ?? t.paidOn)),
          DocRow(sw ? 'Njia ya malipo' : 'Payment method', methodLabel(sw: sw, method: t.method)),
          if (t.externalRef != null) DocRow(sw ? 'Namba ya muamala' : 'Transaction reference', t.externalRef!),
          DocRow(sw ? 'Hali' : 'Status', r.reversed ? (sw ? 'IMEREKEBISHWA' : 'REVERSED') : (sw ? 'Imethibitishwa' : 'Verified')),
          if (t.verifiedByName != null) DocRow(sw ? 'Aliyethibitisha' : 'Verified by', t.verifiedByName!),
        ]),
        DocQr(r.verifyUrl, sw ? 'Changanua kuthibitisha risiti hii' : 'Scan to check this receipt'),
        DocNote(sw ? 'Risiti hii imetolewa na mfumo baada ya malipo kuthibitishwa.' : 'Issued by the system once the payment was verified.'),
      ],
    );
  }

  /// A member's statement: balances, what is owed (contributions, and loans when [loans] are given), and every verified movement.
  static GroupDoc statementDoc(
    final GroupStatementData d, {
    required final bool sw,
    required final String group,
    required final String memberName,
    final List<GroupLoan> loans = const <GroupLoan>[],
  }) {
    final List<GroupLoan> running = loans.where((final GroupLoan l) => l.status == 'active').toList();
    final double loansOwed = running.fold<double>(0, (final double s, final GroupLoan l) => s + (l.outstanding ?? 0));
    return GroupDoc(
      group: group,
      title: '${sw ? 'Taarifa ya fedha' : 'Statement'} - $memberName',
      fileName: 'statement',
      blocks: <DocBlock>[
        DocNote('${sw ? 'Imetolewa' : 'Printed'} ${_date(DateTime.now().toIso8601String())}'),
        DocHeading(sw ? 'Salio' : 'Balances'),
        DocRows(<DocRow>[for (final MapEntry<String, double> b in d.balances.entries) DocRow(categoryLabel(sw: sw, category: b.key), tsh(b.value))]),
        DocHeading(sw ? 'Madeni yote' : 'Everything owed'),
        DocRows(<DocRow>[
          DocRow(sw ? 'Michango' : 'Contributions', tsh(d.owingTotal)),
          if (loans.isNotEmpty) DocRow(sw ? 'Mikopo' : 'Loans', tsh(loansOwed)),
          DocRow(sw ? 'Jumla' : 'Total', tsh(d.owingTotal + loansOwed), bold: true),
        ]),
        if (d.owing.isNotEmpty)
          DocTable(
            <String>[sw ? 'Mchango' : 'Contribution', sw ? 'Mwisho' : 'Due', sw ? 'Imebaki' : 'Left'],
            <List<String>>[for (final GroupObligation o in d.owing) <String>[o.title, _date(o.dueDate), tsh(o.remaining)]],
          ),
        if (running.isNotEmpty)
          DocTable(
            <String>[sw ? 'Mkopo' : 'Loan', sw ? 'Msingi uliobaki' : 'Principal left', sw ? 'Riba iliyobaki' : 'Interest left', sw ? 'Imepita muda' : 'Overdue', sw ? 'Jumla' : 'Total'],
            <List<String>>[for (final GroupLoan l in running) <String>[l.reference, tsh(l.outstandingPrincipal), tsh(l.outstandingInterest), tsh(l.arrears ?? 0), tsh(l.outstanding ?? 0)]],
          ),
        DocHeading(sw ? 'Malipo yaliyothibitishwa' : 'Verified payments'),
        if (d.lines.isEmpty)
          DocNote(sw ? 'Bado hakuna.' : 'None yet.')
        else
          DocTable(
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
            widths: <int, double>{0: 60, 2: 60, 3: 80, 4: 80},
          ),
      ],
    );
  }

  /// One loan: its terms and where it stands, and the repayment schedule.
  static GroupDoc loanDoc(final GroupLoan l, {required final bool sw, required final String group}) => GroupDoc(
        group: group,
        title: '${sw ? 'Taarifa ya mkopo' : 'Loan statement'} ${l.reference}',
        fileName: l.reference,
        blocks: <DocBlock>[
          DocRows(<DocRow>[
            DocRow(sw ? 'Mwanachama' : 'Member', l.memberName ?? '-', bold: true),
            DocRow(sw ? 'Kiasi kilichokubaliwa' : 'Agreed amount', tsh(l.amountApproved ?? l.amountRequested)),
            DocRow(sw ? 'Muda' : 'Term', '${l.termMonths} ${sw ? 'miezi' : 'month(s)'}'),
            DocRow(sw ? 'Riba' : 'Interest', '${l.interestRate}% ${sw ? 'kwa mwezi' : 'a month'} - ${interestMethodLabel(sw: sw, method: l.interestMethod)}'),
            if (l.disbursedOn != null) DocRow(sw ? 'Kilitolewa' : 'Paid out on', _date(l.disbursedOn)),
            DocRow(sw ? 'Matumizi' : 'Purpose', l.purpose),
          ]),
          DocHeading(sw ? 'Hali ya mkopo' : 'Where it stands'),
          DocRows(<DocRow>[
            DocRow(sw ? 'Msingi uliolipwa' : 'Principal repaid', tsh(l.principalPaid)),
            DocRow(sw ? 'Riba iliyolipwa' : 'Interest paid', tsh(l.interestPaid)),
            DocRow(sw ? 'Msingi uliobaki' : 'Principal left', tsh(l.outstandingPrincipal)),
            DocRow(sw ? 'Riba iliyobaki' : 'Interest left', tsh(l.outstandingInterest)),
            if ((l.arrears ?? 0) > 0) DocRow(sw ? 'Imepita muda' : 'Overdue', tsh(l.arrears!)),
            if (l.nextDue != null) DocRow(sw ? 'Rejesho lijalo' : 'Next instalment', '${tsh(l.nextAmount ?? 0)} - ${_date(l.nextDue)}'),
            DocRow(sw ? 'Deni lote' : 'Total still owed', tsh(l.outstanding ?? 0), bold: true),
          ]),
          if (l.instalments.isNotEmpty) ...<DocBlock>[
            DocHeading(sw ? 'Ratiba ya marejesho' : 'Repayment schedule'),
            DocTable(
              <String>['#', sw ? 'Tarehe' : 'Due', sw ? 'Msingi' : 'Principal', sw ? 'Riba' : 'Interest', sw ? 'Jumla' : 'Total', sw ? 'Imelipwa' : 'Paid', sw ? 'Hali' : 'State'],
              <List<String>>[
                for (final GroupInstalment i in l.instalments)
                  <String>['${i.number}', _date(i.dueDate), tsh(i.principalDue), tsh(i.interestDue), tsh(i.total), tsh(i.paid), i.state == null ? '' : obligationStateLabel(sw: sw, state: i.state!)],
              ],
              widths: <int, double>{0: 24},
            ),
          ],
        ],
      );

  /// The group's report for a period: members, verified money, contributions and loans.
  static GroupDoc reportDoc(final GroupReport r, {required final bool sw, required final String group, required final String from, required final String to}) => GroupDoc(
        group: group,
        title: '${sw ? 'Ripoti ya kikundi' : 'Group report'} ${_date(from)} - ${_date(to)}',
        fileName: 'ripoti_${from}_$to',
        blocks: <DocBlock>[
          DocHeading(sw ? 'Wanachama' : 'Members'),
          DocRows(<DocRow>[
            for (final MapEntry<String, int> e in r.byStatus.entries)
              if (e.value > 0) DocRow(statusLabel(sw: sw, status: e.key), '${e.value}'),
            DocRow(sw ? 'Waliojiunga katika kipindi' : 'Joined in the period', '${r.joined}'),
            DocRow(sw ? 'Vikao vilivyofanyika' : 'Meetings held', '${r.meetingsHeld}'),
          ]),
          DocHeading(sw ? 'Fedha (zilizothibitishwa)' : 'Money (verified)'),
          if (r.money.isEmpty)
            DocNote(sw ? 'Hakuna katika kipindi hiki.' : 'Nothing in this period.')
          else
            DocTable(
              <String>[sw ? 'Aina' : 'Kind', sw ? 'Imeingia' : 'In', sw ? 'Imetoka' : 'Out'],
              <List<String>>[for (final MapEntry<String, (double, double)> e in r.money.entries) <String>[categoryLabel(sw: sw, category: e.key), tsh(e.value.$1), tsh(e.value.$2)]],
            ),
          DocHeading(sw ? 'Michango' : 'Contributions'),
          DocRows(<DocRow>[
            DocRow(sw ? 'Iliyotarajiwa' : 'Expected', tsh(r.contributions['expected'] ?? 0)),
            DocRow(sw ? 'Iliyolipwa' : 'Collected', tsh(r.contributions['collected'] ?? 0)),
            DocRow(sw ? 'Iliyopita muda (sasa)' : 'Overdue (now)', '${tsh(r.contributions['overdue_now'] ?? 0)} - ${(r.contributions['overdue_members'] ?? 0).toStringAsFixed(0)} ${sw ? 'wanachama' : 'members'}'),
          ]),
          DocHeading(sw ? 'Mikopo (sasa)' : 'Loans (now)'),
          DocRows(<DocRow>[
            DocRow(sw ? 'Msingi unaodaiwa' : 'Principal owed', tsh(r.loans['principal'] ?? 0)),
            DocRow(sw ? 'Riba inayodaiwa' : 'Interest owed', tsh(r.loans['interest'] ?? 0)),
            DocRow(sw ? 'Imepita muda' : 'Overdue', tsh(r.loans['arrears'] ?? 0)),
          ]),
          DocNote('${sw ? 'Imetolewa' : 'Printed'} ${_date(DateTime.now().toIso8601String())}'),
        ],
      );

  /// The report of one voting: the decision, the results, who has taken part (never what a secret ballot chose).
  static GroupDoc votingDoc(final VotingReport r, {required final bool sw, required final String group, required final String decisionLabel}) {
    String person(final Map<String, dynamic> t) => '${t['name']}${'${t['member_number'] ?? ''}'.isEmpty ? '' : ' (${t['member_number']})'}';
    return GroupDoc(
      group: group,
      title: '${sw ? 'Ripoti ya kura' : 'Voting report'} - ${r.voting.target}',
      fileName: 'kura_${r.voting.reference}',
      blocks: <DocBlock>[
        DocRows(<DocRow>[
          DocRow(sw ? 'Kura' : 'Voting', r.voting.reference),
          DocRow(sw ? 'Uamuzi' : 'Decision', decisionLabel, bold: true),
          DocRow(sw ? 'Hali' : 'Standing', r.isFinal ? (sw ? 'Ya mwisho' : 'Final') : (sw ? 'Bado inaendelea' : 'Still running')),
          DocRow(sw ? 'Waliopiga kura' : 'Turnout', '${r.results.turnout} / ${r.results.eligible} (${r.results.participationPercent.toStringAsFixed(1)}%)'),
          DocRow(sw ? 'Akidi' : 'Quorum', '${r.results.quorumPercent.toStringAsFixed(0)}% - ${r.results.quorumMet ? (sw ? 'imefikiwa' : 'met') : (sw ? 'haijafikiwa' : 'not met')}'),
        ]),
        DocHeading(sw ? 'Matokeo' : 'Results'),
        DocTable(
          <String>[sw ? 'Chaguo' : 'Option', sw ? 'Kura' : 'Votes', '%'],
          <List<String>>[for (final VotingResultRow o in r.results.options) <String>[o.label, '${o.votes}', o.percent.toStringAsFixed(1)]],
        ),
        DocHeading(sw ? 'Waliopiga kura (${r.turnout.length})' : 'Who has voted (${r.turnout.length})'),
        if (r.turnout.isEmpty) DocNote(sw ? 'Bado hakuna.' : 'Nobody yet.') else DocTable(<String>[sw ? 'Jina' : 'Name', sw ? 'Tarehe' : 'Date'], <List<String>>[for (final Map<String, dynamic> t in r.turnout) <String>[person(t), '${t['date'] ?? ''}']]),
        DocHeading(sw ? 'Hawajapiga kura (${r.notVoted.length})' : 'Not yet voted (${r.notVoted.length})'),
        if (r.notVoted.isEmpty) DocNote(sw ? 'Wote wameshiriki.' : 'Everyone has taken part.') else DocTable(<String>[sw ? 'Jina' : 'Name'], <List<String>>[for (final Map<String, dynamic> t in r.notVoted) <String>[person(t)]]),
        if (r.secret)
          DocNote(sw ? 'Kura ya siri: ulichochagua kila mtu hakirekodiwi kamwe.' : 'Secret ballot: what each person chose is never recorded.')
        else if (r.individual != null) ...<DocBlock>[
          DocHeading(sw ? 'Kura za mmoja mmoja' : 'Individual votes'),
          DocTable(<String>[sw ? 'Jina' : 'Name', sw ? 'Chaguo' : 'Choice'], <List<String>>[for (final Map<String, dynamic> i in r.individual!) <String>[person(i), '${i['option'] ?? ''}']]),
        ],
      ],
    );
  }

  /// A CSV from the server (a member register, a period's payments) as a table, so it too can be a PDF or a Word file.
  static GroupDoc csvDoc(final Uint8List csv, {required final String group, required final String title, required final String fileName}) {
    final List<List<String>> rows = parseCsv(String.fromCharCodes(csv.length >= 3 && csv[0] == 0xEF && csv[1] == 0xBB && csv[2] == 0xBF ? csv.sublist(3) : csv));
    final List<String> head = rows.isEmpty ? const <String>[] : rows.first;
    return GroupDoc(
      group: group,
      title: title,
      wide: true,
      fileName: fileName,
      blocks: <DocBlock>[if (head.isNotEmpty) DocTable(head, <List<String>>[for (final List<String> r in rows.skip(1)) <String>[for (int i = 0; i < head.length; i++) i < r.length ? r[i] : '']])],
    );
  }

  /// A small CSV reader: commas, quotes with doubled quotes inside, and line breaks inside quotes.
  static List<List<String>> parseCsv(final String text) {
    final List<List<String>> rows = <List<String>>[];
    List<String> row = <String>[];
    final StringBuffer cell = StringBuffer();
    bool quoted = false;
    bool any = false;
    void endCell() {
      row.add(cell.toString());
      cell.clear();
    }

    void endRow() {
      endCell();
      if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
      row = <String>[];
      any = false;
    }

    for (int i = 0; i < text.length; i++) {
      final String c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
        any = true;
      } else if (c == ',') {
        endCell();
        any = true;
      } else if (c == '\n') {
        endRow();
      } else if (c != '\r') {
        cell.write(c);
        any = true;
      }
    }
    if (any || cell.isNotEmpty) endRow();
    return rows;
  }

  // ------------------------------------------------------------------------------------------------ making the files

  static pw.Widget _row(final DocRow r) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
          pw.SizedBox(width: 130, child: pw.Text(r.label, style: const pw.TextStyle(color: _muted, fontSize: 10))),
          pw.Expanded(child: pw.Text(r.value, style: pw.TextStyle(color: _ink, fontSize: 11, fontWeight: r.bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        ]),
      );

  static pw.Widget _table(final DocTable t) => pw.Table(
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5), bottom: pw.BorderSide(color: _line, width: 0.5)),
        columnWidths: <int, pw.TableColumnWidth>{if (t.widths != null) for (final MapEntry<int, double> w in t.widths!.entries) w.key: pw.FixedColumnWidth(w.value)},
        children: <pw.TableRow>[
          pw.TableRow(children: <pw.Widget>[for (final String h in t.head) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2), child: pw.Text(h, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)))]),
          for (final List<String> r in t.rows)
            pw.TableRow(children: <pw.Widget>[for (final String c in r) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2), child: pw.Text(c, style: const pw.TextStyle(fontSize: 9, color: _ink)))]),
        ],
      );

  static pw.Widget _block(final DocBlock b) {
    switch (b) {
      case DocHeading():
        return pw.Padding(padding: const pw.EdgeInsets.only(top: 12, bottom: 4), child: pw.Text(b.text, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)));
      case DocRows():
        return pw.Column(children: <pw.Widget>[for (final DocRow r in b.rows) _row(r)]);
      case DocTable():
        return pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: _table(b));
      case DocNote():
        return pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text(b.text, style: const pw.TextStyle(fontSize: 8, color: _muted)));
      case DocQr():
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(children: <pw.Widget>[
            pw.SizedBox(width: 90, height: 90, child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: b.data)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: pw.Text(b.caption, style: const pw.TextStyle(fontSize: 8, color: _muted))),
          ]),
        );
    }
  }

  /// The PDF of [d] (several pages when it is long).
  static Future<Uint8List> pdf(final GroupDoc d) async {
    final pw.Document doc = pw.Document(title: d.title);
    doc.addPage(pw.MultiPage(
      pageFormat: d.small ? PdfPageFormat.a5 : (d.wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4),
      margin: pw.EdgeInsets.all(d.small ? 28 : 32),
      build: (_) => <pw.Widget>[
        pw.Text(d.group, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 2),
        pw.Text(d.title, style: const pw.TextStyle(fontSize: 12, color: _muted)),
        pw.Divider(color: _line),
        for (final DocBlock b in d.blocks) _block(b),
      ],
    ));
    return doc.save();
  }

  /// The Word file of [d].
  static Uint8List docx(final GroupDoc d) => DocxWriter.build(d);

  // The documents as PDF, kept for the screens and tests that already call them.
  static Future<Uint8List> receipt(final GroupReceipt r, {required final bool sw}) => pdf(receiptDoc(r, sw: sw));

  static Future<Uint8List> statement(
    final GroupStatementData d, {
    required final bool sw,
    required final String group,
    required final String memberName,
    final List<GroupLoan> loans = const <GroupLoan>[],
  }) =>
      pdf(statementDoc(d, sw: sw, group: group, memberName: memberName, loans: loans));

  static Future<Uint8List> loanStatement(final GroupLoan l, {required final bool sw, required final String group}) => pdf(loanDoc(l, sw: sw, group: group));

  // ------------------------------------------------------------------------------------------------ sharing

  /// Opens the phone's share sheet with the PDF.
  static Future<void> share(final Uint8List bytes, final String filename) => Printing.sharePdf(bytes: bytes, filename: filename);

  static Future<void> _shareFile(final Uint8List bytes, final String name, final String mime) async {
    final Directory dir = await getTemporaryDirectory();
    final File file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(<XFile>[XFile(file.path, mimeType: mime)], subject: name);
  }

  /// Makes the pages of a PDF into pictures (the phone's own renderer); tests put a stand-in here.
  @visibleForTesting
  static Future<List<Uint8List>> Function(Uint8List pdfBytes) pictureMaker = _pictures;

  /// The pages of [pdfBytes] as pictures; empty when this phone cannot make them.
  static Future<List<Uint8List>> _pictures(final Uint8List pdfBytes) async {
    try {
      final List<Uint8List> out = <Uint8List>[];
      await for (final PdfRaster page in Printing.raster(pdfBytes, dpi: 150)) {
        out.add(await page.toPng());
      }
      return out;
    } on Object {
      return const <Uint8List>[];
    }
  }

  /// Asks which form to share [d] in: PDF; a picture, only when the document fits one page; or Word. [csv] adds the spreadsheet form.
  static Future<void> shareDoc(final BuildContext context, final GroupDoc d, {required final bool sw, final Uint8List? csv}) async {
    try {
      final Uint8List bytes = await pdf(d);
      final List<Uint8List> pictures = await pictureMaker(bytes);
      if (!context.mounted) return;
      final String? picked = await groupActions(
        context,
        title: sw ? 'Tuma ripoti kama' : 'Share as',
        actions: <GroupSheetAction>[
          GroupSheetAction(icon: Icons.picture_as_pdf_rounded, label: 'PDF', value: 'pdf'),
          if (pictures.length == 1) GroupSheetAction(icon: Icons.image_rounded, label: sw ? 'Picha (ukurasa mmoja)' : 'Picture (one page)', value: 'image'),
          GroupSheetAction(icon: Icons.description_rounded, label: sw ? 'Word (.docx)' : 'Word (.docx)', value: 'docx'),
          if (csv != null) GroupSheetAction(icon: Icons.table_view_rounded, label: sw ? 'Jedwali (CSV)' : 'Spreadsheet (CSV)', value: 'csv'),
        ],
      );
      switch (picked) {
        case 'pdf':
          await share(bytes, '${d.fileName}.pdf');
        case 'image':
          await _shareFile(pictures.first, '${d.fileName}.png', 'image/png');
        case 'docx':
          await _shareFile(docx(d), '${d.fileName}.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
        case 'csv':
          await _shareFile(csv!, '${d.fileName}.csv', 'text/csv');
      }
    } on Exception catch (e) {
      if (context.mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  /// A Tanzanian number in international form for WhatsApp (0754 100 200 -> 255754100200).
  static String internationalPhone(final String phone) {
    final String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) return '255${digits.substring(1)}';
    return digits;
  }

  /// The words that go with a receipt when it is sent to the member.
  static String receiptMessage(final GroupReceipt r, {required final bool sw}) {
    final GroupTransaction t = r.transaction;
    final String what = t.obligationLabel ?? categoryLabel(sw: sw, category: t.category);
    return sw
        ? 'Risiti ${t.receiptNumber ?? ''} - ${r.group}: ${tsh(t.amount)} imepokelewa (${what}) tarehe ${_date(t.verifiedAt ?? t.paidOn)}. Thibitisha risiti: ${r.verifyUrl}'
        : 'Receipt ${t.receiptNumber ?? ''} - ${r.group}: ${tsh(t.amount)} received ($what) on ${_date(t.verifiedAt ?? t.paidOn)}. Check the receipt: ${r.verifyUrl}';
  }

  /// Send a receipt to the member: a text message or WhatsApp to their number (their own apps open with the words ready), or the file in
  /// any form (PDF, picture, Word) through the share sheet.
  static Future<void> sendReceipt(final BuildContext context, final GroupReceipt r, {required final bool sw}) async {
    final String? phone = r.memberPhone == null || r.memberPhone!.trim().isEmpty ? null : r.memberPhone!.trim();
    final String message = receiptMessage(r, sw: sw);
    final String? picked = await groupActions(
      context,
      title: sw ? 'Tuma risiti ${r.transaction.receiptNumber ?? ''}${r.transaction.memberName == null ? '' : ' kwa ${r.transaction.memberName}'}' : 'Send receipt ${r.transaction.receiptNumber ?? ''}${r.transaction.memberName == null ? '' : ' to ${r.transaction.memberName}'}',
      actions: <GroupSheetAction>[
        if (phone != null) GroupSheetAction(icon: Icons.sms_rounded, label: sw ? 'Ujumbe mfupi (SMS) kwa $phone' : 'Text message (SMS) to $phone', value: 'sms'),
        if (phone != null) GroupSheetAction(icon: Icons.chat_rounded, label: 'WhatsApp $phone', value: 'whatsapp'),
        GroupSheetAction(icon: Icons.attach_file_rounded, label: sw ? 'Faili: PDF, picha au Word' : 'File: PDF, picture or Word', value: 'file'),
      ],
    );
    if (picked == null || !context.mounted) return;
    try {
      switch (picked) {
        case 'sms':
          await launchUrl(Uri.parse('sms:$phone?body=${Uri.encodeComponent(message)}'));
        case 'whatsapp':
          await launchUrl(Uri.parse('https://wa.me/${internationalPhone(phone!)}?text=${Uri.encodeComponent(message)}'), mode: LaunchMode.externalApplication);
        case 'file':
          await shareDoc(context, receiptDoc(r, sw: sw), sw: sw);
      }
    } on Exception catch (e) {
      if (context.mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  /// Fetches the receipt of payment [id] and offers to send or share it; says why when it cannot.
  static Future<void> shareReceipt(final BuildContext context, final GroupsApi api, final int id, {required final bool sw}) async {
    try {
      final GroupReceipt r = await api.receipt(id);
      if (!context.mounted) return;
      await sendReceipt(context, r, sw: sw);
    } on Exception catch (e) {
      if (context.mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }
}
