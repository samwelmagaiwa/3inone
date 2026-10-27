import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/screens/settings/crate_deposit_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const InvCrateType _crate =
    InvCrateType(id: 1, name: 'Crate', depositValue: 2000);
const InvCrateType _bottle =
    InvCrateType(id: 2, name: 'Empty bottle', depositValue: 100, status: 'inactive');

class _Calls {
  final List<String> log = <String>[];
  String? nextProblem;
}

Future<void> _pump(
  WidgetTester t,
  _Calls calls, {
  List<InvCrateType> types = const <InvCrateType>[_crate, _bottle],
  bool swahili = false,
}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  await t.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CrateDepositCard(
              swahili: swahili,
              types: types,
              onCreate: (String name, double deposit) async {
                calls.log.add('create $name $deposit');
                return calls.nextProblem;
              },
              onUpdate: (InvCrateType type, String name, double deposit,
                  bool active) async {
                calls.log.add('update ${type.id} $name $deposit $active');
                return calls.nextProblem;
              },
              onDelete: (InvCrateType type) async {
                calls.log.add('delete ${type.id}');
                return calls.nextProblem;
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('lists each crate type with its deposit and marks switched-off ones',
      (t) async {
    await _pump(t, _Calls());
    expect(find.text('Crate security deposit'), findsOneWidget);
    expect(find.text('Crate'), findsOneWidget);
    expect(find.text('TZS 2000'), findsOneWidget);
    expect(find.text('Empty bottle'), findsOneWidget);
    expect(find.text('TZS 100'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget); // only the inactive one
  });

  testWidgets('says so when there are no crate types', (t) async {
    await _pump(t, _Calls(), types: const <InvCrateType>[]);
    expect(_key('crate_types_empty'), findsOneWidget);
    expect(_key('crate_type_add'), findsOneWidget);
  });

  testWidgets('editing the deposit sends the new amount and closes', (t) async {
    final _Calls calls = _Calls();
    await _pump(t, calls);

    await t.tap(_key('crate_type_row_1'));
    await t.pumpAndSettle();
    await t.enterText(_key('crate_type_deposit'), '3500');
    await t.tap(_key('crate_type_save'));
    await t.pumpAndSettle();

    expect(calls.log, <String>['update 1 Crate 3500.0 true']);
    expect(_key('crate_type_save'), findsNothing); // dialog closed
  });

  testWidgets('a type can be switched off from the editor', (t) async {
    final _Calls calls = _Calls();
    await _pump(t, calls);

    await t.tap(_key('crate_type_row_1'));
    await t.pumpAndSettle();
    await t.tap(_key('crate_type_active'));
    await t.tap(_key('crate_type_save'));
    await t.pumpAndSettle();

    expect(calls.log, <String>['update 1 Crate 2000.0 false']);
  });

  testWidgets('the server refusing keeps the dialog open and shows why',
      (t) async {
    final _Calls calls = _Calls()
      ..nextProblem = 'Customers still hold 10 crate(s) of this type.';
    await _pump(t, calls);

    await t.tap(_key('crate_type_row_1'));
    await t.pumpAndSettle();
    await t.tap(_key('crate_type_active'));
    await t.tap(_key('crate_type_save'));
    await t.pumpAndSettle();

    expect(_key('crate_type_save'), findsOneWidget); // still open
    expect(t.widget<Text>(_key('crate_type_error')).data,
        'Customers still hold 10 crate(s) of this type.');
  });

  testWidgets('adding a type needs a name and a valid deposit', (t) async {
    final _Calls calls = _Calls();
    await _pump(t, calls);

    await t.tap(_key('crate_type_add'));
    await t.pumpAndSettle();
    await t.tap(_key('crate_type_save'));
    await t.pump();
    expect(find.text('A name is required'), findsOneWidget);
    expect(find.text('Enter a valid amount'), findsOneWidget);
    expect(calls.log, isEmpty);

    await t.enterText(_key('crate_type_name'), 'Big crate');
    // An amount is typed with its commas and cannot be negative: a minus sign is simply not accepted.
    await t.enterText(_key('crate_type_deposit'), '-5');
    await t.pump();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('-5'), findsNothing);
    await t.enterText(_key('crate_type_deposit'), '');
    await t.tap(_key('crate_type_save'));
    await t.pump();
    expect(find.text('Enter a valid amount'), findsOneWidget);
    expect(calls.log, isEmpty);

    await t.enterText(_key('crate_type_deposit'), '5000');
    await t.tap(_key('crate_type_save'));
    await t.pumpAndSettle();
    expect(calls.log, <String>['create Big crate 5000.0']);
  });

  testWidgets('delete asks first, then calls the server', (t) async {
    final _Calls calls = _Calls();
    await _pump(t, calls);

    await t.tap(_key('crate_type_row_2'));
    await t.pumpAndSettle();
    await t.tap(_key('crate_type_delete'));
    await t.pumpAndSettle();
    expect(calls.log, isEmpty); // nothing yet: waiting for confirmation

    await t.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await t.pumpAndSettle();
    expect(calls.log, <String>['delete 2']);
  });

  testWidgets('a new type has no delete button or in-use switch', (t) async {
    await _pump(t, _Calls());
    await t.tap(_key('crate_type_add'));
    await t.pumpAndSettle();
    expect(_key('crate_type_delete'), findsNothing);
    expect(_key('crate_type_active'), findsNothing);
  });

  testWidgets('Swahili labels', (t) async {
    await _pump(t, _Calls(), swahili: true);
    expect(find.text('Dhamana ya makreti'), findsOneWidget);
    expect(find.text('Ongeza aina ya crate'), findsOneWidget);
    expect(find.text('Imezimwa'), findsOneWidget);
  });
}
