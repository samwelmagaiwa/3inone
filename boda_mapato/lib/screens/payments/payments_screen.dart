import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../models/driver.dart';
import '../../models/payment.dart';
import '../../providers/debts_provider.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/responsive_helper.dart';
import 'new_payment_screen.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with TickerProviderStateMixin {
  bool _listeningProvider = false;
  final ApiService _apiService = ApiService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  // Animation controllers
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // State variables
  List<Driver> _drivers = [];
  List<Driver> _filteredDrivers = [];
  Driver? _selectedDriver;
  PaymentSummary? _driverPaymentSummary;
  final List<DebtRecord> _selectedDebts = [];
  PaymentChannel _selectedChannel = PaymentChannel.cash;
  final Set<String> _newPaymentDriversThisMonth = <String>{};

  bool _isLoadingDrivers = true;
  bool _isLoadingDebts = false;
  bool _isSubmittingPayment = false;
  bool _isDriverSelectionMode = true;

  String? _errorMessage;
  double _totalSelectedAmount = 0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadDriversWithDebts();
    _searchController.addListener(_filterDrivers);
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ));

    _fadeController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listeningProvider) {
      _listeningProvider = true;
      try {
        final DebtsProvider dp =
            Provider.of<DebtsProvider>(context, listen: false);
        dp.addListener(() async {
          if (dp.shouldRefresh) {
            await _loadDriversWithDebts();
            if (_selectedDriver != null) {
              await _loadDriverDebts(_selectedDriver!.id);
            }
            dp.consume();
          }
        });
      } on Exception catch (e) {
        debugPrint('Failed to set up DebtsProvider listener: $e');
      }
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    _amountController.dispose();
    _remarksController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDriversWithDebts() async {
    try {
      if (mounted) {
        setState(() {
          _isLoadingDrivers = true;
          _errorMessage = null;
        });
      }

      // Backend moved drivers-with-debts under /admin/debts/drivers
      final Map<String, Object?> response =
          await _apiService.getDebtDrivers() as Map<String, Object?>;

      final bool success = (response['success'] as bool?) ?? false;

      if (success) {
        final Map<String, dynamic> data =
            (response['data'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
        final List<dynamic> driversData =
            (data['drivers'] as List?)?.cast<dynamic>() ?? <dynamic>[];
        if (mounted) {
          setState(() {
            _drivers = driversData
                .map(
                    (driver) => Driver.fromJson(driver as Map<String, dynamic>))
                .toList();
            _filteredDrivers = List<Driver>.from(_drivers);
            _isLoadingDrivers = false;
          });
        }
        // After loading drivers, fetch new-payment map for this month
        await _loadNewPaymentsMapForThisMonth();
      } else {
        final String msg =
            response['message'] as String? ?? LocalizationService.instance.translate('failed_to_load_drivers');
        throw Exception(msg);
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = LocalizationService.instance.translateWith('failed_to_load_drivers_2', <Object?>[e]);
          _isLoadingDrivers = false;
        });
      }
    }
  }

  Future<void> _loadNewPaymentsMapForThisMonth() async {
    try {
      final DateTime now = DateTime.now();
      final String month =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
      final Map<String, dynamic> res =
          await _apiService.getNewPaymentsMap(month: month);
      final Map<String, dynamic>? data = res['data'] as Map<String, dynamic>?;
      final List<dynamic> drivers =
          (data?['drivers'] as List<dynamic>?) ?? <dynamic>[];
      if (mounted) {
        setState(() {
          _newPaymentDriversThisMonth
            ..clear()
            ..addAll(drivers
                .map((e) => (e as Map)['driver_id']?.toString() ?? '')
                .where((s) => s.isNotEmpty));
        });
      }
    } on Exception catch (_) {
      // Silently ignore; badge is optional
    }
  }

  Future<void> _loadDriverDebts(String driverId) async {
    try {
      if (mounted) {
        setState(() {
          _isLoadingDebts = true;
          _errorMessage = null;
        });
      }

      final response = await _apiService.getDriverDebtSummary(driverId);

      if (response['success'] == true) {
        final summaryData = response['data'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _driverPaymentSummary = PaymentSummary.fromJson(summaryData);
            _isLoadingDebts = false;
          });
        }
      } else {
        throw Exception(response['message'] ?? LocalizationService.instance.translate('failed_to_load_debt_records'));
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = LocalizationService.instance.translateWith('failed_to_load_debt_records_2', <Object?>[e]);
          _isLoadingDebts = false;
        });
      }
    }
  }

  void _filterDrivers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredDrivers = _drivers.where((driver) {
        return driver.name.toLowerCase().contains(query) ||
            driver.phone.toLowerCase().contains(query) ||
            driver.email.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _selectDriver(Driver driver) {
    setState(() {
      _selectedDriver = driver;
      _isDriverSelectionMode = false;
    });

    _slideController.forward();
    _loadDriverDebts(driver.id);
  }

  void _backToDriverSelection() {
    setState(() {
      _isDriverSelectionMode = true;
      _selectedDriver = null;
      _driverPaymentSummary = null;
      _selectedDebts.clear();
      _totalSelectedAmount = 0.0;
      _amountController.clear();
      _remarksController.clear();
    });

    _slideController.reverse();
  }

  void _toggleDebtSelection(DebtRecord debt) {
    setState(() {
      if (_selectedDebts.contains(debt)) {
        _selectedDebts.remove(debt);
        _totalSelectedAmount -= debt.remainingAmount;
      } else {
        _selectedDebts.add(debt);
        _totalSelectedAmount += debt.remainingAmount;
      }

      // Update amount controller with total selected amount
      _amountController.text = _totalSelectedAmount.toStringAsFixed(0);
    });
  }

  String _mapChannelToMethod(PaymentChannel ch) {
    // Map to backend-expected values: cash, bank, mobile, other
    switch (ch) {
      case PaymentChannel.cash:
        return 'cash';
      case PaymentChannel.bank:
        return 'bank';
      case PaymentChannel.mobile:
        return 'mobile';
      case PaymentChannel.other:
        return 'other';
    }
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDebts.isEmpty) {
      _showErrorDialog(LocalizationService.instance.translate('select_at_least_one_payment_day'));
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isSubmittingPayment = true;
        });
      }

      final Map<String, dynamic> paymentData = <String, dynamic>{
        'driver_id': _selectedDriver!.id.trim(),
        'amount': double.parse(_amountController.text),
        // Backend expects 'payment_channel' values: cash | bank | mobile | other
        'payment_channel': _mapChannelToMethod(_selectedChannel),
        // Backend expects 'covers_days' as an array of YYYY-MM-DD strings
        'covers_days': _selectedDebts.map((debt) => debt.date).toList(),
        if (_remarksController.text.trim().isNotEmpty)
          'remarks': _remarksController.text.trim(),
      };

      final response = await _apiService.recordPayment(paymentData);

      if (response['success'] == true) {
        // Notify other parts (Rekodi Madeni) to refresh its list
        try {
          // ignore: use_build_context_synchronously
          Provider.of<DebtsProvider>(context, listen: false).markChanged();
        } on Exception catch (_) {}
        _showSuccessDialog();
      } else {
        throw Exception(response['message'] ?? LocalizationService.instance.translate('failed_to_record_payment_2'));
      }
    } on Exception catch (e) {
      _showErrorDialog(LocalizationService.instance.translateWith('error_saving_the_payment', <Object?>[e]));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingPayment = false;
        });
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ThemeConstants.successGreen.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: ThemeConstants.successGreen,
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${LocalizationService.instance.translate('payment_saved')}!',
                style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                LocalizationService.instance.translateWith('payment_of_tsh_saved_for', <Object?>[_formatCurrency(_amountController.text), _selectedDriver?.name]),
                style: const TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Payment Details Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          color: ThemeConstants.primaryOrange,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          LocalizationService.instance.translate('payment_details'),
                          style: TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Payment channel
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${LocalizationService.instance.translate('payment_method_label')}:',
                          style: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _selectedChannel.displayName,
                          style: const TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Days covered
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${LocalizationService.instance.translate('covered_days')}:',
                          style: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${_selectedDebts.length}',
                          style: const TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    if (_remarksController.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${LocalizationService.instance.translate('description')}:',
                            style: TextStyle(
                              color: ThemeConstants.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _remarksController.text,
                              style: const TextStyle(
                                color: ThemeConstants.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Paid days summary
              if (_selectedDebts.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ThemeConstants.successGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: ThemeConstants.successGreen.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.event_available,
                            color: ThemeConstants.successGreen,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            LocalizationService.instance.translate('covered_days'),
                            style: TextStyle(
                              color: ThemeConstants.successGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _selectedDebts.map((debt) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  ThemeConstants.successGreen.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              debt.formattedDate,
                              style: const TextStyle(
                                color: ThemeConstants.successGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // Stay on payment form to record another payment
                        _clearForm();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ThemeConstants.textPrimary,
                        side: const BorderSide(
                          color: ThemeConstants.textSecondary,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        LocalizationService.instance.translate('another_payment'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _backToDriverSelection();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeConstants.primaryOrange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        LocalizationService.instance.translate('finish'),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
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

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.error, color: ThemeConstants.errorRed, size: 18.sp),
            SizedBox(width: 8.w),
            Expanded(
              child: AutoSizeText(
                LocalizationService.instance.translate('error'),
                style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                stepGranularity: 0.5,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: ThemeConstants.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              LocalizationService.instance.translate('ok'),
              style: TextStyle(
                color: ThemeConstants.primaryOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(String amount) {
    try {
      final number = double.parse(amount);
      if (number >= 1000000) {
        return '${(number / 1000000).toStringAsFixed(1)}M';
      } else if (number >= 1000) {
        return '${(number / 1000).toStringAsFixed(0)}K';
      }
      return number.toStringAsFixed(0);
    } on FormatException catch (_) {
      return amount;
    }
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);

    return Consumer<LocalizationService>(
      builder: (context, l10n, _) {
        return ThemeConstants.buildScaffold(
          title: l10n.translate('payments'),
          body: FadeTransition(
            opacity: _fadeAnimation,
            child: Stack(
              children: [
                if (_isDriverSelectionMode) _buildDriverSelectionView(),
                SlideTransition(
                  position: _slideAnimation,
                  child: !_isDriverSelectionMode
                      ? _buildPaymentFormView()
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriverSelectionView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          ThemeConstants.buildGlassCardStatic(
            child: Padding(
              padding: EdgeInsets.all(12.w),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: ThemeConstants.primaryOrange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.payment,
                      color: ThemeConstants.primaryOrange,
                      size: 24.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LocalizationService.instance
                              .translate('record_payment'),
                          style: TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          LocalizationService.instance
                              .translate('record_payment_subtitle'),
                          style: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontSize: 14.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 16.h),

          // Search Bar
          ThemeConstants.buildGlassCard(
            onTap: () {},
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    color: ThemeConstants.textSecondary,
                    size: 20.sp,
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ThemeConstants.primaryBlue.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12.r),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          color: ThemeConstants.textPrimary,
                          fontSize: 16.sp,
                        ),
                        decoration: InputDecoration(
                          hintText: LocalizationService.instance
                              .translate('search_drivers'),
                          hintStyle: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontSize: 14.sp,
                          ),
                          filled: true,
                          fillColor: Colors
                              .transparent, // background handled by Container above
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12.w, vertical: 8.h),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 10.h),

          // Drivers List
          if (_isLoadingDrivers)
            _buildLoadingState()
          else if (_errorMessage != null)
            _buildErrorState()
          else if (_filteredDrivers.isEmpty)
            _buildEmptyState()
          else
            _buildDriversList(),
        ],
      ),
    );
  }

  Widget _buildPaymentFormView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(12.w),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Driver Info Header
            _buildDriverInfoHeader(),
            SizedBox(height: 12.h),

            // Payment Summary if debts loaded
            if (_driverPaymentSummary != null) _buildDebtSummaryCard(),

            SizedBox(height: 12.h),

            // Debt Records Selection
            if (_isLoadingDebts)
              _buildLoadingState()
            else if (_driverPaymentSummary != null)
              _buildDebtRecordsList(),

            SizedBox(height: 12.h),

            // Payment Form
            if (_driverPaymentSummary != null && !_isLoadingDebts)
              _buildPaymentForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverInfoHeader() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: EdgeInsets.all(10.w),
        child: Row(
          children: [
            IconButton(
              onPressed: _backToDriverSelection,
              icon: const Icon(
                Icons.arrow_back,
                color: ThemeConstants.textPrimary,
              ),
            ),
            SizedBox(width: 8.w),
            CircleAvatar(
              backgroundColor: ThemeConstants.primaryOrange.withOpacity(0.2),
              child: Text(
                _selectedDriver?.name.substring(0, 1).toUpperCase() ?? '?',
                style: const TextStyle(
                  color: ThemeConstants.primaryOrange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedDriver?.name ?? '',
                    style: TextStyle(
                      color: ThemeConstants.textPrimary,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    _selectedDriver?.phone ?? '',
                    style: TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtSummaryCard() {
    final summary = _driverPaymentSummary!;

    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.summarize,
                  color: ThemeConstants.primaryOrange,
                  size: 20.sp,
                ),
                SizedBox(width: 8.w),
                Text(
                  LocalizationService.instance.translate('debt_summary'),
                  style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    LocalizationService.instance.translate('total_owed'),
                    'TSh ${_formatCurrency(summary.totalDebt.toString())}',
                    ThemeConstants.errorRed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryItem(
                    LocalizationService.instance.translate('days_remaining'),
                    '${summary.unpaidDays}',
                    ThemeConstants.warningAmber,
                  ),
                ),
              ],
            ),
            if (summary.lastPaymentDate != null) ...[
              const SizedBox(height: 8),
              _buildSummaryItem(
                LocalizationService.instance.translate('last_payment'),
                _formatDate(summary.lastPaymentDate!),
                ThemeConstants.successGreen,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String title, String value, Color color) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtRecordsList() {
    final unpaidDebts = _driverPaymentSummary!.debtRecords
        .where((debt) => !debt.isPaid)
        .toList();

    if (unpaidDebts.isEmpty) {
      return ThemeConstants.buildGlassCardStatic(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle,
                color: ThemeConstants.successGreen,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                LocalizationService.instance.translate('no_debt'),
                style: const TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LocalizationService.instance.translate('driver_has_no_debt'),
                style: const TextStyle(
                  color: ThemeConstants.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.list_alt,
              color: ThemeConstants.textPrimary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              LocalizationService.instance.translate('select_payment_days'),
              style: const TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildDebtRecordsGrid(unpaidDebts),
      ],
    );
  }

  Widget _buildDebtRecordsGrid(List<DebtRecord> unpaidDebts) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: unpaidDebts.map((debt) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 44) /
              2, // Account for container padding (32) and wrap spacing (12)
          child: _buildDebtRecordCard(debt),
        );
      }).toList(),
    );
  }

  Widget _buildDebtRecordCard(DebtRecord debt) {
    final isSelected = _selectedDebts.contains(debt);

    return ThemeConstants.buildGlassCard(
      onTap: () => _toggleDebtSelection(debt),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.r),
          border: isSelected
              ? Border.all(color: ThemeConstants.primaryOrange, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    ThemeConstants.primaryOrange.withOpacity(0.1),
                    ThemeConstants.primaryOrange.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 24.w,
              height: 24.w,
              decoration: BoxDecoration(
                color: isSelected
                    ? ThemeConstants.primaryOrange
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? ThemeConstants.primaryOrange
                      : ThemeConstants.textSecondary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4.r),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16.sp,
                    )
                  : null,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    debt.formattedDate,
                    style: TextStyle(
                      color: isSelected
                          ? ThemeConstants.primaryOrange
                          : ThemeConstants.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'TSh ${debt.remainingAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: isSelected
                          ? ThemeConstants.primaryOrange
                          : ThemeConstants.textSecondary,
                      fontSize: 12.sp,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: [
                      if ((debt.licenseNumber ?? '').isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.badge,
                                  size: 12.sp,
                                  color: ThemeConstants.textSecondary),
                              SizedBox(width: 4.w),
                              Flexible(
                                child: Text(
                                  LocalizationService.instance.translateWith('license_2', <Object?>[debt.licenseNumber]),
                                  style: TextStyle(
                                      color: ThemeConstants.textSecondary,
                                      fontSize: 10.sp),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (debt.promisedToPay)
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color:
                                ThemeConstants.warningAmber.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_available,
                                  size: 12.sp,
                                  color: ThemeConstants.warningAmber),
                              SizedBox(width: 4.w),
                              Flexible(
                                child: Text(
                                  debt.promiseToPayAt == null
                                      ? LocalizationService.instance.translate('promise_to_pay')
                                      : LocalizationService.instance.translateWith('promise', <Object?>[_formatDate(debt.promiseToPayAt!)]),
                                  style: TextStyle(
                                      color: ThemeConstants.warningAmber,
                                      fontSize: 10.sp),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
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
            if (debt.isOverdue)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: ThemeConstants.errorRed.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '${debt.daysOverdue}d',
                  style: TextStyle(
                    color: ThemeConstants.errorRed,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.payments,
              color: ThemeConstants.textPrimary,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              LocalizationService.instance.translate('payment_details'),
              style: TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ThemeConstants.buildGlassCardStatic(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Amount Field
                Text(
                  LocalizationService.instance.translate('amount_tsh'),
                  style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 6.h),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: LocalizationService.instance.translate('enter_the_payment_amount'),
                    hintStyle: TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 14.sp,
                    ),
                    prefixIcon: Icon(
                      Icons.monetization_on,
                      color: ThemeConstants.primaryOrange,
                      size: 20.sp,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: const BorderSide(
                        color: ThemeConstants.primaryOrange,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return LocalizationService.instance.translate('enter_the_payment_amount');
                    }

                    final amount = double.tryParse(value);
                    if (amount == null || amount <= 0) {
                      return LocalizationService.instance.translate('enter_a_valid_amount_3');
                    }

                    return null;
                  },
                ),

                SizedBox(height: 12.h),

                // Payment Channel
                Text(
                  LocalizationService.instance.translate('payment_method_label'),
                  style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.h),

                Row(
                  children: PaymentChannel.values.map((channel) {
                    final isSelected = _selectedChannel == channel;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedChannel = channel;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 8.h,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? ThemeConstants.primaryOrange
                                  : Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20.r),
                              border: Border.all(
                                color: isSelected
                                    ? ThemeConstants.primaryOrange
                                    : Colors.white.withOpacity(0.3),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                channel.displayName,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : ThemeConstants.textPrimary,
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                SizedBox(height: 12.h),

                // Remarks Field
                Text(
                  LocalizationService.instance.translate('note_optional'),
                  style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 6.h),
                TextFormField(
                  controller: _remarksController,
                  maxLines: 3,
                  style: TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 14.sp,
                  ),
                  decoration: InputDecoration(
                    hintText: '${LocalizationService.instance.translate('write_any_extra_details')}...',
                    hintStyle: TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 14.sp,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: const BorderSide(
                        color: ThemeConstants.primaryOrange,
                        width: 2,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 24.h),

                // Submit Button
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isSubmittingPayment || _selectedDebts.isEmpty
                          ? [Colors.grey.shade600, Colors.grey.shade700]
                          : [
                              ThemeConstants.primaryOrange,
                              const Color(0xFFEA580C)
                            ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: (_isSubmittingPayment || _selectedDebts.isEmpty
                                ? Colors.grey
                                : ThemeConstants.primaryOrange)
                            .withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isSubmittingPayment || _selectedDebts.isEmpty
                        ? null
                        : _submitPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isSubmittingPayment) ...[
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ] else ...[
                          Icon(Icons.save, size: 20.sp),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          _isSubmittingPayment
                              ? '${LocalizationService.instance.translate('saving')}...'
                              : LocalizationService.instance.translate('save_payment'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriversList() {
    return Column(
      children: _filteredDrivers.map((driver) {
        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: ThemeConstants.buildGlassCard(
            onTap: () => _showDriverActionPopup(driver),
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        ThemeConstants.primaryOrange.withOpacity(0.2),
                    child: Text(
                      driver.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: ThemeConstants.primaryOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver.name,
                          style: TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          driver.phone,
                          style: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontSize: 12.sp,
                          ),
                        ),
                        if (driver.vehicleNumber?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 2),
                          Text(
                            driver.vehicleNumber!,
                            style: const TextStyle(
                              color: ThemeConstants.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 4.h,
                    ),
                    decoration: BoxDecoration(
                      color: (driver.totalDebt > 0
                              ? ThemeConstants.errorRed
                              : ThemeConstants.successGreen)
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      driver.totalDebt > 0 ? LocalizationService.instance.translate('has_debt_2') : LocalizationService.instance.translate('no_debt_2'),
                      style: TextStyle(
                        color: driver.totalDebt > 0
                            ? ThemeConstants.errorRed
                            : ThemeConstants.successGreen,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_newPaymentDriversThisMonth.contains(driver.id)) ...[
                    SizedBox(width: 6.w),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: ThemeConstants.primaryOrange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(
                            color:
                                ThemeConstants.primaryOrange.withOpacity(0.5)),
                      ),
                      child: Text(
                        LocalizationService.instance.translate('new').toUpperCase(),
                        style: TextStyle(
                          color: ThemeConstants.primaryOrange,
                          fontSize: 9.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(width: 8.w),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: ThemeConstants.textSecondary,
                    size: 16.sp,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showDriverActionPopup(Driver driver) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        final bool hasDebt = (driver.totalDebt) > 0;
        return AlertDialog(
          backgroundColor: ThemeConstants.primaryBlue,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor:
                        ThemeConstants.primaryOrange.withOpacity(0.2),
                    child: Text(
                      (driver.name.isNotEmpty ? driver.name[0] : '?')
                          .toUpperCase(),
                      style:
                          const TextStyle(color: ThemeConstants.primaryOrange),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          driver.name,
                          style: const TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if ((driver.vehicleNumber ?? '').isNotEmpty)
                          Text(driver.vehicleNumber!,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Text(
                  hasDebt
                      ? LocalizationService.instance.translateWith('the_driver_has_a_debt_of', <Object?>[_formatCurrency(driver.totalDebt.toString())])
                      : '${LocalizationService.instance.translate('the_driver_has_no_debt_you')}.',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              if (hasDebt)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _selectDriver(driver);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(LocalizationService.instance.translate('debts')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  NewPaymentScreen(initialDriver: driver),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ThemeConstants.primaryOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(LocalizationService.instance.translate('new_payment')),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              NewPaymentScreen(initialDriver: driver),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(LocalizationService.instance.translate('record_new_payment')),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          children: [
            CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(ThemeConstants.primaryOrange),
            ),
            SizedBox(height: 16),
            Text(
              '${LocalizationService.instance.translate('loading_2')}...',
              style: TextStyle(
                color: ThemeConstants.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline,
              color: ThemeConstants.errorRed,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '${LocalizationService.instance.translate('error')}!',
              style: TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? LocalizationService.instance.translate('unknown_error'),
              style: const TextStyle(
                color: ThemeConstants.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDriversWithDebts,
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeConstants.primaryOrange,
              ),
              child: Text(
                LocalizationService.instance.translate('try_again'),
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ThemeConstants.buildGlassCardStatic(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.search_off,
              color: ThemeConstants.textSecondary,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              LocalizationService.instance.translate('no_results'),
              style: TextStyle(
                color: ThemeConstants.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              LocalizationService.instance.translate('no_driver_found_for_this_search'),
              style: TextStyle(
                color: ThemeConstants.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _clearForm() {
    setState(() {
      _selectedDebts.clear();
      _totalSelectedAmount = 0.0;
      _amountController.clear();
      _remarksController.clear();
      _selectedChannel = PaymentChannel.cash;
      // Keep the selected driver and their debts loaded
      // so user can make another payment without re-selecting driver
    });
  }
}
