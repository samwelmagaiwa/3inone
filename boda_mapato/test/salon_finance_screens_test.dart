import 'dart:typed_data';

import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/payroll_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/profit_loss_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_expenses_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/inventory_widgets.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The salon's money pages: expenses (with approval and receipts), payroll (salary + commission - paid - advances) and
/// profit and loss. A fake server answers; what is checked is what the owner reads and what each tap sends.
class _FakeSalon extends SalonApi {
  List<SalonExpense> expenseRows = <SalonExpense>[];
  final List<(DateTime, DateTime)> expenseAsks = <(DateTime, DateTime)>[];
  final List<Map<String, dynamic>> saved = <Map<String, dynamic>>[];
  final List<(int, bool)> decided = <(int, bool)>[];
  final List<(int, String)> receipts = <(int, String)>[];
  Object? failExpenses;

  PayrollReport report = const PayrollReport(month: '2026-10', staff: <PayrollRow>[], salary: 0, commissionEarned: 0, owed: 0);
  List<Payout> payoutRows = <Payout>[];
  final List<String> payrollAsks = <String>[];
  final List<Map<String, dynamic>> payoutsSaved = <Map<String, dynamic>>[];
  final List<int> payoutsDeleted = <int>[];
  final List<Map<String, dynamic>> profilesSaved = <Map<String, dynamic>>[];
  List<StaffProfile> profiles = <StaffProfile>[];
  Object? failPayroll;

  ProfitLoss? pl;
  final List<(DateTime, DateTime)> plAsks = <(DateTime, DateTime)>[];
  Object? failPl;

  @override
  Future<List<SalonExpense>> expenses(DateTime from, DateTime to) async {
    expenseAsks.add((from, to));
    if (failExpenses != null) {
      final Object e = failExpenses!;
      failExpenses = null;
      throw e;
    }
    return expenseRows;
  }

  @override
  Future<SalonExpense> saveExpense({int? id, required String category, required String description, required double amount, required DateTime date, String? supplier, String? paymentMethod}) async {
    saved.add(<String, dynamic>{'id': id, 'category': category, 'description': description, 'amount': amount, 'date': date, 'supplier': supplier, 'method': paymentMethod});
    final SalonExpense made = SalonExpense(id: id ?? 99, category: category, description: description, amount: amount, date: date, status: 'approved', supplier: supplier);
    expenseRows = <SalonExpense>[made, ...expenseRows.where((SalonExpense e) => e.id != made.id)];
    return made;
  }

  @override
  Future<SalonExpense> decideExpense(int id, {required bool approve}) async {
    decided.add((id, approve));
    final SalonExpense e = expenseRows.firstWhere((SalonExpense x) => x.id == id);
    final SalonExpense after = SalonExpense(id: e.id, category: e.category, description: e.description, amount: e.amount, date: e.date, status: approve ? 'approved' : 'rejected');
    expenseRows = <SalonExpense>[for (final SalonExpense x in expenseRows) x.id == id ? after : x];
    return after;
  }

  @override
  Future<SalonExpense> attachReceipt(int id, Uint8List bytes, String filename) async {
    receipts.add((id, filename));
    final SalonExpense e = expenseRows.firstWhere((SalonExpense x) => x.id == id);
    final SalonExpense after = SalonExpense(id: e.id, category: e.category, description: e.description, amount: e.amount, date: e.date, status: e.status, receiptUrl: 'https://example.test/receipt.jpg');
    expenseRows = <SalonExpense>[for (final SalonExpense x in expenseRows) x.id == id ? after : x];
    return after;
  }

  @override
  Future<PayrollReport> payroll(String month) async {
    payrollAsks.add(month);
    if (failPayroll != null) {
      final Object e = failPayroll!;
      failPayroll = null;
      throw e;
    }
    return PayrollReport(month: month, staff: report.staff, salary: report.salary, commissionEarned: report.commissionEarned, owed: report.owed);
  }

  @override
  Future<List<Payout>> payouts(String month) async => payoutRows;

  @override
  Future<void> savePayout({required String staffId, required String kind, required double amount, required DateTime paidOn, required String method, String? periodMonth, String? note}) async {
    payoutsSaved.add(<String, dynamic>{'staff': staffId, 'kind': kind, 'amount': amount, 'method': method, 'period': periodMonth, 'note': note});
  }

  @override
  Future<void> deletePayout(int id) async => payoutsDeleted.add(id);

