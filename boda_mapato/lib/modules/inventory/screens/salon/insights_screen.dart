import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import 'salon_text.dart';

/// How the salon is doing over the months: takings and profit by month, new against returning clients, how many clients
/// come back within 60 days, the best services, and the busiest days and hours. Owner, managers and the accountant.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, this.api});

  final SalonApi? api;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  Map<String, dynamic> _d = <String, dynamic>{};
  int _months = 6;
  String? _error;
  bool _loading = true;

  List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[
        if (v is List)
          for (final dynamic r in v)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> d = await _api.analytics(months: _months);
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

  static String dayName(final int iso, final bool sw) {
    const List<String> en = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const List<String> swa = <String>['Jtt', 'Jnn', 'Jtn', 'Alh', 'Ijm', 'Jms', 'Jpl'];

    return (sw ? swa : en)[(iso - 1).clamp(0, 6)];
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<Map<String, dynamic>> trend = _list(_d['trend']);
    final Map<String, dynamic> ret = _d['retention'] is Map ? Map<String, dynamic>.from(_d['retention'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> busiest = _d['busiest'] is Map ? Map<String, dynamic>.from(_d['busiest'] as Map) : <String, dynamic>{};
    final List<Map<String, dynamic>> days = _list(busiest['weekdays']);
    final List<Map<String, dynamic>> hours = _list(busiest['hours']);
    final List<Map<String, dynamic>> services = _list(_d['top_services']);
    final int maxDay = days.fold<int>(0, (int m, Map<String, dynamic> r) => ((r['visits'] as num?)?.toInt() ?? 0) > m ? (r['visits'] as num).toInt() : m);

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Mwenendo wa biashara' : 'Business insights')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    Wrap(spacing: 8, children: <Widget>[
                      for (final int m in <int>[3, 6, 12])
                        ChoiceChip(
                          key: Key('ins_months_$m'),
                          label: Text(sw ? 'Miezi $m' : '$m months'),
                          selected: _months == m,
                          onSelected: (_) {
                            setState(() => _months = m);
                            _load();
                          },
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Text(sw ? 'Mapato kwa mwezi' : 'By month', style: const TextStyle(fontWeight: FontWeight.bold)),
                    for (final Map<String, dynamic> r in trend)
                      ListTile(
                        key: Key('ins_month_${r['month']}'),
                        dense: true,
                        title: Text('${r['month']}  ·  ${tsh((r['revenue'] as num?) ?? 0)}'),
                        subtitle: Text('${sw ? 'Faida' : 'Profit'} ${tsh((r['net_profit'] as num?) ?? 0)} · ${sw ? 'ziara' : 'visits'} ${r['visits']} · ${sw ? 'wapya' : 'new'} ${r['new_clients']} · ${sw ? 'wanaorudi' : 'returning'} ${r['returning_clients']}'),
                      ),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        key: const Key('ins_retention'),
                        title: Text(ret['rate'] == null ? '—' : '${ret['rate']}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        subtitle: Text(sw ? 'ya wateja wanarudi ndani ya siku ${ret['days'] ?? 60} (kati ya ${ret['eligible'] ?? 0})' : 'of clients come back within ${ret['days'] ?? 60} days (out of ${ret['eligible'] ?? 0})'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(sw ? 'Siku zenye shughuli' : 'Busiest days', style: const TextStyle(fontWeight: FontWeight.bold)),
                    for (final Map<String, dynamic> r in days)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: <Widget>[
                          SizedBox(width: 40, child: Text(dayName((r['day'] as num).toInt(), sw))),
                          Expanded(child: LinearProgressIndicator(value: maxDay == 0 ? 0 : ((r['visits'] as num).toDouble() / maxDay), minHeight: 8)),
                          SizedBox(width: 36, child: Text('${r['visits']}', textAlign: TextAlign.right)),
                        ]),
                      ),
                    if (hours.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(sw ? 'Saa zenye shughuli' : 'Busiest hours', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Wrap(spacing: 8, children: <Widget>[for (final Map<String, dynamic> r in hours) Chip(label: Text('${r['hour']}:00 · ${r['visits']}'))]),
                    ],
                    const SizedBox(height: 12),
                    Text(sw ? 'Huduma zinazoongoza' : 'Best services', style: const TextStyle(fontWeight: FontWeight.bold)),
                    for (final Map<String, dynamic> r in services) ListTile(dense: true, title: Text('${r['name']}'), subtitle: Text('${r['times']}×'), trailing: Text(tsh((r['total'] as num?) ?? 0))),
                  ]),
                ),
    );
  }
}
