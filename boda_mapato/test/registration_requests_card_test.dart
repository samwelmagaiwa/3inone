import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/admin/registrations_screen.dart';
import 'package:boda_mapato/screens/service_selection_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/widgets/pending_registrations_count.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The super admin sees, the moment they sign in, how many businesses are waiting to be let in, and one tap
/// opens them. Nobody else sees the card.

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 'someone@example.test', role: role, isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

BusinessRegistration _reg(String id) => BusinessRegistration.fromJson(<String, dynamic>{
      'id': id,
      'status': 'pending',
      'business_name': 'Asha Rentals',
      'requested_services': <String>['rental'],
      'assigned_services': <String>[],
      'user': <String, dynamic>{'id': 'u-$id', 'name': 'Asha Owner', 'email': 'a@example.test', 'phone_number': '0743519100', 'phone_verified': true},
    });

class _Source implements RegistrationsDataSource {
  _Source(this.pending, {this.fails = false});

  int pending;
  bool fails;
  int loads = 0;

  @override
  Future<RegistrationsPage> load(String status, {String? query}) async {
    loads++;
    if (fails) throw Exception('no connection');
    return RegistrationsPage(
      items: status == 'pending' ? List<BusinessRegistration>.generate(pending, (int i) => _reg('r$i')) : <BusinessRegistration>[],
      counts: <String, int>{'pending': pending, 'approved': 0, 'rejected': 0},
    );
  }

  @override
  Future<void> approve(String id, List<String> services,
      {bool allowUnverified = false, String? plan, DateTime? validUntil, String? inventoryType}) async {
    pending = 0;
  }

  @override
  Future<void> reject(String id, String reason) async {}
}

Future<void> _open(WidgetTester t, {required String role, required _Source source, bool withAuth = true}) async {
  t.view.physicalSize = const Size(411, 860);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await LocalizationService.instance.changeLanguage('en');
  Widget app = ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    builder: (_, __) => MaterialApp(
      home: ServiceSelectionScreen(allowedServices: const <String>['inventory', 'rental', 'transport'], registrationsSource: source),
    ),
  );
  app = MultiProvider(
    providers: <ChangeNotifierProvider<ChangeNotifier>>[
      ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      if (withAuth) ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
    ],
    child: app,
  );
  await t.pumpWidget(app);
  await t.pump();
  await t.pump();
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => LocalizationService.instance.changeLanguage('sw'));

  group('Select Service for a super admin', () {
    testWidgets('shows how many registrations are waiting', (t) async {
      await _open(t, role: 'super_admin', source: _Source(3));

      expect(_key('registration_requests_card'), findsOneWidget);
      expect(find.text('Registration requests'), findsOneWidget);
      expect(find.text('3 waiting for approval'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('count_badge')), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'the badge');
    });

    testWidgets('says plainly when nothing is waiting, with no badge', (t) async {
      await _open(t, role: 'super_admin', source: _Source(0));

      expect(find.text('No requests waiting'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('count_badge')), findsNothing);
      expect(_key('registration_requests_card'), findsOneWidget, reason: 'the list stays one tap away');
    });

    testWidgets('a failed count never shows a wrong number', (t) async {
      await _open(t, role: 'super_admin', source: _Source(5, fails: true));

      expect(find.byKey(const ValueKey<String>('count_badge')), findsNothing);
      expect(find.textContaining('waiting for approval'), findsNothing);
    });

    testWidgets('one tap opens the list on the Pending tab, and the count is fresh when coming back', (t) async {
      final _Source source = _Source(1);
      await _open(t, role: 'super_admin', source: source);

      await t.tap(_key('registration_requests_card'));
      await t.pumpAndSettle();

      expect(find.byType(RegistrationsScreen), findsOneWidget);
      expect(find.text('Asha Rentals'), findsOneWidget, reason: 'the waiting request is listed');
      expect(find.text('Pending (1)'), findsOneWidget);

      // approve it with one tap, then go back
      await t.tap(find.byKey(const ValueKey<String>('approve_as_requested_r0')));
      await t.pumpAndSettle();
      await t.tap(_key('approve_as_requested_confirm'));
      await t.pumpAndSettle();
      expect(source.pending, 0);

      t.state<NavigatorState>(find.byType(Navigator).first).pop();
      await t.pumpAndSettle();

      expect(find.text('No requests waiting'), findsOneWidget, reason: 'the card asked again when the list closed');
      await t.pump(const Duration(seconds: 4)); // the success banner removes itself
    });
  });

  group('everyone else', () {
    for (final String role in <String>['admin', 'manager', 'operator']) {
      testWidgets('a $role does not see the card', (t) async {
        final _Source source = _Source(2);
        await _open(t, role: role, source: source);

        expect(_key('registration_requests_card'), findsNothing);
        expect(source.loads, 0, reason: 'nothing is even asked of the server');
      });
    }

    testWidgets('without a signed-in user the screen still works and shows no card', (t) async {
      await _open(t, role: 'admin', source: _Source(2), withAuth: false);

      expect(_key('registration_requests_card'), findsNothing);
      expect(find.byIcon(Icons.inventory_2_rounded), findsOneWidget);
    });
  });

  group('the count badge', () {
    testWidgets('shows the number, 99+ when large, and nothing for zero or unknown', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: <Widget>[
        CountBadge(count: 4),
        CountBadge(count: 250),
        CountBadge(count: 0),
        CountBadge(count: null),
      ]))));

      expect(find.text('4'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('count_badge')), findsNWidgets(2));
    });

    testWidgets('PendingRegistrationsCount hands over null until it knows, then the number', (t) async {
      final List<int?> seen = <int?>[];
      await t.pumpWidget(MaterialApp(
        home: PendingRegistrationsCount(
          source: _Source(7),
          builder: (BuildContext context, int? pending) {
            seen.add(pending);
            return Text('n=$pending');
          },
        ),
      ));
      await t.pump();

      expect(seen.first, isNull);
      expect(find.text('n=7'), findsOneWidget);
    });
  });
}
