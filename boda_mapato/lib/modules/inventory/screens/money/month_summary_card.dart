import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../services/money_api.dart';
import 'money_style.dart';
import '../salon/salon_text.dart';
import 'monthly_report_screen.dart';

/// The month so far, on the dashboard: this month's profit, whether it is ahead of last month (with the percentage) and how
/// close the profit target is. A tap opens the whole report. Quiet when the numbers cannot be loaded.
class MonthSummaryCard extends StatefulWidget {
  const MonthSummaryCard({super.key, this.api});

  final MoneyApi? api;

  @override
  State<MonthSummaryCard> createState() => _MonthSummaryCardState();
}

class _MonthSummaryCardState extends State<MonthSummaryCard> {
  late final MoneyApi _api = widget.api ?? MoneyApi();
  Map<String, dynamic>? _r;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> r = await _api.monthlyReport();
      if (mounted && r.isNotEmpty) setState(() => _r = r);
    } on Exception {
      // The dashboard is the point of this page; the card is a bonus.
    }
  }

  Map<String, dynamic> _m(final dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  num _n(final dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? r = _r;
    if (r == null) return const SizedBox.shrink();
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final Map<String, dynamic> f = _m(r['figures']);
    final Map<String, dynamic> o = _m(r['overall']);
    final String dir = '${o['direction']}';
    final num? pct = o['percent'] is num ? o['percent'] as num : null;
    final Color color = dir == 'up' ? ThemeConstants.successGreen : (dir == 'down' ? ThemeConstants.errorRed : Colors.blueGrey);
    final IconData icon = dir == 'up' ? Icons.trending_up_rounded : (dir == 'down' ? Icons.trending_down_rounded : Icons.trending_flat_rounded);
    final Map<String, dynamic>? t = r['target'] is Map ? _m(r['target']) : null;
    final String pctText = pct == null ? '' : '${pct > 0 ? '+' : '-'}${pct.abs().toStringAsFixed(pct.abs() >= 10 ? 0 : 1)}%';

    return Card(
      key: const Key('month_summary'),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MonthlyReportScreen(api: widget.api))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Expanded(child: Text(monthName('${r['month']}', sw: sw), style: kMoneyCaption)),
              Text(sw ? 'Ripoti kamili' : 'Full report', style: const TextStyle(color: ThemeConstants.invAccent, fontSize: 12, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right, size: 18, color: ThemeConstants.invAccent),
            ]),
            const SizedBox(height: 4),
            Row(children: <Widget>[
              Expanded(child: Text(tsh(_n(f['net_profit'])), key: const Key('month_profit'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _n(f['net_profit']) < 0 ? ThemeConstants.errorText : Colors.white))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 4),
                  Text(dir == 'same' ? (sw ? 'Pale pale' : 'Same') : pctText, key: const Key('month_trend'), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            Text(sw ? 'Faida ya mwezi huu · ${dir == 'up' ? 'mbele ya' : dir == 'down' ? 'nyuma ya' : 'sawa na'} mwezi uliopita' : 'Profit this month · ${dir == 'up' ? 'ahead of' : dir == 'down' ? 'behind' : 'level with'} last month', style: kMoneyCaption),
            if (t != null) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(key: const Key('month_target_bar'), value: (_n(t['progress_percent']) / 100).clamp(0.0, 1.0).toDouble(), minHeight: 7, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>('${t['status']}' == 'behind' || '${t['status']}' == 'missed' ? ThemeConstants.errorRed : ThemeConstants.successGreen))),
              const SizedBox(height: 4),
              Text('${sw ? 'Lengo' : 'Target'} ${shortMoney(_n(t['profit_target']))}  ·  ${_n(t['progress_percent']).round()}%  ·  ${switch ('${t['status']}') {
                'reached' => sw ? 'limefikiwa' : 'reached',
                'on_track' => sw ? 'kwenye njia' : 'on track',
                'behind' => sw ? 'uko nyuma' : 'behind',
                _ => ''
              }}', key: const Key('month_target_text'), style: kMoneyCaption),
            ],
          ]),
        ),
      ),
    );
  }
}
