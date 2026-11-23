import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_receipt_models.dart';
import 'package:boda_mapato/modules/groups/models/group_records_models.dart';
import 'package:boda_mapato/modules/groups/screens/records_screens.dart';
import 'package:boda_mapato/modules/groups/screens/statement_screen.dart';
import 'package:boda_mapato/modules/groups/services/group_doc.dart';
import 'package:boda_mapato/modules/groups/services/group_documents.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

GroupReceipt _receipt({final String? phone = '0754 100 200', final String group = 'MEG Group'}) => GroupReceipt.fromJson(<String, dynamic>{
      'transaction': <String, dynamic>{
        'id': 1,
        'reference': 'TRX-1',
        'receipt_number': 'RC-000001',
        'category': 'savings',
        'direction': 'in',
        'amount': 50000,
        'method': 'mpesa',
        'external_ref': 'MP123',
        'paid_on': '2026-11-20',
        'status': 'verified',
        'member_name': 'Asha Juma',
        'member_number': 'MEG-0005',
        'verified_by_name': 'Assistant Member',
        'verified_at': '2026-11-20 10:00:00',
      },
      'group': group,
      'verify_url': 'https://3inone.example/api/public/groups/receipts/abc.RC-000001.0123',
      'reversed': false,
      'member_phone': phone,
    });

GroupReport _report() => GroupReport.fromJson(<String, dynamic>{
      'members': <String, dynamic>{
        'by_status': <String, dynamic>{'active': 18, 'suspended': 1},
        'joined': 2,
      },
      'money': <String, dynamic>{
        'savings': <String, dynamic>{'in': 868000, 'out': 150000},
        'contribution': <String, dynamic>{'in': 200000, 'out': 0},
      },
      'contributions': <String, dynamic>{'expected': 400000, 'collected': 200000, 'overdue_now': 520000, 'overdue_members': 16},
      'loans_now': <String, dynamic>{'principal': 312000, 'interest': 36000, 'arrears': 292000},
      'meetings_held': 3,
    });

Map<String, String> _unzip(final Uint8List bytes) {
  final Archive zip = ZipDecoder().decodeBytes(bytes);
  return <String, String>{for (final ArchiveFile f in zip) f.name: utf8.decode(f.content as List<int>)};
}

Map<String, dynamic> _line(final int id, final String category, final String direction, final num amount, final String day, final num account, {final String? receipt}) => <String, dynamic>{
      'id': id,
      'reference': 'TRX-$id',
      'receipt_number': receipt ?? 'RC-00000$id',
      'category': category,
      'direction': direction,
      'amount': amount,
      'method': 'mpesa',
      'external_ref': 'MP$id',
      'paid_on': day,
      'status': 'verified',
      'member_name': 'Asha Juma',
      'verified_at': '$day 10:00:00',
      'balance_after': account,
      'account_after': account,
    };

Map<String, dynamic> _statementJson() => <String, dynamic>{
      'member': <String, dynamic>{'id': 5, 'full_name': 'Asha Juma', 'member_number': 'UWM-0005', 'phone': '0713000001', 'status': 'active', 'office': null, 'joined_on': '2026-01-05'},
      'account': 70000,
      'balances': <String, dynamic>{'joining_fee': 80000, 'shares': 20000, 'savings': 50000, 'contribution': 10000},
      'period': <String, dynamic>{'from': null, 'to': null, 'opening': 0, 'closing': 70000, 'in': 70000, 'out': 0, 'count': 2},
      'lines': <dynamic>[
        _line(2, 'shares', 'in', 20000, '2026-11-02', 70000),
        _line(1, 'savings', 'in', 50000, '2026-01-10', 50000),
      ],
      'owing_total': 10000,
      'owing': <dynamic>[
        <String, dynamic>{'id': 4, 'member_id': 5, 'period': '2026-11', 'amount_due': 10000, 'paid': 0, 'remaining': 10000, 'due_date': '2026-11-05', 'state': 'overdue', 'type_name': 'JAMII'},
      ],
      'waiting': <dynamic>[
        <String, dynamic>{..._line(8, 'savings', 'in', 1000, '2026-11-20', 0), 'status': 'pending', 'receipt_number': null},
      ],
      'declined': <dynamic>[
        <String, dynamic>{..._line(9, 'savings', 'in', 2000, '2026-11-21', 0), 'status': 'rejected', 'receipt_number': null, 'reject_reason': 'Not received'},
      ],
      'loans': <dynamic>[
        <String, dynamic>{
          'id': 9, 'reference': 'LN-0009', 'member_id': 5, 'member_name': 'Asha Juma', 'amount_requested': 300000, 'amount_approved': 300000, 'purpose': 'Duka', 'term_months': 3,
          'interest_rate': 2, 'interest_method': 'flat', 'status': 'active', 'state': 'active', 'outstanding': 212000,
        },
      ],
      'promises': <dynamic>[],
    };

