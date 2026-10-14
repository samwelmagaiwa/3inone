import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/screens/admin/registrations_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

BusinessRegistration _reg(
  String id, {
  String business = 'Asha Rentals',
  String status = 'pending',
  List<String> requested = const <String>['rental', 'transport'],
  List<String> assigned = const <String>[],
  String? reason,
  bool phoneVerified = true,
  String? inventoryType,
  String? plan,
  int? months,
  double? price,
}) =>
    BusinessRegistration.fromJson(<String, dynamic>{
      'id': id,
      'status': status,
      'business_name': business,
      'requested_services': requested,
      'assigned_services': assigned,
      'requested_plan': plan,
      'requested_months': months,
      'requested_price': price,
      'inventory_type': inventoryType,
      'region': 'Dar es Salaam',
      'district': 'Kinondoni',
      'address': 'Mikocheni B',
      'id_number': '1990-0001',
      'notes': 'Two apartment blocks',
      'submitted_at': '2026-10-11T08:30:00.000000Z',
      'rejection_reason': reason,
      'user': <String, dynamic>{
        'id': 'u-$id',
        'name': 'Asha Owner',
        'email': 'asha@example.test',
        'phone_number': '0743519100',
        'phone_verified': phoneVerified,
      },
    });

/// A scripted backend: what each status returns, and a record of every call.
class _FakeSource implements RegistrationsDataSource {
  _FakeSource(this.pages);

  Map<String, RegistrationsPage> pages;
  final List<String> loads = <String>[];
  final List<(String, List<String>)> approvals = <(String, List<String>)>[];
  final List<bool> approvedUnverified = <bool>[];
  final List<(String?, DateTime?)> approvedPlans = <(String?, DateTime?)>[];
  final List<String?> approvedTypes = <String?>[];
  final List<(String, String)> rejections = <(String, String)>[];
  Object? approveError;

  @override
  Future<RegistrationsPage> load(String status, {String? query}) async {
    loads.add(status);
    return pages[status] ??
        const RegistrationsPage(items: <BusinessRegistration>[], counts: <String, int>{});
  }

  @override
  Future<void> approve(String id, List<String> services, {bool allowUnverified = false, String? plan, DateTime? validUntil, String? inventoryType}) async {
    if (approveError != null) throw approveError!;
    approvals.add((id, services));
    approvedTypes.add(inventoryType);
    approvedUnverified.add(allowUnverified);
    approvedPlans.add((plan, validUntil));
    // After approval the registration leaves "pending".
    pages = <String, RegistrationsPage>{
      ...pages,
      'pending': const RegistrationsPage(
        items: <BusinessRegistration>[],
        counts: <String, int>{'pending': 0, 'approved': 1, 'rejected': 0},
      ),
    };
  }

  @override
  Future<void> reject(String id, String reason) async {
    rejections.add((id, reason));
  }
}

RegistrationsPage _pending(List<BusinessRegistration> items) => RegistrationsPage(
      items: items,
      counts: <String, int>{'pending': items.length, 'approved': 3, 'rejected': 1},
    );

Widget _host(_FakeSource source) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: RegistrationsScreen(dataSource: source)),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

final Finder _approve = find.byKey(const ValueKey<String>('approve_button'));

