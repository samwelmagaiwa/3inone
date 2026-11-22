/// Dividends, meetings, notices and texts of the Groups (Vikundi) service, typed once here.
library;

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

class GroupDividendLine {
  const GroupDividendLine({required this.memberId, required this.name, required this.base, required this.amount, this.memberNumber});

  factory GroupDividendLine.fromJson(final Map<String, dynamic> j) => GroupDividendLine(
        memberId: _int(j['member_id']) ?? 0,
        name: '${j['name'] ?? ''}',
        memberNumber: _str(j['member_number']),
        base: _num(j['base']),
        amount: _num(j['amount']),
      );

  final int memberId;
  final String name;
  final String? memberNumber;
  final double base;
  final double amount;
}

/// One dividend run: its period, the approved profit, the formula chosen, and (opened) every member's line.
class GroupDividendRun {
  const GroupDividendRun({
    required this.id,
    required this.periodFrom,
    required this.periodTo,
    required this.profitPool,
    required this.base,
    required this.method,
    required this.total,
    required this.status,
    this.rate,
    this.note,
    this.preparedByName,
    this.approvedByName,
    this.lines = const <GroupDividendLine>[],
  });

  factory GroupDividendRun.fromJson(final Map<String, dynamic> j) => GroupDividendRun(
        id: _int(j['id']) ?? 0,
        periodFrom: '${j['period_from'] ?? ''}',
        periodTo: '${j['period_to'] ?? ''}',
        profitPool: _num(j['profit_pool']),
        base: '${j['base'] ?? 'closing'}',
        method: '${j['method'] ?? 'rate'}',
        rate: j['rate'] == null ? null : _num(j['rate']),
        total: _num(j['total']),
        status: '${j['status'] ?? 'draft'}',
        note: _str(j['note']),
        preparedByName: _str(j['prepared_by_name']),
        approvedByName: _str(j['approved_by_name']),
        lines: <GroupDividendLine>[for (final dynamic l in (j['lines'] as List? ?? const <dynamic>[])) GroupDividendLine.fromJson(Map<String, dynamic>.from(l as Map))],
      );

  final int id;
  final String periodFrom;
  final String periodTo;
  final double profitPool;

  /// closing | average
  final String base;

  /// rate | share
  final String method;
  final double? rate;
  final double total;

  /// draft | posted | discarded
  final String status;
  final String? note;
  final String? preparedByName;
  final String? approvedByName;
  final List<GroupDividendLine> lines;
}

/// A member's own dividend from a posted run.
class GroupMyDividend {
  const GroupMyDividend({required this.periodFrom, required this.periodTo, required this.myBase, required this.amount, required this.base, required this.method, this.rate});

  factory GroupMyDividend.fromJson(final Map<String, dynamic> j) => GroupMyDividend(
        periodFrom: '${j['period_from'] ?? ''}',
        periodTo: '${j['period_to'] ?? ''}',
        myBase: _num(j['my_base']),
        amount: _num(j['amount']),
        base: '${j['base'] ?? ''}',
        method: '${j['method'] ?? ''}',
        rate: j['rate'] == null ? null : _num(j['rate']),
      );

  final String periodFrom;
  final String periodTo;
  final double myBase;
  final double amount;
  final String base;
  final String method;
  final double? rate;
}

/// A resolution or an action of a meeting's minutes.
class GroupMeetingItem {
  const GroupMeetingItem({required this.id, required this.meetingId, required this.kind, required this.text, required this.status, this.meetingTitle, this.assigneeId, this.assigneeName, this.dueDate, this.overdue = false});

  factory GroupMeetingItem.fromJson(final Map<String, dynamic> j) => GroupMeetingItem(
        id: _int(j['id']) ?? 0,
        meetingId: _int(j['meeting_id']) ?? 0,
        meetingTitle: _str(j['meeting_title']),
        kind: '${j['kind'] ?? 'resolution'}',
        text: '${j['text'] ?? ''}',
        assigneeId: _int(j['assignee_id']),
        assigneeName: _str(j['assignee_name']),
        dueDate: _str(j['due_date']),
        status: '${j['status'] ?? 'open'}',
        overdue: j['overdue'] == true,
      );

