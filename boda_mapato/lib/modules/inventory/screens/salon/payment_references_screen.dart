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

enum _When { today, thisMonth, lastMonth, all }

/// Money > References: every payment that came with a reference number (mobile money, bank), from the first to the last, with when it
/// was paid, how much, and who for. Tapping one opens the whole sale behind it. The owner reads these to check them against the phone or
/// the bank statement; a sale paid by mobile money cannot be saved without its reference.
class PaymentReferencesScreen extends StatefulWidget {
  const PaymentReferencesScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What day it is (a fixed day in tests).
  final DateTime? today;

  @override
  State<PaymentReferencesScreen> createState() => _PaymentReferencesScreenState();
}

class _PaymentReferencesScreenState extends State<PaymentReferencesScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();

  _When _when = _When.thisMonth;
  String _channel = '';
  String _query = '';
  PaymentReferencePage? _page;
  final List<PaymentReference> _rows = <PaymentReference>[];
  String? _error;
  bool _loading = true;
  bool _more = false;
  int _generation = 0;

  static const List<String> _channels = <String>['', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer'];

  DateTime get _today {
    final DateTime now = widget.today ?? DateTime.now();

    return DateTime(now.year, now.month, now.day);
  }

  (DateTime?, DateTime?) get _range {
    final DateTime t = _today;
    switch (_when) {
      case _When.today:
        return (t, t);
      case _When.thisMonth:
        return (DateTime(t.year, t.month), t);
      case _When.lastMonth:
        return (DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0));
      case _When.all:
        return (null, null);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Read the first page again (the choices changed); an answer for choices made before this one is ignored.
  Future<void> _load() async {
    final int mine = ++_generation;
    final (DateTime? from, DateTime? to) = _range;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final PaymentReferencePage page = await _api.paymentReferences(from: from, to: to, query: _query, channel: _channel);
      if (!mounted || mine != _generation) return;
      setState(() {
        _page = page;
        _rows
          ..clear()
          ..addAll(page.rows);
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted || mine != _generation) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _showMore() async {
    final PaymentReferencePage? current = _page;
    if (current == null || _more) return;
    final int mine = _generation;
    final (DateTime? from, DateTime? to) = _range;
    setState(() => _more = true);
    try {
      final PaymentReferencePage next = await _api.paymentReferences(from: from, to: to, query: _query, channel: _channel, page: current.page + 1);
      if (!mounted || mine != _generation) return;
      setState(() {
        _page = next;
        _rows.addAll(next.rows);
        _more = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _more = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  void _open(PaymentReference r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (BuildContext ctx) => _SaleSheet(api: _api, reference: r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return RefreshIndicator(
      onRefresh: _load,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
        children: <Widget>[
          InvFilterChips<_When>(
            value: _when,
            options: <_When, String>{
              _When.today: sw ? 'Leo' : 'Today',
              _When.thisMonth: sw ? 'Mwezi huu' : 'This month',
              _When.lastMonth: sw ? 'Mwezi uliopita' : 'Last month',
              _When.all: sw ? 'Zote' : 'All',
            },
            onSelected: (_When w) {
              if (w == _when) return;
              setState(() => _when = w);
              _load();
            },
          ),
          SizedBox(height: 8.h),
          InvFilterChips<String>(
            value: _channel,
            options: <String, String>{for (final String c in _channels) c: c.isEmpty ? (sw ? 'Njia zote' : 'All ways') : channelLabel(sw: sw, channel: c)},
            onSelected: (String c) {
              if (c == _channel) return;
              setState(() => _channel = c);
              _load();
            },
          ),
          SizedBox(height: 8.h),
          InvSearchField(
            hint: sw ? 'Tafuta namba ya muamala, mteja au risiti' : 'Search a reference, a customer or a sale',
            onChanged: (String v) {
              _query = v;
              _load();
            },
          ),
          SizedBox(height: 12.h),
          ..._body(sw),
        ],
      ),
    );
  }

  List<Widget> _body(bool sw) {
    if (_loading && _page == null) {
      return <Widget>[SizedBox(height: 100.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];
    }
    if (_error != null && _page == null) {
      return <Widget>[
        SizedBox(height: 40.h),
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('references_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ];
    }
    final PaymentReferencePage page = _page!;

    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Miamala' : 'Payments', value: '${page.count}', icon: Icons.confirmation_number_outlined)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Jumla' : 'Total', value: tsh(page.amount), icon: Icons.payments_outlined, accent: ThemeConstants.successGreen)),
        ],
      ),
      SizedBox(height: 12.h),
      if (_rows.isEmpty)
        InvEmptyState(icon: Icons.confirmation_number_outlined, message: sw ? 'Hakuna miamala yenye namba kwa chaguo hili.' : 'No payments with a reference number for this choice.')
      else
        for (final PaymentReference r in _rows) ...<Widget>[
          _ReferenceCard(reference: r, sw: sw, onTap: () => _open(r)),
          SizedBox(height: 8.h),
        ],
      if (page.page < page.lastPage)
        Center(
          child: TextButton(
            key: const ValueKey<String>('references_more'),
            onPressed: _more ? null : _showMore,
            child: Text(_more ? (sw ? 'Inapakia…' : 'Loading…') : (sw ? 'Onyesha zaidi' : 'Show more'), style: const TextStyle(color: Colors.white)),
          ),
        ),
    ];
  }
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.reference, required this.sw, required this.onTap});

  final PaymentReference reference;
  final bool sw;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PaymentReference r = reference;

    return InkWell(
      borderRadius: BorderRadius.circular(20.r),
      onTap: onTap,
      child: Container(
        key: ValueKey<String>('reference_${r.id}'),
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(r.reference, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5))),
                SizedBox(width: 8.w),
                Text(tsh(r.amount), style: TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w800, fontSize: 14.sp)),
                Icon(Icons.chevron_right, color: Colors.white70, size: 20.sp),
              ],
            ),
            SizedBox(height: 4.h),
            Text(
              <String>[
                if (r.paidAt != null) '${dayLabel(r.paidAt!)} ${_hm(r.paidAt!)}',
                channelLabel(sw: sw, channel: r.channel),
                r.saleNumber,
                if (r.customerName != null) r.customerName!,
              ].join(' • '),
              style: ThemeConstants.captionStyle,
            ),
            if (r.cancelled) ...<Widget>[
              SizedBox(height: 6.h),
              InvBadge(label: sw ? 'Mauzo yamefutwa' : 'Sale cancelled', color: ThemeConstants.errorRed),
            ],
          ],
        ),
      ),
    );
  }
}

