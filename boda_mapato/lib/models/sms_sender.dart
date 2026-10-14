/// The SMS sender name of a business: the name its customers' phones show instead of a number.
library;

/// Where a business's sender name stands. Only [approved] is ever used to send.
const List<String> kSmsSenderStatuses = <String>['none', 'pending', 'approved', 'rejected'];

/// What is known about one business's sender name. The owner sees the first four fields; the super admin sees all.
/// The API key itself is never here: only whether there is one and its last four characters.
class SmsSenderInfo {
  const SmsSenderInfo({
    this.senderId,
    this.displayName,
    this.status = 'none',
    this.note,
    this.requestedAt,
    this.approvedAt,
    this.sentCount = 0,
    this.ownCount = 0,
    this.fallbackCount = 0,
    this.lastSentAt,
    this.lastError,
    this.needsAttention = false,
    this.hasApiKey = false,
    this.hasApiSecret = false,
    this.apiKeyHint,
    this.fallbackPlatform = true,
  });

  factory SmsSenderInfo.fromJson(final Map<String, dynamic> json) => SmsSenderInfo(
        senderId: _text(json['sender_id']),
        displayName: _text(json['display_name']),
        status: kSmsSenderStatuses.contains(json['status']) ? json['status'] as String : 'none',
        note: _text(json['note']),
        requestedAt: _date(json['requested_at']),
        approvedAt: _date(json['approved_at']),
        sentCount: (json['sent_count'] as num?)?.toInt() ?? 0,
        ownCount: (json['own_count'] as num?)?.toInt() ?? 0,
        fallbackCount: (json['fallback_count'] as num?)?.toInt() ?? 0,
        lastSentAt: _date(json['last_sent_at']),
        lastError: _text(json['last_error']),
        needsAttention: json['needs_attention'] == true,
        hasApiKey: json['has_api_key'] == true,
        hasApiSecret: json['has_api_secret'] == true,
        apiKeyHint: _text(json['api_key_hint']),
        fallbackPlatform: json['fallback_platform'] != false,
      );

  final String? senderId;

  /// The (shorter) business name written inside the text; empty means the business name.
  final String? displayName;
  final String status;

  /// Why it was turned down, or a note.
  final String? note;
  final DateTime? requestedAt;
  final DateTime? approvedAt;

  /// Texts the provider accepted for this business, under any name / under its own name / after the provider refused
  /// its own name or account and the platform's was used.
  final int sentCount;
  final int ownCount;
  final int fallbackCount;
  final DateTime? lastSentAt;

  /// Why the name or key stopped working, when it did.
  final String? lastError;
  final bool needsAttention;

  /// The business has an SMS account of its own (its API key is stored on the server, encrypted).
  final bool hasApiKey;
  final bool hasApiSecret;
  final String? apiKeyHint;

  /// May a text go out through the platform's account when the business's own is refused?
  final bool fallbackPlatform;

  bool get hasSender => (senderId ?? '').isNotEmpty;
  bool get isApproved => status == 'approved' && hasSender;
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
}

/// One business in the super admin's list of sender names.
class SmsSenderEntry {
  const SmsSenderEntry({
    required this.id,
    required this.name,
    required this.sender,
    this.tin = '',
    this.phone = '',
    this.plan = '',
    this.ownerName = '',
    this.ownerPhone = '',
  });

