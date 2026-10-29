import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_text.dart';

/// Each person's cash for a shift: open it with the float in the till, and at the end count the cash and hand it over.
/// The page says what the till SHOULD hold (the float plus the cash taken) so any difference is seen at once, and the
/// owner is alerted when a shift closes short or over. Mobile money and bank are shown beside it (they are not in the
/// till). Revenue, commission and this cash are three different figures.
class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What "today" is (a test fixes it); the real clock otherwise.
  final DateTime? today;

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  late String _month = _monthOf(widget.today ?? DateTime.now());

  SalonShift? _mine;
  ShiftsReport? _report;
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
      final SalonShift? mine = await _api.currentShift();
      final ShiftsReport report = await _api.shifts(asked);
      if (!mounted || asked != _month) return;
      setState(() {
        _mine = mine;
        _report = report;
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

  Future<void> _open() async {
    final double? float = await showDialog<double>(context: context, builder: (BuildContext d) => const _OpenShiftDialog());
    if (float == null || !mounted) return;
    await _run(() => _api.openShift(float));
  }

  Future<void> _close(final SalonShift shift) async {
    final bool? closed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => _CloseSheet(api: _api, shift: shift),
    );
    if (closed == true && mounted) _load();
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
    final SalonShift? mine = _mine;
    final ShiftsReport? r = _report;

    return <Widget>[
      if (_loading && r == null)
        Padding(padding: EdgeInsets.only(top: 80.h), child: const Center(child: CircularProgressIndicator(color: Colors.white70)))
      else if (_error != null && r == null) ...<Widget>[
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('shifts_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ] else ...<Widget>[
        if (mine == null)
          Container(
            key: const ValueKey<String>('shift_none'),
            decoration: ThemeConstants.glassCardDecoration,
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(sw ? 'Huna zamu iliyo wazi.' : 'You have no shift open.', style: ThemeConstants.bodyStyle)),
                ElevatedButton(key: const ValueKey<String>('shift_open'), onPressed: _busy ? null : _open, child: Text(sw ? 'Fungua zamu' : 'Open a shift')),
              ],
            ),
          )
        else
          _MyShiftCard(shift: mine, sw: sw, onClose: () => _close(mine)),
        SizedBox(height: 12.h),
        Row(
          children: <Widget>[
            IconButton(key: const ValueKey<String>('shifts_prev'), onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left, color: Colors.white)),
            Expanded(child: Center(child: Text(monthLabel(sw: sw, month: _month), key: const ValueKey<String>('shifts_month'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)))),
            IconButton(key: const ValueKey<String>('shifts_next'), onPressed: () => _go(1), icon: const Icon(Icons.chevron_right, color: Colors.white)),
          ],
        ),
        if (r != null) ...<Widget>[
          Text(
            sw ? 'Zamu ${r.count} • zenye tofauti ${r.withDifference} • jumla ya tofauti ${tsh(r.difference)}' : '${r.count} shifts • ${r.withDifference} with a difference • difference in all ${tsh(r.difference)}',
            key: const ValueKey<String>('shifts_totals'),
            style: ThemeConstants.captionStyle.copyWith(color: r.withDifference > 0 ? ThemeConstants.warningAmber : null),
          ),
          SizedBox(height: 8.h),
          if (r.shifts.isEmpty)
            InvEmptyState(icon: Icons.point_of_sale_outlined, message: sw ? 'Hakuna zamu mwezi huu.' : 'No shifts this month.')
          else
            for (final SalonShift s in r.shifts) ...<Widget>[
              _ShiftCard(shift: s, sw: sw),
              SizedBox(height: 8.h),
            ],
        ],
      ],
    ];
  }
}

class _MyShiftCard extends StatelessWidget {
  const _MyShiftCard({required this.shift, required this.sw, required this.onClose});

