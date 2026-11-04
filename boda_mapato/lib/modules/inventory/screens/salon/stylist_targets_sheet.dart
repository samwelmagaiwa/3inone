import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import 'salon_text.dart';

/// What the owner expects each person to bring in for a month: one amount per person, saved together. An empty box (or 0) means "no target",
/// and the people not touched keep theirs.
class StylistTargetsSheet extends StatefulWidget {
  const StylistTargetsSheet({super.key, required this.api, required this.month});

  final SalonApi api;

  /// The month as `2026-11`.
  final String month;

  @override
  State<StylistTargetsSheet> createState() => _StylistTargetsSheetState();
}

class _StylistTargetsSheetState extends State<StylistTargetsSheet> {
  StylistTargets? _data;
  String? _error;
  bool _saving = false;
  final Map<String, TextEditingController> _boxes = <String, TextEditingController>{};
  final Map<String, String> _first = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final TextEditingController c in _boxes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final StylistTargets data = await widget.api.stylistTargets(widget.month);
      if (!mounted) return;
      for (final TargetPerson p in data.people) {
        final String text = p.target == null ? '' : p.target!.amount.toStringAsFixed(0);
        _first[p.staffId] = text;
        _boxes[p.staffId] = TextEditingController(text: text);
      }
      setState(() => _data = data);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  double _amount(final String text) => double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  Future<void> _save() async {
    // Only the people whose box was changed are sent.
    final Map<String, double> changed = <String, double>{
      for (final MapEntry<String, TextEditingController> e in _boxes.entries)
        if (e.value.text.trim() != _first[e.key]) e.key: _amount(e.value.text),
    };
    if (changed.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.saveStylistTargets(widget.month, changed);
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
      }
    }
  }

  String _monthName(final bool sw) {
    final List<String> en = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final List<String> swa = <String>['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'];
    final List<String> parts = widget.month.split('-');
    final int m = int.tryParse(parts.length == 2 ? parts[1] : '') ?? 1;

    return '${(sw ? swa : en)[(m - 1).clamp(0, 11)]} ${parts.first}';
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final StylistTargets? data = _data;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(color: ThemeConstants.primaryBlue, borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)), border: Border.all(color: Colors.white24)),
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(child: Container(width: 40.w, height: 4.h, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4.r)))),
              SizedBox(height: 12.h),
              Text(sw ? 'Malengo ya ${_monthName(sw)}' : 'Targets for ${_monthName(sw)}', key: const ValueKey<String>('targets_title'), style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w800)),
              SizedBox(height: 4.h),
              Text(
                sw ? 'Andika mapato ambayo kila mtu anatarajiwa kuleta kwa mwezi. Sanduku tupu ni bila lengo.' : 'Write what each person is expected to bring in for the month. An empty box means no target.',
                style: ThemeConstants.captionStyle,
              ),
              SizedBox(height: 12.h),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  child: Column(children: <Widget>[
                    Text(_error!, key: const ValueKey<String>('targets_error'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                    TextButton(onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white))),
                  ]),
                )
              else if (data == null)
                Padding(padding: EdgeInsets.all(24.w), child: const Center(child: CircularProgressIndicator()))
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final TargetPerson p in data.people)
                        Padding(
                          padding: EdgeInsets.only(bottom: 10.h),
                          child: Row(children: <Widget>[
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                                Text(p.name, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                                Text(
                                  p.target == null ? p.role.replaceAll('_', ' ') : '${sw ? 'Sasa' : 'Now'} ${tsh(p.target!.achieved)} (${p.target!.percent.toStringAsFixed(0)}%)',
                                  style: ThemeConstants.captionStyle,
                                ),
                              ]),
                            ),
                            SizedBox(
                              width: 140.w,
                              child: TextField(
                                key: ValueKey<String>('target_box_${p.staffId}'),
                                controller: _boxes[p.staffId],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: sw ? 'Bila lengo' : 'No target',
                                  hintStyle: const TextStyle(color: Colors.white38),
                                  prefixText: 'TSh ',
                                  prefixStyle: const TextStyle(color: Colors.white54),
                                  isDense: true,
                                  filled: true,
                                  fillColor: ThemeConstants.invFill,
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: const BorderSide(color: Colors.white24)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: const BorderSide(color: Colors.white70)),
                                ),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
              SizedBox(height: 8.h),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('targets_save'),
                  onPressed: data == null || _saving ? null : _save,
                  child: _saving ? SizedBox(width: 18.r, height: 18.r, child: const CircularProgressIndicator(strokeWidth: 2)) : Text(sw ? 'Hifadhi malengo' : 'Save targets'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
