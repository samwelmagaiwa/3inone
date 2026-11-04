import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/services_report_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The salon's full pages sit on the same plain dark teal as the rest of the salon, with no near-black at the top (the dashboard's gradient
/// starts nearly black, which looked like a hole in the page).
class _Salon extends SalonApi {
  @override
  Future<ServiceReport> serviceSales({DateTime? from, DateTime? to}) async => ServiceReport(from: DateTime(2026, 11), to: DateTime(2026, 11, 4), times: 0, revenue: 0, services: const <ServiceRow>[]);
}

Future<void> _pump(WidgetTester t, Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 900), minTextAdapt: true, builder: (_, __) => MaterialApp(home: home)),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

bool _hasGradient(WidgetTester t) => find.byWidgetPredicate((Widget w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient != null && (w.decoration as BoxDecoration).gradient == ThemeConstants.dashboardBackground.gradient).evaluate().isNotEmpty;

void main() {
  testWidgets('Services sold is plain dark teal from the title bar to the bottom, with no near-black top', (t) async {
    await _pump(t, ServicesReportScreen(api: _Salon(), today: DateTime(2026, 11, 4)));

    expect(t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, ThemeConstants.primaryBlue);
    expect(t.widget<AppBar>(find.byType(AppBar)).backgroundColor, ThemeConstants.primaryBlue);
    expect(_hasGradient(t), isFalse, reason: 'the dashboard gradient is not painted behind it');
  });

  testWidgets('a page that did not ask for it keeps the dashboard gradient and its dark bar as before', (t) async {
    await _pump(t, ThemeConstants.buildScaffold(title: 'Other', body: const SizedBox()));

    expect(t.widget<AppBar>(find.byType(AppBar)).backgroundColor, ThemeConstants.bgTop);
    expect(_hasGradient(t), isTrue);
  });

  testWidgets('flat is also an option of the bar alone', (t) async {
    await _pump(t, Scaffold(appBar: ThemeConstants.buildAppBar('X', flat: true)));

    expect(t.widget<AppBar>(find.byType(AppBar)).backgroundColor, ThemeConstants.primaryBlue);
  });
}
