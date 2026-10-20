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
  const RebookSettings({required this.enabled, required this.weeks, this.maxWeeks = 52, this.graceDays = 14, this.appointmentReminders = false, this.dailySummary = false});

  factory RebookSettings.fromJson(final Map<String, dynamic> j) => RebookSettings(
        enabled: _flag(j['rebook_enabled']),
        weeks: _int(j['rebook_weeks']) <= 0 ? 4 : _int(j['rebook_weeks']),
        maxWeeks: _int(j['max_weeks']) <= 0 ? 52 : _int(j['max_weeks']),
        graceDays: _int(j['grace_days']) <= 0 ? 14 : _int(j['grace_days']),
        appointmentReminders: _flag(j['appointment_reminders']),
        dailySummary: _flag(j['daily_summary']),
      );

  final bool enabled;
  final int weeks;
  final int maxWeeks;
  final int graceDays;

  /// Clients are texted the day before their appointment.
  final bool appointmentReminders;

  /// The owner is texted how the day went each evening.
  final bool dailySummary;

  RebookSettings copyWith({final bool? enabled, final int? weeks, final bool? appointmentReminders, final bool? dailySummary}) => RebookSettings(
        enabled: enabled ?? this.enabled,
        weeks: weeks ?? this.weeks,
        maxWeeks: maxWeeks,
        graceDays: graceDays,
        appointmentReminders: appointmentReminders ?? this.appointmentReminders,
        dailySummary: dailySummary ?? this.dailySummary,
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

// ------------------------------------------------------------------ expenses

class SalonExpense {
  const SalonExpense({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.date,
    required this.status,
    this.supplier,
    this.paymentMethod,
    this.receiptUrl,
    this.createdByName,
  });

  factory SalonExpense.fromJson(final Map<String, dynamic> j) => SalonExpense(
        id: _int(j['id']),
        category: _text(j['category']),
        description: _text(j['description']),
        amount: _num(j['amount']),
        date: _date(j['expense_date']) ?? DateTime.now(),
        status: _text(j['status']).isEmpty ? 'approved' : _text(j['status']),
        supplier: j['supplier'] == null || _text(j['supplier']).isEmpty ? null : _text(j['supplier']),
        paymentMethod: j['payment_method'] == null || _text(j['payment_method']).isEmpty ? null : _text(j['payment_method']),
        receiptUrl: j['receipt_url'] == null || _text(j['receipt_url']).isEmpty ? null : _text(j['receipt_url']),
        createdByName: j['created_by_name'] == null ? null : _text(j['created_by_name']),
      );

  final int id;
  final String category;
  final String description;
  final double amount;
  final DateTime date;

  /// approved, pending (waiting for the owner) or rejected.
  final String status;
  final String? supplier;
  final String? paymentMethod;
  final String? receiptUrl;
  final String? createdByName;

  bool get isPending => status == 'pending';
}

// ------------------------------------------------------------------ profit and loss

class ExpenseGroup {
  const ExpenseGroup({required this.category, required this.total, required this.count});

  factory ExpenseGroup.fromJson(final Map<String, dynamic> j) => ExpenseGroup(category: _text(j['category']), total: _num(j['total']), count: _int(j['count']));

  final String category;
  final double total;
  final int count;
}

class Collection {
  const Collection({required this.method, required this.amount});

  factory Collection.fromJson(final Map<String, dynamic> j) => Collection(method: _text(j['method']), amount: _num(j['amount']));

  /// cash, mpesa, mixx, airtel_money, halopesa or bank_transfer.
  final String method;
  final double amount;
}

class ProfitLoss {
  const ProfitLoss({
    required this.from,
    required this.to,
    required this.serviceRevenue,
    required this.goodsRevenue,
    required this.revenue,
    required this.discounts,
    required this.costOfGoods,
    required this.grossProfit,
    required this.expenses,
    required this.expensesByCategory,
    required this.commissions,
    required this.salaries,
    required this.operatingCosts,
    required this.netProfit,
    required this.collections,
    required this.collected,
    required this.outstanding,
    required this.cancelledCount,
    required this.cancelledTotal,
    required this.sales,
    required this.clients,
  });

  factory ProfitLoss.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> cancelled = j['cancelled'] is Map ? Map<String, dynamic>.from(j['cancelled'] as Map) : <String, dynamic>{};
    return ProfitLoss(
      from: _date(j['from']) ?? DateTime.now(),
      to: _date(j['to']) ?? DateTime.now(),
      serviceRevenue: _num(j['service_revenue']),
      goodsRevenue: _num(j['goods_revenue']),
      revenue: _num(j['revenue']),
      discounts: _num(j['discounts']),
      costOfGoods: _num(j['cost_of_goods']),
      grossProfit: _num(j['gross_profit']),
      expenses: _num(j['expenses']),
      expensesByCategory: _rows(j['expenses_by_category']).map(ExpenseGroup.fromJson).toList(),
      commissions: _num(j['commissions']),
      salaries: _num(j['salaries']),
      operatingCosts: _num(j['operating_costs']),
      netProfit: _num(j['net_profit']),
      collections: _rows(j['collections']).map(Collection.fromJson).toList(),
      collected: _num(j['collected']),
      outstanding: _num(j['outstanding']),
      cancelledCount: _int(cancelled['count']),
      cancelledTotal: _num(cancelled['total']),
      sales: _int(j['sales']),
      clients: _int(j['clients']),
    );
  }

  final DateTime from;
  final DateTime to;

  /// Revenue is what the lines were sold for AFTER the discount.
  final double serviceRevenue;
  final double goodsRevenue;
  final double revenue;
  final double discounts;
  final double costOfGoods;
  final double grossProfit;
  final double expenses;
  final List<ExpenseGroup> expensesByCategory;
  final double commissions;
  final double salaries;
  final double operatingCosts;
  final double netProfit;

  /// Money received in the period, by how it was paid (not the same as revenue).
  final List<Collection> collections;
  final double collected;
  final double outstanding;
  final int cancelledCount;
  final double cancelledTotal;
  final int sales;
  final int clients;
}

