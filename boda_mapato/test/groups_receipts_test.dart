import 'dart:typed_data';

import 'package:boda_mapato/modules/groups/models/group_loan_models.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_receipt_models.dart';
import 'package:boda_mapato/modules/groups/screens/statement_screen.dart';
import 'package:boda_mapato/modules/groups/services/group_documents.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _tx(final int id, {final String? receipt = 'RC-000001'}) => <String, dynamic>{
      'id': id,
      'reference': 'TRX-$id',
      'receipt_number': receipt,
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
    };

GroupReceipt _receipt({final bool reversed = false}) => GroupReceipt.fromJson(<String, dynamic>{
      'transaction': _tx(1),
      'group': 'MEG Group',
      'verify_url': 'https://3inone.example/api/public/groups/receipts/abc.RC-000001.0123456789abcdef',
      'reversed': reversed,
    });

GroupStatementData _statement() => GroupStatementData.fromJson(<String, dynamic>{
      'balances': <String, dynamic>{'joining_fee': 80000, 'shares': 200000, 'savings': 50000, 'contribution': 0},
      'owing_total': 10000,
      'owing': <dynamic>[
        <String, dynamic>{'id': 4, 'member_id': 5, 'period': '2026-11', 'amount_due': 10000, 'paid': 0, 'remaining': 10000, 'due_date': '2026-11-05', 'state': 'overdue', 'type_name': 'JAMII'},
      ],
      'lines': <dynamic>[
        <String, dynamic>{..._tx(1), 'balance_after': 50000},
      ],
    });

GroupLoan _loan() => GroupLoan.fromJson(<String, dynamic>{
      'id': 9,
      'reference': 'LN-0009',
      'member_id': 5,
      'member_name': 'Asha Juma',
      'amount_requested': 300000,
      'amount_approved': 300000,
      'purpose': 'Mtaji wa duka',
      'term_months': 3,
      'interest_rate': 2,
      'interest_method': 'flat',
      'status': 'active',
      'state': 'active',
      'disbursed_on': '2026-10-01',
      'outstanding': 212000,
      'position': <String, dynamic>{
        'principal_paid': 100000,
        'interest_paid': 6000,
        'outstanding_principal': 200000,
        'outstanding_interest': 12000,
        'instalments': <dynamic>[
          <String, dynamic>{'number': 1, 'due_date': '2026-11-01', 'principal_due': 100000, 'interest_due': 6000, 'paid': 106000, 'left': 0, 'state': 'paid'},
          <String, dynamic>{'number': 2, 'due_date': '2026-12-01', 'principal_due': 100000, 'interest_due': 6000, 'paid': 0, 'left': 106000, 'state': 'due'},
        ],
      },
    });

class _FakeApi extends GroupsApi {
  final List<String> calls = <String>[];

  @override
  Future<GroupStatementData?> statement({final int? memberId}) async => _statement();

  @override
  Future<GroupReceipt> receipt(final int id) async {
    calls.add('receipt:$id');
    return _receipt();
  }

  @override
  Future<GroupMe> me() async => GroupMe.fromJson(<String, dynamic>{
        'is_owner': false,
        'rights': <String>[],
        'member': <String, dynamic>{'id': 5, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active'},
        'group': <String, dynamic>{'name': 'MEG Group'},
      });

  @override
  Future<(List<GroupLoan>, List<GroupGuarantee>)> myLoans() async => (<GroupLoan>[_loan()], <GroupGuarantee>[]);
}

bool _isPdf(final Uint8List b) => b.length > 500 && String.fromCharCodes(b.sublist(0, 5)) == '%PDF-';

void main() {
  test('a receipt, a statement and a loan statement are made as PDF documents, in both languages', () async {
    for (final bool sw in <bool>[true, false]) {
      expect(_isPdf(await GroupDocuments.receipt(_receipt(), sw: sw)), isTrue);
      expect(_isPdf(await GroupDocuments.receipt(_receipt(reversed: true), sw: sw)), isTrue);
      expect(_isPdf(await GroupDocuments.statement(_statement(), sw: sw, group: 'MEG Group', memberName: 'Asha Juma', loans: <GroupLoan>[_loan()])), isTrue);
      expect(_isPdf(await GroupDocuments.loanStatement(_loan(), sw: sw, group: 'MEG Group')), isTrue);
    }
  });

  test('the receipt model carries the group, the link the QR code holds and whether it was reversed', () {
    final GroupReceipt r = _receipt(reversed: true);
    expect(r.group, 'MEG Group');
    expect(r.verifyUrl, contains('/api/public/groups/receipts/'));
    expect(r.reversed, isTrue);
    expect(r.transaction.receiptNumber, 'RC-000001');
  });

  testWidgets('in the statement a verified line opens its receipt, and the PDF button is there', (final WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    t.view.physicalSize = const Size(411, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final _FakeApi api = _FakeApi();
    await t.pumpWidget(
      ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: GroupStatementScreen(api: api))),
      ),
    );
    await t.pumpAndSettle();

    expect(find.byKey(const Key('grp_stmt_pdf')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('grp_tx_1')));
    await t.tap(find.byKey(const Key('grp_tx_1')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['receipt:1']);
    await t.pump(const Duration(seconds: 6));
  });
}