  factory SmsSenderEntry.fromJson(final Map<String, dynamic> json) {
    final Object? owner = json['owner'];
    return SmsSenderEntry(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      tin: (json['tin'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      plan: (json['plan'] ?? '').toString(),
      ownerName: owner is Map ? (owner['name'] ?? '').toString() : '',
      ownerPhone: owner is Map ? (owner['phone_number'] ?? '').toString() : '',
      sender: json['sms_sender'] is Map ? SmsSenderInfo.fromJson(Map<String, dynamic>.from(json['sms_sender'] as Map)) : const SmsSenderInfo(),
    );
  }

  final String id;
  final String name;
  final String tin;
  final String phone;
  final String plan;
  final String ownerName;
  final String ownerPhone;
  final SmsSenderInfo sender;
}

/// A page of the list with the counts that go on the filter chips.
class SmsSenderPage {
  const SmsSenderPage({
    required this.items,
    this.counts = const <String, int>{},
    this.platformSender = '',
    this.smsDelivering = true,
    this.page = 1,
    this.hasMore = false,
  });

  final List<SmsSenderEntry> items;

  /// total, none, pending, approved, rejected, attention.
  final Map<String, int> counts;

  /// The name texts go out under when a business has none of its own.
  final String platformSender;

  /// Is a real SMS provider switched on at the server? When not, texts are only written to a log.
  final bool smsDelivering;
  final int page;
  final bool hasMore;

  int count(final String key) => counts[key] ?? 0;
}

/// The change a super admin saves for one business. Only what was typed is sent: an empty key field leaves the
/// saved key alone, and [clearCredentials] removes it.
class SmsSenderEdit {
  const SmsSenderEdit({
    this.senderId = '',
    this.displayName = '',
    this.status = 'approved',
    this.note = '',
    this.apiKey = '',
    this.apiSecret = '',
    this.clearCredentials = false,
    this.fallbackPlatform,
  });

  final String senderId;
  final String displayName;
  final String status;
  final String note;
  final String apiKey;
  final String apiSecret;
  final bool clearCredentials;
  final bool? fallbackPlatform;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sender_id': senderId.trim(),
        'display_name': displayName.trim(),
        'note': note.trim(),
        if (senderId.trim().isNotEmpty) 'status': status,
        if (apiKey.trim().isNotEmpty) 'api_key': apiKey.trim(),
        if (apiSecret.trim().isNotEmpty) 'api_secret': apiSecret.trim(),
        if (clearCredentials) 'clear_credentials': true,
        if (fallbackPlatform != null) 'fallback_platform': fallbackPlatform,
      };
}

/// What a test text showed. [outcome]: accepted | refused | no_answer | not_delivering.
class SmsSenderTestResult {
  const SmsSenderTestResult({required this.outcome, this.senderId = '', this.platformSender = '', this.ownAccount = false});

  factory SmsSenderTestResult.fromJson(final Map<String, dynamic> json) => SmsSenderTestResult(
        outcome: (json['outcome'] ?? 'no_answer').toString(),
        senderId: (json['sender_id'] ?? '').toString(),
        platformSender: (json['platform_sender'] ?? '').toString(),
        ownAccount: json['own_account'] == true,
      );

  final String outcome;
  final String senderId;
  final String platformSender;
  final bool ownAccount;

  bool get accepted => outcome == 'accepted';
}

/// The lines a super admin takes to the SMS provider to register the names that are waiting: the name, the business
/// it is for, its TIN and the owner's phone. Nothing is listed when no name is waiting.
String smsSenderRegistrationList(final Iterable<SmsSenderEntry> entries) {
  final List<SmsSenderEntry> waiting = entries.where((final SmsSenderEntry e) => e.sender.isPending && e.sender.hasSender).toList();
  if (waiting.isEmpty) return '';
  return <String>[
    'SENDER ID | BUSINESS | TIN | OWNER | OWNER PHONE',
    for (final SmsSenderEntry e in waiting)
      <String>[
        e.sender.senderId!.toUpperCase(),
        e.name,
        e.tin.isEmpty ? '-' : e.tin,
        e.ownerName.isEmpty ? '-' : e.ownerName,
        e.ownerPhone.isEmpty ? '-' : e.ownerPhone,
      ].join(' | '),
  ].join('\n');
}

String? _text(final Object? v) {
  final String t = (v ?? '').toString().trim();
  return t.isEmpty ? null : t;
}

DateTime? _date(final Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
