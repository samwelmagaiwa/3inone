import 'package:flutter/material.dart';

import '../../../../constants/theme_constants.dart';
import '../salon/salon_text.dart';
import '../widgets/joined_sections.dart';
import 'money_style.dart';

/// What each CATEGORY earned, in one place (the monthly report and the Sales "By category" page both show it): one block per category, closed it
/// shows its total, opened it shows its goods and its services each with their items and a subtotal (a service's goods used up are named under
/// it), then the category total; at the foot the totals of all goods, all services and everything. The owner reads profit; anyone else, sales.
class CategoryProfitView extends StatelessWidget {
  const CategoryProfitView({super.key, required this.profit, required this.owner, required this.sw});

  /// The server's `profit_by_category` (or the by-category answer): `categories` and `totals`.
  final Map<String, dynamic> profit;
  final bool owner;
  final bool sw;

  static Map<String, dynamic> _m(final dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[
        if (v is List)
          for (final dynamic e in v)
            if (e is Map) Map<String, dynamic>.from(e),
      ];
  static num _n(final dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  @override
  Widget build(final BuildContext context) {
    final List<Map<String, dynamic>> cats = _list(profit['categories']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      for (final Map<String, dynamic> c in cats) _block(context, c),
      _totals(),
    ]);
  }

  Widget _block(final BuildContext context, final Map<String, dynamic> c) {
    final String name = c['category'] == null ? (sw ? 'Bila kundi' : 'No category') : '${c['category']}';
    final Map<String, dynamic> total = _m(c['total']);
    final String key = owner ? 'profit' : 'sales';
    final Map<String, dynamic>? goods = c['goods'] is Map ? _m(c['goods']) : null;
    final Map<String, dynamic>? services = c['services'] is Map ? _m(c['services']) : null;
    final dynamic margin = total['margin_percent'];

    Widget kind(final String heading, final String id, final Map<String, dynamic> part, final bool isService) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _kindHeading(heading, 'kind_${id}_$name'),
            for (final Map<String, dynamic> i in _list(part['items'])) ...<Widget>[
              _line('${i['name']}  ×${i['qty']}', tsh(_n(i[key])), key: 'cat_item_${id}_${name}_${i['name']}'),
              if (isService && owner)
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 4),
                  child: Text(
                    '${sw ? 'Mauzo' : 'Sold'} ${tsh(_n(i['sales']))}  −  ${sw ? 'bidhaa zilizotumika' : 'goods used'} ${tsh(_n(i['cost']))}'
                    '${_list(i['materials']).isEmpty ? '' : '\n${_list(i['materials']).map((Map<String, dynamic> m) => '${m['name']} ×${m['qty']} (${tsh(_n(m['cost']))})').join(', ')}'}',
                    key: Key('cat_used_${id}_${name}_${i['name']}'),
                    style: kMoneyCaption,
                  ),
                ),
            ],
            _line(isService ? (sw ? 'Jumla ndogo ya huduma' : 'Subtotal: services') : (sw ? 'Jumla ndogo ya bidhaa' : 'Subtotal: goods'), tsh(_n(part[key])), key: 'sub_${id}_$name', bold: true),
          ],
        );

    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('cat_block_$name'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 10),
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white54,
          title: Row(children: <Widget>[
            Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            Text(tsh(_n(total[key])), key: Key('cat_total_$name'), style: TextStyle(color: _n(total[key]) < 0 ? ThemeConstants.errorText : Colors.white, fontWeight: FontWeight.w800)),
          ]),
          subtitle: Text(owner ? '${sw ? 'Mauzo' : 'Sales'} ${tsh(_n(total['sales']))}${margin == null ? '' : '  ·  $margin%'}' : '${sw ? 'Mauzo' : 'Sales'} ${tsh(_n(total['sales']))}', style: kMoneyCaption),
          children: <Widget>[
            if (goods != null) kind(sw ? 'Bidhaa' : 'Goods', 'goods', goods, false),
            if (services != null) kind(sw ? 'Huduma' : 'Services', 'services', services, true),
            if (goods != null && services != null) _line(sw ? 'Jumla ya kundi' : 'Category total', tsh(_n(total[key])), key: 'cat_sum_$name', bold: true),
          ],
        ),
      ),
    );
  }

  /// The totals of everything at the foot: all the goods, all the services, and the whole.
  Widget _totals() {
    final Map<String, dynamic> t = _m(profit['totals']);
    final String key = owner ? 'profit' : 'sales';
    if (t.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const SectionGlowDivider(lift: false),
        _line(sw ? 'Jumla ya bidhaa' : 'Total: goods', tsh(_n(_m(t['goods'])[key])), key: 'totals_goods'),
        _line(sw ? 'Jumla ya huduma' : 'Total: services', tsh(_n(_m(t['services'])[key])), key: 'totals_services'),
        _line(sw ? 'Jumla yote' : 'Total: all', tsh(_n(_m(t['all'])[key])), key: 'totals_all', bold: true),
      ]),
    );
  }

  static Widget _kindHeading(final String text, final String key) =>
      Padding(key: Key(key), padding: const EdgeInsets.only(top: 2, bottom: 2), child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: ThemeConstants.invAccent)));

  static Widget _line(final String label, final String value, {final String? key, final bool bold = false}) => Padding(
        key: key == null ? null : Key(key),
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: <Widget>[
          Expanded(child: Text(label, style: TextStyle(color: Colors.white, fontWeight: bold ? FontWeight.w800 : null))),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(color: Colors.white, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}
