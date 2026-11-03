import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_reminder.dart';
import '../../providers/inventory_provider.dart';
import '../widgets/glow_list_card.dart';
import '../widgets/inventory_widgets.dart';

/// Simple reminders: low stock and payments coming due. For the fuller list
/// — near-expiry, over-limit customers, overdue invoices — see the Alerts
/// screen instead.
class InventoryRemindersScreen extends StatefulWidget {
  const InventoryRemindersScreen({super.key});

  @override
  State<InventoryRemindersScreen> createState() =>
      _InventoryRemindersScreenState();
}

class _InventoryRemindersScreenState extends State<InventoryRemindersScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loading = context.read<InventoryProvider>().reminders.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<InventoryProvider>().fetchReminders();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final List<InvReminder> reminders = inv.reminders;

    return SafeArea(
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white70))
          : RefreshIndicator(
              onRefresh: _load,
              backgroundColor: Colors.white,
              color: ThemeConstants.primaryBlue,
              child: reminders.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: <Widget>[
                        SizedBox(height: 80.h),
                        InvEmptyState(
                          icon: Icons.notifications_none_rounded,
                          message: loc.translate('no_reminders'),
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: EdgeInsets.all(12.w),
                      children: <Widget>[
                        // The reminders are ONE card of rows, each divided from the next by the glowing line.
                        GlowListCard(
                          dividerKey: 'reminder_divider',
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                          children: <Widget>[
                            for (final InvReminder r in reminders)
                              _ReminderCard(
                                reminder: r,
                                onMarkDone: () => _markDone(r.id),
                                onSnooze: () => _snooze(r.id),
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
    );
  }

  Future<void> _markDone(int id) async {
    final LocalizationService loc = LocalizationService.instance;
    await context.read<InventoryProvider>().markReminderDone(id);
    if (mounted) {
      ThemeConstants.showSuccessSnackBar(context, loc.translate('done'));
    }
  }

  Future<void> _snooze(int id) async {
    final LocalizationService loc = LocalizationService.instance;
    await context
        .read<InventoryProvider>()
        .snoozeReminder(id, minutes: 60 * 24);
    if (mounted) {
      ThemeConstants.showSuccessSnackBar(
          context, loc.translate('snoozed_a_day'));
    }
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.onMarkDone,
    required this.onSnooze,
  });

  final InvReminder reminder;
  final VoidCallback onMarkDone;
  final VoidCallback onSnooze;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final bool isLowStock = reminder.type == 'low_stock';
    final bool isDone = reminder.status == InvReminderStatus.done;

    final (Color color, String statusLabel) = switch (reminder.status) {
      InvReminderStatus.done => (
          ThemeConstants.successGreen,
          loc.translate('done')
        ),
      InvReminderStatus.snoozed => (
          ThemeConstants.warningAmber,
          loc.translate('snoozed')
        ),
      InvReminderStatus.open => (
          ThemeConstants.primaryCyan,
          loc.translate('open')
        ),
    };

    return Container(
      key: ValueKey<String>('reminder_${reminder.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34.w,
                height: 34.w,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  isLowStock
                      ? Icons.inventory_2_outlined
                      : Icons.payments_outlined,
                  color: color,
                  size: 18.sp,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AutoSizeText(
                      reminder.title,
                      maxLines: 1,
                      minFontSize: 11,
                      overflow: TextOverflow.ellipsis,
                      style: ThemeConstants.bodyStyle
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (reminder.description.isNotEmpty) ...<Widget>[
                      SizedBox(height: 2.h),
                      AutoSizeText(
                        reminder.description,
                        maxLines: 2,
                        minFontSize: 9,
                        overflow: TextOverflow.ellipsis,
                        style: ThemeConstants.captionStyle,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              InvBadge(label: statusLabel, color: color),
            ],
          ),
          if (!isDone) ...<Widget>[
            SizedBox(height: 10.h),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: onSnooze,
                    child: AutoSizeText(
                      loc.translate('snooze_a_day'),
                      maxLines: 1,
                      minFontSize: 9,
                      style: ThemeConstants.captionStyle,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.successGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: onMarkDone,
                    child: AutoSizeText(
                      loc.translate('mark_done'),
                      maxLines: 1,
                      minFontSize: 9,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