// ------------------------------------------------------------------ payroll

class PayrollRow {
  const PayrollRow({
    required this.staffId,
    required this.name,
    required this.salary,
    required this.commissionEarned,
    required this.salaryPaid,
    required this.commissionPaid,
    required this.advances,
    required this.owed,
  });

  factory PayrollRow.fromJson(final Map<String, dynamic> j) => PayrollRow(
        staffId: _text(j['staff_id']),
        name: _text(j['name']),
        salary: _num(j['salary']),
        commissionEarned: _num(j['commission_earned']),
        salaryPaid: _num(j['salary_paid']),
        commissionPaid: _num(j['commission_paid']),
        advances: _num(j['advances']),
        owed: _num(j['owed']),
      );

  final String staffId;
  final String name;
  final double salary;
  final double commissionEarned;
  final double salaryPaid;
  final double commissionPaid;
  final double advances;

  /// What the salon still owes them for the month.
  final double owed;
}

class PayrollReport {
  const PayrollReport({required this.month, required this.staff, required this.salary, required this.commissionEarned, required this.owed});

  factory PayrollReport.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> totals = j['totals'] is Map ? Map<String, dynamic>.from(j['totals'] as Map) : <String, dynamic>{};
    return PayrollReport(
      month: _text(j['month']),
      staff: _rows(j['staff']).map(PayrollRow.fromJson).toList(),
      salary: _num(totals['salary']),
      commissionEarned: _num(totals['commission_earned']),
      owed: _num(totals['owed']),
    );
  }

  /// "2026-10".
  final String month;
  final List<PayrollRow> staff;
  final double salary;
  final double commissionEarned;
  final double owed;
}

class Payout {
  const Payout({required this.id, required this.staffId, required this.kind, required this.amount, required this.paidOn, required this.periodMonth, required this.method, this.staffName, this.note});

  factory Payout.fromJson(final Map<String, dynamic> j) => Payout(
        id: _int(j['id']),
        staffId: _text(j['staff_id']),
        staffName: j['staff_name'] == null ? null : _text(j['staff_name']),
        kind: _text(j['kind']),
        amount: _num(j['amount']),
        paidOn: _date(j['paid_on']) ?? DateTime.now(),
        periodMonth: _text(j['period_month']),
        method: _text(j['method']).isEmpty ? 'cash' : _text(j['method']),
        note: j['note'] == null || _text(j['note']).isEmpty ? null : _text(j['note']),
      );

  final int id;
  final String staffId;
  final String? staffName;

  /// salary, commission or advance.
  final String kind;
  final double amount;
  final DateTime paidOn;
  final String periodMonth;
  final String method;
  final String? note;
}

class StaffProfile {
  const StaffProfile({required this.staffId, required this.name, required this.role, required this.monthlySalary, this.specialization, this.commissionPercent, this.workDays = const <int>[], this.shiftStart, this.shiftEnd});

