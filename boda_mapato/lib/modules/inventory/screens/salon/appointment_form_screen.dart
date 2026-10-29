import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/inv_customer.dart';
import '../../models/inv_product.dart';
import '../../models/salon_models.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_text.dart';

/// Book an appointment, or change one: who, when, which services, with which stylist. The services come from the
/// salon's own list (with their price options); only the people who may do ALL the chosen services are offered.
/// Pops `true` when something was saved.
class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({super.key, this.api, this.appointment, required this.day});

  final SalonApi? api;

  /// The appointment being changed; null = a new one.
  final SalonAppointment? appointment;

  /// The day the diary was showing: a new appointment starts on it.
  final DateTime day;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _deposit = TextEditingController();
  String _depositMethod = 'cash';

  late DateTime _date = DateTime(widget.day.year, widget.day.month, widget.day.day);
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  int? _customerId;
  String? _staffId;
  final List<AppointmentService> _services = <AppointmentService>[];
  bool _saving = false;
  String? _error;

  bool get _editing => widget.appointment != null;

  @override
  void initState() {
    super.initState();
    // The way the deposit was paid is asked only once there is a deposit.
    _deposit.addListener(() => setState(() {}));
    final SalonAppointment? a = widget.appointment;
    if (a != null) {
      _name.text = a.clientName;
      _phone.text = a.clientPhone ?? '';
      _notes.text = a.notes ?? '';
      if (a.depositAmount > 0) {
        _deposit.text = formatAmount(a.depositAmount.round());
        _depositMethod = a.depositMethod ?? 'cash';
      }
      _date = DateTime(a.startsAt.year, a.startsAt.month, a.startsAt.day);
      _time = TimeOfDay(hour: a.startsAt.hour, minute: a.startsAt.minute);
      _customerId = a.customerId;
      _staffId = a.staffId;
      _services.addAll(a.services);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final InventoryProvider inv = context.read<InventoryProvider>();
      inv.fetchSalonStaff();
      if (inv.products.isEmpty) inv.fetchProducts();
      if (inv.customers.isEmpty) inv.fetchCustomers();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _deposit.dispose();
    super.dispose();
  }

  DateTime get _startsAt => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  /// Minutes the chosen services take together (an hour when none says).
  int get _minutes {
    final int sum = _services.fold<int>(0, (int s, AppointmentService x) => s + (x.minutes ?? 0));
    return sum > 0 ? sum : 60;
  }

  double get _total => _services.fold<double>(0, (double s, AppointmentService x) => s + x.price);

  /// The people who may do every chosen service (a service that names nobody may be done by anyone).
  List<Map<String, String>> _eligible(final InventoryProvider inv) {
    final List<List<String>> limits = <List<String>>[
      for (final AppointmentService s in _services)
        if ((inv.products.where((InvProduct p) => p.id == s.productId).firstOrNull?.staffIds ?? const <String>[]).isNotEmpty)
          inv.products.firstWhere((InvProduct p) => p.id == s.productId).staffIds,
    ];
    return inv.salonStaff.where((Map<String, String> m) => limits.every((List<String> l) => l.contains(m['id']))).toList();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickClient() async {
    final InventoryProvider inv = context.read<InventoryProvider>();
    final bool sw = context.read<LocalizationService>().isSwahili;
    final InvCustomer? c = await showModalBottomSheet<InvCustomer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => _ClientSheet(customers: inv.customers, sw: sw),
    );
    if (c == null || !mounted) return;
    setState(() {
      _customerId = c.id;
      _name.text = c.name;
      _phone.text = c.phone;
    });
  }

  Future<void> _addService() async {
    final InventoryProvider inv = context.read<InventoryProvider>();
    final bool sw = context.read<LocalizationService>().isSwahili;
    final List<InvProduct> list = inv.products.where((InvProduct p) => p.isService && p.status == 'active').toList();
    final InvProduct? p = await showModalBottomSheet<InvProduct>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => InvSheetShell(
        title: sw ? 'Chagua huduma' : 'Choose a service',
        children: <Widget>[
          Material(
            type: MaterialType.transparency,
            child: Column(
              children: <Widget>[
                if (list.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    child: Text(sw ? 'Hakuna huduma bado. Ziongeze kwenye Huduma na Bidhaa.' : 'No services yet. Add them under Services & Goods.', key: const ValueKey<String>('appt_no_services'), style: ThemeConstants.captionStyle),
                  ),
                for (final InvProduct s in list)
                  ListTile(
                    key: ValueKey<String>('appt_service_${s.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.content_cut_rounded, color: Colors.white70, size: 20.sp),
                    title: Text(s.name, style: ThemeConstants.bodyStyle),
                    subtitle: Text('${tsh(s.sellingPrice)}${s.durationMinutes == null ? '' : ' • ${s.durationMinutes} min'}', style: ThemeConstants.captionStyle),
                    onTap: () => Navigator.pop(sheet, s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (p == null || !mounted) return;

    PriceOption? option;
    if (p.priceOptions.isNotEmpty) {
      final List<PriceOption> options = p.priceOptions;
      option = await showModalBottomSheet<PriceOption>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext sheet) => InvSheetShell(
          title: p.name,
          children: <Widget>[
            Material(
              type: MaterialType.transparency,
              child: Column(
                children: <Widget>[
                  for (final PriceOption o in options)
                    ListTile(
                      key: ValueKey<String>('appt_option_${o.label}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(o.label, style: ThemeConstants.bodyStyle),
                      trailing: Text(tsh(o.price), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                      onTap: () => Navigator.pop(sheet, o),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
      if (option == null || !mounted) return; // chose nothing: the service is not added
    }

    setState(() {
      _services.add(AppointmentService(
        productId: p.id,
        name: p.name,
        price: option?.price ?? p.sellingPrice,
        minutes: p.durationMinutes,
        label: option?.label,
      ));
      _dropStylistWhoCannot(inv);
    });
  }

  /// A stylist chosen earlier who may not do the services now chosen is let go, so a booking is never made that
  /// the salon itself ruled out.
  void _dropStylistWhoCannot(final InventoryProvider inv) {
    if (_staffId != null && !_eligible(inv).any((Map<String, String> m) => m['id'] == _staffId)) _staffId = null;
  }

  Future<void> _save({final bool force = false}) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = sw ? 'Andika jina la mteja.' : 'Write the name of the client.');
      return;
    }
    if (_services.isEmpty) {
      setState(() => _error = sw ? 'Chagua angalau huduma moja.' : 'Choose at least one service.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.saveAppointment(
        id: widget.appointment?.id,
        customerId: _customerId,
        clientName: _name.text.trim(),
        clientPhone: _phone.text.trim(),
        staffId: _staffId,
        startsAt: _startsAt,
        services: _services,
        notes: _notes.text.trim(),
        // A settled deposit (in the sale, kept or given back) is not sent again.
        depositAmount: widget.appointment?.depositSettled == true ? null : (double.tryParse(_deposit.text.replaceAll(',', '').trim()) ?? 0),
        depositMethod: _depositMethod,
        force: force,
      );
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Miadi imehifadhiwa.' : 'Appointment saved.');
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      final String message = readableErrorMessage(e);
      setState(() {
        _saving = false;
        _error = message;
      });
      // The stylist is already booked then, is off that day or works other hours (the server's words name the booked
      // hours, "10:00-11:00", or the date, "13/10/2026", in either language): say so, and let the owner book anyway
      // if that is what they mean.
      if (!force && RegExp(r'\d{1,2}:\d{2}-\d{1,2}:\d{2}|\d{2}/\d{2}/\d{4}').hasMatch(message)) {
        final bool? anyway = await showDialog<bool>(
          context: context,
          builder: (BuildContext d) => AlertDialog(
            title: Text(sw ? 'Mhudumu ana miadi' : 'Stylist is booked'),
            content: Text(message, key: const ValueKey<String>('appt_clash_message')),
            actions: <Widget>[
              TextButton(key: const ValueKey<String>('appt_clash_cancel'), onPressed: () => Navigator.pop(d, false), child: Text(sw ? 'Badilisha muda' : 'Change the time')),
              TextButton(key: const ValueKey<String>('appt_clash_force'), onPressed: () => Navigator.pop(d, true), child: Text(sw ? 'Weka hata hivyo' : 'Book anyway')),
            ],
          ),
        );
        if (anyway == true && mounted) await _save(force: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final InventoryProvider provider = context.watch<InventoryProvider>();
    final List<Map<String, String>> eligible = _eligible(provider);
    final DateTime ends = _startsAt.add(Duration(minutes: _minutes));
    String hm(final DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return ThemeConstants.buildScaffold(
      title: _editing ? (sw ? 'Badilisha miadi' : 'Change appointment') : (sw ? 'Miadi mpya' : 'New appointment'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(sw ? 'Mteja' : 'Client', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
              TextButton.icon(
                key: const ValueKey<String>('appt_pick_client'),
                onPressed: _pickClient,
                icon: const Icon(Icons.person_search_outlined, color: Colors.white70),
                label: Text(sw ? 'Chagua aliyepo' : 'Pick existing', style: const TextStyle(color: Colors.white70)),
              ),
            ],
          ),
          InvTextField(key: const ValueKey<String>('appt_name'), controller: _name, label: sw ? 'Jina la mteja' : 'Client name'),
          SizedBox(height: 10.h),
          InvTextField(
            key: const ValueKey<String>('appt_phone'),
            controller: _phone,
            label: sw ? 'Namba ya simu' : 'Phone number',
            hint: '07…',
            isOptional: true,
            keyboardType: TextInputType.phone,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
          ),
          SizedBox(height: 16.h),
          Text(sw ? 'Lini' : 'When', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 8.h),
          Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  key: const ValueKey<String>('appt_date'),
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12.r),
                  child: InputDecorator(decoration: ThemeConstants.invInputDecoration(sw ? 'Tarehe' : 'Date'), child: Text(dayLabel(_date), style: ThemeConstants.bodyStyle)),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: InkWell(
                  key: const ValueKey<String>('appt_time'),
                  onTap: _pickTime,
                  borderRadius: BorderRadius.circular(12.r),
                  child: InputDecorator(decoration: ThemeConstants.invInputDecoration(sw ? 'Saa' : 'Time'), child: Text(hm(_startsAt), style: ThemeConstants.bodyStyle)),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            children: <Widget>[
              Expanded(child: Text(sw ? 'Huduma' : 'Services', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
              TextButton.icon(
                key: const ValueKey<String>('appt_add_service'),
                onPressed: _addService,
                icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                label: Text(sw ? 'Ongeza' : 'Add', style: const TextStyle(color: Colors.white70)),
              ),
            ],
          ),
          if (_services.isEmpty)
            Text(sw ? 'Bado hakuna huduma.' : 'No service yet.', style: ThemeConstants.captionStyle)
          else
            for (int i = 0; i < _services.length; i++)
              Container(
                key: ValueKey<String>('appt_line_$i'),
                margin: EdgeInsets.only(bottom: 6.h),
                decoration: ThemeConstants.glassCardDecoration,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(_services[i].shown, style: ThemeConstants.bodyStyle)),
                    Text(tsh(_services[i].price), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                    IconButton(
                      key: ValueKey<String>('appt_remove_$i'),
                      onPressed: () => setState(() => _services.removeAt(i)),
                      icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    ),
                  ],
                ),
              ),
          SizedBox(height: 16.h),
          Text(sw ? 'Mhudumu' : 'Stylist', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 4.h,
            children: <Widget>[
              ChoiceChip(
                key: const ValueKey<String>('appt_staff_none'),
                label: Text(sw ? 'Bado' : 'Not yet'),
                selected: _staffId == null,
                onSelected: (_) => setState(() => _staffId = null),
              ),
              for (final Map<String, String> m in eligible)
                ChoiceChip(
                  key: ValueKey<String>('appt_staff_${m['id']}'),
                  label: Text(m['name'] ?? ''),
                  selected: _staffId == m['id'],
                  onSelected: (_) => setState(() => _staffId = m['id']),
                ),
            ],
          ),
          if (_services.isNotEmpty && eligible.length < provider.salonStaff.length)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text(
                sw ? 'Wanaoonyeshwa ni wale wanaoweza kufanya huduma zote zilizochaguliwa.' : 'Only people who can do all the chosen services are shown.',
                key: const ValueKey<String>('appt_staff_note'),
                style: ThemeConstants.captionStyle,
              ),
            ),
          SizedBox(height: 16.h),
          InvTextField(key: const ValueKey<String>('appt_notes'), controller: _notes, label: sw ? 'Maelezo' : 'Notes', isOptional: true, maxLines: 2),
          SizedBox(height: 10.h),
          if (widget.appointment?.depositSettled == true)
            Text(
              sw ? 'Amana ya ${tsh(widget.appointment!.depositAmount)}: ${widget.appointment!.depositStatus}' : 'Deposit ${tsh(widget.appointment!.depositAmount)}: ${widget.appointment!.depositStatus}',
              key: const ValueKey<String>('appt_deposit_settled'),
              style: ThemeConstants.captionStyle,
            )
          else ...<Widget>[
            InvTextField(key: const ValueKey<String>('appt_deposit'), controller: _deposit, label: sw ? 'Amana iliyolipwa (TSh)' : 'Deposit paid (TSh)', isOptional: true, keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[ThousandsFormatter()]),
            if ((double.tryParse(_deposit.text.replaceAll(',', '').trim()) ?? 0) > 0)
              Wrap(
                spacing: 8.w,
                children: <Widget>[
                  for (final String c in <String>['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer'])
                    ChoiceChip(key: ValueKey<String>('appt_deposit_$c'), label: Text(channelLabel(sw: sw, channel: c)), selected: _depositMethod == c, onSelected: (_) => setState(() => _depositMethod = c)),
                ],
              ),
          ],
          SizedBox(height: 14.h),
          Container(
            key: const ValueKey<String>('appt_summary'),
            decoration: ThemeConstants.glassCardDecoration,
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(sw ? '${hm(_startsAt)}–${hm(ends)} • dakika $_minutes' : '${hm(_startsAt)}–${hm(ends)} • $_minutes min', style: ThemeConstants.bodyStyle)),
                Text(tsh(_total), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, color: ThemeConstants.invAccent)),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: Text(_error!, key: const ValueKey<String>('appt_error'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorText, fontSize: 12.sp)),
            ),
          SizedBox(height: 14.h),
          InvPrimaryButton(key: const ValueKey<String>('appt_save'), busy: _saving, label: sw ? 'Hifadhi miadi' : 'Save appointment', onPressed: _save),
        ],
      ),
    );
  }
}

class _ClientSheet extends StatefulWidget {
  const _ClientSheet({required this.customers, required this.sw});

  final List<InvCustomer> customers;
  final bool sw;

  @override
  State<_ClientSheet> createState() => _ClientSheetState();
}

class _ClientSheetState extends State<_ClientSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final String q = _q.trim().toLowerCase();
    final List<InvCustomer> shown = widget.customers.where((InvCustomer c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(q)).take(40).toList();

    return InvSheetShell(
      title: widget.sw ? 'Chagua mteja' : 'Choose a client',
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('appt_client_search'),
          style: ThemeConstants.bodyStyle,
          decoration: ThemeConstants.invInputDecoration(widget.sw ? 'Tafuta jina au simu' : 'Search name or phone'),
          onChanged: (String v) => setState(() => _q = v),
        ),
        SizedBox(height: 8.h),
        Material(
          type: MaterialType.transparency,
          child: Column(
            children: <Widget>[
              if (shown.isEmpty) Padding(padding: EdgeInsets.symmetric(vertical: 12.h), child: Text(widget.sw ? 'Hakuna mteja aliyepatikana.' : 'No client found.', style: ThemeConstants.captionStyle)),
              for (final InvCustomer c in shown)
                ListTile(
                  key: ValueKey<String>('appt_client_${c.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_outline, color: Colors.white70, size: 20.sp),
                  title: Text(c.name, style: ThemeConstants.bodyStyle),
                  subtitle: Text(c.phone.isEmpty ? '—' : c.phone, style: ThemeConstants.captionStyle),
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
