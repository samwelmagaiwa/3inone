import 'dart:typed_data';

import '../../../services/api_service.dart';
import '../models/salon_models.dart';

/// The salon's calls to the server. The screens take one of these so a test can hand them a fake with canned
/// answers; the app uses the real one. A failed call throws the [ApiException] of the server's own words.
class SalonApi {
  SalonApi({final ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  static String _day(final DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _data(final Map<String, dynamic> res) => res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};

  /// How each stylist did between two days (this month when none are given).
  Future<StylistReport> stylists({final DateTime? from, final DateTime? to}) async {
    final List<String> q = <String>[if (from != null) 'from=${_day(from)}', if (to != null) 'to=${_day(to)}'];
    final Map<String, dynamic> res = await _api.get('/inventory/salon/stylists${q.isEmpty ? '' : '?${q.join('&')}'}');
    return StylistReport.fromJson(_data(res));
  }

  /// Every service behind one stylist's total for the period; [staffId] null = "nobody named".
  Future<StylistPage> stylistPage(final String? staffId, {final DateTime? from, final DateTime? to}) async {
    final List<String> q = <String>[if (from != null) 'from=${_day(from)}', if (to != null) 'to=${_day(to)}'];
    final Map<String, dynamic> res = await _api.get('/inventory/salon/stylists/${staffId ?? 'none'}/transactions${q.isEmpty ? '' : '?${q.join('&')}'}');
    return StylistPage.fromJson(_data(res));
  }

  // ---------------------------------------------------------------- expenses

  Future<List<SalonExpense>> expenses(final DateTime from, final DateTime to) async {
    final Map<String, dynamic> res = await _api.get('/inventory/expenses?from=${_day(from)}&to=${_day(to)}');
    final dynamic rows = res['data'];
    return <SalonExpense>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) SalonExpense.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// Record an expense ([id] null) or change one. What a stylist records waits for the owner's approval.
  Future<SalonExpense> saveExpense({
    final int? id,
    required final String category,
    required final String description,
    required final double amount,
    required final DateTime date,
    final String? supplier,
    final String? paymentMethod,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'category': category,
      'description': description,
      'amount': amount,
      'expense_date': _day(date),
      'supplier': supplier ?? '',
      if (paymentMethod != null) 'payment_method': paymentMethod,
    };
    final Map<String, dynamic> res = id == null ? await _api.post('/inventory/expenses', body) : await _api.put('/inventory/expenses/$id', body);
    return SalonExpense.fromJson(_data(res));
  }

  Future<SalonExpense> decideExpense(final int id, {required final bool approve}) async => SalonExpense.fromJson(
      _data(await _api.post('/inventory/expenses/$id/approval', <String, dynamic>{'decision': approve ? 'approve' : 'reject'})));

  /// A photo of the receipt.
  Future<SalonExpense> attachReceipt(final int id, final Uint8List bytes, final String filename) async =>
      SalonExpense.fromJson(_data(await _api.uploadFile('/inventory/expenses/$id/receipt', 'photo', bytes, filename)));

  // ---------------------------------------------------------------- the dashboard

  Future<SalonOverview> overview() async => SalonOverview.fromJson(_data(await _api.get('/inventory/salon/overview')));

  // ---------------------------------------------------------------- profit and loss

  Future<ProfitLoss> profitLoss(final DateTime from, final DateTime to) async =>
      ProfitLoss.fromJson(_data(await _api.get('/inventory/salon/profit-loss?from=${_day(from)}&to=${_day(to)}')));

  // ---------------------------------------------------------------- payroll

  Future<PayrollReport> payroll(final String month) async => PayrollReport.fromJson(_data(await _api.get('/inventory/salon/payroll?month=$month')));

  Future<List<Payout>> payouts(final String month) async {
    final Map<String, dynamic> res = await _api.get('/inventory/salon/payouts?month=$month');
    final dynamic rows = res['data'];
    return <Payout>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) Payout.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// Record a salary, commission or advance paid to someone. [kind]: salary, commission or advance.
  Future<void> savePayout({
    required final String staffId,
    required final String kind,
    required final double amount,
    required final DateTime paidOn,
    required final String method,
    final String? periodMonth,
    final String? note,
  }) async {
    await _api.post('/inventory/salon/payouts', <String, dynamic>{
      'staff_id': staffId,
      'kind': kind,
      'amount': amount,
      'paid_on': _day(paidOn),
      if (periodMonth != null) 'period_month': periodMonth,
      'method': method,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<void> deletePayout(final int id) async {
    await _api.delete('/inventory/salon/payouts/$id');
  }

  Future<List<StaffProfile>> staffProfiles() async {
    final Map<String, dynamic> res = await _api.get('/inventory/salon/staff-profiles');
    final dynamic rows = res['data'];
    return <StaffProfile>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) StaffProfile.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  Future<void> saveStaffProfile(
    final String staffId, {
    final String? specialization,
    final double? monthlySalary,
    final double? commissionPercent,
    final bool clearCommission = false,
    final List<int>? workDays,
    final String? shiftStart,
    final String? shiftEnd,
    final bool clearHours = false,
  }) async {
    await _api.put('/inventory/salon/staff-profiles/$staffId', <String, dynamic>{
      if (specialization != null) 'specialization': specialization,
      if (monthlySalary != null) 'monthly_salary': monthlySalary,
      if (commissionPercent != null || clearCommission) 'commission_percent': commissionPercent,
      if (workDays != null) 'work_days': workDays,
      if (shiftStart != null || clearHours) 'shift_start': shiftStart,
      if (shiftEnd != null || clearHours) 'shift_end': shiftEnd,
    });
  }

  // ---------------------------------------------------------------- people at work

  Future<AttendanceNow> attendanceToday() async => AttendanceNow.fromJson(_data(await _api.get('/inventory/salon/attendance/today')));

  /// Start work ([staffId] null = me; the owner and managers may clock someone else in).
  Future<void> clockIn({final String? staffId}) async {
    await _api.post('/inventory/salon/attendance/clock-in', <String, dynamic>{if (staffId != null) 'staff_id': staffId});
  }

  Future<void> clockOut({final String? staffId}) async {
    await _api.post('/inventory/salon/attendance/clock-out', <String, dynamic>{if (staffId != null) 'staff_id': staffId});
  }

  Future<List<AttendancePerson>> attendance(final String month) async {
    final Map<String, dynamic> res = await _api.get('/inventory/salon/attendance?month=$month');
    final Map<String, dynamic> data = _data(res);
    final dynamic rows = data['staff'];
    return <AttendancePerson>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) AttendancePerson.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  Future<List<DayOff>> daysOff(final String month) async {
    final Map<String, dynamic> res = await _api.get('/inventory/salon/days-off?month=$month');
    final dynamic rows = res['data'];
    return <DayOff>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) DayOff.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  Future<void> addDayOff(final String staffId, final DateTime day, {final String? reason}) async {
    await _api.post('/inventory/salon/days-off', <String, dynamic>{'staff_id': staffId, 'off_on': _day(day), if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});
  }

  Future<void> deleteDayOff(final int id) async {
    await _api.delete('/inventory/salon/days-off/$id');
  }

  /// My open shift, with what I have taken so far; null when none is open.
  Future<SalonShift?> currentShift() async {
    final Map<String, dynamic> res = await _api.get('/inventory/salon/shifts/current');
    return res['data'] is Map ? SalonShift.fromJson(Map<String, dynamic>.from(res['data'] as Map)) : null;
  }

  Future<SalonShift> openShift(final double openingFloat) async =>
      SalonShift.fromJson(_data(await _api.post('/inventory/salon/shifts/open', <String, dynamic>{'opening_float': openingFloat})));

  /// Count the cash and hand it over; the answer says what the till should have held and the difference.
  Future<SalonShift> closeShift(final int id, {required final double countedCash, final String? handedToId, final String? note}) async =>
      SalonShift.fromJson(_data(await _api.post('/inventory/salon/shifts/$id/close', <String, dynamic>{
        'counted_cash': countedCash,
        if (handedToId != null) 'handed_to_id': handedToId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      })));

  Future<ShiftsReport> shifts(final String month) async => ShiftsReport.fromJson(_data(await _api.get('/inventory/salon/shifts?month=$month')));

  /// The "come back" settings and who is due now.
  Future<RebookOverview> rebookOverview() async => RebookOverview.fromJson(_data(await _api.get('/inventory/salon/rebook/due')));

  Future<RebookSettings> saveRebookSettings({final bool? enabled, final int? weeks}) async {
    final Map<String, dynamic> res = await _api.put('/inventory/salon/settings', <String, dynamic>{
      if (enabled != null) 'rebook_enabled': enabled,
      if (weeks != null) 'rebook_weeks': weeks,
    });
    return RebookSettings.fromJson(_data(res));
  }

  /// The settings as they are now ("come back" reminders and appointment reminders).
  Future<RebookSettings> salonSettings() async => RebookSettings.fromJson(_data(await _api.get('/inventory/salon/settings')));

  Future<RebookSettings> saveDailySummary(final bool on) async =>
      RebookSettings.fromJson(_data(await _api.put('/inventory/salon/settings', <String, dynamic>{'daily_summary': on})));

  Future<RebookSettings> saveAppointmentReminders(final bool on) async =>
      RebookSettings.fromJson(_data(await _api.put('/inventory/salon/settings', <String, dynamic>{'appointment_reminders': on})));

  static String _stamp(final DateTime d) => '${_day(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// The appointments of one day, earliest first.
  Future<List<SalonAppointment>> appointments(final DateTime day) async {
    final Map<String, dynamic> res = await _api.get('/inventory/salon/appointments?date=${_day(day)}');
    final dynamic rows = res['data'];
    return <SalonAppointment>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) SalonAppointment.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// Book a new appointment ([id] null) or change one. The server refuses a stylist already booked then, unless
  /// [force] says to book anyway.
  Future<SalonAppointment> saveAppointment({
    final int? id,
    final int? customerId,
    required final String clientName,
    final String? clientPhone,
    final String? staffId,
    required final DateTime startsAt,
    required final List<AppointmentService> services,
    final String? notes,
    final bool force = false,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (customerId != null) 'customer_id': customerId,
      'client_name': clientName,
      'client_phone': clientPhone ?? '',
      'staff_id': staffId,
      'starts_at': _stamp(startsAt),
      'services': <Map<String, dynamic>>[
        for (final AppointmentService s in services)
          <String, dynamic>{'product_id': s.productId, 'price': s.price, if (s.label != null) 'label': s.label},
      ],
      'notes': notes ?? '',
      if (force) 'force': true,
    };
    final Map<String, dynamic> res = id == null ? await _api.post('/inventory/salon/appointments', body) : await _api.put('/inventory/salon/appointments/$id', body);
    return SalonAppointment.fromJson(_data(res));
  }

  /// confirmed, in_progress, done, cancelled or no_show.
  Future<SalonAppointment> setAppointmentStatus(final int id, final String status) async =>
      SalonAppointment.fromJson(_data(await _api.post('/inventory/salon/appointments/$id/status', <String, dynamic>{'status': status})));

  Future<ClientHistory> clientHistory(final int customerId) async =>
      ClientHistory.fromJson(_data(await _api.get('/inventory/salon/clients/$customerId/history')));

  /// Notes about a client and whether they may be texted. Only what is given is changed.
  Future<void> saveClient(final int customerId, {final String? notes, final bool? smsOptOut}) async {
    await _api.put('/inventory/salon/clients/$customerId', <String, dynamic>{
      if (notes != null) 'notes': notes,
      if (smsOptOut != null) 'sms_opt_out': smsOptOut,
    });
  }

  // ---------------------------------------------------------------- branches

  Future<List<SalonBranchInfo>> branches() async {
    final Map<String, dynamic> res = await _api.get('/inventory/salon/branches');
    final dynamic rows = res['data'];
    return <SalonBranchInfo>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) SalonBranchInfo.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  Future<void> saveBranch({final int? id, required final String name, final String? address, final String? phone, final bool? active}) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
      if (active != null) 'active': active,
    };
    if (id == null) {
      await _api.post('/inventory/salon/branches', body);
    } else {
      await _api.put('/inventory/salon/branches/$id', body);
    }
  }

  Future<void> deleteBranch(final int id) async {
    await _api.delete("/inventory/salon/branches/$id");
  }
}

