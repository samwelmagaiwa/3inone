// ignore_for_file: cascade_invocations
// ignore_for_file: directives_ordering, avoid_catches_without_on_clauses, prefer_foreach, unnecessary_brace_in_string_interps
import "dart:async";
import "dart:math" as math;
import "dart:ui";

import "package:fl_chart/fl_chart.dart";
import "package:flutter/material.dart";
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import "../../models/login_response.dart";
import "../../providers/auth_provider.dart";
import "../../services/api_service.dart";
import "../../services/app_events.dart";
import "../../services/localization_service.dart";
import "../../services/navigation_builder.dart";
import "../../utils/responsive_helper.dart";
import "../../config/api_config.dart";
import "../../constants/theme_constants.dart";
import "../receipts/receipts_screen.dart";
import "../payments/payments_screen.dart";
import "../admin/debts_management_screen.dart";
import "../admin/drivers_management_screen.dart";
import "../../main.dart";
import "../../widgets/month_selector.dart";

class ModernDashboardScreen extends StatefulWidget {
  const ModernDashboardScreen({super.key});

  @override
  State<ModernDashboardScreen> createState() => _ModernDashboardScreenState();
}

class _ModernDashboardScreenState extends State<ModernDashboardScreen>
    with TickerProviderStateMixin {
  Timer? _autoRefreshTimer;
  String? _lastSnapshotSig;
  // Use a Scaffold key to safely control the drawer from anywhere in the tree
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AnimationController _animationController;
  late AnimationController _chartAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _chartAnimation;

  final ApiService _apiService = ApiService();
  Map<String, dynamic> _dashboardData = <String, dynamic>{};
  bool _isLoading = true;
  final PageController _cardController = PageController();
  int _selectedMonth = DateTime.now().month;

  // Badge counters for drawer notifications (only reminders kept)
  int _remindersCount = 0;

  // Event subscription for automatic refresh
  late StreamSubscription<AppEvent> _eventSubscription;

  // Colors for the modern theme - use shared ThemeConstants
  static const Color primaryBlue = ThemeConstants.primaryBlue;
  static const Color cardColor = ThemeConstants.cardColor;
  static const Color textPrimary = ThemeConstants.textPrimary;
  static const Color textSecondary = ThemeConstants.textSecondary;
  static const Color accentColor = ThemeConstants.primaryOrange;

  final List<String> months = <String>[
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadDashboardData();
    _startAutoRefresh();

    // Listen to app events for automatic refresh
    _eventSubscription = AppEvents.instance.stream.listen((event) {
      switch (event.type) {
        case AppEventType.receiptsUpdated:
        case AppEventType.paymentsUpdated:
        case AppEventType.debtsUpdated:
        case AppEventType.dashboardShouldRefresh:
          // Refresh dashboard when payments, receipts, or debts are updated
          if (mounted) {
            _loadDashboardData();
          }
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _chartAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _slideAnimation = Tween<double>(
      begin: 50,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _chartAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _chartAnimationController,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _eventSubscription.cancel();
    _autoRefreshTimer?.cancel();
    _animationController.dispose();
    _chartAnimationController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    try {
      // Guard: only load if authenticated
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (!auth.isAuthenticated) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        // Ensure content becomes visible even if we don't load data
        try {
          unawaited(_animationController.forward());
        } on Exception catch (_) {}
        return;
      }

      setState(() {
        _isLoading = true;
      });

      // Load real-time data directly from database tables via comprehensive API calls
      await _loadComprehensiveRealTimeData();

      // Load revenue chart data for visualization
      await _loadRevenueChartData(
          year: DateTime.now().year, month: _selectedMonth);

      // Load additional badge counts (reminders)
      if (!mounted) return;
      await _loadAdditionalBadgeCounts();

      // Update UI and start animations
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        unawaited(_animationController.forward());
        unawaited(Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _chartAnimationController.forward();
          }
        }));
      }
    } on Exception catch (_) {
      // No mock/fallback data; just surface the error and keep zeros
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Make sure main content is shown (animation opacity > 0)
        try {
          unawaited(_animationController.forward());
        } on Exception catch (_) {}
        _showErrorSnackBar(
            "Backend haipatikani. Tafadhali jaribu tena baadaye.");
      }
    }
  }

  /// Load comprehensive real-time data using existing backend endpoints
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      await _pollForUpdates();
    });
  }

  Future<void> _pollForUpdates() async {
    if (!mounted || _isLoading) return;
    try {
      final Map<String, dynamic> dashboardResponse =
          await _apiService.getDashboardData();
      final Map<String, dynamic> main =
          _extractDataFromResponse(dashboardResponse);
      final String sig = _buildSignatureFromMain(main);
      if (sig != _lastSnapshotSig) {
        await _loadDashboardData();
      }
    } catch (_) {
      // ignore network errors during polling
    }
  }

  String _buildSignatureFromMain(Map<String, dynamic> m) {
    final List<dynamic> parts = [
      m['payments_today'],
      m['payments_this_week'],
      m['payments_this_month'],
      m['total_drivers'],
      m['total_vehicles'],
      m['active_drivers'],
      m['active_vehicles'],
      m['pending_receipts'] ?? 0,
      if (m['recent_transactions'] is List)
        (m['recent_transactions'] as List).length
      else
        0,
    ];
    return parts.map((e) => (e ?? 0).toString()).join('|');
  }

  Future<void> _loadComprehensiveRealTimeData() async {
    try {
      // Use main dashboard endpoint which returns complete and accurate data
      final Map<String, dynamic> dashboardResponse =
          await _apiService.getDashboardData();

      // Extract data from the main dashboard response
      final Map<String, dynamic> mainData =
          _extractDataFromResponse(dashboardResponse);

      // Initialize dashboard data and populate with main response data
      _dashboardData = _getEmptyDashboardData();

      // Map the dashboard response to our expected data structure
      _dashboardData.addAll({
        // Revenue data from main endpoint
        'daily_revenue': _toDouble(mainData['payments_today'] ?? 0),
        'weekly_revenue': _toDouble(mainData['payments_this_week'] ?? 0),
        'monthly_revenue': _toDouble(mainData['payments_this_month'] ?? 0),

        // Driver and vehicle counts
        'drivers_count': _toInt(mainData['total_drivers'] ?? 0),
        'total_drivers': _toInt(mainData['total_drivers'] ?? 0),
        'active_drivers': _toInt(mainData['active_drivers'] ?? 0),
        'devices_count': _toInt(mainData['total_vehicles'] ?? 0),
        'total_vehicles': _toInt(mainData['total_vehicles'] ?? 0),
        'active_vehicles': _toInt(mainData['active_vehicles'] ?? 0),

        // Recent transactions
        'recent_transactions': mainData['recent_transactions'] ?? [],
      });

      // Fetch additional counts (unpaid debts, generated receipts, pending receipts)
      try {
        final List<Map<String, dynamic>> extras =
            await Future.wait<Map<String, dynamic>>([
          _loadUnpaidDebtsCountFromExisting(),
          _loadPaymentReceiptsCountFromExisting(),
          _loadPendingReceiptsCountFromExisting(),
        ]);
        for (final Map<String, dynamic> m in extras) {
          _dashboardData.addAll(m);
        }
      } on Exception catch (_) {
        // ignore supplemental errors
      }

      // Fetch all-time revenue to display on the balance card
      try {
        final Map<String, dynamic> revResp =
            await _apiService.getAdminRevenueReport();
        final Map<String, dynamic> revData = _extractDataFromResponse(revResp);
        _dashboardData['total_revenue'] = _toDouble(
          revData['total_revenue'] ??
              revData['revenue'] ??
              revData['total_amount'] ??
              0,
        );
      } on Exception catch (_) {
        // If unavailable, fall back to monthly revenue already set
        _dashboardData['total_revenue'] =
            _dashboardData['monthly_revenue'] ?? 0;
      }

      // Update snapshot signature for polling comparison
      _lastSnapshotSig = _buildSignatureFromMain(mainData);

      // Badge counts derived directly in _buildDrawer from _dashboardData
    } on Exception catch (e) {
      // Initialize with empty data if all fails
      _dashboardData = _getEmptyDashboardData();
      if (mounted) {
        _showErrorSnackBar("Imeshindikana kupakia data za dashboard: ${e}");
      }
    }
  }

  /// Load unpaid debts count aligned with the DebtsManagementScreen list.
  /// We prefer counting unique drivers who currently have any outstanding debt,
  /// so the value matches the "Ana deni" driver tiles you see in that screen.
  Future<Map<String, dynamic>> _loadUnpaidDebtsCountFromExisting() async {
    try {
      int endpointCount = 0;
      // 1) Try new endpoint first for unpaid debts (is_paid = 0)
      try {
        final response = await _apiService.getUnpaidDebtsCount();
        final data = _extractDataFromResponse(response);
        endpointCount =
            _toInt(data['count'] ?? data['unpaid_debts_count'] ?? 0);
      } on Exception {
        // 2) Fallback to a generic summary if endpoint not available
        try {
          final response = await _apiService.getPaymentSummary();
          final data = _extractDataFromResponse(response);
          endpointCount = _toInt(
            data['unpaid_debts'] ??
                data['outstanding_debts'] ??
                data['total_debts'] ??
                data['pending_payments'] ??
                0,
          );
        } catch (_) {
          endpointCount = 0;
        }
      }

      // 3) Compute unique debtor drivers via /admin/debts/drivers to match DebtsManagementScreen UI
      int uniqueDebtorDrivers = endpointCount; // default
      try {
        final Map<String, dynamic> resp =
            await _apiService.getDebtDrivers(limit: 500);
        final Map<String, dynamic>? data =
            resp['data'] as Map<String, dynamic>?;
        final List<dynamic> list =
            (data?['drivers'] as List<dynamic>?) ?? <dynamic>[];
        uniqueDebtorDrivers = list.where((e) {
          if (e is Map<String, dynamic>) {
            final m = e;
            final num total = (m['total_debt'] is num)
                ? (m['total_debt'] as num)
                : num.tryParse(m['total_debt']?.toString() ?? '0') ?? 0;
            return total > 0;
          }
          return false;
        }).length;
      } catch (_) {
        // ignore; keep endpointCount
      }

      // Prefer the unique drivers count to match what the user sees in DebtsManagementScreen
      final int finalCount = uniqueDebtorDrivers;
      return {'unpaid_debts_count': finalCount};
    } on Exception {
      return {'unpaid_debts_count': 0};
    }
  }

  /// Load generated receipts count from payment_receipts table WHERE receipt_status = 'generated'
  Future<Map<String, dynamic>> _loadPaymentReceiptsCountFromExisting() async {
    try {
      // Try new endpoint first for generated receipts (receipt_status = 'generated')
      try {
        final response = await _apiService.getGeneratedReceiptsCount();
        final data = _extractDataFromResponse(response);
        final int cnt =
            _toInt(data['count'] ?? data['generated_receipts_count'] ?? 0);
        return {
          'payment_receipts_count': cnt,
          'receipts_count': cnt,
        };
      } on Exception {
        // Fallback to existing receipts endpoint and filter generated receipts
        final response = await _apiService.getPaymentReceipts();
        final data = _extractDataFromResponse(response);

        // Try to extract generated receipts count from response
        int generatedCount = 0;
        if (data['receipts'] is List) {
          final List<dynamic> receipts = data['receipts'] as List<dynamic>;
          generatedCount = receipts.where((receipt) {
            if (receipt is Map<String, dynamic>) {
              return receipt['receipt_status'] == 'generated' ||
                  receipt['status'] == 'generated';
            }
            return false;
          }).length;
        } else {
          // If no filtering possible, use total count as fallback
          generatedCount = _extractTotalCountFromResponse(response);
        }

        return {
          'payment_receipts_count': generatedCount,
          'receipts_count': generatedCount,
        };
      }
    } on Exception {
      return {'payment_receipts_count': 0, 'receipts_count': 0};
    }
  }

  /// Load pending receipts count from payments table WHERE receipt_status = 'pending'
  /// To keep consistency with the "Toa Risiti" page, count total pending receipt items
  /// (same as what users see in the receipts screen list).
  Future<Map<String, dynamic>> _loadPendingReceiptsCountFromExisting() async {
    try {
      int endpointCount = 0;
      // 1) Try new endpoint first for pending receipts (receipt_status = 'pending')
      try {
        final response = await _apiService.getPendingReceiptsCount();
        final data = _extractDataFromResponse(response);
        endpointCount =
            _toInt(data['count'] ?? data['pending_receipts_count'] ?? 0);
      } on Exception {
        // ignore and keep endpointCount = 0
      }

      // 2) Fetch pending receipts list and count TOTAL ITEMS to match ReceiptsScreen UI
      int totalItemsCount = endpointCount; // default to endpoint result
      try {
        final response = await _apiService.getPendingReceipts();
        final data = _extractDataFromResponse(response);

        // Common shapes observed:
        // - { pending_receipts: [ { driver: { id, ... }, ... } ] }
        // - { data: [ ...same as above... ] }
        // - Legacy: { payments: [ { driver_id, receipt_status, ... } ] } -> filter pending
        final List<dynamic> list =
            (data['pending_receipts'] as List<dynamic>?) ??
                (data['data'] as List<dynamic>?) ??
                (data['payments'] as List<dynamic>?) ??
                const <dynamic>[];

        // Count total pending receipt items (same logic as ReceiptsScreen)
        int validItemsCount = 0;
        final Set<String> uniqueDriverIds = <String>{}; // for debug info
        for (final dynamic item in list) {
          if (item is Map<String, dynamic>) {
            // Driver nested - always count as valid pending receipt
            if (item['driver'] is Map) {
              validItemsCount++;
              final Map<String, dynamic> d =
                  (item['driver'] as Map).cast<String, dynamic>();
              final String id = d['id']?.toString() ?? '';
              if (id.isNotEmpty) uniqueDriverIds.add(id);
              continue;
            }
            // Flat driver_id (legacy payments shape), ensure it's pending
            final String driverId = item['driver_id']?.toString() ?? '';
            final String status = item['receipt_status']?.toString() ?? '';
            if (driverId.isNotEmpty &&
                (status.isEmpty || status == 'pending')) {
              validItemsCount++;
              uniqueDriverIds.add(driverId);
            }
          }
        }
        if (validItemsCount > 0) {
          totalItemsCount = validItemsCount;
        } else {
          // As a last resort, fall back to total count extraction
          totalItemsCount = list.isNotEmpty
              ? list.length
              : _extractTotalCountFromResponse(response);
        }
      } catch (_) {
        // ignore; keep endpointCount
      }

      // Return total items count to match ReceiptsScreen (pending filter) UI exactly
      final int finalCount = totalItemsCount;
      return {'pending_receipts_count': finalCount};
    } on Exception {
      return {'pending_receipts_count': 0};
    }
  }

  /// Load revenue chart data for visualization
  Future<void> _loadRevenueChartData({int? year, int? month}) async {
    try {
      DateTime? start;
      DateTime? end;
      if (year != null && month != null) {
        start = DateTime(year, month);
        end = DateTime(year, month + 1, 0);
      }
      final List<dynamic> chart = await _apiService.getRevenueChart(
        startDate: start,
        endDate: end,
      );
      // Parse entries supporting both 'amount' and 'revenue' keys and capture dates
      List<double> values = <double>[];
      List<String> dates = <String>[];
      for (final e in chart) {
        if (e is Map) {
          final dynamic rawVal = e['amount'] ??
              e['total'] ??
              e['total_amount'] ??
              e['revenue'] ??
              e['paid'] ??
              e['paid_amount'] ??
              e['value'];
          double val = 0;
          if (rawVal is num) {
            val = rawVal.toDouble();
          } else if (rawVal != null) {
            final String cleaned =
                rawVal.toString().replaceAll(RegExp(r'[^0-9\\.-]'), '');
            val = double.tryParse(cleaned) ?? 0.0;
          }
          values.add(val);
          final String? dateStr =
              (e['date'] ?? e['day'] ?? e['label'] ?? e['created_at'])
                  ?.toString();
          dates.add(_formatDateLabel(dateStr));
        } else if (e is num) {
          values.add(e.toDouble());
          dates.add('');
        }
      }

      // If the API returned zeros across the board, rebuild series from payment history
      final bool allZero = values.isEmpty || values.every((v) => v == 0);
      if (allZero) {
        try {
          // Build per-day map for the selected range
          final DateTime rangeStart = start ?? DateTime(end!.year, end.month);
          final DateTime rangeEnd = end ?? DateTime.now();
          final Map<String, double> perDay = <String, double>{};

          final Map<String, dynamic> payments =
              await _apiService.getPaymentHistory(
            startDate: rangeStart,
            endDate: rangeEnd,
            limit: 2000,
          );
          final dynamic root = payments['data'] ?? payments;
          List<dynamic> list = const <dynamic>[];
          if (root is Map && root['data'] is List) {
            list = (root['data'] as List).cast<dynamic>();
          } else if (root is Map && root['payments'] is List) {
            list = (root['payments'] as List).cast<dynamic>();
          } else if (root is List) {
            list = root.cast<dynamic>();
          }

          double readAmount(Map<String, dynamic> m) {
            final dynamic raw = m['amount'] ??
                m['paid_amount'] ??
                m['amount_received'] ??
                m['total'] ??
                m['total_amount'] ??
                m['revenue'] ??
                m['value'];
            if (raw is num) return raw.toDouble();
            if (raw is String) {
              final String cleaned = raw.replaceAll(RegExp(r'[^0-9\\.-]'), '');
              return double.tryParse(cleaned) ?? 0.0;
            }
            return 0;
          }

          String? readDate(Map<String, dynamic> m) {
            final String? s = (m['paid_at'] ??
                    m['date'] ??
                    m['created_at'] ??
                    m['updated_at'])
                ?.toString();
            return s;
          }

          for (final dynamic it in list) {
            if (it is Map) {
              final Map<String, dynamic> m = it.cast<String, dynamic>();
              final String? ds = readDate(m);
              if (ds == null) continue;
              final DateTime? dt = DateTime.tryParse(ds);
              if (dt == null) continue;
              if (dt.isBefore(DateTime(
                      rangeStart.year, rangeStart.month, rangeStart.day)) ||
                  dt.isAfter(
                      DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day))) {
                continue;
              }
              final String key = _formatDateLabel(dt.toIso8601String());
              perDay[key] = (perDay[key] ?? 0) + readAmount(m);
            }
          }

          // Rebuild ordered series for the entire month range
          final List<String> rebuiltDates = <String>[];
          final List<double> rebuiltValues = <double>[];
          DateTime cursor =
              DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
          while (!cursor
              .isAfter(DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day))) {
            final String key = _formatDateLabel(cursor.toIso8601String());
            rebuiltDates.add(key);
            rebuiltValues.add(perDay[key] ?? 0.0);
            cursor = cursor.add(const Duration(days: 1));
          }

          dates = rebuiltDates;
          values = rebuiltValues;
        } catch (_) {
          // keep original zeros
        }
      }

      // Ensure today's value is aligned with the Daily Revenue card when viewing the current month
      if (year != null && month != null) {
        final String todayLabel =
            _formatDateLabel(DateTime.now().toIso8601String());
        final int idx = dates.indexOf(todayLabel);
        final double todayCard = _toDouble(_dashboardData['daily_revenue']);
        if (idx >= 0) {
          if (todayCard > 0 && (idx < values.length && values[idx] <= 0)) {
            values[idx] = todayCard;
          }
        } else if (month == DateTime.now().month &&
            DateTime.now().year == year) {
          dates.add(todayLabel);
          values.add(todayCard);
        }
      }
      if (values.isNotEmpty) {
        // Use the full range for the selected month; if no range specified, fallback to last 30 days
        _dashboardData['weekly_earnings'] = values;
        _dashboardData['weekly_dates'] = dates.length == values.length
            ? dates
            : List<String>.filled(values.length, '');
        // Keep monthly card in sync when we loaded a specific month
        if (year != null && month != null) {
          final double sum = values.fold<double>(0, (a, b) => a + b);
          _dashboardData['monthly_revenue'] = sum;
        }
      } else {
        _dashboardData['weekly_earnings'] = <double>[];
        _dashboardData['weekly_dates'] = <String>[];
      }
    } on Exception {
      // Set empty chart data if loading fails
      _dashboardData['weekly_earnings'] = <double>[];
      _dashboardData['weekly_dates'] = <String>[];
    }
  }

  /// Extract data from API response handling Laravel ResponseHelper format
  Map<String, dynamic> _extractDataFromResponse(Map<String, dynamic> response) {
    // Handle both shapes:
    // - {status: 'success', data: {...}}
    // - {success: true, data: {...}}
    // - Or already a data map with expected keys
    if (response.containsKey('data') &&
        response['data'] is Map<String, dynamic>) {
      return response['data'] as Map<String, dynamic>;
    }
    if ((response['success'] == true) || (response['status'] == 'success')) {
      final dynamic data = response['data'];
      if (data is Map<String, dynamic>) return data;
    }
    return response;
  }

  /// Get empty dashboard data structure with defaults
  Map<String, dynamic> _getEmptyDashboardData() {
    return <String, dynamic>{
      // Revenue data
      'daily_revenue': 0,
      'weekly_revenue': 0,
      'monthly_revenue': 0,
      'net_profit': 0,
      'total_saved': 0,
      'saving_rate': 0,

      // Database table counts
      'drivers_count': 0,
      'devices_count': 0,
      'unpaid_debts_count': 0,
      'payment_receipts_count': 0,
      'pending_receipts_count': 0,

      // Legacy compatibility
      'total_drivers': 0,
      'total_vehicles': 0,
      'active_drivers': 0,
      'active_vehicles': 0,
      'pending_payments': 0,
      'receipts_count': 0,

      // Chart data
      'weekly_earnings': <double>[],
      'weekly_dates': <String>[],
      'monthly_data': <dynamic>[],
      'recent_transactions': <dynamic>[],

      // Costs
      'fuel_costs': 0,
      'maintenance_costs': 0,
    };
  }

  void _showErrorSnackBar(String message) {
    ThemeConstants.showErrorSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) => Scaffold(
        key: _scaffoldKey,
        drawer:
            _buildDrawer(localizationService), // Add drawer with localization
        appBar: _buildAppBar(),
        bottomNavigationBar: _buildFooter(),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            color: primaryBlue,
          ),
          child: SafeArea(
            child: _isLoading
                ? _buildLoadingScreen(localizationService)
                : _buildMainContent(localizationService),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(LocalizationService localizationService) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ThemeConstants.buildResponsiveLoadingWidget(
          context,
          message: localizationService.translate('loading_dashboard'),
        ),
      ),
    );
  }

  Widget _buildMainContent(LocalizationService localizationService) =>
      FadeTransition(
        opacity: _fadeAnimation,
        child: AnimatedBuilder(
          animation: _slideAnimation,
          builder: (BuildContext context, Widget? child) => Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: RefreshIndicator(
              onRefresh: _loadDashboardData,
              backgroundColor: Colors.white,
              color: primaryBlue,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildBalanceCard(),
                      ResponsiveHelper.verticalSpace(2),
                      _buildStatsCards(),
                      ResponsiveHelper.verticalSpace(2),
                      _buildChartSection(),
                      ResponsiveHelper.verticalSpace(1),
                      _buildQuickActions(localizationService),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  PreferredSizeWidget _buildAppBar() {
    final AuthProvider authProvider =
        Provider.of<AuthProvider>(context, listen: false);
    final LocalizationService loc =
        Provider.of<LocalizationService>(context, listen: false);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/app_icon.png',
            height: 32.h,
            width: 32.h,
          ),
          SizedBox(width: 10.w),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.white, ThemeConstants.primaryCyan],
            ).createShader(bounds),
            child: Text(
              loc.translate('app_name'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 22.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded, color: textPrimary),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded, color: textPrimary),
          onPressed: () => _navigateToReceiptsList(filter: 'all'),
        ),
      ],
    );
  }

  Widget _buildBalanceCard() {
    // Use MediaQuery-driven sizing to avoid overflow on short devices
    final Size size = MediaQuery.of(context).size;
    final bool isShort = size.height < 700;

    // Compute a compact but readable card height
    double cardHeight = size.height * (isShort ? 0.11 : 0.14);
    cardHeight = cardHeight.clamp(100.0, 130.0);

    final double avatarSide = (size.width * 0.10).clamp(32.0, 42.0);
    final double gapLarge = isShort ? 6.0 : 8.0; // tighter spacing
    final double gapMid = isShort ? 4.0 : 6.0;
    final double gapSmall = isShort ? 3.0 : 4.0;

    final bool canViewRevenue =
        Provider.of<AuthProvider>(context, listen: false)
            .user
            ?.hasPermission('view_reports_transport') ??
        false;

    if (!canViewRevenue) return const SizedBox.shrink();

    return SizedBox(
      height: cardHeight,
      child: PageView(
        controller: _cardController,
        children: <Widget>[
          _buildGlassCard(
            child: Padding(
              // Add a bit more bottom padding so the subtitle doesn't touch the card border
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: avatarSide,
                        height: avatarSide,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(avatarSide / 2),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet,
                          color: textPrimary,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.more_horiz,
                        color: textSecondary,
                      ),
                    ],
                  ),
                  SizedBox(height: gapLarge),
                  // Removed user name from card; keep spacing compact
                  SizedBox(height: gapMid),
                  // Make amount text scale down to fit to avoid overflow on short/tight layouts
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "TSH ${_formatCurrency(_dashboardData["total_revenue"] ?? _dashboardData["monthly_revenue"])}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: isShort
                              ? (ResponsiveHelper.h2 * 0.9)
                              : ResponsiveHelper.h2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Subtitle with safe spacing from the bottom border
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Consumer<LocalizationService>(
                        builder: (context, localizationService, child) =>
                            Padding(
                          padding: EdgeInsets.only(bottom: gapSmall),
                          child: Text(
                            localizationService.translate("total_revenue"),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: isShort
                                  ? (ResponsiveHelper.bodyL * 0.95)
                                  : ResponsiveHelper.bodyL,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) {
        // Active vs total for drivers and vehicles (exact backend values)
        final int activeDrivers = _toInt(_dashboardData['active_drivers'] ?? 0);
        final int totalDrivers = _toInt(
          _dashboardData['total_drivers'] ??
              _dashboardData['drivers_count'] ??
              0,
        );
        final int activeVehicles =
            _toInt(_dashboardData['active_vehicles'] ?? 0);
        final int totalVehicles = _toInt(
          _dashboardData['total_vehicles'] ??
              _dashboardData['devices_count'] ??
              0,
        );

        final user = Provider.of<AuthProvider>(context, listen: false).user;
        final bool canViewDrivers = user?.hasPermission('manage_drivers_transport') ?? false;
        final bool canViewVehicles = user?.hasPermission('manage_vehicles_transport') ?? false;
        final bool canViewRevenue = user?.hasPermission('view_reports_transport') ?? false;

        return Column(
          children: <Widget>[
            // First row: Revenue cards (Daily, Weekly, Monthly)
            if (canViewRevenue)
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildStatCard(
                      localizationService.translate("daily_revenue"),
                      "TSH ${_formatCurrency(_dashboardData["daily_revenue"])}",
                      "",
                      Icons.today,
                      true,
                    ),
                  ),
                  ResponsiveHelper.horizontalSpace(4),
                  Expanded(
                    child: _buildStatCard(
                      localizationService.translate("weekly_revenue"),
                      "TSH ${_formatCurrency(_dashboardData["weekly_revenue"])}",
                      "",
                      Icons.calendar_view_week,
                      false,
                    ),
                  ),
                ],
              ),
            if (canViewRevenue) ResponsiveHelper.verticalSpace(2),
            if (canViewRevenue)
              _buildStatCard(
                localizationService.translate("monthly_revenue"),
                "TSH ${_formatCurrency(_dashboardData["monthly_revenue"])}",
                "",
                Icons.calendar_month,
                false,
              ),
            if (canViewRevenue && (canViewDrivers || canViewVehicles))
              ResponsiveHelper.verticalSpace(2),

            // Second row: Drivers and Vehicles
            Row(
              children: <Widget>[
                if (canViewDrivers)
                  Expanded(
                    child: _buildStatCard(
                      localizationService.translate("drivers"),
                      "$activeDrivers",
                      "${localizationService.translate("active")} $activeDrivers/$totalDrivers",
                      Icons.people,
                      true,
                    ),
                  ),
                if (canViewDrivers && canViewVehicles)
                  ResponsiveHelper.horizontalSpace(4),
                if (canViewVehicles)
                  Expanded(
                    child: _buildStatCard(
                      localizationService.translate("vehicles"),
                      "$activeVehicles",
                      "${localizationService.translate("active")} $activeVehicles/$totalVehicles",
                      Icons.directions_car,
                      true,
                    ),
                  ),
                if (canViewDrivers || canViewVehicles)
                  ResponsiveHelper.horizontalSpace(4),
                if (canViewDrivers || canViewVehicles)
                  const Expanded(child: SizedBox()),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String change,
    IconData icon,
    bool isPositive,
  ) =>
      _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    icon,
                    color: textSecondary,
                    size: ResponsiveHelper.iconSizeM,
                  ),
                  const Spacer(),
                  _buildCardDropdownMenu(title, value, icon),
                ],
              ),
              ResponsiveHelper.verticalSpace(1.5),
              Text(
                title,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: ResponsiveHelper.bodyS,
                  fontWeight: FontWeight.w500,
                ),
              ),
              ResponsiveHelper.verticalSpace(0.5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: ResponsiveHelper.bodyL,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ResponsiveHelper.verticalSpace(0.5),
              Text(
                change,
                style: TextStyle(
                  color:
                      isPositive ? Colors.green.shade300 : Colors.red.shade300,
                  fontSize: ResponsiveHelper.bodyS,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildChartSection() => _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildMonthSelector(),
              const SizedBox(height: 24),
              SizedBox(
                height: MediaQuery.of(context).size.height < 700 ? 200 : 240,
                child: AnimatedBuilder(
                  animation: _chartAnimation,
                  builder: (BuildContext context, Widget? child) {
                    final List<double> points =
                        (_dashboardData["weekly_earnings"] as List?)
                                ?.map<double>(_toDouble)
                                .toList() ??
                            <double>[];
                    if (points.isEmpty) {
                      return Consumer<LocalizationService>(
                        builder: (context, localizationService, child) =>
                            Center(
                          child: Text(
                            localizationService.translate('no_chart_data'),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      );
                    }
                    final double dataMax = points.reduce(math.max);
                    final double displayMax =
                        _niceCeilValue((dataMax <= 0 ? 1 : dataMax) * 1.1);
                    final double interval =
                        math.max(1, _niceStep(displayMax / 5));
                    final String maxLabel = _formatShort(displayMax);
                    final double reserved =
                        (maxLabel.length * 8 + 12).clamp(44, 72).toDouble();
                    return LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (points.length - 1).toDouble(),
                        minY: 0,
                        maxY: displayMax,
                        // Guard against zero intervals when all points are zero
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: interval,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.white.withOpacity(0.15),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: reserved,
                              interval: interval,
                              getTitlesWidget: (value, meta) => Text(
                                _formatShort(value),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 10),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 1,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                final List<String> labels =
                                    (_dashboardData['weekly_dates'] as List?)
                                            ?.cast<String>() ??
                                        <String>[];
                                final int i = value.toInt();
                                if (i < 0 || i >= labels.length) {
                                  return const SizedBox.shrink();
                                }
                                final String text = labels[i];
                                // Compute an adaptive step so labels don't overlap, keep ~30° tilt
                                final double width =
                                    MediaQuery.of(context).size.width -
                                        40; // padding approx
                                const double approxLabelWidth =
                                    22; // rotated width estimate
                                final int step = (labels.isEmpty)
                                    ? 1
                                    : (labels.length * approxLabelWidth / width)
                                        .ceil()
                                        .clamp(1, 6);
                                if (i % step != 0) {
                                  return const SizedBox.shrink();
                                }

                                return Transform.rotate(
                                  angle: -math.pi / 6, // -30 degrees
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      text,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 10),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(),
                          topTitles: const AxisTitles(),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              final labels =
                                  (_dashboardData['weekly_dates'] as List?)
                                          ?.cast<String>() ??
                                      <String>[];
                              return touchedSpots.map((barSpot) {
                                final i = barSpot.x.toInt();
                                final label = (i >= 0 && i < labels.length)
                                    ? labels[i]
                                    : '';
                                final valueText =
                                    'TSH ${_formatCurrency(barSpot.y)}';
                                return LineTooltipItem(
                                  '$label\n$valueText',
                                  const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: points
                                .asMap()
                                .entries
                                .map((e) => FlSpot(
                                      e.key.toDouble(),
                                      e.value * _chartAnimation.value,
                                    ))
                                .toList(),
                            isCurved: true,
                            color: Colors.white,
                            barWidth: 3,
                            dotData: FlDotData(
                              getDotPainter: (spot, percent, bar, index) =>
                                  FlDotCirclePainter(
                                radius: 3,
                                color: Colors.white,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.3),
                                  Colors.white.withOpacity(0.05),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  // Opens on the current month (scrolled into view); earlier months are a swipe away.
  Widget _buildMonthSelector() => MonthSelector(
        months: months,
        selectedMonth: _selectedMonth,
        selectedColor: textPrimary,
        unselectedColor: textSecondary,
        onSelected: (int month) {
          setState(() {
            _selectedMonth = month;
          });
          unawaited(_loadRevenueChartData(
              year: DateTime.now().year, month: _selectedMonth));
          _chartAnimationController.reset();
          _chartAnimationController.forward();
        },
      );

  // Not used anymore; kept for reference. Footer now handles the quick menu.
  Widget _buildQuickActions(LocalizationService localizationService) =>
      const SizedBox.shrink();

  /// Footer styled like Inventory footer bar, with a centered Menu action
  Widget _buildFooter() {
    return ColoredBox(
      color: ThemeConstants.footerBarColor,
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28.r),
          child: Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(vertical: 8.h),
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: ThemeConstants.footerBarColor,
              borderRadius: BorderRadius.circular(28.r),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // Left side: Payments, Debts
                Row(
                  children: <Widget>[
                    _FooterIcon(
                      icon: Icons.account_balance_wallet_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PaymentsScreen()),
                      ),
                    ),
                    SizedBox(width: 14.w),
                    _FooterIcon(
                      icon: Icons.pending_actions_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DebtsManagementScreen()),
                      ),
                    ),
                  ],
                ),
                // Center: Menu
                _FooterIcon(
                  icon: Icons.apps_rounded,
                  onTap: () => NavigationBuilder.showGridMenu(context),
                ),
                // Right side: Drivers, Receipts
                Row(
                  children: <Widget>[
                    _FooterIcon(
                      icon: Icons.people_alt_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DriversManagementScreen()),
                      ),
                    ),
                    SizedBox(width: 14.w),
                    _FooterIcon(
                      icon: Icons.receipt_long_rounded,
                      onTap: () => _navigateToReceiptsList(filter: 'generated'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build dropdown menu for each dashboard card
  Widget _buildCardDropdownMenu(String title, String value, IconData icon) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: textSecondary,
        size: ResponsiveHelper.iconSizeS,
      ),
      color: primaryBlue.withOpacity(0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.white.withOpacity(0.2),
        ),
      ),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.3),
      itemBuilder: (BuildContext context) => _getMenuItems(title, icon),
      onSelected: (String action) => _handleMenuAction(action, title, value),
    );
  }

  /// Get menu items based on card type
  List<PopupMenuEntry<String>> _getMenuItems(String title, IconData icon) {
    final localizationService =
        Provider.of<LocalizationService>(context, listen: false);
    final List<PopupMenuEntry<String>> items = [];

    // Common actions for all cards
    items.add(_buildMenuItem(
      'view_details',
      localizationService.translate('view_details'),
      Icons.visibility,
    ));

    // Card-specific actions
    if (_isRevenueCard(title)) {
      items.add(_buildMenuItem(
        'view_revenue_drivers',
        localizationService.translate('drivers_who_paid'),
        Icons.people,
      ));
      items.add(_buildMenuItem(
        'revenue_breakdown',
        localizationService.translate('revenue_breakdown'),
        Icons.pie_chart,
      ));
    } else if (title == localizationService.translate('drivers')) {
      items.add(_buildMenuItem(
        'view_all_drivers',
        localizationService.translate('all_drivers'),
        Icons.people,
      ));
      items.add(_buildMenuItem(
        'active_drivers',
        localizationService.translate('active_drivers_only'),
        Icons.check_circle,
      ));
      items.add(_buildMenuItem(
        'add_driver',
        localizationService.translate('add_driver'),
        Icons.person_add,
      ));
    } else if (title == localizationService.translate('vehicles')) {
      items.add(_buildMenuItem(
        'view_all_vehicles',
        localizationService.translate('all_vehicles'),
        Icons.directions_car,
      ));
      items.add(_buildMenuItem(
        'active_vehicles',
        localizationService.translate('active_vehicles_only'),
        Icons.check_circle,
      ));
      items.add(_buildMenuItem(
        'add_vehicle',
        localizationService.translate('add_vehicle'),
        Icons.add_circle,
      ));
    } else if (title ==
        localizationService.translate('payments_with_receipts')) {
      items.add(_buildMenuItem(
        'view_receipts',
        localizationService.translate('all_receipts'),
        Icons.receipt,
      ));
      items.add(_buildMenuItem(
        'generate_receipt',
        localizationService.translate('generate_receipt'),
        Icons.add_circle,
      ));
    } else if (title ==
        localizationService.translate('paid_awaiting_receipts')) {
      items.add(_buildMenuItem(
        'pending_receipts',
        localizationService.translate('pending_receipts'),
        Icons.pending,
      ));
      items.add(_buildMenuItem(
        'process_pending',
        localizationService.translate('process'),
        Icons.play_arrow,
      ));
    } else if (title == localizationService.translate('unpaid_payments')) {
      items.add(_buildMenuItem(
        'unpaid_debts',
        localizationService.translate('unpaid_debts'),
        Icons.warning,
      ));
      items.add(_buildMenuItem(
        'send_reminders',
        localizationService.translate('send_reminders'),
        Icons.notifications_active,
      ));
    }

    // Add divider and export option for all cards
    items.add(const PopupMenuDivider());
    items.add(_buildMenuItem(
      'export',
      localizationService.translate('export_data'),
      Icons.download,
    ));

    return items;
  }

  bool _isRevenueCard(String title) {
    final localizationService =
        Provider.of<LocalizationService>(context, listen: false);
    return title == localizationService.translate('daily_revenue') ||
        title == localizationService.translate('weekly_revenue') ||
        title == localizationService.translate('monthly_revenue');
  }

  /// Build individual menu item with consistent styling
  PopupMenuItem<String> _buildMenuItem(
      String value, String text, IconData icon) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: textPrimary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Handle menu item selection
  void _handleMenuAction(String action, String cardTitle, String value) {
    void defer(VoidCallback f) =>
        WidgetsBinding.instance.addPostFrameCallback((_) => f());
    switch (action) {
      case 'view_details':
        defer(() => _showCardDetails(cardTitle, value));

      case 'view_revenue_drivers':
        defer(() => _navigateToRevenueDrivers(cardTitle));

      case 'revenue_breakdown':
        defer(() => _navigateToRevenueBreakdown(cardTitle));

      case 'view_all_drivers':
        defer(() => _navigateToDriversList(filter: 'all'));

      case 'active_drivers':
        defer(() => _navigateToDriversList(filter: 'active'));

      case 'add_driver':
        defer(_navigateToAddDriver);

      case 'view_all_vehicles':
        defer(() => _navigateToVehiclesList(filter: 'all'));

      case 'active_vehicles':
        defer(() => _navigateToVehiclesList(filter: 'active'));

      case 'add_vehicle':
        defer(_navigateToAddVehicle);

      case 'view_receipts':
        defer(() => _navigateToReceiptsList(filter: 'generated'));

      case 'generate_receipt':
        defer(_navigateToGenerateReceipt);

      case 'pending_receipts':
        defer(() => _navigateToReceiptsList(filter: 'pending'));

      case 'process_pending':
        defer(_processPendingReceipts);

      case 'unpaid_debts':
        defer(() => _navigateToDebtsList(filter: 'unpaid'));

      case 'send_reminders':
        defer(_sendPaymentReminders);

      case 'export':
        defer(() => _exportCardData(cardTitle));
    }
  }

  /// Show detailed information about the card
  void _showCardDetails(String title, String value) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Consumer<LocalizationService>(
        builder: (context, localizationService, child) => AlertDialog(
          backgroundColor: primaryBlue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          title: Row(
            children: [
              Icon(
                _getCardIcon(title),
                color: textPrimary,
                size: 20.sp,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizationService.translate('current_value'),
                style: const TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _getCardDescription(title, localizationService),
                style: const TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                localizationService.translate('close'),
                style: const TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigation methods for different card actions
  void _navigateToRevenueDrivers(String period) {
    // Navigate to drivers list filtered by revenue period
    Navigator.pushNamed(
      context,
      '/admin/drivers',
      arguments: {
        'filter': 'revenue',
        'period': period,
      },
    );
  }

  void _navigateToRevenueBreakdown(String period) {
    Navigator.pushNamed(
      context,
      '/admin/analytics',
      arguments: {
        'view': 'revenue_breakdown',
        'period': period,
      },
    );
  }

  void _navigateToDriversList({required String filter}) {
    Navigator.pushNamed(
      context,
      '/admin/drivers',
      arguments: {'filter': filter},
    );
  }

  void _navigateToAddDriver() {
    Navigator.pushNamed(context, '/admin/drivers/add');
  }

  void _navigateToVehiclesList({required String filter}) {
    Navigator.pushNamed(
      context,
      '/admin/vehicles',
      arguments: {'filter': filter},
    );
  }

  void _navigateToAddVehicle() {
    Navigator.pushNamed(context, '/admin/vehicles/add');
  }

  void _navigateToReceiptsList({required String filter}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReceiptsScreen(
          initialFilter: filter == 'pending' ? 'pending' : 'all',
        ),
      ),
    );
  }

  void _navigateToGenerateReceipt() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ReceiptsScreen(),
      ),
    );
  }

  void _navigateToDebtsList({required String filter}) {
    Navigator.pushNamed(
      context,
      '/admin/debts',
      arguments: {'filter': filter},
    );
  }

  /// Action methods
  void _processPendingReceipts() {
    final localizationService =
        Provider.of<LocalizationService>(context, listen: false);
    _showActionDialog(
      title: localizationService.translate('process_pending_receipts'),
      message:
          localizationService.translate('confirm_process_pending_receipts'),
      confirmText: localizationService.translate('process'),
      onConfirm: () async {
        try {
          // 1) Fetch pending receipts from the backend (real API, no mock data)
          final Map<String, dynamic> resp =
              await _apiService.getPendingReceipts();
          final Map<String, dynamic> data =
              (resp['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final List<dynamic> list =
              (data['pending_receipts'] as List<dynamic>?) ??
                  (data['data'] as List<dynamic>?) ??
                  <dynamic>[];
          final List<String> paymentIds = list
              .whereType<Map<String, dynamic>>()
              .map((m) => m['payment_id']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();

          if (paymentIds.isEmpty) {
            _showSuccessSnackBar(
                localizationService.translate('no_pending_receipts'));
            return;
          }

          // 2) Ask backend to generate receipts in bulk for these payments
          await _apiService.generateBulkReceipts(paymentIds);

          // 3) Notify other parts of the app to refresh live data
          AppEvents.instance.emit(AppEventType.receiptsUpdated);
          AppEvents.instance.emit(AppEventType.dashboardShouldRefresh);

          _showSuccessSnackBar(
              localizationService.translate('pending_receipts_processed'));
        } on Exception catch (e) {
          _showErrorSnackBar('Failed to process receipts: $e');
        }
      },
    );
  }

  void _sendPaymentReminders() {
    final localizationService =
        Provider.of<LocalizationService>(context, listen: false);
    _showActionDialog(
      title: localizationService.translate('send_payment_reminders'),
      message: localizationService.translate('confirm_send_reminders'),
      confirmText: localizationService.translate('send'),
      onConfirm: () {
        // Implement reminder sending
        _showSuccessSnackBar(
            localizationService.translate('payment_reminders_sent'));
      },
    );
  }

  void _exportCardData(String cardTitle) {
    final localizationService =
        Provider.of<LocalizationService>(context, listen: false);
    _showActionDialog(
      title: localizationService.translate('export_data'),
      message:
          '${localizationService.translate('confirm_export_data')} "$cardTitle"?',
      confirmText: localizationService.translate('export'),
      onConfirm: () {
        // Implement data export
        _showSuccessSnackBar(
            localizationService.translate('data_exported_successfully'));
      },
    );
  }

  /// Helper methods
  IconData _getCardIcon(String title) {
    final localizationService =
        Provider.of<LocalizationService>(context, listen: false);

    if (title == localizationService.translate('daily_revenue')) {
      return Icons.today;
    } else if (title == localizationService.translate('weekly_revenue')) {
      return Icons.calendar_view_week;
    } else if (title == localizationService.translate('monthly_revenue')) {
      return Icons.trending_up;
    } else if (title == localizationService.translate('drivers')) {
      return Icons.person;
    } else if (title == localizationService.translate('vehicles')) {
      return Icons.directions_car;
    } else if (title ==
        localizationService.translate('payments_with_receipts')) {
      return Icons.receipt;
    } else if (title ==
        localizationService.translate('paid_awaiting_receipts')) {
      return Icons.receipt_long;
    } else if (title == localizationService.translate('unpaid_payments')) {
      return Icons.pending_actions;
    } else {
      return Icons.info;
    }
  }

  String _getCardDescription(
      String title, LocalizationService localizationService) {
    if (title == localizationService.translate('daily_revenue')) {
      return localizationService.translate('daily_revenue_desc');
    } else if (title == localizationService.translate('weekly_revenue')) {
      return localizationService.translate('weekly_revenue_desc');
    } else if (title == localizationService.translate('monthly_revenue')) {
      return localizationService.translate('monthly_revenue_desc');
    } else if (title == localizationService.translate('drivers')) {
      return localizationService.translate('drivers_desc');
    } else if (title == localizationService.translate('vehicles')) {
      return localizationService.translate('vehicles_desc');
    } else if (title ==
        localizationService.translate('payments_with_receipts')) {
      return localizationService.translate('payments_with_receipts_desc');
    } else if (title ==
        localizationService.translate('paid_awaiting_receipts')) {
      return localizationService.translate('paid_awaiting_receipts_desc');
    } else if (title == localizationService.translate('unpaid_payments')) {
      return localizationService.translate('unpaid_payments_desc');
    } else {
      return localizationService.translate('additional_card_info');
    }
  }

  void _showActionDialog({
    required String title,
    required String message,
    required String confirmText,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Consumer<LocalizationService>(
        builder: (context, localizationService, child) => AlertDialog(
          backgroundColor: primaryBlue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                localizationService.translate('cancel'),
                style: const TextStyle(
                  color: textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
              child: Text(
                confirmText,
                style: const TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ThemeConstants.showSuccessSnackBar(context, message);
  }

  Widget _buildGlassCard({required Widget child}) => DecoratedBox(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: child,
          ),
        ),
      );

  Widget _buildDrawer(LocalizationService localizationService) {
    final AuthProvider authProvider = Provider.of<AuthProvider>(context);
    final UserData? user = authProvider.user;

    // Removed hardcoded permissions logic to use UserData granular permissions

    // Get badge counts from dashboard data
    final badges = NavigationBuilder.getBadgesFromDashboardData(_dashboardData);
    badges['reminders'] = _remindersCount;

    return Drawer(
      backgroundColor: primaryBlue,
      child: Column(
        children: <Widget>[
          // Drawer Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // New Premium Logo in Drawer
                  Container(
                    margin: EdgeInsets.only(bottom: 20.h),
                    padding: EdgeInsets.all(2.w),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ThemeConstants.primaryCyan.withOpacity(0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ThemeConstants.primaryCyan.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30.r),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 50.w,
                        height: 50.w,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: cardColor,
                        child: _avatarWidget(user, radius: 20),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? "Admin User",
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user?.email ?? "admin@bodamapato.com",
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12.sp,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Navigation Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: NavigationBuilder.buildDrawerItems(
                localization: localizationService,
                badges: badges,
                user: user,
                context: context,
                onLogout: () async {
                  Navigator.pop(context);
                  await authProvider.logout();
                  if (!mounted) return;
                  // Replace the entire stack so the user lands on Login
                  await Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthWrapper()),
                    (route) => false,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _avatarUrl(UserData? user) {
    final String? url = user?.avatarUrl;
    if (url == null || url.isEmpty) return null;
    String pathPart;
    try {
      final Uri u = Uri.parse(url);
      pathPart = u.hasScheme ? (u.path.isEmpty ? '/' : u.path) : url;
    } on Exception {
      pathPart = url;
    }
    if (pathPart.startsWith('/storage')) {
      pathPart = pathPart.replaceFirst('/storage', '');
    }
    if (!pathPart.startsWith('/')) pathPart = '/$pathPart';
    final String apiBase = ApiConfig.baseUrl; // ends with /api
    return "$apiBase/files/public$pathPart";
  }

  Widget _avatarWidget(UserData? user, {double? radius}) {
    final String? url = _avatarUrl(user);
    final double r = radius ?? 20;
    if (url == null) {
      final String initial = ((user?.name ?? '').isNotEmpty)
          ? user!.name.substring(0, 1).toUpperCase()
          : '';
      return Center(
        child: initial.isNotEmpty
            ? Text(initial,
                style: const TextStyle(
                    color: textPrimary, fontWeight: FontWeight.bold))
            : const Icon(Icons.person, color: textPrimary, size: 20),
      );
    }
    return ClipOval(
      child: Image.network(
        url,
        width: r * 2,
        height: r * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) {
          final String initial = ((user?.name ?? '').isNotEmpty)
              ? user!.name.substring(0, 1).toUpperCase()
              : '';
          return Container(
            color: Colors.white24,
            alignment: Alignment.center,
            child: initial.isNotEmpty
                ? Text(initial,
                    style: const TextStyle(
                        color: textPrimary, fontWeight: FontWeight.bold))
                : const Icon(Icons.person, color: textPrimary, size: 20),
          );
        },
      ),
    );
  }

  String _formatCurrency(amount) {
    final double value = _toDouble(amount);
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1)}M";
    } else if (value >= 1000) {
      return "${(value / 1000).toStringAsFixed(1)}K";
    } else {
      return value.toStringAsFixed(0);
    }
  }

  String _formatShort(double value) {
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1)}M";
    }
    if (value >= 1000) {
      return "${(value / 1000).round()}K";
    }
    return value.round().toString();
  }

  String _formatDateLabel(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    // Expecting YYYY-MM-DD or ISO8601; take date part and format as DD/MM
    final String datePart = iso.split('T').first;
    final List<String> parts = datePart.split('-');
    if (parts.length >= 3) {
      final String dd = parts[2].padLeft(2, '0');
      final String mm = parts[1].padLeft(2, '0');
      return '$dd/$mm';
    }
    return datePart;
  }

  // Compute a "nice" rounded-up ceiling for axis max (1, 2, or 5 times a power of 10)
  double _niceCeilValue(double value) {
    if (value <= 0) return 1;
    final double exponent = (math.log(value) / math.ln10).floorToDouble();
    final double fraction = value / math.pow(10, exponent);
    double niceFraction;
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
    return niceFraction * math.pow(10, exponent);
  }

  // Compute a nice tick step (1/2/5 * power of 10)
  double _niceStep(double value) {
    if (value <= 0) return 1;
    final double exponent = (math.log(value) / math.ln10).floorToDouble();
    final double fraction = value / math.pow(10, exponent);
    double niceFraction;
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
    return niceFraction * math.pow(10, exponent);
  }

  // Helper method to safely convert dynamic values to double
  double _toDouble(value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final String cleaned = value.replaceAll(RegExp(r'[^0-9\.-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0;
  }

  // Helper method to safely convert dynamic values to int
  int _toInt(value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  // Extract a total count from common API response shapes
  int _extractTotalCountFromResponse(Map<String, dynamic> resp) {
    // Try top-level meta.total
    final dynamic metaTop = resp['meta'];
    if (metaTop is Map && metaTop['total'] is num) {
      return (metaTop['total'] as num).toInt();
    }

    // Try data as List
    final dynamic data = resp['data'];
    if (data is List) return data.length;

    // Try data: { data: [...], meta: { total } }
    if (data is Map<String, dynamic>) {
      final dynamic metaInData = data['meta'];
      if (metaInData is Map && metaInData['total'] is num) {
        return (metaInData['total'] as num).toInt();
      }
      final dynamic inner = data['data'];
      if (inner is List) return inner.length;
    }

    return 0;
  }

  // Load additional counts (reminders, receipts, debts) via API calls
  Future<void> _loadAdditionalBadgeCounts() async {
    if (!mounted) return;
    try {
      // Load reminders count for drawer badge; rely on ApiService auth guard
      try {
        final Map<String, dynamic> remindersResponse =
            await _apiService.getReminders(limit: 1);
        final Map<String, dynamic>? remindersMeta =
            remindersResponse["meta"] as Map<String, dynamic>?;
        _remindersCount = remindersMeta?["total"] ?? 0;
      } on Exception {
        _remindersCount = 0;
      }
    } on Exception catch (_) {
      // If API fails, set reminder count to 0
      _remindersCount = 0;
    }
  }
}

// Custom Chart Painter
class _FooterIcon extends StatelessWidget {
  const _FooterIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final Color bg = ThemeConstants.primaryBlue.withOpacity(0.22);
    return InkResponse(
      onTap: onTap,
      radius: 28.r,
      child: Container(
        width: 46.w,
        height: 46.w,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 22.sp),
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  ChartPainter(
      {required this.data, required this.animationValue, this.yAxisMax});
  final List<dynamic> data;
  final double animationValue;
  // Optional Y-axis maximum. If null, a nice rounded ceiling above data max is used.
  final double? yAxisMax;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Layout paddings to make space for Y-axis labels
    const double leftPad = 44;
    const double rightPad = 12;
    const double topPad = 8;
    const double bottomPad = 28;

    final double chartWidth =
        (size.width - leftPad - rightPad).clamp(1.0, double.infinity);
    final double chartHeight =
        (size.height - topPad - bottomPad).clamp(1.0, double.infinity);
    const double chartLeft = leftPad;
    final double chartRight = leftPad + chartWidth;
    final double chartBottom = size.height - bottomPad;

    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Colors.white.withOpacity(0.3),
          Colors.white.withOpacity(0.05),
        ],
      ).createShader(Rect.fromLTWH(chartLeft, topPad, chartWidth, chartHeight))
      ..style = PaintingStyle.fill;

    final Path path = Path();
    final Path fillPath = Path();

    final double dataMax = data.map(_toDoubleStatic).reduce(math.max);

    // Determine the display max: at least yAxisMax (e.g., 6M), or a rounded-up nice number above data
    double displayMax = yAxisMax ?? dataMax;
    // Add 10% headroom above data if our desired max equals the data max
    if ((yAxisMax == null) || (displayMax <= dataMax)) {
      displayMax = _niceCeil((dataMax <= 0 ? 1 : dataMax) * 1.1);
    }
    // Ensure the displayMax is at least the provided yAxisMax (for 6M cap)
    if (yAxisMax != null && displayMax < yAxisMax!) {
      displayMax = yAxisMax!;
    }

    if (displayMax <= 0) return;

    // Draw horizontal gridlines and Y-axis labels (6 ticks including 0)
    const int tickCount = 6;
    final Paint gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1;

    for (int i = 0; i < tickCount; i++) {
      final double t = i / (tickCount - 1);
      final double value = displayMax * (1 - t); // top to bottom labels
      final double y = topPad + chartHeight * t;

      // grid line
      canvas.drawLine(Offset(chartLeft, y), Offset(chartRight, y), gridPaint);

      // label
      final TextPainter label = TextPainter(
        text: TextSpan(
          text: _formatShort(value),
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: leftPad - 6);
      label.paint(canvas, Offset(0, y - label.height / 2));
    }

    final double stepX = chartWidth / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final double value = _toDoubleStatic(data[i]);
      // Normalize from 0 to displayMax so the baseline is zero and scale is flexible
      final double normalizedValue = (value / displayMax).clamp(0.0, 1.0);
      final double x = chartLeft + i * stepX;
      final double y = chartBottom - (normalizedValue * chartHeight);

      final double animatedX = chartLeft + (x - chartLeft) * animationValue;
      final double animatedY = y + (chartBottom - y) * (1 - animationValue);

      if (i == 0) {
        path.moveTo(animatedX, animatedY);
        fillPath.moveTo(animatedX, chartBottom);
        fillPath.lineTo(animatedX, animatedY);
      } else {
        path.lineTo(animatedX, animatedY);
        fillPath.lineTo(animatedX, animatedY);
      }

      // Draw data point marker (kept as-is)
      canvas.drawCircle(
        Offset(animatedX, animatedY),
        4,
        Paint()..color = Colors.white,
      );

      // Always-visible, rotated green amount label above each point/bar
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: value.toStringAsFixed(0),
          style: const TextStyle(
            color: Color(0xFF00FF00), // bright green
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Position label directly above the bar/point and rotate 90° clockwise
      canvas.save();
      // Translate to a point above the data point
      const double labelYOffset = 20;
      canvas.translate(animatedX, animatedY - labelYOffset);
      // Rotate clockwise 90 degrees so text reads left-to-right when head tilted right
      canvas.rotate(math.pi / 2);
      // Draw centered, with text positioned above the anchor point
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }

    // Complete the fill path
    fillPath.lineTo(chartLeft + chartWidth * animationValue, chartBottom);
    fillPath.close();

    // Draw fill first, then stroke
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  // Static helper method for type conversion in chart painter
  static double _toDoubleStatic(value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0;
  }

  static String _formatShort(double value) {
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1)}M";
    }
    if (value >= 1000) {
      return "${(value / 1000).round()}K";
    }
    return value.round().toString();
  }

  // Compute a "nice" rounded-up ceiling for axis max (1, 2, or 5 times a power of 10)
  static double _niceCeil(double value) {
    if (value <= 0) return 1;
    final double exponent = (math.log(value) / math.ln10).floorToDouble();
    final double fraction = value / math.pow(10, exponent);
    double niceFraction;
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
    return niceFraction * math.pow(10, exponent);
  }
}
