import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/settings/depot_settings_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/inventory_widgets.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/joined_sections.dart';
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
  t.view.physicalSize = const Size(800, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Widget _host(Widget child) => ScreenUtilInit(
      designSize: const Size(800, 4000),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 'u@example.test', role: role, isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

class _Server extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'depot_name': 'Beverage Depot',
          'depot_phone': '',
          'depot_address': '',
          'invoice_prefix': 'INV',
          'invoice_next_number': '1',
          'tax_percent': '0',
          'inventory_type': 'depot',
          'use_crates': '1',
          'sale_tier': 'product',
        },
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

Future<void> _openSettings(WidgetTester t, String role) async {
  _ignoreTestFontOverflow();
  _tall(t);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: _Server())),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(800, 4000),
        minTextAdapt: true,
        builder: (_, __) => const MaterialApp(home: DepotSettingsScreen()),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

/// How many sections the one card holds.
int _sectionsIn(WidgetTester t) => t.widget<JoinedSectionsCard>(find.byType(JoinedSectionsCard)).sections.length;

void main() {
  group('the joined card', () {
    testWidgets('puts a glowing divider BETWEEN sections, none before the first or after the last', (t) async {
      _tall(t);
      await t.pumpWidget(_host(const JoinedSectionsCard(sections: <Widget>[Text('one'), Text('two'), Text('three')])));

      expect(find.byType(SectionGlowDivider), findsNWidgets(2));
      // and they sit between the texts, top to bottom: one, divider, two, divider, three
      final double one = t.getTopLeft(find.text('one')).dy;
      final double two = t.getTopLeft(find.text('two')).dy;
      final double three = t.getTopLeft(find.text('three')).dy;
      final List<double> dividers = <double>[
        t.getTopLeft(find.byType(SectionGlowDivider).at(0)).dy,
        t.getTopLeft(find.byType(SectionGlowDivider).at(1)).dy,
      ];
      expect(one < dividers[0] && dividers[0] < two && two < dividers[1] && dividers[1] < three, isTrue);
    });

    testWidgets('a single section has no divider at all', (t) async {
      _tall(t);
      await t.pumpWidget(_host(const JoinedSectionsCard(sections: <Widget>[Text('only')])));

      expect(find.byType(SectionGlowDivider), findsNothing);
    });

    testWidgets('a flush section reaches the sides of the card; a normal one is padded in', (t) async {
      _tall(t);
      await t.pumpWidget(_host(const JoinedSectionsCard(sections: <Widget>[
        Text('padded'),
        FlushSection(child: SizedBox(key: ValueKey<String>('flush_row'), height: 20)),
      ])));

      final Rect card = t.getRect(find.byType(JoinedSectionsCard));
      expect(t.getRect(_key('flush_row')).width, card.width, reason: 'no padding around it');
      expect(t.getTopLeft(find.text('padded')).dx, greaterThan(card.left + 8));
    });
  });

  group('Depot settings', () {
    testWidgets('every section is in ONE card, with no box of its own and no gaps between them', (t) async {
      await _openSettings(t, 'admin');

      expect(find.byType(JoinedSectionsCard), findsOneWidget);
      final Rect card = t.getRect(find.byType(JoinedSectionsCard));
      final LocalizationService loc = LocalizationService.instance;
      for (final String key in <String>['depot_details', 'invoicing', 'limits_and_thresholds']) {
        final Finder title = find.text(loc.translate(key));
        expect(title, findsOneWidget, reason: key);
        expect(card.contains(t.getTopLeft(title)), isTrue, reason: '$key is inside the joined card');
      }
      expect(card.contains(t.getTopLeft(_key('business_kind_card'))), isTrue);

      // nothing in the screen still draws the separate glass box
      final Iterable<Container> boxes = t
          .widgetList<Container>(find.byType(Container))
          .where((Container c) => c.decoration == ThemeConstants.glassCardDecoration);
      expect(boxes, isEmpty, reason: 'the old per-section cards are gone');
      expect(t.widget<Container>(_key('business_kind_card')).decoration, isNull);
    });

    testWidgets('a divider line separates each pair of sections', (t) async {
      await _openSettings(t, 'admin');

      expect(find.byType(SectionGlowDivider), findsNWidgets(_sectionsIn(t) - 1));
      expect(_sectionsIn(t), greaterThanOrEqualTo(6), reason: 'kind, 3 groups, crate deposits and the links');
    });

    testWidgets('the owner\'s links are rows of the card, not boxes of their own', (t) async {
      await _openSettings(t, 'admin');

      final LocalizationService loc = LocalizationService.instance;
      final Finder users = find.text(loc.translate('users_management'));
      expect(users, findsOneWidget);
      expect(find.text('Mpangilio wa Risiti'), findsOneWidget);
      final Rect card = t.getRect(find.byType(JoinedSectionsCard));
      expect(card.contains(t.getTopLeft(users)), isTrue);
      expect(card.contains(t.getTopLeft(find.text('Mpangilio wa Risiti'))), isTrue);
    });

    testWidgets('someone without those rights sees fewer sections, and still no stray divider', (t) async {
      await _openSettings(t, 'cashier');

      expect(find.text(LocalizationService.instance.translate('users_management')), findsNothing);
      expect(find.text('Mpangilio wa Risiti'), findsNothing);
      expect(find.byType(SectionGlowDivider), findsNWidgets(_sectionsIn(t) - 1));
    });

    testWidgets('the Save button stays below the card', (t) async {
      await _openSettings(t, 'admin');

      final Rect card = t.getRect(find.byType(JoinedSectionsCard));
      expect(t.getTopLeft(find.byType(InvPrimaryButton)).dy, greaterThanOrEqualTo(card.bottom));
    });
  });
}