  @override
  Future<List<StaffProfile>> staffProfiles() async => profiles;

  @override
  Future<void> saveStaffProfile(String staffId, {String? specialization, double? monthlySalary, double? commissionPercent, bool clearCommission = false, List<int>? workDays, String? shiftStart, String? shiftEnd, bool clearHours = false}) async {
    profilesSaved.add(<String, dynamic>{'staff': staffId, 'specialization': specialization, 'salary': monthlySalary, 'rate': commissionPercent, 'clear': clearCommission});
  }

  @override
  Future<ProfitLoss> profitLoss(DateTime from, DateTime to) async {
    plAsks.add((from, to));
    if (failPl != null) {
      final Object e = failPl!;
      failPl = null;
      throw e;
    }
    return pl!;
  }
}

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 's@example.test', role: role, isActive: true, serviceTypes: const <String>['salon']);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

final DateTime _today = DateTime(2026, 10, 15);

Future<void> _host(WidgetTester t, Widget screen, {String role = 'admin', bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(411, 1800), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: screen))),
    ),
  );
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

SalonExpense _exp(int id, String description, double amount, {String category = 'rent', String status = 'approved', String? supplier, String? method, String? receipt, String? by}) => SalonExpense(
      id: id,
      category: category,
      description: description,
      amount: amount,
      date: DateTime(2026, 10, 2),
      status: status,
      supplier: supplier,
      paymentMethod: method,
      receiptUrl: receipt,
      createdByName: by,
    );

