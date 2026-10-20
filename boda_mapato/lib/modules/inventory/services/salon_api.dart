import '../../../services/api_service.dart';
import '../models/salon_models.dart';

/// The salon's calls to the server. The screens take one of these so a test can hand them a fake with canned
/// answers; the app uses the real one. A failed call throws the [ApiException] of the server's own words.
class SalonApi {
  SalonApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static String _day(final DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _data(final Map<String, dynamic> res) => res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};

  /// How each stylist did between two days (this month when none are given).
  Future<StylistReport> stylists({final DateTime? from, final DateTime? to}) async {
    final List<String> q = <String>[if (from != null) 'from=${_day(from)}', if (to != null) 'to=${_day(to)}'];
    final Map<String, dynamic> res = await _api.get('/inventory/salon/stylists${q.isEmpty ? '' : '?${q.join('&')}'}');
    return StylistReport.fromJson(_data(res));
  }

  /// The "come back" settings and who is due now.
  Future<RebookOverview> rebookOverview() async => RebookOverview.fromJson(_data(await _api.get('/inventory/salon/rebook/due')));

  Future<RebookSettings> saveRebookSettings({final bool? enabled, final int? weeks}) async {
    final Map<String, dynamic> res = await _api.put('/inventory/salon/settings', <String, dynamic>{
      if (enabled != null) 'rebook_enabled': enabled,
      if (weeks != null) 'rebook_weeks': weeks,
    });
    return RebookSettings.fromJson(_data(res));
  }

  Future<ClientHistory> clientHistory(final int customerId) async =>
      ClientHistory.fromJson(_data(await _api.get('/inventory/salon/clients/$customerId/history')));

  /// Notes about a client and whether they may be texted. Only what is given is changed.
  Future<void> saveClient(final int customerId, {final String? notes, final bool? smsOptOut}) async {
    await _api.put('/inventory/salon/clients/$customerId', <String, dynamic>{
      if (notes != null) 'notes': notes,
      if (smsOptOut != null) 'sms_opt_out': smsOptOut,
    });
  }
}
