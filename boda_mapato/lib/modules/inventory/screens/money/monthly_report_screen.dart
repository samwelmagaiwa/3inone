import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/money_api.dart';
import 'money_style.dart';
import '../salon/salon_input.dart';
import '../salon/salon_text.dart';
import 'debts_screen.dart';

const List<String> _monthsEn = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const List<String> _monthsSw = <String>['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'];

/// "2026-11" -> "November 2026" / "Novemba 2026".
String monthName(final String key, {required final bool sw}) {
  final List<String> p = key.split('-');
  final int m = int.tryParse(p.length > 1 ? p[1] : '') ?? 1;

  return '${(sw ? _monthsSw : _monthsEn)[(m - 1).clamp(0, 11)]} ${p.first}';
}

/// Money in short form for a headline: 1,250,000 -> "1.25M", 45,000 -> "45K".
String shortMoney(final num n) {
  final double a = n.abs().toDouble();
  final String sign = n < 0 ? '-' : '';
  String trim(final double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  if (a >= 1000000) return '${sign}TSH ${trim(a / 1000000)}M';
  if (a >= 10000) return '${sign}TSH ${trim(a / 1000)}K';

  return tsh(n);
}

/// A month of the business on one page: how it compares with the month before, the profit target, the money figures, where
/// the business stands (stock, debts, capital), spending, the products and customers behind the numbers, and advice on where
/// to do better.
class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key, this.api, this.month, this.today});

  final MoneyApi? api;

  /// Today, for tests; the real date otherwise.
  final DateTime? today;

  /// `2026-11`; null = this month.
  final String? month;

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  late final MoneyApi _api = widget.api ?? MoneyApi();
  late final DateTime _today = widget.today ?? DateTime.now();
  late String _month = widget.month ?? MoneyApi.monthKey(_today);
  Map<String, dynamic> _r = <String, dynamic>{};
  Map<String, dynamic>? _advice;
  String? _error;
  String? _adviceError;
  bool _loading = true;
  bool _adviceLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Map<String, dynamic> _m(final dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[
        if (v is List)
          for (final dynamic r in v)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  num _n(final dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  String _shift(final int by) {
    final List<String> p = _month.split('-');
    final DateTime d = DateTime(int.parse(p[0]), int.parse(p[1]) + by);

    return MoneyApi.monthKey(d);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _advice = null;
      _adviceError = null;
    });
    try {
      final Map<String, dynamic> r = await _api.monthlyReport(_month);
      if (!mounted) return;
      setState(() {
        _r = r;
        _loading = false;
      });
      _loadAdvice();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadAdvice({final bool refresh = false}) async {
    if (_m(_r)['is_future'] == true) return;
    setState(() {
      _adviceLoading = true;
      _adviceError = null;
    });
    try {
      final Map<String, dynamic> a = await _api.advice(_month, LocalizationService.instance.isSwahili ? 'sw' : 'en', refresh: refresh);
      if (mounted) setState(() => _advice = a);
    } on Exception catch (e) {
      if (mounted) setState(() => _adviceError = readableErrorMessage(e));
    }
    if (mounted) setState(() => _adviceLoading = false);
  }

  Future<void> _editTarget() async {
    final Map<String, dynamic>? t = _r['target'] is Map ? _m(_r['target']) : null;
    final double? value = await showDialog<double>(
      context: context,
      builder: (BuildContext d) => _TargetDialog(month: _month, current: t == null ? null : _n(t['profit_target']).round()),
    );
    if (value == null || !mounted) return;
    try {
      await _api.setTarget(_month, value);
      if (mounted) await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    // The report can be read up to the next month, so a target can be set before it begins.
    final bool canNext = _month.compareTo(MoneyApi.monthKey(DateTime(_today.year, _today.month + 1))) < 0;

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Ripoti ya mwezi' : 'Monthly report')),
      body: Column(children: <Widget>[
        _monthBar(sw, canNext),
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

  Widget _monthBar(final bool sw, final bool canNext) => Container(
        color: Colors.black12,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: <Widget>[
          IconButton(key: const Key('month_prev'), icon: const Icon(Icons.chevron_left), onPressed: _loading ? null : () {
            setState(() => _month = _shift(-1));
            _load();
          }),
          Expanded(child: Text(monthName(_month, sw: sw), key: const Key('month_title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))),
          IconButton(key: const Key('month_next'), icon: const Icon(Icons.chevron_right), onPressed: _loading || !canNext ? null : () {
            setState(() => _month = _shift(1));
            _load();
          }),
        ]),
      );

  Widget _body(final bool sw) {
    final Map<String, dynamic> f = _m(_r['figures']);
    final Map<String, dynamic> cmp = _m(_r['compare']);
    final Map<String, dynamic> pos = _r['position'] is Map ? _m(_r['position']) : <String, dynamic>{};
    final bool hasPos = _r['position'] is Map;
    final bool future = _r['is_future'] == true;
    final List<Map<String, dynamic>> cats = _list(f['expenses_by_category']);
    final num spendTotal = _n(f['expenses']);
    final String prevMonth = '${_m(_r['previous'])['month'] ?? ''}';

    return ListView(
      key: const Key('report_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        if (!future) _headline(sw, prevMonth),
        _targetCard(sw),
        _section(sw ? 'Hesabu za mwezi' : 'The month in numbers'),
        Row(children: <Widget>[
          Expanded(child: _figure('fig_sales', sw ? 'Mauzo' : 'Sales', _n(f['sales']), cmp['sales'] is Map ? _m(cmp['sales']) : null)),
          const SizedBox(width: 8),
          Expanded(child: _figure('fig_cogs', sw ? 'Gharama ya bidhaa' : 'Cost of goods', _n(f['cost_of_goods']), null)),
        ]),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(child: _figure('fig_gross', sw ? 'Faida ya mauzo' : 'Gross profit', _n(f['gross_profit']), cmp['gross_profit'] is Map ? _m(cmp['gross_profit']) : null, note: f['margin_percent'] == null ? null : '${f['margin_percent']}%')),
          const SizedBox(width: 8),
          Expanded(child: _figure('fig_expenses', sw ? 'Matumizi ya biashara' : 'Business expenses', _n(f['expenses']), cmp['expenses'] is Map ? _m(cmp['expenses']) : null)),
        ]),
        const SizedBox(height: 8),
        _figure('fig_net', sw ? 'Faida halisi' : 'Net profit', _n(f['net_profit']), cmp['net_profit'] is Map ? _m(cmp['net_profit']) : null, big: true),
        // In plain words, for someone who does not keep books: how the profit is worked out.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            sw ? 'Faida halisi = Mauzo − Gharama ya bidhaa − Matumizi ya biashara. Matumizi binafsi hayaondolewi kwenye faida.' : 'Net profit = Sales − Cost of goods − Business expenses. Personal spending is not taken off the profit.',
            key: const Key('hint_net'),
            style: kMoneyCaption,
          ),
        ),
        _section(sw ? 'Biashara ilipo' : 'Where the business stands'),
        if (!hasPos)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(sw ? 'Hesabu za mali, madeni na mtaji zinaanza kuhifadhiwa tangu unapofungua ripoti hii kwa mara ya kwanza.' : 'Stock, debts and capital are recorded from the day you first open this report; this month was not recorded.', key: const Key('no_position'), style: kMoneyCaption))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: <Widget>[
                _line(sw ? 'Bidhaa dukani (kwa gharama)' : 'Stock on hand (at cost)', tsh(_n(pos['stock_value'])), key: 'pos_stock'),
                _line(sw ? 'Ninayodai (madeni ya wateja)' : 'Owed to me (customers)', tsh(_n(pos['receivable'])), key: 'pos_receivable', tap: () => _openDebts(0)),
                _line(sw ? 'Ninayodaiwa' : 'I owe (suppliers, loans)', tsh(_n(pos['payable'])), key: 'pos_payable', tap: () => _openDebts(1)),
                const Divider(),
                _line(sw ? 'Mtaji' : 'Capital', tsh(_n(pos['capital'])), key: 'pos_capital', bold: true),
                if (_r['capital_change'] is Map) _capitalChange(sw),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    sw ? 'Mtaji = Bidhaa dukani + Ninayodai − Ninayodaiwa.' : 'Capital = Stock on hand + Owed to me − I owe.',
                    key: const Key('hint_capital'),
                    style: kMoneyCaption,
                  ),
                ),
              ]),
            ),
          ),
        if (cats.isNotEmpty || _n(f['personal_spending']) > 0) ...<Widget>[
          _section(sw ? 'Matumizi' : 'Spending'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: <Widget>[
                for (final Map<String, dynamic> c in cats) _spendRow('${c['category']}', _n(c['total']), spendTotal),
                if (_n(f['write_offs']) > 0) _line(sw ? 'Bidhaa zilizoharibika' : 'Damaged and written off', tsh(_n(f['write_offs'])), key: 'spend_writeoffs'),
                if (_n(f['personal_spending']) > 0) ...<Widget>[
                  const Divider(),
                  _line(sw ? 'Matumizi binafsi (hayahesabiwi kwenye faida)' : 'Personal spending (not taken off the profit)', tsh(_n(f['personal_spending'])), key: 'spend_personal'),
                ],
              ]),
            ),
          ),
        ],
        if (_list(_r['top_products']).isNotEmpty) ...<Widget>[
          _section(sw ? 'Bidhaa zilizoleta faida zaidi' : 'Products that earned the most'),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: <Widget>[for (final Map<String, dynamic> p in _list(_r['top_products'])) _line('${p['name']}  ×${p['qty']}', tsh(_n(p['profit'])), key: 'top_${p['name']}')]))),
        ],
        if (_list(_r['top_customers']).isNotEmpty) ...<Widget>[
          _section(sw ? 'Wateja wakubwa' : 'Best customers'),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: <Widget>[for (final Map<String, dynamic> c in _list(_r['top_customers'])) _line('${c['name']}  (${c['purchases']})', tsh(_n(c['spent'])), key: 'cust_${c['name']}')]))),
        ],
        if (_list(_r['slow_stock']).isNotEmpty && _r['is_current'] == true) ...<Widget>[
          _section(sw ? 'Bidhaa zilizolala (siku 30 bila kuuzwa)' : 'Sleeping stock (not sold in 30 days)'),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: <Widget>[for (final Map<String, dynamic> p in _list(_r['slow_stock'])) _line('${p['name']}  ×${p['quantity']}', tsh(_n(p['value'])), key: 'slow_${p['name']}')]))),
        ],
        if (_list(_r['debtors']).isNotEmpty && _r['is_current'] == true) ...<Widget>[
          _section(sw ? 'Wanaonidai zaidi' : 'Who owes me most'),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: <Widget>[for (final Map<String, dynamic> d in _list(_r['debtors'])) _line('${d['name']}  (${sw ? 'siku' : 'days'} ${d['days']})', tsh(_n(d['owed'])), key: 'debtor_${d['name']}', tap: () => _openDebts(0))]))),
        ],
        if (!future) _adviceCard(sw),
      ],
    );
  }

  void _openDebts(final int tab) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DebtsScreen(api: widget.api, initialTab: tab)));

  Widget _section(final String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 18, 2, 8), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)));

  Widget _line(final String label, final String value, {final String? key, final bool bold = false, final VoidCallback? tap}) {
    final Widget row = Padding(
      key: key == null ? null : Key(key),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: <Widget>[
        Expanded(child: Text(label, style: TextStyle(color: Colors.white, fontWeight: bold ? FontWeight.w800 : null))),
        const SizedBox(width: 8),
        Text(value, style: TextStyle(color: Colors.white, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        if (tap != null) const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
      ]),
    );

    return tap == null ? row : InkWell(onTap: tap, child: row);
  }

  Widget _spendRow(final String category, final num amount, final num total) {
    final LocalizationService loc = LocalizationService.instance;
    const List<String> known = <String>['rent', 'salaries', 'transport', 'utilities', 'supplies', 'maintenance', 'marketing', 'other', 'licences', 'loan_repayment'];
    final String label = known.contains(category) ? loc.translate(category) : category;
    final double share = total <= 0 ? 0 : (amount / total).clamp(0.0, 1.0).toDouble();

    return Padding(
      key: Key('spend_$category'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[Expanded(child: Text(label, style: const TextStyle(color: Colors.white))), Text(tsh(amount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 4),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: share, minHeight: 4, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation<Color>(ThemeConstants.warningAmber))),
      ]),
    );
  }

  /// The headline: better, the same or worse than the month before, big and coloured, with the numbers under it.
  Widget _headline(final bool sw, final String prevMonth) {
    final Map<String, dynamic> o = _m(_r['overall']);
    final String dir = '${o['direction']}';
    final num? pct = o['percent'] is num ? o['percent'] as num : null;
    final Map<String, dynamic> profit = _m(_m(_r['compare'])['net_profit']);
    final bool inProgress = _r['is_current'] == true;
    final bool like = _m(_r['previous'])['like_for_like'] == true;
    final String prev = monthName(prevMonth, sw: sw);
    final Color color = dir == 'up' ? ThemeConstants.successGreen : (dir == 'down' ? ThemeConstants.errorRed : Colors.blueGrey);
    final IconData icon = dir == 'up' ? Icons.trending_up_rounded : (dir == 'down' ? Icons.trending_down_rounded : Icons.trending_flat_rounded);
    final String pctText = pct == null ? '' : ' ${pct.abs().toStringAsFixed(pct.abs() >= 10 ? 0 : 1)}%';
    final String title = dir == 'up'
        ? (sw ? 'Umefanya vizuri kuliko $prev$pctText' : 'Better than $prev$pctText')
        : dir == 'down'
            ? (sw ? 'Uko chini ya $prev$pctText' : 'Below $prev$pctText')
            : (sw ? 'Umebaki pale pale na $prev' : 'The same as $prev');

    return Card(
      key: Key('headline_$dir'),
      color: color.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: <Widget>[
          Icon(icon, size: 40, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(title, key: const Key('headline_text'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                '${sw ? 'Faida' : 'Profit'}: ${tsh(_n(profit['now']))} ${sw ? 'dhidi ya' : 'against'} ${tsh(_n(profit['before']))}${inProgress && like ? (sw ? ' (siku zilezile za $prev)' : ' (same days of $prev)') : ''}',
                style: kMoneyCaption,
              ),
              if (inProgress) Text(sw ? 'Mwezi bado unaendelea.' : 'The month is still in progress.', style: kMoneyCaption),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _targetCard(final bool sw) {
    final Map<String, dynamic>? t = _r['target'] is Map ? _m(_r['target']) : null;
    final bool past = _m(_r).isNotEmpty && _r['is_current'] != true && _r['is_future'] != true;

    if (t == null) {
      if (past) return const SizedBox.shrink();

      return Card(
        child: ListTile(
          key: const Key('target_set'),
          leading: const Icon(Icons.flag_outlined, color: ThemeConstants.invAccent),
          title: Text(sw ? 'Weka lengo la faida' : 'Set a profit target', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          subtitle: Text(sw ? 'Uone kama uko mbele au nyuma ya lengo.' : 'See whether you are ahead or behind.', style: kMoneyCaption),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: _editTarget,
        ),
      );
    }
    final String status = '${t['status']}';
    final num progress = _n(t['progress_percent']);
    final double bar = (progress / 100).clamp(0.0, 1.0).toDouble();
    final num target = _n(t['profit_target']);
    final double marker = target <= 0 ? 0 : (_n(t['expected_by_today']) / target).clamp(0.0, 1.0).toDouble();
    final Color color = switch (status) {
      'reached' || 'on_track' => ThemeConstants.successGreen,
      'behind' || 'missed' => ThemeConstants.errorRed,
      _ => Colors.blueGrey,
    };
    final String label = switch (status) {
      'reached' => sw ? 'Lengo limefikiwa' : 'Target reached',
      'on_track' => sw ? 'Uko kwenye njia' : 'On track',
      'behind' => sw ? 'Uko nyuma ya lengo' : 'Behind target',
      'missed' => sw ? 'Lengo halikufikiwa' : 'Target missed',
      _ => sw ? 'Bado haijaanza' : 'Not started',
    };

    return Card(
      key: Key('target_$status'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.flag_rounded, color: ThemeConstants.invAccent, size: 20),
            const SizedBox(width: 8),
            Text(sw ? 'Lengo la faida' : 'Profit target', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: Text(label, key: const Key('target_status'), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12))),
            IconButton(key: const Key('target_edit'), visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white70), onPressed: _editTarget),
          ]),
          const SizedBox(height: 8),
          Text('${shortMoney(_n(t['profit']))} / ${shortMoney(target)}', key: const Key('target_numbers'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 10),
          Stack(alignment: Alignment.centerLeft, children: <Widget>[
            ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: bar, minHeight: 10, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(color))),
            if (_r['is_current'] == true) FractionallySizedBox(widthFactor: marker == 0 ? 0.001 : marker, child: Align(alignment: Alignment.centerRight, child: Container(width: 3, height: 16, color: Colors.white))),
          ]),
          const SizedBox(height: 8),
          Text(
            status == 'reached'
                ? (sw ? 'Umevuka lengo kwa ${tsh(_n(t['over_by']))}.' : 'You are over the target by ${tsh(_n(t['over_by']))}.')
                : status == 'missed'
                    ? (sw ? 'Ulikosa ${tsh(_n(t['left']))}.' : 'You were short by ${tsh(_n(t['left']))}.')
                    : '${sw ? 'Bado' : 'To go'}: ${tsh(_n(t['left']))}${_n(t['days_left']) > 0 ? '  ·  ${sw ? 'siku' : 'days'} ${_n(t['days_left'])}' : ''}${_r['is_current'] == true ? '  ·  ${sw ? 'Ungekuwa na' : 'By today you should have'} ${tsh(_n(t['expected_by_today']))}' : ''}',
            key: const Key('target_detail'),
            style: kMoneyCaption,
          ),
        ]),
      ),
    );
  }

  /// One money figure: its number, and a small chip saying how it moved against the month before (green is good news).
  Widget _figure(final String key, final String label, final num value, final Map<String, dynamic>? cmp, {final bool big = false, final String? note}) {
    final bool hasChip = cmp != null && cmp['direction'] != null;
    final bool good = cmp?['good'] == true;
    final String dir = '${cmp?['direction']}';
    final num? pct = cmp?['percent'] is num ? cmp!['percent'] as num : null;

    return Card(
      key: Key(key),
      color: big ? ThemeConstants.invAccent.withValues(alpha: 0.16) : null,
      child: Padding(
        padding: EdgeInsets.all(big ? 16 : 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(label, style: kMoneyCaption),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(tsh(value), style: TextStyle(fontSize: big ? 24 : 16, fontWeight: FontWeight.w800, color: value < 0 ? ThemeConstants.errorText : Colors.white))),
          if (note != null) Text('${LocalizationService.instance.isSwahili ? 'Kiwango' : 'Margin'} $note', style: kMoneyCaption),
          if (hasChip && dir != 'same') ...<Widget>[
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(dir == 'up' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: good ? ThemeConstants.successGreen : ThemeConstants.errorText),
              const SizedBox(width: 2),
              Text(pct == null ? (LocalizationService.instance.isSwahili ? 'mpya' : 'new') : '${pct.abs().toStringAsFixed(pct.abs() >= 10 ? 0 : 1)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: good ? ThemeConstants.successGreen : ThemeConstants.errorText)),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _capitalChange(final bool sw) {
    final Map<String, dynamic> c = _m(_r['capital_change']);
    final bool up = c['direction'] == 'up';
    final bool same = c['direction'] == 'same';
    final Color color = same ? Colors.white54 : (up ? ThemeConstants.successGreen : ThemeConstants.errorRed);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: <Widget>[
        Icon(same ? Icons.trending_flat : (up ? Icons.trending_up : Icons.trending_down), size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            same
                ? (sw ? 'Mtaji haujabadilika tangu mwezi uliopita' : 'Capital is unchanged since last month')
                : '${up ? (sw ? 'Mtaji umeongezeka' : 'Capital grew') : (sw ? 'Mtaji umepungua' : 'Capital fell')} ${tsh(_n(c['change']).abs())}${c['percent'] is num ? ' (${(c['percent'] as num).abs().toStringAsFixed(1)}%)' : ''} ${sw ? 'tangu mwezi uliopita' : 'since last month'}',
            key: const Key('capital_change'),
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _adviceCard(final bool sw) {
    final List<Map<String, dynamic>> items = _list(_advice?['items']);
    final bool ai = _advice?['source'] == 'ai';
    final int left = _n(_advice?['refreshes_left']).toInt();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Row(children: <Widget>[
          const Icon(Icons.auto_awesome, color: ThemeConstants.invAccent, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(sw ? 'Wapi uboreshe' : 'Where to improve', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white))),
          if (_advice != null)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: (ai ? ThemeConstants.invAccent : Colors.white24).withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)), child: Text(ai ? 'AI' : (sw ? 'Mahesabu' : 'Rules'), key: const Key('advice_source'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white))),
          IconButton(key: const Key('advice_refresh'), visualDensity: VisualDensity.compact, tooltip: sw ? 'Ushauri mpya' : 'Fresh advice', icon: const Icon(Icons.refresh, size: 20, color: Colors.white70), onPressed: _adviceLoading || left <= 0 && _advice != null ? null : () => _loadAdvice(refresh: true)),
        ]),
      ),
      if (_adviceLoading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      if (_adviceError != null && !_adviceLoading) Text(_adviceError!, style: const TextStyle(color: ThemeConstants.errorText)),
      if (!_adviceLoading)
        for (int i = 0; i < items.length; i++) _adviceItem(items[i], i),
      if (!_adviceLoading && _advice != null && ai == false && _advice!['ai_available'] == true)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(sw ? 'AI haipatikani sasa, ushauri umetokana na mahesabu ya mfumo.' : 'The AI could not be reached just now; this advice comes from the app\'s own rules.', key: const Key('advice_ai_down'), style: kMoneyCaption)),
    ]);
  }

  Widget _adviceItem(final Map<String, dynamic> a, final int i) {
    final String level = '${a['level']}';
    final Color color = level == 'warning' ? ThemeConstants.warningAmber : (level == 'good' ? ThemeConstants.successGreen : ThemeConstants.invAccent);
    final IconData icon = level == 'warning' ? Icons.warning_amber_rounded : (level == 'good' ? Icons.check_circle_outline : Icons.lightbulb_outline);

    return Card(
      key: Key('advice_$i'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4)), borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 3),
              Text('${a['detail']}', style: kMoneyCaption.copyWith(color: Colors.white70)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Asks for the month's profit target. Owns its text box, so the box lives exactly as long as the dialog (closing animation included).
class _TargetDialog extends StatefulWidget {
  const _TargetDialog({required this.month, this.current});

  final String month;
  final int? current;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.current == null ? '' : widget.current.toString());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = LocalizationService.instance.isSwahili;

    return AlertDialog(
      title: Text('${sw ? 'Lengo la faida' : 'Profit target'}: ${monthName(widget.month, sw: sw)}'),
      content: TextField(
        key: const Key('target_amount'),
        controller: _c,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: salonInputStyle,
        decoration: salonInput(labelText: sw ? 'Faida unayotaka (TSh)' : 'Profit you want (TSh)', hintText: sw ? '0 = ondoa lengo' : '0 clears the target'),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(key: const Key('target_save'), onPressed: () => Navigator.pop(context, double.tryParse(_c.text.replaceAll(',', '').trim()) ?? -1), child: Text(sw ? 'Hifadhi' : 'Save')),
      ],
    );
  }
}
