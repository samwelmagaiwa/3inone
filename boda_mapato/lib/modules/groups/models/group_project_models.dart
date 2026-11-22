/// Projects (miradi) of the Groups (Vikundi) service, typed once here.
library;

double _num(final Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

class GroupProjectUpdate {
  const GroupProjectUpdate(
      {required this.progress,
      required this.note,
      required this.createdAt,
      this.byName});

  factory GroupProjectUpdate.fromJson(final Map<String, dynamic> j) =>
      GroupProjectUpdate(
          progress: _int(j['progress']) ?? 0,
          note: '${j['note'] ?? ''}',
          createdAt: '${j['created_at'] ?? ''}',
          byName: _str(j['by_name']));

  final int progress;
  final String note;
  final String createdAt;
  final String? byName;
}

class GroupProjectReview {
  const GroupProjectReview(
      {required this.supports,
      required this.memberName,
      required this.mine,
      this.note});

  factory GroupProjectReview.fromJson(final Map<String, dynamic> j) =>
      GroupProjectReview(
          supports: j['supports'] == true,
          memberName: '${j['member_name'] ?? ''}',
          mine: j['mine'] == true,
          note: _str(j['note']));

  final bool supports;
  final String memberName;
  final bool mine;
  final String? note;
}

/// One project: proposed, running, finished or turned down.
class GroupProject {
  const GroupProject({
    required this.id,
    required this.reference,
    required this.title,
    required this.budget,
    required this.status,
    required this.progress,
    required this.supports,
    required this.opposes,
    this.description,
    this.startDate,
    this.endDate,
    this.proposedById,
    this.proposerName,
    this.managerId,
    this.managerName,
    this.decisionNote,
    this.closingNote,
    this.updates = const <GroupProjectUpdate>[],
    this.reviews = const <GroupProjectReview>[],
  });

  factory GroupProject.fromJson(final Map<String, dynamic> j) => GroupProject(
        id: _int(j['id']) ?? 0,
        reference: '${j['reference'] ?? ''}',
        title: '${j['title'] ?? ''}',
        description: _str(j['description']),
        budget: _num(j['budget']),
        startDate: _str(j['start_date']),
        endDate: _str(j['end_date']),
        proposedById: _int(j['proposed_by_id']),
        proposerName: _str(j['proposer_name']),
        managerId: _int(j['manager_id']),
        managerName: _str(j['manager_name']),
        status: '${j['status'] ?? 'proposed'}',
        progress: _int(j['progress']) ?? 0,
        supports: _int(j['supports']) ?? 0,
        opposes: _int(j['opposes']) ?? 0,
        decisionNote: _str(j['decision_note']),
        closingNote: _str(j['closing_note']),
        updates: <GroupProjectUpdate>[
          for (final dynamic u in (j['updates'] as List? ?? const <dynamic>[]))
            GroupProjectUpdate.fromJson(Map<String, dynamic>.from(u as Map))
        ],
        reviews: <GroupProjectReview>[
          for (final dynamic r in (j['reviews'] as List? ?? const <dynamic>[]))
            GroupProjectReview.fromJson(Map<String, dynamic>.from(r as Map))
        ],
      );

  final int id;
  final String reference;
  final String title;
  final String? description;
  final double budget;
  final String? startDate;
  final String? endDate;
  final int? proposedById;
  final String? proposerName;
  final int? managerId;
  final String? managerName;

  /// proposed | active | completed | rejected | cancelled
  final String status;
  final int progress;
  final int supports;
  final int opposes;
  final String? decisionNote;
  final String? closingNote;
  final List<GroupProjectUpdate> updates;
  final List<GroupProjectReview> reviews;

  bool get isOpen => status == 'proposed' || status == 'active';
}
