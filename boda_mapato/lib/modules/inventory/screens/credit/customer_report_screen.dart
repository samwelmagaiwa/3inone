import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/customer_report_api.dart';
import '../money/money_style.dart';
import '../widgets/inventory_widgets.dart' show formatAmount;

enum _Period { week, month, quarter, year, custom }

/// One customer's story for any period: how many times they bought, how much (and how much of it they paid), the profit they brought,
/// what they buy most, how it moved day by day, week by week or month by month, and what they owe now. Profit is shown only to people
/// whose rights include it (the server leaves it out for everyone else).
class CustomerReportScreen extends StatefulWidget {
  const CustomerReportScreen({super.key, required this.customerId, required this.name, this.api, this.today});

  final int customerId;
  final String name;
  final CustomerReportApi? api;

  /// Today, for tests; the real date (in Tanzania) otherwise.
  final DateTime? today;

  @override
  State<CustomerReportScreen> createState() => _CustomerReportScreenState();
}

class _CustomerReportScreenState extends State<CustomerReportScreen> {
  late final CustomerReportApi _api = widget.api ?? CustomerReportApi();
  late final DateTime _today = widget.today ?? _tanzaniaToday();
  _Period _period = _Period.month;
  String _group = 'week';
  late DateTime _from = DateTime(_today.year, _today.month, 1);
  late DateTime _to = _today;
  Map<String, dynamic> _r = <String, dynamic>{};
  bool _loading = true;
  String? _error;

  static DateTime _tanzaniaToday() {
    final DateTime eat = DateTime.now().toUtc().add(const Duration(hours: 3));

    return DateTime(eat.year, eat.month, eat.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _m(final dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[if (v is List) for (final dynamic e in v) if (e is Map) Map<String, dynamic>.from(e)];
  num _n(final dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
  String _tsh(final num v) => 'TSh ${formatAmount(v)}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> r = await _api.report(widget.customerId, from: _from, to: _to, group: _group);
      if (mounted) setState(() => _r = r);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _choose(final _Period p) async {
    if (p == _Period.custom) {
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: _today,
        initialDateRange: DateTimeRange(start: _from, end: _to),
      );
      if (picked == null || !mounted) return;
      _from = picked.start;
      _to = picked.end;
    } else {
      switch (p) {
        case _Period.week:
          _from = _today.subtract(Duration(days: _today.weekday - 1));
          _to = _today;
        case _Period.month:
          _from = DateTime(_today.year, _today.month, 1);
          _to = _today;
        case _Period.quarter:
          _from = DateTime(_today.year, _today.month - 2, 1);
          _to = _today;
        case _Period.year:
          _from = DateTime(_today.year, 1, 1);
          _to = _today;
        case _Period.custom:
          break;
      }
    }
    // Days for a week, weeks for a month, months for anything longer: the grouping that reads best (changeable below).
    _group = switch (p) { _Period.week => 'day', _Period.month => 'week', _ => 'month' };
    setState(() => _period = p);
    await _load();
  }

  Future<void> _regroup(final String g) async {
    setState(() => _group = g);
    await _load();
  }

  String _periodName(final _Period p, final bool sw) => switch (p) {
        _Period.week => sw ? 'Wiki hii' : 'This week',
        _Period.month => sw ? 'Mwezi huu' : 'This month',
        _Period.quarter => sw ? 'Miezi 3' : '3 months',
        _Period.year => sw ? 'Mwaka huu' : 'This year',
        _Period.custom => sw ? 'Chagua tarehe' : 'Pick dates',
      };

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(children: <Widget>[
        _bar(sw),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                  : RefreshIndicator(onRefresh: _load, child: _body(sw)),
        ),
      ]),
    );
  }

