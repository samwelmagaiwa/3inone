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

enum _Period { today, week, month, year }

/// The salon's profit and loss for a period: what the services and goods earned (after discounts), what the goods
/// cost, what was spent, what stylists earned in commission and were paid in salary, and what is left. Below it:
/// the money received by how it was paid, and what clients still owe. (Money received is not the same as revenue.)
class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What "today" is (a test fixes it); the real clock otherwise.
  final DateTime? today;

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();

  _Period _period = _Period.month;
  ProfitLoss? _data;
  String? _error;
  bool _loading = true;

  DateTime get _today {
    final DateTime d = widget.today ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  (DateTime, DateTime) get _dates {
    final DateTime t = _today;
    switch (_period) {
      case _Period.today:
        return (t, t);
      case _Period.week:
        return (t.subtract(Duration(days: t.weekday - 1)), t);
      case _Period.month:
        return (DateTime(t.year, t.month), t);
      case _Period.year:
        return (DateTime(t.year), t);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final _Period asked = _period;
    final (DateTime from, DateTime to) = _dates;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ProfitLoss d = await _api.profitLoss(from, to);
      if (!mounted || asked != _period) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted || asked != _period) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
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
          children: <Widget>[
            InvFilterChips<_Period>(
              value: _period,
              options: <_Period, String>{
                _Period.today: sw ? 'Leo' : 'Today',
                _Period.week: sw ? 'Wiki hii' : 'This week',
                _Period.month: sw ? 'Mwezi huu' : 'This month',
                _Period.year: sw ? 'Mwaka huu' : 'This year',
              },
              onSelected: (_Period p) {
                if (p == _period) return;
                setState(() => _period = p);
                _load();
              },
            ),
            SizedBox(height: 12.h),
            ..._body(sw),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(final bool sw) {
    final ProfitLoss? d = _data;
    if (_loading && d == null) {
      return <Widget>[SizedBox(height: 100.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];
    }
    if (_error != null && d == null) {
      return <Widget>[
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('pl_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ];
    }
    if (d == null) return <Widget>[];

    final bool profit = d.netProfit >= 0;

    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Mapato' : 'Revenue', value: tsh(d.revenue), icon: Icons.payments_outlined, accent: ThemeConstants.successGreen)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Matumizi' : 'Costs', value: tsh(d.operatingCosts + d.costOfGoods), icon: Icons.receipt_long_outlined, accent: ThemeConstants.warningAmber)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: profit ? (sw ? 'Faida' : 'Profit') : (sw ? 'Hasara' : 'Loss'), value: tsh(d.netProfit), icon: profit ? Icons.trending_up : Icons.trending_down, accent: profit ? ThemeConstants.successGreen : ThemeConstants.errorRed)),
        ],
      ),
      SizedBox(height: 12.h),
      _card(<Widget>[
        _line(sw ? 'Mapato ya huduma' : 'Service revenue', d.serviceRevenue, key: 'pl_service_revenue'),
        _line(sw ? 'Mauzo ya bidhaa' : 'Goods sold', d.goodsRevenue, key: 'pl_goods_revenue'),
        if (d.discounts > 0) _line(sw ? '(ndani yake punguzo la ${tsh(d.discounts)})' : '(after ${tsh(d.discounts)} of discounts)', null, muted: true),
        _line(sw ? 'Gharama ya bidhaa zilizouzwa' : 'Cost of goods sold', -d.costOfGoods, key: 'pl_cogs'),
        const Divider(color: Colors.white24),
        _line(sw ? 'Faida ghafi' : 'Gross profit', d.grossProfit, bold: true, key: 'pl_gross'),
      ]),
      SizedBox(height: 10.h),
      _card(<Widget>[
        Text(sw ? 'Faida inatoka wapi?' : 'Where does the profit come from?', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: 2.h),
        Text(
          sw ? 'Kabla ya gharama za uendeshaji (kodi ya pango, mishahara). Bidhaa ni zile ulizouzia mteja (rasta, shampoo); huduma ni kazi ya kusuka.' : 'Before the running costs (rent, salaries). Goods are what you sold the client (hair, shampoo); services are the work done (braiding).',
          style: ThemeConstants.captionStyle,
        ),
        SizedBox(height: 8.h),
        Text(sw ? 'Bidhaa zilizouzwa' : 'Goods sold', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700, color: ThemeConstants.invAccent)),
        _line(sw ? 'Mauzo' : 'Sold for', d.goodsRevenue, key: 'pl_kind_goods_revenue'),
        _line(sw ? 'Zilinunuliwa' : 'Bought for', -d.goodsCost, key: 'pl_kind_goods_cost'),
        _line(sw ? 'Faida ya bidhaa' : 'Profit on goods', d.goodsProfit, bold: true, color: d.goodsProfit >= 0 ? ThemeConstants.successGreen : ThemeConstants.errorText, key: 'pl_goods_profit'),
        const Divider(color: Colors.white24),
        Text(sw ? 'Huduma (kusuka n.k.)' : 'Services (braiding etc.)', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700, color: ThemeConstants.invAccent)),
        _line(sw ? 'Mapato ya huduma' : 'Service revenue', d.serviceRevenue, key: 'pl_kind_service_revenue'),
        if (d.servicesProfit != d.serviceRevenue) _line(sw ? 'Bidhaa zilizotumika na kamisheni' : 'Goods used and stylists\' commission', d.servicesProfit - d.serviceRevenue, key: 'pl_kind_service_costs'),
        _line(sw ? 'Faida ya huduma' : 'Profit on services', d.servicesProfit, bold: true, color: d.servicesProfit >= 0 ? ThemeConstants.successGreen : ThemeConstants.errorText, key: 'pl_services_profit'),
      ]),
      SizedBox(height: 10.h),
      _card(<Widget>[
        Text(sw ? 'Gharama za uendeshaji' : 'Running costs', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: 6.h),
        for (final ExpenseGroup g in d.expensesByCategory) _line(expenseCategoryLabel(sw: sw, category: g.category), -g.total, key: 'pl_exp_${g.category}'),
        if (d.expensesByCategory.isEmpty) _line(sw ? 'Matumizi' : 'Expenses', 0, key: 'pl_expenses'),
        _line(sw ? 'Kamisheni za wahudumu' : 'Stylists commission', -d.commissions, key: 'pl_commissions'),
        _line(sw ? 'Mishahara iliyolipwa' : 'Salaries paid', -d.salaries, key: 'pl_salaries'),
        const Divider(color: Colors.white24),
        _line(profit ? (sw ? 'Faida halisi' : 'Net profit') : (sw ? 'Hasara halisi' : 'Net loss'), d.netProfit, bold: true, color: profit ? ThemeConstants.successGreen : ThemeConstants.errorText, key: 'pl_net'),
      ]),
      SizedBox(height: 10.h),
      _card(<Widget>[
        Text(sw ? 'Pesa zilizopokelewa' : 'Money received', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: 6.h),
        for (final Collection c in d.collections) _line(channelLabel(sw: sw, channel: c.method), c.amount, key: 'pl_col_${c.method}'),
        if (d.collections.isEmpty) Text(sw ? 'Hakuna malipo kwa kipindi hiki.' : 'No payments in this period.', style: ThemeConstants.captionStyle),
        const Divider(color: Colors.white24),
        _line(sw ? 'Jumla iliyopokelewa' : 'Total received', d.collected, bold: true, key: 'pl_collected'),
        _line(sw ? 'Madeni ya wateja' : 'Owed by clients', d.outstanding, color: d.outstanding > 0 ? ThemeConstants.warningAmber : null, key: 'pl_outstanding'),
        if (d.otherIncome > 0) _line(sw ? 'Mapato mengine (amana zilizopotea)' : 'Other income (deposits kept)', d.otherIncome, key: 'pl_other_income'),
        if (d.depositsHeld > 0) _line(sw ? 'Amana zilizoshikiliwa (si mapato bado)' : 'Deposits held (not income yet)', d.depositsHeld, muted: true, key: 'pl_deposits_held'),
      ]),
      if (d.vatTotal > 0) ...<Widget>[
        SizedBox(height: 10.h),
        _card(<Widget>[
          Text(sw ? 'Kodi (VAT)' : 'VAT', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 6.h),
          for (final VatRate r in d.vatByRate) _line('${r.rate.toStringAsFixed(r.rate == r.rate.roundToDouble() ? 0 : 1)}%  (${sw ? 'mauzo yanayotozwa kodi' : 'taxable'} ${tsh(r.taxable)})', r.vat, key: 'pl_vat_${r.rate.round()}'),
          const Divider(color: Colors.white24),
          _line(sw ? 'Jumla ya VAT' : 'Total VAT', d.vatTotal, bold: true, key: 'pl_vat_total'),
        ]),
      ],
      SizedBox(height: 10.h),
      Text(
        sw
            ? 'Wateja ${d.clients} • mauzo ${d.sales}${d.cancelledCount > 0 ? ' • yaliyofutwa ${d.cancelledCount} (${tsh(d.cancelledTotal)})' : ''}'
            : '${d.clients} clients • ${d.sales} sales${d.cancelledCount > 0 ? ' • ${d.cancelledCount} cancelled (${tsh(d.cancelledTotal)})' : ''}',
        key: const ValueKey<String>('pl_footer'),
        style: ThemeConstants.captionStyle,
      ),
      SizedBox(height: 4.h),
      Text(
        sw ? 'Mapato ni baada ya punguzo. Pesa zilizopokelewa si sawa na mapato: zinajumuisha madeni yaliyolipwa.' : 'Revenue is after discounts. Money received is not the same as revenue: it includes old debts being paid.',
        style: ThemeConstants.captionStyle.copyWith(fontStyle: FontStyle.italic),
      ),
    ];
  }

  Widget _card(final List<Widget> children) => Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _line(final String label, final double? amount, {final bool bold = false, final bool muted = false, final Color? color, final String? key}) => Padding(
        key: key == null ? null : ValueKey<String>(key),
        padding: EdgeInsets.symmetric(vertical: 3.h),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: (muted ? ThemeConstants.captionStyle : ThemeConstants.bodyStyle).copyWith(fontWeight: bold ? FontWeight.w800 : null))),
            if (amount != null)
              Text(
                amount < 0 ? '− ${tsh(-amount)}' : tsh(amount),
                style: ThemeConstants.bodyStyle.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color),
              ),
          ],
        ),
      );
}
