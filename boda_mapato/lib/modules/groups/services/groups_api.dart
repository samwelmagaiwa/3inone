import '../../../services/api_service.dart';
import '../models/group_models.dart';

/// The Groups (Vikundi) service's calls to the server. Screens take one of these so a test can hand them a fake; a failed call throws the
/// [ApiException] carrying the server's own words.
class GroupsApi {
  GroupsApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static const String _base = '/groups';

  Map<String, dynamic> _data(final Map<String, dynamic> res) => res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};

  String _query(final Map<String, String?> q) {
    final List<String> parts = <String>[
      for (final MapEntry<String, String?> e in q.entries)
        if (e.value != null && e.value!.trim().isNotEmpty) '${e.key}=${Uri.encodeQueryComponent(e.value!.trim())}',
    ];
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  // ---------------------------------------------------------------- me

  Future<GroupMe> me() async => GroupMe.fromJson(_data(await _api.get('$_base/me')));

  Future<List<GroupTransaction>> myTransactions() async => <GroupTransaction>[
        for (final dynamic t in (_data(await _api.get('$_base/me/transactions'))['transactions'] as List? ?? const <dynamic>[]))
          GroupTransaction.fromJson(Map<String, dynamic>.from(t as Map)),
      ];

  /// The member says they paid; it waits for the treasurer.
  Future<GroupTransaction> payMine(final Map<String, dynamic> payment) async =>
      GroupTransaction.fromJson(Map<String, dynamic>.from(_data(await _api.post('$_base/me/payments', payment))['transaction'] as Map));

  // ---------------------------------------------------------------- members

  Future<GroupMemberPage> members({final String? status, final String? office, final String? query, final int page = 1}) async =>
      GroupMemberPage.fromJson(await _api.get('$_base/members${_query(<String, String?>{'status': status, 'office': office, 'q': query, 'page': '$page'})}'));

  Future<GroupMemberFile> member(final int id) async => GroupMemberFile.fromJson(_data(await _api.get('$_base/members/$id')));

  Future<GroupMemberFile> createMember(final Map<String, dynamic> body) async => GroupMemberFile.fromJson(_data(await _api.post('$_base/members', body)));

  Future<GroupMemberFile> updateMember(final int id, final Map<String, dynamic> body) async =>
      GroupMemberFile.fromJson(_data(await _api.put('$_base/members/$id', body)));

  /// approve | reject | suspend | reinstate | exit | deceased
  Future<GroupMemberFile> moveMember(final int id, final String action, {final String? reason}) async =>
      GroupMemberFile.fromJson(_data(await _api.post('$_base/members/$id/status', <String, dynamic>{'action': action, if (reason != null) 'reason': reason})));

  Future<GroupMemberFile> setOffice(final int id, final String? office, {final bool replace = false}) async =>
      GroupMemberFile.fromJson(_data(await _api.put('$_base/members/$id/office', <String, dynamic>{'office': office, 'replace': replace})));

  Future<GroupMemberFile> saveDependant(final int memberId, final Map<String, dynamic> body, {final int? id}) async => GroupMemberFile.fromJson(_data(
        id == null ? await _api.post('$_base/members/$memberId/dependants', body) : await _api.put('$_base/members/$memberId/dependants/$id', body),
      ));

  Future<GroupMemberFile> deleteDependant(final int memberId, final int id) async =>
      GroupMemberFile.fromJson(_data(await _api.delete('$_base/members/$memberId/dependants/$id')));

  /// Gives the member a sign-in (or, with [reset], a new one-time password). The password is in the answer once.
  Future<Map<String, dynamic>> signIn(final int id, {final bool reset = false}) async =>
      _data(await _api.post('$_base/members/$id/sign-in', <String, dynamic>{if (reset) 'reset': true}));

  // ---------------------------------------------------------------- money

  Future<GroupTransactionPage> transactions({final String? status, final String? category, final int? memberId, final String? query, final int page = 1}) async =>
      GroupTransactionPage.fromJson(await _api.get('$_base/transactions${_query(<String, String?>{
            'status': status,
            'category': category,
            'member_id': memberId?.toString(),
            'q': query,
            'page': '$page',
          })}'));

  Future<Map<String, dynamic>> moneySummary({final String? month}) async => _data(await _api.get('$_base/transactions/summary${month == null ? '' : '?month=$month'}'));

  Future<GroupTransaction> recordPayment(final Map<String, dynamic> payment) async =>
      GroupTransaction.fromJson(Map<String, dynamic>.from(_data(await _api.post('$_base/transactions', payment))['transaction'] as Map));

  Future<GroupTransaction> verify(final int id) async =>
      GroupTransaction.fromJson(Map<String, dynamic>.from(_data(await _api.post('$_base/transactions/$id/verify', <String, dynamic>{}))['transaction'] as Map));

  Future<GroupTransaction> reject(final int id, final String reason) async =>
      GroupTransaction.fromJson(Map<String, dynamic>.from(_data(await _api.post('$_base/transactions/$id/reject', <String, dynamic>{'reason': reason}))['transaction'] as Map));

  Future<GroupTransaction> reverse(final int id, final String reason) async =>
      GroupTransaction.fromJson(Map<String, dynamic>.from(_data(await _api.post('$_base/transactions/$id/reverse', <String, dynamic>{'reason': reason}))['transaction'] as Map));

  // ---------------------------------------------------------------- contributions, promises, statements

  Future<List<GroupContributionType>> contributionTypes() async => <GroupContributionType>[
        for (final dynamic t in (_data(await _api.get('$_base/contribution-types'))['types'] as List? ?? const <dynamic>[]))
          GroupContributionType.fromJson(Map<String, dynamic>.from(t as Map)),
      ];

  Future<GroupContributionType> saveContributionType(final Map<String, dynamic> body, {final int? id}) async => GroupContributionType.fromJson(Map<String, dynamic>.from(
        _data(id == null ? await _api.post('$_base/contribution-types', body) : await _api.put('$_base/contribution-types/$id', body))['type'] as Map,
      ));

  /// Raise a call: monthly for [month] (2026-11), once or an event on [dueDate] (an event says what it is for in [label]). Returns how many
  /// members now owe it.
  Future<int> raiseContribution(final int typeId, {final String? month, final String? dueDate, final String? label}) async {
    final Map<String, dynamic> d = _data(await _api.post('$_base/contribution-types/$typeId/raise', <String, dynamic>{
      if (month != null) 'month': month,
      if (dueDate != null) 'due_date': dueDate,
      if (label != null) 'label': label,
    }));
    return (d['created'] as num?)?.toInt() ?? 0;
  }

  Future<GroupObligationPage> obligations({final String state = 'owing', final int? typeId, final int? memberId, final String? query, final int page = 1}) async =>
      GroupObligationPage.fromJson(await _api.get('$_base/obligations${_query(<String, String?>{
            'state': state,
            'type_id': typeId?.toString(),
            'member_id': memberId?.toString(),
            'q': query,
            'page': '$page',
          })}'));

  Future<void> exempt(final int obligationId, final String reason) async => _api.post('$_base/obligations/$obligationId/exempt', <String, dynamic>{'reason': reason});

  Future<List<GroupPromise>> promises({final int? memberId}) async => <GroupPromise>[
        for (final dynamic p in (_data(await _api.get('$_base/promises${_query(<String, String?>{'member_id': memberId?.toString()})}'))['promises'] as List? ?? const <dynamic>[]))
          GroupPromise.fromJson(Map<String, dynamic>.from(p as Map)),
      ];

  /// A promise for oneself ([memberId] null) or, by an officer, for a member.
  Future<GroupPromise> makePromise(final Map<String, dynamic> body, {final int? memberId}) async => GroupPromise.fromJson(Map<String, dynamic>.from(
        _data(memberId == null ? await _api.post('$_base/me/promises', body) : await _api.post('$_base/promises', <String, dynamic>{...body, 'member_id': memberId}))['promise'] as Map,
      ));

  Future<void> cancelPromise(final int id) async => _api.post('$_base/promises/$id/cancel', <String, dynamic>{});

  /// A member's statement ([memberId]) or one's own (null).
  Future<GroupStatementData?> statement({final int? memberId}) async {
    final Map<String, dynamic> res = await _api.get(memberId == null ? '$_base/me/statement' : '$_base/members/$memberId/statement');
    return res['data'] is Map ? GroupStatementData.fromJson(Map<String, dynamic>.from(res['data'] as Map)) : null;
  }

  // ---------------------------------------------------------------- settings and the log

  Future<Map<String, dynamic>> settings() async => _data(await _api.get('$_base/settings'));

  Future<Map<String, dynamic>> saveSettings(final Map<String, dynamic> values, {required final String reason, final String? effectiveFrom}) async =>
      _data(await _api.put('$_base/settings', <String, dynamic>{'values': values, 'reason': reason, if (effectiveFrom != null) 'effective_from': effectiveFrom}));

  Future<List<Map<String, dynamic>>> activity({final int? before}) async => <Map<String, dynamic>>[
        for (final dynamic e in (_data(await _api.get('$_base/audit${before == null ? '' : '?before=$before'}'))['entries'] as List? ?? const <dynamic>[]))
          Map<String, dynamic>.from(e as Map),
      ];
}