/// The whole sale behind a reference: when, who for, what was sold, the totals and every payment with its reference.
class _SaleSheet extends StatefulWidget {
  const _SaleSheet({required this.api, required this.reference});

  final SalonApi api;
  final PaymentReference reference;

  @override
  State<_SaleSheet> createState() => _SaleSheetState();
}

class _SaleSheetState extends State<_SaleSheet> {
  Map<String, dynamic>? _sale;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final Map<String, dynamic> sale = await widget.api.saleDetail(widget.reference.saleId);
      if (mounted) setState(() => _sale = sale);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final PaymentReference ref = widget.reference;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (BuildContext _, ScrollController controller) => ListView(
        key: const ValueKey<String>('reference_sale'),
        controller: controller,
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
        children: <Widget>[
          Text('${sw ? 'Mauzo' : 'Sale'} ${ref.saleNumber}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, fontSize: 16.sp)),
          SizedBox(height: 4.h),
          Text('${sw ? 'Namba ya muamala' : 'Reference'}: ${ref.reference}', style: ThemeConstants.captionStyle),
          SizedBox(height: 12.h),
          ..._content(sw),
        ],
      ),
    );
  }

  List<Widget> _content(bool sw) {
    if (_error != null) {
      return <Widget>[
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('reference_sale_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ];
    }
    final Map<String, dynamic>? sale = _sale;
    if (sale == null) return <Widget>[SizedBox(height: 60.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];

    final List<dynamic> items = sale['items'] is List ? sale['items'] as List<dynamic> : <dynamic>[];
    final List<dynamic> payments = sale['payments'] is List ? sale['payments'] as List<dynamic> : <dynamic>[];
    final String customer = '${sale['customer_name'] ?? ''}'.trim();
    final DateTime? when = DateTime.tryParse('${sale['created_at'] ?? ''}');
    final num discount = _n(sale['discount']);

    Widget line(String label, String value, {bool bold = false, Key? key}) => Padding(
          key: key,
          padding: EdgeInsets.symmetric(vertical: 3.h),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label, style: bold ? ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800) : ThemeConstants.captionStyle)),
              Text(value, style: ThemeConstants.bodyStyle.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        );

    return <Widget>[
      line(sw ? 'Mteja' : 'Customer', customer.isEmpty ? (sw ? 'Mteja wa kawaida' : 'Walk-in client') : customer),
      if (when != null) line(sw ? 'Tarehe' : 'Date', '${dayLabel(when)} ${_hm(when)}'),
      line(sw ? 'Hali' : 'Status', '${sale['payment_status'] ?? ''}'),
      SizedBox(height: 8.h),
      Divider(color: Colors.white24, height: 1.h),
      SizedBox(height: 8.h),
      Text(sw ? 'Vilivyouzwa' : 'What was sold', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
      for (final dynamic it in items)
        if (it is Map)
          line(
            '${it['product_name'] ?? ''} × ${it['quantity'] ?? it['qty'] ?? 1}${'${it['staff_name'] ?? ''}'.isEmpty ? '' : ' • ${it['staff_name']}'}',
            tsh(_n(it['total'])),
          ),
      SizedBox(height: 8.h),
      Divider(color: Colors.white24, height: 1.h),
      SizedBox(height: 8.h),
      if (discount > 0) line(sw ? 'Punguzo' : 'Discount', '− ${tsh(discount)}'),
      line(sw ? 'Jumla' : 'Total', tsh(_n(sale['total'])), bold: true),
      line(sw ? 'Kimelipwa' : 'Paid', tsh(_n(sale['paid_total']))),
      SizedBox(height: 8.h),
      Divider(color: Colors.white24, height: 1.h),
      SizedBox(height: 8.h),
      Text(sw ? 'Malipo' : 'Payments', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
      for (final dynamic p in payments)
        if (p is Map)
          line(
            '${channelLabel(sw: sw, channel: '${p['method'] ?? ''}')}${'${p['reference'] ?? ''}'.isEmpty ? '' : ' • ${p['reference']}'}',
            tsh(_n(p['amount'])),
            key: ValueKey<String>('reference_payment_${p['id']}'),
          ),
    ];
  }
}