void main() {
  testWidgets('lists what is waiting, with the counts per state', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[
        _reg('1'),
        _reg('2', business: 'Juma Transport', requested: const <String>['transport']),
      ]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    expect(find.text('Asha Rentals'), findsOneWidget);
    expect(find.text('Juma Transport'), findsOneWidget);
    expect(find.textContaining('0743519100'), findsWidgets);
    expect(find.text('Zinazosubiri (2)'), findsOneWidget);
    expect(find.text('Zilizokubaliwa (3)'), findsOneWidget);
    expect(find.text('Zilizokataliwa (1)'), findsOneWidget);
    expect(source.loads, <String>['pending']);
  });

  testWidgets('shows a friendly empty state', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(<String, RegistrationsPage>{'pending': _pending(<BusinessRegistration>[])})));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('registrations_empty')), findsOneWidget);
  });

  testWidgets('opening a registration shows every detail', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(<String, RegistrationsPage>{'pending': _pending(<BusinessRegistration>[_reg('1')])})));
    await t.pumpAndSettle();

    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    for (final String detail in <String>[
      'Asha Owner',
      'asha@example.test',
      '0743519100',
      'Mikocheni B, Kinondoni, Dar es Salaam',
      '1990-0001',
      'Two apartment blocks',
    ]) {
      expect(find.text(detail), findsOneWidget, reason: detail);
    }
  });

  testWidgets('approving gives exactly the services the super admin chose', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1')]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    // They asked for rental + transport; the super admin gives rental and inventory instead.
    await t.tap(find.byKey(const ValueKey<String>('grant_transport')));
    await t.tap(find.byKey(const ValueKey<String>('grant_inventory')));
    await t.pump();
    await t.tap(_approve);
    await t.pumpAndSettle();

    expect(source.approvals, hasLength(1));
    expect(source.approvals.single.$1, '1');
    expect(source.approvals.single.$2, <String>['inventory', 'rental']);
    // The sheet closed and the list was reloaded without the approved one.
    expect(_approve, findsNothing);
    expect(find.text('Asha Rentals'), findsNothing);
    expect(source.loads.length, 2);
  });

  testWidgets('approving starts the business on a trial unless a plan is chosen', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1')]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    // The default is a trial, with no date picked (the server sets the trial's length).
    expect(find.byKey(const ValueKey<String>('plan_valid_until_text')), findsOneWidget);
    expect(find.textContaining('Jaribio huanza leo'), findsOneWidget);
    await t.tap(_approve);
    await t.pumpAndSettle();

    expect(source.approvedPlans, <(String?, DateTime?)>[('trial', null)]);
  });

  testWidgets('the super admin can choose another plan when approving', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1')]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    await t.ensureVisible(find.byKey(const ValueKey<String>('plan_standard')));
    await t.tap(find.byKey(const ValueKey<String>('plan_standard')));
    await t.pump();
    expect(find.textContaining('Hakuna tarehe ya kuisha'), findsOneWidget, reason: 'a paid plan has no end date until one is picked');
    await t.tap(_approve);
    await t.pumpAndSettle();

    expect(source.approvedPlans, <(String?, DateTime?)>[('standard', null)]);
  });

  testWidgets('the kind of stock business the applicant chose is shown and sent when approving', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[
        _reg('1', business: 'Juma Shop', requested: <String>['inventory'], inventoryType: 'retail'),
      ]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Juma Shop'));
    await t.pumpAndSettle();

    expect(find.textContaining('Rejareja'), findsWidgets, reason: 'what the applicant said they run');
    await t.tap(_approve);
    await t.pumpAndSettle();

    expect(source.approvedTypes, <String?>['retail']);
  });

  testWidgets('the super admin can correct the kind of business before approving', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[
        _reg('1', business: 'Juma Shop', requested: <String>['inventory'], inventoryType: 'retail'),
      ]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Juma Shop'));
    await t.pumpAndSettle();

    await t.ensureVisible(find.byKey(const ValueKey<String>('inv_type_wholesale')));
    await t.tap(find.byKey(const ValueKey<String>('inv_type_wholesale')));
    await t.pump();
    await t.tap(_approve);
    await t.pumpAndSettle();

    expect(source.approvedTypes, <String?>['wholesale']);
  });

  testWidgets('no kind of business is asked for or sent when inventory is not given', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1')]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('inv_type_retail')), findsNothing);
    await t.tap(_approve);
    await t.pumpAndSettle();

    expect(source.approvedTypes, <String?>[null]);
  });

  testWidgets('a confirmed phone is shown as confirmed and approving asks nothing extra', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1')]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    expect(find.text('Imethibitishwa kwa nambari'), findsOneWidget);
    await t.tap(_approve);
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('unverified_dialog')), findsNothing);
    expect(source.approvedUnverified, <bool>[false]);
  });

  testWidgets('an unconfirmed phone is flagged, and approving needs an explicit "approve anyway"', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1', phoneVerified: false)]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    expect(find.text('Haijathibitishwa'), findsOneWidget, reason: 'the warning is on the details');

    // Cancelling the question approves nothing.
    await t.tap(_approve);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('unverified_dialog')), findsOneWidget);
    await t.tap(find.text('Ghairi'));
    await t.pumpAndSettle();
    expect(source.approvals, isEmpty);
    expect(_approve, findsOneWidget, reason: 'the sheet is still open');

    // Approving anyway goes through, and tells the server it was meant.
    await t.tap(_approve);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('approve_unverified_confirm')));
    await t.pumpAndSettle();

    expect(source.approvals, hasLength(1));
    expect(source.approvedUnverified, <bool>[true]);
  });

  testWidgets('approving with no service chosen is refused on the spot', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1', requested: const <String>['rental'])]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey<String>('grant_rental'))); // untick the only one
    await t.pump();
    await t.tap(_approve);
    await t.pump();

    expect(find.byKey(const ValueKey<String>('registration_action_error')), findsOneWidget);
    expect(source.approvals, isEmpty);
  });

  testWidgets("the server's reason for refusing is shown and the sheet stays open", (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1', requested: const <String>['inventory'])]),
    })
      ..approveError = Exception('Inventory is currently a single-depot service');
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    await t.tap(_approve);
    await t.pumpAndSettle();

    expect(find.textContaining('single-depot service'), findsOneWidget);
    expect(_approve, findsOneWidget, reason: 'still open so they can pick something else');
  });

  testWidgets('rejecting needs a reason, and sends it', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[_reg('1')]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    // No reason: nothing is sent.
    await t.tap(find.byKey(const ValueKey<String>('reject_button')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('reject_confirm')));
    await t.pumpAndSettle();
    expect(source.rejections, isEmpty);
    expect(find.byKey(const ValueKey<String>('registration_action_error')), findsOneWidget);

    // With a reason it goes through.
    await t.tap(find.byKey(const ValueKey<String>('reject_button')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey<String>('reject_reason')), 'Documents unclear');
    await t.tap(find.byKey(const ValueKey<String>('reject_confirm')));
    await t.pumpAndSettle();

    expect(source.rejections, <(String, String)>[('1', 'Documents unclear')]);
  });

  testWidgets('the approved tab shows what each business was given', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
      'pending': _pending(<BusinessRegistration>[]),
      'approved': _pending(<BusinessRegistration>[
        _reg('9', business: 'Done Ltd', status: 'approved', assigned: const <String>['rental']),
      ]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey<String>('status_approved')));
    await t.pumpAndSettle();

    expect(source.loads.last, 'approved');
    expect(find.text('Done Ltd'), findsOneWidget);
    expect(find.text('Imekubaliwa'), findsOneWidget);
    // An approved registration offers no approve/reject buttons.
    await t.tap(find.text('Done Ltd'));
    await t.pumpAndSettle();
    expect(_approve, findsNothing);
  });

  group('Approve as requested, in one tap', () {
    final Finder oneTap = find.byKey(const ValueKey<String>('approve_as_requested_1'));
    final Finder confirm = find.byKey(const ValueKey<String>('approve_as_requested_confirm'));

    testWidgets('gives exactly the services that were asked for, on the trial plan, after one question', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
        'pending': _pending(<BusinessRegistration>[_reg('1', requested: const <String>['transport', 'rental'])]),
      });
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      await t.tap(oneTap);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('approve_as_requested_dialog')), findsOneWidget, reason: 'nothing is sent before the question');
      expect(source.approvals, isEmpty);

      await t.tap(confirm);
      await t.pumpAndSettle();

      // services go in the app's fixed order (inventory, rental, transport), whatever order they were asked in
      expect(source.approvals.length, 1);
      expect(source.approvals.single.$1, '1');
      expect(source.approvals.single.$2, <String>['rental', 'transport']);
      expect(source.approvedPlans, <(String?, DateTime?)>[('trial', null)]);
      expect(source.approvedUnverified, <bool>[false]);
      expect(find.byKey(const ValueKey<String>('registrations_empty')), findsOneWidget, reason: 'the list was reloaded and the request left it');
      await t.pump(const Duration(seconds: 4)); // the success banner removes itself
    });

    testWidgets('saying no sends nothing', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(<String, RegistrationsPage>{'pending': _pending(<BusinessRegistration>[_reg('1')])});
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      await t.tap(oneTap);
      await t.pumpAndSettle();
      await t.tap(find.text('Ghairi'));
      await t.pumpAndSettle();

      expect(source.approvals, isEmpty);
      expect(find.text('Asha Rentals'), findsOneWidget);
    });

    testWidgets('a phone that was never confirmed still has to be approved on purpose', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
        'pending': _pending(<BusinessRegistration>[_reg('1', phoneVerified: false)]),
      });
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      await t.tap(oneTap);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('unverified_dialog')), findsOneWidget);
      expect(source.approvals, isEmpty, reason: 'not yet');

      await t.tap(find.byKey(const ValueKey<String>('approve_unverified_confirm')));
      await t.pumpAndSettle();

      expect(source.approvals.single.$1, '1');
      expect(source.approvedUnverified, <bool>[true]);
      await t.pump(const Duration(seconds: 4)); // the success banner removes itself
    });

    testWidgets('a refused approval says why and leaves the request where it was', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(<String, RegistrationsPage>{'pending': _pending(<BusinessRegistration>[_reg('1')])})
        ..approveError = Exception('Exception: Already approved. / Imeshakubaliwa.');
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      await t.tap(oneTap);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Exception'), findsNothing, reason: 'the error reads as plain words');
      expect(find.text('Asha Rentals'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('only a waiting request with services asked for has the button', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(<String, RegistrationsPage>{
        'pending': _pending(<BusinessRegistration>[_reg('1'), _reg('2', business: 'Nothing Asked', requested: const <String>[])]),
        'approved': _pending(<BusinessRegistration>[_reg('9', business: 'Done Ltd', status: 'approved', assigned: const <String>['rental'])]),
      });
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      expect(oneTap, findsOneWidget);
      expect(find.byKey(const ValueKey<String>('approve_as_requested_2')), findsNothing, reason: 'nothing to give "as requested"');

      await t.tap(find.byKey(const ValueKey<String>('status_approved')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('approve_as_requested_9')), findsNothing);
    });

    testWidgets('Review still opens the request so the services or plan can be changed first', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(<String, RegistrationsPage>{'pending': _pending(<BusinessRegistration>[_reg('1')])});
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey<String>('review_1')));
      await t.pumpAndSettle();

      expect(_approve, findsOneWidget);
      expect(source.approvals, isEmpty);
    });
  });

  group('the package the applicant chose', () {
    Future<_FakeSource> open(WidgetTester t, BusinessRegistration r) async {
      _tall(t);
      final _FakeSource source = _FakeSource(<String, RegistrationsPage>{'pending': _pending(<BusinessRegistration>[r])});
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await t.tap(find.text(r.businessName));
      await t.pumpAndSettle();
      return source;
    }

    String shown(WidgetTester t, String key) => (t.widget(find.byKey(ValueKey<String>(key))) as Text).data!;

    testWidgets('is shown with what it covers, the months and the price the super admin set', (t) async {
      await open(t, _reg('1', plan: 'standard', months: 3, price: 140000));

      expect(shown(t, 'requested_package'), 'Kawaida · Huduma 2 · Miezi 3 · TZS 140,000');
    });

    testWidgets('says so when no price has been set for it yet', (t) async {
      await open(t, _reg('1', plan: 'basic', months: 1));

      expect(shown(t, 'requested_package'), 'Msingi · Huduma MOJA · Mwezi 1 · bei haijawekwa');
    });

    testWidgets('a registration from before packages existed shows no package', (t) async {
      await open(t, _reg('1'));

      expect(find.byKey(const ValueKey<String>('requested_package')), findsNothing);
    });

    testWidgets('a sold plan that holds fewer services than are being given is refused before it is sent', (t) async {
      final _FakeSource source = await open(t, _reg('1', requested: const <String>['rental', 'transport']));

      await t.ensureVisible(find.byKey(const ValueKey<String>('plan_basic')));
      await t.tap(find.byKey(const ValueKey<String>('plan_basic')));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('plan_too_small_note')), findsOneWidget);
      expect(shown(t, 'plan_too_small_note'), startsWith('Mpango wa Msingi ni huduma MOJA tu, na umechagua 2'));

      await t.ensureVisible(_approve);
      await t.tap(_approve);
      await t.pumpAndSettle();
      expect(source.approvals, isEmpty, reason: 'nothing is sent');
      expect(shown(t, 'registration_action_error'), contains('huduma MOJA tu'));

      // Standard holds two: it goes through
      await t.tap(find.byKey(const ValueKey<String>('plan_standard')));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('plan_too_small_note')), findsNothing);
      await t.tap(_approve);
      await t.pumpAndSettle();
      expect(source.approvals, hasLength(1));
      expect(source.approvedPlans.single.$1, 'standard');
    });

    testWidgets('taking a service away makes a smaller plan fit', (t) async {
      final _FakeSource source = await open(t, _reg('1', requested: const <String>['rental', 'transport']));
      await t.ensureVisible(find.byKey(const ValueKey<String>('plan_basic')));
      await t.tap(find.byKey(const ValueKey<String>('plan_basic')));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('plan_too_small_note')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey<String>('grant_transport')));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('plan_too_small_note')), findsNothing);

      await t.ensureVisible(_approve);
      await t.tap(_approve);
      await t.pumpAndSettle();
      expect(source.approvals.single.$2, <String>['rental']);
      expect(source.approvedPlans.single.$1, 'basic');
    });

    testWidgets('a trial has no limit, whatever the services', (t) async {
      final _FakeSource source = await open(t, _reg('1', requested: const <String>['rental', 'transport', 'inventory'], inventoryType: 'depot'));

      expect(find.byKey(const ValueKey<String>('plan_too_small_note')), findsNothing);
      await t.ensureVisible(_approve);
      await t.tap(_approve);
      await t.pumpAndSettle();
      expect(source.approvedPlans.single.$1, 'trial');
    });
  });
}
