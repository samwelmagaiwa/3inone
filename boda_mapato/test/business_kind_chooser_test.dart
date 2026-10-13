import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/products/add_edit_product_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/products/business_kind_chooser.dart';
import 'package:boda_mapato/modules/inventory/screens/products/products_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// The mark on the current kind, in whichever language the app starts in.
Finder get _currentMark => find.text(LocalizationService.instance.isSwahili ? 'Sasa' : 'Current');

void _ignoreTestFontOverflow() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 6000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

// ============================================================================ the card on its own

/// A button that opens the chooser and remembers what it answered.
Widget _chooserHost({
  String current = 'depot',
  bool sw = false,
  required Future<String?> Function(String) onChange,
  required List<bool> answers,
}) =>
    ScreenUtilInit(
      designSize: const Size(800, 6000),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: TextButton(
              key: const ValueKey<String>('open_chooser'),
              onPressed: () async => answers.add(await chooseBusinessKind(ctx, current: current, onChange: onChange, sw: sw)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester t) async {
  await t.tap(_key('open_chooser'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

// ============================================================================ the products screen

class _Server extends ApiService {
  _Server({this.knowsKinds = true, this.kind = 'depot', this.refuse});

  final bool knowsKinds;
  String kind;
  final String? refuse;
  final List<Map<String, dynamic>> businessPuts = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'depot_name': 'Beverage Depot',
          if (knowsKinds) 'inventory_type': kind,
          if (knowsKinds) 'use_crates': kind == 'depot' ? '1' : '0',
          if (knowsKinds) 'sale_tier': kind == 'depot' ? 'product' : (kind == 'wholesale' ? 'wholesale' : 'retail'),
        },
      };
    }
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

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 'u@example.test', role: role, isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

late InventoryProvider _inv;

Future<void> _openProducts(WidgetTester t, _Server server, {String role = 'admin'}) async {
  _ignoreTestFontOverflow();
  _tall(t);
  _inv = InventoryProvider(api: server);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: _inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(800, 6000),
        minTextAdapt: true,
        builder: (_, __) => const MaterialApp(home: Scaffold(body: ProductsScreen())),
      ),
    ),
  );
  await t.pump();
}

