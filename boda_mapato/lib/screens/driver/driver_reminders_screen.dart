// ignore_for_file: unused_field
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';

class DriverRemindersScreen extends StatefulWidget {
  const DriverRemindersScreen({super.key});

  @override
  State<DriverRemindersScreen> createState() => _DriverRemindersScreenState();
}

class _DriverRemindersScreenState extends State<DriverRemindersScreen> {
  // Debts
  bool _isLoadingDebts = true;
  List<Map<String, dynamic>> _debts = <Map<String, dynamic>>[];
  double _debtsTotal = 0;
  final ApiService _api = ApiService();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _reminders = <Map<String, dynamic>>[];

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
      final Map<String, dynamic> res =
          await _api.getDriverReminders(limit: 100);
      final Map<String, dynamic> debtsRes =
          await _api.getDriverDebtRecordsSelf(limit: 500, onlyUnpaid: true);
      final dynamic data = res['data'] ?? res;
      final List<dynamic> list =
          (data is Map && data is! List && data['data'] is List)
              ? (data['data'] as List)
              : (data is List)
                  ? data
                  : (data is Map && data['reminders'] is List)
                      ? (data['reminders'] as List)
                      : <dynamic>[];
      final dynamic ddata = debtsRes['data'] ?? debtsRes;
      final List<dynamic> dlist =
          (ddata is Map && ddata['debt_records'] is List)
              ? (ddata['debt_records'] as List)
              : <dynamic>[];
      final List<Map<String, dynamic>> debts =
          dlist.map((e) => (e as Map).cast<String, dynamic>()).toList();
      final double total = debts.fold(
          0,
          (sum, m) =>
              sum + _toDouble(m['remaining_amount'] ?? m['expected_amount']));
      setState(() {
        _reminders =
            list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _debts = debts;
        _debtsTotal = total;
        _isLoading = false;
        _isLoadingDebts = false;
      });
    } on Exception catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeConstants.buildScaffold(
      title: LocalizationService.instance.translate('reminders'),
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
    if (_reminders.isEmpty) {
      return Center(
          child: Text(LocalizationService.instance.translate('no_reminders'),
              style: TextStyle(color: Colors.white.withOpacity(0.85))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: ThemeConstants.primaryBlue,
      backgroundColor: Colors.white,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Outstanding debts summary
          ThemeConstants.buildGlassCardStatic(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet,
                      color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${LocalizationService.instance.translate('outstanding_debts')}: TSH ${_debtsTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Unpaid debts list
          ..._debts.map(_debtTile),
          const SizedBox(height: 16),
          // Reminders list
          ..._reminders.map(_reminderTile),
        ],
      ),
    );
  }

  Widget _reminderTile(Map<String, dynamic> r) {
    final String title = (r['title']?.toString() ?? '').isNotEmpty
        ? r['title'].toString()
        : (r['reminder_type']?.toString() ?? LocalizationService.instance.translate('reminder'));
    final String msg = r['message']?.toString() ?? '';
    final String status = r['status']?.toString() ?? 'active';
    final String priority = r['priority']?.toString() ?? 'low';
    final DateTime? date =
        DateTime.tryParse(r['reminder_date']?.toString() ?? '') ??
            DateTime.tryParse(r['reminder_time']?.toString() ?? '');
    final bool overdue =
        (status == 'active') && (date != null && date.isBefore(DateTime.now()));
    final Color dot = overdue
        ? Colors.redAccent
        : (priority == 'high' || priority == 'urgent')
            ? Colors.orange
            : Colors.greenAccent;
    return ThemeConstants.buildGlassCardStatic(
      child: ListTile(
        leading: Icon(
            overdue ? Icons.warning_amber_rounded : Icons.notifications,
            color: dot),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (msg.isNotEmpty)
            Text(msg, style: TextStyle(color: Colors.white.withOpacity(0.85))),
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(DateFormat('dd/MM/yyyy').format(date),
                  style: TextStyle(color: Colors.white.withOpacity(0.8))),
            ),
        ]),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
          child: Text(_statusText(status),
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _debtTile(Map<String, dynamic> m) {
    final String date =
        m['formatted_date']?.toString() ?? m['date']?.toString() ?? '';
    final int overdue = (m['days_overdue'] is int)
        ? m['days_overdue'] as int
        : int.tryParse(m['days_overdue']?.toString() ?? '0') ?? 0;
    final double remain =
        _toDouble(m['remaining_amount'] ?? m['expected_amount']);
    return ThemeConstants.buildGlassCardStatic(
      child: ListTile(
        leading: const Icon(Icons.event_busy, color: Colors.orangeAccent),
        title: Text('TSH ${remain.toStringAsFixed(0)}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${LocalizationService.instance.translate('due_date')}: $date\n${LocalizationService.instance.translate('days_overdue')}: $overdue',
            style: TextStyle(color: Colors.white.withOpacity(0.85))),
      ),
    );
  }

  String _statusText(String s) {
    switch (s) {
      case 'active':
        return LocalizationService.instance.translate('status_active');
      case 'completed':
        return LocalizationService.instance.translate('status_completed');
      case 'cancelled':
        return LocalizationService.instance.translate('status_cancelled');
      case 'expired':
        return LocalizationService.instance.translate('status_expired');
      default:
        return s;
    }
  }

  double _toDouble(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
