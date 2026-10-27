import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/branch_team_api.dart';
import '../money/money_style.dart';
import '../widgets/inventory_widgets.dart' show formatAmount;

enum _Period { week, month, quarter, year }

/// What each branch sold and what each person sold (first tab), and who works in which branch (second tab, for whoever may change
/// settings). A person's branch is where their sales are recorded when no other branch is chosen. Profit appears only when the
/// server sends it.
class BranchSalesScreen extends StatefulWidget {
  const BranchSalesScreen({super.key, this.api, this.manage, this.today});

  final BranchTeamApi? api;

  /// Whoever may change settings can also place people in branches. Null = try, and show the second tab only if the server allows it.
  final bool? manage;

  /// Today, for tests; the real date (in Tanzania) otherwise.
  final DateTime? today;

  @override
  State<BranchSalesScreen> createState() => _BranchSalesScreenState();
}

class _BranchSalesScreenState extends State<BranchSalesScreen> {
  late final BranchTeamApi _api = widget.api ?? BranchTeamApi();
  late final DateTime _today = widget.today ?? _tanzaniaToday();
  _Period _period = _Period.month;
  Map<String, dynamic> _r = <String, dynamic>{};
  List<Map<String, dynamic>> _team = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _branches = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  bool _manage = false;

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

  DateTime get _from => switch (_period) {
        _Period.week => _today.subtract(Duration(days: _today.weekday - 1)),
        _Period.month => DateTime(_today.year, _today.month, 1),
        _Period.quarter => DateTime(_today.year, _today.month - 2, 1),
        _Period.year => DateTime(_today.year, 1, 1),
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> r = await _api.sales(_from, _today);
      List<Map<String, dynamic>> team = <Map<String, dynamic>>[];
      List<Map<String, dynamic>> branches = <Map<String, dynamic>>[];
      bool manage = false;
      if (widget.manage != false) {
        try {
          team = await _api.team();
          branches = (await _api.branches()).where((Map<String, dynamic> b) => b['active'] == true).toList();
          manage = true;
        } on Exception {
          manage = false; // not allowed to place people: the sales tab is all there is
        }
      }
      if (mounted) {
        setState(() {
          _r = r;
          _team = team;
          _branches = branches;
          _manage = manage;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _place(final Map<String, dynamic> member, final int? branchId) async {
    try {
      await _api.assign('${member['staff_id']}', branchId);
      await _load();
    } on Exception catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(readableErrorMessage(e))));
    }
  }

  String _periodName(final _Period p, final bool sw) => switch (p) {
        _Period.week => sw ? 'Wiki hii' : 'This week',
        _Period.month => sw ? 'Mwezi huu' : 'This month',
        _Period.quarter => sw ? 'Miezi 3' : '3 months',
        _Period.year => sw ? 'Mwaka huu' : 'This year',
      };

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return DefaultTabController(
      key: ValueKey<bool>(_manage),
      length: _manage ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(sw ? 'Mauzo kwa tawi na mtu' : 'Sales by branch and person'),
          bottom: _manage ? TabBar(tabs: <Widget>[Tab(text: sw ? 'Mauzo' : 'Sales'), Tab(text: sw ? 'Watu' : 'People')]) : null,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                : TabBarView(children: <Widget>[_salesTab(sw), if (_manage) _peopleTab(sw)]),
      ),
    );
  }

  Widget _line(final String title, final String value, {final String? note, final Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            if (note != null && note.isNotEmpty) Text(note, style: kMoneyCaption),
          ])),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(color: Colors.white70)),
        ]),
      );

  Widget _section(final String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
        child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
      );

  String _cellNote(final Map<String, dynamic> c, final bool sw) =>
      '${_n(c['sales_count']).toInt()}${sw ? ' mauzo' : ' sales'}  ·  ${sw ? 'zimelipwa' : 'paid'} ${_tsh(_n(c['paid']))}${c['profit'] == null ? '' : (sw ? '  ·  faida ${_tsh(_n(c['profit']))}' : '  ·  profit ${_tsh(_n(c['profit']))}')}';

  Widget _salesTab(final bool sw) {
    final Map<String, dynamic> total = _m(_r['total']);
    final String none = sw ? 'Bila tawi' : 'No branch';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: <Widget>[
        Wrap(spacing: 8, children: <Widget>[
          for (final _Period p in _Period.values)
            ChoiceChip(key: Key('period_${p.name}'), label: Text(_periodName(p, sw)), selected: _period == p, onSelected: (_) {
              setState(() => _period = p);
              _load();
            }),
        ]),
        const SizedBox(height: 10),
        _line(sw ? 'Jumla iliyouzwa' : 'Total sold', _tsh(_n(total['sales'])), key: const Key('bs_total'), note: '${_n(total['sales_count']).toInt()}${sw ? ' mauzo' : ' sales'}  ·  ${sw ? 'zimelipwa' : 'paid'} ${_tsh(_n(total['paid']))}'),
        _section(sw ? 'Kwa tawi' : 'By branch'),
        if (_list(_r['by_branch']).isEmpty) Text(sw ? 'Hakuna kilichouzwa katika kipindi hiki.' : 'Nothing sold in this period.', key: const Key('bs_none'), style: kMoneyCaption),
        for (final Map<String, dynamic> b in _list(_r['by_branch'])) ...<Widget>[
          _line('${b['name'] ?? none}', _tsh(_n(b['sales'])), key: Key('branch_${b['branch_id'] ?? 0}'), note: _cellNote(b, sw)),
          for (final Map<String, dynamic> s in _list(b['staff'])) Padding(padding: const EdgeInsets.only(left: 14), child: _line('${s['name']}', _tsh(_n(s['sales'])), note: _cellNote(s, sw))),
        ],
        _section(sw ? 'Kwa mtu' : 'By person'),
        for (final Map<String, dynamic> s in _list(_r['by_staff'])) ...<Widget>[
          _line('${s['name']}', _tsh(_n(s['sales'])), key: Key('staff_${s['staff_id']}'), note: _cellNote(s, sw)),
          for (final Map<String, dynamic> b in _list(s['branches'])) Padding(padding: const EdgeInsets.only(left: 14), child: _line('${b['name'] ?? none}', _tsh(_n(b['sales'])), note: _cellNote(b, sw))),
        ],
      ]),
    );
  }

  Widget _peopleTab(final bool sw) => ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: <Widget>[
        Text(
          sw
              ? 'Mweke kila mtu kwenye tawi analofanyia kazi. Mauzo yake yanarekodiwa humo asipochagua tawi lingine.'
              : 'Place each person in the branch they work in. Their sales are recorded there when no other branch is chosen.',
          style: kMoneyCaption,
        ),
        if (_branches.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(sw ? 'Ongeza tawi kwanza (menyu ya Matawi).' : 'Add a branch first (Branches menu).', key: const Key('bp_nobranches'), style: const TextStyle(color: Colors.amber))),
        for (final Map<String, dynamic> m in _team)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: <Widget>[
              Expanded(child: Text('${m['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
              DropdownButton<int?>(
                key: Key('place_${m['staff_id']}'),
                value: _branches.any((Map<String, dynamic> b) => b['id'] == m['branch_id']) ? m['branch_id'] as int? : null,
                items: <DropdownMenuItem<int?>>[
                  DropdownMenuItem<int?>(value: null, child: Text(sw ? 'Hana tawi' : 'No branch')),
                  for (final Map<String, dynamic> b in _branches) DropdownMenuItem<int?>(value: b['id'] as int, child: Text('${b['name']}')),
                ],
                onChanged: (final int? v) => _place(m, v),
              ),
            ]),
          ),
      ]);
}
