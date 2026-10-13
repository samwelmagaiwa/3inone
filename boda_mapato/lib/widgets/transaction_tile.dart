import "package:flutter/material.dart";
import "../constants/colors.dart";
import "../constants/styles.dart";
import "../models/transaction.dart";
import "../utils/date_utils.dart";
import "../utils/responsive_utils.dart";
import "responsive_wrapper.dart";
import '../services/localization_service.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    required this.transaction,
    super.key,
    this.showDate = false,
    this.onTap,
    this.onLongPress,
  });
  final Transaction transaction;
  final bool showDate;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(final BuildContext context) {
    final double iconSize = ResponsiveUtils.getResponsiveIconSize(context, 48);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ResponsiveWrapper(
        child: ResponsiveRow(
          spacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
          children: <Widget>[
            // Transaction Type Icon
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: _getTransactionColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(
                  ResponsiveUtils.getResponsiveBorderRadius(context, 8),
                ),
              ),
              child: Icon(
                _getTransactionIcon(),
                color: _getTransactionColor(),
                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
              ),
            ),

            // Transaction Details
            Expanded(
              child: ResponsiveColumn(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: ResponsiveUtils.getResponsiveSpacing(context, 4),
                children: <Widget>[
                  Text(
                    transaction.description,
                    style: AppStyles.bodyMediumResponsive(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Wrap(
                    children: <Widget>[
                      Text(
                        transaction.category,
                        style: AppStyles.bodySmallResponsive(context).copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (showDate) ...<Widget>[
                        Text(
                          " • ",
                          style:
                              AppStyles.bodySmallResponsive(context).copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          AppDateUtils.formatDate(transaction.createdAt),
                          style:
                              AppStyles.bodySmallResponsive(context).copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (transaction.status != TransactionStatus.completed)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            ResponsiveUtils.getResponsiveSpacing(context, 8),
                        vertical:
                            ResponsiveUtils.getResponsiveSpacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor().withOpacity(0.1),
                        borderRadius: BorderRadius.circular(
                          ResponsiveUtils.getResponsiveBorderRadius(context, 4),
                        ),
                      ),
                      child: Text(
                        transaction.status.name,
                        style: AppStyles.bodySmallResponsive(context).copyWith(
                          color: _getStatusColor(),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Amount and Time
            ResponsiveColumn(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: ResponsiveUtils.getResponsiveSpacing(context, 4),
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "${transaction.type == TransactionType.income ? "+" : "-"}TSh ${transaction.amount.toStringAsFixed(0)}",
                    style: AppStyles.bodyMediumResponsive(context).copyWith(
                      color: _getTransactionColor(),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  AppDateUtils.formatTime(transaction.createdAt),
                  style: AppStyles.bodySmallResponsive(context).copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getTransactionColor() {
    switch (transaction.type) {
      case TransactionType.income:
        return AppColors.success;
      case TransactionType.expense:
        return AppColors.error;
    }
  }

  IconData _getTransactionIcon() {
    switch (transaction.type) {
      case TransactionType.income:
        return Icons.arrow_downward;
      case TransactionType.expense:
        return Icons.arrow_upward;
    }
  }

  Color _getStatusColor() {
    switch (transaction.status) {
      case TransactionStatus.completed:
        return AppColors.success;
      case TransactionStatus.pending:
        return AppColors.warning;
      case TransactionStatus.cancelled:
        return AppColors.error;
    }
  }
}

class TransactionSummaryTile extends StatelessWidget {
  const TransactionSummaryTile({
    required this.title,
    required this.amount,
    required this.count,
    required this.color,
    required this.icon,
    super.key,
    this.onTap,
  });
  final String title;
  final double amount;
  final int count;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) {
    final double iconSize = ResponsiveUtils.getResponsiveIconSize(context, 48);

    return InkWell(
      onTap: onTap,
      child: ResponsiveWrapper(
        child: ResponsiveRow(
          spacing: ResponsiveUtils.getResponsiveSpacing(context, 16),
          children: <Widget>[
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(
                  ResponsiveUtils.getResponsiveBorderRadius(context, 8),
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: ResponsiveUtils.getResponsiveIconSize(context, 24),
              ),
            ),
            Expanded(
              child: ResponsiveColumn(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: ResponsiveUtils.getResponsiveSpacing(context, 4),
                children: <Widget>[
                  Text(
                    title,
                    style: AppStyles.bodyMediumResponsive(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    LocalizationService.instance.translateWith('transactions_2', <Object?>[count]),
                    style: AppStyles.bodySmallResponsive(context).copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                "TSh ${amount.toStringAsFixed(0)}",
                style: AppStyles.bodyLargeResponsive(context).copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionListHeader extends StatelessWidget {
  const TransactionListHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(final BuildContext context) => Container(
        padding: ResponsiveUtils.getResponsiveCardPadding(context),
        color: AppColors.background,
        child: ResponsiveRow(
          children: <Widget>[
            Expanded(
              child: ResponsiveColumn(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: ResponsiveUtils.getResponsiveSpacing(context, 4),
                children: <Widget>[
                  Text(
                    title,
                    style: AppStyles.bodyMediumResponsive(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppStyles.bodySmallResponsive(context).copyWith(
                        color: AppColors.textHint,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}
