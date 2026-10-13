import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants/colors.dart';
import 'constants/styles.dart';
import 'constants/theme_constants.dart';
import 'modules/inventory/screens/inventory_home.dart';
import 'models/login_response.dart';
import 'providers/auth_provider.dart';
import 'widgets/business_state_scope.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/communications_screen.dart';
import 'screens/admin/debts_management_screen.dart';
import 'screens/admin/drivers_management_screen.dart';
import 'screens/admin/vehicles_management_screen.dart';
import 'screens/analytics/analytics_screen.dart';
import 'screens/auth/force_password_change_screen.dart';
import 'screens/coming_soon_screen.dart';
import 'screens/dashboard/modern_dashboard_screen.dart';
import 'screens/demo_language_screen.dart';
import 'screens/driver/driver_dashboard_screen.dart';
import 'screens/driver/driver_payment_history_screen.dart';
import 'screens/driver/driver_receipts_screen.dart';
import 'screens/driver/driver_reminders_screen.dart';
import 'screens/maintenance/maintenance_details_screen.dart';
import 'screens/maintenance/maintenance_list_screen.dart';
import 'screens/maintenance/request_maintenance_screen.dart';
import 'screens/maintenance/vendors_list_screen.dart';
import 'screens/payments/payments_screen.dart';
import 'screens/public/public_landing_screen.dart';
import 'screens/receipts/receipts_screen.dart';
import 'screens/reminders/reminders_screen.dart';
import 'screens/rental/billing_list_screen.dart';
import 'screens/rental/blocks_management_screen.dart';
import 'screens/rental/create_property_screen.dart';
import 'screens/rental/edit_property_screen.dart';
import 'screens/rental/helpdesk_screen.dart';
import 'screens/rental/house_details_screen.dart';
import 'screens/rental/house_management_screen.dart';
import 'screens/rental/lease_agreements_screen.dart';
import 'screens/rental/lease_details_screen.dart';
import 'screens/rental/onboard_tenant_screen.dart';
import 'screens/rental/properties_list_screen.dart';
import 'screens/rental/property_details_screen.dart';
import 'screens/rental/record_payment_screen.dart';
import 'screens/rental/rental_arrears_screen.dart';
import 'screens/rental/rental_main_screen.dart';
import 'screens/rental/rental_payments_screen.dart';
import 'screens/rental/rental_receipts_screen.dart';
import 'screens/rental/rental_tenants_screen.dart';
import 'screens/rental/tenant_details_screen.dart';
import 'screens/rental/tenant_self_service_screen.dart';
import 'screens/rental/vendor_dashboard_screen.dart';
import 'screens/rental/lease_agreement_wizard_screen.dart';
import 'screens/reports/report_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_business_screen.dart';
import 'screens/landing/app_landing_screen.dart';
import 'screens/service_selection_screen.dart';
import 'widgets/service_guard.dart';
import 'screens/settings/settings_screen.dart';
import 'services/api_service.dart';
import 'services/app_messenger.dart';
import 'services/localization_service.dart';
import 'screens/splash/app_splash_screen.dart';
import 'utils/role_services.dart';
import 'utils/web_keyboard_fix_stub.dart'
    if (dart.library.html) 'utils/web_keyboard_fix_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize web keyboard fix for Flutter web
  WebKeyboardFix.initialize();

  // Initialize localization service
  await LocalizationService.instance.initialize();

  // Debug: tag overflow issues with current page name in console
  FlutterError.onError = (FlutterErrorDetails details) {
    // Keep default behavior
    FlutterError.presentError(details);
    if (kDebugMode) {
      final String msg = details.exceptionAsString();
      if (msg.contains('RenderFlex overflowed') ||
          msg.contains('A RenderFlex overflowed')) {
        debugPrint(
            '[OVERFLOW] page=${RouteTracker.currentRouteName} -> ${details.exceptionAsString()}');
      }
    }
  };

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Test API connectivity in debug mode (disabled to reduce console noise)
  // if (kDebugMode) {
  //   await ConnectivityTest.printConnectivityReport();
  // }

  runApp(const BodaMapatoApp());
}

// Global route tracker to know which page is active (for debug logs)
class RouteTracker extends NavigatorObserver {
  static final RouteTracker observer = RouteTracker();
  static String _current = '(unknown)';
  static String get currentRouteName => _current;

