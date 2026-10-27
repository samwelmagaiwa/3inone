import '../../../services/api_service.dart';

/// Who works in which branch, and what each branch and each person sold. Screens take one of these so a test can hand them a fake.
class BranchTeamApi {
  BranchTeamApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static String day(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _rows(final Map<String, dynamic> res) => <Map<String, dynamic>>[
        if (res['data'] is List)
          for (final dynamic r in res['data'] as List)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  /// Each person with `branch_id` (null = not tied to one).
  Future<List<Map<String, dynamic>>> team() async => _rows(await _api.get('/inventory/branch-team'));

  /// The branches that can be chosen (`id`, `name`, `active`).
  Future<List<Map<String, dynamic>>> branches() async => _rows(await _api.get('/inventory/branches'));

  /// Place a person in a branch; null takes them out of any branch.
  Future<void> assign(final String staffId, final int? branchId) async {
    await _api.put('/inventory/branch-team/$staffId', <String, dynamic>{'branch_id': branchId});
  }

  /// `{by_branch, by_staff, total}` for the period (profit is null when the person may not see it).
  Future<Map<String, dynamic>> sales(final DateTime from, final DateTime to) async {
    final Map<String, dynamic> res = await _api.get('/inventory/branch-sales?from=${day(from)}&to=${day(to)}');

    return res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
  }
}
