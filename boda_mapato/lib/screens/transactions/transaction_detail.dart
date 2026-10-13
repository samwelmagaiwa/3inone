import 'package:auto_size_text/auto_size_text.dart';
import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../constants/colors.dart";
import "../../constants/strings.dart";
import "../../constants/styles.dart";
import "../../constants/theme_constants.dart";
import "../../models/transaction.dart";
import "../../providers/transaction_provider.dart";
import "../../utils/date_utils.dart";
import "../../widgets/custom_button.dart";
import "../../widgets/custom_card.dart";
import '../../services/localization_service.dart';

class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({
    required this.transaction,
    super.key,
  });
  final Transaction transaction;

  @override
  Widget build(final BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            AppStrings.transactionDetails,
            style: AppStyles.heading2,
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                _showEditDialog(context);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                _showDeleteDialog(context);
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppStyles.spacingM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Amount Card
              CustomCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppStyles.spacingL),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        transaction.type == TransactionType.income
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        size: 48,
                        color: transaction.type == TransactionType.income
                            ? AppColors.success
                            : AppColors.error,
                      ),
                      const SizedBox(height: AppStyles.spacingM),
                      Text(
                        "TSh ${transaction.amount.toStringAsFixed(0)}",
                        style: AppStyles.heading1.copyWith(
                          color: transaction.type == TransactionType.income
                              ? AppColors.success
                              : AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppStyles.spacingS),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppStyles.spacingM,
                          vertical: AppStyles.spacingS,
                        ),
                        decoration: BoxDecoration(
                          color: transaction.type == TransactionType.income
                              ? AppColors.success.withOpacity(0.1)
                              : AppColors.error.withOpacity(0.1),
                          borderRadius:
                              BorderRadius.circular(AppStyles.radiusM(context)),
                        ),
                        child: Text(
                          transaction.type.name,
                          style: AppStyles.bodyMedium.copyWith(
                            color: transaction.type == TransactionType.income
                                ? AppColors.success
                                : AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppStyles.spacingL),

              // Transaction Details
              CustomCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppStyles.spacingM),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        LocalizationService.instance.translate('transaction_details'),
                        style: AppStyles.heading3,
                      ),
                      const SizedBox(height: AppStyles.spacingM),
                      _DetailRow(
                        label: AppStrings.description,
                        value: transaction.description,
                      ),
                      _DetailRow(
                        label: AppStrings.category,
                        value: transaction.category,
                      ),
                      _DetailRow(
                        label: LocalizationService.instance.translate('status'),
                        value: transaction.status.name,
                      ),
                      _DetailRow(
                        label: AppStrings.date,
                        value: AppDateUtils.formatDate(transaction.createdAt),
                      ),
                      _DetailRow(
                        label: AppStrings.time,
                        value: AppDateUtils.formatTime(transaction.createdAt),
                      ),
                      if (transaction.receiptNumber != null)
                        _DetailRow(
                          label: AppStrings.receiptNumber,
                          value: transaction.receiptNumber!,
                        ),
                      if (transaction.customerName != null)
                        _DetailRow(
                          label: AppStrings.customerName,
                          value: transaction.customerName!,
                        ),
                      if (transaction.notes != null)
                        _DetailRow(
                          label: LocalizationService.instance.translate('extra_details'),
                          value: transaction.notes!,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppStyles.spacingL),

              // Action Buttons
              Row(
                children: <Widget>[
                  Expanded(
                    child: CustomButton(
                      text: LocalizationService.instance.translate('edit'),
                      onPressed: () => _showEditDialog(context),
                      backgroundColor: AppColors.info,
                    ),
                  ),
                  const SizedBox(width: AppStyles.spacingM),
                  Expanded(
                    child: CustomButton(
                      text: LocalizationService.instance.translate('delete'),
                      onPressed: () => _showDeleteDialog(context),
                      backgroundColor: AppColors.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  void _showEditDialog(final BuildContext context) {
    // TODO(dev): Implement edit transaction dialog
    ThemeConstants.showInfoSnackBar(context, LocalizationService.instance.translate('transaction_editing_will_be_added_soon'));
  }

  void _showDeleteDialog(final BuildContext context) {
    showDialog(
      context: context,
      builder: (final BuildContext context) => AlertDialog(
        title: AutoSizeText(
          LocalizationService.instance.translate('delete_transaction'),
          maxLines: 1,
          stepGranularity: 0.5,
        ),
        content: Text("${LocalizationService.instance.translate('are_you_sure_you_want_to_7')}?"),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () async {
              try {
                await Provider.of<TransactionProvider>(context, listen: false)
                    .deleteTransaction(transaction.id);

                if (context.mounted) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back to transactions list
                  ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('transaction_deleted'));
                }
              } on Exception catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
                }
              }
            },
            child: Text(
              AppStrings.delete,
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });
  final String label;
  final String value;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppStyles.spacingM),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: AppStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppStyles.bodyMedium,
              ),
            ),
          ],
        ),
      );
}
