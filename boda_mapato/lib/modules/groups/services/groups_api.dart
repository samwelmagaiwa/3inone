import 'dart:typed_data';

import '../../../services/api_service.dart';
import '../models/group_asset_models.dart';
import '../models/group_expense_models.dart';
import '../models/group_governance_models.dart';
import '../models/group_loan_models.dart';
import '../models/group_models.dart';
import '../models/group_project_models.dart';
import '../models/group_receipt_models.dart';
import '../models/group_records_models.dart';
import '../models/group_voting_models.dart';

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

  /// A member registers a new member: tied to them as the one who brought them in, and a one-time password is sent by SMS to the phone
  /// number entered for the new member (it is never shown here). [smsSent] says whether the text was accepted.
  Future<({GroupMemberFile file, bool smsSent})> registerMember(final Map<String, dynamic> body) async {
    final Map<String, dynamic> d = _data(await _api.post('$_base/members/register', body));
    return (file: GroupMemberFile.fromJson(d), smsSent: d['sms_sent'] == true);
  }

  /// A new one-time password to the member's phone (for one who has not yet chosen their own); whether the text was accepted.
  Future<bool> resendOtp(final int memberId) async => _data(await _api.post('$_base/members/$memberId/resend-otp', <String, dynamic>{}))['sms_sent'] == true;

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

  /// A promise for oneself ([memberId] null) or, by a leader, for a member.
  Future<GroupPromise> makePromise(final Map<String, dynamic> body, {final int? memberId}) async => GroupPromise.fromJson(Map<String, dynamic>.from(
        _data(memberId == null ? await _api.post('$_base/me/promises', body) : await _api.post('$_base/promises', <String, dynamic>{...body, 'member_id': memberId}))['promise'] as Map,
      ));

  Future<void> cancelPromise(final int id) async => _api.post('$_base/promises/$id/cancel', <String, dynamic>{});

  /// A member's statement ([memberId]) or one's own (null).
  Future<GroupStatementData?> statement({final int? memberId, final String? from, final String? to}) async {
    final String query = <String>[if (from != null) 'from=$from', if (to != null) 'to=$to'].join('&');
    final Map<String, dynamic> res = await _api.get('${memberId == null ? '$_base/me/statement' : '$_base/members/$memberId/statement'}${query.isEmpty ? '' : '?$query'}');
    return res['data'] is Map ? GroupStatementData.fromJson(Map<String, dynamic>.from(res['data'] as Map)) : null;
  }

  // ---------------------------------------------------------------- loans

  Future<GroupLoanEligibility?> myEligibility() async {
    final Map<String, dynamic> res = await _api.get('$_base/me/loan-eligibility');
    return res['data'] is Map ? GroupLoanEligibility.fromJson(Map<String, dynamic>.from(res['data'] as Map)) : null;
  }

  /// One's own loans and the guarantees others asked of one.
  Future<(List<GroupLoan>, List<GroupGuarantee>)> myLoans() async {
    final Map<String, dynamic> d = _data(await _api.get('$_base/me/loans'));
    return (
      <GroupLoan>[for (final dynamic l in (d['loans'] as List? ?? const <dynamic>[])) GroupLoan.fromJson(Map<String, dynamic>.from(l as Map))],
      <GroupGuarantee>[for (final dynamic g in (d['guarantees'] as List? ?? const <dynamic>[])) GroupGuarantee.fromJson(Map<String, dynamic>.from(g as Map))],
    );
  }

  GroupLoan _loan(final Map<String, dynamic> res) => GroupLoan.fromJson(Map<String, dynamic>.from(_data(res)['loan'] as Map));

  Future<GroupLoan> applyLoan(final Map<String, dynamic> body) async => _loan(await _api.post('$_base/me/loans', body));

  Future<GroupLoan> addGuarantor(final int loanId, final int memberId) async => _loan(await _api.post('$_base/me/loans/$loanId/guarantors', <String, dynamic>{'member_id': memberId}));

  Future<GroupLoan> cancelLoan(final int loanId) async => _loan(await _api.post('$_base/me/loans/$loanId/cancel', <String, dynamic>{}));

  Future<GroupLoan> respondGuarantee(final int guaranteeId, {required final bool accept, final String? note}) async =>
      _loan(await _api.post('$_base/guarantees/$guaranteeId/respond', <String, dynamic>{'accept': accept, if (note != null) 'note': note}));

  Future<GroupLoanPage> loans({final String? status, final int page = 1}) async =>
      GroupLoanPage.fromJson(await _api.get('$_base/loans${_query(<String, String?>{'status': status, 'page': '$page'})}'));

  Future<GroupLoan> loan(final int id) async => _loan(await _api.get('$_base/loans/$id'));

  Future<GroupLoan> recommendLoan(final int id, {required final double amount, required final String note}) async =>
      _loan(await _api.post('$_base/loans/$id/recommend', <String, dynamic>{'amount': amount, 'note': note}));

  Future<GroupLoan> approveLoan(final int id, {final double? amount}) async => _loan(await _api.post('$_base/loans/$id/approve', <String, dynamic>{if (amount != null) 'amount': amount}));

  Future<GroupLoan> rejectLoan(final int id, final String reason) async => _loan(await _api.post('$_base/loans/$id/reject', <String, dynamic>{'reason': reason}));

  Future<GroupLoan> disburseLoan(final int id, {required final String method, final String? reference}) async =>
      _loan(await _api.post('$_base/loans/$id/disburse', <String, dynamic>{'method': method, if (reference != null && reference.isNotEmpty) 'external_ref': reference}));

  // ---------------------------------------------------------------- welfare

  Future<List<GroupBenefitType>> benefitTypes() async => <GroupBenefitType>[
        for (final dynamic t in (_data(await _api.get('$_base/benefit-types'))['types'] as List? ?? const <dynamic>[]))
          GroupBenefitType.fromJson(Map<String, dynamic>.from(t as Map)),
      ];

  Future<void> saveBenefitType(final Map<String, dynamic> body, {final int? id}) async {
    if (id == null) {
      await _api.post('$_base/benefit-types', body);
    } else {
      await _api.put('$_base/benefit-types/$id', body);
    }
  }

  List<GroupBenefitRequest> _requests(final Map<String, dynamic> res) => <GroupBenefitRequest>[
        for (final dynamic r in (_data(res)['requests'] as List? ?? const <dynamic>[])) GroupBenefitRequest.fromJson(Map<String, dynamic>.from(r as Map)),
      ];

  Future<List<GroupBenefitRequest>> myBenefits() async => _requests(await _api.get('$_base/me/benefits'));

  Future<void> applyBenefit(final Map<String, dynamic> body) async => _api.post('$_base/me/benefits', body);

  Future<void> cancelBenefit(final int id) async => _api.post('$_base/me/benefits/$id/cancel', <String, dynamic>{});

  Future<List<GroupBenefitRequest>> benefits({final String? status}) async => _requests(await _api.get('$_base/benefits${_query(<String, String?>{'status': status})}'));

  Future<void> decideBenefit(final int id, {required final bool approve, final double? amount, final String? note}) async =>
      _api.post('$_base/benefits/$id/decide', <String, dynamic>{'approve': approve, if (amount != null) 'amount': amount, if (note != null) 'note': note});

  Future<void> payBenefit(final int id, {required final String method, final String? reference}) async =>
      _api.post('$_base/benefits/$id/pay', <String, dynamic>{'method': method, if (reference != null && reference.isNotEmpty) 'external_ref': reference});

  // ---------------------------------------------------------------- assets and hiring out

  /// The assets this person may see, and whether they manage the register.
  Future<(List<GroupAsset>, bool)> assets() async {
    final Map<String, dynamic> d = _data(await _api.get('$_base/assets'));
    return (
      <GroupAsset>[for (final dynamic a in (d['assets'] as List? ?? const <dynamic>[])) GroupAsset.fromJson(Map<String, dynamic>.from(a as Map))],
      d['can_manage'] == true,
    );
  }

  /// One asset, its history (for its keeper and whoever manages assets) and whether this person handles its hires.
  Future<(GroupAsset, List<GroupAssetEvent>, bool)> asset(final int id) async {
    final Map<String, dynamic> d = _data(await _api.get('$_base/assets/$id'));
    return (
      GroupAsset.fromJson(Map<String, dynamic>.from(d['asset'] as Map)),
      <GroupAssetEvent>[for (final dynamic e in (d['events'] as List? ?? const <dynamic>[])) GroupAssetEvent.fromJson(Map<String, dynamic>.from(e as Map))],
      d['can_handle'] == true,
    );
  }

  /// How many are free from [from] to [to], how many days are charged, and the rate.
  Future<(int, int, double?)> availability(final int assetId, final String from, final String to) async {
    final Map<String, dynamic> d = _data(await _api.get('$_base/assets/$assetId/availability?from=$from&to=$to'));
    return ((d['free'] as num?)?.toInt() ?? 0, (d['days'] as num?)?.toInt() ?? 1, (d['rate'] as num?)?.toDouble());
  }

  Future<void> saveAsset(final Map<String, dynamic> body, {final int? id}) async {
    if (id == null) {
      await _api.post('$_base/assets', body);
    } else {
      await _api.put('$_base/assets/$id', body);
    }
  }

  Future<void> assetEvent(final int id, final Map<String, dynamic> body) async => _api.post('$_base/assets/$id/events', body);

  List<GroupHire> _hires(final Map<String, dynamic> res) =>
      <GroupHire>[for (final dynamic h in (_data(res)['hires'] as List? ?? const <dynamic>[])) GroupHire.fromJson(Map<String, dynamic>.from(h as Map))];

  GroupHire _hire(final Map<String, dynamic> res) => GroupHire.fromJson(Map<String, dynamic>.from(_data(res)['hire'] as Map));

  Future<List<GroupHire>> myHires() async => _hires(await _api.get('$_base/me/hires'));

  Future<GroupHire> askHire(final Map<String, dynamic> body) async => _hire(await _api.post('$_base/me/hires', body));

  Future<GroupHire> cancelHire(final int id) async => _hire(await _api.post('$_base/me/hires/$id/cancel', <String, dynamic>{}));

  Future<List<GroupHire>> hires({final String? status}) async => _hires(await _api.get('$_base/hires${_query(<String, String?>{'status': status})}'));

  /// The keeper (or a leader) writes down a hire for a member or someone outside the group.
  Future<GroupHire> askHireFor(final Map<String, dynamic> body) async => _hire(await _api.post('$_base/hires', body));

  Future<GroupHire> decideHire(final int id, {required final bool approve, final String? note}) async =>
      _hire(await _api.post('$_base/hires/$id/decide', <String, dynamic>{'approve': approve, if (note != null) 'note': note}));

  Future<GroupHire> issueHire(final int id, {required final int quantity, final String? condition}) async =>
      _hire(await _api.post('$_base/hires/$id/issue', <String, dynamic>{'quantity': quantity, if (condition != null && condition.isNotEmpty) 'condition': condition}));

  Future<GroupHire> returnHire(final int id, {required final int returned, final int damaged = 0, final int missing = 0, final String? note}) async => _hire(await _api.post(
        '$_base/hires/$id/return',
        <String, dynamic>{'returned': returned, 'damaged': damaged, 'missing': missing, if (note != null && note.isNotEmpty) 'note': note},
      ));

  Future<GroupHire> chargeHire(final int id, {required final double amount, required final String note}) async =>
      _hire(await _api.post('$_base/hires/$id/charge', <String, dynamic>{'amount': amount, 'note': note}));

  Future<GroupHire> payHire(final int id, {required final double amount, required final String method, final String? reference}) async => _hire(await _api.post(
        '$_base/hires/$id/pay',
        <String, dynamic>{'amount': amount, 'method': method, if (reference != null && reference.isNotEmpty) 'external_ref': reference},
      ));

  Future<GroupHire> closeHire(final int id) async => _hire(await _api.post('$_base/hires/$id/close', <String, dynamic>{}));

  // ---------------------------------------------------------------- dividends

  Future<List<GroupDividendRun>> dividendRuns() async => <GroupDividendRun>[
        for (final dynamic r in (_data(await _api.get('$_base/dividends'))['runs'] as List? ?? const <dynamic>[])) GroupDividendRun.fromJson(Map<String, dynamic>.from(r as Map)),
      ];

  GroupDividendRun _run(final Map<String, dynamic> res) => GroupDividendRun.fromJson(Map<String, dynamic>.from(_data(res)['run'] as Map));

  Future<GroupDividendRun> dividendRun(final int id) async => _run(await _api.get('$_base/dividends/$id'));

  Future<GroupDividendRun> prepareDividend(final Map<String, dynamic> body) async => _run(await _api.post('$_base/dividends', body));

  Future<GroupDividendRun> postDividend(final int id) async => _run(await _api.post('$_base/dividends/$id/post', <String, dynamic>{}));

  Future<GroupDividendRun> discardDividend(final int id) async => _run(await _api.post('$_base/dividends/$id/discard', <String, dynamic>{}));

  Future<List<GroupMyDividend>> myDividends() async => <GroupMyDividend>[
        for (final dynamic d in (_data(await _api.get('$_base/me/dividends'))['dividends'] as List? ?? const <dynamic>[])) GroupMyDividend.fromJson(Map<String, dynamic>.from(d as Map)),
      ];

  // ---------------------------------------------------------------- meetings, notices, texts

  Future<List<GroupMeeting>> meetings() async => <GroupMeeting>[
        for (final dynamic m in (_data(await _api.get('$_base/meetings'))['meetings'] as List? ?? const <dynamic>[])) GroupMeeting.fromJson(Map<String, dynamic>.from(m as Map)),
      ];

  Future<void> callMeeting(final Map<String, dynamic> body) async => _api.post('$_base/meetings', body);

  Future<void> cancelMeeting(final int id, final String reason) async => _api.post('$_base/meetings/$id/cancel', <String, dynamic>{'reason': reason});

  Future<void> addMeetingItem(final int id, final Map<String, dynamic> body) async => _api.post('$_base/meetings/$id/items', body);

  Future<void> removeMeetingItem(final int id, final int itemId) async => _api.delete('$_base/meetings/$id/items/$itemId');

  Future<void> completeMeetingItem(final int id, final int itemId) async => _api.post('$_base/meetings/$id/items/$itemId/done', <String, dynamic>{});

  Future<void> approveMinutes(final int id) async => _api.post('$_base/meetings/$id/approve-minutes', <String, dynamic>{});

  Future<void> reopenMinutes(final int id, final String reason) async => _api.post('$_base/meetings/$id/reopen-minutes', <String, dynamic>{'reason': reason});

  /// Open actions of approved minutes: one's own, or everyone's (for whoever records meetings).
  Future<List<GroupMeetingItem>> meetingActions({final bool all = false}) async => <GroupMeetingItem>[
        for (final dynamic a in (_data(await _api.get('$_base/meeting-actions${all ? '?scope=all' : ''}'))['actions'] as List? ?? const <dynamic>[]))
          GroupMeetingItem.fromJson(Map<String, dynamic>.from(a as Map)),
      ];

  Future<void> recordMeeting(final int id, {required final List<int> presentIds, final String? minutes}) async =>
      _api.post('$_base/meetings/$id/record', <String, dynamic>{'present_ids': presentIds, if (minutes != null) 'minutes': minutes});

  Future<List<GroupAnnouncement>> announcements() async => <GroupAnnouncement>[
        for (final dynamic a in (_data(await _api.get('$_base/announcements'))['announcements'] as List? ?? const <dynamic>[]))
          GroupAnnouncement.fromJson(Map<String, dynamic>.from(a as Map)),
      ];

  Future<void> postAnnouncement(final Map<String, dynamic> body) async => _api.post('$_base/announcements', body);

  Future<void> removeAnnouncement(final int id) async => _api.post('$_base/announcements/$id/remove', <String, dynamic>{});

  /// How many people and SMS parts a text would take: (people, parts each, parts in all).
  Future<(int, int, int)> estimateText({required final String audience, required final String body, final List<int>? memberIds}) async {
    final Map<String, dynamic> d = _data(await _api.post('$_base/messages/estimate', <String, dynamic>{'audience': audience, 'body': body, if (memberIds != null) 'member_ids': memberIds}));
    return ((d['recipients'] as num?)?.toInt() ?? 0, (d['parts_each'] as num?)?.toInt() ?? 1, (d['parts_total'] as num?)?.toInt() ?? 0);
  }

  Future<void> sendText({required final String audience, required final String body, final List<int>? memberIds}) async =>
      _api.post('$_base/messages', <String, dynamic>{'audience': audience, 'body': body, if (memberIds != null) 'member_ids': memberIds});

  Future<List<GroupMessage>> texts() async => <GroupMessage>[
        for (final dynamic m in (_data(await _api.get('$_base/messages'))['messages'] as List? ?? const <dynamic>[])) GroupMessage.fromJson(Map<String, dynamic>.from(m as Map)),
      ];

  // ---------------------------------------------------------------- invitations, the tree, documents, reports

  /// One's own invitation code (made the first time) and, for whoever registers members, the group's codes.
  Future<(GroupInvitation?, List<GroupInvitation>)> invitations() async {
    final Map<String, dynamic> d = _data(await _api.get('$_base/invitations'));
    return (
      d['mine'] is Map ? GroupInvitation.fromJson(Map<String, dynamic>.from(d['mine'] as Map)) : null,
      <GroupInvitation>[for (final dynamic i in (d['group'] as List? ?? const <dynamic>[])) GroupInvitation.fromJson(Map<String, dynamic>.from(i as Map))],
    );
  }

  Future<void> newGroupCode() async => _api.post('$_base/invitations', <String, dynamic>{});

  Future<void> stopCode(final int id) async => _api.post('$_base/invitations/$id/stop', <String, dynamic>{});

  List<GroupTreeNode> _nodes(final Map<String, dynamic> d) =>
      <GroupTreeNode>[for (final dynamic n in (d['nodes'] as List? ?? const <dynamic>[])) GroupTreeNode.fromJson(Map<String, dynamic>.from(n as Map))];

  /// The whole tree (leaders).
  Future<List<GroupTreeNode>> tree() async => _nodes(_data(await _api.get('$_base/tree')));

  /// One's own branch and its root.
  Future<(List<GroupTreeNode>, int?)> myBranch() async {
    final Map<String, dynamic> d = _data(await _api.get('$_base/me/referrals'));
    return (_nodes(d), (d['root'] as num?)?.toInt());
  }

  List<GroupDocument> _docs(final Map<String, dynamic> d) =>
      <GroupDocument>[for (final dynamic x in (d['documents'] as List? ?? const <dynamic>[])) GroupDocument.fromJson(Map<String, dynamic>.from(x as Map))];

  Future<List<GroupDocument>> documents(final int memberId) async => _docs(_data(await _api.get('$_base/members/$memberId/documents')));

  Future<List<GroupDocument>> uploadDocument(final int memberId, final Uint8List bytes, final String filename, {required final String kind, final String? caption}) async =>
      _docs(_data(await _api.uploadFile('$_base/members/$memberId/documents', 'file', bytes, filename, fields: <String, String>{'kind': kind, if (caption != null) 'caption': caption})));

  /// Sets the signed-in member's OWN profile photo (no right needed). The answer is the new link.
  Future<String?> uploadMyPhoto(final Uint8List bytes, final String filename) async {
    final Map<String, dynamic> d = _data(await _api.uploadFile('$_base/members/me/photo', 'file', bytes, filename));
    final Object? url = d['photo_url'];
    return url == null || '$url'.isEmpty ? null : '$url';
  }

  Future<List<GroupDocument>> removeDocument(final int memberId, final int id) async => _docs(_data(await _api.delete('$_base/members/$memberId/documents/$id')));

  // ---------------------------------------------------------------- payment methods

  /// The authorised payment methods and where to pay; [configured] is false until the group has chosen (then every method is accepted).
  Future<({bool configured, bool canManage, List<GroupPayMethod> methods})> paymentMethods() async {
    final Map<String, dynamic> d = _data(await _api.get('$_base/payment-methods'));
    return (
      configured: d['configured'] == true,
      canManage: d['can_manage'] == true,
      methods: <GroupPayMethod>[for (final dynamic m in (d['methods'] as List? ?? const <dynamic>[])) GroupPayMethod.fromJson(Map<String, dynamic>.from(m as Map))],
    );
  }

  /// Replaces the list of authorised methods (the Mwenyekiti or the Makamu); the reason goes to the activity log.
  Future<void> savePaymentMethods(final List<Map<String, dynamic>> methods, {required final String reason}) async {
    await _api.put('$_base/payment-methods', <String, dynamic>{'methods': methods, 'reason': reason});
  }

  // ---------------------------------------------------------------- voting

  GroupVoting _voting(final Map<String, dynamic> res) => GroupVoting.fromJson(Map<String, dynamic>.from(_data(res)['voting'] as Map));

  Future<List<GroupVoting>> votings() async => <GroupVoting>[
        for (final dynamic v in (_data(await _api.get('$_base/votings'))['votings'] as List? ?? const <dynamic>[])) GroupVoting.fromJson(Map<String, dynamic>.from(v as Map)),
      ];

  Future<GroupVoting> voting(final int id) async => _voting(await _api.get('$_base/votings/$id'));

  /// Casts (or, where the voting allows it, changes) the member's vote in THIS voting.
  Future<GroupVoting> vote(final int id, final int optionId) async => _voting(await _api.post('$_base/votings/$id/vote', <String, dynamic>{'option_id': optionId}));

  Future<GroupVoting> createVoting(final Map<String, dynamic> body) async => _voting(await _api.post('$_base/votings', body));

  Future<GroupVoting> updateVoting(final int id, final Map<String, dynamic> body) async => _voting(await _api.put('$_base/votings/$id', body));

  Future<void> deleteVoting(final int id) async {
    await _api.delete('$_base/votings/$id');
  }

  /// publish | pause | resume | close | cancel | extend | publish-results
  Future<GroupVoting> votingAction(final int id, final String action, {final Map<String, dynamic> body = const <String, dynamic>{}}) async =>
      _voting(await _api.post('$_base/votings/$id/$action', body));

  Future<VotingReport> votingReport(final int id) async => VotingReport.fromJson(_data(await _api.get('$_base/votings/$id/report')));

  Future<Uint8List> votingReportCsv(final int id) => _api.getFileBytes('$_base/votings/$id/report.csv');

  Future<(List<GroupNotice>, int)> notifications() async {
    final Map<String, dynamic> d = _data(await _api.get('$_base/me/notifications'));
    return (
      <GroupNotice>[for (final dynamic n in (d['notifications'] as List? ?? const <dynamic>[])) GroupNotice.fromJson(Map<String, dynamic>.from(n as Map))],
      d['unread'] is num ? (d['unread'] as num).toInt() : 0,
    );
  }

  Future<void> readNotifications({final List<int>? ids, final bool all = false}) async {
    await _api.post('$_base/me/notifications/read', <String, dynamic>{if (ids != null) 'ids': ids, if (all) 'all': true});
  }

  Future<GroupReport> report({required final String from, required final String to}) async => GroupReport.fromJson(_data(await _api.get('$_base/reports/summary?from=$from&to=$to')));

  /// The member register as a CSV file.
  Future<Uint8List> exportMembers() => _api.getFileBytes('$_base/reports/members.csv');

  /// The verified payments of a period as a CSV file.
  Future<Uint8List> exportPayments({required final String from, required final String to}) => _api.getFileBytes('$_base/reports/transactions.csv?from=$from&to=$to');

  /// The leaders' dashboard for [month] (2026-11; this month when null).
  Future<GroupDashboardData> dashboard({final String? month}) async =>
      GroupDashboardData.fromJson(_data(await _api.get('$_base/dashboard${month == null ? '' : '?month=$month'}')));

  // ---------------------------------------------------------------- someone outside the group, with a code (no sign-in)

  static String _code(final String code) => Uri.encodeComponent(code.trim().toUpperCase());

  Future<GroupPublicInfo> publicGroup(final String code) async =>
      GroupPublicInfo.fromJson(_data(await _api.get('/public/groups/${_code(code)}', requireAuth: false)));

  Future<(int, int, double)> publicAvailability(final String code, final int assetId, final String from, final String to) async {
    final Map<String, dynamic> d = _data(await _api.get('/public/groups/${_code(code)}/assets/$assetId/availability?from=$from&to=$to', requireAuth: false));
    return ((d['free'] as num?)?.toInt() ?? 0, (d['days'] as num?)?.toInt() ?? 1, (d['rate'] as num?)?.toDouble() ?? 0);
  }

  /// Apply to join; the answer is the application's reference.
  Future<String> publicApply(final String code, final Map<String, dynamic> body) async =>
      '${_data(await _api.post('/public/groups/${_code(code)}/apply', body, requireAuth: false))['application_ref'] ?? ''}';

  /// Ask to hire; the answer is (reference, amount).
  Future<(String, double)> publicHire(final String code, final Map<String, dynamic> body) async {
    final Map<String, dynamic> d = _data(await _api.post('/public/groups/${_code(code)}/hire', body, requireAuth: false));
    return ('${d['reference'] ?? ''}', (d['amount'] as num?)?.toDouble() ?? 0);
  }

  // ---------------------------------------------------------------- settings and the log

  Future<Map<String, dynamic>> settings() async => _data(await _api.get('$_base/settings'));

  Future<Map<String, dynamic>> saveSettings(final Map<String, dynamic> values, {required final String reason, final String? effectiveFrom}) async =>
      _data(await _api.put('$_base/settings', <String, dynamic>{'values': values, 'reason': reason, if (effectiveFrom != null) 'effective_from': effectiveFrom}));

  Future<List<Map<String, dynamic>>> activity({final int? before}) async => <Map<String, dynamic>>[
        for (final dynamic e in (_data(await _api.get('$_base/audit${before == null ? '' : '?before=$before'}'))['entries'] as List? ?? const <dynamic>[]))
          Map<String, dynamic>.from(e as Map),
      ];

  // ---------------------------------------------------------------- receipts

  /// The receipt of a verified payment (one's own, or any for whoever sees the finances).
  Future<GroupReceipt> receipt(final int id) async => GroupReceipt.fromJson(Map<String, dynamic>.from(_data(await _api.get('$_base/receipts/$id'))['receipt'] as Map));

  // ---------------------------------------------------------------- expenses (matumizi)

  Future<List<GroupExpense>> expenses({final String? status}) async => <GroupExpense>[
        for (final dynamic r in (_data(await _api.get('$_base/expenses${_query(<String, String?>{'status': status})}'))['requests'] as List? ?? const <dynamic>[]))
          GroupExpense.fromJson(Map<String, dynamic>.from(r as Map)),
      ];

  Future<void> requestExpense(final Map<String, dynamic> body) async => _api.post('$_base/expenses', body);

  Future<void> cancelExpense(final int id) async => _api.post('$_base/expenses/$id/cancel', <String, dynamic>{});

  Future<void> decideExpense(final int id, {required final bool approve, final double? amount, final String? note}) async =>
      _api.post('$_base/expenses/$id/decide', <String, dynamic>{'approve': approve, if (amount != null) 'amount': amount, if (note != null) 'note': note});

  Future<void> payExpense(final int id, {required final String method, final String? reference}) async =>
      _api.post('$_base/expenses/$id/pay', <String, dynamic>{'method': method, if (reference != null && reference.isNotEmpty) 'external_ref': reference});

  // ---------------------------------------------------------------- projects (miradi)

  Future<List<GroupProject>> projects({final String? status}) async => <GroupProject>[
        for (final dynamic p in (_data(await _api.get('$_base/projects${_query(<String, String?>{'status': status})}'))['projects'] as List? ?? const <dynamic>[]))
          GroupProject.fromJson(Map<String, dynamic>.from(p as Map)),
      ];

  GroupProject _project(final Map<String, dynamic> res) => GroupProject.fromJson(Map<String, dynamic>.from(_data(res)['project'] as Map));

  Future<GroupProject> project(final int id) async => _project(await _api.get('$_base/projects/$id'));

  Future<GroupProject> proposeProject(final Map<String, dynamic> body) async => _project(await _api.post('$_base/projects', body));

  Future<void> withdrawProject(final int id) async => _api.post('$_base/projects/$id/withdraw', <String, dynamic>{});

  Future<GroupProject> reviewProject(final int id, {required final bool supports, final String? note}) async =>
      _project(await _api.post('$_base/projects/$id/review', <String, dynamic>{'supports': supports, if (note != null) 'note': note}));

  Future<GroupProject> decideProject(final int id, {required final bool approve, final String? note}) async =>
      _project(await _api.post('$_base/projects/$id/decide', <String, dynamic>{'approve': approve, if (note != null) 'note': note}));

  Future<GroupProject> updateProject(final int id, final Map<String, dynamic> body) async => _project(await _api.put('$_base/projects/$id', body));

  Future<GroupProject> logProjectProgress(final int id, {required final int progress, required final String note}) async =>
      _project(await _api.post('$_base/projects/$id/progress', <String, dynamic>{'progress': progress, 'note': note}));

  Future<GroupProject> closeProject(final int id, {required final String outcome, required final String note}) async =>
      _project(await _api.post('$_base/projects/$id/close', <String, dynamic>{'outcome': outcome, 'note': note}));
}
