import "package:flutter/material.dart";
import "package:flutter_screenutil/flutter_screenutil.dart";
import "../constants/colors.dart";
import "../constants/styles.dart";
import "../utils/responsive_utils.dart";
import "responsive_wrapper.dart";
import '../services/localization_service.dart';

class ReceiptTile extends StatelessWidget {
  const ReceiptTile({
    required this.receiptNumber,
    required this.customerName,
    required this.amount,
    required this.date,
    required this.serviceType,
    super.key,
    this.onTap,
    this.onPrint,
    this.onShare,
  });
  final String receiptNumber;
  final String customerName;
  final double amount;
  final DateTime date;
  final String serviceType;
  final VoidCallback? onTap;
  final VoidCallback? onPrint;
  final VoidCallback? onShare;

  @override
  Widget build(final BuildContext context) {
    final double iconSize = ResponsiveUtils.getResponsiveIconSize(context, 48);

    return InkWell(
      onTap: onTap,
      child: ResponsiveContainer(
        child: ResponsiveColumn(
          spacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
          children: <Widget>[
            ResponsiveRow(
              spacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
              children: <Widget>[
                // Receipt Icon
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                      ResponsiveUtils.getResponsiveBorderRadius(context, 8),
                    ),
                  ),
                  child: Icon(
                    Icons.receipt_long,
                    color: AppColors.info,
                    size: ResponsiveUtils.getResponsiveIconSize(context, 24),
                  ),
                ),

                // Receipt Details
                Expanded(
                  child: ResponsiveColumn(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: ResponsiveUtils.getResponsiveSpacing(context, 4),
                    children: <Widget>[
                      Text(
                        receiptNumber,
                        style: AppStyles.bodyMediumResponsive(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        customerName,
                        style: AppStyles.bodySmallResponsive(context).copyWith(
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        serviceType,
                        style: AppStyles.bodySmallResponsive(context).copyWith(
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),

                // Amount and Date
                ResponsiveColumn(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: ResponsiveUtils.getResponsiveSpacing(context, 4),
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        "TSh ${amount.toStringAsFixed(0)}",
                        style: AppStyles.bodyMediumResponsive(context).copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      "${date.day}/${date.month}/${date.year}",
                      style: AppStyles.bodySmallResponsive(context).copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Action Buttons
            if (onPrint != null || onShare != null)
              ResponsiveRow(
                spacing: ResponsiveUtils.getResponsiveSpacing(context, 8),
                children: <Widget>[
                  if (onPrint != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPrint,
                        icon: Icon(
                          Icons.print,
                          size: ResponsiveUtils.getResponsiveIconSize(
                            context,
                            16,
                          ),
                        ),
                        label: Text(
                          LocalizationService.instance.translate('print'),
                          style: AppStyles.bodySmallResponsive(context),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side:
                              BorderSide(color: AppColors.primary, width: 1.w),
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveUtils.getResponsiveSpacing(
                              context,
                              12,
                            ),
                            vertical: ResponsiveUtils.getResponsiveSpacing(
                              context,
                              8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (onShare != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onShare,
                        icon: Icon(
                          Icons.share,
                          size: ResponsiveUtils.getResponsiveIconSize(
                            context,
                            16,
                          ),
                        ),
                        label: Text(
                          LocalizationService.instance.translate('share'),
                          style: AppStyles.bodySmallResponsive(context),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          side: BorderSide(
                            color: AppColors.secondary,
                            width: 1.w,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveUtils.getResponsiveSpacing(
                              context,
                              12,
                            ),
                            vertical: ResponsiveUtils.getResponsiveSpacing(
                              context,
                              8,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class ReceiptSummaryCard extends StatelessWidget {
  const ReceiptSummaryCard({
    required this.title,
    required this.count,
    required this.totalAmount,
    required this.icon,
    required this.color,
    super.key,
    this.onTap,
  });
  final String title;
  final int count;
  final double totalAmount;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => InkWell(
        onTap: onTap,
        child: ResponsiveContainer(
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(
              ResponsiveUtils.getResponsiveBorderRadius(context, 12),
            ),
            border: Border.all(color: color.withOpacity(0.3), width: 1.w),
          ),
          child: ResponsiveColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
            children: <Widget>[
              ResponsiveRow(
                spacing: ResponsiveUtils.getResponsiveSpacing(context, 8),
                children: <Widget>[
                  Icon(
                    icon,
                    color: color,
                    size: ResponsiveUtils.getResponsiveIconSize(context, 24),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: AppStyles.bodyMediumResponsive(context).copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  count.toString(),
                  style: AppStyles.heading2Responsive(context).copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  "TSh ${totalAmount.toStringAsFixed(0)}",
                  style: AppStyles.bodyMediumResponsive(context).copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class ReceiptPreviewCard extends StatelessWidget {
  const ReceiptPreviewCard({
    required this.receiptNumber,
    required this.customerName,
    required this.amount,
    required this.serviceType,
    required this.date,
    super.key,
    this.notes,
  });
  final String receiptNumber;
  final String customerName;
  final double amount;
  final String serviceType;
  final DateTime date;
  final String? notes;

  @override
  Widget build(final BuildContext context) => ResponsiveContainer(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(
            ResponsiveUtils.getResponsiveBorderRadius(context, 8),
          ),
          border: Border.all(
            color: AppColors.textHint.withOpacity(0.3),
            width: 1.w,
          ),
        ),
        child: ResponsiveColumn(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
          children: <Widget>[
            // Header
            Center(
              child: Text(
                "3 IN ONE",
                style: AppStyles.heading3Responsive(context),
              ),
            ),
            Center(
              child: Text(
                LocalizationService.instance.translate('service_receipt'),
                style: AppStyles.bodySmallResponsive(context),
              ),
            ),

            const Divider(),

            // Receipt Details
            _ReceiptRow("${LocalizationService.instance.translate('receipt_number_2')}:", receiptNumber),
            _ReceiptRow("${LocalizationService.instance.translate('date')}:", "${date.day}/${date.month}/${date.year}"),
            _ReceiptRow(
              "${LocalizationService.instance.translate('time_2')}:",
              "${date.hour}:${date.minute.toString().padLeft(2, "0")}",
            ),

            const Divider(),

            // Customer & Service Details
            _ReceiptRow("${LocalizationService.instance.translate('customer')}:", customerName),
            _ReceiptRow("${LocalizationService.instance.translate('service_label')}:", serviceType),
            if (notes != null && notes!.isNotEmpty)
              _ReceiptRow("${LocalizationService.instance.translate('description')}:", notes!),

            const Divider(),

            // Amount
            ResponsiveRow(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  "${LocalizationService.instance.translate('total').toUpperCase()}:",
                  style: AppStyles.heading3Responsive(context),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "TSh ${amount.toStringAsFixed(0)}",
                    style: AppStyles.heading3Responsive(context).copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(),

            // Footer
            Center(
              child: Text(
                "${LocalizationService.instance.translate('thank_you_for_using_our_services')}!",
                style: AppStyles.bodySmallResponsive(context),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: EdgeInsets.only(
          bottom: ResponsiveUtils.getResponsiveSpacing(context, 8),
        ),
        child: ResponsiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: ResponsiveUtils.getResponsiveSpacing(context, 100),
              child: Text(
                label,
                style: AppStyles.bodySmallResponsive(context).copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppStyles.bodySmallResponsive(context),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      );
}
