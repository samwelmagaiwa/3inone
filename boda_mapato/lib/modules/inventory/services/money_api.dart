import '../../../services/api_service.dart';

/// The owner's money tools: debts from before the app, the monthly report with its target, and the advice. Screens take
/// one of these so a test can hand them a fake with canned answers.
class MoneyApi {
  MoneyApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static String day(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String monthKey(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  Map<String, dynamic> _data(final Map<String, dynamic> res) => res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};

  /// The debts of one kind (`receivable` = owed to me, `payable` = I owe) with the totals.
  Future<Map<String, dynamic>> debts(final String kind, {final bool includePaid = false}) async =>
      _data(await _api.get('/inventory/opening-debts?kind=$kind${includePaid ? '&paid=1' : ''}'));

  Future<void> addDebt({
    required final String kind,
    required final String name,
    final String? phone,
    required final double amount,
    final DateTime? startedOn,
    final DateTime? dueOn,
    final String? note,
    final int? customerId,
  }) async {
    await _api.post('/inventory/opening-debts', <String, dynamic>{
      'kind': kind,
      'name': name,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      'amount': amount,
      if (startedOn != null) 'started_on': day(startedOn),
      if (dueOn != null) 'due_on': day(dueOn),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (customerId != null) 'customer_id': customerId,
    });
  }

  Future<void> payDebt(final int id, {required final double amount, final String? method, final String? note}) async {
    await _api.post('/inventory/opening-debts/$id/payments', <String, dynamic>{
      'amount': amount,
      if (method != null) 'method': method,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> debtPayments(final int id) async {
    final Map<String, dynamic> res = await _api.get('/inventory/opening-debts/$id/payments');
    final dynamic rows = res['data'];

    return <Map<String, dynamic>>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  Future<void> deleteDebt(final int id) async {
    await _api.delete('/inventory/opening-debts/$id');
  }

  /// A month in full ([month] is `2026-11`; null = this month).
  Future<Map<String, dynamic>> monthlyReport([final String? month]) async =>
      _data(await _api.get('/inventory/monthly-report${month == null ? '' : '?month=$month'}'));

  /// Set the profit target of a month; zero clears it. Returns the target as the report now shows it (null when cleared).
  Future<Map<String, dynamic>?> setTarget(final String month, final double target) async {
    final Map<String, dynamic> res = await _api.put('/inventory/monthly-target', <String, dynamic>{'month': month, 'profit_target': target});

    return res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
  }

  /// Where to do better: [lang] is `sw` or `en`; [refresh] asks for a fresh answer (a few a day).
  Future<Map<String, dynamic>> advice(final String month, final String lang, {final bool refresh = false}) async =>
      _data(await _api.get('/inventory/advice?month=$month&lang=$lang${refresh ? '&refresh=1' : ''}'));
}
