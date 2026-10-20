import 'package:boda_mapato/modules/inventory/screens/salon/equipment_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/feedback_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSalon extends SalonApi {
  Map<String, dynamic> eq = <String, dynamic>{
    'equipment': <Map<String, dynamic>>[
      <String, dynamic>{'id': 1, 'name': 'Hood dryer', 'kind': 'dryer', 'cost': 400000, 'status': 'working', 'next_service_on': '2026-01-01', 'overdue': true, 'due_soon': false, 'spent_on_upkeep': 20000},
      <String, dynamic>{'id': 2, 'name': 'Old chair', 'status': 'retired', 'cost': 0, 'overdue': false, 'due_soon': false, 'spent_on_upkeep': 0},
    ],
    'totals': <String, dynamic>{'count': 1, 'value': 400000, 'in_repair': 0, 'needs_attention': 1},
  };
  final List<Map<String, dynamic>> saves = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> logs = <Map<String, dynamic>>[];
  final List<int> resolved = <int>[];
  String? resolvedNote;

  Map<String, dynamic> fb = <String, dynamic>{
    'summary': <String, dynamic>{
      'average': 4.5,
      'ratings': 2,
      'open_complaints': 1,
      'by_staff': <Map<String, dynamic>>[<String, dynamic>{'name': 'Asha', 'average': 4.5, 'ratings': 2}],
    },
    'feedback': <Map<String, dynamic>>[
      <String, dynamic>{'id': 7, 'kind': 'complaint', 'rating': 1, 'message': 'Waited long', 'client': 'Neema', 'status': 'new', 'at': '2026-10-20 10:00'},
      <String, dynamic>{'id': 8, 'kind': 'review', 'rating': 5, 'message': 'Lovely', 'status': 'resolved', 'at': '2026-10-19 10:00'},
    ],
  };

  @override
  Future<Map<String, dynamic>> equipment() async => eq;

  @override
  Future<List<Map<String, dynamic>>> equipmentLogs(int id) async => <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'kind': 'repair', 'done_on': '2026-09-01', 'cost': 35000, 'description': 'New heating element'},
      ];

  @override
  Future<void> saveEquipment(Map<String, dynamic> body, {int? id}) async => saves.add(<String, dynamic>{...body, 'id': id});

  @override
  Future<void> addEquipmentLog(int id, Map<String, dynamic> body) async => logs.add(<String, dynamic>{...body, 'id': id});

  @override
  Future<Map<String, dynamic>> feedback({String? status}) async => fb;

  @override
  Future<void> resolveFeedback(int id, {String? note}) async {
    resolved.add(id);
    resolvedNote = note;
  }
}

Future<void> _pump(WidgetTester t, Widget screen) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  await t.pumpWidget(ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance, child: MaterialApp(home: screen)));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('equipment shows totals, flags overdue and adds a piece', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, EquipmentScreen(api: api));
    expect(find.text('Hood dryer'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('TSH 400,000'), findsOneWidget);

    await t.tap(find.byKey(const Key('eq_add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('eq_save')));
    await t.pump();
    expect(find.text('Enter a name.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('eq_name')), 'Steamer');
    await t.enterText(find.byKey(const Key('eq_cost')), '90000');
    await t.enterText(find.byKey(const Key('eq_next')), 'soon');
    await t.tap(find.byKey(const Key('eq_save')));
    await t.pump();
    expect(find.textContaining('year-month-day'), findsOneWidget);
    await t.enterText(find.byKey(const Key('eq_next')), '2026-12-31');
    await t.tap(find.byKey(const Key('eq_save')));
    await t.pumpAndSettle();
    expect(api.saves.single['name'], 'Steamer');
    expect(api.saves.single['cost'], 90000);
    expect(api.saves.single['next_service_on'], '2026-12-31');
  });

  testWidgets('a repair is recorded with its cost and the piece can be retired', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, EquipmentScreen(api: api));
    await t.tap(find.text('Hood dryer'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('eq_log')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('log_save')));
    await t.pump();
    expect(find.text('Say what was done.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('log_what')), 'New heating element');
    await t.enterText(find.byKey(const Key('log_cost')), '35000');
    await t.tap(find.byKey(const Key('log_save')));
    await t.pumpAndSettle();
    expect(api.logs.single['description'], 'New heating element');
    expect(api.logs.single['cost'], 35000);
    expect(api.logs.single['id'], 1);

    await t.tap(find.text('Hood dryer'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('eq_retire')));
    await t.pumpAndSettle();
    expect(api.saves.last['status'], 'retired');
  });

  testWidgets('the service history of a piece lists what was done and what it cost', (WidgetTester t) async {
    await _pump(t, EquipmentScreen(api: _FakeSalon()));
    await t.tap(find.text('Hood dryer'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('eq_history')));
    await t.pumpAndSettle();
    expect(find.text('New heating element'), findsOneWidget);
    expect(find.text('TSH 35,000'), findsOneWidget);
  });

  testWidgets('feedback shows the average, the stylists and resolves a complaint with a note', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, FeedbackScreen(api: api));
    expect(find.text('4.5 ★'), findsOneWidget);
    expect(find.text('Waited long'), findsNothing); // inside the subtitle with other lines
    expect(find.textContaining('Waited long'), findsOneWidget);
    expect(find.byKey(const Key('fb_resolve_8')), findsNothing);

    await t.tap(find.byKey(const Key('fb_resolve_7')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('fb_note')), 'Called and apologised');
    await t.tap(find.byKey(const Key('fb_resolve_save')));
    await t.pumpAndSettle();
    expect(api.resolved, <int>[7]);
    expect(api.resolvedNote, 'Called and apologised');
  });
}
