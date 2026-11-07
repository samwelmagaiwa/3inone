import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../widgets/glow_list_card.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/joined_sections.dart';
import 'device_attendance_flow.dart';
import 'salon_input.dart';

/// For the owner and whoever was given the right: switch device checks on, approve / reject / block / reset each person's phone, set up
/// the offices (with their number, place and who works there) and read the log of every attempt, good and bad. Nothing here is deleted:
/// a replaced phone stays in the list as "replaced".
class DevicesAdminScreen extends StatefulWidget {
  const DevicesAdminScreen({super.key, this.api, this.staff});

  final SalonApi? api;

  /// People that can be assigned to an office, as {id, name}; the inventory provider's staff list when null.
  final List<Map<String, String>>? staff;

  @override
  State<DevicesAdminScreen> createState() => _DevicesAdminScreenState();
}

class _DevicesAdminScreenState extends State<DevicesAdminScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _policyOn = false;
  List<Map<String, dynamic>> _devices = <Map<String, dynamic>>[];
  List<AttendanceOffice> _offices = <AttendanceOffice>[];
  List<Map<String, dynamic>> _checks = <Map<String, dynamic>>[];
  List<Map<String, String>> _staff = <Map<String, String>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> policy = await _api.attendancePolicy();
      final List<Map<String, dynamic>> devices = await _api.attendanceDevices();
      final List<Map<String, dynamic>> offices = await _api.attendanceOffices();
      final List<Map<String, dynamic>> checks = await _api.attendanceChecks();
      List<Map<String, String>> staff = widget.staff ?? <Map<String, String>>[];
      if (widget.staff == null && mounted) {
        try {
          final InventoryProvider inv = context.read<InventoryProvider>();
          await inv.fetchSalonStaff();
          staff = inv.salonStaff;
        } on ProviderNotFoundException {
          staff = <Map<String, String>>[];
        }
      }
      if (!mounted) return;
      setState(() {
        _policyOn = policy['enabled'] == true;
        _devices = devices;
        _offices = <AttendanceOffice>[for (final Map<String, dynamic> o in offices) AttendanceOffice.fromJson(o)];
        _checks = checks;
        _staff = staff;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _do(final Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        appBar: AppBar(
          backgroundColor: ThemeConstants.primaryBlue,
          foregroundColor: Colors.white,
          title: Text(sw ? 'Vifaa na ofisi' : 'Devices and offices'),
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: <Widget>[
              Tab(key: const ValueKey<String>('tab_devices'), text: sw ? 'Vifaa' : 'Devices'),
              Tab(key: const ValueKey<String>('tab_offices'), text: sw ? 'Ofisi' : 'Offices'),
              Tab(key: const ValueKey<String>('tab_log'), text: sw ? 'Kumbukumbu' : 'Log'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white70))
            : _error != null
                ? ListView(children: <Widget>[InvEmptyState(icon: Icons.error_outline, message: _error!), Center(child: TextButton(key: const ValueKey<String>('devices_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white))))])
                : Column(
                    children: <Widget>[
                      SwitchListTile(
                        key: const ValueKey<String>('policy_switch'),
                        value: _policyOn,
                        onChanged: _busy ? null : (bool v) => _do(() => _api.saveAttendancePolicy(enabled: v)),
                        title: Text(sw ? 'Mahudhurio kwa kifaa kilichoidhinishwa' : 'Attendance from an approved device', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          sw ? 'Ikiwashwa, kila mfanyakazi huanza na kumaliza kazi kwa simu yake iliyosajiliwa tu.' : 'When on, each person starts and finishes work only from their own registered phone.',
                          style: ThemeConstants.captionStyle,
                        ),
                      ),
                      const SectionGlowDivider(lift: false),
                      Expanded(child: TabBarView(children: <Widget>[_devicesTab(sw), _officesTab(sw), _logTab(sw)])),
                    ],
                  ),
      ),
    );
  }

  // ------------------------------------------------------------------ devices

  Widget _devicesTab(final bool sw) {
    if (_devices.isEmpty) return InvEmptyState(icon: Icons.smartphone_outlined, message: sw ? 'Hakuna kifaa kilichosajiliwa bado.' : 'No device registered yet.');

    return ListView(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 24.h),
      children: <Widget>[
        GlowListCard(
          dividerKey: 'device_divider',
          children: <Widget>[
            for (final Map<String, dynamic> d in _devices) _deviceRow(sw, d),
          ],
        ),
      ],
    );
  }

  Widget _deviceRow(final bool sw, final Map<String, dynamic> d) {
    final int id = (d['id'] as num).toInt();
    final String status = d['status']?.toString() ?? '';
    final List<String> facts = <String>[
      for (final String k in <String>['manufacturer', 'model'])
        if ((d[k]?.toString() ?? '').isNotEmpty) d[k].toString(),
      if ((d['os_name']?.toString() ?? '').isNotEmpty) '${d['os_name']} ${d['os_version'] ?? ''}'.trim(),
      if ((d['app_version']?.toString() ?? '').isNotEmpty) 'app ${d['app_version']}',
    ];

    return KeyedSubtree(
      key: ValueKey<String>('device_$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(d['user_name']?.toString() ?? '', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
              InvBadge(label: _statusLabel(sw, status), color: _statusColor(status)),
            ],
          ),
          SizedBox(height: 4.h),
          Text(facts.join(' • '), style: ThemeConstants.captionStyle),
          Text('${sw ? 'Imeombwa' : 'Asked'} ${d['requested_at'] ?? ''}${d['last_seen_at'] == null ? '' : ' • ${sw ? 'Ilionekana' : 'Last seen'} ${d['last_seen_at']}'}', style: ThemeConstants.captionStyle.copyWith(color: Colors.white70)),
          if (status != 'replaced')
            Wrap(
              spacing: 4.w,
              children: <Widget>[
                if (status == 'pending' || status == 'blocked') _act('approve', id, sw ? 'Idhinisha' : 'Approve', ThemeConstants.successGreen),
                if (status == 'pending') _act('reject', id, sw ? 'Kataa' : 'Reject', ThemeConstants.warningAmber),
                if (status != 'blocked') _act('block', id, sw ? 'Zuia' : 'Block', ThemeConstants.errorText),
                if (status == 'approved') _act('reset', id, sw ? 'Weka upya' : 'Reset', ThemeConstants.warningAmber),
              ],
            ),
        ],
      ),
    );
  }

  Widget _act(final String decision, final int id, final String label, final Color color) => TextButton(
        key: ValueKey<String>('device_${decision}_$id'),
        onPressed: _busy ? null : () => _do(() => _api.decideDevice(id, decision)),
        child: Text(label, style: TextStyle(color: color)),
      );

  static String _statusLabel(final bool sw, final String s) {
    switch (s) {
      case 'approved':
        return sw ? 'Imeidhinishwa' : 'Approved';
      case 'pending':
        return sw ? 'Inasubiri' : 'Pending';
      case 'rejected':
        return sw ? 'Imekataliwa' : 'Rejected';
      case 'blocked':
        return sw ? 'Imezuiwa' : 'Blocked';
      case 'replaced':
        return sw ? 'Imebadilishwa' : 'Replaced';
      default:
        return s;
    }
  }

  static Color _statusColor(final String s) => s == 'approved' ? ThemeConstants.successGreen : (s == 'pending' ? ThemeConstants.warningAmber : (s == 'replaced' ? Colors.white54 : ThemeConstants.errorText));

  // ------------------------------------------------------------------ offices

  Widget _officesTab(final bool sw) => ListView(
        padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 24.h),
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey<String>('add_office'),
              onPressed: _busy ? null : () => _editOffice(sw, null),
              icon: const Icon(Icons.add_business_outlined, color: Colors.white70),
              label: Text(sw ? 'Ongeza ofisi' : 'Add an office', style: const TextStyle(color: Colors.white70)),
            ),
          ),
          if (_offices.isEmpty)
            InvEmptyState(icon: Icons.storefront_outlined, message: sw ? 'Hakuna ofisi. Ongeza ya kwanza.' : 'No offices yet. Add the first.')
          else
            GlowListCard(
              dividerKey: 'office_divider',
              children: <Widget>[
                for (final AttendanceOffice o in _offices)
                  KeyedSubtree(
                    key: ValueKey<String>('office_row_${o.id}'),
                    child: InkWell(
                      onTap: _busy ? null : () => _editOffice(sw, o),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(child: Text(o.label, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
                              if (!o.active) InvBadge(label: sw ? 'Imezimwa' : 'Off', color: Colors.white54),
                              if (o.geofenceRequired) InvBadge(label: '${o.radiusM} m', color: ThemeConstants.successGreen),
                            ],
                          ),
                          Text(
                            '${o.address ?? ''}${o.address == null || o.address!.isEmpty ? '' : ' • '}${sw ? 'Watu' : 'People'} ${o.staffIds.length}',
                            style: ThemeConstants.captionStyle,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      );

  Future<void> _editOffice(final bool sw, final AttendanceOffice? office) async {
    final TextEditingController name = TextEditingController(text: office?.name ?? '');
    final TextEditingController address = TextEditingController(text: office?.address ?? '');
    final TextEditingController lat = TextEditingController(text: office?.latitude?.toString() ?? '');
    final TextEditingController lng = TextEditingController(text: office?.longitude?.toString() ?? '');
    final TextEditingController radius = TextEditingController(text: (office?.radiusM ?? 150).toString());
    bool fence = office?.geofenceRequired ?? false;
    bool active = office?.active ?? true;
    final Set<String> chosen = <String>{...?office?.staffIds};

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) set) => InvSheetShell(
          title: office == null ? (sw ? 'Ofisi mpya' : 'New office') : office.label,
          children: <Widget>[
            Material(
              type: MaterialType.transparency,
              child: Column(
                children: <Widget>[
                  TextField(key: const ValueKey<String>('office_name'), controller: name, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Jina la ofisi' : 'Office name')),
                  SizedBox(height: 10.h),
                  TextField(key: const ValueKey<String>('office_address'), controller: address, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Anwani' : 'Address')),
                  SizedBox(height: 10.h),
                  Row(
                    children: <Widget>[
                      Expanded(child: TextField(key: const ValueKey<String>('office_lat'), controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Latitudo' : 'Latitude'))),
                      SizedBox(width: 8.w),
                      Expanded(child: TextField(key: const ValueKey<String>('office_lng'), controller: lng, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Longitudo' : 'Longitude'))),
                      SizedBox(width: 8.w),
                      SizedBox(width: 80.w, child: TextField(key: const ValueKey<String>('office_radius'), controller: radius, keyboardType: TextInputType.number, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Mita' : 'Metres'))),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  const SectionGlowDivider(lift: false),
                  SwitchListTile(key: const ValueKey<String>('office_fence'), contentPadding: EdgeInsets.zero, value: fence, onChanged: (bool v) => set(() => fence = v), title: Text(sw ? 'Lazima awe karibu na ofisi' : 'Must be near the office', style: ThemeConstants.bodyStyle)),
                  const SectionGlowDivider(lift: false),
                  SwitchListTile(key: const ValueKey<String>('office_active'), contentPadding: EdgeInsets.zero, value: active, onChanged: (bool v) => set(() => active = v), title: Text(sw ? 'Ofisi inatumika' : 'Office is active', style: ThemeConstants.bodyStyle)),
                  const SectionGlowDivider(lift: false),
                  if (_staff.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text(sw ? 'Wanaofanya kazi hapa' : 'Who works here', style: ThemeConstants.captionStyle)),
                  for (final Map<String, String> s in _staff)
                    CheckboxListTile(
                      key: ValueKey<String>('office_staff_${s['id']}'),
                      contentPadding: EdgeInsets.zero,
                      value: chosen.contains(s['id']),
                      onChanged: (bool? v) => set(() => v == true ? chosen.add(s['id']!) : chosen.remove(s['id'])),
                      title: Text(s['name'] ?? '', style: ThemeConstants.bodyStyle),
                    ),
                  SizedBox(height: 8.h),
                  ElevatedButton(key: const ValueKey<String>('office_save'), onPressed: () => Navigator.pop(sheet, true), child: Text(sw ? 'Hifadhi' : 'Save')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await _do(() async {
      await _api.saveAttendanceOffice(
        id: office?.id,
        name: name.text.trim(),
        address: address.text.trim().isEmpty ? null : address.text.trim(),
        latitude: double.tryParse(lat.text.trim()),
        longitude: double.tryParse(lng.text.trim()),
        radiusM: int.tryParse(radius.text.trim()) ?? 150,
        geofenceRequired: fence,
        active: active,
      );
      // A new office gets its number from the server, so the people are set on the saved office.
      int? id = office?.id;
      if (id == null) {
        final List<Map<String, dynamic>> now = await _api.attendanceOffices();
        id = now.isEmpty ? null : now.map((Map<String, dynamic> o) => (o['id'] as num).toInt()).reduce((int a, int b) => a > b ? a : b);
      }
      if (id != null) await _api.setOfficeStaff(id, chosen.toList());
    });
  }

  // ------------------------------------------------------------------ the log

  Widget _logTab(final bool sw) {
    if (_checks.isEmpty) return InvEmptyState(icon: Icons.fact_check_outlined, message: sw ? 'Bado hakuna kumbukumbu.' : 'Nothing logged yet.');

    return ListView(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 24.h),
      children: <Widget>[
        GlowListCard(
          dividerKey: 'check_divider',
          children: <Widget>[
            for (final Map<String, dynamic> c in _checks)
              KeyedSubtree(
                key: ValueKey<String>('check_${c['id']}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: Text('${c['user_name'] ?? ''}  ${c['purpose'] == 'out' ? '⟵' : '⟶'}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
                        InvBadge(label: c['outcome']?.toString() ?? '', color: c['outcome'] == 'ok' ? ThemeConstants.successGreen : ThemeConstants.errorText),
                      ],
                    ),
                    Text('${c['at'] ?? ''}${(c['ip']?.toString() ?? '').isEmpty ? '' : ' • ${c['ip']}'}${c['office_id'] == null ? '' : ' • #${c['office_id']}'}', style: ThemeConstants.captionStyle),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
