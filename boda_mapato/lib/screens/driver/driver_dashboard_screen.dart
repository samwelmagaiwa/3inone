// ignore_for_file: avoid_dynamic_calls, unused_field
import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../constants/colors.dart";
import "../../constants/styles.dart";
import "../../constants/theme_constants.dart";
import "../../providers/auth_provider.dart";
import "../../services/api_service.dart";
import "../../services/localization_service.dart";
import "../../utils/responsive_utils.dart";
import "../../widgets/custom_button.dart";
import "../../widgets/custom_card.dart";
import "../../widgets/responsive_wrapper.dart";

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _dashboardData = <String, dynamic>{};
  // Driver-specific aggregates
  int _driverReceiptsCount = 0;
  int _driverPendingReceipts = 0;
  double _driverTotalDebt = 0;
  int _driverUnpaidDays = 0;
  DateTime? _driverLastPaymentAt;
  Map<String, dynamic>? _driverAgreement; // raw agreement map
  double _paidThisWeek = 0;
  double _paidThisMonth = 0;
  final List<Map<String, dynamic>> _driverDebtRecords =
      <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final ApiService api = ApiService();
      // Driver dashboard (authorized for driver role)
      final Map<String, dynamic> response = await api.getDriverDashboard();
      final Map<String, dynamic> data =
          response['data'] as Map<String, dynamic>? ?? response;

      // Load driver-focused data in parallel using driver endpoints
      final List<dynamic> results =
          await Future.wait<dynamic>(<Future<dynamic>>[
        api.getDriverReceipts(limit: 50),
        api.getDriverPaymentHistory(
            limit: 1000,
            startDate: DateTime.now().subtract(const Duration(days: 31)),
            endDate: DateTime.now()),
        api.getDriverPaymentsSummary(),
      ]);

      // Parse receipts counts
      final Map<String, dynamic> rec = results[0] as Map<String, dynamic>;
      final Map<String, dynamic> recData =
          rec['data'] as Map<String, dynamic>? ?? rec;
      final List<dynamic> receiptsList = (recData['data'] as List<dynamic>?) ??
          (recData['receipts'] as List<dynamic>?) ??
          const <dynamic>[];
      _driverReceiptsCount = recData['total'] as int? ??
          recData['count'] as int? ??
          receiptsList.length;

      // Pending receipts (not available on driver route); set 0
      _driverPendingReceipts = 0;

      // No debt endpoints for driver in current API; default zeros
      _driverTotalDebt = 0;
      _driverUnpaidDays = 0;
      _driverLastPaymentAt = null;
      _driverAgreement = data['agreement'] as Map<String, dynamic>?;

      // Prefer backend aggregation via driver controller (includes debt clearances + new payments)
      try {
        final Map<String, dynamic> sumResp = results[2] as Map<String, dynamic>;
        final Map<String, dynamic> sumData =
            (sumResp['data'] as Map<String, dynamic>? ?? sumResp)
                .cast<String, dynamic>();
        final Map<String, dynamic> totals =
            (sumData['totals'] as Map<String, dynamic>? ?? <String, dynamic>{})
                .cast<String, dynamic>();
        final double today = _toDouble(totals['today']);
        final double week = _toDouble(totals['week']);
        final double month = _toDouble(totals['month']);
        _dashboardData['payments_today'] = today;
        _paidThisWeek = week;
        _paidThisMonth = month;
      } on Exception catch (_) {
        // Fallback: derive from driver payment history if summary not available
        final Map<String, dynamic> pay = results[1] as Map<String, dynamic>;
        final dynamic root = pay['data'] ?? pay;
        final List<dynamic> payments = root is Map && root['data'] is List
            ? (root['data'] as List).cast<dynamic>()
            : root is Map && root['payments'] is List
                ? (root['payments'] as List).cast<dynamic>()
                : root is List
                    ? root.cast<dynamic>()
                    : const <dynamic>[];
        double day = 0;
        double week = 0;
        double month = 0;
        final DateTime now = DateTime.now();
        final DateTime todayStart = DateTime(now.year, now.month, now.day);
        final DateTime monthStart = DateTime(now.year, now.month);
        final DateTime weekStart = now.subtract(const Duration(days: 6));
        for (final dynamic p in payments) {
          if (p is Map) {
            final Map<String, dynamic> m = p.cast<String, dynamic>();
            final String? d =
                (m['paid_at'] ?? m['date'] ?? m['created_at'])?.toString();
            final DateTime? dt = d != null ? DateTime.tryParse(d) : null;
            final double amt = () {
              final dynamic raw = m['amount'] ??
                  m['paid_amount'] ??
                  m['total'] ??
                  m['total_amount'];
              if (raw is num) return raw.toDouble();
              return double.tryParse(raw?.toString() ?? '') ?? 0.0;
            }();
            if (dt != null) {
              if (!dt.isBefore(todayStart)) day += amt;
              if (!dt.isBefore(weekStart)) week += amt;
              if (!dt.isBefore(monthStart)) month += amt;
            }
          }
        }
        _paidThisWeek = week;
        _paidThisMonth = month;
        _dashboardData['payments_today'] = day;
      }

      setState(() {
        _dashboardData = data;
      });
    } on Exception catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    final String? name = Provider.of<AuthProvider>(context).user?.name;
    final String welcomeTitle =
        '${LocalizationService.instance.translate('welcome')}, ${(name?.isNotEmpty ?? false) ? name! : 'Driver'}!';
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        welcomeTitle,
        actions: <Widget>[
          IconButton(
            onPressed: _loadDashboardData,
            icon: Icon(
              Icons.refresh,
              size: ResponsiveUtils.getResponsiveIconSize(context, 24),
            ),
          ),
          PopupMenuButton<String>(
            color: ThemeConstants.primaryBlue,
            onSelected: (final String value) {
              if (value == "logout") {
                _handleLogout();
              }
            },
            itemBuilder: (final BuildContext context) =>
                <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: "logout",
                child: ResponsiveRow(
                  spacing: ResponsiveUtils.getResponsiveSpacing(context, 8),
                  children: <Widget>[
                    Icon(
                      Icons.logout,
                      color: Colors.white,
                      size: 20,
                    ),
                    Text(
                      LocalizationService.instance.translate('logout'),
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(color: ThemeConstants.primaryBlue),
        child: _isLoading
            ? ThemeConstants.buildLoadingWidget()
            : RefreshIndicator(
                onRefresh: _loadDashboardData,
                backgroundColor: Colors.white,
                color: ThemeConstants.primaryBlue,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  padding: ResponsiveUtils.getResponsivePadding(context),
                  child: ResponsiveColumn(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: ResponsiveUtils.getResponsiveSpacing(context, 24),
                    children: <Widget>[
                      // Assigned Vehicle
                      if (_dashboardData["assigned_vehicle"] !=
                          null) ...<Widget>[
                        Text(
                          LocalizationService.instance
                              .translate('your_vehicle'),
                          style: AppStyles.heading3Responsive(context),
                        ),
                        ThemeConstants.buildGlassCardStatic(
                          child: Padding(
                            padding: EdgeInsets.all(
                                ResponsiveUtils.getResponsiveSpacing(
                                    context, 16)),
                            child: ResponsiveRow(
                              spacing: ResponsiveUtils.getResponsiveSpacing(
                                context,
                                16,
                              ),
                              children: <Widget>[
                                Container(
                                  width: ResponsiveUtils.getResponsiveIconSize(
                                    context,
                                    60,
                                  ),
                                  height: ResponsiveUtils.getResponsiveIconSize(
                                    context,
                                    60,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(
                                      ResponsiveUtils.getResponsiveBorderRadius(
                                        context,
                                        12,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    _getVehicleIcon(
                                      _dashboardData["assigned_vehicle"]
                                          ["type"],
                                    ),
                                    color: AppColors.secondary,
                                    size: ResponsiveUtils.getResponsiveIconSize(
                                      context,
                                      32,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ResponsiveColumn(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing:
                                        ResponsiveUtils.getResponsiveSpacing(
                                      context,
                                      4,
                                    ),
                                    children: <Widget>[
                                      Text(
                                        _dashboardData["assigned_vehicle"]
                                            ["name"],
                                        style: AppStyles.bodyLargeResponsive(
                                                context)
                                            .copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      Text(
                                        "${LocalizationService.instance.translate('plate_number')}: ${_dashboardData["assigned_vehicle"]["plate_number"]}",
                                        style: AppStyles.bodyMediumResponsive(
                                                context)
                                            .copyWith(color: Colors.white70),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: ResponsiveUtils
                                              .getResponsiveSpacing(
                                            context,
                                            8,
                                          ),
                                          vertical: ResponsiveUtils
                                              .getResponsiveSpacing(
                                            context,
                                            4,
                                          ),
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.success
                                              .withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            ResponsiveUtils
                                                .getResponsiveBorderRadius(
                                              context,
                                              4,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          LocalizationService.instance
                                              .translate('status_active'),
                                          style: AppStyles.bodySmallResponsive(
                                                  context)
                                              .copyWith(
                                                  color: AppColors.success,
                                                  fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // Payment Statistics
                      Text(
                        LocalizationService.instance
                            .translate('driver_payment_stats'),
                        style: AppStyles.heading3Responsive(context)
                            .copyWith(color: Colors.white),
                      ),
                      ThemeConstants.buildGlassCardStatic(
                        child: Padding(
                          padding: EdgeInsets.all(
                              ResponsiveUtils.getResponsiveSpacing(
                                  context, 16)),
                          child: ResponsiveRow(
                            spacing: ResponsiveUtils.getResponsiveSpacing(
                                context, 16),
                            children: <Widget>[
                              Expanded(
                                child: _miniStat(
                                  icon: Icons.today,
                                  label: LocalizationService.instance
                                      .translate('today'),
                                  value:
                                      "TSh ${(_dashboardData["payments_today"] ?? 0).toStringAsFixed(0)}",
                                ),
                              ),
                              Expanded(
                                child: _miniStat(
                                  icon: Icons.calendar_view_week,
                                  label: LocalizationService.instance
                                      .translate('week'),
                                  value:
                                      "TSh ${_paidThisWeek.toStringAsFixed(0)}",
                                ),
                              ),
                              Expanded(
                                child: _miniStat(
                                  icon: Icons.calendar_month,
                                  label: LocalizationService.instance
                                      .translate('month'),
                                  value:
                                      "TSh ${_paidThisMonth.toStringAsFixed(0)}",
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Quick Actions
                      Text(
                        LocalizationService.instance.translate('quick_actions'),
                        style: AppStyles.heading3Responsive(context)
                            .copyWith(color: Colors.white),
                      ),
                      ResponsiveRow(
                        spacing:
                            ResponsiveUtils.getResponsiveSpacing(context, 16),
                        children: <Widget>[
                          Expanded(
                            child: _QuickActionCard(
                              title: LocalizationService.instance
                                  .translate('payment_history'),
                              icon: Icons.history,
                              color: AppColors.primary,
                              onTap: _navigateToPaymentHistory,
                            ),
                          ),
                          Expanded(
                            child: _QuickActionCard(
                              title: LocalizationService.instance
                                  .translate('receipts'),
                              icon: Icons.receipt,
                              color: AppColors.info,
                              onTap: _navigateToReceipts,
                            ),
                          ),
                          Expanded(
                            child: _QuickActionCard(
                              title: LocalizationService.instance
                                  .translate('reminders'),
                              icon: Icons.notifications,
                              color: AppColors.warning,
                              onTap: _navigateToReminders,
                            ),
                          ),
                        ],
                      ),

                      // Agreement / Total to Pay card
                      ThemeConstants.buildGlassCardStatic(
                        child: Padding(
                          padding: EdgeInsets.all(
                              ResponsiveUtils.getResponsiveSpacing(
                                  context, 16)),
                          child: ResponsiveColumn(
                            spacing: ResponsiveUtils.getResponsiveSpacing(
                              context,
                              16,
                            ),
                            children: <Widget>[
                              Icon(
                                Icons.account_balance_wallet,
                                size: ResponsiveUtils.getResponsiveIconSize(
                                  context,
                                  48,
                                ),
                                color: AppColors.success,
                              ),
                              Text(
                                _agreementTitle(),
                                style: AppStyles.bodyLargeResponsive(context)
                                    .copyWith(color: Colors.white),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _agreementValueText(),
                                  style: AppStyles.heading1Responsive(context)
                                      .copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Text(
                                _agreementSubtitle(),
                                style: AppStyles.bodySmallResponsive(context)
                                    .copyWith(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  IconData _getVehicleIcon(final String type) {
    switch (type) {
      case "bajaji":
        return Icons
            .directions_car; // three_wheeler not available, using car icon
      case "pikipiki":
        return Icons.motorcycle;
      case "gari":
        return Icons.directions_car;
      default:
        return Icons.directions_car;
    }
  }

  // ignore: unused_element
  void _showPaymentRequestDialog() {
    showDialog(
      context: context,
      builder: (final BuildContext context) => _PaymentRequestDialog(),
    );
  }

  void _navigateToPaymentHistory() {
    Navigator.pushNamed(context, "/driver/payment-history");
  }

  void _navigateToReceipts() {
    Navigator.pushNamed(context, "/driver/receipts");
  }

  void _navigateToReminders() {
    Navigator.pushNamed(context, "/driver/reminders");
  }

  // Small stat tile used in glass cards
  Widget _miniStat({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon,
                color: Colors.white70,
                size: ResponsiveUtils.getResponsiveIconSize(context, 18)),
            SizedBox(width: ResponsiveUtils.getResponsiveSpacing(context, 8)),
            Expanded(
              child: Text(
                label,
                style: AppStyles.bodySmallResponsive(context)
                    .copyWith(color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 8)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppStyles.heading3Responsive(context)
                .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
    return onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: content);
  }

  String _agreementTitle() {
    final String type =
        (_driverAgreement?['agreement_type']?.toString() ?? '').toLowerCase();
    if (type.contains('dei')) {
      return LocalizationService.instance.translate('agreement_daily_title');
    }
    return LocalizationService.instance.translate('agreement_total_title');
  }

  String _agreementValueText() {
    final String type =
        (_driverAgreement?['agreement_type']?.toString() ?? '').toLowerCase();
    if (type.contains('dei')) {
      final double perDay = _toDouble(_driverAgreement?['amount_per_day'] ??
          _driverAgreement?['kiasi_cha_makubaliano']);
      final double perWeek =
          _toDouble(_driverAgreement?['amount_per_week'] ?? 0);
      if (perWeek > 0) return LocalizationService.instance.translateWith('tsh_week', <Object?>[perWeek.toStringAsFixed(0)]);
      return LocalizationService.instance.translateWith('tsh_day', <Object?>[perDay.toStringAsFixed(0)]);
    }
    final double remaining = _toDouble(_driverAgreement?['remaining_total'] ??
        _driverAgreement?['total_expected']);
    return 'TSh ${remaining.toStringAsFixed(0)}';
  }

  String _agreementSubtitle() {
    final String type =
        (_driverAgreement?['agreement_type']?.toString() ?? '').toLowerCase();
    if (type.contains('dei')) {
      return LocalizationService.instance.translate('agreement_daily_subtitle');
    }
    return LocalizationService.instance.translate('agreement_total_subtitle');
  }

  double _toDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(RegExp(r'[^0-9\.-]'), '')) ??
        0;
  }

  Future<void> _handleLogout() async {
    final AuthProvider authProvider =
        Provider.of<AuthProvider>(context, listen: false);
    await authProvider.logout();
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    return CustomCard(
      onTap: onTap,
      backgroundColor: ThemeConstants.cardColor,
      elevation: 0,
      borderRadius: BorderRadius.circular(
        ResponsiveUtils.getResponsiveBorderRadius(context, 12),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveUtils.getResponsiveSpacing(context, 12),
        vertical: ResponsiveUtils.getResponsiveSpacing(context, 16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              color: color,
              size: ResponsiveUtils.getResponsiveIconSize(context, 28),
            ),
            SizedBox(height: ResponsiveUtils.getResponsiveSpacing(context, 8)),
            Text(
              title,
              style: AppStyles.bodyMediumResponsive(context).copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRequestDialog extends StatefulWidget {
  @override
  State<_PaymentRequestDialog> createState() => _PaymentRequestDialogState();
}

class _PaymentRequestDialogState extends State<_PaymentRequestDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _paymentMethod = "cash";
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitPaymentRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // TODO(dev): Submit payment request to API
      await Future.delayed(const Duration(seconds: 2)); // Simulate API call

      if (mounted) {
        Navigator.pop(context);
        ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('payment_request_sent_waiting_for_admin'));
      }
    } on Exception catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: AppStyles.dialogConstraints(context),
          child: ResponsiveContainer(
            child: Form(
              key: _formKey,
              child: ResponsiveColumn(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
                children: <Widget>[
                  Text(
                    LocalizationService.instance.translate('request_payment'),
                    style: AppStyles.heading3Responsive(context),
                  ),
                  TextFormField(
                    controller: _amountController,
                    style: AppStyles.bodyMediumResponsive(context),
                    decoration: AppStyles.inputDecoration(context).copyWith(
                      labelText: LocalizationService.instance.translate('amount_tsh'),
                      prefixText: "TSh ",
                    ),
                    keyboardType: TextInputType.number,
                    validator: (final String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return LocalizationService.instance.translate('amount_is_required');
                      }
                      if (double.tryParse(value) == null ||
                          double.parse(value) <= 0) {
                        return LocalizationService.instance.translate('invalid_amount');
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: _descriptionController,
                    style: AppStyles.bodyMediumResponsive(context),
                    decoration: AppStyles.inputDecoration(context).copyWith(
                      labelText: LocalizationService.instance.translate('description'),
                    ),
                    maxLines: 3,
                    validator: (final String? value) {
                      if (value == null || value.trim().isEmpty) {
                        return LocalizationService.instance.translate('description_is_required');
                      }
                      return null;
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    style: AppStyles.bodyMediumResponsive(context),
                    decoration: AppStyles.inputDecoration(context).copyWith(
                      labelText: LocalizationService.instance.translate('payment_method_label'),
                    ),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                        value: "cash",
                        child: Text(
                          LocalizationService.instance.translate('cash'),
                          style: AppStyles.bodyMediumResponsive(context),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      DropdownMenuItem(
                        value: "mobile_money",
                        child: Text(
                          LocalizationService.instance.translate('mobile_money'),
                          style: AppStyles.bodyMediumResponsive(context),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      DropdownMenuItem(
                        value: "bank_transfer",
                        child: Text(
                          LocalizationService.instance.translate('bank_transfer'),
                          style: AppStyles.bodyMediumResponsive(context),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                    onChanged: (final String? value) {
                      setState(() {
                        _paymentMethod = value!;
                      });
                    },
                  ),
                  ResponsiveRow(
                    spacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
                    children: <Widget>[
                      Expanded(
                        child: CustomButton(
                          text: LocalizationService.instance.translate('cancel_2'),
                          onPressed: () => Navigator.pop(context),
                          isOutlined: true,
                        ),
                      ),
                      Expanded(
                        child: CustomButton(
                          text: _isLoading ? "${LocalizationService.instance.translate('sending_2')}..." : LocalizationService.instance.translate('send_request'),
                          onPressed: _isLoading ? null : _submitPaymentRequest,
                          isLoading: _isLoading,
                        ),
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