  final int id;
  final int meetingId;
  final String? meetingTitle;

  /// resolution | action
  final String kind;
  final String text;
  final int? assigneeId;
  final String? assigneeName;
  final String? dueDate;

  /// open | done
  final String status;
  final bool overdue;

  bool get done => status == 'done';
}

class GroupMeeting {
  const GroupMeeting({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.status,
    this.agenda,
    this.venue,
    this.minutes,
    this.cancelReason,
    this.calledByName,
    this.presentCount = 0,
    this.presentIds = const <int>[],
    this.iWasThere,
    this.minutesStatus = 'none',
    this.minutesApprovedByName,
    this.items = const <GroupMeetingItem>[],
  });

  factory GroupMeeting.fromJson(final Map<String, dynamic> j) => GroupMeeting(
        id: _int(j['id']) ?? 0,
        title: '${j['title'] ?? ''}',
        startsAt: '${j['starts_at'] ?? ''}',
        status: '${j['status'] ?? 'scheduled'}',
        agenda: _str(j['agenda']),
        venue: _str(j['venue']),
        minutes: _str(j['minutes']),
        cancelReason: _str(j['cancel_reason']),
        calledByName: _str(j['called_by_name']),
        presentCount: _int(j['present_count']) ?? 0,
        presentIds: <int>[for (final dynamic i in (j['present_ids'] as List? ?? const <dynamic>[])) _int(i) ?? 0],
        iWasThere: j['i_was_there'] is bool ? j['i_was_there'] as bool : null,
        minutesStatus: '${j['minutes_status'] ?? 'none'}',
        minutesApprovedByName: _str(j['minutes_approved_by_name']),
        items: <GroupMeetingItem>[for (final dynamic i in (j['items'] as List? ?? const <dynamic>[])) GroupMeetingItem.fromJson(Map<String, dynamic>.from(i as Map))],
      );

  final int id;
  final String title;
  final String startsAt;

  /// scheduled | held | cancelled
  final String status;
  final String? agenda;
  final String? venue;
  final String? minutes;
  final String? cancelReason;
  final String? calledByName;
  final int presentCount;
  final List<int> presentIds;
  final bool? iWasThere;

  /// none (not held) | draft (the chair has not approved it) | approved
  final String minutesStatus;
  final String? minutesApprovedByName;
  final List<GroupMeetingItem> items;

  DateTime? get when => DateTime.tryParse(startsAt);
}

class GroupAnnouncement {
  const GroupAnnouncement({required this.id, required this.title, required this.body, required this.category, required this.audience, this.expiresOn, this.authorName, this.createdAt});

  factory GroupAnnouncement.fromJson(final Map<String, dynamic> j) => GroupAnnouncement(
        id: _int(j['id']) ?? 0,
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        category: '${j['category'] ?? 'general'}',
        audience: '${j['audience'] ?? 'all'}',
        expiresOn: _str(j['expires_on']),
        authorName: _str(j['author_name']),
        createdAt: _str(j['created_at']),
      );

  final int id;
  final String title;
  final String body;
  final String category;

  /// all | officers
  final String audience;
  final String? expiresOn;
  final String? authorName;
  final String? createdAt;
}

/// A text sent to many members: to whom, how many went out.
class GroupMessage {
  const GroupMessage({required this.id, required this.body, required this.audience, required this.recipients, required this.sent, required this.parts, required this.status, this.sentByName, this.createdAt});

  factory GroupMessage.fromJson(final Map<String, dynamic> j) => GroupMessage(
        id: _int(j['id']) ?? 0,
        body: '${j['body'] ?? ''}',
        audience: '${j['audience'] ?? 'all'}',
        recipients: _int(j['recipients']) ?? 0,
        sent: _int(j['sent']) ?? 0,
        parts: _int(j['parts']) ?? 1,
        status: '${j['status'] ?? 'queued'}',
        sentByName: _str(j['sent_by_name']),
        createdAt: _str(j['created_at']),
      );

  final int id;
  final String body;
  final String audience;
  final int recipients;
  final int sent;
  final int parts;
  final String status;
  final String? sentByName;
  final String? createdAt;
}
