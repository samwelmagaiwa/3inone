import 'package:boda_mapato/modules/inventory/screens/widgets/inventory_widgets.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A hub can gain or lose a tab while it is open (the crates tab, once the business's kind is known). That makes the
/// scaffold build a new TabController. With a single-ticker State this stopped debug builds with "multiple tickers
/// were created"; release builds hide that, so only a test shows it.
void main() {
  Widget host(ValueNotifier<int> tabCount) => MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ],
        child: ScreenUtilInit(
          designSize: const Size(411, 900),
          minTextAdapt: true,
          builder: (_, __) => MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: tabCount,
              builder: (BuildContext context, int n, Widget? _) => InvTabScaffold(
                title: '',
                tabs: <String>[for (int i = 0; i < n; i++) 'Tab $i'],
                views: <Widget>[for (int i = 0; i < n; i++) Text('page $i')],
              ),
            ),
          ),
        ),
      );

  testWidgets('losing a tab while open does not crash', (t) async {
    final ValueNotifier<int> count = ValueNotifier<int>(3);
    await t.pumpWidget(host(count));
    expect(find.text('Tab 2'), findsOneWidget);

    count.value = 2;
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(t.takeException(), isNull);
    expect(find.text('Tab 2'), findsNothing);
    expect(find.text('Tab 1'), findsOneWidget);
  });

  testWidgets('gaining a tab, and then losing it again, does not crash either', (t) async {
    final ValueNotifier<int> count = ValueNotifier<int>(2);
    await t.pumpWidget(host(count));

    count.value = 3;
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Tab 2'), findsOneWidget);

    count.value = 2;
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(t.takeException(), isNull);
    expect(find.text('Tab 2'), findsNothing);
  });

  testWidgets('the new tab bar still switches pages', (t) async {
    final ValueNotifier<int> count = ValueNotifier<int>(3);
    await t.pumpWidget(host(count));
    count.value = 2;
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    await t.tap(find.text('Tab 1'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(find.text('page 1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
