import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../utils/type_helpers.dart';
import '../../services/localization_service.dart';

class RentalPaymentsScreen extends StatefulWidget {
  const RentalPaymentsScreen({super.key});

  @override
  State<RentalPaymentsScreen> createState() => _RentalPaymentsScreenState();
}

class _RentalPaymentsScreenState extends State<RentalPaymentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RentalProvider>().fetchPayments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rentalProvider = context.watch<RentalProvider>();
    final payments = rentalProvider.payments;

    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: LocalizationService.instance.translate('payments_section'),
      body: rentalProvider.isLoading && payments.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : payments.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.payment, size: 64, color: Colors.white38),
                      SizedBox(height: 16.h),
                      Text(LocalizationService.instance.translate('no_payments'),
                          style: TextStyle(
                              color: Colors.white54, fontSize: 16.sp)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16.w),
                  itemCount: payments.length,
                  itemBuilder: (context, index) {
                    final payment = payments[index];
                    return _buildPaymentCard(context, payment);
                  },
                ),
    );
  }

  Widget _buildPaymentCard(BuildContext context, Map<String, dynamic> payment) {
    final tenant = payment['tenant'] ?? {};
    final bill = payment['bill'] ?? {};
    final house = bill['agreement']?['house'] ?? {};
    final amount = TypeHelpers.toDouble(payment['amount_paid']);

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
                color: ThemeConstants.successGreen.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(Icons.check_circle,
                  color: ThemeConstants.successGreen, size: 24.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tenant['name'] ?? LocalizationService.instance.translate('agreement_step_tenant'),
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
                    payment['payment_date'] ?? '',
                    style: TextStyle(color: Colors.white38, fontSize: 12.sp),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "TSh ${_formatCurrency(amount)}",
                  style: TextStyle(
                      color: ThemeConstants.successGreen,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    payment['payment_method'] ?? 'cash',
                    style: TextStyle(color: Colors.white54, fontSize: 10.sp),
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
