import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/money_api.dart';
import '../money/category_profit_view.dart';
import '../salon/salon_period.dart';

/// "By category": what each category sold between two days, goods and services apart, with subtotals and totals; the owner also sees the profit.
class SalesByCategoryScreen extends StatefulWidget {
  const SalesByCategoryScreen({super.key, this.api, this.today});

  final MoneyApi? api;
  final DateTime? today;

  @override
  State<SalesByCategoryScreen> createState() => _SalesByCategoryScreenState();
}

class _SalesByCategoryScreenState extends State<SalesByCategoryScreen> {
  late final MoneyApi _api = widget.api ?? MoneyApi();
  late final DateTime _today = widget.today ?? DateTime.now();
  SalonPeriod _period = SalonPeriod.thisMonth;
  DateTimeRange? _custom;
  Map<String, dynamic> _data = <String, dynamic>{};
  String? _error;
  bool _loading = true;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  static String _iso(final DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final int ticket = ++_asked;
    setState(() {
      _loading = true;
      _error = null;
    });
    final (DateTime a, DateTime b) = salonRange(_period, _today, custom: _custom);
    try {
      final Map<String, dynamic> d = await _api.salesByCategory(_iso(a), _iso(b));
      if (mounted && ticket == _asked) setState(() => _data = d);
    } on Exception catch (e) {
      if (mounted && ticket == _asked) setState(() => _error = readableErrorMessage(e));
    }
    if (mounted && ticket == _asked) setState(() => _loading = false);
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool owner = _data['owner_figures'] != false;
    final bool empty = _data['categories'] is! List || (_data['categories'] as List).isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Mauzo kwa kundi' : 'Sales by category')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 24.h),
        children: <Widget>[
          SalonPeriodButton(
            period: _period,
            custom: _custom,
            today: _today,
            sw: sw,
            onChanged: (SalonPeriodChoice c) {
              _period = c.period;
              _custom = c.custom;
              _load();
            },
          ),
          SizedBox(height: 12.h),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text(_error!, key: const Key('cat_error'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))
          else if (empty)
            Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna kilichouzwa kipindi hiki.' : 'Nothing was sold in this period.', key: const Key('cat_empty'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)))
          else ...<Widget>[
            Text(owner ? (sw ? 'Faida kwa kundi' : 'Profit by category') : (sw ? 'Mauzo kwa kundi' : 'Sales by category'), key: const Key('by_category_title'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              decoration: ThemeConstants.glassCardDecoration,
              child: CategoryProfitView(profit: _data, owner: owner, sw: sw),
            ),
          ],
        ],
      ),
    );
  }
}
