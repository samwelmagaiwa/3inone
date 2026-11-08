import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../widgets/glow_list_card.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/joined_sections.dart';
import 'device_attendance_flow.dart';
import '../../services/device_identity.dart';
import 'salon_access.dart';
import 'salon_input.dart';

/// For the owner and whoever was given the right: switch device checks on, approve / reject / block / reset each person's phone, set up
/// the offices (with their number, place and who works there) and read the log of every attempt, good and bad. Nothing here is deleted:
/// a replaced phone stays in the list as "replaced".
class DevicesAdminScreen extends StatefulWidget {
  const DevicesAdminScreen({super.key, this.api, this.staff, this.identity, this.rights});

  /// Which of the four attendance rights the person holds (a test fixes it); read from who is signed in when null.
  final Set<String>? rights;

  /// Where the phone is (a fake in tests): the office's place is taken from the phone, never typed.
  final DeviceIdentity? identity;

  final SalonApi? api;

  /// People that can be assigned to an office, as {id, name}; the inventory provider's staff list when null.
  final List<Map<String, String>>? staff;

  @override
  State<DevicesAdminScreen> createState() => _DevicesAdminScreenState();
}

class _DevicesAdminScreenState extends State<DevicesAdminScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  late final DeviceIdentity _identity = widget.identity ?? SecureDeviceIdentity();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _policyOn = false;
  List<Map<String, dynamic>> _devices = <Map<String, dynamic>>[];
  List<AttendanceOffice> _offices = <AttendanceOffice>[];
  List<Map<String, dynamic>> _checks = <Map<String, dynamic>>[];
  List<Map<String, String>> _staff = <Map<String, String>>[];
  List<SalonBranchInfo> _branches = <SalonBranchInfo>[];

  Set<String> get _rights => widget.rights ?? attendanceRightsHere(context, listen: false);

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
      // Only what this person holds the right to: the server refuses the rest.
      final Set<String> has = _rights;
      final Map<String, dynamic> policy = has.contains('inv_salon_attendance_policy') ? await _api.attendancePolicy() : <String, dynamic>{};
      final List<Map<String, dynamic>> devices = has.contains('inv_salon_devices') ? await _api.attendanceDevices() : <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> offices = has.contains('inv_salon_offices') ? await _api.attendanceOffices() : <Map<String, dynamic>>[];
      final List<Map<String, dynamic>> checks = has.contains('inv_salon_attendance_log') ? await _api.attendanceChecks() : <Map<String, dynamic>>[];
      List<SalonBranchInfo> branches = <SalonBranchInfo>[];
      if (has.contains('inv_salon_offices')) {
        try {
          branches = await _api.branches();
        } on Exception {
          branches = <SalonBranchInfo>[]; // no right to see branches: an office of its own still works
        }
      }
      List<Map<String, String>> staff = widget.staff ?? <Map<String, String>>[];
      if (widget.staff == null && mounted && has.contains('inv_salon_offices')) {
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
        _branches = branches;
        // the business admin is never an office's staff: they control the staff, they do not start work
        _staff = <Map<String, String>>[for (final Map<String, String> s in staff) if (!isBusinessAdminRole(s['role'])) s];
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
    final Set<String> has = widget.rights ?? attendanceRightsHere(context);
    // One tab for each right held.
    final List<(String, String, Widget Function())> tabs = <(String, String, Widget Function())>[
      if (has.contains('inv_salon_devices')) ('tab_devices', sw ? 'Vifaa' : 'Devices', () => _devicesTab(sw)),
      if (has.contains('inv_salon_offices')) ('tab_offices', sw ? 'Ofisi' : 'Offices', () => _officesTab(sw)),
      if (has.contains('inv_salon_attendance_log')) ('tab_log', sw ? 'Kumbukumbu' : 'Log', () => _logTab(sw)),
    ];

    return DefaultTabController(
      key: ValueKey<int>(tabs.length),
      length: tabs.isEmpty ? 1 : tabs.length,
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
              for (final (String, String, Widget Function()) tab in tabs) Tab(key: ValueKey<String>(tab.$1), text: tab.$2),
              if (tabs.isEmpty) const Tab(text: ''),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white70))
            : _error != null
                ? ListView(children: <Widget>[InvEmptyState(icon: Icons.error_outline, message: _error!), Center(child: TextButton(key: const ValueKey<String>('devices_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white))))])
                : Column(
                    children: <Widget>[
                      // The on/off switch is a right of its own: shown (and loaded) only for whoever holds it.
                      if (has.contains('inv_salon_attendance_policy')) ...<Widget>[
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
                      ],
                      Expanded(
                        child: tabs.isEmpty
                            ? InvEmptyState(icon: Icons.lock_outline, message: sw ? 'Huna ruhusa ya sehemu hii.' : 'You do not have a right to anything here.')
                            : TabBarView(children: <Widget>[for (final (String, String, Widget Function()) tab in tabs) tab.$3()]),
                      ),
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

  static String _placeLabel(final bool sw, final String s) {
    switch (s) {
      case 'at_work':
        return sw ? 'Yuko kazini' : 'At work';
      case 'away':
        return sw ? 'Yuko mbali' : 'Away';
      case 'no_location':
        return sw ? 'Hakuna eneo' : 'No location';
      case 'stale':
        return sw ? 'Eneo la zamani' : 'Old location';
      case 'weak_signal':
        return sw ? 'GPS hafifu' : 'Weak GPS';
      case 'mocked':
        return sw ? 'Eneo bandia' : 'Fake location';
      default:
        return sw ? 'Hakuna mahali pa kulinganisha' : 'No place to compare';
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
    int? branchId = office?.branchId;
    bool fence = office?.geofenceRequired ?? false;
    bool active = office?.active ?? true;
    String? problem;
    bool locating = false;
    double? lastAccuracy;
    final Set<String> withPlace = <String>{...?office?.staffPlaceIds};
    bool started = false;
    String? accuracyNote = office?.latitude == null ? null : (sw ? 'Mahali pamehifadhiwa' : 'Place saved');

    // Capture the place for ONE person (from this phone, standing where they work): it wins over the office's place for them.
    Future<void> capturePerson(final String uid, final void Function(void Function()) set) async {
      final PhonePlace? where = await _identity.place();
      if (!mounted) return;
      if (where == null || (where.accuracy != null && where.accuracy! > 100)) {
        set(() => problem = sw ? 'Simu haikupata mahali pazuri. Nenda eneo wazi ujaribu tena.' : 'The phone could not get a good place. Move to open space and try again.');
        return;
      }
      try {
        await _api.setPersonPlace(office!.id, uid, latitude: where.latitude, longitude: where.longitude, accuracy: where.accuracy);
        set(() {
          withPlace.add(uid);
          problem = null;
          accuracyNote = sw ? 'Mahali pa mtu pamehifadhiwa' : 'Person\u2019s place saved';
        });
      } on Exception catch (e) {
        set(() => problem = readableErrorMessage(e));
      }
    }

    Future<void> clearPerson(final String uid, final void Function(void Function()) set) async {
      try {
        await _api.clearPersonPlace(office!.id, uid);
        set(() => withPlace.remove(uid));
      } on Exception catch (e) {
        set(() => problem = readableErrorMessage(e));
      }
    }

    // The place is read from the phone (stand in the office and tap): never typed, so it cannot be mistyped.
    Future<void> grab(final void Function(void Function()) set) async {
      set(() {
        locating = true;
        problem = null;
      });
      final PhonePlace? where = await _identity.place();
      if (!mounted) return;
      set(() {
        locating = false;
        if (where != null && where.accuracy != null && where.accuracy! > 100) {
          problem = sw ? 'Mawasiliano ya GPS ni hafifu (± ${where.accuracy!.round()} m). Nenda eneo wazi ujaribu tena.' : 'The GPS signal is weak (± ${where.accuracy!.round()} m). Move to open space and try again.';
        } else if (where == null) {
          problem = sw ? 'Simu haikupata mahali. Washa location na ruhusu app, kisha jaribu tena.' : 'The phone could not find where it is. Turn location on, allow the app, and try again.';
        } else {
          lastAccuracy = where.accuracy;
          lat.text = where.latitude.toStringAsFixed(7);
          lng.text = where.longitude.toStringAsFixed(7);
          accuracyNote = where.accuracy == null ? (sw ? 'Mahali pamechukuliwa' : 'Place captured') : (sw ? 'Mahali pamechukuliwa (± ${where.accuracy!.round()} m)' : 'Place captured (± ${where.accuracy!.round()} m)');
        }
      });
    }

    final Set<String> chosen = <String>{...?office?.staffIds};

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) set) {
          if (!started && lat.text.isEmpty) {
            started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => grab(set));
          }

          return InvSheetShell(
          title: office == null ? (sw ? 'Ofisi mpya' : 'New office') : office.label,
          children: <Widget>[
            Material(
              type: MaterialType.transparency,
              child: Column(
                children: <Widget>[
                  if (_branches.isNotEmpty) ...<Widget>[
                    DropdownButtonFormField<int?>(
                      key: const ValueKey<String>('office_branch'),
                      value: branchId,
                      isExpanded: true,
                      dropdownColor: ThemeConstants.invFill,
                      style: salonInputStyle,
                      decoration: salonInput(labelText: sw ? 'Tawi' : 'Branch'),
                      items: <DropdownMenuItem<int?>>[
                        DropdownMenuItem<int?>(value: null, child: Text(sw ? 'Hakuna (ofisi yake yenyewe)' : 'None (an office of its own)', style: salonInputStyle)),
                        for (final SalonBranchInfo b in _branches) DropdownMenuItem<int?>(value: b.id, child: Text(b.name, style: salonInputStyle)),
                      ],
                      onChanged: (int? v) => set(() {
                        branchId = v;
                        if (v != null) {
                          final SalonBranchInfo b = _branches.firstWhere((SalonBranchInfo x) => x.id == v);
                          name.text = b.name;
                          address.text = b.address;
                        }
                      }),
                    ),
                    SizedBox(height: 10.h),
                  ],
                  TextField(key: const ValueKey<String>('office_name'), controller: name, enabled: branchId == null, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Jina la ofisi' : 'Office name')),
                  SizedBox(height: 10.h),
                  TextField(key: const ValueKey<String>('office_address'), controller: address, enabled: branchId == null, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Anwani' : 'Address')),
                  SizedBox(height: 10.h),
                  Row(
                    children: <Widget>[
                      Expanded(child: TextField(key: const ValueKey<String>('office_lat'), controller: lat, readOnly: true, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Latitudo' : 'Latitude'))),
                      SizedBox(width: 8.w),
                      Expanded(child: TextField(key: const ValueKey<String>('office_lng'), controller: lng, readOnly: true, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Longitudo' : 'Longitude'))),
                      SizedBox(width: 8.w),
                      SizedBox(width: 80.w, child: TextField(key: const ValueKey<String>('office_radius'), controller: radius, keyboardType: TextInputType.number, style: salonInputStyle, decoration: salonInput(labelText: sw ? 'Mita' : 'Metres'))),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  Row(
                    children: <Widget>[
                      Expanded(child: Text(accuracyNote ?? (sw ? 'Mahali pa wote wa ofisi hii: simama ofisini na uchukue.' : 'One place for everyone at this office: stand there and capture it.'), key: const ValueKey<String>('office_place_note'), style: ThemeConstants.captionStyle)),
                      TextButton.icon(
                        key: const ValueKey<String>('office_capture'),
                        onPressed: locating ? null : () => grab(set),
                        icon: locating ? SizedBox(width: 16.w, height: 16.w, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)) : const Icon(Icons.my_location, color: Colors.white70),
                        label: Text(sw ? 'Tumia mahali nilipo' : 'Use my location', style: const TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                  const SectionGlowDivider(lift: false),
                  SwitchListTile(key: const ValueKey<String>('office_fence'), contentPadding: EdgeInsets.zero, value: fence, onChanged: (bool v) => set(() => fence = v), title: Text(sw ? 'Lazima awe karibu na ofisi' : 'Must be near the office', style: ThemeConstants.bodyStyle)),
                  const SectionGlowDivider(lift: false),
                  SwitchListTile(key: const ValueKey<String>('office_active'), contentPadding: EdgeInsets.zero, value: active, onChanged: (bool v) => set(() => active = v), title: Text(sw ? 'Ofisi inatumika' : 'Office is active', style: ThemeConstants.bodyStyle)),
                  const SectionGlowDivider(lift: false),
                  if (_staff.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        office == null
                            ? (sw ? 'Wanaofanya kazi hapa (hifadhi kwanza, kisha unaweza kuchukua mahali pa mtu mmoja, si lazima)' : 'Who works here (save first; then you may capture a place for one person, optional)')
                            : (sw ? 'Wanaofanya kazi hapa. Bonyeza pini ya mtu kuchukua mahali pake peke yake (si lazima); wasio na pini hutumia mahali pa ofisi.' : 'Who works here. Tap a person\u2019s pin to capture a place for them alone (optional); everyone else uses the office place.'),
                        style: ThemeConstants.captionStyle,
                      ),
                    ),
                  for (final Map<String, String> s in _staff)
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: CheckboxListTile(
                            key: ValueKey<String>('office_staff_${s['id']}'),
                            contentPadding: EdgeInsets.zero,
                            value: chosen.contains(s['id']),
                            onChanged: (bool? v) => set(() => v == true ? chosen.add(s['id']!) : chosen.remove(s['id'])),
                            title: Text(s['name'] ?? '', style: ThemeConstants.bodyStyle),
                            subtitle: withPlace.contains(s['id']) ? Text(sw ? 'Ana mahali pake mwenyewe' : 'Has a place of their own', style: ThemeConstants.captionStyle) : null,
                          ),
                        ),
                        // only for someone already saved at this office: stand where they work and capture it for them
                        if (office != null && office.staffIds.contains(s['id'])) ...<Widget>[
                          IconButton(
                            key: ValueKey<String>('person_capture_${s['id']}'),
                            tooltip: sw ? 'Chukua mahali pa mtu huyu' : 'Capture this person\u2019s place',
                            onPressed: () => capturePerson(s['id']!, set),
                            icon: Icon(withPlace.contains(s['id']) ? Icons.where_to_vote : Icons.add_location_alt_outlined, color: withPlace.contains(s['id']) ? ThemeConstants.successGreen : Colors.white70),
                          ),
                          if (withPlace.contains(s['id']))
                            IconButton(key: ValueKey<String>('person_clear_${s['id']}'), tooltip: sw ? 'Rudi kwenye mahali pa ofisi' : 'Back to the office\u2019s place', onPressed: () => clearPerson(s['id']!, set), icon: const Icon(Icons.location_off_outlined, color: Colors.white54)),
                        ],
                      ],
                    ),
                  SizedBox(height: 8.h),
                  if (problem != null)
                    Padding(
                      padding: EdgeInsets.only(top: 6.h),
                      child: Text(problem!, key: const ValueKey<String>('office_problem'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorText)),
                    ),
                  ElevatedButton(
                    key: const ValueKey<String>('office_save'),
                    onPressed: () {
                      // Said here, in the form, before anything is sent: a name (or a branch), and a place when the office must be near.
                      final bool hasPlace = double.tryParse(lat.text.trim()) != null && double.tryParse(lng.text.trim()) != null;
                      final String? why = branchId == null && name.text.trim().length < 2
                          ? (sw ? 'Andika jina la ofisi, au chagua tawi.' : 'Enter the office name, or choose a branch.')
                          : fence && !hasPlace
                              ? (sw ? 'Chukua mahali pa ofisi ili kuhitaji awe karibu nayo, au zima chaguo hilo.' : 'Capture the place of the office to require being near it, or switch that off.')
                              : null;
                      if (why != null) {
                        set(() => problem = why);
                        return;
                      }
                      Navigator.pop(sheet, true);
                    },
                    child: Text(sw ? 'Hifadhi' : 'Save'),
                  ),
                ],
              ),
            ),
          ],
          );
        },
      ),
    );
    if (saved != true || !mounted) return;
    await _do(() async {
      await _api.saveAttendanceOffice(
        id: office?.id,
        branchId: branchId,
        name: name.text.trim(),
        address: address.text.trim().isEmpty ? null : address.text.trim(),
        latitude: double.tryParse(lat.text.trim()),
        longitude: double.tryParse(lng.text.trim()),
        accuracy: lastAccuracy,
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

  /// The first eight characters of a device id: enough to tell two phones apart without a wall of letters.
  static String _shortId(final dynamic id) {
    final String s = id?.toString() ?? '';

    return s.isEmpty ? '—' : (s.length > 8 ? '${s.substring(0, 8)}…' : s);
  }

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
                        InvBadge(
                          label: c['flagged'] == true ? (sw ? 'Si kifaa alichoingia nacho' : 'Not the logged-in device') : (c['outcome']?.toString() ?? ''),
                          color: c['outcome'] == 'ok' ? ThemeConstants.successGreen : ThemeConstants.errorText,
                        ),
                      ],
                    ),
                    if (c['flagged'] == true) ...<Widget>[
                      // The audit line the administrator needs: the phone registered to this person against the one that was used.
                      Text(
                        '${sw ? 'Kilichosajiliwa' : 'Registered'}: ${_shortId(c['registered_device_uuid'])}  •  ${sw ? 'Kilichotumika' : 'Used'}: ${_shortId(c['presented_device_uuid'])}${(c['presented_device_name']?.toString() ?? '').isEmpty ? '' : ' (${c['presented_device_name']})'}',
                        key: ValueKey<String>('check_devices_${c['id']}'),
                        style: ThemeConstants.captionStyle,
                      ),
                      if (c['acknowledged'] != true)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: ValueKey<String>('check_ack_${c['id']}'),
                            onPressed: _busy ? null : () => _do(() => _api.acknowledgeCheck((c['id'] as num).toInt())),
                            child: Text(sw ? 'Nimeona' : 'Seen', style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                    ],
                    Text('${c['at'] ?? ''}${(c['ip']?.toString() ?? '').isEmpty ? '' : ' • ${c['ip']}'}${c['office_id'] == null ? '' : ' • #${c['office_id']}'}', style: ThemeConstants.captionStyle),
                    if ((c['place_status']?.toString() ?? '').isNotEmpty)
                      Text(
                        '${_placeLabel(sw, c['place_status'].toString())}${c['distance_m'] == null ? '' : ' • ${(c['distance_m'] as num).round()} m'}${c['mocked'] == true ? ' • ${sw ? 'eneo bandia' : 'fake location'}' : ''}',
                        key: ValueKey<String>('check_place_${c['id']}'),
                        style: ThemeConstants.captionStyle.copyWith(color: c['place_status'] == 'at_work' ? ThemeConstants.successGreen : ThemeConstants.warningAmber),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