  Widget _bar(final bool sw) => SizedBox(
        height: 54,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: <Widget>[
            for (final _Period p in _Period.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(key: Key('period_${p.name}'), label: Text(_periodName(p, sw)), selected: _period == p, onSelected: (_) => _choose(p)),
              ),
          ],
        ),
      );

  Widget _section(final String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  Widget _card(final String label, final String value, {final Key? key, final Color? color, final String? note}) => Container(
        key: key,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(label, style: kMoneyCaption),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(note, style: kMoneyCaption.copyWith(fontSize: 11))),
        ]),
      );

  Widget _line(final String title, final String value, {final String? note, final Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            if (note != null && note.isNotEmpty) Text(note, style: kMoneyCaption),
          ])),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(color: Colors.white70)),
        ]),
      );

  Widget _body(final bool sw) {
    final Map<String, dynamic> totals = _m(_r['totals']);
    final Map<String, dynamic> debt = _m(_r['debt']);
    final Map<String, dynamic> life = _m(_r['lifetime']);
    final Map<String, dynamic> who = _m(_r['customer']);
    final bool profit = _r['profit_visible'] == true;
    final List<Map<String, dynamic>> periods = _list(_r['by_period']);
    final List<Map<String, dynamic>> products = _list(_r['top_products']);
    final List<Map<String, dynamic>> recent = _list(_r['recent_sales']);
    final num owes = _n(debt['owes_now']);

    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: <Widget>[
      Text('${who['phone'] ?? ''}${'${who['address'] ?? ''}'.isEmpty ? '' : '  ·  ${who['address']}'}', style: kMoneyCaption.copyWith(fontSize: 13)),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        Expanded(child: _card(sw ? 'Alichonunua' : 'Bought', _tsh(_n(totals['sales'])), key: const Key('cr_sales'), note: sw ? 'Mara ${_n(totals['purchases']).toInt()}' : '${_n(totals['purchases']).toInt()} purchases')),
        const SizedBox(width: 10),
        Expanded(child: _card(sw ? 'Alicholipa' : 'Paid', _tsh(_n(totals['paid'])), key: const Key('cr_paid'), color: ThemeConstants.successGreen)),
      ]),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        if (profit) ...<Widget>[
          Expanded(child: _card(sw ? 'Faida aliyoleta' : 'Profit they brought', _tsh(_n(totals['profit'])), key: const Key('cr_profit'), color: _n(totals['profit']) < 0 ? ThemeConstants.errorRed : ThemeConstants.successGreen, note: totals['margin_percent'] == null ? null : '${totals['margin_percent']}%')),
          const SizedBox(width: 10),
        ],
        Expanded(child: _card(sw ? 'Deni analodaiwa sasa' : 'Owes now', _tsh(owes), key: const Key('cr_owes'), color: owes > 0 ? ThemeConstants.warningAmber : Colors.white, note: _n(debt['from_before_app']) > 0 ? (sw ? 'pamoja na ${_tsh(_n(debt['from_before_app']))} za kabla ya programu' : 'incl. ${_tsh(_n(debt['from_before_app']))} from before the app') : null)),
      ]),
      _section(sw ? 'Kwa ${_group == 'day' ? 'siku' : (_group == 'week' ? 'wiki' : 'mwezi')}' : 'By ${_group == 'day' ? 'day' : (_group == 'week' ? 'week' : 'month')}'),
      Wrap(spacing: 8, children: <Widget>[
        for (final (String, String, String) g in <(String, String, String)>[('day', 'Siku', 'Day'), ('week', 'Wiki', 'Week'), ('month', 'Mwezi', 'Month')])
          ChoiceChip(key: Key('group_${g.$1}'), label: Text(sw ? g.$2 : g.$3), selected: _group == g.$1, onSelected: (_) => _regroup(g.$1)),
      ]),
      if (periods.isEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(sw ? 'Hakununua chochote katika kipindi hiki.' : 'Bought nothing in this period.', key: const Key('cr_none'), style: kMoneyCaption))
      else
        for (final Map<String, dynamic> p in periods)
          _line('${p['period']}', _tsh(_n(p['sales'])), key: Key('period_row_${p['period']}'), note: '${_n(p['purchases']).toInt()}${sw ? ' mara' : ' purchases'}${profit && p['profit'] != null ? (sw ? '  ·  faida ${_tsh(_n(p['profit']))}' : '  ·  profit ${_tsh(_n(p['profit']))}') : ''}'),
      if (products.isNotEmpty) ...<Widget>[
        _section(sw ? 'Anachonunua zaidi' : 'Buys most'),
        for (final Map<String, dynamic> p in products)
          _line('${p['name']}', _tsh(_n(p['sales'])), note: '${_n(p['qty'])}${profit && p['profit'] != null ? (sw ? '  ·  faida ${_tsh(_n(p['profit']))}' : '  ·  profit ${_tsh(_n(p['profit']))}') : ''}'),
      ],
      if (recent.isNotEmpty) ...<Widget>[
        _section(sw ? 'Manunuzi ya karibuni' : 'Recent purchases'),
        for (final Map<String, dynamic> s in recent)
          _line('${s['number']}', _tsh(_n(s['total'])), note: '${s['at']}  ·  ${s['status']}'),
      ],
      _section(sw ? 'Tangu ameanza kununua' : 'Since they first bought'),
      _line(sw ? 'Manunuzi yote' : 'All purchases', _tsh(_n(life['sales'])), key: const Key('cr_life'), note: '${_n(life['purchases']).toInt()}${sw ? ' mara' : ' times'}${life['first_purchase'] == null ? '' : (sw ? '  ·  ya kwanza ${life['first_purchase']}' : '  ·  first ${life['first_purchase']}')}'),
      if (profit && life['profit'] != null) _line(sw ? 'Faida yote aliyoleta' : 'All the profit they brought', _tsh(_n(life['profit']))),
    ]);
  }
}
