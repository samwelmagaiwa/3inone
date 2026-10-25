import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import 'salon_text.dart';

/// The salon's reports on one page for a period: takings by service, stylist, way of payment and branch; spending by
/// category; how the diary went; the clients; what is still owed; and what the goods on the shelves are worth.
class SalonReportsScreen extends StatefulWidget {
  const SalonReportsScreen({super.key, this.api, this.today});

  final SalonApi? api;
  final DateTime? today;

  @override
  State<SalonReportsScreen> createState() => _SalonReportsScreenState();
}

class _SalonReportsScreenState extends State<SalonReportsScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  String _period = 'month';
  Map<String, dynamic> _d = <String, dynamic>{};
  String? _error;
  bool _loading = true;

  DateTime get _now {
    final DateTime n = widget.today ?? DateTime.now();

    return DateTime(n.year, n.month, n.day);
  }

  (DateTime, DateTime) _range() {
    final DateTime t = _now;
    switch (_period) {
      case 'today':
        return (t, t);
      case 'week':
        return (t.subtract(Duration(days: t.weekday - 1)), t);
      case 'year':
        return (DateTime(t.year), t);
      default:
        return (DateTime(t.year, t.month), t);
    }
  }

  List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[
        if (v is List)
          for (final dynamic r in v)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  Map<String, dynamic> _map(final dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final (DateTime, DateTime) r = _range();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> d = await _api.salonReports(r.$1, r.$2);
      if (!mounted) return;
      setState(() {
        _d = d;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _pick(final String p) {
    setState(() => _period = p);
    _load();
  }

  String _n(final dynamic v) => tsh((v as num?) ?? 0);

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!, key: const Key('sr_error')))
            : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: _body(sw)));
  }

  List<Widget> _body(final bool sw) {
    final Map<String, dynamic> s = _map(_d['summary']);
    final Map<String, dynamic> diary = _map(_d['diary']);
    final Map<String, dynamic> clients = _map(_d['clients']);
    final Map<String, dynamic> owed = _map(_d['owed']);
    final Map<String, dynamic> stock = _map(_d['stock']);
    final List<Map<String, dynamic>> branches = _list(_d['by_branch']);

    return <Widget>[
      Wrap(spacing: 8, children: <Widget>[
        for (final (String, String) p in <(String, String)>[('today', 'today'), ('week', 'this_week'), ('month', 'this_month'), ('year', 'this_year')])
          ChoiceChip(key: Key('sr_${p.$1}'), label: Text(LocalizationService.instance.translate(p.$2)), selected: _period == p.$1, onSelected: (_) => _pick(p.$1)),
      ]),
      const SizedBox(height: 12),
      _section(sw ? 'Muhtasari' : 'Summary', 'summary', <Widget>[
        _row(sw ? 'Mapato' : 'Revenue', _n(s['revenue']), key: 'sr_revenue'),
        _row(sw ? 'Huduma' : 'Services', _n(s['service_revenue'])),
        _row(sw ? 'Bidhaa' : 'Goods', _n(s['goods_revenue'])),
        _row(sw ? 'Punguzo' : 'Discounts', _n(s['discounts'])),
        _row(sw ? 'Matumizi' : 'Expenses', _n(s['expenses'])),
        _row(sw ? 'Kamisheni' : 'Commissions', _n(s['commissions'])),
        _row(sw ? 'Faida halisi' : 'Net profit', _n(s['net_profit']), bold: true, key: 'sr_profit'),
        _row(sw ? 'Mauzo / wateja' : 'Sales / clients', '${s['sales'] ?? 0} / ${s['clients'] ?? 0}'),
      ]),
      _section(sw ? 'Mapato kwa huduma' : 'Takings by service', 'service', <Widget>[
        for (final Map<String, dynamic> r in _list(_d['by_service'])) ...<Widget>[
          _row('${r['name']}  ×${r['times']}', _n(r['revenue'])),
          _profitLine(sw, <String>[
            if (((r['commission'] as num?) ?? 0) > 0) '${sw ? 'kamisheni' : 'commission'} ${_n(r['commission'])}',
            if (((r['materials_cost'] as num?) ?? 0) > 0) '${sw ? 'bidhaa zilizotumika' : 'goods used'} ${_n(r['materials_cost'])}',
          ], r['profit']),
        ],
        if (_list(_d['by_service']).isEmpty) _none(sw),
      ]),
      if (_list(_d['goods_sold']).isNotEmpty)
        _section(sw ? 'Bidhaa zilizouzwa na faida yake' : 'Goods sold and what they earned', 'goods', <Widget>[
          for (final Map<String, dynamic> r in _list(_d['goods_sold'])) ...<Widget>[
            _row('${r['name']}  ×${r['qty']}', _n(r['revenue'])),
            _profitLine(sw, <String>['${sw ? 'gharama' : 'cost'} ${_n(r['cost'])}'], r['profit']),
          ],
        ]),
      _section(sw ? 'Mapato kwa mhudumu' : 'Takings by stylist', 'stylist', <Widget>[
        for (final Map<String, dynamic> r in _list(_d['by_stylist'])) _row('${r['name']}  (${r['services']} · ${r['clients']} ${sw ? 'wateja' : 'clients'})', _n(r['revenue'])),
        if (_list(_d['by_stylist']).isEmpty) _none(sw),
      ]),
      _section(sw ? 'Pesa zilizopokelewa kwa njia' : 'Money received by way of payment', 'method', <Widget>[
        for (final Map<String, dynamic> r in _list(_d['by_method'])) _row(channelLabel(sw: sw, channel: '${r['method']}'), _n(r['amount'])),
        if (_list(_d['by_method']).isEmpty) _none(sw),
      ]),
      if (branches.isNotEmpty)
        _section(sw ? 'Kwa tawi' : 'By branch', 'branch', <Widget>[
          for (final Map<String, dynamic> r in branches) _row('${r['name']}  (${r['sales']} ${sw ? 'mauzo' : 'sales'})', _n(r['revenue'])),
        ]),
      _section(sw ? 'Matumizi kwa aina' : 'Spending by category', 'expenses', <Widget>[
        for (final Map<String, dynamic> r in _list(_d['expenses_by_category'])) _row('${r['category']}', _n(r['total'])),
        if (_list(_d['expenses_by_category']).isEmpty) _none(sw),
      ]),
      _section(sw ? 'Miadi' : 'Appointments', 'diary', <Widget>[
        _row(sw ? 'Zilizowekwa' : 'Booked', '${diary['booked'] ?? 0}', key: 'sr_booked'),
        _row(sw ? 'Zilizokamilika' : 'Done', '${diary['done'] ?? 0}'),
        _row(sw ? 'Hawakuja' : 'No-shows', '${diary['no_show'] ?? 0}${diary['no_show_rate'] == null ? '' : ' (${diary['no_show_rate']}%)'}', key: 'sr_noshow'),
        _row(sw ? 'Zilizoghairiwa' : 'Cancelled', '${diary['cancelled'] ?? 0}'),
        _row(sw ? 'Bado wazi' : 'Still open', '${diary['still_open'] ?? 0}'),
        _row(sw ? 'Zilizowekwa mtandaoni' : 'Booked online', '${diary['online'] ?? 0}'),
        _row(sw ? 'Amana zilizobaki' : 'Deposits kept', _n(diary['deposits_kept'])),
      ]),
      _section(sw ? 'Wateja' : 'Clients', 'clients', <Widget>[
        _row(sw ? 'Waliokuja' : 'Came', '${clients['active'] ?? 0}'),
        _row(sw ? 'Wapya' : 'New', '${clients['new'] ?? 0}', key: 'sr_new'),
        _row(sw ? 'Wanaorudi' : 'Returning', '${clients['returning'] ?? 0}'),
        _row(sw ? 'Hawajaja wiki ${clients['stopped_after_weeks'] ?? 8}+' : 'Not seen for ${clients['stopped_after_weeks'] ?? 8}+ weeks', '${clients['stopped_coming'] ?? 0}', key: 'sr_stopped'),
        _row(sw ? 'Siku ya kuzaliwa mwezi huu' : 'Birthdays this month', '${clients['birthdays_this_month'] ?? 0}'),
        if (_list(clients['top_spenders']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(sw ? 'Wanaotumia zaidi' : 'Best spenders', style: const TextStyle(fontWeight: FontWeight.bold))),
        for (final Map<String, dynamic> r in _list(clients['top_spenders'])) _row('${r['name']}  (${r['visits']})', _n(r['spent'])),
      ]),
      _section(sw ? 'Madeni ya wateja' : 'Owed by clients', 'owed', <Widget>[
        _row(sw ? 'Jumla' : 'Total', _n(owed['total']), bold: true, key: 'sr_owed'),
        for (final Map<String, dynamic> r in _list(owed['list'])) _row('${r['client']}  ·  ${r['days']} ${sw ? 'siku' : 'days'}', _n(r['due'])),
      ]),
      _section(sw ? 'Bidhaa zilizopo' : 'Goods on the shelves', 'stock', <Widget>[
        _row(sw ? 'Aina' : 'Items', '${stock['items'] ?? 0}'),
        _row(sw ? 'Thamani kwa gharama' : 'Worth at cost', _n(stock['at_cost']), key: 'sr_cost'),
        _row(sw ? 'Thamani kwa bei' : 'Worth at price', _n(stock['at_price'])),
        _row(sw ? 'Zinazoisha' : 'Running low', '${stock['low'] ?? 0}'),
      ]),
    ];
  }

  /// Under a service or goods line: what came off it (commission, goods used, cost) and the profit that is left.
  Widget _profitLine(final bool sw, final List<String> takenOff, final dynamic profit) => Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Row(children: <Widget>[
          Expanded(child: Text(takenOff.isEmpty ? '' : '− ${takenOff.join(' · ')}', style: const TextStyle(fontSize: 12, color: Colors.white70))),
          Text('${sw ? 'faida' : 'profit'} ${_n(profit)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.lightGreenAccent)),
        ]),
      );

  Widget _none(final bool sw) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(sw ? 'Hakuna kwa kipindi hiki.' : 'Nothing in this period.'));

  Widget _row(final String label, final String value, {final bool bold = false, final String? key}) => Padding(
        key: key == null ? null : Key(key),
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: <Widget>[
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ]),
      );

  Widget _section(final String title, final String id, final List<Widget> children) => Card(
        key: Key('sr_section_$id'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 6),
            ...children,
          ]),
        ),
      );
}
