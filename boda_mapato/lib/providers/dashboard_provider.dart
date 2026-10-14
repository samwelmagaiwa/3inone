import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../utils/server_message.dart';

class DashboardProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  bool _loading = false;
  String? _error;

  // Counts
  int activeDrivers = 0;
  int activeDevices = 0;
  int unpaidDebts = 0;
  int generatedReceipts = 0;
  int pendingReceipts = 0;

  // Revenue
  double dailyRevenue = 0;
  double weeklyRevenue = 0;
  double monthlyRevenue = 0;

  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> loadAll() async {
    _setLoading(true);
    _setError(null);

    try {
      // Fetch all card endpoints concurrently
      final results = await Future.wait<Map<String, dynamic>>([
        _api.getActiveDriversCount(),
        _api.getActiveDevicesCount(),
        _api.getUnpaidDebtsCount(),
        _api.getGeneratedReceiptsCount(),
        _api.getPendingReceiptsCount(),
        _api.getDailyRevenue(),
        _api.getWeeklyRevenue(),
        _api.getMonthlyRevenue(),
      ]);

      final d0 = _extract(results[0]);
      final d1 = _extract(results[1]);
      final d2 = _extract(results[2]);
      final d3 = _extract(results[3]);
      final d4 = _extract(results[4]);
      final d5 = _extract(results[5]);
      final d6 = _extract(results[6]);
      final d7 = _extract(results[7]);

      activeDrivers = _toInt(d0['count']);
      activeDevices = _toInt(d1['count']);
      unpaidDebts = _toInt(d2['count']);
      generatedReceipts = _toInt(d3['count']);
      pendingReceipts = _toInt(d4['count']);

      dailyRevenue =
          _toDouble(d5['revenue'] ?? d5['daily_revenue'] ?? d5['total']);
      weeklyRevenue =
          _toDouble(d6['revenue'] ?? d6['weekly_revenue'] ?? d6['total']);
      monthlyRevenue =
          _toDouble(d7['revenue'] ?? d7['monthly_revenue'] ?? d7['total']);
    } on Exception catch (e) {
      _setError(readableErrorMessage(e));
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refresh() => loadAll();

  Map<String, dynamic> _extract(Map<String, dynamic> response) {
    if (response.containsKey('data') &&
        response['data'] is Map<String, dynamic>) {
      return response['data'] as Map<String, dynamic>;
    }
    return response;
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _error = value;
    notifyListeners();
  }

  int _toInt(v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _toDouble(v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