/// Taps "Add product" and lets whatever it starts (reading the settings, the card, the page) happen.
Future<void> _tapAdd(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.add).first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  group('the card that asks what kind of business this is', () {
    testWidgets('shows the four kinds with what each means, and marks the current one', (t) async {
      _tall(t);
      final List<bool> answers = <bool>[];
      await t.pumpWidget(_chooserHost(current: 'wholesale', onChange: (_) async => null, answers: answers));
      await _open(t);

      expect(find.text('What kind of business is this?'), findsOneWidget);
      for (final String k in <String>['retail', 'wholesale', 'mixed', 'depot']) {
        expect(_key('chooser_kind_$k'), findsOneWidget, reason: k);
      }
      expect(find.textContaining('single items'), findsOneWidget, reason: 'what retail means');
      expect(find.text('Current'), findsOneWidget);
      expect(find.descendant(of: _key('chooser_kind_wholesale'), matching: find.text('Current')), findsOneWidget);
    });

    testWidgets('says the same in Swahili', (t) async {
      _tall(t);
      await t.pumpWidget(_chooserHost(sw: true, onChange: (_) async => null, answers: <bool>[]));
      await _open(t);

      expect(find.text('Biashara yako ni ya aina gani?'), findsOneWidget);
      expect(find.text('Ghairi'), findsOneWidget);
      expect(find.text('Sasa'), findsOneWidget);
    });

    testWidgets('picking another kind saves that kind and answers yes', (t) async {
      _tall(t);
      final List<String> sent = <String>[];
      final List<bool> answers = <bool>[];
      await t.pumpWidget(_chooserHost(
        answers: answers,
        onChange: (String k) async {
          sent.add(k);
          return null;
        },
      ));
      await _open(t);

      await t.tap(_key('chooser_kind_retail'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(sent, <String>['retail']);
      expect(answers, <bool>[true]);
      expect(_key('business_kind_chooser'), findsNothing, reason: 'the card closes');
    });

    testWidgets('picking the kind it already is answers yes without saving anything', (t) async {
      _tall(t);
      final List<String> sent = <String>[];
      final List<bool> answers = <bool>[];
      await t.pumpWidget(_chooserHost(
        current: 'mixed',
        answers: answers,
        onChange: (String k) async {
          sent.add(k);
          return null;
        },
      ));
      await _open(t);

      await t.tap(_key('chooser_kind_mixed'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(sent, isEmpty);
      expect(answers, <bool>[true]);
    });

    testWidgets('when the server refuses, the reason shows, the card stays and the answer is not yes', (t) async {
      _tall(t);
      final List<bool> answers = <bool>[];
      await t.pumpWidget(_chooserHost(answers: answers, onChange: (_) async => 'Only the owner can change this.'));
      await _open(t);

      await t.tap(_key('chooser_kind_retail'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.text('Only the owner can change this.'), findsOneWidget);
      expect(_key('business_kind_chooser'), findsOneWidget);
      expect(answers, isEmpty, reason: 'still waiting for a choice');
    });

    testWidgets('Cancel answers no', (t) async {
      _tall(t);
      final List<bool> answers = <bool>[];
      await t.pumpWidget(_chooserHost(onChange: (_) async => null, answers: answers));
      await _open(t);

      await t.tap(_key('chooser_cancel'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(answers, <bool>[false]);
    });
  });

  group('Add product', () {
    testWidgets('the owner is asked first; choosing a kind opens the product page laid out for it', (t) async {
      final _Server server = _Server();
      await _openProducts(t, server);

      await _tapAdd(t);
      expect(_key('business_kind_chooser'), findsOneWidget, reason: 'the card comes before the page');
      expect(find.byType(AddEditProductScreen), findsNothing);

      await t.tap(_key('chooser_kind_retail'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));

      expect(server.businessPuts, <Map<String, dynamic>>[
        <String, dynamic>{'inventory_type': 'retail'}
      ]);
      expect(find.byType(AddEditProductScreen), findsOneWidget, reason: 'now the page opens');
      expect(_inv.capabilities.inventoryType, 'retail', reason: 'the page already knows the new kind');
      expect(_key('business_kind_chooser'), findsNothing);
    });

    testWidgets('choosing the kind it already is goes straight to the page', (t) async {
      final _Server server = _Server(kind: 'wholesale');
      await _openProducts(t, server);

      await _tapAdd(t);
      expect(find.descendant(of: _key('chooser_kind_wholesale'), matching: _currentMark), findsOneWidget);
      await t.tap(_key('chooser_kind_wholesale'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));

      expect(server.businessPuts, isEmpty);
      expect(find.byType(AddEditProductScreen), findsOneWidget);
    });

    testWidgets('backing out of the card opens no page and changes nothing', (t) async {
      final _Server server = _Server();
      await _openProducts(t, server);

      await _tapAdd(t);
      await t.tap(_key('chooser_cancel'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.byType(AddEditProductScreen), findsNothing);
      expect(server.businessPuts, isEmpty);
    });

    testWidgets('a refused change keeps the card open and opens no page', (t) async {
      final _Server server = _Server(refuse: 'Only the owner of the business can change this.');
      await _openProducts(t, server);

      await _tapAdd(t);
      await t.tap(_key('chooser_kind_retail'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.text('Only the owner of the business can change this.'), findsOneWidget);
      expect(find.byType(AddEditProductScreen), findsNothing);
    });

    testWidgets('staff, who cannot change the kind, go straight to the page', (t) async {
      final _Server server = _Server();
      await _openProducts(t, server, role: 'sales_officer');

      await _tapAdd(t);

      expect(_key('business_kind_chooser'), findsNothing);
      expect(find.byType(AddEditProductScreen), findsOneWidget);
      expect(server.businessPuts, isEmpty);
    });

    testWidgets('an older server, which knows no kinds, goes straight to the page', (t) async {
      final _Server server = _Server(knowsKinds: false);
      await _openProducts(t, server);

      await _tapAdd(t);

      expect(_key('business_kind_chooser'), findsNothing);
      expect(find.byType(AddEditProductScreen), findsOneWidget);
    });
  });
}