class _StmtApi extends GroupsApi {
  final List<String> calls = <String>[];

  @override
  Future<GroupStatementData?> statement({final int? memberId, final String? from, final String? to}) async {
    calls.add('${from ?? '-'}..${to ?? '-'}');
    return GroupStatementData.fromJson(_statementJson());
  }
}

class _Api extends GroupsApi {
  @override
  Future<GroupReport> report({required final String from, required final String to}) async => _report();

  @override
  Future<Uint8List> exportMembers() async => Uint8List.fromList(utf8.encode('Namba,Jina,Simu\nMEG-0001,"Juma, Ali",0754\n'));
}

GroupMe _me() => GroupMe.fromJson(<String, dynamic>{
      'is_owner': false,
      'rights': <String>['view_members', 'view_finance'],
      'member': <String, dynamic>{'id': 5, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active'},
      'group': <String, dynamic>{'name': 'MEG Group'},
    });

Future<void> _pump(final WidgetTester t, final Widget child) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: child)),
    ),
  );
  await t.pumpAndSettle();
}

/// A filter chip may be past the edge of its sliding row: bring it into view, then tap it a little off its centre (the arrow may cover the edge).
Future<void> _tapChip(final WidgetTester t, final Finder chip) async {
  await t.ensureVisible(chip);
  await t.pumpAndSettle();
  await t.tapAt(t.getCenter(chip) - const Offset(8, 0));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => GroupDocuments.pictureMaker = (final Uint8List _) async => const <Uint8List>[]);
  test('a document becomes a real Word file: a zip with the content types, the relationships and the document, every word in it', () {
    final Uint8List bytes = GroupDocuments.docx(GroupDocuments.receiptDoc(_receipt(), sw: false));
    final Map<String, String> parts = _unzip(bytes);
    expect(parts.keys, containsAll(<String>['[Content_Types].xml', '_rels/.rels', 'word/document.xml']));
    final String doc = parts['word/document.xml']!;
    expect(doc, contains('RC-000001'));
    expect(doc, contains('MEG Group'));
    expect(doc, contains('Asha Juma (MEG-0005)'));
    expect(doc, contains('MP123'));
    expect(doc, contains('https://3inone.example/api/public/groups/receipts/abc.RC-000001.0123'));
    expect(doc, contains('<w:document'));
  });

  test('the Word file keeps Swahili letters and escapes characters that would break the XML', () {
    final GroupDoc d = GroupDocuments.receiptDoc(_receipt(group: 'Umoja <Wajasiriamali> & "Wenzake"'), sw: true);
    final String doc = _unzip(GroupDocuments.docx(d))['word/document.xml']!;
    expect(doc, contains('RISITI'));
    expect(doc, contains('Umoja &lt;Wajasiriamali&gt; &amp; &quot;Wenzake&quot;'));
    expect(doc, isNot(contains('<Wajasiriamali>')));
  });

  test('tables are written as Word tables, and a wide document is landscape', () {
    final GroupDoc d = GroupDocuments.csvDoc(Uint8List.fromList(utf8.encode('A,B,C\n1,2,3\n4,5,6\n')), group: 'G', title: 'T', fileName: 'x');
    final String doc = _unzip(GroupDocuments.docx(d))['word/document.xml']!;
    expect(RegExp('<w:tr>').allMatches(doc).length, 3);
    expect(doc, contains('w:orient="landscape"'));
  });

  test('the group report holds the members, the money, the contributions and the loans, as PDF and as Word', () async {
    for (final bool sw in <bool>[true, false]) {
      final GroupDoc d = GroupDocuments.reportDoc(_report(), sw: sw, group: 'MEG Group', from: '2026-11-01', to: '2026-11-23');
      final Uint8List pdf = await GroupDocuments.pdf(d);
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      final String doc = _unzip(GroupDocuments.docx(d))['word/document.xml']!;
      for (final String s in <String>['868,000', '150,000', '400,000', '312,000', '292,000', '520,000']) {
        expect(doc, contains(s));
      }
      expect(doc, contains(sw ? 'Ripoti ya kikundi' : 'Group report'));
    }
  });

  test('a CSV with quotes, a comma inside quotes, doubled quotes, a line break inside quotes and a byte-order mark is read right', () {
    final List<List<String>> rows = GroupDocuments.parseCsv('A,B,C\r\n1,"x, y","say ""hi"""\r\n"two\nlines",,end\r\n');
    expect(rows, <List<String>>[
      <String>['A', 'B', 'C'],
      <String>['1', 'x, y', 'say "hi"'],
      <String>['two\nlines', '', 'end'],
    ]);
    final GroupDoc d = GroupDocuments.csvDoc(Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode('Jina,Simu\nAsha,0754\n')]), group: 'G', title: 'T', fileName: 'x');
    expect((d.blocks.single as DocTable).head, <String>['Jina', 'Simu']);
  });

  test('a long table runs over several pages, each with its header line, and names with any letter are made without the plain-font warning', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final StringBuffer csv = StringBuffer('Namba,Jina,Kiasi\n');
    for (int i = 1; i <= 120; i++) {
      csv.writeln('UWM-$i,Wanging’ombe Émile ŋgowi $i,"TSH ${i * 1000}"');
    }
    final Uint8List pdf = await GroupDocuments.pdf(GroupDocuments.csvDoc(Uint8List.fromList(utf8.encode(csv.toString())), group: 'Umoja – Mikocheni', title: 'Register', fileName: 'x'));
    final String text = String.fromCharCodes(pdf);
    expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(text).length, greaterThan(2));
    expect(text, contains('NotoSans'));
  });

  test('the statement document has everything: the member, the account, the period, what is owed, the loans, every transaction with the account after it, what waited or was turned down', () async {
    final GroupStatementData d = GroupStatementData.fromJson(_statementJson());
    for (final bool sw in <bool>[true, false]) {
      final GroupDoc doc = GroupDocuments.statementDoc(d, sw: sw, group: 'MEG Group', memberName: 'Asha Juma', loans: d.loans);
      final String text = _unzip(GroupDocuments.docx(doc))['word/document.xml']!;
      for (final String s in <String>['Asha Juma', 'UWM-0005', '0713000001', '70,000', '80,000', '10,000', 'LN-0009', '212,000', 'RC-000001', 'RC-000002', 'MP1', 'Not received', '1,000', '2,000']) {
        expect(text, contains(s), reason: s);
      }
      expect(text, contains(sw ? 'Anachoshikiliwa na kikundi hadi sasa' : 'Held for the member by the group so far'));
      expect(String.fromCharCodes((await GroupDocuments.pdf(doc)).sublist(0, 5)), '%PDF-');
    }
  });

  testWidgets('the statement opens with the account: what the group holds for the member so far, and every transaction below', (final WidgetTester t) async {
    final _StmtApi api = _StmtApi();
    await _pump(t, GroupStatementScreen(api: api));
    expect(find.byKey(const Key('grp_stmt_account')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('grp_stmt_account'))).data, contains('70,000'));
    expect(find.text('Held for you by the group so far (savings and shares)'), findsOneWidget);
    expect(find.text('Asha Juma · UWM-0005'), findsOneWidget);
    expect(find.byKey(const Key('grp_tx_1')), findsOneWidget);
    expect(find.byKey(const Key('grp_tx_2')), findsOneWidget);
    expect(find.byKey(const Key('grp_stmt_declined')), findsOneWidget);
    expect(api.calls, <String>['-..-'], reason: 'all time to begin with');
  });

  testWidgets('the buttons at the top choose the period (asked of the server) and the kind of money (filtered on the phone)', (final WidgetTester t) async {
    final _StmtApi api = _StmtApi();
    await _pump(t, GroupStatementScreen(api: api));
    final DateTime now = DateTime.now();
    String iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    await _tapChip(t, find.byKey(const Key('grp_stmt_range_month')));
    await t.pumpAndSettle();
    expect(api.calls.last, '${iso(DateTime(now.year, now.month))}..${iso(now)}');
    await _tapChip(t, find.byKey(const Key('grp_stmt_range_year')));
    await t.pumpAndSettle();
    expect(api.calls.last, '${iso(DateTime(now.year))}..${iso(now)}');
    await _tapChip(t, find.byKey(const Key('grp_stmt_range_all')));
    await t.pumpAndSettle();
    expect(api.calls.last, '-..-');

    await _tapChip(t, find.byKey(const Key('grp_stmt_kind_shares')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_tx_2')), findsOneWidget);
    expect(find.byKey(const Key('grp_tx_1')), findsNothing, reason: 'a savings line is hidden under Shares');
    await _tapChip(t, find.byKey(const Key('grp_stmt_kind_loans')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_stmt_none')), findsOneWidget);
    await _tapChip(t, find.byKey(const Key('grp_stmt_kind_all')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_tx_1')), findsOneWidget);
  });

  test('a short row in a CSV is filled so the table stays square', () {
    final GroupDoc d = GroupDocuments.csvDoc(Uint8List.fromList(utf8.encode('A,B,C\n1,2\n')), group: 'G', title: 'T', fileName: 'x');
    expect((d.blocks.single as DocTable).rows.single, <String>['1', '2', '']);
  });

  test('a Tanzanian number is made international for WhatsApp, and the receipt message carries the amount and the check link', () {
    expect(GroupDocuments.internationalPhone('0754 100 200'), '255754100200');
    expect(GroupDocuments.internationalPhone('+255 754 100 200'), '255754100200');
    final String sw = GroupDocuments.receiptMessage(_receipt(), sw: true);
    expect(sw, contains('RC-000001'));
    expect(sw, contains('50,000'));
    expect(sw, contains('Thibitisha risiti'));
    expect(sw, contains('abc.RC-000001.0123'));
    expect(GroupDocuments.receiptMessage(_receipt(), sw: false), contains('Check the receipt'));
  });

  testWidgets('sending a receipt offers a text message and WhatsApp to the member\'s number, and the file; with no number only the file', (final WidgetTester t) async {
    GroupReceipt? r = _receipt();
    await _pump(
      t,
      Builder(builder: (final BuildContext c) => Scaffold(body: Center(child: TextButton(key: const Key('go'), onPressed: () => GroupDocuments.sendReceipt(c, r!, sw: false), child: const Text('go'))))),
    );
    await t.tap(find.byKey(const Key('go')));
    await t.pumpAndSettle();
    expect(find.textContaining('Text message (SMS) to 0754 100 200'), findsOneWidget);
    expect(find.textContaining('WhatsApp 0754 100 200'), findsOneWidget);
    expect(find.text('File: PDF, picture or Word'), findsOneWidget);
    expect(find.textContaining('Send receipt RC-000001 to Asha Juma'), findsOneWidget);

    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    r = _receipt(phone: null);
    await t.tap(find.byKey(const Key('go')));
    await t.pumpAndSettle();
    expect(find.textContaining('Text message (SMS)'), findsNothing);
    expect(find.textContaining('WhatsApp'), findsNothing);
    expect(find.text('File: PDF, picture or Word'), findsOneWidget);
  });

  testWidgets('choosing the file shows the forms: PDF and Word, and no picture when the phone cannot make one', (final WidgetTester t) async {
    await _pump(
      t,
      Builder(builder: (final BuildContext c) => Scaffold(body: Center(child: TextButton(key: const Key('go'), onPressed: () => GroupDocuments.shareDoc(c, GroupDocuments.receiptDoc(_receipt(), sw: false), sw: false, csv: Uint8List(1)), child: const Text('go'))))),
    );
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('go')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pumpAndSettle();
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Word (.docx)'), findsOneWidget);
    expect(find.text('Spreadsheet (CSV)'), findsOneWidget);
  });

  testWidgets('a document that fits one page can also be shared as a picture; a longer one cannot', (final WidgetTester t) async {
    GroupDocuments.pictureMaker = (final Uint8List _) async => <Uint8List>[Uint8List(3)];
    await _pump(
      t,
      Builder(builder: (final BuildContext c) => Scaffold(body: Center(child: TextButton(key: const Key('go'), onPressed: () => GroupDocuments.shareDoc(c, GroupDocuments.receiptDoc(_receipt(), sw: true), sw: true), child: const Text('go'))))),
    );
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('go')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pumpAndSettle();
    expect(find.text('Picha (ukurasa mmoja)'), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    GroupDocuments.pictureMaker = (final Uint8List _) async => <Uint8List>[Uint8List(3), Uint8List(3)];
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('go')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pumpAndSettle();
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Picha (ukurasa mmoja)'), findsNothing);
  });

  testWidgets('the group report screen has a share button that offers PDF and Word, and the exports offer them too', (final WidgetTester t) async {
    await _pump(t, GroupReportsScreen(api: _Api(), me: _me()));
    expect(find.byKey(const Key('grp_share_report')), findsOneWidget);
    expect(find.text('Share the report (PDF, picture, Word)'), findsOneWidget);
    expect(find.text('Member register (PDF, Word, CSV)'), findsOneWidget);
    expect(find.text('Payments of the period (PDF, Word, CSV)'), findsOneWidget);

    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('grp_share_report')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pumpAndSettle();
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Word (.docx)'), findsOneWidget);
    expect(find.text('Spreadsheet (CSV)'), findsNothing);
  });
}
