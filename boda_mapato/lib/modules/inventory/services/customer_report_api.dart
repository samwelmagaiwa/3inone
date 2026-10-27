import '../../../services/api_service.dart';

/// One customer's story with the business for a period: what they bought, what they paid, the profit they brought, what they owe now.
/// Screens take one of these so a test can hand them a fake with canned answers.
class CustomerReportApi {
  CustomerReportApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static String day(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// [group] is `day`, `week` or `month`. The server works the days in Tanzania time.
  Future<Map<String, dynamic>> report(final int customerId, {required final DateTime from, required final DateTime to, required final String group}) async {
    final Map<String, dynamic> res = await _api.get('/inventory/credit/customers/$customerId/report?from=${day(from)}&to=${day(to)}&group=$group');

    return res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
  }
}
