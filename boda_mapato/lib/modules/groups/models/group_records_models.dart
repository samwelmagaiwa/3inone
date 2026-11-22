/// Invitations, the referral tree, documents and reports of the Groups (Vikundi) service.
library;

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

class GroupInvitation {
  const GroupInvitation({required this.id, required this.code, required this.kind, required this.active, required this.used});

  factory GroupInvitation.fromJson(final Map<String, dynamic> j) =>
      GroupInvitation(id: _int(j['id']) ?? 0, code: '${j['code'] ?? ''}', kind: '${j['kind'] ?? 'member'}', active: j['active'] != false, used: _int(j['used']) ?? 0);

  final int id;
  final String code;

  /// member | group
  final String kind;
  final bool active;
  final int used;
}

/// One person in the referral tree.
class GroupTreeNode {
  const GroupTreeNode({required this.id, required this.name, required this.status, this.memberNumber, this.referrerId, this.joinedOn, this.founding = false, this.office});

  factory GroupTreeNode.fromJson(final Map<String, dynamic> j) => GroupTreeNode(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        status: '${j['status'] ?? 'active'}',
        memberNumber: _str(j['member_number']),
        referrerId: _int(j['referrer_id']),
        joinedOn: _str(j['joined_on']),
        founding: j['founding'] == true,
        office: _str(j['office']),
      );

  final int id;
  final String name;
  final String status;
  final String? memberNumber;
  final int? referrerId;
  final String? joinedOn;
  final bool founding;
  final String? office;
}

class GroupDocument {
  const GroupDocument({required this.id, required this.kind, this.caption, this.url});

  factory GroupDocument.fromJson(final Map<String, dynamic> j) => GroupDocument(id: _int(j['id']) ?? 0, kind: '${j['kind'] ?? 'other'}', caption: _str(j['caption']), url: _str(j['url']));

  final int id;

  /// photo | id | other
  final String kind;
  final String? caption;
  final String? url;
}

/// The group in numbers for a period.
class GroupReport {
  const GroupReport({required this.byStatus, required this.joined, required this.money, required this.contributions, required this.loans, required this.meetingsHeld});

  factory GroupReport.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> members = j['members'] is Map ? Map<String, dynamic>.from(j['members'] as Map) : <String, dynamic>{};
    return GroupReport(
      byStatus: <String, int>{if (members['by_status'] is Map) for (final MapEntry<dynamic, dynamic> e in (members['by_status'] as Map).entries) '${e.key}': _int(e.value) ?? 0},
      joined: _int(members['joined']) ?? 0,
      money: <String, (double, double)>{
        if (j['money'] is Map)
          for (final MapEntry<dynamic, dynamic> e in (j['money'] as Map).entries)
            '${e.key}': (_num((e.value as Map)['in']), _num((e.value as Map)['out'])),
      },
      contributions: <String, double>{if (j['contributions'] is Map) for (final MapEntry<dynamic, dynamic> e in (j['contributions'] as Map).entries) '${e.key}': _num(e.value)},
      loans: <String, double>{if (j['loans_now'] is Map) for (final MapEntry<dynamic, dynamic> e in (j['loans_now'] as Map).entries) '${e.key}': _num(e.value)},
      meetingsHeld: _int(j['meetings_held']) ?? 0,
    );
  }

  final Map<String, int> byStatus;
  final int joined;

  /// kind of money => (in, out)
  final Map<String, (double, double)> money;
  final Map<String, double> contributions;
  final Map<String, double> loans;
  final int meetingsHeld;
}

/// What a code shows someone outside the group.
class GroupPublicInfo {
  const GroupPublicInfo({required this.group, required this.assets, this.invitedBy});

  factory GroupPublicInfo.fromJson(final Map<String, dynamic> j) => GroupPublicInfo(
        group: '${j['group'] ?? ''}',
        invitedBy: _str(j['invited_by']),
        assets: <(int, String, double, int)>[
          for (final dynamic a in (j['assets'] as List? ?? const <dynamic>[]))
            if (a is Map) (_int(a['id']) ?? 0, '${a['name'] ?? ''}', _num(a['hire_rate']), _int(a['free_today']) ?? 0),
        ],
      );

  final String group;
  final String? invitedBy;

  /// (id, name, rate a day, free today)
  final List<(int, String, double, int)> assets;
}
