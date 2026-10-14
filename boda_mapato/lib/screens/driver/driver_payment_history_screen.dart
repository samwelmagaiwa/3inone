import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/server_message.dart';

class DriverPaymentHistoryScreen extends StatefulWidget {
  const DriverPaymentHistoryScreen({super.key});

  @override
  State<DriverPaymentHistoryScreen> createState() =>
      _DriverPaymentHistoryScreenState();
}

class _DriverPaymentHistoryScreenState
    extends State<DriverPaymentHistoryScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _entries =
      <Map<String, dynamic>>[]; // {date, type, amount, covered_days}
  double _outstanding = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final resPayments = await _api.getDriverPayments(limit: 200);
      final resDebts = await _api.getDriverDebtRecordsSelf(limit: 500);
      // Outstanding
      final unpaid =
          await _api.getDriverDebtRecordsSelf(limit: 1, onlyUnpaid: true);

      double outstanding = 0;
      final dynamic ud = unpaid['data'] ?? unpaid;
      if (ud is Map && ud['debt_records'] is List) {
        for (final r in ud['debt_records'] as List) {
          final m = (r as Map).cast<String, dynamic>();
          final double remain = _toDouble(m['remaining_amount']);
          outstanding += remain;
        }
      }

      // Build entries
      final List<Map<String, dynamic>> entries = <Map<String, dynamic>>[];
      // Payments
      final dynamic pd = resPayments['data'] ?? resPayments;
      final List<dynamic> payments = (pd is Map && pd['payments'] is List)
          ? (pd['payments'] as List)
          : (pd is Map && pd['data'] is List)
              ? (pd['data'] as List)
              : <dynamic>[];
      for (final p in payments) {
        final m = (p as Map).cast<String, dynamic>();
        entries.add({
          'type': 'payment',
          'amount': _toDouble(m['amount']),
          'date': m['payment_date']?.toString() ?? m['created_at']?.toString(),
          'covered_days': (m['covers_days'] is List)
              ? (m['covers_days'] as List).map((e) => e.toString()).toList()
              : <String>[],
          'reference': m['reference_number']?.toString() ?? '',
        });
      }
      // Debt clearances without Payment
      final dynamic dd = resDebts['data'] ?? resDebts;
      final List<dynamic> debts = (dd is Map && dd['debt_records'] is List)
          ? (dd['debt_records'] as List)
          : <dynamic>[];
      for (final d in debts) {
        final m = (d as Map).cast<String, dynamic>();
        if (m['is_paid'] == true &&
            (m['payment_id'] == null || m['payment_id'].toString().isEmpty)) {
          entries.add({
            'type': 'debt_clearance',
            'amount': _toDouble(m['paid_amount']),
            'date': m['paid_at']?.toString() ?? m['date']?.toString(),
            'covered_days': <String>[
              m['date']?.toString() ?? m['earning_date']?.toString() ?? ''
            ],
            'reference': '',
          });
        }
      }

      // Sort desc by date
      entries.sort((a, b) {
        final DateTime ad = DateTime.tryParse(a['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime bd = DateTime.tryParse(b['date']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

      setState(() {
        _entries = entries;
        _outstanding = outstanding;
        _isLoading = false;
      });
    } on Exception catch (e) {
      setState(() {
        _error = readableErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  double _toDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return ThemeConstants.buildScaffold(
      title: LocalizationService.instance.translate('payment_history'),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_error!, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 12),
        ElevatedButton(
            onPressed: _load,
            child: Text(LocalizationService.instance.translate('try_again'))),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: ThemeConstants.primaryBlue,
      backgroundColor: Colors.white,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(),
          const SizedBox(height: 12),
          ..._entries.map(_entryTile),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final bool hasDebt = _outstanding > 0.0;
    return ThemeConstants.buildGlassCardStatic(
      child: ListTile(
        leading: Icon(hasDebt ? Icons.error_outline : Icons.check_circle,
            color: hasDebt ? Colors.orange : Colors.green),
        title: Text(
            hasDebt
                ? LocalizationService.instance.translate('has_debt')
                : LocalizationService.instance.translate('no_debt'),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: hasDebt
            ? Text(
                '${LocalizationService.instance.translate('total_debt_label')}: TSH ${_outstanding.toStringAsFixed(0)}',
                style: TextStyle(color: Colors.white.withOpacity(0.85)))
            : null,
      ),
    );
  }

  Widget _entryTile(Map<String, dynamic> e) {
    final String type = e['type'] as String;
    final double amount = (e['amount'] as num).toDouble();
    final DateTime dt =
        DateTime.tryParse(e['date']?.toString() ?? '') ?? DateTime.now();
    final List<String> days = (e['covered_days'] as List)
        .map((x) => x.toString())
        .where((x) => x.isNotEmpty)
        .toList();
    final String title = type == 'payment'
        ? LocalizationService.instance.translate('payment')
        : LocalizationService.instance.translate('debt_clearance');
    final IconData icon = type == 'payment' ? Icons.payments : Icons.task_alt;
    final Color color =
        type == 'payment' ? ThemeConstants.primaryOrange : Colors.greenAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ThemeConstants.buildGlassCardStatic(
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text('$title • TSH ${amount.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('dd/MM/yyyy').format(dt),
                style: TextStyle(color: Colors.white.withOpacity(0.85))),
            if (days.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${LocalizationService.instance.translate('days')}: ${days.join(', ')}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8))),
              ),
          ]),
        ),
      ),
    );
  }
}
