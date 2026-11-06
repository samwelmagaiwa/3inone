import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../../../widgets/live_refresh.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import '../widgets/glow_list_card.dart';
import 'attendance_screen.dart';
import 'feedback_screen.dart';
import 'salon_text.dart';

/// A stylist's own day, on one page: the diary and the queue to work through, what they have earned (with the target), whether they are
/// at work, and their days off (asked for here, decided by whoever sets the schedule). Everything is their own: the server shows a stylist
/// no one else's figures, and nothing about the salon's profit, the money or other people's pay.
class StylistHomeScreen extends StatefulWidget {
  const StylistHomeScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What day it is (a fixed day in tests).
  final DateTime? today;

  @override
  State<StylistHomeScreen> createState() => _StylistHomeScreenState();
}

class _Earned {
  const _Earned({required this.revenue, required this.commission, required this.visits});

  final double revenue;
  final double commission;
  final int visits;
}

class _StylistHomeScreenState extends State<StylistHomeScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();

  bool _loading = true;
  String? _error;
  _Earned _today = const _Earned(revenue: 0, commission: 0, visits: 0);
  _Earned _week = const _Earned(revenue: 0, commission: 0, visits: 0);
  _Earned _month = const _Earned(revenue: 0, commission: 0, visits: 0);
  StylistTarget? _target;
  List<SalonAppointment> _diary = <SalonAppointment>[];
  List<Map<String, dynamic>> _queue = <Map<String, dynamic>>[];
  AttendanceNow? _attendance;
  List<DayOffRequest> _requests = <DayOffRequest>[];
  bool _busy = false;

  DateTime get _now {
    final DateTime n = widget.today ?? DateTime.now();

    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// One part failing (a right switched off, no network for it) leaves the rest of the page as it was.
  Future<T?> _try<T>(final Future<T> Function() call) async {
    try {
      return await call();
    } on Exception {
      return null;
    }
  }

  _Earned _own(final StylistReport? r) {
    if (r == null || r.stylists.isEmpty) return const _Earned(revenue: 0, commission: 0, visits: 0);
    final StylistRow row = r.stylists.first;

    return _Earned(revenue: row.revenue, commission: row.commission, visits: row.visits);
  }

  Future<void> _load() async {
    final DateTime t = _now;
    final DateTime weekStart = t.subtract(Duration(days: t.weekday - 1));
    final DateTime monthStart = DateTime(t.year, t.month);
    setState(() {
      _loading = true;
      _error = null;
    });
    final List<Object?> got = await Future.wait<Object?>(<Future<Object?>>[
      _try<StylistReport>(() => _api.stylists(from: t, to: t)),
      _try<StylistReport>(() => _api.stylists(from: weekStart, to: t)),
      _try<StylistReport>(() => _api.stylists(from: monthStart, to: t)),
      _try<List<SalonAppointment>>(() => _api.appointments(t)),
      _try<Map<String, dynamic>>(() => _api.queue()),
      _try<AttendanceNow>(() => _api.attendanceToday()),
      _try<(bool, List<DayOffRequest>)>(() => _api.dayOffRequests()),
    ]);
    if (!mounted) return;
    final StylistReport? month = got[2] as StylistReport?;
    setState(() {
      _today = _own(got[0] as StylistReport?);
      _week = _own(got[1] as StylistReport?);
      _month = _own(month);
      _target = month != null && month.stylists.isNotEmpty ? month.stylists.first.target : null;
      _diary = (got[3] as List<SalonAppointment>?) ?? <SalonAppointment>[];
      final Map<String, dynamic>? q = got[4] as Map<String, dynamic>?;
      _queue = q != null && q['queue'] is List ? <Map<String, dynamic>>[for (final dynamic r in q['queue'] as List<dynamic>) if (r is Map) Map<String, dynamic>.from(r)] : <Map<String, dynamic>>[];
      _attendance = got[5] as AttendanceNow?;
      final (bool, List<DayOffRequest>)? dr = got[6] as (bool, List<DayOffRequest>)?;
      _requests = dr?.$2 ?? <DayOffRequest>[];
      _loading = false;
      if (got.every((Object? g) => g == null)) _error = LocalizationService.instance.isSwahili ? 'Haikuweza kupakia siku yako.' : 'Your day could not be loaded.';
    });
  }

  Future<void> _act(final Future<void> Function() call, {final String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await call();
      if (ok != null && mounted) ThemeConstants.showSuccessSnackBar(context, ok);
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _askDayOff(final bool sw) async {
    final DateTime? day = await showDatePicker(context: context, initialDate: _now.add(const Duration(days: 1)), firstDate: _now, lastDate: _now.add(const Duration(days: 180)));
    if (day == null || !mounted) return;
    final TextEditingController why = TextEditingController();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: const ValueKey<String>('dayoff_dialog'),
        backgroundColor: ThemeConstants.primaryBlue,
        title: Text(sw ? 'Omba siku ya mapumziko' : 'Ask for a day off', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.bold)),
        content: TextField(controller: why, key: const ValueKey<String>('dayoff_reason'), maxLength: 120, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: sw ? 'Sababu (si lazima)' : 'Reason (optional)', hintStyle: const TextStyle(color: Colors.white54))),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white70))),
          ElevatedButton(key: const ValueKey<String>('dayoff_send'), onPressed: () => Navigator.pop(c, true), child: Text(sw ? 'Tuma ombi' : 'Send request')),
        ],
      ),
    );
    if (go != true) return;
    await _act(() => _api.requestDayOff(day, reason: why.text), ok: sw ? 'Ombi limetumwa.' : 'Request sent.');
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final String name = context.watch<AuthProvider>().user?.name ?? '';

    return LiveRefresh(
      onRefresh: _load,
      child: Builder(
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            key: const ValueKey<String>('stylist_home'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 24.h),
            children: <Widget>[
              Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: Text(sw ? 'Siku yangu${name.isEmpty ? '' : ', $name'}' : 'My day${name.isEmpty ? '' : ', $name'}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, fontSize: 17.sp)),
              ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  child: Row(children: <Widget>[
                    Expanded(child: Text(_error!, style: ThemeConstants.captionStyle)),
                    TextButton(key: const ValueKey<String>('stylist_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white))),
                  ]),
                ),
              if (_loading && _diary.isEmpty && _error == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: Colors.white70))),
              _statusCard(sw),
              _earnedCard(sw),
              _diaryCard(sw),
              _queueCard(sw),
              _daysOffCard(sw),
              _linksCard(sw),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- at work
  Widget _statusCard(final bool sw) {
    final AttendanceNow? a = _attendance;
    if (a == null) return const SizedBox.shrink();
    final bool at = a.atWork;

    return GlowCard(
      title: sw ? 'Hali yangu' : 'My status',
      dividerKey: 'stylist_status_divider',
      children: <Widget>[
        Row(children: <Widget>[
          Icon(at ? Icons.check_circle_rounded : Icons.do_not_disturb_on_outlined, color: at ? ThemeConstants.successGreen : Colors.white54),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              at ? (sw ? 'Uko kazini${a.since == null ? '' : ' tangu ${_hhmm(a.since!)}'}' : 'You are at work${a.since == null ? '' : ' since ${_hhmm(a.since!)}'}') : (sw ? 'Hujaanza kazi leo' : 'You have not started today'),
              key: const ValueKey<String>('stylist_status'),
              style: ThemeConstants.bodyStyle,
            ),
          ),
          ElevatedButton(
            key: ValueKey<String>(at ? 'stylist_clock_out' : 'stylist_clock_in'),
            style: ElevatedButton.styleFrom(backgroundColor: at ? ThemeConstants.errorRed : ThemeConstants.successGreen),
            onPressed: _busy ? null : () => _act(at ? _api.clockOut : _api.clockIn, ok: at ? (sw ? 'Umemaliza kazi.' : 'Day finished.') : (sw ? 'Umeanza kazi.' : 'Day started.')),
            child: Text(at ? (sw ? 'Maliza kazi' : 'Finish') : (sw ? 'Anza kazi' : 'Start'), style: const TextStyle(color: Colors.white)),
          ),
        ]),
      ],
    );
  }

  // ---------------------------------------------------------------- what I earned
  Widget _earnedCard(final bool sw) => GlowCard(
        title: sw ? 'Nilichopata' : 'What I earned',
        dividerKey: 'stylist_earned_divider',
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: _tile('today', sw ? 'Leo' : 'Today', _today, sw)),
            SizedBox(width: 8.w),
            Expanded(child: _tile('week', sw ? 'Wiki' : 'Week', _week, sw)),
            SizedBox(width: 8.w),
            Expanded(child: _tile('month', sw ? 'Mwezi' : 'Month', _month, sw)),
          ]),
          if (_target != null) ...<Widget>[SizedBox(height: 10.h), _targetBar(_target!, sw)],
        ],
      );

  Widget _tile(final String key, final String label, final _Earned e, final bool sw) => Container(
        key: ValueKey<String>('stylist_$key'),
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12.r), border: Border.all(color: Colors.white12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(label, style: ThemeConstants.captionStyle),
          SizedBox(height: 2.h),
          Text(tsh(e.revenue), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w800, fontSize: 14.sp)),
          SizedBox(height: 2.h),
          Text('${sw ? 'Kamisheni' : 'Commission'} ${tsh(e.commission)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.successGreen, fontSize: 10.sp)),
          Text('${e.visits} ${sw ? 'ziara' : 'visits'}', style: ThemeConstants.captionStyle.copyWith(fontSize: 10.sp)),
        ]),
      );

  Widget _targetBar(final StylistTarget t, final bool sw) {
    final (String, Color) pace = switch (t.pace) {
      'reached' => (sw ? 'Lengo limefikiwa' : 'Target reached', ThemeConstants.successGreen),
      'ahead' => (sw ? 'Mbele ya kasi' : 'Ahead of pace', ThemeConstants.successGreen),
      'on_track' => (sw ? 'Kwenye njia' : 'On track', ThemeConstants.warningAmber),
      _ => (sw ? 'Nyuma ya kasi' : 'Behind pace', ThemeConstants.errorText),
    };

    return Column(key: const ValueKey<String>('stylist_target'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[
        Icon(Icons.flag_outlined, size: 14.sp, color: pace.$2),
        SizedBox(width: 4.w),
        Expanded(child: Text('${sw ? 'Lengo langu' : 'My target'} ${tsh(t.amount)}  ·  ${pace.$1}', style: ThemeConstants.captionStyle)),
        Text('${t.percent.round()}%', style: TextStyle(color: pace.$2, fontWeight: FontWeight.w800, fontSize: 12.sp)),
      ]),
      SizedBox(height: 4.h),
      ClipRRect(
        borderRadius: BorderRadius.circular(4.r),
        child: LinearProgressIndicator(value: (t.percent / 100).clamp(0.0, 1.0).toDouble(), minHeight: 7.h, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(pace.$2)),
      ),
    ]);
  }

  // ---------------------------------------------------------------- the diary and the queue
  Widget _diaryCard(final bool sw) => GlowCard(
        title: sw ? 'Miadi ya leo' : "Today's appointments",
        dividerKey: 'stylist_diary_divider',
        children: <Widget>[
          if (_diary.isEmpty) Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: Text(sw ? 'Hakuna miadi leo.' : 'No appointments today.', key: const ValueKey<String>('stylist_no_diary'), style: ThemeConstants.captionStyle)),
          for (final SalonAppointment a in _diary) _appointment(a, sw),
        ],
      );

  Widget _appointment(final SalonAppointment a, final bool sw) {
    final bool open = <String>['booked', 'confirmed', 'in_progress'].contains(a.status);
    final String? next = a.status == 'in_progress' ? 'done' : (open ? 'in_progress' : null);
    final String label = switch (a.status) {
      'in_progress' => sw ? 'Inaendelea' : 'In progress',
      'done' => sw ? 'Imekamilika' : 'Done',
      'cancelled' => sw ? 'Imeghairiwa' : 'Cancelled',
      'no_show' => sw ? 'Hakuja' : 'No-show',
      'confirmed' => sw ? 'Imethibitishwa' : 'Confirmed',
      _ => sw ? 'Imewekwa' : 'Booked',
    };

    return Padding(
      key: ValueKey<String>('stylist_appt_${a.id}'),
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(children: <Widget>[
        SizedBox(width: 46.w, child: Text(_hhmm(a.startsAt), style: TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w800, fontSize: 14.sp))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(a.clientName.isEmpty ? (sw ? 'Mteja' : 'Client') : a.clientName, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
            Text(a.services.map((AppointmentService s) => s.name).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.captionStyle),
            Text(label, style: ThemeConstants.captionStyle.copyWith(color: a.status == 'done' ? ThemeConstants.successGreen : Colors.white70, fontSize: 10.sp)),
          ]),
        ),
        if (next != null)
          ElevatedButton(
            key: ValueKey<String>('stylist_appt_${a.id}_$next'),
            style: ElevatedButton.styleFrom(backgroundColor: next == 'done' ? ThemeConstants.successGreen : ThemeConstants.invAccent, padding: EdgeInsets.symmetric(horizontal: 12.w)),
            onPressed: _busy ? null : () => _act(() => _api.setAppointmentStatus(a.id, next)),
            child: Text(next == 'done' ? (sw ? 'Maliza' : 'Finish') : (sw ? 'Anza' : 'Start'), style: const TextStyle(color: Colors.white)),
          ),
      ]),
    );
  }

  Widget _queueCard(final bool sw) {
    final List<Map<String, dynamic>> waiting = _queue.where((Map<String, dynamic> r) => r['status'] == 'waiting').toList();
    final List<Map<String, dynamic>> serving = _queue.where((Map<String, dynamic> r) => r['status'] == 'serving').toList();

    return GlowCard(
      title: sw ? 'Wanaosubiri' : 'Waiting in the queue',
      dividerKey: 'stylist_queue_divider',
      children: <Widget>[
        if (waiting.isEmpty && serving.isEmpty) Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: Text(sw ? 'Hakuna anayesubiri.' : 'Nobody is waiting.', key: const ValueKey<String>('stylist_no_queue'), style: ThemeConstants.captionStyle)),
        for (final Map<String, dynamic> r in <Map<String, dynamic>>[...serving, ...waiting]) _queueRow(r, sw),
      ],
    );
  }

  Widget _queueRow(final Map<String, dynamic> r, final bool sw) {
    final int id = r['id'] is num ? (r['id'] as num).toInt() : int.tryParse('${r['id']}') ?? 0;
    final bool serving = r['status'] == 'serving';

    return Padding(
      key: ValueKey<String>('stylist_queue_$id'),
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(children: <Widget>[
        Icon(serving ? Icons.content_cut_rounded : Icons.hourglass_bottom_rounded, size: 18.sp, color: serving ? ThemeConstants.successGreen : ThemeConstants.warningAmber),
        SizedBox(width: 8.w),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('${r['name'] ?? ''}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
            if ('${r['service'] ?? r['product_name'] ?? ''}'.isNotEmpty) Text('${r['service'] ?? r['product_name']}', style: ThemeConstants.captionStyle),
          ]),
        ),
        ElevatedButton(
          key: ValueKey<String>('stylist_queue_${id}_${serving ? 'done' : 'serving'}'),
          style: ElevatedButton.styleFrom(backgroundColor: serving ? ThemeConstants.successGreen : ThemeConstants.invAccent, padding: EdgeInsets.symmetric(horizontal: 12.w)),
          onPressed: _busy ? null : () => _act(() => _api.setQueueStatus(id, serving ? 'done' : 'serving')),
          child: Text(serving ? (sw ? 'Maliza' : 'Finish') : (sw ? 'Chukua' : 'Take'), style: const TextStyle(color: Colors.white)),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- days off
  Widget _daysOffCard(final bool sw) => GlowCard(
        title: sw ? 'Mapumziko yangu' : 'My days off',
        dividerKey: 'stylist_dayoff_divider',
        children: <Widget>[
          if (_requests.isEmpty) Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: Text(sw ? 'Hujaomba mapumziko.' : 'No days off asked for.', style: ThemeConstants.captionStyle)),
          for (final DayOffRequest r in _requests)
            Padding(
              key: ValueKey<String>('stylist_dayoff_${r.id}'),
              padding: EdgeInsets.symmetric(vertical: 5.h),
              child: Row(children: <Widget>[
                Expanded(child: Text('${_dmy(r.offOn)}${r.reason == null ? '' : '  ·  ${r.reason}'}', style: ThemeConstants.bodyStyle)),
                _statusChip(r.status, sw),
              ]),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey<String>('stylist_ask_dayoff'),
              onPressed: _busy ? null : () => _askDayOff(sw),
              icon: const Icon(Icons.event_busy_outlined, size: 18, color: Colors.white),
              label: Text(sw ? 'Omba siku ya mapumziko' : 'Ask for a day off', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r), side: const BorderSide(color: Colors.white24))),
            ),
          ),
        ],
      );

  Widget _statusChip(final String status, final bool sw) {
    final (String, Color) c = switch (status) {
      'approved' => (sw ? 'Imekubaliwa' : 'Approved', ThemeConstants.successGreen),
      'rejected' => (sw ? 'Imekataliwa' : 'Turned down', ThemeConstants.errorText),
      _ => (sw ? 'Inasubiri' : 'Waiting', ThemeConstants.warningAmber),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(color: c.$2.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10.r), border: Border.all(color: c.$2.withValues(alpha: 0.6))),
      child: Text(c.$1, style: TextStyle(color: c.$2, fontWeight: FontWeight.w800, fontSize: 11.sp)),
    );
  }

  // ---------------------------------------------------------------- where else to go
  Widget _linksCard(final bool sw) {
    final AuthProvider? auth = context.read<AuthProvider>();
    final bool feedback = auth?.user?.access.has('inv_salon_feedback') ?? false;

    return GlowCard(
      dividerKey: 'stylist_links_divider',
      children: <Widget>[
        _link(Icons.timer_outlined, sw ? 'Mahudhurio yangu' : 'My attendance', 'stylist_link_attendance', () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => ThemeConstants.buildScaffold(flat: true, title: sw ? 'Mahudhurio' : 'Attendance', body: AttendanceScreen(api: _api))))),
        if (feedback) _link(Icons.star_outline_rounded, sw ? 'Maoni ya wateja kunihusu' : 'What clients said about me', 'stylist_link_feedback', () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => ThemeConstants.buildScaffold(flat: true, title: sw ? 'Maoni ya wateja' : 'Client feedback', body: FeedbackScreen(api: _api))))),
      ],
    );
  }

  Widget _link(final IconData icon, final String label, final String key, final VoidCallback onTap) => ListTile(
        key: ValueKey<String>(key),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Colors.white70),
        title: Text(label, style: ThemeConstants.bodyStyle),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
        onTap: onTap,
      );

  static String _hhmm(final DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  static String _dmy(final DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