  void _setCurrent(Route<dynamic>? route) {
    final Route<dynamic>? r = route;
    final String name =
        r?.settings.name ?? r?.runtimeType.toString() ?? '(unknown)';
    // Some MaterialPageRoutes might not have names; also try widget type if available
    _current = name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _setCurrent(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _setCurrent(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _setCurrent(newRoute);
  }
}

class BodaMapatoApp extends StatelessWidget {
  const BodaMapatoApp({super.key});

  @override
  Widget build(final BuildContext context) => ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        useInheritedMediaQuery: true,
        builder: (final BuildContext context, final Widget? child) =>
            MultiProvider(
          providers: <SingleChildWidget>[
            Provider<ApiService>(
              create: (final BuildContext _) => ApiService(),
            ),
            ChangeNotifierProvider<LocalizationService>.value(
              value: LocalizationService.instance,
            ),
            ChangeNotifierProvider<AuthProvider>(
              create: (final BuildContext _) => AuthProvider(),
            ),
            // Business data (products, sales, drivers, properties...) is NOT created here: it lives
            // in BusinessStateScope below, rebuilt for whoever is signed in, so one person never
            // sees the previous person's cached lists.
          ],
          child: Consumer<LocalizationService>(
            builder: (context, localizationService, child) => MaterialApp(
              title: localizationService.translate('app_name'),
              theme: _buildTheme(context),
              scaffoldMessengerKey: AppMessenger.key,
              locale: localizationService.currentLocale,
              navigatorObservers: <NavigatorObserver>[RouteTracker.observer],
              supportedLocales: const [
                Locale('en', 'US'),
                Locale('sw', 'TZ'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (final BuildContext context, final Widget? navigator) =>
                  BusinessStateScope(child: navigator ?? const SizedBox.shrink()),
              home: const AuthWrapper(),
              debugShowCheckedModeBanner: false,
              routes: <String, WidgetBuilder>{
                "/landing": (final BuildContext context) =>
                    const PublicLandingScreen(),
                "/receipts": (final BuildContext context) =>
                    const ReceiptsScreen(),
                "/driver/receipts": (final BuildContext context) =>
                    const DriverReceiptsScreen(),
                "/driver/payment-history": (final BuildContext context) =>
                    const DriverPaymentHistoryScreen(),
                "/admin/dashboard": (final BuildContext context) =>
                    const AdminDashboardScreen(),
                "/modern-dashboard": (final BuildContext context) =>
                    const ServiceGuard(service: 'transport', child: ModernDashboardScreen()),
                "/admin/drivers": (final BuildContext context) =>
                    const DriversManagementScreen(),
                "/admin/vehicles": (final BuildContext context) =>
                    const VehiclesManagementScreen(),
                "/payments": (final BuildContext context) =>
                    const PaymentsScreen(),
                "/admin/analytics": (final BuildContext context) =>
                    const AnalyticsScreen(),
                "/admin/reports": (final BuildContext context) =>
                    const ReportScreen(),
                "/admin/reminders": (final BuildContext context) =>
                    const RemindersScreen(),
                "/driver/reminders": (final BuildContext context) =>
                    const DriverRemindersScreen(),
                "/admin/debts": (final BuildContext context) =>
                    const DebtsManagementScreen(),
                "/admin/communications": (final BuildContext context) =>
                    const CommunicationsScreen(),
                "/settings": (final BuildContext context) =>
                    const SettingsScreen(),
                "/demo": (final BuildContext context) =>
                    const DemoLanguageScreen(),
                "/select-service": (final BuildContext context) {
                  // This route builder never had access to the logged-in
                  // user, so it always constructed ServiceSelectionScreen
                  // with allowedServices left null -> "no access to any
                  // service" for EVERY user (super_admin included) who
                  // reached it via the back arrow / apps icon from a
                  // service home screen, regardless of their real access.
                  final UserData? user =
                      Provider.of<AuthProvider>(context, listen: false).user;
                  return ServiceSelectionScreen(
                    allowedServices:
                        user != null ? _allowedServicesFor(user) : const <String>[],
                  );
                },
                "/inventory": (final BuildContext context) =>
                    const ServiceGuard(service: 'inventory', child: InventoryHome()),
                "/coming-soon": (final BuildContext context) =>
                    const ComingSoonScreen(),
                "/rental/dashboard": (final BuildContext context) =>
                    const ServiceGuard(service: 'rental', child: RentalMainScreen()),
                "/rental/properties": (final BuildContext context) =>
                    const PropertiesListScreen(),
                "/rental/property-details": (final BuildContext context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  if (args is Map) {
                    return PropertyDetailsScreen(propertyId: (args['id'] ?? args['propertyId'] ?? '').toString());
                  }
                  return PropertyDetailsScreen(propertyId: args?.toString() ?? '');
                },
                "/rental/add-property": (final BuildContext context) =>
                    const CreatePropertyScreen(),
                "/rental/edit-property": (final BuildContext context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  if (args is Map) {
                     final map = Map<String, dynamic>.from(args);
                     return EditPropertyScreen(property: map['property'] ?? map);
                  }
                  return const EditPropertyScreen(property: {});
                },
                "/rental/tenants": (final BuildContext context) =>
                    const RentalTenantsScreen(),
                "/rental/tenant-details": (final BuildContext context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  if (args is Map) {
                    return TenantDetailsScreen(tenant: Map<dynamic, dynamic>.from(args));
                  }
                  return TenantDetailsScreen(tenant: {'id': args?.toString() ?? ''});
                },
                "/rental/onboard-tenant": (final BuildContext context) =>
                    const OnboardTenantScreen(),
                "/rental/house-details": (final BuildContext context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  if (args is Map) {
                    return HouseDetailsScreen(house: Map<String, dynamic>.from(args));
                  }
                  return HouseDetailsScreen(house: {'id': args?.toString() ?? ''});
                },
                "/rental/billing": (final BuildContext context) =>
                    const BillingListScreen(),
                "/rental/maintenance": (final BuildContext context) =>
                    const MaintenanceListScreen(),
                "/rental/maintenance-details": (final BuildContext context) {
                  final args = ModalRoute.of(context)!.settings.arguments;
                  if (args is Map) {
                    return MaintenanceDetailsScreen(request: Map<String, dynamic>.from(args));
                  }
                  return const ComingSoonScreen();
                },
                "/rental/maintenance-request": (final BuildContext context) =>
                    const RequestMaintenanceScreen(),
                "/rental/vendors": (final BuildContext context) =>
                    const VendorsListScreen(),
                "/rental/payments": (final BuildContext context) =>
                    const RentalPaymentsScreen(),
                "/rental/receipts": (final BuildContext context) =>
                    const RentalReceiptsScreen(),
                "/rental/arrears": (final BuildContext context) =>
                    const RentalArrearsScreen(),
                "/rental/reports": (final BuildContext context) =>
                    const RentalArrearsScreen(),
                "/rental/record-payment": (final BuildContext context) =>
                    const RecordPaymentScreen(),
                "/rental/tenant-self-service": (final BuildContext context) =>
                    const TenantSelfServiceScreen(),
                "/vendor-dashboard": (final BuildContext context) =>
                    const VendorDashboardScreen(),
                "/rental/blocks": (final BuildContext context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  if (args is Map) {
                    return BlocksManagementScreen(
                      propertyId: (args['propertyId'] ?? '').toString(),
                      propertyName: (args['propertyName'] ?? '').toString(),
                    );
                  }
                  return const BlocksManagementScreen(propertyId: '', propertyName: '');
                },
                "/rental/houses": (final BuildContext context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  if (args is Map) {
                    return HouseManagementScreen(
                      propertyId: (args['propertyId'] ?? '').toString(),
                      propertyName: (args['propertyName'] ?? '').toString(),
                    );
                  }
                  return const HouseManagementScreen(propertyId: '', propertyName: '');
                },
                // SMS history was never built (no screen exists anywhere in
                // the app), but navigation_config.dart's "sms_history" nav
                // item still links here -- without a route entry, tapping it
                // crashed with "Could not find a generator for route
                // RouteSettings(/rental/sms, null)" for anyone holding the
                // view_sms_history permission. Coming-soon stub until the
                // real feature is built.
                "/rental/sms": (final BuildContext context) =>
                    const ComingSoonScreen(),
                "/rental/agreements": (final BuildContext context) =>
                    const LeaseAgreementsScreen(),
                "/rental/create-agreement": (final BuildContext context) =>
                    const LeaseAgreementWizardScreen(),
                "/rental/agreement-details": (final BuildContext context) {
                  final args = ModalRoute.of(context)?.settings.arguments;
                  if (args is Map) {
                    return LeaseDetailsScreen(agreement: Map<String, dynamic>.from(args));
                  }
                  return const ComingSoonScreen();
                },
                "/rental/helpdesk": (final BuildContext context) =>
                    const HelpdeskScreen(),
                "/rental/lease-templates": (final BuildContext context) =>
                    const LeaseAgreementsScreen(), // Placeholder for templates
                "/register-business": (final BuildContext context) {
                  final dynamic args = ModalRoute.of(context)?.settings.arguments;
                  if (args is Map) {
                    return RegisterBusinessScreen(
                      initialEmail: args['email']?.toString(),
                      initialPhone: args['phone']?.toString(),
                    );
                  }
                  return const RegisterBusinessScreen();
                },
              },
            ),
          ),
        ),
      );

  ThemeData _buildTheme(BuildContext context) => ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: ThemeConstants.primaryBlue,
        colorScheme: ColorScheme.dark(
          primary: AppColors.primary,
          surface: ThemeConstants.primaryBlue,
          onSurface: Colors.white,
          onPrimary: Colors.white,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'NotoSans',

        // Responsive theme components
        appBarTheme: AppStyles.appBarTheme(context),
        cardTheme: AppStyles.cardTheme(context),
        floatingActionButtonTheme: AppStyles.fabTheme(context),
        bottomNavigationBarTheme: AppStyles.bottomNavTheme(context),

        // Date picker styling to align with brand blue background
        datePickerTheme: DatePickerThemeData(
          backgroundColor: ThemeConstants.primaryBlue,
          headerBackgroundColor: ThemeConstants.primaryBlue,
          headerForegroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          dayForegroundColor: const WidgetStatePropertyAll<Color>(Colors.white),
          yearForegroundColor:
              const WidgetStatePropertyAll<Color>(Colors.white),
          weekdayStyle: const TextStyle(color: Colors.white70),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: ThemeConstants.primaryBlue,
          surfaceTintColor: Colors.transparent,
        ),

        // Input decoration theme
        inputDecorationTheme: AppStyles.inputDecorationTheme(context),

        // Button themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: AppStyles.primaryButton(context),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: AppStyles.secondaryButton(context),
        ),

        // Text theme configured for crisp white text on dark background
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
              fontFamily: 'NotoSans',
            ),

        // Responsive spacing and sizing
        materialTapTargetSize: MaterialTapTargetSize.padded,
        useMaterial3: true,
      );
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _LanguageSelectionPage extends StatelessWidget {
  const _LanguageSelectionPage({required this.onSelected});
  final Future<void> Function(String code) onSelected;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeConstants.primaryBlue,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loc.translate('select_language'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => onSelected('sw'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(loc.translate('swahili')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => onSelected('en'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(loc.translate('english')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _languageChosenThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((final Duration _) async {
      await Provider.of<AuthProvider>(context, listen: false).initialize();
    });
  }

  Future<void> _onLanguageChosen(String code) async {
    await LocalizationService.instance.changeLanguage(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_language', code);
    if (mounted) setState(() => _languageChosenThisSession = true);
  }

  Widget _resolveServiceHome(AuthProvider authProvider) {
    final List<String> allowed = _allowedServicesFor(authProvider.user!);
    if (allowed.length == 1) {
      return _ServiceHomeFor(service: allowed.first, authProvider: authProvider);
    }
    return ServiceSelectionScreen(allowedServices: allowed);
  }

  void _goToLogin(BuildContext ctx) {
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  void _goToRegister(BuildContext ctx) {
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(builder: (_) => const RegisterBusinessScreen()),
    );
  }

  @override
  Widget build(final BuildContext context) =>
      Consumer2<AuthProvider, LocalizationService>(
        builder: (ctx, authProvider, localizationService, _) {
          // Splash while auth initialises
          if (authProvider.isLoading) {
            return AppSplashScreen(
              appName: localizationService.translate('app_name'),
              message: localizationService.translate('loading'),
            );
          }

          // ── Authenticated ────────────────────────────────────────────────
          if (authProvider.isAuthenticated && authProvider.user != null) {
            // Admin-issued default password: must be replaced before anything else.
            if (authProvider.user!.mustChangePassword) {
              return const ForcePasswordChangeScreen();
            }
            if (!_languageChosenThisSession) {
              return _LanguageSelectionPage(onSelected: _onLanguageChosen);
            }
            // Go straight to the user's service home — no landing interstitial
            return _resolveServiceHome(authProvider);
          }

          // ── Not authenticated — premium landing is the public default ────
          // Wrap AppLandingScreen in a Stack to overlay the "Ingia" button
          // without touching AppLandingScreen's own code.
          return Stack(
            children: [
              // The premium 3-slide landing (unchanged)
              AppLandingScreen(
                onContinue: () => _goToLogin(context),
              ),

              // Language icon + Ingia pill pinned top-right. The extra
              // fixed margin (not just the device's safe-area inset) keeps
              // it clear of the status bar / rounded corners on devices
              // that report a small or zero padding.top.
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                right: 16,
                // This Stack has no Scaffold, so nothing above these buttons is a Material and their text
                // would use MaterialApp's "Material is missing" style: a yellow double underline in a
                // monospace font. A transparent Material gives it the app's normal text style (no
                // background, no ink: the pills draw themselves).
                child: Material(
                  type: MaterialType.transparency,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LangToggleButton(onChanged: _onLanguageChosen),
                      const SizedBox(width: 8),
                      _JisajiliPill(onTap: () => _goToRegister(context)),
                      const SizedBox(width: 8),
                      _IngiaPill(onTap: () => _goToLogin(context)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
}

/// Glass language-toggle icon. Cycles EN ↔ SW and persists the choice.
class _LangToggleButton extends StatelessWidget {
  const _LangToggleButton({required this.onChanged});
  final Future<void> Function(String code) onChanged;

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalizationService>(
      builder: (_, loc, __) {
        final isSw = loc.isSwahili;
        return GestureDetector(
          onTap: () => onChanged(isSw ? 'en' : 'sw'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 5),
                Text(
                  isSw ? 'SW' : 'EN',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Small pill button that sits on top of the public landing slides.
class _IngiaPill extends StatelessWidget {
  const _IngiaPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF00E5FF),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withOpacity(0.45),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.login_rounded, color: Colors.black87, size: 16),
            const SizedBox(width: 6),
            Text(
              loc.translate('login'),
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Outlined counterpart of [_IngiaPill]: a business owner registers here, then
/// waits for a super admin to approve and assign their services.
class _JisajiliPill extends StatelessWidget {
  const _JisajiliPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00E5FF), width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, color: Color(0xFF00E5FF), size: 16),
            const SizedBox(width: 6),
            Text(
              loc.isSwahili ? 'Jisajili' : 'Register',
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Routes straight to the one service this account is bound to - no
/// picker. Persists the choice to `selected_service` too, since several
/// other screens (permissions/user management, the service switcher)
/// still read that pref as their context.
class _ServiceHomeFor extends StatefulWidget {
  const _ServiceHomeFor({required this.service, required this.authProvider});
  final String service;
  final AuthProvider authProvider;

  @override
  State<_ServiceHomeFor> createState() => _ServiceHomeForState();
}

class _ServiceHomeForState extends State<_ServiceHomeFor> {
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString('selected_service', widget.service));
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.service) {
      case 'inventory':
        return const InventoryHome();
      case 'transport':
        return const ModernDashboardScreen();
      case 'rental':
        return const RentalMainScreen();
      default:
        // Unrecognized service value — fall back to role-based routing.
        // super_admin only goes directly to ModernDashboard; admin follows the
        // same service-binding path as other roles (enforced by ServiceGuard).
        final String role = widget.authProvider.user?.role ?? '';
        if (role == 'super_admin') {
          return const ModernDashboardScreen();
        }
        if (role == 'sales_officer' || role == 'manager' || role == 'operator') {
          return const InventoryHome();
        }
        if (role == 'vendor') {
          return const VendorDashboardScreen();
        }
        return const DriverDashboardScreen();
    }
  }
}

// Role → allowed services mapping lives in utils/role_services.dart.
// Alias so existing call-sites in this file don't need changing.
List<String> _servicesForRole(String role) => servicesForRole(role);

/// The services a user may pick from: their explicit bindings if any exist,
/// else whatever their role implies (e.g. super_admin -> all three).
/// Single source of truth so "Select Service" always reflects who's
/// actually logged in, instead of a route that forgets to look.
List<String> _allowedServicesFor(UserData user) {
  final List<String> bound = user.serviceTypes;
  if (bound.isNotEmpty) return bound;
  return _servicesForRole(user.role ?? '');
}