void main() {
  group('expenses', () {
    testWidgets('lists what was spent, only approved spending is added up, and waiting ones are counted', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..expenseRows = <SalonExpense>[
          _exp(1, 'Frame rent', 300000, supplier: 'Mama Landlord', method: 'mpesa', by: 'Owner'),
          _exp(2, 'Taxi for supplies', 20000, category: 'transport', status: 'pending', by: 'Helper'),
          _exp(3, 'Bad receipt', 5000, status: 'rejected'),
        ];
      await _host(t, SalonExpensesScreen(api: api, today: _today));

      expect(find.text('TSH 300,000'), findsWidgets, reason: 'the total is only what was approved');
      expect(find.text('Waiting approval'), findsWidgets);
      expect(find.descendant(of: _key('expense_1'), matching: find.text('Rent • 02/10/2026 • Mama Landlord • M-Pesa • Owner')), findsOneWidget);
      expect(find.descendant(of: _key('expense_2'), matching: find.text('Waiting approval')), findsOneWidget);
      expect(find.descendant(of: _key('expense_3'), matching: find.text('Rejected')), findsOneWidget);
    });

    testWidgets('this month is asked first, from the first day to today; last month ends on its last day', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _host(t, SalonExpensesScreen(api: api, today: _today));

      expect(api.expenseAsks.single, (DateTime(2026, 10), DateTime(2026, 10, 15)));
      await t.ensureVisible(find.text('Last month'));
      await t.tap(find.text('Last month'));
      await _settle(t);
      expect(api.expenseAsks.last, (DateTime(2026, 9), DateTime(2026, 9, 30)));
      await t.ensureVisible(find.text('This week'));
      await t.tap(find.text('This week'));
      await _settle(t);
      expect(api.expenseAsks.last, (DateTime(2026, 10, 12), DateTime(2026, 10, 15)), reason: 'Monday to today');
      await t.ensureVisible(find.text('Today'));
      await t.tap(find.text('Today'));
      await _settle(t);
      expect(api.expenseAsks.last, (DateTime(2026, 10, 15), DateTime(2026, 10, 15)));
    });

    testWidgets('the owner sees approve and reject on waiting spending, a stylist does not', (t) async {
      final _FakeSalon api = _FakeSalon()..expenseRows = <SalonExpense>[_exp(2, 'Taxi', 20000, category: 'transport', status: 'pending')];
      await _host(t, SalonExpensesScreen(api: api, today: _today), role: 'sales_officer');
      expect(_key('expense_approve_2'), findsNothing);
      expect(_key('expense_reject_2'), findsNothing);
    });

    testWidgets('approving sends the decision and the list then says approved', (t) async {
      final _FakeSalon api = _FakeSalon()..expenseRows = <SalonExpense>[_exp(2, 'Taxi', 20000, category: 'transport', status: 'pending')];
      await _host(t, SalonExpensesScreen(api: api, today: _today));

      await t.tap(_key('expense_approve_2'));
      await _settle(t);

      expect(api.decided, <(int, bool)>[(2, true)]);
      expect(_key('expense_approve_2'), findsNothing);
      expect(find.text('Waiting approval'), findsWidgets, reason: 'the tile still names the counter');
      expect(find.descendant(of: _key('expense_2'), matching: find.text('Waiting approval')), findsNothing);
    });

    testWidgets('rejecting sends the other decision', (t) async {
      final _FakeSalon api = _FakeSalon()..expenseRows = <SalonExpense>[_exp(2, 'Taxi', 20000, category: 'transport', status: 'pending')];
      await _host(t, SalonExpensesScreen(api: api, today: _today));

      await t.tap(_key('expense_reject_2'));
      await _settle(t);

      expect(api.decided, <(int, bool)>[(2, false)]);
      expect(find.descendant(of: _key('expense_2'), matching: find.text('Rejected')), findsOneWidget);
    });

    testWidgets('recording one needs what it was for and an amount, then sends everything', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _host(t, SalonExpensesScreen(api: api, today: _today));
      await t.tap(_key('expense_add'));
      await _settle(t);

      await t.tap(_key('expense_save'));
      await _settle(t);
      expect(find.text('Say what it was for.'), findsOneWidget);
      await t.enterText(_key('expense_description'), 'Shampoo and gel');
      await t.tap(_key('expense_save'));
      await _settle(t);
      expect(find.text('Write the amount.'), findsOneWidget);
      expect(api.saved, isEmpty);

      await t.tap(_key('expense_cat_supplies'));
      await t.enterText(_key('expense_amount'), '45000');
      await t.enterText(_key('expense_supplier'), 'Beauty Wholesale');
      await t.tap(_key('expense_method_airtel_money'));
      await t.pump();
      await t.tap(_key('expense_save'));
      await _settle(t);

      expect(api.saved.single, <String, dynamic>{'id': null, 'category': 'supplies', 'description': 'Shampoo and gel', 'amount': 45000.0, 'date': _today, 'supplier': 'Beauty Wholesale', 'method': 'airtel_money'});
      expect(find.text('Shampoo and gel'), findsOneWidget, reason: 'the list was reloaded');
    });

    testWidgets('editing one keeps its id and fills the form in', (t) async {
      final _FakeSalon api = _FakeSalon()..expenseRows = <SalonExpense>[_exp(1, 'Frame rent', 300000, supplier: 'Mama Landlord', method: 'mpesa')];
      await _host(t, SalonExpensesScreen(api: api, today: _today));

      await t.tap(_key('expense_edit_1'));
      await _settle(t);
      expect(find.text('Edit expense'), findsOneWidget);
      expect(t.widget<InvTextField>(_key('expense_description')).controller.text, 'Frame rent');
      expect(t.widget<InvTextField>(_key('expense_amount')).controller.text, '300,000');
      await t.enterText(_key('expense_amount'), '320000');
      await t.tap(_key('expense_save'));
      await _settle(t);

      expect(api.saved.single['id'], 1);
      expect(api.saved.single['amount'], 320000.0);
      expect(api.saved.single['method'], 'mpesa');
    });

    testWidgets('a receipt photo is attached from the picker and then shown as a link', (t) async {
      final _FakeSalon api = _FakeSalon()..expenseRows = <SalonExpense>[_exp(1, 'Frame rent', 300000)];
      await _host(t, SalonExpensesScreen(api: api, today: _today, pickReceipt: () async => (Uint8List.fromList(<int>[1, 2, 3]), 'r.jpg')));

      await t.tap(_key('expense_attach_1'));
      await _settle(t);

      expect(api.receipts, <(int, String)>[(1, 'r.jpg')]);
      expect(_key('expense_receipt_1'), findsOneWidget);
      expect(_key('expense_attach_1'), findsNothing);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('choosing no photo sends nothing', (t) async {
      final _FakeSalon api = _FakeSalon()..expenseRows = <SalonExpense>[_exp(1, 'Frame rent', 300000)];
      await _host(t, SalonExpensesScreen(api: api, today: _today, pickReceipt: () async => null));

      await t.tap(_key('expense_attach_1'));
      await _settle(t);

      expect(api.receipts, isEmpty);
    });

    testWidgets('an empty period says so, and a failed load says why and can be retried', (t) async {
      final _FakeSalon api = _FakeSalon()..failExpenses = ApiException('Server is down');
      await _host(t, SalonExpensesScreen(api: api, today: _today));
      expect(find.text('Server is down'), findsOneWidget);

      await t.tap(_key('expense_retry'));
      await _settle(t);
      expect(find.text('No expenses in this period.'), findsOneWidget);
    });

    testWidgets('in Swahili the page is Swahili', (t) async {
      final _FakeSalon api = _FakeSalon()..expenseRows = <SalonExpense>[_exp(1, 'Frame rent', 300000)];
      await _host(t, SalonExpensesScreen(api: api, today: _today), sw: true);

      expect(find.text('Andika matumizi'), findsOneWidget);
      expect(find.text('Wiki hii'), findsOneWidget);
      expect(find.text('Ongeza picha ya risiti'), findsOneWidget);
      expect(find.textContaining('Kodi ya fremu'), findsOneWidget);
    });
  });

  group('payroll', () {
    PayrollReport report() => const PayrollReport(
          month: '2026-10',
          staff: <PayrollRow>[
            PayrollRow(staffId: 'u-asha', name: 'Asha', salary: 100000, commissionEarned: 16000, salaryPaid: 0, commissionPaid: 10000, advances: 30000, owed: 76000),
            PayrollRow(staffId: 'u-bahati', name: 'Bahati', salary: 0, commissionEarned: 0, salaryPaid: 0, commissionPaid: 0, advances: 0, owed: 0),
          ],
          salary: 100000,
          commissionEarned: 16000,
          owed: 76000,
        );

    testWidgets('shows each person\'s month and what is still owed', (t) async {
      final _FakeSalon api = _FakeSalon()..report = report();
      await _host(t, PayrollScreen(api: api, today: _today));

      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('TSH 76,000'), findsWidgets);
      expect(find.text('Owed TSH 76,000'), findsOneWidget);
      expect(find.text('Nothing owed'), findsOneWidget);
      expect(find.descendant(of: _key('payroll_u-asha'), matching: find.text('TSH 10,000')), findsOneWidget, reason: 'paid so far');
      expect(find.descendant(of: _key('payroll_u-asha'), matching: find.text('TSH 30,000')), findsOneWidget, reason: 'advance');
    });

    testWidgets('the arrows move to the month before and after', (t) async {
      final _FakeSalon api = _FakeSalon()..report = report();
      await _host(t, PayrollScreen(api: api, today: DateTime(2026, 1, 10)));
      expect(api.payrollAsks.last, '2026-01');

      await t.tap(_key('payroll_prev'));
      await _settle(t);
      expect(api.payrollAsks.last, '2025-12');
      expect(find.text('December 2025'), findsOneWidget);
      await t.tap(_key('payroll_next'));
      await t.tap(_key('payroll_next'));
      await _settle(t);
      expect(api.payrollAsks.last, '2026-02');
    });

    testWidgets('paying opens with what is owed filled in and sends a salary payment for this month', (t) async {
      final _FakeSalon api = _FakeSalon()..report = report();
      await _host(t, PayrollScreen(api: api, today: _today));

      await t.tap(_key('payroll_pay_u-asha'));
      await _settle(t);
      expect(t.widget<InvTextField>(_key('payout_amount')).controller.text, '76,000');
      await t.enterText(_key('payout_amount'), '70000');
      await t.tap(_key('payout_method_mpesa'));
      await t.enterText(_key('payout_note'), 'October pay');
      await t.pump();
      await t.tap(_key('payout_save'));
      await _settle(t);

      expect(api.payoutsSaved.single, <String, dynamic>{'staff': 'u-asha', 'kind': 'salary', 'amount': 70000.0, 'method': 'mpesa', 'period': '2026-10', 'note': 'October pay'});
    });

    testWidgets('an advance does not name a month: it counts against the month it was given in', (t) async {
      final _FakeSalon api = _FakeSalon()..report = report();
      await _host(t, PayrollScreen(api: api, today: _today));

      await t.tap(_key('payroll_pay_u-bahati'));
      await _settle(t);
      expect(t.widget<InvTextField>(_key('payout_amount')).controller.text, '', reason: 'nothing owed, nothing filled in');
      await t.tap(_key('payout_kind_advance'));
      await t.enterText(_key('payout_amount'), '5000');
      await t.pump();
      await t.tap(_key('payout_save'));
      await _settle(t);

      expect(api.payoutsSaved.single['kind'], 'advance');
      expect(api.payoutsSaved.single['period'], isNull);
    });

    testWidgets('a payment needs an amount', (t) async {
      final _FakeSalon api = _FakeSalon()..report = report();
      await _host(t, PayrollScreen(api: api, today: _today));

      await t.tap(_key('payroll_pay_u-bahati'));
      await _settle(t);
      await t.tap(_key('payout_save'));
      await _settle(t);

      expect(find.text('Write the amount.'), findsOneWidget);
      expect(api.payoutsSaved, isEmpty);
    });

    testWidgets('the sheet for a person loads their profile and saves salary, specialization and own rate', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..report = report()
        ..profiles = const <StaffProfile>[StaffProfile(staffId: 'u-asha', name: 'Asha', role: 'sales_officer', monthlySalary: 100000, specialization: 'Hair stylist', commissionPercent: 5)];
      await _host(t, PayrollScreen(api: api, today: _today));

      await t.tap(_key('payroll_profile_u-asha'));
      await _settle(t);
      expect(t.widget<InvTextField>(_key('profile_specialization')).controller.text, 'Hair stylist');
      expect(t.widget<InvTextField>(_key('profile_salary')).controller.text, '100,000');
      expect(t.widget<InvTextField>(_key('profile_rate')).controller.text, '5');

      await t.enterText(_key('profile_salary'), '120000');
      await t.enterText(_key('profile_rate'), '');
      await t.tap(_key('profile_save'));
      await _settle(t);

      expect(api.profilesSaved.single, <String, dynamic>{'staff': 'u-asha', 'specialization': 'Hair stylist', 'salary': 120000.0, 'rate': null, 'clear': true});
    });

    testWidgets('a commission above 100 is refused', (t) async {
      final _FakeSalon api = _FakeSalon()..report = report();
      await _host(t, PayrollScreen(api: api, today: _today));
      await t.tap(_key('payroll_profile_u-asha'));
      await _settle(t);

      await t.enterText(_key('profile_rate'), '150');
      await t.tap(_key('profile_save'));
      await _settle(t);

      expect(find.text('The commission must be between 0 and 100 percent.'), findsOneWidget);
      expect(api.profilesSaved, isEmpty);
    });

    testWidgets('payments of the month are listed and one can be taken back after asking', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..report = report()
        ..payoutRows = <Payout>[Payout(id: 7, staffId: 'u-asha', staffName: 'Asha', kind: 'advance', amount: 30000, paidOn: DateTime(2026, 10, 3), periodMonth: '2026-10', method: 'cash', note: 'School fees')];
      await _host(t, PayrollScreen(api: api, today: _today));

      expect(find.text('Asha • Salary advance'), findsOneWidget);
      expect(find.text('03/10/2026 • Cash • School fees'), findsOneWidget);
      await t.tap(_key('payout_remove_7'));
      await _settle(t);
      await t.tap(_key('payout_delete_no'));
      await _settle(t);
      expect(api.payoutsDeleted, isEmpty);

      await t.tap(_key('payout_remove_7'));
      await _settle(t);
      await t.tap(_key('payout_delete_yes'));
      await _settle(t);
      expect(api.payoutsDeleted, <int>[7]);
    });

    testWidgets('a failed load says why and can be retried; Swahili is Swahili', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..report = report()
        ..failPayroll = ApiException('Server is down');
      await _host(t, PayrollScreen(api: api, today: _today), sw: true);
      expect(find.text('Server is down'), findsOneWidget);

      await t.tap(_key('payroll_retry'));
      await _settle(t);
      expect(find.text('Oktoba 2026'), findsOneWidget);
      expect(find.text('Anadaiwa TSH 76,000'), findsOneWidget);
      expect(find.text('Hadaiwi kitu'), findsOneWidget);
    });
  });

  group('profit and loss', () {
    ProfitLoss data({double net = 51000, double discounts = 10000, double outstanding = 20000, int cancelled = 1}) => ProfitLoss(
          from: DateTime(2026, 10),
          to: DateTime(2026, 10, 15),
          serviceRevenue: 110000,
          goodsRevenue: 16000,
          revenue: 126000,
          discounts: discounts,
          costOfGoods: 8000,
          grossProfit: 118000,
          expenses: 30000,
          expensesByCategory: const <ExpenseGroup>[ExpenseGroup(category: 'rent', total: 30000, count: 1)],
          commissions: 12000,
          salaries: 25000,
          operatingCosts: 67000,
          netProfit: net,
          collections: const <Collection>[Collection(method: 'mpesa', amount: 90000), Collection(method: 'cash', amount: 16000)],
          collected: 106000,
          outstanding: outstanding,
          cancelledCount: cancelled,
          cancelledTotal: 80000,
          sales: 3,
          clients: 1,
        );

    testWidgets('lays the month out line by line down to the net profit', (t) async {
      final _FakeSalon api = _FakeSalon()..pl = data();
      await _host(t, ProfitLossScreen(api: api, today: _today));

      expect(api.plAsks.single, (DateTime(2026, 10), DateTime(2026, 10, 15)));
      expect(find.descendant(of: _key('pl_service_revenue'), matching: find.text('TSH 110,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_goods_revenue'), matching: find.text('TSH 16,000')), findsOneWidget);
      expect(find.text('(after TSH 10,000 of discounts)'), findsOneWidget);
      expect(find.descendant(of: _key('pl_cogs'), matching: find.text('− TSH 8,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_gross'), matching: find.text('TSH 118,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_exp_rent'), matching: find.text('− TSH 30,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_commissions'), matching: find.text('− TSH 12,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_salaries'), matching: find.text('− TSH 25,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_net'), matching: find.text('TSH 51,000')), findsOneWidget);
      expect(find.text('Net profit'), findsOneWidget);
    });

    testWidgets('money received is by how it was paid, apart from revenue, with what clients still owe', (t) async {
      final _FakeSalon api = _FakeSalon()..pl = data();
      await _host(t, ProfitLossScreen(api: api, today: _today));

      expect(find.descendant(of: _key('pl_col_mpesa'), matching: find.text('TSH 90,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_col_cash'), matching: find.text('TSH 16,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_collected'), matching: find.text('TSH 106,000')), findsOneWidget);
      expect(find.descendant(of: _key('pl_outstanding'), matching: find.text('TSH 20,000')), findsOneWidget);
      expect(find.text('1 clients • 3 sales • 1 cancelled (TSH 80,000)'), findsOneWidget);
    });

    testWidgets('a loss is called a loss', (t) async {
      final _FakeSalon api = _FakeSalon()..pl = data(net: -4000, discounts: 0, outstanding: 0, cancelled: 0);
      await _host(t, ProfitLossScreen(api: api, today: _today));

      expect(find.text('Net loss'), findsOneWidget);
      expect(find.text('Loss'), findsOneWidget);
      expect(find.descendant(of: _key('pl_net'), matching: find.text('− TSH 4,000')), findsOneWidget);
      expect(find.textContaining('of discounts'), findsNothing);
      expect(find.textContaining('cancelled'), findsNothing);
    });

    testWidgets('the period chips ask for today, this week, this month and this year', (t) async {
      final _FakeSalon api = _FakeSalon()..pl = data();
      await _host(t, ProfitLossScreen(api: api, today: _today));

      await t.ensureVisible(find.text('This year'));
      await t.tap(find.text('This year'));
      await _settle(t);
      expect(api.plAsks.last, (DateTime(2026), DateTime(2026, 10, 15)));
      await t.ensureVisible(find.text('This week'));
      await t.tap(find.text('This week'));
      await _settle(t);
      expect(api.plAsks.last, (DateTime(2026, 10, 12), DateTime(2026, 10, 15)));
      await t.ensureVisible(find.text('Today'));
      await t.tap(find.text('Today'));
      await _settle(t);
      expect(api.plAsks.last, (DateTime(2026, 10, 15), DateTime(2026, 10, 15)));
    });

    testWidgets('a failed load says why and can be retried; Swahili is Swahili', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..pl = data()
        ..failPl = ApiException('Server is down');
      await _host(t, ProfitLossScreen(api: api, today: _today), sw: true);
      expect(find.text('Server is down'), findsOneWidget);

      await t.tap(_key('pl_retry'));
      await _settle(t);
      expect(find.text('Mapato'), findsOneWidget);
      expect(find.text('Faida halisi'), findsOneWidget);
      expect(find.text('Pesa zilizopokelewa'), findsOneWidget);
      expect(find.text('Madeni ya wateja'), findsOneWidget);
    });
  });
}
