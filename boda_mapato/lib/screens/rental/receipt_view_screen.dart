import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../constants/theme_constants.dart';
import '../../services/localization_service.dart';
import '../../providers/rental_provider.dart';

class ReceiptViewScreen extends StatelessWidget { // Can be a payment record or derived from bill

  const ReceiptViewScreen({required this.payment, super.key});
  final dynamic payment;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    return ThemeConstants.buildResponsiveScaffold(
      context,
      title: loc.translate("digital_receipt"),
      actions: [
        if (payment['receipt'] != null)
          IconButton(
            icon: const Icon(Icons.send_rounded),
            tooltip: LocalizationService.instance.translate('send_to_tenant'),
            onPressed: () async {
              final receiptId = payment['receipt']['id'].toString();
              ThemeConstants.showInfoSnackBar(context, LocalizationService.instance.translate('sending_receipt_to_tenant'));
              final success = await context.read<RentalProvider>().dispatchTenantReceipt(receiptId);
              if (success) {
                ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('receipt_sent_successfully'));
              } else {
                ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('failed_to_send_receipt_2'));
              }
            },
          ),
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: () {
             ThemeConstants.showSuccessSnackBar(context, loc.translate("sharing_success"));
          },
        ),
        IconButton(
          icon: const Icon(Icons.print),
          onPressed: () {
             ThemeConstants.showSuccessSnackBar(context, loc.translate("printing_msg"));
          },
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 600;
          
          return Center(
            child: SingleChildScrollView(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isTablet ? 500.w : double.infinity,
                ),
                child: Column(
                  children: [
                    _buildReceiptHeader(context, loc),
                    SizedBox(height: 16.h),
                    _buildReceiptBody(context, payment, loc),
                    SizedBox(height: 24.h),
                    _buildFooter(context, loc),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReceiptHeader(BuildContext context, LocalizationService loc) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: ThemeConstants.successGreen.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_circle, color: ThemeConstants.successGreen, size: 48.w),
        ),
        SizedBox(height: 16.h),
        Text(
          loc.translate("payment_successful"),
          style: TextStyle(
            color: Colors.white,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          "${loc.translate("receipt_prefix")}${payment['id'] ?? 'N/A'}",
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12.sp,
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptBody(BuildContext context, payment, LocalizationService loc) {
    // Extract data safely
    final dateStr = payment['created_at']?.toString() ?? '';
    final formattedDate = dateStr.isNotEmpty 
        ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.tryParse(dateStr) ?? DateTime.now())
        : LocalizationService.instance.translate('today');
        
    final tenantName = payment['tenant']?['name'] ?? payment['bill']?['tenant']?['name'] ?? 'N/A';
    final houseObj = payment['bill']?['agreement']?['house'] ?? payment['bill']?['house'];
    final propertyName = houseObj?['property']?['name'] ?? 'N/A';
    final houseNumber = houseObj?['house_number'] ?? houseObj?['unit_number'] ?? 'N/A';
    final amountPaid = payment['amount_paid'] ?? payment['amount'] ?? '0';

    final rentAmountStr = payment['bill']?['agreement']?['rent_amount']?.toString() ?? payment['bill']?['amount']?.toString() ?? '1';
    final rentAmount = double.tryParse(rentAmountStr) ?? 1;
    final parsedAmountPaid = double.tryParse(amountPaid.toString()) ?? 0;
    
    String monthsCoveredStr = 'N/A';
    if (rentAmount > 0 && parsedAmountPaid > 0) {
      final months = parsedAmountPaid / rentAmount;
      monthsCoveredStr = months.toStringAsFixed(1).replaceAll('.0', '');
    }

    final dueDateStr = payment['bill']?['due_date']?.toString() ?? '';
    final formattedDueDate = dueDateStr.isNotEmpty 
        ? DateFormat('dd MMM yyyy').format(DateTime.tryParse(dueDateStr) ?? DateTime.now())
        : 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: ThemeConstants.bgMid,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            offset: const Offset(8, 8),
            blurRadius: 16,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.04),
            offset: const Offset(-4, -4),
            blurRadius: 12,
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: Column(
          children: [
            Container(
              height: 4.h,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [ThemeConstants.primaryOrange, ThemeConstants.successGreen],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                children: [
                  _buildReceiptRow(loc.translate("date"), formattedDate),
                  _buildReceiptRow(loc.translate("tenant"), tenantName.toString()),
                  _buildReceiptRow(loc.translate("property"), propertyName.toString()),
                  _buildReceiptRow("${loc.translate("house")} #", houseNumber.toString()),
                  _buildReceiptRow(loc.translate("months_covered"), monthsCoveredStr),
                  _buildReceiptRow(loc.translate("due_date"), formattedDueDate),
                  SizedBox(height: 12.h),
                  _buildDashedSeparator(),
                  SizedBox(height: 12.h),
                  _buildReceiptRow(loc.translate("payment_method"), (payment['payment_method'] ?? 'Cash').toString().toUpperCase()),
                  _buildReceiptRow(loc.translate("amount_paid"), "Tsh $amountPaid", isBold: true, color: ThemeConstants.successGreen),
                  SizedBox(height: 12.h),
                  _buildDashedSeparator(),
                  SizedBox(height: 12.h),
                  _buildReceiptRow(loc.translate("balance"), "Tsh ${payment['bill']?['balance'] ?? '0'}", color: ThemeConstants.errorRed),
                  SizedBox(height: 24.h),
                  
                  // Premium QR Code with embedded text
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: ThemeConstants.primaryOrange.withOpacity(0.2),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        QrImageView(
                          data: payment['receipt']?['receipt_number']?.toString() ?? payment['id']?.toString() ?? 'All on one',
                          version: QrVersions.auto,
                          size: 150.w,
                          backgroundColor: Colors.white,
                          foregroundColor: ThemeConstants.bgTop,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                          decoration: BoxDecoration(
                            color: ThemeConstants.bgTop,
                            borderRadius: BorderRadius.circular(6.r),
                            border: Border.all(color: ThemeConstants.primaryOrange, width: 1.5),
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1)
                            ],
                          ),
                          child: Text(
                            'All on one',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 10.sp,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildDashedSeparator() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        final dashWidth = 5.0.w;
        final dashHeight = 1.5.h;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2)),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isBold = false, Color color = Colors.white}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13.sp,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, LocalizationService loc) {
    return Column(
      children: [
        Text(
          loc.translate("thank_you_payment"),
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12.sp,
            fontStyle: FontStyle.italic,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          loc.translate("mapato_rental_service"),
          style: TextStyle(
            color: ThemeConstants.footerBarColor,
            fontSize: 10.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
