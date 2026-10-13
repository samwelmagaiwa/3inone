import 'package:boda_mapato/modules/inventory/models/crates_owed.dart';
import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/crates_owed_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

InvCrateBalance _bal(int customerId, String type, int held, double deposit) =>
    InvCrateBalance(
      customerId: customerId,
      crateTypeId: type.length,
      crateTypeName: type,
      held: held,
      depositAtRisk: deposit,
    );

void main() {
  group('CratesOwed.forCustomer', () {
    final List<InvCrateBalance> all = <InvCrateBalance>[
      _bal(2, 'Crate', 10, 20000),
      _bal(2, 'Empty bottle', 24, 2400),
      _bal(3, 'Crate', 5, 10000),
      _bal(4, 'Crate', -3, 0), // the depot owes customer 4
    ];

    test('adds up only that customer, per crate type', () {
      final CratesOwed owed = CratesOwed.forCustomer(all, 2);
      expect(owed.isNone, isFalse);
      expect(owed.total, 34);
      expect(owed.depositAtRisk, 22400);
      expect(owed.heldSummary, '10 × Crate, 24 × Empty bottle');
      expect(owed.owedToCustomer, isEmpty);
    });

    test('a customer with nothing recorded owes nothing', () {
      expect(CratesOwed.forCustomer(all, 99).isNone, isTrue);
      expect(CratesOwed.forCustomer(const <InvCrateBalance>[], 2).isNone, isTrue);
    });

    test('crates the depot owes the customer are kept apart from crates they owe', () {
      final CratesOwed owed = CratesOwed.forCustomer(all, 4);
      expect(owed.isNone, isFalse);
      expect(owed.total, 0);
      expect(owed.held, isEmpty);
      expect(owed.owedToCustomerSummary, '3 × Crate');
    });
  });

  group('CratesOwedNote', () {
    Future<void> pump(WidgetTester t, CratesOwed owed, {bool swahili = false}) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(body: CratesOwedNote(owed: owed, swahili: swahili)),
        ),
      ));
    }

    testWidgets('shows what is owed and the deposit it covers', (t) async {
      await pump(t, CratesOwed.forCustomer(<InvCrateBalance>[_bal(2, 'Crate', 10, 20000)], 2));
      expect(find.byKey(const ValueKey<String>('crates_owed_note')), findsOneWidget);
      expect(find.text('Crates owed: 10 × Crate (deposit TZS 20000)'), findsOneWidget);
    });

    testWidgets('draws nothing when no crates are owed', (t) async {
      await pump(t, const CratesOwed());
      expect(find.byKey(const ValueKey<String>('crates_owed_note')), findsNothing);
    });

    testWidgets('says so when the depot owes the customer crates', (t) async {
      await pump(t, CratesOwed.forCustomer(<InvCrateBalance>[_bal(4, 'Crate', -3, 0)], 4));
      expect(find.text('Depot owes them: 3 × Crate'), findsOneWidget);
    });

    Future<void> pumpNotDepot(WidgetTester t, CratesOwed owed, {bool swahili = false}) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(body: CratesOwedNote(owed: owed, swahili: swahili, isDepot: false)),
        ),
      ));
    }

    testWidgets('a business that is not a depot says "We owe them", not "Depot owes them"', (t) async {
      await pumpNotDepot(t, CratesOwed.forCustomer(<InvCrateBalance>[_bal(4, 'Crate', -3, 0)], 4));
      expect(find.text('We owe them: 3 × Crate'), findsOneWidget);
      expect(find.textContaining('Depot'), findsNothing);
    });

    testWidgets('and in Swahili it does not say "Ghala"', (t) async {
      await pumpNotDepot(t, CratesOwed.forCustomer(<InvCrateBalance>[_bal(4, 'Crate', -3, 0)], 4), swahili: true);
      expect(find.text('Anatudai makreti: 3 × Crate'), findsOneWidget);
      expect(find.textContaining('Ghala'), findsNothing);
    });

    testWidgets('Swahili', (t) async {
      await pump(t, CratesOwed.forCustomer(<InvCrateBalance>[_bal(2, 'Crate', 10, 20000)], 2),
          swahili: true);
      expect(find.text('Makreti anayodaiwa: 10 × Crate (dhamana TZS 20000)'), findsOneWidget);
    });
  });
}
