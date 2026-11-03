import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_reminder.dart';
import '../../providers/inventory_provider.dart';
import '../../../../providers/auth_provider.dart';
import '../../models/inv_reminder.dart' show InvReminderStatus;
import '../../services/daily_voice.dart';
import '../../services/reminder_voice.dart';
import '../widgets/glow_list_card.dart';
import '../widgets/inv_action_button.dart';
import '../widgets/inventory_widgets.dart';

/// Simple reminders: low stock and payments coming due. For the fuller list
/// — near-expiry, over-limit customers, overdue invoices — see the Alerts
/// screen instead.
class InventoryRemindersScreen extends StatefulWidget {
  const InventoryRemindersScreen({super.key, this.speech});

  /// The speaker (the phone's own voice); a test gives its own.
  final SpeechPort? speech;

  @override
  State<InventoryRemindersScreen> createState() =>
      _InventoryRemindersScreenState();
}

class _InventoryRemindersScreenState extends State<InventoryRemindersScreen> {
  bool _loading = false;
  // The phone's own reader is shared with the one that reads when the app opens; a test brings its own.
  late final ReminderVoice _voice = widget.speech == null ? ReminderVoice.shared : ReminderVoice(speech: widget.speech);
  bool _auto = true;

  @override
  void dispose() {
    if (widget.speech != null) {
      _voice.stop();
      _voice.dispose();
    }
    super.dispose();
  }

  /// The owner's name for the greeting ('' when it is not known).
  String _owner() {
    try {
      return context.read<AuthProvider>().userDisplayName;
    } on ProviderNotFoundException {
      return '';
    }
  }

  /// Reads the given reminders aloud in the chosen language, or says why it cannot.
  Future<void> _speak(final List<InvReminder> list) async {
    final LocalizationService loc = LocalizationService.instance;
    final VoiceResult r = await _voice.read(list, owner: _owner(), sw: loc.isSwahili);
    if (!mounted) return;
    if (r == VoiceResult.noVoice) {
      ThemeConstants.showWarningSnackBar(context, loc.translate('voice_missing'));
    } else if (r == VoiceResult.nothingToRead) {
      ThemeConstants.showWarningSnackBar(context, loc.translate('voice_nothing'));
    }
  }

  @override
  void initState() {
    super.initState();
    _loading = context.read<InventoryProvider>().reminders.isEmpty;
    VoiceSettings.autoRead().then((bool on) {
      if (mounted) setState(() => _auto = on);
    });
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
    // Open reminders first, then the ones put away for a while, then the done ones.
    final List<InvReminder> reminders = List<InvReminder>.of(inv.reminders)..sort((InvReminder a, InvReminder b) => a.status.index.compareTo(b.status.index));

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
                        // Reading by itself when the app is opened (once a day): on until it is switched off here.
                        Container(
                          margin: EdgeInsets.only(bottom: 10.h),
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14.r), border: Border.all(color: Colors.white24)),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.record_voice_over_rounded, color: const Color(0xFF3B82F6), size: 20.sp),
                              SizedBox(width: 10.w),
                              Expanded(child: Text(loc.translate('voice_auto_read'), style: ThemeConstants.captionStyle.copyWith(color: Colors.white))),
                              Switch(
                                key: const ValueKey<String>('voice_auto_switch'),
                                value: _auto,
                                onChanged: (bool v) {
                                  setState(() => _auto = v);
                                  VoiceSettings.setAutoRead(v);
                                },
                              ),
                            ],
                          ),
                        ),
                        // Reads every debt reminder aloud, one after the other: "Hello ..., customer ... owes ... shillings ...".
                        if (reminders.any(canSpeak))
                          Padding(
                            padding: EdgeInsets.only(bottom: 10.h),
                            child: ListenableBuilder(
                              listenable: _voice,
                              builder: (BuildContext context, Widget? _) => InvActionButton(
                                key: const ValueKey<String>('read_all_aloud'),
                                label: _voice.speaking ? loc.translate('stop_reading') : loc.translate('read_aloud'),
                                icon: _voice.speaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                                color: _voice.speaking ? ThemeConstants.errorRed : const Color(0xFF3B82F6),
                                arrow: false,
                                onPressed: _voice.speaking ? _voice.stop : () => _speak(reminders),
                              ),
                            ),
                          ),
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
                                onSpeak: canSpeak(r) ? () => _speak(<InvReminder>[r]) : null,
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
    // A reminder is closed for good: ask first, so a stray tap does not lose it.
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(loc.translate('mark_done_question'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)),
        content: Text(loc.translate('mark_done_explain'), style: ThemeConstants.captionStyle),
        actions: <Widget>[
          TextButton(key: const ValueKey<String>('mark_done_no'), onPressed: () => Navigator.pop(ctx, false), child: Text(loc.translate('no'))),
          ElevatedButton(
            key: const ValueKey<String>('mark_done_yes'),
            style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.successGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.translate('yes'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
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

/// "04/11 10:00": the day and the time a snoozed reminder comes back.
String _when(final DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.onMarkDone,
    required this.onSnooze,
    this.onSpeak,
  });

  final InvReminder reminder;
  final VoidCallback onMarkDone;
  final VoidCallback onSnooze;

  /// Reads this reminder aloud (null when it has no customer and amount to read).
  final VoidCallback? onSpeak;

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
              if (onSpeak != null)
                IconButton(
                  key: ValueKey<String>('voice_${reminder.id}'),
                  visualDensity: VisualDensity.compact,
                  tooltip: loc.translate('read_aloud'),
                  icon: Icon(Icons.volume_up_rounded, color: const Color(0xFF3B82F6), size: 22.sp),
                  onPressed: onSpeak,
                ),
              InvBadge(label: statusLabel, color: color),
            ],
          ),
          if (reminder.status == InvReminderStatus.snoozed && reminder.snoozeUntil != null)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                loc.translate('snoozed_until').replaceAll('{when}', _when(reminder.snoozeUntil!.toLocal())),
                key: ValueKey<String>('reminder_back_${reminder.id}'),
                style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.warningAmber),
              ),
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
