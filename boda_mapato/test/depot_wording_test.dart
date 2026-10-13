import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/hubs/supply_chain_hub_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/settings/depot_settings_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/inventory_widgets.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Depot" and "ghala" are for a business that IS a depot. A shop, a wholesaler or a mixed business reads
/// "business", "your stock", "we owe them" -- the words follow the kind of business set in Settings.

final LocalizationService _loc = LocalizationService.instance;

Future<void> _language(String code) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final String before = _loc.currentLanguage;
  await _loc.changeLanguage(code);
  addTearDown(() => _loc.changeLanguage(before));
}

/// Every translated place that had depot wording, and that now has a wording for other businesses too.
const List<String> _keys = <String>[
  'depot_details',
  'depot_name',
  'depot_position',
  'load_removes_stock_note',
  'reconcile_note',
  'warehouse_expenses',
];

final RegExp _depotWords = RegExp(r'depot|depo\b|ghala|ghalani|warehouse', caseSensitive: false);

class _Auth extends AuthProvider {
  @override
  UserData? get user => UserData(id: 'o1', name: 'Owner', email: 'o@example.test', role: 'admin', isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole('admin');
}

class _Server extends ApiService {
  _Server(this.kind);

  final String kind;

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'depot_name': 'Mama Asha',
          'depot_phone': '',
          'depot_address': '',
          'invoice_prefix': 'INV',
          'invoice_next_number': '1',
          'tax_percent': '0',
          'inventory_type': kind,
          'use_crates': kind == 'depot' ? '1' : '0',
          'sale_tier': kind == 'depot' ? 'product' : 'retail',
        },
      };
    }
    return null;
  }
}

void _ignoreTestFontOverflow() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> _pump(WidgetTester t, String kind, Widget screen) async {
  _ignoreTestFontOverflow();
  t.view.physicalSize = const Size(800, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Server server = _Server(kind);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<LocalizationService>.value(value: _loc),
      ],
      child: ScreenUtilInit(
        designSize: const Size(800, 4000),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: Scaffold(body: screen)),
      ),
    ),
  );
  await t.pump();
  await Provider.of<InventoryProvider>(t.element(find.byType(Scaffold).first), listen: false).fetchCapabilities();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final String lang in <String>['en', 'sw']) {
    group('the words, in ${lang == 'en' ? 'English' : 'Swahili'}', () {
      testWidgets('a business that is not a depot reads no "depot", "ghala" or "warehouse" in any of those places', (t) async {
        await _language(lang);

        for (final String key in _keys) {
          final String text = _loc.translateForKind(key, isDepot: false);
          expect(_depotWords.hasMatch(text), isFalse, reason: '$key reads "$text"');
          expect(text, isNot(equals(key)), reason: '$key has a wording of its own');
        }
      });

      testWidgets('a depot reads exactly what it always read', (t) async {
        await _language(lang);

        for (final String key in _keys) {
          expect(_loc.translateForKind(key, isDepot: true), _loc.translate(key), reason: key);
        }
        expect(_depotWords.hasMatch(_loc.translateForKind('depot_details', isDepot: true)), isTrue);
      });

      testWidgets('a text with no other wording reads the same for everyone', (t) async {
        await _language(lang);

        expect(_loc.translateForKind('settings', isDepot: false), _loc.translate('settings'));
        expect(_loc.translateForKind('settings', isDepot: true), _loc.translate('settings'));
      });
    });
  }

  group('Settings', () {
    for (final String kind in <String>['retail', 'wholesale', 'mixed']) {
      testWidgets('$kind: "Business details" and "Business name", and an example that is not a depot', (t) async {
        await _language('en');
        await _pump(t, kind, const DepotSettingsScreen());

        expect(find.text('Business details'), findsOneWidget);
        expect(find.text('Business name'), findsOneWidget);
        expect(find.text('Depot details'), findsNothing);
        expect(find.text('Depot name'), findsNothing);
        expect(find.byWidgetPredicate((Widget w) => w is TextField && w.decoration?.hintText == 'e.g. Mama Asha Shop'), findsOneWidget);
        expect(find.byWidgetPredicate((Widget w) => w is TextField && (w.decoration?.hintText ?? '').contains('Depot')), findsNothing);
      });
    }

    testWidgets('a depot keeps "Depot details" and "Depot name"', (t) async {
      await _language('en');
      await _pump(t, 'depot', const DepotSettingsScreen());

      expect(find.text('Depot details'), findsOneWidget);
      expect(find.text('Depot name'), findsOneWidget);
      expect(find.byWidgetPredicate((Widget w) => w is TextField && w.decoration?.hintText == 'e.g. Beverage Depot Dodoma'), findsOneWidget);
    });

    testWidgets('in Swahili a shop reads "Taarifa za biashara" and "Jina la biashara", not "ghala"', (t) async {
      await _language('sw');
      await _pump(t, 'retail', const DepotSettingsScreen());

      expect(find.text('Taarifa za biashara'), findsOneWidget);
      expect(find.text('Jina la biashara'), findsOneWidget);
      expect(find.textContaining('ghala'), findsNothing);
    });

    for (final (String kind, String label, String message) in <(String, String, String)>[
      ('retail', 'Business name', 'Business name is required'),
      ('depot', 'Depot name', 'Depot name is required'),
    ]) {
      testWidgets('$kind: leaving the name empty says "$message"', (t) async {
        await _language('en');
        await _pump(t, kind, const DepotSettingsScreen());

        expect(find.text(label), findsOneWidget, reason: 'the first box is the one labelled "$label"');
        await t.enterText(find.byType(TextFormField).first, '');
        await t.tap(find.byType(InvPrimaryButton));
        await t.pump();

        expect(find.text(message), findsOneWidget);
      });
    }
  });

  group('the supply-chain hub', () {
    testWidgets('a shop has an "Expenses" tab, not "Warehouse Expenses"', (t) async {
      await _language('en');
      await _pump(t, 'retail', const SupplyChainHubScreen());

      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Warehouse Expenses'), findsNothing);
    });

    testWidgets('a depot keeps "Warehouse Expenses"', (t) async {
      await _language('en');
      await _pump(t, 'depot', const SupplyChainHubScreen());

      expect(find.text('Warehouse Expenses'), findsOneWidget);
    });
  });
}
