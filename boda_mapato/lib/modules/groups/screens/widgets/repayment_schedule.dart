import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';

/// How often a loan is repaid. The group chooses one rhythm for its loans (each loan keeps the one it was applied under).

const List<String> repaymentChoices = <String>['daily', 'weekly', 'every_2_weeks', 'monthly', 'every_2_months', 'quarterly', 'every_6_months', 'custom'];

/// "Every week", "Kila miezi mitatu", "Every 10 days".
String repaymentLabel({required final bool sw, required final String every, final int? days}) => switch (every) {
      'daily' => sw ? 'Kila siku' : 'Every day',
      'weekly' => sw ? 'Kila wiki' : 'Every week',
      'every_2_weeks' => sw ? 'Kila wiki mbili' : 'Every 2 weeks',
      'every_2_months' => sw ? 'Kila miezi miwili' : 'Every 2 months',
      'quarterly' => sw ? 'Kila miezi mitatu' : 'Every 3 months',
      'every_6_months' => sw ? 'Kila miezi sita' : 'Every 6 months',
      'custom' => sw ? 'Kila siku ${days ?? 30}' : 'Every ${days ?? 30} days',
      _ => sw ? 'Kila mwezi' : 'Every month',
    };

/// One line saying what the rhythm means.
String repaymentDetail({required final bool sw, required final String every}) => switch (every) {
      'daily' => sw ? 'Kulipa kidogo kila siku, kuanzia kesho baada ya kukopa leo.' : 'A little each day, starting tomorrow after borrowing today.',
      'weekly' => sw ? 'Malipo kila wiki; la kwanza wiki moja baada ya kukopa.' : 'A payment every week; the first one a week after borrowing.',
      'every_2_weeks' => sw ? 'Malipo kila baada ya wiki mbili.' : 'A payment after every two weeks.',
      'every_2_months' => sw ? 'Malipo kila baada ya miezi miwili.' : 'A payment after every two months.',
      'quarterly' => sw ? 'Malipo kila baada ya miezi mitatu (robo mwaka).' : 'A payment after every three months (every quarter).',
      'every_6_months' => sw ? 'Malipo kila baada ya miezi sita (nusu mwaka).' : 'A payment after every six months (twice a year).',
      'custom' => sw ? 'Chagua mwenyewe idadi ya siku kati ya malipo.' : 'You choose the number of days between payments.',
      _ => sw ? 'Malipo kila mwezi; la kwanza mwezi mmoja baada ya kukopa.' : 'A payment every month; the first one a month after borrowing.',
    };

IconData repaymentIcon(final String every) => switch (every) {
      'daily' => Icons.today_rounded,
      'weekly' => Icons.view_week_rounded,
      'every_2_weeks' => Icons.date_range_rounded,
      'every_2_months' || 'quarterly' => Icons.calendar_view_month_rounded,
      'every_6_months' => Icons.event_repeat_rounded,
      'custom' => Icons.tune_rounded,
      _ => Icons.calendar_month_rounded,
    };

/// The day the first payment falls for a loan taken on [from]: one period later.
DateTime repaymentFirstDue(final DateTime from, final String every, final int? days) {
  DateTime months(final int n) {
    final int total = from.month - 1 + n;
    final int y = from.year + total ~/ 12;
    final int m = total % 12 + 1;
    final int last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, from.day > last ? last : from.day);
  }

  return switch (every) {
    'daily' => from.add(const Duration(days: 1)),
    'weekly' => from.add(const Duration(days: 7)),
    'every_2_weeks' => from.add(const Duration(days: 14)),
    'every_2_months' => months(2),
    'quarterly' => months(3),
    'every_6_months' => months(6),
    'custom' => from.add(Duration(days: (days ?? 30).clamp(1, 365))),
    _ => months(1),
  };
}

