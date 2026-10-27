import 'package:boda_mapato/modules/inventory/screens/widgets/inv_units_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// The price dialog of the till: money is written with commas as it is typed (1,000,000), not as 1000000.
Future<void> _open(WidgetTester t, {required double initial, double? list, bool offerList = false, void Function(PriceAnswer?)? onAnswer}) async {
  await t.pumpWidget(ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (BuildContext _, Widget? __) => MaterialApp(
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: TextButton(
          key: const Key('open'),
          onPressed: () async {
            final PriceAnswer? a = await askPrice(context, title: 'Write the price', initial: initial, listPrice: list, offerList: offerList, okLabel: 'Save', cancelLabel: 'Cancel', listLabel: 'Use the usual price');
            onAnswer?.call(a);
          },
          child: const Text('open'),
        ),
      ),
    ),
  )));
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('typing a big amount shows the thousands commas as you go', (WidgetTester t) async {
    await _open(t, initial: 2500);
    expect(find.text('2,500'), findsOneWidget, reason: 'the price already there is shown with its comma');

    await t.enterText(find.byKey(const ValueKey<String>('price_field')), '1000000');
    await t.pump();

    expect(find.text('1,000,000'), findsOneWidget);
  });

  testWidgets('Save answers with the number, without the commas', (WidgetTester t) async {
    PriceAnswer? got;
    await _open(t, initial: 2500, onAnswer: (PriceAnswer? a) => got = a);

    await t.enterText(find.byKey(const ValueKey<String>('price_field')), '1500000');
    await t.tap(find.byKey(const ValueKey<String>('price_ok')));
    await t.pumpAndSettle();

    expect(got!.useList, isFalse);
    expect(got!.price, 1500000);
  });

  testWidgets('the usual price can be taken back, and it is shown with commas', (WidgetTester t) async {
    PriceAnswer? got;
    await _open(t, initial: 800, list: 22000, offerList: true, onAnswer: (PriceAnswer? a) => got = a);
    expect(find.text('Use the usual price (22,000)'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('price_use_list')));
    await t.pumpAndSettle();

    expect(got!.useList, isTrue);
  });

  testWidgets('the usual price is not offered while the price is the usual one', (WidgetTester t) async {
    await _open(t, initial: 22000, list: 22000);

    expect(find.byKey(const ValueKey<String>('price_use_list')), findsNothing);
  });

  testWidgets('Cancel answers nothing', (WidgetTester t) async {
    bool called = false;
    PriceAnswer? got = const PriceAnswer.write(1);
    await _open(t, initial: 2500, onAnswer: (PriceAnswer? a) {
      called = true;
      got = a;
    });

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(called, isTrue);
    expect(got, isNull);
  });
}
