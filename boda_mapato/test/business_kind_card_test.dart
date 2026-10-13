import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/settings/business_kind_card.dart';
import 'package:boda_mapato/modules/inventory/screens/settings/depot_settings_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void _ignoreTestFontOverflow() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

// ============================================================================ the card on its own

Widget _cardHost({
  bool serverKnowsKinds = true,
  String current = 'depot',
  bool canChange = true,
  bool sw = false,
  required Future<String?> Function(String) onChange,
}) =>
    ScreenUtilInit(
      designSize: const Size(800, 3000),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BusinessKindCard(
              serverKnowsKinds: serverKnowsKinds,
              current: current,
              canChange: canChange,
              onChange: onChange,
              sw: sw,
            ),
          ),
        ),
      ),
    );

// ============================================================================ the whole Depot settings screen

class _OwnerAuth extends AuthProvider {
  _OwnerAuth({this.role = 'admin'});

  final String role;

  @override
  UserData? get user => UserData(id: 'owner-1', name: 'Owner', email: 'owner@example.test', role: role, isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

/// A server: its settings, and what happens when the kind is changed.
class _FakeServer extends ApiService {
  _FakeServer({required this.knowsKinds, this.kind = 'depot', this.refuse});

  final bool knowsKinds;
  String kind;
  final String? refuse;
  final List<Map<String, dynamic>> businessPuts = <Map<String, dynamic>>[];

  Map<String, dynamic> get settings => <String, dynamic>{
        'depot_name': 'Beverage Depot',
        'depot_phone': '',
        'depot_address': '',
        'invoice_prefix': 'INV',
        'invoice_next_number': '1',
        'tax_percent': '0',
        if (knowsKinds) 'inventory_type': kind,
        if (knowsKinds) 'use_crates': kind == 'depot' ? '1' : '0',
        if (knowsKinds) 'sale_tier': kind == 'depot' ? 'product' : (kind == 'wholesale' ? 'wholesale' : 'retail'),
      };

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) return <String, dynamic>{'data': settings};
    return <String, dynamic>{'data': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> data) async {
    if (endpoint == '/business') {
      if (refuse != null) throw ApiException(refuse!);
      businessPuts.add(data);
      kind = data['inventory_type'] as String;
    }
    return <String, dynamic>{'data': <String, dynamic>{}};
  }
}

Future<void> _openDepotSettings(WidgetTester t, _FakeServer server, {AuthProvider? auth}) async {
  _ignoreTestFontOverflow();
  _tall(t);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => auth ?? _OwnerAuth()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(800, 3000),
        minTextAdapt: true,
        builder: (_, __) => const MaterialApp(home: DepotSettingsScreen()),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  group('the card on its own', () {
    testWidgets('an old server: it says so and offers nothing to tap', (t) async {
      _tall(t);
      await t.pumpWidget(_cardHost(serverKnowsKinds: false, onChange: (_) async => null));

      expect(_key('business_kind_card'), findsOneWidget, reason: 'the card never hides');
      expect(_key('business_kind_server_old'), findsOneWidget);
      expect(find.textContaining('not been updated'), findsOneWidget);
      for (final String k in <String>['retail', 'wholesale', 'mixed', 'depot']) {
        expect(_key('business_kind_$k'), findsNothing, reason: k);
      }
      expect(_key('business_kind_save'), findsNothing);
    });

    testWidgets('says the same in Swahili', (t) async {
      _tall(t);
      await t.pumpWidget(_cardHost(serverKnowsKinds: false, sw: true, onChange: (_) async => null));

      expect(find.textContaining('haijasasishwa'), findsOneWidget);
      expect(find.text('Aina ya biashara'), findsOneWidget);
    });

    testWidgets('a current server: four kinds, the current one chosen, with what it means', (t) async {
      _tall(t);
      await t.pumpWidget(_cardHost(current: 'wholesale', onChange: (_) async => null));

      for (final String k in <String>['retail', 'wholesale', 'mixed', 'depot']) {
        expect(_key('business_kind_$k'), findsOneWidget, reason: k);
      }
      expect(t.widget<ChoiceChip>(_key('business_kind_wholesale')).selected, isTrue);
      expect(t.widget<ChoiceChip>(_key('business_kind_retail')).selected, isFalse);
      expect(find.textContaining('carton, sack'), findsOneWidget, reason: 'the hint of the chosen kind');
      expect(_key('business_kind_save'), findsNothing, reason: 'nothing changed yet');
      expect(_key('business_kind_server_old'), findsNothing);
    });

    testWidgets('picking another kind offers Save, and saving sends that kind', (t) async {
      _tall(t);
      final List<String> sent = <String>[];
      await t.pumpWidget(_cardHost(onChange: (String k) async {
        sent.add(k);
        return null;
      }));

      await t.tap(_key('business_kind_retail'));
      await t.pump();
      expect(find.textContaining('single items'), findsOneWidget, reason: 'the hint follows the choice');
      expect(_key('business_kind_save'), findsOneWidget);

      await t.tap(_key('business_kind_save'));
      await t.pump();
      expect(sent, <String>['retail']);
      await t.pump(const Duration(seconds: 4)); // the "Saved" banner
    });

    testWidgets('going back to the current kind takes Save away again', (t) async {
      _tall(t);
      await t.pumpWidget(_cardHost(current: 'depot', onChange: (_) async => null));

      await t.tap(_key('business_kind_mixed'));
      await t.pump();
      expect(_key('business_kind_save'), findsOneWidget);
      await t.tap(_key('business_kind_depot'));
      await t.pump();
      expect(_key('business_kind_save'), findsNothing);
    });

    testWidgets('the server\'s reason is shown when it refuses', (t) async {
      _tall(t);
      await t.pumpWidget(_cardHost(onChange: (_) async => 'Only the owner of the business can change its details.'));

      await t.tap(_key('business_kind_retail'));
      await t.pump();
      await t.tap(_key('business_kind_save'));
      await t.pump();

      expect(find.text('Only the owner of the business can change its details.'), findsOneWidget);
      expect(_key('business_kind_save'), findsOneWidget, reason: 'still there to try again');
    });

    testWidgets('someone who is not the owner sees the kind but cannot change it', (t) async {
      _tall(t);
      await t.pumpWidget(_cardHost(current: 'mixed', canChange: false, onChange: (_) async => null));

      expect(t.widget<ChoiceChip>(_key('business_kind_mixed')).selected, isTrue);
      expect(t.widget<ChoiceChip>(_key('business_kind_retail')).onSelected, isNull);
      expect(_key('business_kind_read_only'), findsOneWidget);
      expect(_key('business_kind_save'), findsNothing);
    });

    testWidgets('when the kind arrives from the server after a save, the card shows it', (t) async {
      _tall(t);
      String current = 'depot';
      late StateSetter rebuild;
      await t.pumpWidget(ScreenUtilInit(
        designSize: const Size(800, 3000),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(builder: (BuildContext context, StateSetter setState) {
              rebuild = setState;
              return BusinessKindCard(
                serverKnowsKinds: true,
                current: current,
                canChange: true,
                onChange: (String k) async => null,
                sw: false,
              );
            }),
          ),
        ),
      ));

      expect(t.widget<ChoiceChip>(_key('business_kind_depot')).selected, isTrue);
      rebuild(() => current = 'retail');
      await t.pump();
      expect(t.widget<ChoiceChip>(_key('business_kind_retail')).selected, isTrue);
      expect(t.widget<ChoiceChip>(_key('business_kind_depot')).selected, isFalse);
    });
  });

  group('in Depot settings', () {
    testWidgets('the card is at the top, above the depot details', (t) async {
      await _openDepotSettings(t, _FakeServer(knowsKinds: true));

      expect(_key('business_kind_card'), findsOneWidget);
      final double card = t.getTopLeft(_key('business_kind_card')).dy;
      final double details = t.getTopLeft(find.text(LocalizationService.instance.translate('depot_details'))).dy;
      expect(card, lessThan(details));
    });

    testWidgets('an old server: the settings are all there and the card says the server needs updating', (t) async {
      await _openDepotSettings(t, _FakeServer(knowsKinds: false));

      expect(_key('business_kind_server_old'), findsOneWidget);
      expect(find.text(LocalizationService.instance.translate('depot_details')), findsOneWidget, reason: 'the rest of the screen is untouched');
    });

    testWidgets('the owner of a depot changes it to retail: the server is told, and the screen follows', (t) async {
      final _FakeServer server = _FakeServer(knowsKinds: true, kind: 'depot');
      await _openDepotSettings(t, server);

      expect(t.widget<ChoiceChip>(_key('business_kind_depot')).selected, isTrue);
      expect(find.text('Dhamana ya makreti'), findsWidgets, reason: 'a depot has crate deposits');

      await t.tap(_key('business_kind_retail'));
      await t.pump();
      await t.tap(_key('business_kind_save'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(server.businessPuts, <Map<String, dynamic>>[
        <String, dynamic>{'inventory_type': 'retail'},
      ]);
      expect(t.widget<ChoiceChip>(_key('business_kind_retail')).selected, isTrue, reason: 'read back from the server');
      expect(_key('business_kind_save'), findsNothing, reason: 'saved: nothing left to save');
      expect(find.text('Dhamana ya makreti'), findsNothing, reason: 'a shop has no crate deposits');
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('a refusal from the server is shown and nothing changes', (t) async {
      final _FakeServer server = _FakeServer(knowsKinds: true, refuse: 'Only the owner of the business can change its details.');
      await _openDepotSettings(t, server);

      await t.tap(_key('business_kind_wholesale'));
      await t.pump();
      await t.tap(_key('business_kind_save'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('Only the owner of the business can change its details.'), findsOneWidget);
      expect(server.kind, 'depot');
    });

    testWidgets('staff who are not the owner can see it but not change it', (t) async {
      await _openDepotSettings(t, _FakeServer(knowsKinds: true, kind: 'retail'), auth: _OwnerAuth(role: 'manager'));

      expect(t.widget<ChoiceChip>(_key('business_kind_retail')).selected, isTrue);
      expect(t.widget<ChoiceChip>(_key('business_kind_depot')).onSelected, isNull);
      expect(_key('business_kind_read_only'), findsOneWidget);
    });
  });

  group('the provider call', () {
    test('changeBusinessKind sends the kind, reads the settings again and returns null', () async {
      final _FakeServer server = _FakeServer(knowsKinds: true);
      final DepotProvider depot = DepotProvider(api: server);
      await depot.fetchSettings();
      expect(depot.capabilities.inventoryType, 'depot');

      expect(await depot.changeBusinessKind('wholesale'), isNull);

      expect(server.businessPuts, <Map<String, dynamic>>[
        <String, dynamic>{'inventory_type': 'wholesale'},
      ]);
      expect(depot.capabilities.inventoryType, 'wholesale');
      expect(depot.capabilities.useCrates, isFalse);
      expect(depot.capabilities.saleTier, 'wholesale');
    });

    test('a refusal comes back as its reason', () async {
      final DepotProvider depot = DepotProvider(api: _FakeServer(knowsKinds: true, refuse: 'Not allowed'));
      expect(await depot.changeBusinessKind('retail'), 'Not allowed');
    });
  });
}
