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
  const StylistRow({required this.staffId, required this.name, required this.services, required this.revenue, required this.visits, required this.clients, this.commission = 0, this.discount = 0});

  factory StylistRow.fromJson(final Map<String, dynamic> j) => StylistRow(
        staffId: j['staff_id'] == null ? null : _text(j['staff_id']),
        name: _text(j['name']),
        services: _int(j['services']),
        revenue: _num(j['revenue']),
        commission: _num(j['commission']),
        discount: _num(j['discount']),
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

  /// The share of the sales' discounts that came off this stylist's services (their revenue is already net of it).
  final double discount;
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
  const RebookSettings({required this.enabled, required this.weeks, this.maxWeeks = 52, this.graceDays = 14, this.appointmentReminders = false});

  factory RebookSettings.fromJson(final Map<String, dynamic> j) => RebookSettings(
        enabled: _flag(j['rebook_enabled']),
        weeks: _int(j['rebook_weeks']) <= 0 ? 4 : _int(j['rebook_weeks']),
        maxWeeks: _int(j['max_weeks']) <= 0 ? 52 : _int(j['max_weeks']),
        graceDays: _int(j['grace_days']) <= 0 ? 14 : _int(j['grace_days']),
        appointmentReminders: _flag(j['appointment_reminders']),
      );

  final bool enabled;
  final int weeks;
  final int maxWeeks;
  final int graceDays;

  /// Clients are texted the day before their appointment.
  final bool appointmentReminders;

  RebookSettings copyWith({final bool? enabled, final int? weeks, final bool? appointmentReminders}) => RebookSettings(
        enabled: enabled ?? this.enabled,
        weeks: weeks ?? this.weeks,
        maxWeeks: maxWeeks,
        graceDays: graceDays,
        appointmentReminders: appointmentReminders ?? this.appointmentReminders,
      );
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

// ------------------------------------------------------------------ appointments

class AppointmentService {
  const AppointmentService({required this.productId, required this.name, required this.price, this.minutes, this.label});

  factory AppointmentService.fromJson(final Map<String, dynamic> j) => AppointmentService(
        productId: _int(j['product_id']),
        name: _text(j['name']),
        price: _num(j['price']),
        minutes: j['minutes'] == null ? null : _int(j['minutes']),
        label: j['label'] == null || _text(j['label']).isEmpty ? null : _text(j['label']),
      );

  final int productId;
  final String name;
  final double price;
  final int? minutes;

  /// The price option it was booked with ("Long"), if any.
  final String? label;

  /// "Braids (Long)".
  String get shown => label == null ? name : '$name ($label)';
}

class SalonAppointment {
  const SalonAppointment({
    required this.id,
    required this.clientName,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.services,
    required this.total,
    this.customerId,
    this.clientPhone,
    this.staffId,
    this.staffName,
    this.notes,
  });

  factory SalonAppointment.fromJson(final Map<String, dynamic> j) => SalonAppointment(
        id: _int(j['id']),
        customerId: j['customer_id'] == null ? null : _int(j['customer_id']),
        clientName: _text(j['client_name']),
        clientPhone: j['client_phone'] == null || _text(j['client_phone']).isEmpty ? null : _text(j['client_phone']),
        staffId: j['staff_id'] == null ? null : _text(j['staff_id']),
        staffName: j['staff_name'] == null ? null : _text(j['staff_name']),
        startsAt: _date(j['starts_at']) ?? DateTime.now(),
        endsAt: _date(j['ends_at']) ?? DateTime.now(),
        status: _text(j['status']).isEmpty ? 'booked' : _text(j['status']),
        services: _rows(j['services']).map(AppointmentService.fromJson).toList(),
        notes: j['notes'] == null || _text(j['notes']).isEmpty ? null : _text(j['notes']),
        total: _num(j['total']),
      );

  /// The states in which an appointment still takes up its stylist's time.
  static const List<String> activeStates = <String>['booked', 'confirmed', 'in_progress'];

  final int id;
  final int? customerId;
  final String clientName;
  final String? clientPhone;
  final String? staffId;
  final String? staffName;
  final DateTime startsAt;
  final DateTime endsAt;

  /// booked, confirmed, in_progress, done, cancelled or no_show.
  final String status;
  final List<AppointmentService> services;
  final String? notes;
  final double total;

  bool get isActive => activeStates.contains(status);

  int get minutes => endsAt.difference(startsAt).inMinutes;

  String get servicesText => services.map((AppointmentService s) => s.shown).join(', ');
}

// ------------------------------------------------------------------ the services behind a stylist's total

class StylistLine {
  const StylistLine({
    required this.saleId,
    required this.number,
    required this.date,
    required this.service,
    required this.qty,
    required this.value,
    required this.discount,
    required this.net,
    required this.commission,
    required this.paymentStatus,
    required this.methods,
    this.client,
    this.discountReason,
  });

  factory StylistLine.fromJson(final Map<String, dynamic> j) => StylistLine(
        saleId: _int(j['sale_id']),
        number: _text(j['number']),
        date: _date(j['date']) ?? DateTime.now(),
        client: j['client'] == null || _text(j['client']).isEmpty ? null : _text(j['client']),
        service: _text(j['service']),
        qty: _int(j['qty']),
        value: _num(j['value']),
        discount: _num(j['discount']),
        net: _num(j['net']),
        commission: _num(j['commission']),
        discountReason: j['discount_reason'] == null || _text(j['discount_reason']).isEmpty ? null : _text(j['discount_reason']),
        paymentStatus: _text(j['payment_status']),
        methods: j['methods'] is List ? <String>[for (final dynamic m in j['methods'] as List) _text(m)] : <String>[],
      );

  final int saleId;
  final String number;
  final DateTime date;
  final String? client;
  final String service;
  final int qty;

  /// What the service was worth, the share of the sale's discount it carried, and what is left.
  final double value;
  final double discount;
  final double net;

  /// What the stylist earns on it.
  final double commission;
  final String? discountReason;

  /// paid, partial or debt (the whole sale's).
  final String paymentStatus;

  /// How the sale was paid: cash, mpesa, mixx, airtel_money, halopesa, bank_transfer.
  final List<String> methods;
}

class StylistPage {
  const StylistPage({required this.from, required this.to, required this.lines, required this.services, required this.value, required this.discount, required this.net, required this.commission, this.name});

  factory StylistPage.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> totals = j['totals'] is Map ? Map<String, dynamic>.from(j['totals'] as Map) : <String, dynamic>{};
    return StylistPage(
      from: _date(j['from']) ?? DateTime.now(),
      to: _date(j['to']) ?? DateTime.now(),
      name: j['name'] == null ? null : _text(j['name']),
      lines: _rows(j['transactions']).map(StylistLine.fromJson).toList(),
      services: _int(totals['services']),
      value: _num(totals['value']),
      discount: _num(totals['discount']),
      net: _num(totals['net']),
      commission: _num(totals['commission']),
    );
  }

  final DateTime from;
  final DateTime to;
  final String? name;
  final List<StylistLine> lines;
  final int services;
  final double value;
  final double discount;
  final double net;
  final double commission;
}
