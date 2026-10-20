/// What the salon screens read from the server: how each stylist did, who is due to be reminded to come back,
/// and a client's history. Everything is read defensively: a missing or oddly typed field becomes a zero or an
/// empty text, never a crash on a client's phone.
library;

int _int(final dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

double _num(final dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String _text(final dynamic v) => v == null ? '' : '$v';

DateTime? _date(final dynamic v) => v == null ? null : DateTime.tryParse('$v');

bool _flag(final dynamic v) => v == true || v == 1 || v == '1';

List<Map<String, dynamic>> _rows(final dynamic v) =>
    v is List ? <Map<String, dynamic>>[for (final dynamic r in v) if (r is Map) Map<String, dynamic>.from(r)] : <Map<String, dynamic>>[];

// ------------------------------------------------------------------ how each stylist did

class StylistRow {
  const StylistRow({required this.staffId, required this.name, required this.services, required this.revenue, required this.visits, required this.clients, this.commission = 0});

  factory StylistRow.fromJson(final Map<String, dynamic> j) => StylistRow(
        staffId: j['staff_id'] == null ? null : _text(j['staff_id']),
        name: _text(j['name']),
        services: _int(j['services']),
        revenue: _num(j['revenue']),
        commission: _num(j['commission']),
        visits: _int(j['visits']),
        clients: _int(j['clients']),
      );

  /// The stylist's account id; null for the line "nobody was named" (a walk-in whose stylist was not picked).
  final String? staffId;
  final String name;
  final int services;
  final double revenue;

  /// What this stylist earned in commission on those services (0 when no service has a rate).
  final double commission;
  final int visits;
  final int clients;

  bool get isUnassigned => staffId == null;
}

class StylistReport {
  const StylistReport({required this.from, required this.to, required this.stylists, required this.services, required this.revenue, required this.visits, this.commission = 0});

  factory StylistReport.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> totals = j['totals'] is Map ? Map<String, dynamic>.from(j['totals'] as Map) : <String, dynamic>{};
    return StylistReport(
      from: _date(j['from']) ?? DateTime.now(),
      to: _date(j['to']) ?? DateTime.now(),
      stylists: _rows(j['stylists']).map(StylistRow.fromJson).toList(),
      services: _int(totals['services']),
      revenue: _num(totals['revenue']),
      commission: _num(totals['commission']),
      visits: _int(totals['visits']),
    );
  }

  final DateTime from;
  final DateTime to;
  final List<StylistRow> stylists;
  final int services;
  final double revenue;
  final double commission;
  final int visits;
}

// ------------------------------------------------------------------ "come back" reminders

class RebookSettings {
  const RebookSettings({required this.enabled, required this.weeks, this.maxWeeks = 52, this.graceDays = 14});

  factory RebookSettings.fromJson(final Map<String, dynamic> j) => RebookSettings(
        enabled: _flag(j['rebook_enabled']),
        weeks: _int(j['rebook_weeks']) <= 0 ? 4 : _int(j['rebook_weeks']),
        maxWeeks: _int(j['max_weeks']) <= 0 ? 52 : _int(j['max_weeks']),
        graceDays: _int(j['grace_days']) <= 0 ? 14 : _int(j['grace_days']),
      );

  final bool enabled;
  final int weeks;
  final int maxWeeks;
  final int graceDays;

  RebookSettings copyWith({final bool? enabled, final int? weeks}) =>
      RebookSettings(enabled: enabled ?? this.enabled, weeks: weeks ?? this.weeks, maxWeeks: maxWeeks, graceDays: graceDays);
}

class RebookClient {
  const RebookClient({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.visitOn,
    required this.dueOn,
    required this.weeksWaited,
    required this.ruleWeeks,
    required this.service,
    required this.sent,
    required this.canText,
    this.skipReason,
  });

  factory RebookClient.fromJson(final Map<String, dynamic> j) => RebookClient(
        customerId: _int(j['customer_id']),
        name: _text(j['name']),
        phone: _text(j['phone']),
        visitOn: _date(j['visit_on']) ?? DateTime.now(),
        dueOn: _date(j['due_on']) ?? DateTime.now(),
        weeksWaited: _int(j['weeks_waited']),
        ruleWeeks: _int(j['rule_weeks']),
        service: _text(j['service']),
        sent: _flag(j['sent']),
        canText: _flag(j['can_text']),
        skipReason: j['skip_reason'] == null ? null : _text(j['skip_reason']),
      );

  final int customerId;
  final String name;
  final String phone;
  final DateTime visitOn;
  final DateTime dueOn;
  final int weeksWaited;
  final int ruleWeeks;
  final String service;

  /// The reminder for that visit has gone out.
  final bool sent;

  /// A reminder can be sent: there is a phone number and the client has not asked not to be texted.
  final bool canText;

  /// Why none can be sent: 'no_phone' or 'opted_out'.
  final String? skipReason;
}

class RebookOverview {
  const RebookOverview({required this.settings, required this.clients});

  factory RebookOverview.fromJson(final Map<String, dynamic> j) => RebookOverview(
        settings: RebookSettings.fromJson(j['settings'] is Map ? Map<String, dynamic>.from(j['settings'] as Map) : <String, dynamic>{}),
        clients: _rows(j['clients']).map(RebookClient.fromJson).toList(),
      );

  final RebookSettings settings;
  final List<RebookClient> clients;
}

// ------------------------------------------------------------------ a client's page

class ClientVisitItem {
  const ClientVisitItem({required this.name, required this.isService, required this.staffName, required this.qty, required this.total});

  factory ClientVisitItem.fromJson(final Map<String, dynamic> j) => ClientVisitItem(
        name: _text(j['name']),
        isService: _flag(j['is_service']),
        staffName: j['staff_name'] == null ? null : _text(j['staff_name']),
        qty: _int(j['qty']),
        total: _num(j['total']),
      );

  final String name;
  final bool isService;
  final String? staffName;
  final int qty;
  final double total;
}

class ClientVisit {
  const ClientVisit({required this.saleId, required this.number, required this.date, required this.total, required this.paid, required this.paymentStatus, required this.items});

  factory ClientVisit.fromJson(final Map<String, dynamic> j) => ClientVisit(
        saleId: _int(j['sale_id']),
        number: _text(j['number']),
        date: _date(j['date']) ?? DateTime.now(),
        total: _num(j['total']),
        paid: _num(j['paid']),
        paymentStatus: _text(j['payment_status']),
        items: _rows(j['items']).map(ClientVisitItem.fromJson).toList(),
      );

  final int saleId;
  final String number;
  final DateTime date;
  final double total;
  final double paid;
  final String paymentStatus;
  final List<ClientVisitItem> items;
}

class NextVisit {
  const NextVisit({required this.visitOn, required this.dueOn, required this.ruleWeeks, required this.service});

  factory NextVisit.fromJson(final Map<String, dynamic> j) => NextVisit(
        visitOn: _date(j['visit_on']) ?? DateTime.now(),
        dueOn: _date(j['due_on']) ?? DateTime.now(),
        ruleWeeks: _int(j['rule_weeks']),
        service: _text(j['service']),
      );

  final DateTime visitOn;
  final DateTime dueOn;
  final int ruleWeeks;
  final String service;
}

class ClientHistory {
  const ClientHistory({
    required this.id,
    required this.name,
    required this.phone,
    required this.notes,
    required this.smsOptOut,
    required this.visitCount,
    required this.totalSpent,
    required this.lastVisitOn,
    required this.favouriteService,
    required this.nextVisit,
    required this.visits,
  });

  factory ClientHistory.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> client = j['client'] is Map ? Map<String, dynamic>.from(j['client'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> stats = j['stats'] is Map ? Map<String, dynamic>.from(j['stats'] as Map) : <String, dynamic>{};
    return ClientHistory(
      id: _int(client['id']),
      name: _text(client['name']),
      phone: _text(client['phone']),
      notes: client['notes'] == null ? null : _text(client['notes']),
      smsOptOut: _flag(client['sms_opt_out']),
      visitCount: _int(stats['visits']),
      totalSpent: _num(stats['total_spent']),
      lastVisitOn: _date(stats['last_visit_on']),
      favouriteService: stats['favourite_service'] == null ? null : _text(stats['favourite_service']),
      nextVisit: stats['next_visit'] is Map ? NextVisit.fromJson(Map<String, dynamic>.from(stats['next_visit'] as Map)) : null,
      visits: _rows(j['visits']).map(ClientVisit.fromJson).toList(),
    );
  }

  final int id;
  final String name;
  final String phone;
  final String? notes;
  final bool smsOptOut;

  /// Visits that had a service (buying shampoo is not a visit).
  final int visitCount;
  final double totalSpent;
  final DateTime? lastVisitOn;
  final String? favouriteService;
  final NextVisit? nextVisit;
  final List<ClientVisit> visits;
}
