import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_text.dart';

/// When each person works: the weekdays and the hours (a booking outside them is refused unless the owner says book
/// anyway), and their days off. For the owner and managers.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.api, this.today, this.pickTime});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What "today" is (a test fixes it); the real clock otherwise.
  final DateTime? today;

  /// Pick a time of day: the phone's clock dial by default (a test gives its own answer).
  final Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial)? pickTime;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  late String _month = _monthOf(widget.today ?? DateTime.now());

  List<StaffProfile> _people = <StaffProfile>[];
  List<DayOff> _daysOff = <DayOff>[];
  // What is being edited, per person: their weekdays and hours before saving.
  final Map<String, Set<int>> _days = <String, Set<int>>{};
  final Map<String, String?> _from = <String, String?>{};
  final Map<String, String?> _to = <String, String?>{};
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
      final List<StaffProfile> people = await _api.staffProfiles();
      final List<DayOff> off = await _api.daysOff(asked);
      if (!mounted || asked != _month) return;
      setState(() {
        _people = people;
        _daysOff = off;
        for (final StaffProfile p in people) {
          _days[p.staffId] = p.workDays.toSet();
          _from[p.staffId] = p.shiftStart;
          _to[p.staffId] = p.shiftEnd;
        }
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

  Future<void> _run(final Future<void> Function() action, {final String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      if (done != null) ThemeConstants.showSuccessSnackBar(context, done);
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _pickTime(final String staffId, final bool start) async {
    final String? current = start ? _from[staffId] : _to[staffId];
    final TimeOfDay initial = current == null ? TimeOfDay(hour: start ? 9 : 17, minute: 0) : TimeOfDay(hour: int.parse(current.substring(0, 2)), minute: int.parse(current.substring(3, 5)));
    final TimeOfDay? picked = widget.pickTime != null ? await widget.pickTime!(context, initial) : await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final String text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => start ? _from[staffId] = text : _to[staffId] = text);
  }

  Future<void> _save(final StaffProfile p) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? from = _from[p.staffId];
    final String? to = _to[p.staffId];
    if ((from == null) != (to == null)) {
      ThemeConstants.showErrorSnackBar(context, sw ? 'Weka saa ya kuanza na ya kuondoka, au zote ziachwe wazi.' : 'Set both the starting and the finishing time, or leave both empty.');
      return;
    }
    if (from != null && to != null && from.compareTo(to) >= 0) {
      ThemeConstants.showErrorSnackBar(context, sw ? 'Saa ya kuondoka iwe baada ya saa ya kuanza.' : 'The finishing time must be after the starting time.');
      return;
    }
    await _run(
      () => _api.saveStaffProfile(p.staffId, workDays: (_days[p.staffId] ?? <int>{}).toList()..sort(), shiftStart: from, shiftEnd: to, clearHours: from == null),
      done: sw ? 'Ratiba imehifadhiwa.' : 'Schedule saved.',
    );
  }

  Future<void> _addDayOff() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => _DayOffSheet(api: _api, people: _people, month: _month, sw: sw),
    );
    if (saved == true && mounted) _load();
  }

  void _go(final int by) {
    setState(() => _month = shiftMonth(_month, by));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Material(
      color: ThemeConstants.primaryBlue,
      child: RefreshIndicator(
        onRefresh: _load,
        backgroundColor: Colors.white,
        color: ThemeConstants.primaryBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
          children: _body(sw),
        ),
      ),
    );
  }

  List<Widget> _body(final bool sw) {
    if (_loading && _people.isEmpty) {
      return <Widget>[SizedBox(height: 100.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];
    }
    if (_error != null && _people.isEmpty) {
      return <Widget>[
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('schedule_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ];
    }
    final List<String> dayNames = sw ? <String>['Jtt', 'Jnn', 'Jtn', 'Alh', 'Iju', 'Jms', 'Jpl'] : <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return <Widget>[
      Text(sw ? 'Siku na saa za kazi' : 'Working days and hours', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: 2.h),
      Text(
        sw ? 'Usiweke chochote kama mtu anaweza kupangiwa wakati wowote.' : 'Leave empty if they may be booked at any time.',
        style: ThemeConstants.captionStyle,
      ),
      SizedBox(height: 8.h),
      for (final StaffProfile p in _people) ...<Widget>[
        Container(
          key: ValueKey<String>('schedule_${p.staffId}'),
          decoration: ThemeConstants.glassCardDecoration,
          padding: EdgeInsets.all(12.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(p.specialization == null ? p.name : '${p.name} • ${p.specialization}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: 6.h),
              Wrap(
                spacing: 6.w,
                children: <Widget>[
                  for (int d = 1; d <= 7; d++)
                    FilterChip(
                      key: ValueKey<String>('wd_${p.staffId}_$d'),
                      label: Text(dayNames[d - 1]),
                      selected: (_days[p.staffId] ?? <int>{}).contains(d),
                      onSelected: (bool on) => setState(() => on ? (_days[p.staffId] ??= <int>{}).add(d) : (_days[p.staffId] ??= <int>{}).remove(d)),
                    ),
                ],
              ),
              SizedBox(height: 6.h),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey<String>('hours_start_${p.staffId}'),
                      onPressed: () => _pickTime(p.staffId, true),
                      child: Text(_from[p.staffId] ?? (sw ? 'Anza' : 'From'), style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey<String>('hours_end_${p.staffId}'),
                      onPressed: () => _pickTime(p.staffId, false),
                      child: Text(_to[p.staffId] ?? (sw ? 'Ondoka' : 'To'), style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>('hours_clear_${p.staffId}'),
                    tooltip: sw ? 'Futa saa' : 'Clear hours',
                    onPressed: () => setState(() {
                      _from[p.staffId] = null;
                      _to[p.staffId] = null;
                    }),
                    icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(key: ValueKey<String>('schedule_save_${p.staffId}'), onPressed: _busy ? null : () => _save(p), child: Text(sw ? 'Hifadhi' : 'Save', style: const TextStyle(color: ThemeConstants.invAccent))),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.h),
      ],
      SizedBox(height: 8.h),
      Row(
        children: <Widget>[
          IconButton(key: const ValueKey<String>('dayoff_prev'), onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left, color: Colors.white)),
          Expanded(child: Center(child: Text('${sw ? 'Mapumziko' : 'Days off'} • ${monthLabel(sw: sw, month: _month)}', key: const ValueKey<String>('dayoff_month'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)))),
          IconButton(key: const ValueKey<String>('dayoff_next'), onPressed: () => _go(1), icon: const Icon(Icons.chevron_right, color: Colors.white)),
        ],
      ),
      InvPrimaryButton(key: const ValueKey<String>('dayoff_add'), busy: false, label: sw ? 'Ongeza siku ya mapumziko' : 'Add a day off', onPressed: _addDayOff),
      SizedBox(height: 8.h),
      if (_daysOff.isEmpty)
        InvEmptyState(icon: Icons.beach_access_outlined, message: sw ? 'Hakuna mapumziko mwezi huu.' : 'No days off this month.')
      else
        for (final DayOff d in _daysOff)
          ListTile(
            key: ValueKey<String>('dayoff_${d.id}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('${d.staffName ?? ''} • ${dayLabel(d.offOn)}', style: ThemeConstants.bodyStyle),
            subtitle: d.reason == null ? null : Text(d.reason!, style: ThemeConstants.captionStyle),
            trailing: IconButton(key: ValueKey<String>('dayoff_remove_${d.id}'), onPressed: _busy ? null : () => _run(() => _api.deleteDayOff(d.id)), icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 20)),
          ),
    ];
  }
}

class _DayOffSheet extends StatefulWidget {
  const _DayOffSheet({required this.api, required this.people, required this.month, required this.sw});

  final SalonApi api;
  final List<StaffProfile> people;
  final String month;
  final bool sw;

  @override
  State<_DayOffSheet> createState() => _DayOffSheetState();
}

class _DayOffSheetState extends State<_DayOffSheet> {
  final TextEditingController _reason = TextEditingController();
  String? _staffId;
  late DateTime _date = DateTime(int.parse(widget.month.substring(0, 4)), int.parse(widget.month.substring(5, 7)), 1);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_staffId == null) {
      setState(() => _error = widget.sw ? 'Chagua mtu.' : 'Choose who.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.addDayOff(_staffId!, _date, reason: _reason.text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = widget.sw;

    return InvSheetShell(
      title: sw ? 'Siku ya mapumziko' : 'A day off',
      children: <Widget>[
        Wrap(
          spacing: 8.w,
          runSpacing: 4.h,
          children: <Widget>[
            for (final StaffProfile p in widget.people)
              ChoiceChip(key: ValueKey<String>('dayoff_who_${p.staffId}'), label: Text(p.name), selected: _staffId == p.staffId, onSelected: (_) => setState(() => _staffId = p.staffId)),
          ],
        ),
        SizedBox(height: 10.h),
        InvDateField(label: sw ? 'Tarehe' : 'Date', value: _date, onChanged: (DateTime? d) => setState(() => _date = d ?? _date)),
        SizedBox(height: 10.h),
        InvTextField(key: const ValueKey<String>('dayoff_reason'), controller: _reason, label: sw ? 'Sababu' : 'Reason', isOptional: true),
        if (_error != null) Padding(padding: EdgeInsets.only(top: 10.h), child: Text(_error!, key: const ValueKey<String>('dayoff_error'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorText, fontSize: 12.sp))),
        SizedBox(height: 14.h),
        InvPrimaryButton(key: const ValueKey<String>('dayoff_save'), busy: _saving, label: sw ? 'Hifadhi' : 'Save', onPressed: _save),
      ],
    );
  }
}
