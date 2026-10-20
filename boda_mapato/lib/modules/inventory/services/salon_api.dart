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
    final double? depositAmount,
    final String? depositMethod,
    final bool force = false,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (depositAmount != null) 'deposit_amount': depositAmount,
      if (depositAmount != null && depositAmount > 0 && depositMethod != null) 'deposit_method': depositMethod,
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
  Future<void> saveClient(final int customerId, {final String? notes, final bool? smsOptOut, final String? birthday, final Map<String, String>? preferences}) async {
    await _api.put('/inventory/salon/clients/$customerId', <String, dynamic>{
      if (notes != null) 'notes': notes,
      if (smsOptOut != null) 'sms_opt_out': smsOptOut,
      if (birthday != null) 'birthday': birthday.isEmpty ? null : birthday,
      if (preferences != null) 'preferences': preferences,
    });
  }

  Future<List<Map<String, dynamic>>> clientPackages(final int customerId) => _list('/inventory/salon/clients/$customerId/packages');

  Future<List<Map<String, dynamic>>> clientPhotos(final int customerId) => _list('/inventory/salon/clients/$customerId/photos');

  /// Keep a photo of a style; the client has agreed (the server insists on it).
  Future<void> uploadClientPhoto(final int customerId, final Uint8List bytes, final String filename, {final String? caption}) async {
    await _api.uploadFile('/inventory/salon/clients/$customerId/photos', 'photo', bytes, filename,
        fields: <String, String>{'consent': '1', if (caption != null && caption.isNotEmpty) 'caption': caption});
  }

  Future<void> deleteClientPhoto(final int photoId) async {
    await _api.delete('/inventory/salon/photos/$photoId');
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

  // ---------------------------------------------------------------- equipment

  /// {equipment: [...], totals: {...}} as the server sends it.
  Future<Map<String, dynamic>> equipment() async => _data(await _api.get('/inventory/salon/equipment'));

  Future<void> saveEquipment(final Map<String, dynamic> body, {final int? id}) async {
    if (id == null) {
      await _api.post('/inventory/salon/equipment', body);
    } else {
      await _api.put('/inventory/salon/equipment/$id', body);
    }
  }

  Future<void> deleteEquipment(final int id) async {
    await _api.delete('/inventory/salon/equipment/$id');
  }

  Future<List<Map<String, dynamic>>> equipmentLogs(final int id) async {
    final dynamic rows = (await _api.get('/inventory/salon/equipment/$id/logs'))['data'];
    return <Map<String, dynamic>>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  Future<void> addEquipmentLog(final int id, final Map<String, dynamic> body) async {
    await _api.post('/inventory/salon/equipment/$id/logs', body);
  }

  // ---------------------------------------------------------------- feedback

  /// {summary: {...}, feedback: [...]}; [status] 'new' / 'resolved' narrows it.
  Future<Map<String, dynamic>> feedback({final String? status}) async =>
      _data(await _api.get('/inventory/salon/feedback${status == null ? '' : '?status=$status'}'));

  Future<void> resolveFeedback(final int id, {final String? note}) async {
    await _api.post('/inventory/salon/feedback/$id/resolve', <String, dynamic>{if (note != null && note.isNotEmpty) 'note': note});
  }

  // ---------------------------------------------------------------- settings, loyalty, offers, exports

  Future<Map<String, dynamic>> salonSettingsMap() async => _data(await _api.get('/inventory/salon/settings'));

  Future<Map<String, dynamic>> saveSalonSettingsMap(final Map<String, dynamic> body) async => _data(await _api.put('/inventory/salon/settings', body));

  Future<Map<String, dynamic>> loyaltySettings() async => _data(await _api.get('/inventory/salon/loyalty/settings'));

  Future<Map<String, dynamic>> saveLoyaltySettings(final Map<String, dynamic> body) async => _data(await _api.put('/inventory/salon/loyalty/settings', body));

  Future<List<Map<String, dynamic>>> vouchers() => _list('/inventory/salon/vouchers');

  Future<void> saveVoucher(final Map<String, dynamic> body, {final int? id}) async {
    if (id == null) {
      await _api.post('/inventory/salon/vouchers', body);
    } else {
      await _api.put('/inventory/salon/vouchers/$id', body);
    }
  }

  Future<void> deleteVoucher(final int id) async {
    await _api.delete('/inventory/salon/vouchers/$id');
  }

  /// {segments: [{segment, members, reachable}], campaigns: [...], max_per_message}.
  Future<Map<String, dynamic>> campaigns() async => _data(await _api.get('/inventory/salon/campaigns'));

  Future<void> sendCampaign({required final String segment, required final String message, final String? name}) async {
    await _api.post('/inventory/salon/campaigns', <String, dynamic>{'segment': segment, 'message': message, if (name != null && name.isNotEmpty) 'name': name});
  }

  /// A report as a file: [type] sales / expenses / payroll / stylists / profit-loss / tax, [format] csv / pdf.
  Future<Uint8List> exportReport(final String type, {required final String format, required final bool sw, required final DateTime from, required final DateTime to}) =>
      _api.getFileBytes('/inventory/salon/export/$type?format=$format&lang=${sw ? 'sw' : 'en'}&from=${_day(from)}&to=${_day(to)}&month=${_day(to).substring(0, 7)}');

  Future<List<Map<String, dynamic>>> _list(final String path) async {
    final dynamic rows = (await _api.get(path))['data'];
    return <Map<String, dynamic>>[
      if (rows is List)
        for (final dynamic r in rows)
          if (r is Map) Map<String, dynamic>.from(r),
    ];
  }

  /// What a voucher would take off a sale of [subtotal]; throws the server's words when it cannot be used.
  Future<double> voucherDiscount(final String code, final double subtotal) async {
    final Map<String, dynamic> d = _data(await _api.get('/inventory/salon/vouchers/check?code=${Uri.encodeQueryComponent(code)}&subtotal=${subtotal.toStringAsFixed(2)}'));
    final dynamic v = d['discount'];

    return v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  }

  /// {on, balance, worth, per, value, ledger} for one client's points.
  Future<Map<String, dynamic>> clientLoyalty(final int customerId) async => _data(await _api.get('/inventory/salon/clients/$customerId/loyalty'));

  /// Give or take points by hand (owner and managers), with a reason.
  Future<void> adjustLoyalty(final int customerId, {required final int points, required final String note}) async {
    await _api.post('/inventory/salon/clients/$customerId/loyalty/adjust', <String, dynamic>{'points': points, 'note': note});
  }

  // ---------------------------------------------------------------- the owner's books, queue, setup

  /// {places: {cash|mobile|bank: {opening, in, out, closing, days}}, total, moves}.
  Future<Map<String, dynamic>> cashbook(final DateTime from, final DateTime to) async => _data(await _api.get('/inventory/salon/cashbook?from=${_day(from)}&to=${_day(to)}'));

  /// [kind] opening / owner_deposit / owner_withdrawal; [method] cash / mobile / bank.
  Future<void> addCashMove({required final String kind, required final String method, required final double amount, final String? note}) async {
    await _api.post('/inventory/salon/cashbook/moves', <String, dynamic>{'kind': kind, 'method': method, 'amount': amount, if (note != null && note.isNotEmpty) 'note': note});
  }

  Future<void> deleteCashMove(final int id) async {
    await _api.delete('/inventory/salon/cashbook/moves/$id');
  }

  /// Count what is really held; answers {expected, difference}.
  Future<Map<String, dynamic>> countCash({required final String method, required final double counted, final String? note}) async =>
      _data(await _api.post('/inventory/salon/cashbook/counts', <String, dynamic>{'method': method, 'counted': counted, if (note != null && note.isNotEmpty) 'note': note}));

  Future<Map<String, dynamic>> analytics({final int months = 6}) async => _data(await _api.get('/inventory/salon/analytics?months=$months'));

  /// {queue: [...], waiting, serving, done, left}.
  Future<Map<String, dynamic>> queue() async => _data(await _api.get('/inventory/salon/queue'));

  Future<void> addToQueue({required final String name, final String? phone, final int? productId, final String? staffId, final String? note}) async {
    await _api.post('/inventory/salon/queue', <String, dynamic>{
      'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (productId != null) 'product_id': productId,
      if (staffId != null) 'staff_id': staffId,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  Future<void> setQueueStatus(final int id, final String status) async {
    await _api.post('/inventory/salon/queue/$id/status', <String, dynamic>{'status': status});
  }

  Future<List<Map<String, dynamic>>> serviceMaterials(final int serviceId) => _list('/inventory/salon/services/$serviceId/materials');

  Future<void> saveServiceMaterials(final int serviceId, final List<Map<String, dynamic>> items) async {
    await _api.put('/inventory/salon/services/$serviceId/materials', <String, dynamic>{'items': items});
  }

  /// Add the standard salon categories that are not there yet; answers {added: [...], already}.
  Future<Map<String, dynamic>> addCategoryPresets() async => _data(await _api.post('/inventory/salon/category-presets', <String, dynamic>{}));

  // ---------------------------------------------------------------- goods by branch

  /// {branches: [...], products: [{id, name, total, unallocated, over_allocated, branches: [...]}]}.
  Future<Map<String, dynamic>> branchStock() async => _data(await _api.get('/inventory/salon/branch-stock'));

  /// Move goods; a null place is the main store.
  Future<void> transferBranchStock({required final int productId, final int? fromBranchId, final int? toBranchId, required final int quantity}) async {
    await _api.post('/inventory/salon/branch-stock/transfer', <String, dynamic>{
      'product_id': productId,
      'from_branch_id': fromBranchId,
      'to_branch_id': toBranchId,
      'quantity': quantity,
    });
  }

  /// Say when a branch is told a product is running low ([minQuantity] null = no alert).
  Future<void> setBranchLevel({required final int productId, required final int branchId, final int? minQuantity}) async {
    await _api.put('/inventory/salon/branch-stock/level', <String, dynamic>{'product_id': productId, 'branch_id': branchId, 'min_quantity': minQuantity});
  }

  /// Goods moved between the main store and branches, newest first.
  Future<List<Map<String, dynamic>>> branchTransfers({final int? productId, final int? branchId}) =>
      _list('/inventory/salon/branch-stock/transfers?limit=100${productId == null ? '' : '&product_id=$productId'}${branchId == null ? '' : '&branch_id=$branchId'}');
}
