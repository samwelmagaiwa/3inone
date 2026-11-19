/// How many SMS a business has used against the limit the super admin set for it (server: App\Support\SmsQuota).
library;

class SmsUsage {
  const SmsUsage({
    this.used = 0,
    this.limit,
    this.remaining,
    this.percent,
    this.blocked = false,
    this.warned = false,
    this.weekMessages = 0,
    this.weekParts = 0,
    this.countedIn = 'parts',
  });

  factory SmsUsage.fromJson(final Map<String, dynamic> json) => SmsUsage(
        used: (json['used'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt(),
        remaining: (json['remaining'] as num?)?.toInt(),
        percent: (json['percent'] as num?)?.toInt(),
        blocked: json['blocked'] == true,
        warned: json['warned'] == true,
        weekMessages: (json['week_messages'] as num?)?.toInt() ?? 0,
        weekParts: (json['week_parts'] as num?)?.toInt() ?? 0,
        countedIn: (json['counted_in'] ?? 'parts').toString(),
      );

  static SmsUsage? maybe(final Object? json) => json is Map ? SmsUsage.fromJson(Map<String, dynamic>.from(json)) : null;

  /// SMS used since the counter was last started.
  final int used;

  /// SMS allowed; null = no limit.
  final int? limit;
  final int? remaining;
  final int? percent;

  /// The limit is used up: the business's texts are stopped.
  final bool blocked;

  /// The owner and the super admin were told it is nearly used up.
  final bool warned;
  final int weekMessages;
  final int weekParts;
  final String countedIn;

  bool get hasLimit => limit != null;

  /// "20/1000", or "20" when there is no limit.
  String get badge => hasLimit ? '$used/$limit' : '$used';

  /// 0..1 for a progress bar (0 when there is no limit).
  double get fraction => (limit == null || limit == 0) ? (blocked ? 1 : 0) : (used / limit!).clamp(0, 1).toDouble();
}
