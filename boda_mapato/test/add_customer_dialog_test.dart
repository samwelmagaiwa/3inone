import 'package:boda_mapato/modules/inventory/models/existing_customer.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/add_customer_dialog.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adding a customer at the till: the phone number is a must (nine digits at least), and while the name or number is typed the dialog says
/// when that customer is already saved and offers to use them, so nobody is saved twice.
class _Calls {
  final List<String> looked = <String>[];
  final List<String> saved = <String>[];
  ExistingCustomer? existing;
  CustomerChoice? saveResult = const CustomerChoice(id: 11, name: 'Asha');
}

Future<CustomerChoice?> _open(WidgetTester t, _Calls calls, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  CustomerChoice? result;
  bool closed = false;
  await t.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Builder(
          builder: (BuildContext c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey<String>('open'),
                onPressed: () async {
                  result = await showDialog<CustomerChoice>(
                    context: c,
                    builder: (_) => AddCustomerDialog(
                      debounce: const Duration(milliseconds: 50),
                      lookup: (String name, String phone) async {
                        calls.looked.add('$name|$phone');
                        return calls.existing;
                      },
                      save: ({required String name, required String phone, String? address}) async {
                        calls.saved.add('$name|$phone|${address ?? ''}');
                        return calls.saveResult;
                      },
                    ),
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const ValueKey<String>('open')));
  await t.pumpAndSettle();
  // the result is read after the dialog closes
  addTearDown(() {});
  return Future<CustomerChoice?>.value(closed ? result : null);
}

Finder _k(String k) => find.byKey(ValueKey<String>(k));

Future<void> _type(WidgetTester t, {String? name, String? phone}) async {
  if (name != null) await t.enterText(_k('new_customer_name'), name);
  if (phone != null) await t.enterText(_k('new_customer_phone'), phone);
  await t.pump(const Duration(milliseconds: 200));
  await t.pump();
}

void main() {
  test('a phone number has at least nine digits, however it is written', () {
    expect(isValidCustomerPhone('0743519104'), isTrue);
    expect(isValidCustomerPhone('743519104'), isTrue);
    expect(isValidCustomerPhone('+255 743 519 104'), isTrue);
    expect(isValidCustomerPhone('07435191'), isFalse);
    expect(isValidCustomerPhone(''), isFalse);
    expect(isValidCustomerPhone('abc'), isFalse);
  });

  testWidgets('saving without a phone number is refused and says so', (t) async {
    final _Calls calls = _Calls();
    await _open(t, calls);

    await _type(t, name: 'Asha');
    await t.tap(_k('new_customer_save'));
    await t.pump();

    expect(find.text("Enter the customer's phone number (at least 9 digits)."), findsOneWidget);
    expect(calls.saved, isEmpty);
    expect(_k('new_customer_name'), findsOneWidget, reason: 'the dialog stays open');
  });

  testWidgets('a number that is too short is refused as it is typed', (t) async {
    final _Calls calls = _Calls();
    await _open(t, calls);

    await _type(t, name: 'Asha', phone: '07435');
    expect(find.text("Enter the customer's phone number (at least 9 digits)."), findsOneWidget);
    await t.tap(_k('new_customer_save'));
    await t.pump();

    expect(calls.saved, isEmpty);
  });

  testWidgets('the phone box takes digits only', (t) async {
    await _open(t, _Calls());

    await _type(t, phone: '07x43-5ab19104');

    expect(t.widget<TextField>(_k('new_customer_phone')).controller!.text, '0743519104');
  });

  testWidgets('a valid customer is saved with the name, number and address', (t) async {
    final _Calls calls = _Calls();
    await _open(t, calls);

    await _type(t, name: 'Asha', phone: '0711000111');
    await t.enterText(_k('new_customer_address'), 'Mwanza');
    await t.tap(_k('new_customer_save'));
    await t.pumpAndSettle();

    expect(calls.saved, <String>['Asha|0711000111|Mwanza']);
    expect(_k('new_customer_name'), findsNothing, reason: 'the dialog closed');
  });

  testWidgets('a number that is already saved shows that customer and offers to use them', (t) async {
    final _Calls calls = _Calls()..existing = const ExistingCustomer(id: 5, name: 'Mama Chale', phone: '0711000777');
    await _open(t, calls);

    await _type(t, name: 'Someone else', phone: '+255711000777');

    expect(_k('customer_already_saved'), findsOneWidget);
    expect(find.text('Already saved: Mama Chale (0711000777).'), findsOneWidget);
    expect(find.text('Use this customer'), findsOneWidget, reason: 'the button now uses them instead of saving');
    expect(calls.looked.last, 'Someone else|+255711000777');
  });

  testWidgets('using the customer who is already saved saves nothing and chooses them', (t) async {
    final _Calls calls = _Calls()..existing = const ExistingCustomer(id: 5, name: 'Mama Chale', phone: '0711000777');
    CustomerChoice? chosen;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    addTearDown(t.view.reset);
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1.0;
    await t.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (BuildContext c) => Scaffold(
              body: ElevatedButton(
                key: const ValueKey<String>('open'),
                onPressed: () async => chosen = await showDialog<CustomerChoice>(
                  context: c,
                  builder: (_) => AddCustomerDialog(
                    debounce: const Duration(milliseconds: 50),
                    lookup: (String n, String p) async => calls.existing,
                    save: ({required String name, required String phone, String? address}) async {
                      calls.saved.add(name);
                      return null;
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(_k('open'));
    await t.pumpAndSettle();

    await _type(t, name: 'mama chale');
    await t.tap(_k('new_customer_save'));
    await t.pumpAndSettle();

    expect(calls.saved, isEmpty);
    expect(chosen?.id, 5);
    expect(chosen?.existed, isTrue);
  });

  testWidgets('nothing is asked while there is too little to go on', (t) async {
    final _Calls calls = _Calls();
    await _open(t, calls);

    await _type(t, name: 'A', phone: '07');

    expect(calls.looked, isEmpty);
    expect(_k('customer_already_saved'), findsNothing);
  });

  testWidgets('when the customer is no longer found the notice goes away', (t) async {
    final _Calls calls = _Calls()..existing = const ExistingCustomer(id: 5, name: 'Mama Chale', phone: '0711000777');
    await _open(t, calls);
    await _type(t, name: 'Mama Chale');
    expect(_k('customer_already_saved'), findsOneWidget);

    calls.existing = null;
    await _type(t, name: 'Mama Chalee');

    expect(_k('customer_already_saved'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('a failed save says so and keeps the dialog', (t) async {
    final _Calls calls = _Calls()..saveResult = null;
    await _open(t, calls);

    await _type(t, name: 'Asha', phone: '0711000111');
    await t.tap(_k('new_customer_save'));
    await t.pump();
    await t.pump();
    await t.pump(const Duration(seconds: 6));

    expect(_k('new_customer_name'), findsOneWidget);
  });

  testWidgets('in Swahili the messages are Swahili', (t) async {
    final _Calls calls = _Calls()..existing = const ExistingCustomer(id: 5, name: 'Mama Chale', phone: '0711000777');
    await _open(t, calls, sw: true);

    await _type(t, name: 'Mama Chale', phone: '07');

    expect(find.text('Andika namba ya simu ya mteja (angalau tarakimu 9).'), findsOneWidget);
    expect(find.text('Tayari yupo: Mama Chale (0711000777).'), findsOneWidget);
    expect(find.text('Tumia mteja huyu'), findsOneWidget);
  });
}
