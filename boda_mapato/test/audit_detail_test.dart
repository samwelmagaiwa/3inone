import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/screens/settings/audit_detail_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The audit trail says what a change was: old next to new for every field, who did it and when, and what else that person did.
InvAuditEntry _entry(
        {int id = 1,
        String type = 'product',
        String action = 'updated',
        Map<String, dynamic>? before,
        Map<String, dynamic>? after,
        String user = 'Julius',
        String userId = 'u-1',
        String summary = 'Soda'}) =>
    InvAuditEntry.fromJson(<String, dynamic>{
      'id': id,
      'entity_type': type,
      'entity_id': 7,
      'action': action,
      'summary': summary,
      'user_name': user,
      'user_id': userId,
      'created_at': '2026-10-31T05:25:09Z',
      'before': before,
      'after': after,
    });

Future<void> _open(WidgetTester t, InvAuditEntry e,
    {List<InvAuditEntry> activity = const <InvAuditEntry>[],
    bool sw = false,
    List<String>? asked}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: AuditDetailScreen(
            entry: e,
            loadActivity: (String id) async {
              asked?.add(id);

              return activity;
            },
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

Finder _k(String k) => find.byKey(Key(k));

void main() {
  group('what changed', () {
    test(
        'an update lists only the fields that differ, old next to new, and leaves bookkeeping out',
        () {
      final InvAuditEntry e = _entry(
        before: <String, dynamic>{
          'name': 'Soda',
          'selling_price': 500,
          'updated_at': '2026-10-01',
          'min_stock': 3
        },
        after: <String, dynamic>{
          'name': 'Soda',
          'selling_price': 650,
          'updated_at': '2026-10-31',
          'min_stock': '3'
        },
      );

      expect(e.changes, hasLength(1),
          reason:
              'the name is the same, 3 and "3" are the same, updated_at is noise');
      expect(e.changes.single.field, 'selling_price');
      expect(e.changes.single.before, '500');
      expect(e.changes.single.after, '650');
    });

    test('a field that was empty and is now filled shows an empty old value',
        () {
      final InvAuditEntry e = _entry(
          before: <String, dynamic>{'phone': null},
          after: <String, dynamic>{'phone': '0711000001'});

      expect(e.changes.single.before, isNull);
      expect(e.changes.single.after, '0711000001');
    });

    test(
        'a creation lists everything the record has, a removal everything it had',
        () {
      final InvAuditEntry made = _entry(
          action: 'created',
          after: <String, dynamic>{'name': 'Soda', 'price': 500});
      final InvAuditEntry gone = _entry(
          action: 'removed_for_good',
          before: <String, dynamic>{'name': 'Soda', 'price': 500});

      expect(made.changes.map((AuditChange c) => c.field),
          <String>['name', 'price']);
      expect(made.changes.first.before, isNull);
      expect(gone.changes.first.before, 'Soda');
      expect(gone.changes.first.after, isNull);
    });

    test('before and after may arrive as JSON text from an older server', () {
      final InvAuditEntry e = InvAuditEntry.fromJson(<String, dynamic>{
        'id': 1,
        'entity_type': 'settings',
        'action': 'updated',
        'created_at': '2026-10-31 05:25:09',
        'before': '{"depot_name":"A"}',
        'after': '{"depot_name":"B"}',
      });

      expect(e.changes.single.before, 'A');
      expect(e.changes.single.after, 'B');
    });

    test('an entry with nothing kept has no changes and no crash', () {
      expect(_entry().changes, isEmpty);
      expect(
          InvAuditEntry.fromJson(
                  <String, dynamic>{'id': 1, 'before': 'not json', 'after': 5})
              .changes,
          isEmpty);
    });

    test('the row line says old to new, with how many more', () {
      final InvAuditEntry e = _entry(
        before: <String, dynamic>{'a': 1, 'b': 2, 'c': 3},
        after: <String, dynamic>{'a': 9, 'b': 8, 'c': 7},
      );

      expect(auditChangesLine(LocalizationService.instance, e),
          'A: 1 → 9  •  B: 2 → 8  +1');
    });
  });

  group('the details page', () {
    testWidgets(
        'shows when, who, the record, and the old and new value of each changed field',
        (t) async {
      await _open(
          t,
          _entry(
              before: <String, dynamic>{'selling_price': 500, 'name': 'Soda'},
              after: <String, dynamic>{'selling_price': 650, 'name': 'Soda'}));

      expect(find.text('product · updated'), findsOneWidget);
      expect(
          find.descendant(of: _k('audit_who'), matching: find.text('Julius')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _k('audit_record'), matching: find.text('#7  ·  Soda')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _k('audit_when'),
              matching: find.textContaining('31/10/2026')),
          findsOneWidget);
      expect(_k('audit_change_selling_price'), findsOneWidget);
      expect(_k('audit_change_name'), findsNothing, reason: 'unchanged');
      expect(
          find.descendant(
              of: _k('audit_change_selling_price'), matching: find.text('500')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _k('audit_change_selling_price'), matching: find.text('650')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _k('audit_change_selling_price'),
              matching: find.text('Before')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _k('audit_change_selling_price'),
              matching: find.text('After')),
          findsOneWidget);
    });

    testWidgets('an empty value is said to be empty', (t) async {
      await _open(
          t,
          _entry(
              before: <String, dynamic>{'phone': null},
              after: <String, dynamic>{'phone': '0711'}));

      expect(
          find.descendant(
              of: _k('audit_change_phone'), matching: find.text('(empty)')),
          findsOneWidget);
    });

    testWidgets('an entry with no detail says so', (t) async {
      await _open(t, _entry());

      expect(_k('audit_no_changes'), findsOneWidget);
    });

    testWidgets(
        'a creation shows the details of the new record, not before and after',
        (t) async {
      await _open(t,
          _entry(action: 'created', after: <String, dynamic>{'name': 'Soda'}));

      expect(find.text('Details of the new record'), findsOneWidget);
      expect(find.text('Before'), findsNothing);
      expect(find.text('Soda'), findsWidgets);
    });

    testWidgets(
        'it lists the latest other things the same person did and opens one',
        (t) async {
      final List<String> asked = <String>[];
      final InvAuditEntry other = _entry(
          id: 2,
          type: 'customer',
          action: 'trashed',
          before: <String, dynamic>{'name': 'Mama Neema'},
          after: <String, dynamic>{'deleted_at': '2026-10-31'},
          summary: 'Mama Neema');
      await _open(t, _entry(),
          activity: <InvAuditEntry>[_entry(), other], asked: asked);

      expect(asked, <String>['u-1'], reason: 'asked by the person who did it');
      expect(find.text('More by Julius'), findsOneWidget);
      expect(_k('audit_activity_1'), findsNothing,
          reason: 'this entry itself is not listed again');
      expect(_k('audit_activity_2'), findsOneWidget);
      expect(find.text('customer · moved to trash'), findsOneWidget);

      await t.tap(_k('audit_activity_2'));
      await t.pumpAndSettle();

      expect(find.text('Activity details'), findsOneWidget);
      expect(find.text('customer · moved to trash'), findsWidgets);
    });

    testWidgets(
        'no other activity says so, and an entry with no person asks nobody',
        (t) async {
      final List<String> asked = <String>[];
      await _open(t, _entry(userId: '', user: ''), asked: asked);

      expect(asked, isEmpty);
      expect(_k('audit_nothing_else'), findsOneWidget);
    });

    testWidgets('in Swahili the page is Swahili', (t) async {
      await _open(
          t,
          _entry(
              before: <String, dynamic>{'price': 1},
              after: <String, dynamic>{'price': 2}),
          sw: true);

      expect(find.text('Maelezo ya tukio'), findsOneWidget);
      expect(find.text('product · imebadilishwa'), findsOneWidget);
      expect(find.text('Kilichobadilika'), findsOneWidget);
      expect(find.text('Kabla'), findsOneWidget);
      expect(find.text('Baada'), findsOneWidget);
    });
  });
}
