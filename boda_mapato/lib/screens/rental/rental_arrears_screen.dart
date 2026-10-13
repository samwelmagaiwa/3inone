import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rental_provider.dart';
import '../../utils/rental_flow_validator.dart';
import '../../utils/type_helpers.dart';
import '../../services/localization_service.dart';

class RentalArrearsScreen extends StatefulWidget {
  const RentalArrearsScreen({super.key});

  @override
  State<RentalArrearsScreen> createState() => _RentalArrearsScreenState();
}

class _RentalArrearsScreenState extends State<RentalArrearsScreen> {
  RentalFlowStage? _flowStage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<AuthProvider>().user;
      final provider = context.read<RentalProvider>();
      if (user?.hasPermission('manage_properties_rental') ?? false) {
        await provider.fetchProperties();
        await provider.fetchTenants();
        await provider.fetchArrears();

        if (!context.mounted) return;

        if (!RentalFlowValidator.hasProperties(provider)) {
          setState(() => _flowStage = RentalFlowStage.hasNoProperties);
        } else if (!RentalFlowValidator.hasHouses(provider)) {
          setState(() => _flowStage = RentalFlowStage.hasNoHouses);
        } else if (!RentalFlowValidator.hasTenants(provider)) {
          setState(() => _flowStage = RentalFlowStage.hasNoTenants);
        } else if (!RentalFlowValidator.hasActiveAgreements(provider)) {
          setState(() => _flowStage = RentalFlowStage.hasNoAgreements);
        } else {
          setState(() => _flowStage = RentalFlowStage.complete);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rentalProvider = context.watch<RentalProvider>();
    final arrears = rentalProvider.arrears;

    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translate('rent_debt'),
      body: Column(
        children: [
          if (_flowStage != null && _flowStage != RentalFlowStage.complete)
            RentalFlowValidator.buildStageBanner(
                  stage: _flowStage!,
                  context: context,
                ) ??
                const SizedBox.shrink(),
          Expanded(
            child: rentalProvider.isLoading && arrears.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : arrears.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle,
                                size: 64, color: ThemeConstants.successGreen),
                            SizedBox(height: 16.h),
                            Text(LocalizationService.instance.translate('no_debt_3'),
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 16.sp)),
                            Text(LocalizationService.instance.translate('all_tenants_have_paid'),
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 14.sp)),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          _buildSummaryCard(context, arrears),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.all(16.w),
                              itemCount: arrears.length,
                              itemBuilder: (context, index) {
                                final bill = arrears[index];
                                return _buildArrearCard(context, bill);
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, List arrears) {
    final totalArrears = arrears.fold<double>(
        0, (sum, b) => sum + TypeHelpers.toDouble(b['balance']));
    final overdueCount = arrears.where((b) => b['status'] == 'overdue').length;
    final partialCount = arrears.where((b) => b['status'] == 'partial').length;

    return Container(
      margin: EdgeInsets.all(16.w),
      padding: EdgeInsets.all(16.w),
      decoration: ThemeConstants.glassCardDecoration,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                    LocalizationService.instance.translate('total'),
                    "TSh ${_formatCurrency(totalArrears)}",
                    ThemeConstants.errorRed),
              ),
              Expanded(
                child: _buildSummaryItem(LocalizationService.instance.translate('overdue'), overdueCount.toString(),
                    ThemeConstants.errorRed),
              ),
              Expanded(
                child: _buildSummaryItem(LocalizationService.instance.translate('bill_partial'), partialCount.toString(),
                    ThemeConstants.warningAmber),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18.sp, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
      ],
    );
  }

  Widget _buildArrearCard(BuildContext context, Map<String, dynamic> bill) {
    final agreement = bill['agreement'] ?? {};
    final tenant = agreement['tenant'] ?? {};
    final house = agreement['house'] ?? {};
    final status = bill['status'] ?? 'unpaid';

    Color statusColor;
    switch (status) {
      case 'overdue':
        statusColor = ThemeConstants.errorRed;
      case 'partial':
        statusColor = ThemeConstants.warningAmber;
      default:
        statusColor = Colors.white54;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: ThemeConstants.glassCardDecoration,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(Icons.warning, color: statusColor, size: 24.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tenant['user']?['name'] ?? tenant['name'] ?? LocalizationService.instance.translate('agreement_step_tenant'),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    LocalizationService.instance.translateWith('house_3', <Object?>[house['house_number'] ?? '']),
                    style: TextStyle(color: Colors.white54, fontSize: 12.sp),
                  ),
                  Text(
                    LocalizationService.instance.translateWith('month_3', <Object?>[bill['month_year'] ?? '']),
                    style: TextStyle(color: Colors.white38, fontSize: 12.sp),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "TSh ${_formatCurrency(TypeHelpers.toDouble(bill['balance']))}",
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: statusColor, fontSize: 10.sp),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double value) {
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1)}M";
    } else if (value >= 1000) {
      return "${(value / 1000).toStringAsFixed(0)}K";
    }
    return value.toStringAsFixed(0);
  }
}
