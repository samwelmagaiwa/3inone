import "package:flutter/material.dart";
import "../../constants/colors.dart";
import "../../constants/styles.dart";
import "../../models/transaction.dart";
import "../../utils/date_utils.dart";
import "../../utils/type_helpers.dart";
import '../../services/localization_service.dart';

class TransactionSummaryCard extends StatelessWidget {
  const TransactionSummaryCard({
    required this.transactions,
    required this.title,
    required this.icon,
    required this.color,
    super.key,
  });
  final List<Transaction> transactions;
  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(final BuildContext context) {
    final double totalAmount = transactions.fold<double>(
      0,
      (final double sum, final Transaction transaction) =>
          sum + transaction.amount,
    );

    return Container(
      padding: const EdgeInsets.all(AppStyles.spacingM),
      decoration: AppStyles.cardDecoration(context).copyWith(
        color: color.withOpacity(0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 24),
              const SizedBox(width: AppStyles.spacingS),
              Text(
                title,
                style: AppStyles.bodyMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppStyles.spacingM),
          Text(
            "TSh ${totalAmount.toStringAsFixed(0)}",
            style: AppStyles.heading2.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppStyles.spacingS),
          Text(
            LocalizationService.instance.translateWith('transactions_2', <Object?>[transactions.length]),
            style: AppStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionFilterChips extends StatelessWidget {
  const TransactionFilterChips({
    required this.selectedFilter,
    required this.onFilterChanged,
    super.key,
  });
  final String selectedFilter;
  final Function(String) onFilterChanged;

  @override
  Widget build(final BuildContext context) {
    // Use type-safe filter options to prevent InvalidType errors
    final List<FilterOption> filters = CommonFilters.transactionFilters;

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (final BuildContext context, final int index) {
          final FilterOption filter = filters[index];
          final bool isSelected = selectedFilter == filter.key;

          return Padding(
            padding: const EdgeInsets.only(right: AppStyles.spacingS),
            child: FilterChip(
              label: Text(filter.label),
              selected: isSelected,
              onSelected: (final bool selected) {
                if (selected) {
                  onFilterChanged(filter.key);
                }
              },
              selectedColor: AppColors.primary.withOpacity(0.2),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }
}

class TransactionChart extends StatelessWidget {
  const TransactionChart({
    required this.transactions,
    required this.period,
    super.key,
  });
  final List<Transaction> transactions;
  final String period;

  @override
  Widget build(final BuildContext context) {
    // Group transactions by date
    final Map<String, double> groupedTransactions = _groupTransactionsByDate();

    return Container(
      height: 200,
      padding: const EdgeInsets.all(AppStyles.spacingM),
      decoration: AppStyles.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            LocalizationService.instance.translateWith('income_chart', <Object?>[period]),
            style: AppStyles.heading3,
          ),
          const SizedBox(height: AppStyles.spacingM),
          Expanded(
            child: groupedTransactions.isEmpty
                ? Center(
                    child: Text(
                      LocalizationService.instance.translate('no_data_to_show'),
                      style: AppStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : _buildChart(groupedTransactions),
          ),
        ],
      ),
    );
  }

  Map<String, double> _groupTransactionsByDate() {
    final Map<String, double> grouped = <String, double>{};

    for (final Transaction transaction in transactions) {
      if (transaction.type == TransactionType.income) {
        final String dateKey = AppDateUtils.formatDate(transaction.createdAt);
        grouped[dateKey] = (grouped[dateKey] ?? 0) + transaction.amount;
      }
    }

    return grouped;
  }

  Widget _buildChart(final Map<String, double> data) {
    if (data.isEmpty) {
      return Center(
        child: Text(LocalizationService.instance.translate('no_data_to_show')),
      );
    }

    final double maxAmount =
        data.values.reduce((final double a, final double b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: data.entries.map((final MapEntry<String, double> entry) {
        final double height = (entry.value / maxAmount) * 120;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: AppStyles.spacingS),
                Text(
                  entry.key.split("/").last, // Show only day
                  style: AppStyles.bodySmall,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class TransactionStatusBadge extends StatelessWidget {
  const TransactionStatusBadge({
    required this.status,
    super.key,
  });
  final TransactionStatus status;

  @override
  Widget build(final BuildContext context) {
    Color backgroundColor;
    Color textColor;

    switch (status) {
      case TransactionStatus.completed:
        backgroundColor = AppColors.success.withOpacity(0.1);
        textColor = AppColors.success;
      case TransactionStatus.pending:
        backgroundColor = AppColors.warning.withOpacity(0.1);
        textColor = AppColors.warning;
      case TransactionStatus.cancelled:
        backgroundColor = AppColors.error.withOpacity(0.1);
        textColor = AppColors.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppStyles.spacingS,
        vertical: AppStyles.spacingXS,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppStyles.radiusS(context)),
      ),
      child: Text(
        status.name,
        style: AppStyles.bodySmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class TransactionTypeIcon extends StatelessWidget {
  const TransactionTypeIcon({
    required this.type,
    super.key,
    this.size = 24,
  });
  final TransactionType type;
  final double size;

  @override
  Widget build(final BuildContext context) => Container(
        width: size + 16,
        height: size + 16,
        decoration: BoxDecoration(
          color: type == TransactionType.income
              ? AppColors.success.withOpacity(0.1)
              : AppColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular((size + 16) / 2),
        ),
        child: Icon(
          type == TransactionType.income
              ? Icons.arrow_downward
              : Icons.arrow_upward,
          size: size,
          color: type == TransactionType.income
              ? AppColors.success
              : AppColors.error,
        ),
      );
}
