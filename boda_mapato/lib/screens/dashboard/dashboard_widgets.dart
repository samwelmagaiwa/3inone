import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../constants/colors.dart";
import "../../constants/strings.dart";
import "../../constants/styles.dart";
import "../../models/device.dart";
import "../../models/transaction.dart";
import "../../providers/device_provider.dart";
import "../../providers/transaction_provider.dart";
import "../../widgets/custom_card.dart";
import "../../widgets/transaction_tile.dart";
import '../../services/localization_service.dart';

class RevenueCardsSection extends StatelessWidget {
  const RevenueCardsSection({super.key});

  @override
  Widget build(final BuildContext context) => Consumer<TransactionProvider>(
        builder: (
          final BuildContext context,
          final TransactionProvider transactionProvider,
          final Widget? child,
        ) {
          final Map<String, double> stats =
              transactionProvider.getRevenueStats();

          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // Use single column layout for very small screens
              if (constraints.maxWidth < 400) {
                return Column(
                  children: <Widget>[
                    _RevenueCard(
                      title: AppStrings.todayRevenue,
                      amount: stats["today"] ?? 0,
                      icon: Icons.today,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: AppStyles.spacingS),
                    _RevenueCard(
                      title: AppStrings.weeklyRevenue,
                      amount: stats["week"] ?? 0,
                      icon: Icons.date_range,
                      color: AppColors.info,
                    ),
                    const SizedBox(height: AppStyles.spacingS),
                    _RevenueCard(
                      title: AppStrings.monthlyRevenue,
                      amount: stats["month"] ?? 0,
                      icon: Icons.calendar_month,
                      color: AppColors.warning,
                    ),
                    const SizedBox(height: AppStyles.spacingS),
                    _RevenueCard(
                      title: AppStrings.totalRevenue,
                      amount: stats["total"] ?? 0,
                      icon: Icons.account_balance_wallet,
                      color: AppColors.primary,
                    ),
                  ],
                );
              }

              // Use 2x2 grid for normal screens
              return Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _RevenueCard(
                          title: AppStrings.todayRevenue,
                          amount: stats["today"] ?? 0,
                          icon: Icons.today,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: AppStyles.spacingM),
                      Expanded(
                        child: _RevenueCard(
                          title: AppStrings.weeklyRevenue,
                          amount: stats["week"] ?? 0,
                          icon: Icons.date_range,
                          color: AppColors.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppStyles.spacingM),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _RevenueCard(
                          title: AppStrings.monthlyRevenue,
                          amount: stats["month"] ?? 0,
                          icon: Icons.calendar_month,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: AppStyles.spacingM),
                      Expanded(
                        child: _RevenueCard(
                          title: AppStrings.totalRevenue,
                          amount: stats["total"] ?? 0,
                          icon: Icons.account_balance_wallet,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });
  final String title;
  final double amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(final BuildContext context) => CustomCard(
        child: Padding(
          padding: const EdgeInsets.all(AppStyles.spacingM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    icon,
                    color: color,
                    size: 20,
                  ),
                  const SizedBox(width: AppStyles.spacingS),
                  Expanded(
                    child: Text(
                      title,
                      style: AppStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppStyles.spacingS),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "TSh ${amount.toStringAsFixed(0)}",
                    style: AppStyles.heading3.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class RecentTransactionsSection extends StatelessWidget {
  const RecentTransactionsSection({super.key});

  @override
  Widget build(final BuildContext context) => Consumer<TransactionProvider>(
        builder: (
          final BuildContext context,
          final TransactionProvider transactionProvider,
          final Widget? child,
        ) {
          final List<Transaction> recentTransactions =
              transactionProvider.getRecentTransactions(5);

          if (recentTransactions.isEmpty) {
            return CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(AppStyles.spacingL),
                child: Column(
                  children: <Widget>[
                    const Icon(
                      Icons.receipt_long,
                      size: 48,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    Text(
                      LocalizationService.instance.translate('no_recent_transactions'),
                      style: AppStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return CustomCard(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 300, // Limit height to prevent overflow
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // If there are many transactions, make the list scrollable
                  if (recentTransactions.length > 4)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        itemCount: recentTransactions.length,
                        itemBuilder: (BuildContext context, int index) =>
                            TransactionTile(
                          transaction: recentTransactions[index],
                          showDate: true,
                        ),
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(
                          height: 1,
                          indent: AppStyles.spacingM,
                          endIndent: AppStyles.spacingM,
                        ),
                      ),
                    )
                  else
                    // For few transactions, use regular column
                    ...recentTransactions.asMap().entries.expand(
                          (MapEntry<int, Transaction> entry) =>
                              <StatelessWidget>[
                            TransactionTile(
                              transaction: entry.value,
                              showDate: true,
                            ),
                            if (entry.key < recentTransactions.length - 1)
                              const Divider(
                                height: 1,
                                indent: AppStyles.spacingM,
                                endIndent: AppStyles.spacingM,
                              ),
                          ],
                        ),
                ],
              ),
            ),
          );
        },
      );
}

class DeviceStatusSection extends StatelessWidget {
  const DeviceStatusSection({super.key});

  @override
  Widget build(final BuildContext context) => Consumer<DeviceProvider>(
        builder: (
          final BuildContext context,
          final DeviceProvider deviceProvider,
          final Widget? child,
        ) {
          final List<Device> devices = deviceProvider.devices;

          if (devices.isEmpty) {
            return CustomCard(
              child: Padding(
                padding: const EdgeInsets.all(AppStyles.spacingL),
                child: Column(
                  children: <Widget>[
                    const Icon(
                      Icons.directions_car,
                      size: 48,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(height: AppStyles.spacingM),
                    Text(
                      LocalizationService.instance.translate('no_registered_vehicles'),
                      style: AppStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return CustomCard(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 250, // Limit height to prevent overflow
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // If there are many devices, make the list scrollable
                  if (devices.length > 3)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        itemCount:
                            devices.take(5).length, // Limit to 5 devices max
                        itemBuilder: (BuildContext context, int index) =>
                            _DeviceStatusTile(
                          device: devices[index],
                        ),
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(
                          height: 1,
                          indent: AppStyles.spacingM,
                          endIndent: AppStyles.spacingM,
                        ),
                      ),
                    )
                  else
                    // For few devices, use regular column
                    ...devices.take(3).toList().asMap().entries.expand(
                          (MapEntry<int, Device> entry) => <StatelessWidget>[
                            _DeviceStatusTile(device: entry.value),
                            if (entry.key < devices.take(3).length - 1)
                              const Divider(
                                height: 1,
                                indent: AppStyles.spacingM,
                                endIndent: AppStyles.spacingM,
                              ),
                          ],
                        ),
                ],
              ),
            ),
          );
        },
      );
}

class _DeviceStatusTile extends StatelessWidget {
  const _DeviceStatusTile({required this.device});
  final Device device;

  @override
  Widget build(final BuildContext context) => Consumer<TransactionProvider>(
        builder: (
          final BuildContext context,
          final TransactionProvider transactionProvider,
          final Widget? child,
        ) {
          final double todayRevenue =
              transactionProvider.getDeviceRevenueToday(device.id);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppStyles.spacingM,
              vertical: AppStyles.spacingS,
            ),
            leading: CircleAvatar(
              backgroundColor: _getDeviceColor(device.type),
              radius: 20,
              child: Text(
                device.type.icon,
                style: const TextStyle(fontSize: 18),
              ),
            ),
            title: Text(
              device.name,
              style: AppStyles.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              "${device.plateNumber} • ${device.type.name}",
              style: AppStyles.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: SizedBox(
              width: 80, // Fixed width to prevent overflow
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "TSh ${todayRevenue.toStringAsFixed(0)}",
                      style: AppStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  Text(
                    LocalizationService.instance.translate('today'),
                    style: AppStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Color _getDeviceColor(final DeviceType type) {
    switch (type) {
      case DeviceType.bajaji:
        return AppColors.bajaji;
      case DeviceType.pikipiki:
        return AppColors.pikipiki;
      case DeviceType.gari:
        return AppColors.gari;
    }
  }
}
