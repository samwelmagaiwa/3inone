import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../services/salon_api.dart';
import 'salon_access.dart';
import 'salon_mode.dart';
import 'salon_text.dart';

/// On a salon sale: what the SERVICE earned apart from what the GOODS earned. For each service: what it brought in, the
/// stylist's commission, the goods it used up (shampoo, dye...) and so its profit; for each goods line sold: what it brought
/// in, what it cost and its profit; then the profit of each and of the sale. Only the people who see the salon's money see
/// it, and a shop's sale (or a sale it cannot read) shows nothing.
class SalonSaleBreakdownCard extends StatefulWidget {
  const SalonSaleBreakdownCard({super.key, required this.saleId, this.api});

  final int saleId;
  final SalonApi? api;

  @override
  State<SalonSaleBreakdownCard> createState() => _SalonSaleBreakdownCardState();
}

class _SalonSaleBreakdownCardState extends State<SalonSaleBreakdownCard> {
  late final SalonApi _api = widget.api ?? SalonApi();
  Map<String, dynamic>? _b;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!isSalonMode(context, listen: false)) return;
    // (read, not watch: this runs after the first frame, outside the build)
    bool mayAsk = false;
    try {
      mayAsk = canSeeSalonMoney(context.read<AuthProvider>().user);
    } on ProviderNotFoundException {
      mayAsk = false;
    }
    if (!mayAsk) return;
    try {
      final Map<String, dynamic> b = await _api.saleBreakdown(widget.saleId);
      if (mounted && b.isNotEmpty) setState(() => _b = b);
    } on Exception {
      // The receipt is the point of this page; the breakdown is a bonus.
    }
  }

  List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[
        if (v is List)
          for (final dynamic r in v)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  String _n(final dynamic v) => tsh((v as num?) ?? 0);

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? b = _b;
    if (b == null) return const SizedBox.shrink();
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<Map<String, dynamic>> services = _list(b['services']);
    final List<Map<String, dynamic>> goods = _list(b['goods']);

    Widget row(final String l, final String v, {final bool bold = false, final Color? color, final double indent = 0, final String? key}) => Padding(
          key: key == null ? null : Key(key),
          padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
          child: Row(children: <Widget>[
            Expanded(child: Text(l, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null, color: color))),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
          ]),
        );

    return Card(
      key: const Key('sale_breakdown'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(sw ? 'Mauzo haya yalipata faida gani' : 'What this sale earned', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          if (services.isNotEmpty) Text(sw ? 'Huduma' : 'Services', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final Map<String, dynamic> s in services) ...<Widget>[
            row('${s['name']}${(s['quantity'] as num? ?? 1) > 1 ? ' ×${s['quantity']}' : ''}${'${s['stylist'] ?? ''}'.isEmpty ? '' : ' (${s['stylist']})'}', _n(s['revenue'])),
            if (((s['commission'] as num?) ?? 0) > 0) row(sw ? '− Kamisheni' : '− Commission', _n(s['commission']), indent: 12),
            for (final Map<String, dynamic> m in _list(s['materials'])) row('− ${m['name']} ×${m['quantity']}', _n(m['cost']), indent: 12),
            row(sw ? 'Faida ya huduma' : 'Service profit', _n(s['profit']), bold: true, indent: 12, color: Colors.lightGreenAccent),
          ],
          if (goods.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(sw ? 'Bidhaa' : 'Goods', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          for (final Map<String, dynamic> g in goods) ...<Widget>[
            row('${g['name']}${(g['quantity'] as num? ?? 1) > 1 ? ' ×${g['quantity']}' : ''}', _n(g['revenue'])),
            row(sw ? '− Gharama ya bidhaa' : '− Cost of the goods', _n(g['cost']), indent: 12),
            row(sw ? 'Faida ya bidhaa' : 'Goods profit', _n(g['profit']), bold: true, indent: 12, color: Colors.lightGreenAccent),
          ],
          const Divider(),
          if (services.isNotEmpty) row(sw ? 'Jumla faida ya huduma' : 'Services profit', _n(b['service_profit']), key: 'sb_service'),
          if (goods.isNotEmpty) row(sw ? 'Jumla faida ya bidhaa' : 'Goods profit', _n(b['goods_profit']), key: 'sb_goods'),
          row(sw ? 'Faida ya mauzo haya' : 'Profit on this sale', _n(b['profit']), bold: true, key: 'sb_total'),
        ]),
      ),
    );
  }
}
