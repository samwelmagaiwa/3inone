import 'dart:async';

import "package:flutter/material.dart";
import 'package:flutter_screenutil/flutter_screenutil.dart';
import "package:provider/provider.dart";

import "../../constants/theme_constants.dart";
import "../../services/api_service.dart";
import "../../services/app_events.dart";
import "../../services/localization_service.dart";
import "../../utils/responsive_helper.dart";

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final ApiService _apiService = ApiService();
  String _selectedPeriod = "daily";
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _isGenerating = false;
  Map<String, dynamic>? _currentReportData;
  late final StreamSubscription<AppEvent> _eventSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    // Auto-refresh when relevant app events occur (e.g., new payments/receipts)
    _eventSubscription = AppEvents.instance.stream.listen((event) {
      switch (event.type) {
        case AppEventType.receiptsUpdated:
        case AppEventType.paymentsUpdated:
        case AppEventType.dashboardShouldRefresh:
        case AppEventType.debtsUpdated:
          if (mounted) _generateReport();
      }
    });
  }

  Map<String, dynamic> _normalizeSummary(Map<String, dynamic>? raw,
      {required DateTime start, required DateTime end}) {
    Map<String, dynamic> m = raw ?? <String, dynamic>{};
    // If backend wraps in { data: {...} }
    if (m['data'] is Map<String, dynamic>) {
      m = Map<String, dynamic>.from(m['data']);
    }

    num parseNum(v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v.replaceAll(',', '')) ?? 0;
      return 0;
    }

    num firstNum(Map<String, dynamic> src, List<String> keys) {
      for (final k in keys) {
        final v = src[k];
        if (v != null) return parseNum(v);
      }
      return 0;
    }

    // Try direct totals (cover many backend variants)
    num totalRevenue = firstNum(m, [
      'total_revenue',
      'revenue_total',
      'total',
      'total_income',
      'grand_total',
      'total_collected',
      'total_paid',
      'payments_total',
      'collections_total',
      'debt_payments_total',
      'income_total'
    ]);
    num totalExpenses =
        firstNum(m, ['total_expenses', 'expenses_total', 'expense_total']);

    // Try nested maps if direct missing
    if (totalRevenue == 0 && m['revenue'] is Map<String, dynamic>) {
      totalRevenue = firstNum(Map<String, dynamic>.from(m['revenue']), [
        'total_revenue',
        'revenue_total',
        'total',
        'total_income',
        'grand_total'
      ]);
    }
    if (totalExpenses == 0 && m['expenses'] is Map<String, dynamic>) {
      totalExpenses = firstNum(Map<String, dynamic>.from(m['expenses']),
          ['total_expenses', 'expenses_total', 'total']);
    }

    // If backend returns daily_data over a range, sum within [start, end]
    num sumDaily(daily) {
      num s = 0;
      if (daily is List) {
        for (final e in daily) {
          if (e is Map<String, dynamic>) {
            final String? d = (e['date'] ?? e['day'] ?? e['label'])?.toString();
            if (d != null) {
              final DateTime? dt = DateTime.tryParse(d);
              if (dt != null) {
                final DateTime dd = DateTime(dt.year, dt.month, dt.day);
                if (!dd.isBefore(
                        DateTime(start.year, start.month, start.day)) &&
                    !dd.isAfter(DateTime(end.year, end.month, end.day))) {
                  s += firstNum(
                      e, ['amount', 'total', 'revenue', 'paid', 'value']);
                }
              } else {
                s += firstNum(
                    e, ['amount', 'total', 'revenue', 'paid', 'value']);
              }
            }
          }
        }
      }
      return s;
    }

    // Last-resort: sum amounts from lists when totals missing
    num sumAmounts(list) {
      num s = 0;
      if (list is List) {
        for (final e in list) {
          if (e is Map<String, dynamic>) {
            s += firstNum(e, [
              'amount',
              'total',
              'revenue',
              'paid',
              'paid_amount',
              'amount_paid',
              'amount_received',
              'received',
              'value'
            ]);
          }
        }
      }
      return s;
    }

    if (totalRevenue == 0) {
      if (m['daily_data'] is List) {
        totalRevenue = sumDaily(m['daily_data']);
      }
      if (totalRevenue == 0 && m['transactions'] is List) {
        totalRevenue = sumAmounts(m['transactions']);
      }
      if (totalRevenue == 0 && m['payments'] is List) {
        totalRevenue = sumAmounts(m['payments']);
      }
      if (totalRevenue == 0 && m['revenues'] is List) {
        totalRevenue = sumAmounts(m['revenues']);
      }
      if (totalRevenue == 0 && m['items'] is List) {
        totalRevenue = sumAmounts(m['items']);
      }
      if (totalRevenue == 0 && m['data'] is List) {
        totalRevenue = sumAmounts(m['data']);
      }
    }

    // Transaction count from common shapes
    int transactionCount = 0;
    if (m['transaction_count'] != null) {
      transactionCount = parseNum(m['transaction_count']).toInt();
    } else if (m['count'] != null) {
      transactionCount = parseNum(m['count']).toInt();
    } else if (m['transactions'] is List) {
      transactionCount = (m['transactions'] as List).length;
    } else if (m['payments'] is List) {
      transactionCount = (m['payments'] as List).length;
    }

    // Average per day (fallback computed)
    num averagePerDay = 0;
    if (m['average_per_day'] != null) {
      averagePerDay = parseNum(m['average_per_day']);
    } else {
      final int days = end.difference(start).inDays + 1;
      if (days > 0) averagePerDay = totalRevenue / days;
    }

    return <String, dynamic>{
      'total_revenue': totalRevenue,
      'total_expenses': totalExpenses,
      'transaction_count': transactionCount,
      'average_per_day': averagePerDay,
      // Preserve any progress fields if provided
      if (m['progress_percent'] != null)
        'progress_percent': parseNum(m['progress_percent']),
      if (m['goal_progress'] != null)
        'goal_progress': parseNum(m['goal_progress']),
      if (m['revenue_growth'] != null)
        'revenue_growth': parseNum(m['revenue_growth']),
    };
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  Future<void> _loadInitialData() async {
    // Generate using the full pipeline (with fallbacks) on first load
    await _generateReport();
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
      _currentReportData = null;
    });

    try {
      late Map<String, dynamic> reportData;

      // Always send a full-day range for accuracy
      final DateTime start = _startOfDay(_startDate);
      final DateTime end = _endOfDay(_endDate);

      // Determine which API endpoint to call based on selected period
      switch (_selectedPeriod) {
        case 'revenue':
          reportData = await _apiService.getAdminRevenueReport(
            startDate: start,
            endDate: end,
          );
        case 'expense':
          reportData = await _apiService.getExpenseReport(
            startDate: start,
            endDate: end,
          );
        case 'profit_loss':
          reportData = await _apiService.getProfitLossReport(
            startDate: start,
            endDate: end,
          );
        default:
          // For daily/weekly/monthly, use revenue report as default
          reportData = await _apiService.getAdminRevenueReport(
            startDate: start,
            endDate: end,
          );
      }

      Map<String, dynamic> normalized = _normalizeSummary(
          Map<String, dynamic>.from(reportData),
          start: start,
          end: end);

      // Fallback: if revenue total is still zero, try aggregating from payment history
      if (((normalized['total_revenue'] as num?) ?? 0) == 0) {
        try {
          final Map<String, dynamic> paymentsResp =
              await _apiService.getPaymentHistory(
            startDate: start,
            endDate: end,
            limit: 1000,
          );
          final Map<String, dynamic> fromPayments =
              _normalizeSummary(paymentsResp, start: start, end: end);
          if (((fromPayments['total_revenue'] as num?) ?? 0) > 0) {
            normalized = {
              ...normalized,
              // ensure totals reflect actual collections
              'total_revenue': fromPayments['total_revenue'],
              'transaction_count': fromPayments['transaction_count'] ??
                  normalized['transaction_count'],
              'average_per_day': fromPayments['average_per_day'] ??
                  normalized['average_per_day'],
            };
          }
        } on Exception catch (_) {
          // ignore fallback errors
        }
      }

      setState(() {
        _currentReportData = normalized;
      });

      if (mounted) {
        _showReportPreview();
      }
    } on Exception catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _showReportPreview() {
    showDialog(
      context: context,
      builder: (final BuildContext context) => _ReportPreviewDialog(
        period: _selectedPeriod,
        startDate: _startDate,
        endDate: _endDate,
        reportData: _currentReportData,
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    ResponsiveHelper.init(context);
    return Consumer<LocalizationService>(
      builder: (context, localizationService, child) {
        return ThemeConstants.buildScaffold(
          title: localizationService.translate('reports'),
          body: RefreshIndicator(
            onRefresh: _generateReport,
            color: Colors.white,
            backgroundColor: ThemeConstants.primaryBlue,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Welcome Header with Overview
                  _buildWelcomeHeader(),
                  const SizedBox(height: 24),

                  // Quick Stats Preview - Moved up for better visibility
                  _buildQuickStatsSection(),
                  const SizedBox(height: 24),

                  // Report Types with enhanced design
                  _buildReportTypesSection(),
                  const SizedBox(height: 24),

                  // Date Range Selection with better UX
                  _buildDateRangeSection(),
                  const SizedBox(height: 24),

                  // Generate Report Button with enhanced styling
                  _buildGenerateReportButton(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _eventSubscription.cancel();
    super.dispose();
  }

  // Welcome header with summary
  Widget _buildWelcomeHeader() => ThemeConstants.buildGlassCardStatic(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ThemeConstants.primaryOrange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      color: ThemeConstants.primaryOrange,
                      size: 24.sp,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          LocalizationService.instance.translate('business_reports'),
                          style: TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          LocalizationService.instance.translate('view_your_income_and_expenses'),
                          style: ThemeConstants.captionStyle.copyWith(
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  // Enhanced quick stats section
  Widget _buildQuickStatsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.dashboard_outlined,
                color: ThemeConstants.textPrimary,
                size: 20.sp,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  LocalizationService.instance.translate('quick_summary'),
                  style: ThemeConstants.headingStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main revenue card
          _buildMainRevenueCard(),
          const SizedBox(height: 12),

          // Secondary stats grid
          Row(
            children: <Widget>[
              Expanded(
                child: _buildEnhancedStatCard(
                  title: LocalizationService.instance.translate('transactions'),
                  value: _currentReportData != null
                      ? "${_currentReportData!['transaction_count'] ?? 0}"
                      : "0",
                  icon: Icons.receipt_long,
                  color: const Color(0xFF06B6D4),
                  subtitle: LocalizationService.instance.translate('today'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEnhancedStatCard(
                  title: LocalizationService.instance.translate('vehicles_2'),
                  value: _currentReportData != null
                      ? "${_currentReportData!['vehicle_count'] ?? 0}"
                      : "0",
                  icon: Icons.directions_car,
                  color: const Color(0xFF8B5CF6),
                  subtitle: LocalizationService.instance.translate('working'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildEnhancedStatCard(
                  title: LocalizationService.instance.translate('average'),
                  value: _currentReportData != null
                      ? "TSh ${_formatCurrency(_currentReportData!['average_per_day'] ?? 0)}"
                      : "TSh 0",
                  icon: Icons.trending_up,
                  color: ThemeConstants.primaryOrange,
                  subtitle: LocalizationService.instance.translate('every_day'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEnhancedStatCard(
                  title: LocalizationService.instance.translate('profit'),
                  value: (() {
                    final num tr =
                        (_currentReportData?['total_revenue'] as num?) ?? 0;
                    final num te =
                        (_currentReportData?['total_expenses'] as num?) ?? 0;
                    final double p = tr == 0 ? 0 : (((tr - te) / tr) * 100);
                    return "${p.toStringAsFixed(0)}%";
                  })(),
                  icon: Icons.show_chart,
                  color: ThemeConstants.successGreen,
                  subtitle: LocalizationService.instance.translate('of_income'),
                ),
              ),
            ],
          ),
        ],
      );

  // Main revenue card with progress indicator
  Widget _buildMainRevenueCard() => ThemeConstants.buildGlassCardStatic(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ThemeConstants.successGreen.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: ThemeConstants.successGreen,
                      size: 20.sp,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          LocalizationService.instance.translate('total_revenue'),
                          style: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentReportData != null
                              ? "TSh ${_formatCurrency((_currentReportData!['total_revenue'] ?? 0) as num)}"
                              : "TSh 0",
                          style: const TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if ((_currentReportData?['revenue_growth'] as num?) != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ThemeConstants.successGreen.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "+${(_currentReportData?['revenue_growth'] as num?) ?? 0}%",
                        style: const TextStyle(
                          color: ThemeConstants.successGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
// Progress bar (shown only if backend provides 'progress_percent' or 'goal_progress')
              if (((_currentReportData?['progress_percent'] as num?) != null) ||
                  ((_currentReportData?['goal_progress'] as num?) != null)) ...[
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: (((_currentReportData?['progress_percent']
                                        as num?)
                                    ?.toDouble() ??
                                (_currentReportData?['goal_progress'] as num?)
                                    ?.toDouble() ??
                                0) /
                            100)
                        .clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: ThemeConstants.successGreen,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  LocalizationService.instance.translateWith('of_target', <Object?>[((_currentReportData?['progress_percent'] as num?)?.toDouble() ?? (_currentReportData?['goal_progress'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)]),
                  style: const TextStyle(
                    color: ThemeConstants.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  // Enhanced report types section
  Widget _buildReportTypesSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.category_outlined,
                color: ThemeConstants.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                LocalizationService.instance.translate('report_types'),
                style: ThemeConstants.headingStyle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildEnhancedReportTypeCard(
                  title: LocalizationService.instance.translate('today'),
                  subtitle: LocalizationService.instance.translate('daily_report'),
                  icon: Icons.today,
                  color: const Color(0xFF10B981),
                  isSelected: _selectedPeriod == "daily",
                  onTap: () {
                    setState(() {
                      _selectedPeriod = "daily";
                      _startDate = DateTime.now();
                      _endDate = DateTime.now();
                    });
                    _generateReport();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEnhancedReportTypeCard(
                  title: LocalizationService.instance.translate('week'),
                  subtitle: LocalizationService.instance.translate('weekly_report'),
                  icon: Icons.date_range,
                  color: const Color(0xFF3B82F6),
                  isSelected: _selectedPeriod == "weekly",
                  onTap: () {
                    setState(() {
                      _selectedPeriod = "weekly";
                      _startDate =
                          DateTime.now().subtract(const Duration(days: 7));
                      _endDate = DateTime.now();
                    });
                    _generateReport();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildEnhancedReportTypeCard(
                  title: LocalizationService.instance.translate('month'),
                  subtitle: LocalizationService.instance.translate('monthly_report'),
                  icon: Icons.calendar_month,
                  color: ThemeConstants.primaryOrange,
                  isSelected: _selectedPeriod == "monthly",
                  onTap: () {
                    setState(() {
                      _selectedPeriod = "monthly";
                      _startDate =
                          DateTime(DateTime.now().year, DateTime.now().month);
                      _endDate = DateTime.now();
                    });
                    _generateReport();
                  },
                ),
              ),
            ],
          ),
        ],
      );

  // Enhanced date range section
  Widget _buildDateRangeSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.event_outlined,
                color: ThemeConstants.textPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                LocalizationService.instance.translate('choose_period'),
                style: ThemeConstants.headingStyle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ThemeConstants.buildGlassCard(
            onTap: _selectDateRange,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ThemeConstants.primaryOrange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.date_range,
                      color: ThemeConstants.primaryOrange,
                      size: 20.sp,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          LocalizationService.instance.translate('report_period'),
                          style: TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "${_startDate.day}/${_startDate.month}/${_startDate.year} - ${_endDate.day}/${_endDate.month}/${_endDate.year}",
                          style: const TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 16.sp,
                      color: ThemeConstants.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  // Enhanced generate report button
  Widget _buildGenerateReportButton() => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isGenerating
                ? [Colors.grey.shade600, Colors.grey.shade700]
                : [ThemeConstants.primaryOrange, const Color(0xFFEA580C)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:
                  (_isGenerating ? Colors.grey : ThemeConstants.primaryOrange)
                      .withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isGenerating ? null : _generateReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (_isGenerating) ...[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Icon(
                  Icons.analytics,
                  size: 20.sp,
                ),
                const SizedBox(width: 12),
              ],
              Text(
                _isGenerating ? "${LocalizationService.instance.translate('generating_report')}..." : LocalizationService.instance.translate('generate_report'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

// Enhanced report type card
Widget _buildEnhancedReportTypeCard({
  required String title,
  required String subtitle,
  required IconData icon,
  required Color color,
  required bool isSelected,
  required VoidCallback onTap,
}) =>
    ThemeConstants.buildGlassCard(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: color, width: 2)
              : Border.all(color: Colors.white.withOpacity(0.1)),
          gradient: isSelected
              ? LinearGradient(
                  colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.2)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? color : ThemeConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? color : ThemeConstants.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected
                    ? color.withOpacity(0.8)
                    : ThemeConstants.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

// Enhanced stat card
Widget _buildEnhancedStatCard({
  required String title,
  required String value,
  required IconData icon,
  required Color color,
  String? subtitle,
}) =>
    ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );

// Helper method to format currency
String _formatCurrency(num? amount) {
  final num numAmount = amount ?? 0;
  if (numAmount >= 1000000) {
    return "${(numAmount / 1000000).toStringAsFixed(1)}M";
  } else if (numAmount >= 1000) {
    return "${(numAmount / 1000).toStringAsFixed(0)}K";
  }
  return numAmount.toStringAsFixed(0);
}

class _ReportPreviewDialog extends StatelessWidget {
  const _ReportPreviewDialog({
    required this.period,
    required this.startDate,
    required this.endDate,
    this.reportData,
  });
  final String period;
  final DateTime startDate;
  final DateTime endDate;
  final Map<String, dynamic>? reportData;

  @override
  Widget build(final BuildContext context) => Dialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeConstants.primaryBlue,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Header
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      LocalizationService.instance.translate('report_summary'),
                      style: TextStyle(
                        color: ThemeConstants.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        color: ThemeConstants.textPrimary),
                  ),
                ],
              ),

              const Divider(color: Colors.white24),

              // Report Summary
              Text(
                LocalizationService.instance.translateWith('report', <Object?>[_getPeriodName(period)]),
                style: const TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}",
                style: const TextStyle(
                  fontSize: 14,
                  color: ThemeConstants.textSecondary,
                ),
              ),

              const SizedBox(height: 16),

              // Report Data (no mock defaults)
              Builder(
                builder: (context) {
                  final num totalRevenue =
                      (reportData?['total_revenue'] as num?) ?? 0;
                  final num totalExpenses =
                      (reportData?['total_expenses'] as num?) ?? 0;
                  final int transactionCount =
                      (reportData?['transaction_count'] as int?) ?? 0;
                  final num averagePerDay =
                      (reportData?['average_per_day'] as num?) ?? 0;
                  final num netProfit = totalRevenue - totalExpenses;
                  return Column(
                    children: <Widget>[
                      _ReportRow(
                        "${LocalizationService.instance.translate('total_revenue')}:",
                        "TSh ${totalRevenue.toStringAsFixed(0)}",
                      ),
                      _ReportRow(
                        "${LocalizationService.instance.translate('total_expenses')}:",
                        "TSh ${totalExpenses.toStringAsFixed(0)}",
                      ),
                      _ReportRow(
                        "${LocalizationService.instance.translate('net_profit')}:",
                        "TSh ${netProfit.toStringAsFixed(0)}",
                      ),
                      _ReportRow(
                        "${LocalizationService.instance.translate('number_of_transactions')}:",
                        "$transactionCount",
                      ),
                      _ReportRow(
                        "${LocalizationService.instance.translate('daily_average')}:",
                        "TSh ${averagePerDay.toStringAsFixed(0)}",
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('report_exported'));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(LocalizationService.instance.translate('export')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('report_printed'));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(LocalizationService.instance.translate('print')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  String _getPeriodName(final String period) {
    switch (period) {
      case "daily":
        return LocalizationService.instance.translate('every_day');
      case "weekly":
        return LocalizationService.instance.translate('every_week');
      case "monthly":
        return LocalizationService.instance.translate('every_month');
      default:
        return LocalizationService.instance.translate('period_custom');
    }
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: ThemeConstants.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ThemeConstants.textPrimary,
              ),
            ),
          ],
        ),
      );
}