  factory StaffProfile.fromJson(final Map<String, dynamic> j) => StaffProfile(
        staffId: _text(j['staff_id']),
        name: _text(j['name']),
        role: _text(j['role']),
        specialization: j['specialization'] == null || _text(j['specialization']).isEmpty ? null : _text(j['specialization']),
        monthlySalary: _num(j['monthly_salary']),
        commissionPercent: j['commission_percent'] == null ? null : _num(j['commission_percent']),
        workDays: j['work_days'] is List ? <int>[for (final dynamic d in j['work_days'] as List) _int(d)] : const <int>[],
        shiftStart: j['shift_start'] == null || _text(j['shift_start']).isEmpty ? null : _text(j['shift_start']),
        shiftEnd: j['shift_end'] == null || _text(j['shift_end']).isEmpty ? null : _text(j['shift_end']),
      );

  final String staffId;
  final String name;
  final String role;

  /// The weekdays they work (Monday = 1); empty = not said.
  final List<int> workDays;

  /// Their hours, "08:30" to "17:00"; null = not said.
  final String? shiftStart;
  final String? shiftEnd;
  final String? specialization;
  final double monthlySalary;

  /// Their own rate, used for a service that has none of its own.
  final double? commissionPercent;
}

// ------------------------------------------------------------------ the dashboard

class PeriodFigures {
  const PeriodFigures({required this.revenue, required this.expenses, required this.netProfit, required this.clients, required this.sales});

  factory PeriodFigures.fromJson(final dynamic j) {
    final Map<String, dynamic> m = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    return PeriodFigures(revenue: _num(m['revenue']), expenses: _num(m['expenses']), netProfit: _num(m['net_profit']), clients: _int(m['clients']), sales: _int(m['sales']));
  }

  final double revenue;
  final double expenses;
  final double netProfit;
  final int clients;
  final int sales;
}

class RankedItem {
  const RankedItem({required this.name, required this.revenue, this.times = 0});

  factory RankedItem.fromJson(final Map<String, dynamic> j) => RankedItem(name: _text(j['name']), revenue: _num(j['revenue']), times: _int(j['times']));

  final String name;
  final double revenue;

  /// How many times it was done (services only).
  final int times;
}

class SalonOverview {
  const SalonOverview({
    required this.today,
    required this.week,
    required this.month,
    required this.year,
    required this.collections,
    required this.outstanding,
    required this.topServices,
    required this.topStaff,
    required this.bookingsToday,
    required this.bookingsUpcoming,
  });