String _day(final DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// The tile in the settings: what is chosen now, and a tap opens the cards to choose from.
class RepaymentTile extends StatelessWidget {
  const RepaymentTile({required this.every, required this.days, required this.onTap, super.key});

  final String every;
  final int days;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return InkWell(
      key: const Key('grp_rep_open'),
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white.withValues(alpha: 0.05), border: Border.all(color: Colors.white24)),
        child: Row(children: <Widget>[
          CircleAvatar(radius: 20, backgroundColor: ThemeConstants.invAccent.withValues(alpha: 0.25), child: Icon(repaymentIcon(every), color: Colors.white, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(sw ? 'Ratiba ya marejesho' : 'Repayment schedule', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 2),
              Text(repaymentLabel(sw: sw, every: every, days: days), key: const Key('grp_rep_current'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
          const Icon(Icons.unfold_more_rounded, color: Colors.white54),
        ]),
      ),
    );
  }
}

/// A sheet of cards, one for each way of repaying, each with what it means and a worked first date; the chosen one is marked. Returns the
/// choice and, for "every N days", the number of days; null when closed without choosing.
Future<(String, int)?> showRepaymentPicker(final BuildContext context, {required final String every, required final int days}) =>
    showModalBottomSheet<(String, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (final BuildContext c) => _RepaymentSheet(every: every, days: days),
    );

class _RepaymentSheet extends StatefulWidget {
  const _RepaymentSheet({required this.every, required this.days});

  final String every;
  final int days;

  @override
  State<_RepaymentSheet> createState() => _RepaymentSheetState();
}

class _RepaymentSheetState extends State<_RepaymentSheet> {
  late String _every = widget.every;
  late final TextEditingController _days = TextEditingController(text: '${widget.days}');
  String? _problem;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  int get _n => int.tryParse(_days.text.trim()) ?? 0;

  void _use(final bool sw) {
    if (_every == 'custom' && (_n < 1 || _n > 365)) {
      setState(() => _problem = sw ? 'Siku ziwe kati ya 1 na 365.' : 'Days must be between 1 and 365.');
      return;
    }
    Navigator.pop(context, (_every, _every == 'custom' ? _n : widget.days));
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final DateTime today = DateTime.now();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(sw ? 'Mikopo hurejeshwa mara ngapi?' : 'How often is a loan repaid?', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD166), fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(sw ? 'Kila mkopo unabaki na ratiba aliyoombea. Mabadiliko yanaathiri mikopo mipya tu.' : 'Each loan keeps the schedule it was applied under. A change only affects new loans.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: <Widget>[
                  for (final String o in repaymentChoices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        key: Key('grp_rep_opt_$o'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() {
                          _every = o;
                          _problem = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: _every == o ? ThemeConstants.invAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
                            border: Border.all(color: _every == o ? Colors.white : Colors.white24, width: _every == o ? 1.8 : 1),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            CircleAvatar(radius: 20, backgroundColor: ThemeConstants.invAccent.withValues(alpha: 0.3), child: Icon(repaymentIcon(o), color: Colors.white, size: 20)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                                Text(o == 'custom' ? (sw ? 'Siku nyingine (chagua)' : 'Another number of days') : repaymentLabel(sw: sw, every: o), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(repaymentDetail(sw: sw, every: o), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(height: 6),
                                Text(
                                  '${sw ? 'Mfano: kukopa' : 'Example: borrow'} ${_day(today)} → ${sw ? 'malipo ya kwanza' : 'first payment'} ${_day(repaymentFirstDue(today, o, o == 'custom' ? (_n < 1 ? widget.days : _n) : null))}',
                                  key: Key('grp_rep_example_$o'),
                                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                                ),
                                if (o == 'custom' && _every == 'custom')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: TextField(
                                      key: const Key('grp_rep_days'),
                                      controller: _days,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                                      onChanged: (_) => setState(() => _problem = null),
                                      style: const TextStyle(color: Colors.white),
                                      decoration: ThemeConstants.darkField(sw ? 'Siku kati ya malipo (1 hadi 365)' : 'Days between payments (1 to 365)'),
                                    ),
                                  ),
                              ]),
                            ),
                            Icon(_every == o ? Icons.check_circle_rounded : Icons.circle_outlined, color: _every == o ? ThemeConstants.successGreen : Colors.white30),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_problem != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 6), child: Text(_problem!, key: const Key('grp_rep_problem'), style: const TextStyle(color: ThemeConstants.errorText))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('grp_rep_use'),
                  style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => _use(sw),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(sw ? 'Tumia ratiba hii' : 'Use this schedule'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