  final SalonShift shift;
  final bool sw;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    String hm(final DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Container(
      key: const ValueKey<String>('shift_open_card'),
      decoration: ThemeConstants.glassCardDecoration.copyWith(border: Border.all(color: ThemeConstants.successGreen, width: 1.2)),
      padding: EdgeInsets.all(14.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(sw ? 'Zamu yako imefunguliwa ${hm(shift.openedAt)}' : 'Your shift opened at ${hm(shift.openedAt)}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)),
          SizedBox(height: 8.h),
          InvKeyValueWrap(entries: <String, String>{
            sw ? 'Pesa ya kuanzia' : 'Starting cash': tsh(shift.openingFloat),
            sw ? 'Taslimu ulizopokea' : 'Cash taken': tsh(shift.collected.cash),
            sw ? 'Pesa za simu' : 'Mobile money': tsh(shift.collected.mobileMoney),
            sw ? 'Benki' : 'Bank': tsh(shift.collected.bank),
          }),
          SizedBox(height: 8.h),
          Row(
            children: <Widget>[
              Expanded(child: Text(sw ? 'Droo inapaswa kuwa na ${tsh(shift.expectedCash)}' : 'The till should hold ${tsh(shift.expectedCash)}', key: const ValueKey<String>('shift_expected'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, color: ThemeConstants.invAccent))),
              ElevatedButton(key: const ValueKey<String>('shift_close'), onPressed: onClose, style: ElevatedButton.styleFrom(backgroundColor: ThemeConstants.errorRed), child: Text(sw ? 'Funga zamu' : 'Close shift', style: const TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.shift, required this.sw});

  final SalonShift shift;
  final bool sw;

  @override
  Widget build(BuildContext context) {
    String hm(final DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final double diff = shift.difference ?? 0;
    final bool diffs = shift.hasDifference;

    return Container(
      key: ValueKey<String>('shift_${shift.id}'),
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('${shift.staffName} • ${dayLabel(shift.openedAt)} ${hm(shift.openedAt)}${shift.closedAt == null ? '' : '–${hm(shift.closedAt!)}'}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
              if (shift.isOpen)
                InvBadge(label: sw ? 'Wazi' : 'Open', color: ThemeConstants.successGreen)
              else
                InvBadge(label: diffs ? (diff < 0 ? (sw ? 'Pungufu' : 'Short') : (sw ? 'Zaidi' : 'Over')) : (sw ? 'Sawa' : 'Exact'), color: diffs ? ThemeConstants.errorRed : ThemeConstants.successGreen),
            ],
          ),
          if (!shift.isOpen) ...<Widget>[
            SizedBox(height: 6.h),
            InvKeyValueWrap(entries: <String, String>{
              sw ? 'Ilipaswa kuwa' : 'Expected': tsh(shift.expectedCash),
              sw ? 'Iliyohesabiwa' : 'Counted': tsh(shift.countedCash ?? 0),
              if (diffs) sw ? 'Tofauti' : 'Difference': tsh(diff),
              if (shift.handedToName != null) sw ? 'Alikabidhi' : 'Handed to': shift.handedToName!,
            }),
            if (shift.note != null) Text(shift.note!, style: ThemeConstants.captionStyle.copyWith(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

/// Count the cash, say who it was handed to, and close the shift. Answers with the result: exact, short or over.
class _CloseSheet extends StatefulWidget {
  const _CloseSheet({required this.api, required this.shift});

  final SalonApi api;
  final SalonShift shift;

  @override
  State<_CloseSheet> createState() => _CloseSheetState();
}

class _CloseSheetState extends State<_CloseSheet> {
  final TextEditingController _counted = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _handedTo;
  bool _saving = false;
  String? _error;
  SalonShift? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<InventoryProvider>().fetchSalonStaff());
  }

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (_counted.text.trim().isEmpty) {
      setState(() => _error = sw ? 'Andika pesa uliyohesabu.' : 'Write the cash you counted.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final SalonShift done = await widget.api.closeShift(widget.shift.id, countedCash: parseAmount(_counted.text), handedToId: _handedTo, note: _note.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _result = done;
      });
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
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final SalonShift? done = _result;

    if (done != null) {
      final double diff = done.difference ?? 0;
      final String text = !done.hasDifference
          ? (sw ? 'Pesa ni sawa kabisa. Asante.' : 'The cash is exactly right. Thank you.')
          : diff < 0
              ? (sw ? 'Pesa ina upungufu wa ${tsh(-diff)}. Mmiliki ameambiwa.' : 'The cash is short by ${tsh(-diff)}. The owner has been told.')
              : (sw ? 'Pesa ina ziada ya ${tsh(diff)}. Mmiliki ameambiwa.' : 'The cash is over by ${tsh(diff)}. The owner has been told.');

      return InvSheetShell(
        title: sw ? 'Zamu imefungwa' : 'Shift closed',
        children: <Widget>[
          Text(text, key: const ValueKey<String>('shift_result'), style: ThemeConstants.bodyStyle.copyWith(color: done.hasDifference ? ThemeConstants.warningAmber : ThemeConstants.successGreen, fontWeight: FontWeight.w700)),
          SizedBox(height: 14.h),
          InvPrimaryButton(key: const ValueKey<String>('shift_done'), busy: false, label: 'OK', onPressed: () => Navigator.pop(context, true)),
        ],
      );
    }

    final List<Map<String, String>> staff = context.watch<InventoryProvider>().salonStaff.where((Map<String, String> s) => s['id'] != null).toList();

    return InvSheetShell(
      title: sw ? 'Funga zamu' : 'Close the shift',
      children: <Widget>[
        Text(sw ? 'Droo inapaswa kuwa na ${tsh(widget.shift.expectedCash)}' : 'The till should hold ${tsh(widget.shift.expectedCash)}', style: ThemeConstants.captionStyle),
        SizedBox(height: 8.h),
        InvTextField(key: const ValueKey<String>('shift_counted'), controller: _counted, label: sw ? 'Pesa taslimu uliyohesabu (TZS)' : 'Cash you counted (TZS)', keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[ThousandsFormatter()]),
        SizedBox(height: 10.h),
        Text(sw ? 'Umemkabidhi nani?' : 'Handed to', style: ThemeConstants.captionStyle),
        SizedBox(height: 4.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 4.h,
          children: <Widget>[
            for (final Map<String, String> s in staff)
              ChoiceChip(key: ValueKey<String>('handed_${s['id']}'), label: Text(s['name'] ?? ''), selected: _handedTo == s['id'], onSelected: (bool on) => setState(() => _handedTo = on ? s['id'] : null)),
          ],
        ),
        SizedBox(height: 10.h),
        InvTextField(key: const ValueKey<String>('shift_note'), controller: _note, label: sw ? 'Maelezo' : 'Note', isOptional: true),
        if (_error != null) Padding(padding: EdgeInsets.only(top: 10.h), child: Text(_error!, key: const ValueKey<String>('shift_error'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorText, fontSize: 12.sp))),
        SizedBox(height: 14.h),
        InvPrimaryButton(key: const ValueKey<String>('shift_save'), busy: _saving, label: sw ? 'Funga zamu' : 'Close shift', onPressed: _save),
      ],
    );
  }
}

/// Asks for the cash in the till. It owns its field, so the field is never used after it is thrown away (a field
/// disposed while the dialog is still sliding away would crash it).
class _OpenShiftDialog extends StatefulWidget {
  const _OpenShiftDialog();

  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  final TextEditingController _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(sw ? 'Fungua zamu' : 'Open a shift'),
      content: TextField(
        key: const ValueKey<String>('shift_float'),
        controller: _amount,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
        decoration: ThemeConstants.invInputDecoration(sw ? 'Pesa iliyopo kwenye droo (TZS)' : 'Cash in the till (TZS)'),
      ),
      actions: <Widget>[
        TextButton(key: const ValueKey<String>('shift_open_no'), onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        TextButton(key: const ValueKey<String>('shift_open_yes'), onPressed: () => Navigator.pop(context, parseAmount(_amount.text)), child: Text(sw ? 'Fungua' : 'Open')),
      ],
    );
  }
}
