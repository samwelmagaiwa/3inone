import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'tenant_receipt_repository_screen.dart';
import '../../services/localization_service.dart';

class TenantSelfServiceScreen extends StatefulWidget {
  const TenantSelfServiceScreen({super.key});

  @override
  State<TenantSelfServiceScreen> createState() =>
      _TenantSelfServiceScreenState();
}

class _TenantSelfServiceScreenState extends State<TenantSelfServiceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic>? _tenantData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadTenantData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTenantData() async {
    setState(() => _isLoading = true);
    final ApiService api = ApiService();
    try {
      final results = await Future.wait<Map<String, dynamic>>([
        api.getTenantBills(),
        api.getTenantPayments(),
      ]);

      final bills = (results[0]['data'] as List?) ?? [];
      final payments = (results[1]['data'] as List?) ?? [];
      
      String house = 'N/A';
      String property = 'N/A';
      int balance = 0;

      if (bills.isNotEmpty) {
        final firstBill = bills.first;
        house = firstBill['house']?['house_number'] ?? house;
        property = firstBill['property']?['name'] ?? property;
        
        balance = bills.fold(0, (sum, item) {
          final val = item['balance'];
          if (val == null) return sum;
          final parsed = num.tryParse(val.toString())?.toInt() ?? 0;
          return sum + parsed;
        });
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _tenantData = {
            'house': house,
            'property': property,
            'balance': balance,
            'bills': bills,
            'payments': payments,
          };
        });
      }
    } catch (e) {
      debugPrint('Error loading tenant self-service data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('failed_to_load_account_data'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.bgTop,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: _isLoading 
                    ? ThemeConstants.buildResponsiveLoadingWidget(context)
                    : _buildContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Container(decoration: ThemeConstants.dashboardBackground),
        Positioned(
          top: -100.h,
          right: -50.w,
          child: Container(
            width: 300.w,
            height: 300.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ThemeConstants.primaryOrange.withOpacity(0.15),
            ),
          ).withBlur(80),
        ),
        Positioned(
          bottom: 100.h,
          left: -100.w,
          child: Container(
            width: 400.w,
            height: 400.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF14B8A6).withOpacity(0.12),
            ),
          ).withBlur(90),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              ),
              Text(
                LocalizationService.instance.translate('tenant_self_service'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _loadTenantData,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final user = Provider.of<AuthProvider>(context).user;
    final name = user?.name ?? LocalizationService.instance.translate('agreement_step_tenant');
    final house = _tenantData?['house'] ?? '...';
    final property = _tenantData?['property'] ?? '...';
    final balance = _tenantData?['balance'] ?? 0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 18.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 10.h),
          _buildProfileHeader(name, house, property, balance),
          SizedBox(height: 24.h),
          _buildTabSystem(),
          SizedBox(height: 20.h),
          _buildTabContent(),
          SizedBox(height: 30.h),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(String name, String house, String property, int balance) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.02),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            children: [
              // Smaller Avatar with ring
              Container(
                padding: EdgeInsets.all(2.w),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ThemeConstants.primaryOrange, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 24.r,
                  backgroundColor: ThemeConstants.primaryOrange.withOpacity(0.2),
                  child: Icon(Icons.person_outline, color: Colors.white, size: 22.sp),
                ),
              ),
              SizedBox(width: 12.w),
              
              // House & Balance Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      house != 'N/A' ? "$house - $property" : LocalizationService.instance.translate('see_your_bills'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: (balance > 0 ? ThemeConstants.errorRed : ThemeConstants.successGreen).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        LocalizationService.instance.translateWith('balance_due_tsh', <Object?>[balance]),
                        style: TextStyle(
                          color: balance > 0 ? ThemeConstants.errorRed : ThemeConstants.successGreen,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Repository Link
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TenantReceiptRepositoryScreen())
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_shared_outlined, color: ThemeConstants.primaryOrange, size: 20.sp),
                    SizedBox(height: 2.h),
                    Text(
                      LocalizationService.instance.translate('receipt'),
                      style: TextStyle(
                        color: ThemeConstants.primaryOrange,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white54, fontSize: 12.sp),
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTabSystem() {
    return Container(
      height: 50.h,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(25.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(21.r),
          gradient: const LinearGradient(
            colors: [ThemeConstants.primaryOrange, Color(0xFFEA580C)],
          ),
          boxShadow: [
            BoxShadow(
              color: ThemeConstants.primaryOrange.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        labelStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold),
        unselectedLabelStyle: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.normal),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        tabs: [
          Tab(text: LocalizationService.instance.translate('bills_label')),
          Tab(text: LocalizationService.instance.translate('payments_section')),
          Tab(text: LocalizationService.instance.translate('receipt')),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabController.index) {
      case 0: return _buildInvoiceList();
      case 1: return _buildPaymentHistory();
      case 2: return _buildReceiptSummary();
      default: return const SizedBox();
    }
  }

  Widget _buildInvoiceList() {
    final bills = _tenantData?['bills'] as List? ?? [];
    if (bills.isEmpty) return _buildEmptyTab(LocalizationService.instance.translate('no_bills_yet'));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: bills.length,
      itemBuilder: (context, index) {
        final bill = bills[index];
        final isPaid = bill['status'] == 'paid' || bill['status'] == LocalizationService.instance.translate('bill_paid');
        return _buildModernCard(
          title: LocalizationService.instance.translate('rent_2'),
          subtitle: bill['month_year'] ?? "N/A",
          amount: "TSh ${bill['amount_due']}",
          icon: isPaid ? Icons.check_circle_outline : Icons.pending_outlined,
          status: isPaid ? LocalizationService.instance.translate('bill_paid') : LocalizationService.instance.translate('unpaid_2'),
          statusColor: isPaid ? ThemeConstants.successGreen : ThemeConstants.warningAmber,
        );
      },
    );
  }

  Widget _buildPaymentHistory() {
    final payments = _tenantData?['payments'] as List? ?? [];
    if (payments.isEmpty) return _buildEmptyTab(LocalizationService.instance.translate('no_payments_made'));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final payment = payments[index];
        return _buildModernCard(
          title: LocalizationService.instance.translate('rent_payments'),
          subtitle: payment['payment_date'] ?? "N/A",
          amount: "TSh ${payment['amount']}",
          icon: Icons.account_balance_wallet_outlined,
          status: LocalizationService.instance.translate('confirmed'),
          statusColor: ThemeConstants.successGreen,
        );
      },
    );
  }

  Widget _buildReceiptSummary() {
    return _buildEmptyTab(LocalizationService.instance.translate('see_the_repository_for_all_receipts'));
  }

  Widget _buildModernCard({
    required String title,
    required String subtitle,
    required String amount,
    required IconData icon,
    required String status,
    required Color statusColor,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.r),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(icon, color: ThemeConstants.primaryOrange, size: 24.sp),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(color: Colors.white54, fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amount,
                      style: TextStyle(color: Colors.white, fontSize: 15.sp, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      status,
                      style: TextStyle(color: statusColor, fontSize: 11.sp, fontWeight: FontWeight.w500),
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

  Widget _buildEmptyTab(String message) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 40.h),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 50.sp, color: Colors.white24),
            SizedBox(height: 16.h),
            Text(
              message,
              style: TextStyle(color: Colors.white24, fontSize: 16.sp),
            ),
          ],
        ),
      ),
    );
  }
}

extension BlurExtension on Widget {
  Widget withBlur(double sigma) => ClipRRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: this,
    ),
  );
}
