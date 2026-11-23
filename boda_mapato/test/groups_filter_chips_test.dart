import 'package:boda_mapato/modules/groups/models/group_loan_models.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/loans_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/widgets/scrolling_chip_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends GroupsApi {
  final List<String?> asked = <String?>[];

  @override
  Future<GroupLoanPage> loans({final String? status, final int page = 1}) async {
    asked.add(status);

    return GroupLoanPage.fromJson(<String, dynamic>{
      'data': <String, dynamic>{
        'loans': <dynamic>[],
        'portfolio': <String, dynamic>{'principal_outstanding': 312000, 'interest_outstanding': 36000, 'interest_paid': 104000, 'arrears': 0, 'overdue': 0},
        'waiting': <String, dynamic>{'to_recommend': 1, 'to_approve': 1, 'to_disburse': 1},
      },
    });
  }
}

void main() {
  testWidgets('the filter buttons are first, a tap slides the row on so the other buttons show, and the cards follow below', (final WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    t.view.physicalSize = const Size(411, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final _Api api = _Api();
    final GroupMe me = GroupMe.fromJson(<String, dynamic>{
      'rights': <String>['view_loans'],
      'member': <String, dynamic>{'id': 1, 'full_name': 'Daudi', 'phone': '0713000001', 'status': 'active'},
      'group': <String, dynamic>{'name': 'MEG'},
    });
    await t.pumpWidget(
      ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ScreenUtilInit(
          designSize: const Size(411, 900),
          builder: (_, __) => MaterialApp(home: Scaffold(body: LoansScreen(me: me, api: api, onChanged: () async {}))),
        ),
      ),
    );
    await t.pumpAndSettle();

    final double chips = t.getTopLeft(find.byType(ScrollingChipRow)).dy;
    final double summary = t.getTopLeft(find.byKey(const Key('grp_portfolio_out'))).dy;
    expect(chips, lessThan(summary), reason: 'the buttons are at the top, the sections follow below');

    // The row is wider than the screen: an arrow says there are more, and a tap slides the row.
    expect(find.byKey(const ValueKey<String>('chips_more_after')), findsOneWidget);
    final double before = t.getTopLeft(find.byKey(const Key('grp_loan_filter_under_review'))).dx;
    // The chip starts on screen and ends beyond it (the test font is wide): tap its visible start.
    final Rect r = t.getRect(find.byKey(const Key('grp_loan_filter_under_review')));
    await t.tapAt(Offset(r.left + 12, r.center.dy));
    await t.pumpAndSettle();
    expect(api.asked.last, 'under_review');
    expect(t.getTopLeft(find.byKey(const Key('grp_loan_filter_under_review'))).dx, lessThan(before), reason: 'the tapped button slid towards the start, showing those after it');
  });
}