  factory SalonOverview.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> periods = j['periods'] is Map ? Map<String, dynamic>.from(j['periods'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> month = j['month'] is Map ? Map<String, dynamic>.from(j['month'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> bookings = j['bookings'] is Map ? Map<String, dynamic>.from(j['bookings'] as Map) : <String, dynamic>{};
    return SalonOverview(
      today: PeriodFigures.fromJson(periods['today']),
      week: PeriodFigures.fromJson(periods['week']),
      month: PeriodFigures.fromJson(periods['month']),
      year: PeriodFigures.fromJson(periods['year']),
      collections: _rows(month['collections']).map(Collection.fromJson).toList(),
      outstanding: _num(month['outstanding']),
      topServices: _rows(j['top_services']).map(RankedItem.fromJson).toList(),
      topStaff: _rows(j['top_staff']).map(RankedItem.fromJson).toList(),
      bookingsToday: _int(bookings['today']),
      bookingsUpcoming: _int(bookings['upcoming']),
    );
  }

  final PeriodFigures today;
  final PeriodFigures week;
  final PeriodFigures month;
  final PeriodFigures year;

  /// Money received this month, by how it was paid.
  final List<Collection> collections;
  final double outstanding;
  final List<RankedItem> topServices;
  final List<RankedItem> topStaff;
  final int bookingsToday;
  final int bookingsUpcoming;
}

// ------------------------------------------------------------------ people at work

class AttendanceRecord {
  const AttendanceRecord({required this.id, required this.staffId, required this.date, required this.clockIn, this.clockOut, this.hours, this.name});

  factory AttendanceRecord.fromJson(final Map<String, dynamic> j) => AttendanceRecord(
        id: _int(j['id']),
        staffId: _text(j['staff_id']),
        name: j['name'] == null ? null : _text(j['name']),
        date: _date(j['date']) ?? DateTime.now(),
        clockIn: _date(j['clock_in']) ?? DateTime.now(),
        clockOut: _date(j['clock_out']),
        hours: j['hours'] == null ? null : _num(j['hours']),
      );

  final int id;
  final String staffId;
  final String? name;
  final DateTime date;
  final DateTime clockIn;
  final DateTime? clockOut;

  /// Null while they are still at work.
  final double? hours;
}

class AttendancePerson {
  const AttendancePerson({required this.staffId, required this.name, required this.days, required this.hours, required this.atWork, required this.records});

  factory AttendancePerson.fromJson(final Map<String, dynamic> j) => AttendancePerson(
        staffId: _text(j['staff_id']),
        name: _text(j['name']),
        days: _int(j['days']),
        hours: _num(j['hours']),
        atWork: _flag(j['at_work']),
        records: _rows(j['records']).map(AttendanceRecord.fromJson).toList(),
      );

  final String staffId;
  final String name;
  final int days;
  final double hours;
  final bool atWork;
  final List<AttendanceRecord> records;
}

class AttendanceNow {
  const AttendanceNow({required this.atWork, this.since});

  factory AttendanceNow.fromJson(final Map<String, dynamic> j) => AttendanceNow(atWork: _flag(j['at_work']), since: _date(j['since']));

  final bool atWork;
  final DateTime? since;
}

class DayOff {
  const DayOff({required this.id, required this.staffId, required this.offOn, this.staffName, this.reason});

  factory DayOff.fromJson(final Map<String, dynamic> j) => DayOff(
        id: _int(j['id']),
        staffId: _text(j['staff_id']),
        staffName: j['staff_name'] == null ? null : _text(j['staff_name']),
        offOn: _date(j['off_on']) ?? DateTime.now(),
        reason: j['reason'] == null || _text(j['reason']).isEmpty ? null : _text(j['reason']),
      );

  final int id;
  final String staffId;
  final String? staffName;
  final DateTime offOn;
  final String? reason;
}

class ShiftCollected {
  const ShiftCollected({required this.cash, required this.mobileMoney, required this.bank});

  factory ShiftCollected.fromJson(final dynamic j) {
    final Map<String, dynamic> m = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    return ShiftCollected(cash: _num(m['cash']), mobileMoney: _num(m['mobile_money']), bank: _num(m['bank_transfer']));
  }

  final double cash;
  final double mobileMoney;
  final double bank;
}

class SalonShift {
  const SalonShift({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.status,
    required this.openedAt,
    required this.openingFloat,
    required this.expectedCash,
    required this.collected,
    this.closedAt,
    this.countedCash,
    this.difference,
    this.handedToName,
    this.note,
  });

  factory SalonShift.fromJson(final Map<String, dynamic> j) => SalonShift(
        id: _int(j['id']),
        staffId: _text(j['staff_id']),
        staffName: _text(j['staff_name']),
        status: _text(j['status']),
        openedAt: _date(j['opened_at']) ?? DateTime.now(),
        closedAt: _date(j['closed_at']),
        openingFloat: _num(j['opening_float']),
        expectedCash: _num(j['expected_cash']),
        collected: ShiftCollected.fromJson(j['collected']),
        countedCash: j['counted_cash'] == null ? null : _num(j['counted_cash']),
        difference: j['difference'] == null ? null : _num(j['difference']),
        handedToName: j['handed_to_name'] == null ? null : _text(j['handed_to_name']),
        note: j['note'] == null || _text(j['note']).isEmpty ? null : _text(j['note']),
      );

  final int id;
  final String staffId;
  final String staffName;

  /// open or closed.
  final String status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingFloat;

  /// What the till should hold: the float plus the cash taken.
  final double expectedCash;
  final ShiftCollected collected;

  /// What the person counted and handed over, and the difference (counted - expected; negative = short).
  final double? countedCash;
  final double? difference;
  final String? handedToName;
  final String? note;

  bool get isOpen => status == 'open';

  bool get hasDifference => (difference ?? 0).abs() >= 0.01;
}

class ShiftsReport {
  const ShiftsReport({required this.month, required this.shifts, required this.count, required this.withDifference, required this.difference});

  factory ShiftsReport.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> totals = j['totals'] is Map ? Map<String, dynamic>.from(j['totals'] as Map) : <String, dynamic>{};
    return ShiftsReport(
      month: _text(j['month']),
      shifts: _rows(j['shifts']).map(SalonShift.fromJson).toList(),
      count: _int(totals['shifts']),
      withDifference: _int(totals['with_difference']),
      difference: _num(totals['difference']),
    );
  }

  final String month;
  final List<SalonShift> shifts;
  final int count;
  final int withDifference;
  final double difference;
}

/// One of the salon's branches.
class SalonBranchInfo {
  const SalonBranchInfo({required this.id, required this.name, this.address = '', this.phone = '', this.active = true});

  factory SalonBranchInfo.fromJson(final Map<String, dynamic> j) => SalonBranchInfo(
        id: _int(j['id']),
        name: _text(j['name']),
        address: _text(j['address']),
        phone: _text(j['phone']),
        active: j['active'] == null ? true : _flag(j['active']),
      );

  final int id;
  final String name;
  final String address;
  final String phone;
  final bool active;
}
