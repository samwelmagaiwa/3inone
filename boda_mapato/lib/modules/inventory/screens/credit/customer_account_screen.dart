import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_customer_debt.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../widgets/customer_debt_card.dart';
import '../widgets/inv_action_button.dart';
import 'credit_screen.dart' show ReceivePaymentSheet;

/// One customer's whole account on one page: the old debt, the new debt and the total (with all that was paid), then every old debt and
/// every credit sale with the payments made on it, and all the payments together by date.
class CustomerAccountScreen extends StatefulWidget {
  const CustomerAccountScreen({super.key, required this.customer});

  final InvCreditCustomer customer;

  @override
  State<CustomerAccountScreen> createState() => _CustomerAccountScreenState();
}

class _CustomerAccountScreenState extends State<CustomerAccountScreen> {
  CustomerAccount? _account;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final CustomerAccount? a = await context.read<DepotProvider>().fetchCustomerAccount(widget.customer.id);
    if (!mounted) return;
    setState(() {
      _account = a;
      _failed = a == null;
      _loading = false;
    });
  }

  Future<void> _receive() async {
    final bool? paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext _) => ReceivePaymentSheet(customer: widget.customer),
    );
    if (paid == true && mounted) await _load();
  }

  static String _tsh(final double v) => 'TSH ${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (final Match m) => ',')}';

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final CustomerAccount? a = _account;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: AutoSizeText(widget.customer.name, maxLines: 1, minFontSize: 13, overflow: TextOverflow.ellipsis, style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 19.sp, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white70))
            : _failed || a == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(loc.translate('receive_payment_load_failed'), key: const ValueKey<String>('account_load_failed'), style: ThemeConstants.captionStyle, textAlign: TextAlign.center),
                        TextButton(key: const ValueKey<String>('account_retry'), onPressed: _load, child: Text(loc.translate('retry'))),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    backgroundColor: Colors.white,
                    color: ThemeConstants.primaryBlue,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 24.h),
                      children: <Widget>[
                        if (a.phone.isNotEmpty) Padding(padding: EdgeInsets.only(bottom: 8.h), child: Text(a.phone, style: ThemeConstants.captionStyle)),
                        CustomerDebtCard(summary: a.debt),
                        SizedBox(height: 10.h),
                        if (a.lifetime.purchases > 0) _lifetimeCard(loc, a.lifetime),
                        if (a.debt.totalLeft > 0)
                          InvActionButton(
                            key: const ValueKey<String>('account_receive'),
                            label: loc.translate('receive_payment'),
                            icon: Icons.payments_rounded,
                            color: ThemeConstants.successGreen,
                            arrow: false,
                            onPressed: _receive,
                          ),
                        if (a.oldDebts.isNotEmpty) ...<Widget>[
                          _title(loc.translate('cd_old_title')),
                          ...a.oldDebts.map(_oldDebt),
                        ],
                        if (a.creditSales.isNotEmpty) ...<Widget>[
                          _title(loc.translate('cd_new_title')),
                          ...a.creditSales.map(_creditSale),
                        ],
                        _title(loc.translate('cd_all_payments')),
                        if (a.payments.isEmpty)
                          Padding(padding: EdgeInsets.symmetric(vertical: 12.h), child: Text(loc.translate('cd_no_payments'), key: const ValueKey<String>('no_payments'), style: ThemeConstants.captionStyle, textAlign: TextAlign.center))
                        else ...<Widget>[
                          ...a.payments.map((AccountPayment p) => _paymentRow(p, withLabel: true)),
                          Padding(
                            padding: EdgeInsets.only(top: 6.h),
                            child: Row(
                              key: const ValueKey<String>('payments_total'),
                              children: <Widget>[
                                Expanded(child: Text(loc.translate('cd_paid_all'), style: ThemeConstants.captionStyle.copyWith(color: Colors.white70, fontWeight: FontWeight.w700))),
                                Text(_tsh(a.paidAll), style: ThemeConstants.bodyStyle.copyWith(color: ThemeConstants.successGreen, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  /// What this customer has bought in all, and the profit it brought (only for those who may see profit).
  Widget _lifetimeCard(final LocalizationService loc, final CustomerLifetime l) {
    Widget cell(final String label, final String value, {final Color? color, final Key? key}) => Expanded(
          child: Column(
            key: key,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: ThemeConstants.captionStyle.copyWith(fontSize: 10.sp)),
              Text(value, style: ThemeConstants.bodyStyle.copyWith(color: color ?? Colors.white, fontWeight: FontWeight.w800, fontSize: 13.sp)),
            ],
          ),
        );
    String day(final String? s) => s == null || s.length < 10 ? '—' : s.substring(0, 10);
    return Container(
      key: const ValueKey<String>('account_lifetime'),
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(color: ThemeConstants.invFill, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: ThemeConstants.invBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(loc.translate('acct_bought_title').toUpperCase(), style: ThemeConstants.captionStyle.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white70)),
          SizedBox(height: 6.h),
          Row(children: <Widget>[
            cell(loc.translate('acct_purchases'), '${l.purchases}'),
            cell(loc.translate('acct_sales'), _tsh(l.sales), key: const ValueKey<String>('lifetime_sales')),
            if (l.profit != null) cell(loc.translate('acct_profit'), _tsh(l.profit!), color: l.profit! >= 0 ? ThemeConstants.successGreen : ThemeConstants.errorRed, key: const ValueKey<String>('lifetime_profit')),
          ]),
          SizedBox(height: 6.h),
          Row(children: <Widget>[
            cell(loc.translate('acct_first'), day(l.firstPurchase)),
            cell(loc.translate('acct_last'), day(l.lastPurchase)),
          ]),
        ],
      ),
    );
  }

  Widget _title(final String text) => Padding(
        padding: EdgeInsets.only(top: 16.h, bottom: 8.h),
        child: Text(text.toUpperCase(), style: ThemeConstants.captionStyle.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white70)),
      );

  Widget _box({required final Key key, required final Widget header, required final List<AccountPayment> payments}) {
    return Container(
      key: key,
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(color: ThemeConstants.invFill, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: ThemeConstants.invBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          header,
          if (payments.isNotEmpty) ...<Widget>[
            const Divider(height: 14, color: ThemeConstants.invBorder),
            ...payments.map((AccountPayment p) => _paymentRow(p)),
          ],
        ],
      ),
    );
  }

  Widget _oldDebt(final OldDebtRecord d) {
    final LocalizationService loc = LocalizationService.instance;
    return _box(
      key: ValueKey<String>('old_debt_${d.id}'),
      payments: d.payments,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(d.note?.trim().isNotEmpty == true ? d.note!.trim() : loc.translate('cd_old_title'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          if (d.startedOn.isNotEmpty) Text(d.startedOn, style: ThemeConstants.captionStyle),
          SizedBox(height: 4.h),
          _figures(d.amount, d.paid, d.left),
        ],
      ),
    );
  }

  Widget _creditSale(final CreditSaleRecord s) {
    final LocalizationService loc = LocalizationService.instance;
    return _box(
      key: ValueKey<String>('credit_sale_${s.id}'),
      payments: s.payments,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(s.number.isEmpty ? '—' : s.number, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(color: (s.isPaidOff ? ThemeConstants.successGreen : ThemeConstants.warningAmber).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10.r)),
                child: Text(s.isPaidOff ? loc.translate('cd_paid_off') : loc.translate('cd_open'), style: ThemeConstants.captionStyle.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (s.createdAt.length >= 10) Text(s.createdAt.substring(0, 10), style: ThemeConstants.captionStyle),
          SizedBox(height: 4.h),
          _figures(s.total, s.paid, s.left),
        ],
      ),
    );
  }

  Widget _figures(final double owed, final double paid, final double left) {
    final LocalizationService loc = LocalizationService.instance;
    Widget cell(final String label, final double v, final Color? color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: ThemeConstants.captionStyle.copyWith(fontSize: 10.sp)),
              Text(_tsh(v), style: ThemeConstants.bodyStyle.copyWith(color: color ?? Colors.white, fontWeight: FontWeight.w700, fontSize: 12.sp)),
            ],
          ),
        );
    return Row(children: <Widget>[
      cell(loc.translate('cd_owed'), owed, null),
      cell(loc.translate('cd_paid'), paid, ThemeConstants.successGreen),
      cell(loc.translate('cd_left'), left, left > 0 ? ThemeConstants.warningAmber : Colors.white70),
    ]);
  }

  Widget _paymentRow(final AccountPayment p, {final bool withLabel = false}) {
    final LocalizationService loc = LocalizationService.instance;
    final String how = <String>[
      if (p.method != null && p.method!.isNotEmpty) p.method!.replaceAll('_', ' '),
      if (p.reference != null && p.reference!.trim().isNotEmpty) p.reference!.trim(),
    ].join(' · ');
    return Padding(
      key: ValueKey<String>('payment_${p.isOld ? 'old' : 'new'}_${p.id}'),
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        children: <Widget>[
          Icon(Icons.south_west_rounded, size: 14.sp, color: ThemeConstants.successGreen),
          SizedBox(width: 6.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  withLabel ? '${p.paidOn} · ${p.isOld ? loc.translate('cd_old_short') : loc.translate('cd_new_short')} · ${p.label}' : p.paidOn,
                  style: ThemeConstants.captionStyle.copyWith(color: Colors.white70),
                ),
                if (how.isNotEmpty) Text(how, style: ThemeConstants.captionStyle.copyWith(fontSize: 10.sp)),
              ],
            ),
          ),
          Text(_tsh(p.amount), style: ThemeConstants.bodyStyle.copyWith(color: ThemeConstants.successGreen, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
