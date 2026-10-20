import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/inv_product.dart';
import '../../models/inv_sale.dart';
import '../../models/salon_models.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'appointment_form_screen.dart';
import 'salon_text.dart';

/// The salon's diary for one day: who is booked with which stylist, when, for what. The owner books, confirms,
/// moves, finishes (and sells) or cancels from here; the text that reminds each client the day before goes out from
/// the server when the owner switches it on.
class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What "today" is (a test fixes it); the real clock otherwise.
  final DateTime? today;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  late DateTime _day = _dayOnly(widget.today ?? DateTime.now());

  List<SalonAppointment> _items = <SalonAppointment>[];
  RebookSettings? _settings;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  static DateTime _dayOnly(final DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _today => _dayOnly(widget.today ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadSettings();
    });
  }

  Future<void> _load() async {
    final DateTime asked = _day;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<SalonAppointment> rows = await _api.appointments(asked);
      // An answer for a day nobody is looking at any more is thrown away.
      if (!mounted || asked != _day) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted || asked != _day) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      final RebookSettings s = await _api.salonSettings();
      if (mounted) setState(() => _settings = s);
    } on Exception {
      // the diary works without it: the switch just stays hidden
    }
  }

  void _goTo(final DateTime day) {
    setState(() => _day = _dayOnly(day));
    _load();
  }

  Future<void> _pickDay() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_today.year - 1),
      lastDate: DateTime(_today.year + 2),
    );
    if (picked != null) _goTo(picked);
  }

  Future<void> _switchReminders(final bool on) async {
    final RebookSettings? before = _settings;
    if (before == null) return;
    setState(() => _settings = before.copyWith(appointmentReminders: on));
    try {
      final RebookSettings saved = await _api.saveAppointmentReminders(on);
      if (mounted) setState(() => _settings = saved);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _settings = before);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _openForm({final SalonAppointment? appointment}) async {
    final bool? saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => AppointmentFormScreen(api: _api, appointment: appointment, day: _day)),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _setStatus(final SalonAppointment a, final String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.setAppointmentStatus(a.id, status);
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  /// The client has been served: put what was done in the sale (with who did it) so only the payment is left, and
  /// mark the appointment done.
  Future<void> _sell(final SalonAppointment a) async {
    final InventoryProvider inv = context.read<InventoryProvider>();
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (inv.products.isEmpty) await inv.fetchProducts();
    inv.clearCart();
    int added = 0;
    for (final AppointmentService s in a.services) {
      final InvProduct? p = inv.products.where((InvProduct x) => x.id == s.productId).firstOrNull;
      if (p == null) continue;
      inv.addProductToCart(p, option: s.label == null ? null : PriceOption(label: s.label!, price: s.price));
      final InvSaleItem line = inv.cart.lastWhere((InvSaleItem i) => i.productId == p.id && i.optionLabel == s.label);
      if (s.label == null && line.unitPrice != s.price) inv.setCartUnitPrice(line, s.price);
      if (a.staffId != null) inv.setCartStaff(line, a.staffId, a.staffName);
      added++;
    }
    if (a.customerId != null) inv.setCustomer(a.customerId);
    if (!mounted) return;
    await _setStatus(a, 'done');
    if (!mounted) return;
    ThemeConstants.showSuccessSnackBar(
      context,
      added == 0
          ? (sw ? 'Huduma hazipo tena kwenye orodha: ziongeze kwenye Mauzo.' : 'Those services are no longer on the list: add them in Sales.')
          : (sw ? 'Zimewekwa kwenye Mauzo. Fungua Mauzo ulipishe.' : 'Added to Sales. Open Sales to take the payment.'),
    );
  }

  void _actions(final SalonAppointment a, final bool sw) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) {
        Widget tile(final IconData icon, final String label, final VoidCallback run, {final Color? color, final String? key}) => ListTile(
              key: key == null ? null : ValueKey<String>(key),
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: color ?? Colors.white70, size: 22.sp),
              title: Text(label, style: ThemeConstants.bodyStyle.copyWith(color: color)),
              onTap: () {
                Navigator.pop(sheet);
                run();
              },
            );

        return InvSheetShell(
          title: '${a.clientName} • ${_hm(a.startsAt)}',
          children: <Widget>[
            Material(
              type: MaterialType.transparency,
              child: Column(
                children: <Widget>[
                  if (a.status == 'booked') tile(Icons.event_available_outlined, sw ? 'Thibitisha' : 'Confirm', () => _setStatus(a, 'confirmed'), key: 'appt_confirm'),
                  if (a.status == 'booked' || a.status == 'confirmed') tile(Icons.play_circle_outline, sw ? 'Ameanza' : 'Start', () => _setStatus(a, 'in_progress'), key: 'appt_start'),
                  if (a.isActive) tile(Icons.point_of_sale_outlined, sw ? 'Imekamilika: weka kwenye mauzo' : 'Done: put it in Sales', () => _sell(a), color: ThemeConstants.successGreen, key: 'appt_sell'),
                  if (a.isActive) tile(Icons.edit_calendar_outlined, sw ? 'Badilisha au hamisha' : 'Change or move', () => _openForm(appointment: a), key: 'appt_edit'),
                  if (a.status == 'booked' || a.status == 'confirmed') tile(Icons.person_off_outlined, sw ? 'Hakuja' : 'No-show', () => _setStatus(a, 'no_show'), color: ThemeConstants.warningAmber, key: 'appt_noshow'),
                  if (a.isActive) tile(Icons.cancel_outlined, sw ? 'Ghairi' : 'Cancel', () => _setStatus(a, 'cancelled'), color: ThemeConstants.errorRed, key: 'appt_cancel'),
                  if (!a.isActive)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: Text(sw ? 'Miadi hii imeisha: haibadilishwi tena.' : 'This appointment is finished: it can no longer be changed.', style: ThemeConstants.captionStyle),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Material(
      color: ThemeConstants.primaryBlue,
      child: RefreshIndicator(
        onRefresh: _load,
        backgroundColor: Colors.white,
        color: ThemeConstants.primaryBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
          children: _body(sw),
        ),
      ),
    );
  }

  List<Widget> _body(final bool sw) {
    final bool isToday = _day == _today;
    final RebookSettings? s = _settings;

    return <Widget>[
      Row(
        children: <Widget>[
          IconButton(key: const ValueKey<String>('appt_prev'), onPressed: () => _goTo(_day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left, color: Colors.white)),
          Expanded(
            child: InkWell(
              key: const ValueKey<String>('appt_day'),
              onTap: _pickDay,
              borderRadius: BorderRadius.circular(12.r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6.h),
                child: Column(
                  children: <Widget>[
                    Text(dayLabel(_day), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)),
                    Text(isToday ? (sw ? 'Leo' : 'Today') : _weekday(_day, sw), style: ThemeConstants.captionStyle),
                  ],
                ),
              ),
            ),
          ),
          IconButton(key: const ValueKey<String>('appt_next'), onPressed: () => _goTo(_day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right, color: Colors.white)),
        ],
      ),
      if (!isToday)
        Center(
          child: TextButton(
            key: const ValueKey<String>('appt_today'),
            onPressed: () => _goTo(_today),
            child: Text(sw ? 'Rudi leo' : 'Back to today', style: const TextStyle(color: Colors.white70)),
          ),
        ),
      SizedBox(height: 6.h),
      InvPrimaryButton(
        key: const ValueKey<String>('appt_add'),
        busy: false,
        label: sw ? 'Weka miadi' : 'Book an appointment',
        onPressed: () => _openForm(),
      ),
      if (s != null) ...<Widget>[
        SizedBox(height: 10.h),
        Container(
          key: const ValueKey<String>('appt_reminders_card'),
          decoration: ThemeConstants.glassCardDecoration,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          child: Row(
            children: <Widget>[
              Icon(Icons.sms_outlined, color: ThemeConstants.invAccent, size: 20.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  sw ? 'Mkumbushe mteja siku moja kabla (SMS)' : 'Text the client the day before',
                  style: ThemeConstants.bodyStyle,
                ),
              ),
              Switch(
                key: const ValueKey<String>('appt_reminders_switch'),
                value: s.appointmentReminders,
                onChanged: _switchReminders,
                activeThumbColor: Colors.white,
                activeTrackColor: ThemeConstants.invAccent,
              ),
            ],
          ),
        ),
      ],
      SizedBox(height: 12.h),
      if (_loading && _items.isEmpty)
        Padding(padding: EdgeInsets.only(top: 60.h), child: const Center(child: CircularProgressIndicator(color: Colors.white70)))
      else if (_error != null && _items.isEmpty) ...<Widget>[
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(
          child: TextButton(
            key: const ValueKey<String>('appt_retry'),
            onPressed: _load,
            child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)),
          ),
        ),
      ] else if (_items.isEmpty)
        InvEmptyState(
          icon: Icons.event_available_outlined,
          message: sw ? 'Hakuna miadi siku hii. Bonyeza "Weka miadi".' : 'No appointments this day. Tap "Book an appointment".',
        )
      else ...<Widget>[
        Text(
          sw ? 'Miadi ${_items.length}' : '${_items.length} ${_items.length == 1 ? 'appointment' : 'appointments'}',
          key: const ValueKey<String>('appt_count'),
          style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8.h),
        for (final SalonAppointment a in _items) ...<Widget>[
          _AppointmentCard(appointment: a, sw: sw, onTap: () => _actions(a, sw)),
          SizedBox(height: 8.h),
        ],
      ],
    ];
  }

  static String _hm(final DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _weekday(final DateTime d, final bool sw) {
    const List<String> en = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const List<String> swa = <String>['Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', 'Ijumaa', 'Jumamosi', 'Jumapili'];
    return (sw ? swa : en)[d.weekday - 1];
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment, required this.sw, required this.onTap});

  final SalonAppointment appointment;
  final bool sw;
  final VoidCallback onTap;

  (String, Color) _status() {
    switch (appointment.status) {
      case 'confirmed':
        return (sw ? 'Imethibitishwa' : 'Confirmed', ThemeConstants.primaryCyan);
      case 'in_progress':
        return (sw ? 'Inaendelea' : 'In progress', ThemeConstants.warningAmber);
      case 'done':
        return (sw ? 'Imekamilika' : 'Done', ThemeConstants.successGreen);
      case 'cancelled':
        return (sw ? 'Imeghairiwa' : 'Cancelled', ThemeConstants.errorRed);
      case 'no_show':
        return (sw ? 'Hakuja' : 'No-show', ThemeConstants.errorRed);
      default:
        return (sw ? 'Imewekwa' : 'Booked', Colors.white70);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = _status();
    final SalonAppointment a = appointment;

    return InkWell(
      key: ValueKey<String>('appt_${a.id}'),
      borderRadius: BorderRadius.circular(20.r),
      onTap: onTap,
      child: Opacity(
        opacity: a.isActive || a.status == 'done' ? 1 : 0.6,
        child: Container(
          decoration: ThemeConstants.glassCardDecoration,
          padding: EdgeInsets.all(12.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${_AppointmentsScreenState._hm(a.startsAt)}–${_AppointmentsScreenState._hm(a.endsAt)}',
                    style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, color: ThemeConstants.invAccent),
                  ),
                  const Spacer(),
                  InvBadge(label: label, color: color),
                ],
              ),
              SizedBox(height: 6.h),
              Text(a.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
              if (a.clientPhone != null) Text(a.clientPhone!, style: ThemeConstants.captionStyle),
              SizedBox(height: 4.h),
              Text(a.servicesText, style: ThemeConstants.captionStyle.copyWith(color: Colors.white70)),
              SizedBox(height: 6.h),
              Row(
                children: <Widget>[
                  Icon(Icons.person_outline, size: 14.sp, color: Colors.white54),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Text(
                      a.staffName ?? (sw ? 'Mhudumu bado' : 'No stylist yet'),
                      style: ThemeConstants.captionStyle.copyWith(color: a.staffName == null ? ThemeConstants.warningAmber : null),
                    ),
                  ),
                  Text(tsh(a.total), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              if (a.notes != null) ...<Widget>[
                SizedBox(height: 4.h),
                Text(a.notes!, maxLines: 2, overflow: TextOverflow.ellipsis, style: ThemeConstants.captionStyle.copyWith(fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
