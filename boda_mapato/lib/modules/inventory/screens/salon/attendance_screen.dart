import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_access.dart';
import 'salon_text.dart';

/// Who is at work and for how long. Everyone starts and finishes their own day with one tap; the owner and managers
/// also see everyone's days and hours for the month, and can start or finish someone's day for them.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What "today" is (a test fixes it); the real clock otherwise.
  final DateTime? today;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  late String _month = _monthOf(widget.today ?? DateTime.now());

  AttendanceNow? _now;
  List<AttendancePerson> _people = <AttendancePerson>[];
  String? _error;
  bool _loading = true;
  bool _busy = false;

  static String _monthOf(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final String asked = _month;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AttendanceNow now = await _api.attendanceToday();
      final List<AttendancePerson> people = await _api.attendance(asked);
      if (!mounted || asked != _month) return;
      setState(() {
        _now = now;
        _people = people;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted || asked != _month) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _run(final Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _clockSomeoneIn() async {
    final InventoryProvider inv = context.read<InventoryProvider>();
    final bool sw = context.read<LocalizationService>().isSwahili;
    await inv.fetchSalonStaff();
    if (!mounted) return;
    final Map<String, String>? who = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => InvSheetShell(
        title: sw ? 'Anzisha siku ya nani?' : 'Start whose day?',
        children: <Widget>[
          Material(
            type: MaterialType.transparency,
            child: Column(
              children: <Widget>[
                for (final Map<String, String> s in inv.salonStaff)
                  ListTile(
                    key: ValueKey<String>('clock_for_${s['id']}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.person_outline, color: Colors.white70, size: 22.sp),
                    title: Text(s['name'] ?? '', style: ThemeConstants.bodyStyle),
                    onTap: () => Navigator.pop(sheet, s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (who == null || !mounted) return;
    await _run(() => _api.clockIn(staffId: who['id']));
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool manager = canSeeSalonMoneyHere(context);

    return Material(
      color: ThemeConstants.primaryBlue,
      child: RefreshIndicator(
        onRefresh: _load,
        backgroundColor: Colors.white,
        color: ThemeConstants.primaryBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
          children: _body(sw, manager),
        ),
      ),
    );
  }

  List<Widget> _body(final bool sw, final bool manager) {
    final AttendanceNow? now = _now;
    String hm(final DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return <Widget>[
      if (now != null)
        Container(
          key: const ValueKey<String>('attendance_status'),
          decoration: ThemeConstants.glassCardDecoration,
          padding: EdgeInsets.all(14.w),
          child: Row(
            children: <Widget>[
              Icon(now.atWork ? Icons.work_history_outlined : Icons.hotel_class_outlined, color: now.atWork ? ThemeConstants.successGreen : Colors.white70, size: 26.sp),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  now.atWork ? (sw ? 'Uko kazini tangu ${hm(now.since!)}' : 'At work since ${hm(now.since!)}') : (sw ? 'Hujaanza kazi leo' : 'Not at work yet'),
                  style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ElevatedButton(
                key: ValueKey<String>(now.atWork ? 'clock_out' : 'clock_in'),
                onPressed: _busy ? null : () => _run(now.atWork ? _api.clockOut : _api.clockIn),
                style: ElevatedButton.styleFrom(backgroundColor: now.atWork ? ThemeConstants.errorRed : ThemeConstants.successGreen),
                child: Text(now.atWork ? (sw ? 'Maliza kazi' : 'Finish work') : (sw ? 'Anza kazi' : 'Start work'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      if (manager) ...<Widget>[
        SizedBox(height: 8.h),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey<String>('clock_someone_in'),
            onPressed: _busy ? null : _clockSomeoneIn,
            icon: const Icon(Icons.person_add_alt_1_outlined, color: Colors.white70),
            label: Text(sw ? 'Anzisha siku ya mtu' : 'Start someone\'s day', style: const TextStyle(color: Colors.white70)),
          ),
        ),
      ],
      SizedBox(height: 4.h),
      Row(
        children: <Widget>[
          IconButton(key: const ValueKey<String>('attendance_prev'), onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left, color: Colors.white)),
          Expanded(child: Center(child: Text(monthLabel(sw: sw, month: _month), key: const ValueKey<String>('attendance_month'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)))),
          IconButton(key: const ValueKey<String>('attendance_next'), onPressed: () => _go(1), icon: const Icon(Icons.chevron_right, color: Colors.white)),
        ],
      ),
      if (_loading && _now == null)
        Padding(padding: EdgeInsets.only(top: 40.h), child: const Center(child: CircularProgressIndicator(color: Colors.white70)))
      else if (_error != null && _now == null) ...<Widget>[
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('attendance_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ] else if (_people.isEmpty)
        InvEmptyState(icon: Icons.event_busy_outlined, message: sw ? 'Hakuna aliyeanza kazi mwezi huu.' : 'Nobody has clocked in this month.')
      else
        for (final AttendancePerson p in _people) ...<Widget>[
          Container(
            key: ValueKey<String>('att_${p.staffId}'),
            decoration: ThemeConstants.glassCardDecoration,
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: Text(p.name, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
                    if (p.atWork) InvBadge(label: sw ? 'Kazini' : 'At work', color: ThemeConstants.successGreen),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(sw ? 'Siku ${p.days} • saa ${_hours(p.hours)}' : '${p.days} ${p.days == 1 ? 'day' : 'days'} • ${_hours(p.hours)} h', style: ThemeConstants.captionStyle),
                SizedBox(height: 6.h),
                for (final AttendanceRecord r in p.records.reversed.take(5))
                  Text(
                    '${dayLabel(r.date)}  ${hm(r.clockIn)}–${r.clockOut == null ? '…' : hm(r.clockOut!)}${r.hours == null ? '' : '  (${_hours(r.hours!)} h)'}',
                    style: ThemeConstants.captionStyle.copyWith(color: Colors.white70),
                  ),
                if (manager && p.atWork)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(key: ValueKey<String>('att_out_${p.staffId}'), onPressed: _busy ? null : () => _run(() => _api.clockOut(staffId: p.staffId)), child: Text(sw ? 'Maliza siku yake' : 'Finish their day', style: const TextStyle(color: ThemeConstants.warningAmber))),
                  ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
        ],
    ];
  }

  void _go(final int by) {
    setState(() => _month = shiftMonth(_month, by));
    _load();
  }

  static String _hours(final double h) => h % 1 == 0 ? h.toInt().toString() : h.toStringAsFixed(1);
}
