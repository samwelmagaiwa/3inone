import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import 'salon_input.dart';
import 'salon_text.dart';
import '../widgets/inventory_widgets.dart';

/// The owner's cashbook: for cash, mobile money and bank, what was held at the start, what came in, what went out and
/// what should be held now, day by day. The owner puts money in or takes it out here (and sets the opening balance once),
/// and counts what is really held: a difference is shown and the owner is alerted.
class CashbookScreen extends StatefulWidget {
  const CashbookScreen({super.key, this.api, this.today});

  final SalonApi? api;
  final DateTime? today;

  @override
  State<CashbookScreen> createState() => _CashbookScreenState();
}

class _CashbookScreenState extends State<CashbookScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  String _period = 'month';
  Map<String, dynamic> _book = <String, dynamic>{};
  String? _error;
  bool _loading = true;

  static const List<String> places = <String>['cash', 'mobile', 'bank'];

  DateTime get _now {
    final DateTime n = widget.today ?? DateTime.now();

    return DateTime(n.year, n.month, n.day);
  }

  (DateTime, DateTime) _range() {
    final DateTime t = _now;
    if (_period == 'today') return (t, t);
    if (_period == 'last') return (DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0));

    return (DateTime(t.year, t.month), t);
  }

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
      final Map<String, dynamic> b = await _api.cashbook(r.$1, r.$2);
      if (!mounted) return;
      setState(() {
        _book = b;
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

  Map<String, dynamic> _place(final String p) => _book['places'] is Map && (_book['places'] as Map)[p] is Map ? Map<String, dynamic>.from((_book['places'] as Map)[p] as Map) : <String, dynamic>{};

  static String placeLabel(final String p, final bool sw) => p == 'cash' ? (sw ? 'Taslimu' : 'Cash') : (p == 'mobile' ? (sw ? 'Simu (M-Pesa, Mixx…)' : 'Mobile money') : (sw ? 'Benki' : 'Bank'));

  Future<void> _move() async {
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (BuildContext d) => const _MoveDialog());
    if (got == null || !mounted) return;
    await _run(() => _api.addCashMove(kind: got['kind'] as String, method: got['method'] as String, amount: got['amount'] as double, note: got['note'] as String?));
  }

  Future<void> _count() async {
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (BuildContext d) => const _CountDialog());
    if (got == null || !mounted) return;
    final bool sw = context.read<LocalizationService>().isSwahili;
    try {
      final Map<String, dynamic> r = await _api.countCash(method: got['method'] as String, counted: got['counted'] as double, note: got['note'] as String?);
      if (!mounted) return;
      final num diff = (r['difference'] as num?) ?? 0;
      await showDialog<void>(
        context: context,
        builder: (BuildContext d) => AlertDialog(
          title: Text(sw ? 'Matokeo ya kuhesabu' : 'Count result'),
          content: Text(
            diff == 0
                ? (sw ? 'Inalingana na kitabu.' : 'It matches the book.')
                : (sw ? 'Kitabu: ${tsh((r['expected'] as num?) ?? 0)}\nKilichohesabiwa: ${tsh(((r['expected'] as num?) ?? 0) + diff)}\nTofauti: ${diff < 0 ? '−' : '+'} ${tsh(diff.abs())}' : 'Book: ${tsh((r['expected'] as num?) ?? 0)}\nCounted: ${tsh(((r['expected'] as num?) ?? 0) + diff)}\nDifference: ${diff < 0 ? '−' : '+'} ${tsh(diff.abs())}'),
            key: const Key('count_result'),
          ),
          actions: <Widget>[TextButton(onPressed: () => Navigator.pop(d), child: Text(sw ? 'Sawa' : 'OK'))],
        ),
      );
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _run(final Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<Map<String, dynamic>> moves = <Map<String, dynamic>>[
      if (_book['moves'] is List)
        for (final dynamic m in _book['moves'] as List)
          if (m is Map) Map<String, dynamic>.from(m),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    Wrap(spacing: 8, children: <Widget>[
                      ChoiceChip(key: const Key('cb_today'), label: Text(sw ? 'Leo' : 'Today'), selected: _period == 'today', onSelected: (_) => _pick('today')),
                      ChoiceChip(key: const Key('cb_month'), label: Text(sw ? 'Mwezi huu' : 'This month'), selected: _period == 'month', onSelected: (_) => _pick('month')),
                      ChoiceChip(key: const Key('cb_last'), label: Text(sw ? 'Mwezi uliopita' : 'Last month'), selected: _period == 'last', onSelected: (_) => _pick('last')),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: <Widget>[
                      Expanded(child: FilledButton.icon(key: const Key('cb_move'), onPressed: _move, icon: const Icon(Icons.swap_vert), label: Text(sw ? 'Weka / Toa' : 'Put in / Take out'))),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(key: const Key('cb_count'), onPressed: _count, icon: const Icon(Icons.fact_check_outlined), label: Text(sw ? 'Hesabu' : 'Count'))),
                    ]),
                    const SizedBox(height: 8),
                    for (final String p in places) _placeCard(p, sw),
                    if (moves.isNotEmpty) ...<Widget>[
                      Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(sw ? 'Weka na toa za mmiliki' : 'Owner put in / took out', style: const TextStyle(fontWeight: FontWeight.bold))),
                      for (final Map<String, dynamic> m in moves)
                        ListTile(
                          key: Key('cb_move_${m['id']}'),
                          dense: true,
                          title: Text('${_kindLabel('${m['kind']}', sw)} · ${placeLabel('${m['method']}', sw)}'),
                          subtitle: Text('${m['moved_on']}${'${m['note'] ?? ''}'.isEmpty ? '' : ' · ${m['note']}'}'),
                          trailing: Text(tsh((m['amount'] as num?) ?? 0)),
                          onLongPress: () => _run(() => _api.deleteCashMove((m['id'] as num).toInt())),
                        ),
                    ],
                  ]),
                ),
    );
  }

  void _pick(final String p) {
    setState(() => _period = p);
    _load();
  }

  static String _kindLabel(final String k, final bool sw) => k == 'opening' ? (sw ? 'Salio la kuanzia' : 'Opening balance') : (k == 'owner_deposit' ? (sw ? 'Mmiliki ameweka' : 'Owner put in') : (sw ? 'Mmiliki amechukua' : 'Owner took out'));

  Widget _placeCard(final String p, final bool sw) {
    final Map<String, dynamic> d = _place(p);
    final List<Map<String, dynamic>> days = <Map<String, dynamic>>[
      if (d['days'] is List)
        for (final dynamic r in d['days'] as List)
          if (r is Map) Map<String, dynamic>.from(r),
    ];

    return Card(
      key: Key('cb_place_$p'),
      child: ExpansionTile(
        title: Text(placeLabel(p, sw), style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${sw ? 'Inapaswa kuwepo' : 'Should be held'}: ${tsh((d['closing'] as num?) ?? 0)}', key: Key('cb_closing_$p')),
        children: <Widget>[
          _row(sw ? 'Mwanzo' : 'Opening', (d['opening'] as num?) ?? 0),
          _row(sw ? 'Imeingia' : 'In', (d['in'] as num?) ?? 0),
          _row(sw ? 'Imetoka' : 'Out', (d['out'] as num?) ?? 0),
          for (final Map<String, dynamic> r in days)
            ListTile(
              dense: true,
              title: Text('${r['date']}'),
              subtitle: Text('${sw ? 'Ndani' : 'In'} ${tsh((r['in'] as num?) ?? 0)} · ${sw ? 'Nje' : 'Out'} ${tsh((r['out'] as num?) ?? 0)}${r['count'] == null ? '' : '\n${sw ? 'Imehesabiwa' : 'Counted'} ${tsh((r['count']['counted'] as num?) ?? 0)}'}'),
              isThreeLine: r['count'] != null,
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                Text(tsh((r['closing'] as num?) ?? 0)),
                if (r['count'] != null && ((r['count']['difference'] as num?) ?? 0) != 0)
                  Text('${((r['count']['difference'] as num) < 0) ? '−' : '+'} ${tsh((r['count']['difference'] as num).abs())}', style: TextStyle(color: (r['count']['difference'] as num) < 0 ? ThemeConstants.errorText : Colors.orange, fontSize: 12)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _row(final String label, final num v) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), child: Row(children: <Widget>[Expanded(child: Text(label)), Text(tsh(v))]));
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog();

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _kind = 'owner_deposit';
  String _method = 'cash';
  String? _problem;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(sw ? 'Weka au toa pesa' : 'Put in or take out money'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Wrap(spacing: 6, children: <Widget>[
            for (final String k in <String>['owner_deposit', 'owner_withdrawal', 'opening'])
              ChoiceChip(key: Key('mv_$k'), label: Text(_CashbookScreenState._kindLabel(k, sw)), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ]),
          Wrap(spacing: 6, children: <Widget>[
            for (final String p in _CashbookScreenState.places)
              ChoiceChip(key: Key('mv_place_$p'), label: Text(_CashbookScreenState.placeLabel(p, sw)), selected: _method == p, onSelected: (_) => setState(() => _method = p)),
          ]),
          TextField(style: salonInputStyle, key: const Key('mv_amount'), controller: _amount, keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[ThousandsFormatter()], decoration: salonInput(labelText: sw ? 'Kiasi (TSh)' : 'Amount (TSh)')),
          const SizedBox(height: 8),
          TextField(style: salonInputStyle, key: const Key('mv_note'), controller: _note, decoration: salonInput(labelText: sw ? 'Maelezo (si lazima)' : 'Note (optional)')),
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: TextStyle(color: ThemeConstants.errorText))),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(
          key: const Key('mv_save'),
          onPressed: () {
            final double? a = double.tryParse(_amount.text.replaceAll(',', '').trim());
            if (a == null || a <= 0) return setState(() => _problem = sw ? 'Weka kiasi.' : 'Enter an amount.');
            Navigator.pop(context, <String, dynamic>{'kind': _kind, 'method': _method, 'amount': a, 'note': _note.text.trim()});
          },
          child: Text(sw ? 'Hifadhi' : 'Save'),
        ),
      ],
    );
  }
}

class _CountDialog extends StatefulWidget {
  const _CountDialog();

  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  final TextEditingController _counted = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _method = 'cash';
  String? _problem;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(sw ? 'Hesabu ulichonacho' : 'Count what you hold'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Wrap(spacing: 6, children: <Widget>[
            for (final String p in _CashbookScreenState.places)
              ChoiceChip(key: Key('ct_place_$p'), label: Text(_CashbookScreenState.placeLabel(p, sw)), selected: _method == p, onSelected: (_) => setState(() => _method = p)),
          ]),
          TextField(style: salonInputStyle, key: const Key('ct_counted'), controller: _counted, keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[ThousandsFormatter()], decoration: salonInput(labelText: sw ? 'Kiasi ulichohesabu (TSh)' : 'Amount counted (TSh)')),
          const SizedBox(height: 8),
          TextField(style: salonInputStyle, key: const Key('ct_note'), controller: _note, decoration: salonInput(labelText: sw ? 'Maelezo (si lazima)' : 'Note (optional)')),
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: TextStyle(color: ThemeConstants.errorText))),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(
          key: const Key('ct_save'),
          onPressed: () {
            final double? a = double.tryParse(_counted.text.replaceAll(',', '').trim());
            if (a == null || a < 0) return setState(() => _problem = sw ? 'Weka kiasi ulichohesabu.' : 'Enter the amount counted.');
            Navigator.pop(context, <String, dynamic>{'method': _method, 'counted': a, 'note': _note.text.trim()});
          },
          child: Text(sw ? 'Linganisha' : 'Compare'),
        ),
      ],
    );
  }
}
