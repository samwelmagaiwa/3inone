import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../modules/inventory/screens/widgets/joined_sections.dart'
    show SectionGlowDivider;
import '../../utils/server_message.dart';
import '../settings/user_permissions_management_screen.dart';

/// The super admin's control of every account on the platform: find anyone, create, edit, change role and services, set access
/// rights, reset a password, switch off, delete, and place a staff member under a business admin. The server decides what is
/// allowed (and refuses a person removing their own super admin access); this screen only makes it easy and safe to ask.
class UsersControlScreen extends StatefulWidget {
  const UsersControlScreen({super.key, this.api});

  /// For tests: the server calls come from here instead of the network.
  final ApiService? api;

  @override
  State<UsersControlScreen> createState() => _UsersControlScreenState();
}

/// The roles the server knows, grouped by what the person is on the platform.
class _Roles {
  static const String superAdmin = 'super_admin';
  static const List<String> owners = <String>[
    'admin',
    'administrator',
    'landlord'
  ];
  static const List<String> outside = <String>['driver', 'tenant', 'vendor'];
  static const List<String> all = <String>[
    'super_admin',
    'admin',
    'landlord',
    'manager',
    'accountant',
    'sales_officer',
    'operator',
    'hair_stylist',
    'nail_technician',
    'lash_makeup_artist',
    'caretaker',
    'driver',
    'tenant',
    'viewer',
  ];

  /// The services a role works in. Roles missing here (the owners, manager, viewer) fit any service.
  static const Map<String, List<String>> servicesOf = <String, List<String>>{
    'sales_officer': <String>['inventory'],
    'operator': <String>['inventory'],
    'accountant': <String>['inventory', 'salon'],
    'hair_stylist': <String>['salon'],
    'nail_technician': <String>['salon'],
    'lash_makeup_artist': <String>['salon'],
    'driver': <String>['transport'],
    'landlord': <String>['rental'],
    'caretaker': <String>['rental'],
    'tenant': <String>['rental'],
  };

  /// The roles that make sense for the services ticked: those of a ticked service, and the ones that fit every service.
  static List<String> forServices(final Set<String> services) => <String>[
        for (final String r in all)
          if (r == superAdmin ||
              !servicesOf.containsKey(r) ||
              servicesOf[r]!.any(services.contains))
            r,
      ];

  static bool isOwner(final String role) => owners.contains(role);
  static bool isStaff(final String role) =>
      role != superAdmin && !isOwner(role) && !outside.contains(role);

  static String label(final String role, final bool sw) => switch (role) {
        'super_admin' => 'Super Admin',
        'admin' ||
        'administrator' =>
          sw ? 'Msimamizi wa biashara' : 'Business admin',
        'landlord' => sw ? 'Mwenye nyumba' : 'Landlord',
        'manager' => sw ? 'Meneja' : 'Manager',
        'accountant' => sw ? 'Mhasibu' : 'Accountant',
        'sales_officer' => sw ? 'Afisa mauzo' : 'Sales officer',
        'operator' => sw ? 'Mwendeshaji' : 'Operator',
        'hair_stylist' => sw ? 'Mfanyakazi wa nywele' : 'Hair stylist',
        'nail_technician' => sw ? 'Fundi wa kucha' : 'Nail technician',
        'lash_makeup_artist' =>
          sw ? 'Mpambaji wa kope na uso' : 'Lash & makeup artist',
        'caretaker' => sw ? 'Mlinzi wa nyumba' : 'Caretaker',
        'driver' => sw ? 'Dereva' : 'Driver',
        'tenant' => sw ? 'Mpangaji' : 'Tenant',
        'vendor' => sw ? 'Muuzaji' : 'Vendor',
        'viewer' => sw ? 'Mtazamaji' : 'Viewer',
        _ => role,
      };

  static Color color(final String role) {
    if (role == superAdmin) return const Color(0xFFF59E0B);
    if (isOwner(role)) return const Color(0xFF8B5CF6);
    if (outside.contains(role)) return const Color(0xFF64748B);

    return ThemeConstants.invAccent;
  }
}

const List<String> _services = <String>[
  'inventory',
  'salon',
  'transport',
  'rental'
];

enum _RoleFilter { all, superAdmins, owners, staff }

enum _StatusFilter { all, active, off }

class _UsersControlScreenState extends State<UsersControlScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  final TextEditingController _search = TextEditingController();

  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  _RoleFilter _roleFilter = _RoleFilter.all;
  _StatusFilter _statusFilter = _StatusFilter.all;
  String? _serviceFilter;

  bool get _sw => LocalizationService.instance.isSwahili;
  String get _myId =>
      Provider.of<AuthProvider>(context, listen: false).user?.id.toString() ??
      '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ data

  String _id(final Map<String, dynamic> u) =>
      '${u['id'] ?? u['user_id'] ?? ''}';
  String _role(final Map<String, dynamic> u) =>
      '${u['role'] ?? ''}'.toLowerCase();
  bool _isActive(final Map<String, dynamic> u) =>
      u['is_active'] == true || u['is_active'] == 1;
  List<String> _servicesOf(final Map<String, dynamic> u) => <String>[
        if (u['service_types'] is List)
          for (final dynamic s in u['service_types'] as List) '$s'
      ];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> res = await _api.getUsers(limit: 500);
      final dynamic data = res['data'];
      final dynamic raw = data is Map ? data['users'] : (res['users'] ?? data);
      if (!mounted) return;
      setState(() => _users = <Map<String, dynamic>>[
            if (raw is List)
              for (final dynamic e in raw)
                if (e is Map) Map<String, dynamic>.from(e)
          ]);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Runs a server action, then reloads and says what happened (or why it was refused).
  Future<void> _run(final Future<Map<String, dynamic>> Function() action,
      final String done) async {
    try {
      await action();
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, done);
      await _load();
    } on Exception catch (e) {
      if (mounted)
        ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  List<Map<String, dynamic>> get _shown {
    final String q = _search.text.trim().toLowerCase();

    return _users.where((Map<String, dynamic> u) {
      final String role = _role(u);
      final bool roleOk = switch (_roleFilter) {
        _RoleFilter.all => true,
        _RoleFilter.superAdmins => role == _Roles.superAdmin,
        _RoleFilter.owners => _Roles.isOwner(role),
        _RoleFilter.staff => !_Roles.isOwner(role) && role != _Roles.superAdmin,
      };
      final bool statusOk = switch (_statusFilter) {
        _StatusFilter.all => true,
        _StatusFilter.active => _isActive(u),
        _StatusFilter.off => !_isActive(u),
      };
      final bool serviceOk =
          _serviceFilter == null || _servicesOf(u).contains(_serviceFilter);
      final bool textOk = q.isEmpty ||
          '${u['name']} ${u['email']} ${u['phone_number']}'
              .toLowerCase()
              .contains(q);

      return roleOk && statusOk && serviceOk && textOk;
    }).toList();
  }

  List<Map<String, dynamic>> get _admins => _users
      .where(
          (Map<String, dynamic> u) => _Roles.isOwner(_role(u)) && _isActive(u))
      .toList();

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: ThemeConstants.bgTop,
        foregroundColor: Colors.white,
        title: Text((_sw ? 'Watumiaji na ruhusa' : 'Users & access'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: <Widget>[
          IconButton(
              key: const Key('uc_refresh'),
              tooltip: (_sw ? 'Onyesha upya' : 'Refresh'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load)
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('uc_add'),
        backgroundColor: ThemeConstants.primaryOrange,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text((_sw ? 'Ongeza mtumiaji' : 'Add user'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: <Widget>[
        _stats(),
        const SizedBox(height: 12),
        const SectionGlowDivider(lift: false),
        _searchBox(),
        _filters(),
        const SectionGlowDivider(lift: false),
        const SizedBox(height: 4),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _stats() {
    final int active = _users.where(_isActive).length;
    final int owners = _users
        .where((Map<String, dynamic> u) => _Roles.isOwner(_role(u)))
        .length;
    final int supers = _users
        .where((Map<String, dynamic> u) => _role(u) == _Roles.superAdmin)
        .length;
    Widget tile(final String key, final String label, final int n,
            final IconData icon, final Color color) =>
        Expanded(
          child: Container(
            key: Key(key),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12)),
            child: Row(children: <Widget>[
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('$n',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 17)),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 10.5)),
                    ]),
              ),
            ]),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(children: <Widget>[
        tile('uc_stat_total', (_sw ? 'Watumiaji' : 'Users'), _users.length,
            Icons.groups_rounded, ThemeConstants.invAccent),
        const SizedBox(width: 8),
        tile('uc_stat_active', (_sw ? 'Hai' : 'Active'), active,
            Icons.verified_rounded, ThemeConstants.successGreen),
        const SizedBox(width: 8),
        tile('uc_stat_owners', (_sw ? 'Wasimamizi' : 'Admins'), owners,
            Icons.storefront_rounded, const Color(0xFF8B5CF6)),
        const SizedBox(width: 8),
        tile('uc_stat_super', 'Super', supers, Icons.shield_rounded,
            const Color(0xFFF59E0B)),
      ]),
    );
  }

  Widget _searchBox() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: TextField(
          key: const Key('uc_search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: (_sw
                ? 'Tafuta jina, barua pepe au simu'
                : 'Search name, email or phone'),
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon:
                        const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => setState(_search.clear)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _chip(final String key, final String label, final bool selected,
          final VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Builder(
          builder: (BuildContext chipContext) => ChoiceChip(
            key: Key(key),
            label: Text(label),
            selected: selected,
            onSelected: (_) {
              onTap();
              // After the list is redrawn, centre this chip: the hidden ones on either side come into view.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (chipContext.mounted)
                  Scrollable.ensureVisible(chipContext,
                      alignment: 0.5,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut);
              });
            },
            labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 12.5),
            selectedColor: ThemeConstants.invAccent.withValues(alpha: 0.55),
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            side: BorderSide(
                color: selected ? ThemeConstants.invAccent : Colors.white12),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),
        ),
      );

  Widget _filters() => SizedBox(
        height: 46,
        child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 4),
            children: <Widget>[
              _chip(
                  'uc_role_all',
                  (_sw ? 'Wote' : 'Everyone'),
                  _roleFilter == _RoleFilter.all,
                  () => setState(() => _roleFilter = _RoleFilter.all)),
              _chip(
                  'uc_role_super',
                  'Super Admin',
                  _roleFilter == _RoleFilter.superAdmins,
                  () => setState(() => _roleFilter = _RoleFilter.superAdmins)),
              _chip(
                  'uc_role_owners',
                  (_sw ? 'Wasimamizi' : 'Admins'),
                  _roleFilter == _RoleFilter.owners,
                  () => setState(() => _roleFilter = _RoleFilter.owners)),
              _chip(
                  'uc_role_staff',
                  (_sw ? 'Wafanyakazi' : 'Staff'),
                  _roleFilter == _RoleFilter.staff,
                  () => setState(() => _roleFilter = _RoleFilter.staff)),
              const SizedBox(width: 6),
              _chip(
                  'uc_status_off',
                  (_sw ? 'Waliozimwa' : 'Switched off'),
                  _statusFilter == _StatusFilter.off,
                  () => setState(() => _statusFilter =
                      _statusFilter == _StatusFilter.off
                          ? _StatusFilter.all
                          : _StatusFilter.off)),
              const SizedBox(width: 6),
              for (final String s in _services)
                _chip(
                    'uc_svc_$s',
                    _serviceName(s),
                    _serviceFilter == s,
                    () => setState(
                        () => _serviceFilter = _serviceFilter == s ? null : s)),
            ]),
      );

  String _serviceName(final String s) => switch (s) {
        'inventory' => (_sw ? 'Bidhaa' : 'Inventory'),
        'salon' => (_sw ? 'Saluni' : 'Salon'),
        'transport' => (_sw ? 'Usafiri' : 'Transport'),
        'rental' => (_sw ? 'Upangishaji' : 'Rental'),
        _ => s,
      };

  Widget _body() {
    if (_loading && _users.isEmpty)
      return const Center(child: CircularProgressIndicator());
    if (_error != null && _users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _load,
                child: Text((_sw ? 'Jaribu tena' : 'Try again'))),
          ]),
        ),
      );
    }
    final List<Map<String, dynamic>> shown = _shown;
    if (shown.isEmpty) {
      return Center(
          child: Text((_sw ? 'Hakuna anayelingana.' : 'No one matches.'),
              key: const Key('uc_empty'),
              style: const TextStyle(color: Colors.white60)));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, int i) => _card(shown[i]),
      ),
    );
  }

  Widget _card(final Map<String, dynamic> u) {
    final String name = '${u['name'] ?? ''}';
    final String role = _role(u);
    final bool active = _isActive(u);
    final Color color = _Roles.color(role);
    final List<String> svcs = _servicesOf(u);

    return Material(
      key: Key('uc_user_${_id(u)}'),
      color: Colors.white.withValues(alpha: active ? 0.08 : 0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _actions(u),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: color.withValues(alpha: active ? 0.45 : 0.15))),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withValues(alpha: 0.25),
                  child: Text(name.isEmpty ? '?' : name.trim()[0].toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(children: <Widget>[
                          Flexible(
                              child: Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: active
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15))),
                          if (_id(u) == _myId)
                            Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text((_sw ? '(wewe)' : '(you)'),
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11))),
                        ]),
                        const SizedBox(height: 2),
                        Text('${u['email'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                        if ('${u['phone_number'] ?? ''}'.isNotEmpty)
                          Text('${u['phone_number']}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11.5)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                          _pill(_Roles.label(role, _sw), color),
                          for (final String s in svcs)
                            _pill(_serviceName(s), Colors.white54),
                          if (u['full_access'] == true || u['full_access'] == 1)
                            _pill((_sw ? 'Ufikiaji kamili' : 'Full access'),
                                const Color(0xFFF59E0B)),
                          if (!active)
                            _pill((_sw ? 'Amezimwa' : 'Switched off'),
                                ThemeConstants.errorRed),
                        ]),
                      ]),
                ),
                Icon(Icons.more_vert_rounded,
                    color: Colors.white.withValues(alpha: 0.5)),
              ]),
        ),
      ),
    );
  }

  Widget _pill(final String text, final Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  // ------------------------------------------------------------------ one person's actions

  Future<void> _actions(final Map<String, dynamic> u) async {
    final bool me = _id(u) == _myId;
    final String role = _role(u);
    final bool active = _isActive(u);
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ThemeConstants.bgMid,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (BuildContext ctx) {
        Widget item(final String key, final IconData icon, final String label,
                {final String? hint,
                final Color color = Colors.white,
                final bool enabled = true}) =>
            ListTile(
              key: Key('uc_act_$key'),
              enabled: enabled,
              leading: Icon(icon, color: enabled ? color : Colors.white24),
              title: Text(label,
                  style: TextStyle(
                      color: enabled ? color : Colors.white30,
                      fontWeight: FontWeight.w600)),
              subtitle: hint == null
                  ? null
                  : Text(hint,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () => Navigator.pop(ctx, key),
            );

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4))),
              ListTile(
                leading: CircleAvatar(
                    backgroundColor: _Roles.color(role).withValues(alpha: 0.25),
                    child: Text(
                        '${u['name']}'.isEmpty
                            ? '?'
                            : '${u['name']}'.trim()[0].toUpperCase(),
                        style: TextStyle(
                            color: _Roles.color(role),
                            fontWeight: FontWeight.w800))),
                title: Text('${u['name']}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                subtitle: Text(
                    '${_Roles.label(role, _sw)}  ·  ${u['email'] ?? ''}',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
              const SectionGlowDivider(lift: false),
              item('edit', Icons.edit_rounded,
                  (_sw ? 'Hariri taarifa' : 'Edit details')),
              const SectionGlowDivider(lift: false),
              item('role', Icons.manage_accounts_rounded,
                  (_sw ? 'Badilisha wadhifa' : 'Change role'),
                  enabled: !me,
                  hint: me
                      ? (_sw
                          ? 'Huwezi kubadilisha wadhifa wako mwenyewe'
                          : 'You cannot change your own role')
                      : null),
              const SectionGlowDivider(lift: false),
              item('services', Icons.apps_rounded,
                  (_sw ? 'Huduma' : 'Services')),
              const SectionGlowDivider(lift: false),
              item('rights', Icons.security_rounded,
                  (_sw ? 'Ruhusa za kufikia' : 'Access rights'),
                  hint: (_sw
                      ? 'Anachoruhusiwa kufungua na kufanya'
                      : 'What this person may open and do')),
              const SectionGlowDivider(lift: false),
              if (_Roles.isStaff(role))
                item('place', Icons.supervisor_account_rounded,
                    (_sw ? 'Weka chini ya admin' : 'Place under an admin'),
                    color: Colors.amberAccent,
                    hint: (_sw
                        ? 'Anajiunga na biashara ya admin huyo'
                        : "They join that admin's business")),
              const SectionGlowDivider(lift: false),
              item('password', Icons.lock_reset_rounded,
                  (_sw ? 'Weka nywila mpya' : 'Reset password')),
              const SectionGlowDivider(lift: false),
              item(
                  'toggle',
                  active ? Icons.block_rounded : Icons.check_circle_rounded,
                  active
                      ? (_sw ? 'Zima akaunti' : 'Switch off')
                      : (_sw ? 'Washa akaunti' : 'Switch on'),
                  enabled: !(me && active)),
              const SectionGlowDivider(lift: false),
              item('delete', Icons.delete_forever_rounded,
                  (_sw ? 'Futa' : 'Delete'),
                  color: ThemeConstants.errorRed, enabled: !me),
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'edit':
        return _edit(u);
      case 'role':
        return _changeRole(u);
      case 'services':
        return _editServices(u);
      case 'rights':
        return _rights(u);
      case 'place':
        return _placeUnderAdmin(u);
      case 'password':
        return _resetPassword(u);
      case 'toggle':
        return _toggleActive(u, active);
      case 'delete':
        return _delete(u);
    }
  }

  // ------------------------------------------------------------------ the dialogs

  /// A closed dialog is still on screen while it fades out: its text boxes are released only after that.
  void _disposeLater(final List<TextEditingController> controllers) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      for (final TextEditingController c in controllers) {
        c.dispose();
      }
    });
  }

  Future<bool> _confirm(final String title, final String message,
      {final String yes = 'OK', final bool danger = false}) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        key: const Key('uc_confirm'),
        backgroundColor: ThemeConstants.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text((_sw ? 'Ghairi' : 'Cancel'),
                  style: const TextStyle(color: Colors.white60))),
          TextButton(
              key: const Key('uc_confirm_yes'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(yes,
                  style: TextStyle(
                      color: danger
                          ? ThemeConstants.errorRed
                          : ThemeConstants.primaryOrange,
                      fontWeight: FontWeight.w800))),
        ],
      ),
    );

    return ok == true;
  }

  InputDecoration _field(final String label, {final IconData? icon}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white60),
        prefixIcon:
            icon == null ? null : Icon(icon, color: Colors.white54, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      );

  Future<void> _edit(final Map<String, dynamic> u) async {
    final TextEditingController name =
        TextEditingController(text: '${u['name'] ?? ''}');
    final TextEditingController email =
        TextEditingController(text: '${u['email'] ?? ''}');
    final TextEditingController phone =
        TextEditingController(text: '${u['phone_number'] ?? ''}');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text((_sw ? 'Hariri taarifa' : 'Edit details'),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(
                key: const Key('uc_edit_name'),
                controller: name,
                style: const TextStyle(color: Colors.white),
                decoration: _field((_sw ? 'Jina kamili' : 'Full name'),
                    icon: Icons.person_rounded)),
            const SizedBox(height: 10),
            TextField(
                key: const Key('uc_edit_email'),
                controller: email,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _field((_sw ? 'Barua pepe' : 'Email'),
                    icon: Icons.email_rounded)),
            const SizedBox(height: 10),
            TextField(
                key: const Key('uc_edit_phone'),
                controller: phone,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: _field((_sw ? 'Simu' : 'Phone'),
                    icon: Icons.phone_rounded)),
          ]),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text((_sw ? 'Ghairi' : 'Cancel'),
                  style: const TextStyle(color: Colors.white60))),
          TextButton(
              key: const Key('uc_edit_save'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text((_sw ? 'Hifadhi' : 'Save'),
                  style: const TextStyle(
                      color: ThemeConstants.primaryOrange,
                      fontWeight: FontWeight.w800))),
        ],
      ),
    );
    final Map<String, dynamic> body = <String, dynamic>{
      'name': name.text.trim(),
      'email': email.text.trim(),
      'phone_number': phone.text.trim()
    };
    _disposeLater(<TextEditingController>[name, email, phone]);
    if (ok != true || '${body['name']}'.isEmpty || '${body['email']}'.isEmpty)
      return;
    await _run(() => _api.updateUser(_id(u), body),
        (_sw ? 'Taarifa zimehifadhiwa' : 'Details saved'));
  }

  Future<void> _changeRole(final Map<String, dynamic> u) async {
    String role = _role(u);
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setDialog) =>
            AlertDialog(
          backgroundColor: ThemeConstants.bgMid,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text((_sw ? 'Badilisha wadhifa' : 'Change role'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                for (final String r in _Roles.all)
                  RadioListTile<String>(
                    key: Key('uc_role_$r'),
                    dense: true,
                    value: r,
                    groupValue: role,
                    activeColor: ThemeConstants.primaryOrange,
                    title: Text(_Roles.label(r, _sw),
                        style: TextStyle(
                            color: _Roles.color(r),
                            fontWeight: FontWeight.w600)),
                    onChanged: (String? v) => setDialog(() => role = v ?? role),
                  ),
              ]),
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text((_sw ? 'Ghairi' : 'Cancel'),
                    style: const TextStyle(color: Colors.white60))),
            TextButton(
                key: const Key('uc_role_save'),
                onPressed: () => Navigator.pop(ctx, role),
                child: Text((_sw ? 'Hifadhi' : 'Save'),
                    style: const TextStyle(
                        color: ThemeConstants.primaryOrange,
                        fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (picked == null || picked == _role(u)) return;
    if (picked == _Roles.superAdmin &&
        !await _confirmSuperAdmin('${u['name']}')) return;
    await _run(() => _api.updateUser(_id(u), <String, dynamic>{'role': picked}),
        (_sw ? 'Wadhifa umebadilishwa' : 'Role changed'));
  }

  Future<bool> _confirmSuperAdmin(final String name) => _confirm(
        (_sw ? 'Kumfanya $name Super Admin?' : 'Make $name a Super Admin?'),
        (_sw
            ? 'Mtu huyu atakuwa na ufikiaji kamili wa kila kitu: biashara zote, watumiaji, malipo na mipangilio ya jukwaa.'
            : 'This person will have full access to everything: every business, user, payment and platform setting.'),
        yes: (_sw ? 'Ndiyo, mfanye Super Admin' : 'Yes, make Super Admin'),
        danger: true,
      );

  Future<void> _editServices(final Map<String, dynamic> u) async {
    final Set<String> chosen = _servicesOf(u).toSet();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setDialog) =>
            AlertDialog(
          backgroundColor: ThemeConstants.bgMid,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text((_sw ? 'Huduma' : 'Services'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                    (_sw
                        ? 'Huduma ambazo mtu huyu anaweza kufungua.'
                        : 'The services this person can open.'),
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  for (final String s in _services)
                    FilterChip(
                      key: Key('uc_svcpick_$s'),
                      label: Text(_serviceName(s)),
                      selected: chosen.contains(s),
                      showCheckmark: false,
                      selectedColor:
                          ThemeConstants.invAccent.withValues(alpha: 0.55),
                      backgroundColor: Colors.white.withValues(alpha: 0.07),
                      labelStyle: const TextStyle(color: Colors.white),
                      onSelected: (bool on) => setDialog(
                          () => on ? chosen.add(s) : chosen.remove(s)),
                    ),
                ]),
              ]),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text((_sw ? 'Ghairi' : 'Cancel'),
                    style: const TextStyle(color: Colors.white60))),
            TextButton(
                key: const Key('uc_svc_save'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text((_sw ? 'Hifadhi' : 'Save'),
                    style: const TextStyle(
                        color: ThemeConstants.primaryOrange,
                        fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
        () => _api.updateUser(
            _id(u), <String, dynamic>{'service_types': chosen.toList()}),
        (_sw ? 'Huduma zimesasishwa' : 'Services updated'));
  }

  Future<void> _rights(final Map<String, dynamic> u) async {
    final List<String> svcs = _servicesOf(u);
    final String service = svcs.isNotEmpty ? svcs.first : 'inventory';
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => UserPermissionsManagementScreen(
                user: u, serviceType: service)));
    if (mounted) await _load();
  }

  Future<void> _placeUnderAdmin(final Map<String, dynamic> u) async {
    final List<Map<String, dynamic>> admins = _admins;
    if (admins.isEmpty) {
      ThemeConstants.showErrorSnackBar(context,
          (_sw ? 'Hakuna admin wa biashara.' : 'There is no business admin.'));
      return;
    }
    String? adminId;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setDialog) =>
            AlertDialog(
          backgroundColor: ThemeConstants.bgMid,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
              (_sw
                  ? 'Weka ${u['name']} chini ya admin'
                  : 'Place ${u['name']} under an admin'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      (_sw
                          ? 'Atafanya kazi kwenye biashara ya admin utakayemchagua na ataona data zake tu. Ataingia tena ili kuona mabadiliko.'
                          : 'They will work in the chosen admin\'s business and see only its data. They sign in again to see the change.'),
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    for (final Map<String, dynamic> a in admins)
                      RadioListTile<String>(
                        key: Key('uc_admin_${_id(a)}'),
                        dense: true,
                        value: _id(a),
                        groupValue: adminId,
                        activeColor: ThemeConstants.primaryOrange,
                        title: Text('${a['name']}',
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text('${a['email'] ?? ''}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        onChanged: (String? v) => setDialog(() => adminId = v),
                      ),
                  ]),
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text((_sw ? 'Ghairi' : 'Cancel'),
                    style: const TextStyle(color: Colors.white60))),
            TextButton(
                key: const Key('uc_place_save'),
                onPressed:
                    adminId == null ? null : () => Navigator.pop(ctx, true),
                child: Text((_sw ? 'Weka' : 'Place'),
                    style: const TextStyle(
                        color: ThemeConstants.primaryOrange,
                        fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (ok != true || adminId == null) return;
    await _run(() => _api.assignUserToAdmin(userId: _id(u), adminId: adminId!),
        (_sw ? 'Amewekwa chini ya admin' : 'Placed under the admin'));
  }

  Future<void> _resetPassword(final Map<String, dynamic> u) async {
    final TextEditingController password = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text((_sw ? 'Weka nywila mpya' : 'Reset password'),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                  (_sw
                      ? '${u['name']} atachagua nywila yake mwenyewe atakapoingia tena.'
                      : '${u['name']} must choose their own password at the next sign-in.'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                  key: const Key('uc_pw'),
                  controller: password,
                  style: const TextStyle(color: Colors.white),
                  decoration: _field(
                      (_sw
                          ? 'Nywila mpya (herufi 8 au zaidi)'
                          : 'New password (8 or more characters)'),
                      icon: Icons.lock_rounded)),
            ]),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text((_sw ? 'Ghairi' : 'Cancel'),
                  style: const TextStyle(color: Colors.white60))),
          TextButton(
              key: const Key('uc_pw_save'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text((_sw ? 'Weka' : 'Reset'),
                  style: const TextStyle(
                      color: ThemeConstants.primaryOrange,
                      fontWeight: FontWeight.w800))),
        ],
      ),
    );
    final String value = password.text.trim();
    _disposeLater(<TextEditingController>[password]);
    if (ok != true) return;
    if (!mounted) return;
    if (value.length < 8) {
      ThemeConstants.showErrorSnackBar(context,
          (_sw ? 'Tumia angalau herufi 8.' : 'Use at least 8 characters.'));
      return;
    }
    await _run(() => _api.resetUserPassword(userId: _id(u), newPassword: value),
        (_sw ? 'Nywila imewekwa' : 'Password reset'));
  }

  Future<void> _toggleActive(
      final Map<String, dynamic> u, final bool active) async {
    final bool sure = await _confirm(
      active
          ? (_sw
              ? 'Kuzima akaunti ya ${u['name']}?'
              : 'Switch off ${u['name']}?')
          : (_sw
              ? 'Kuwasha akaunti ya ${u['name']}?'
              : 'Switch on ${u['name']}?'),
      active
          ? (_sw
              ? 'Mtu huyu hataweza kuingia hadi uiwashe tena. Hakuna kinachofutwa.'
              : 'This person cannot sign in until you switch it on again. Nothing is deleted.')
          : (_sw
              ? 'Mtu huyu ataweza kuingia tena.'
              : 'This person will be able to sign in again.'),
      yes: active
          ? (_sw ? 'Zima' : 'Switch off')
          : (_sw ? 'Washa' : 'Switch on'),
      danger: active,
    );
    if (!sure) return;
    await _run(
        () => _api.updateUser(_id(u), <String, dynamic>{'is_active': !active}),
        active
            ? (_sw ? 'Akaunti imezimwa' : 'Account switched off')
            : (_sw ? 'Akaunti imewashwa' : 'Account switched on'));
  }

  Future<void> _delete(final Map<String, dynamic> u) async {
    final bool sure = await _confirm(
      (_sw ? 'Kufuta ${u['name']}?' : 'Delete ${u['name']}?'),
      (_sw
          ? 'Akaunti inaondolewa na mtu huyu hataweza kuingia tena. Hili haliwezi kurudishwa.'
          : 'The account is removed and the person can no longer sign in. This cannot be undone.'),
      yes: (_sw ? 'Futa' : 'Delete'),
      danger: true,
    );
    if (!sure) return;
    await _run(() => _api.deleteUser(_id(u)),
        (_sw ? 'Mtumiaji amefutwa' : 'User deleted'));
  }

  // ------------------------------------------------------------------ create

  Future<void> _create() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController email = TextEditingController();
    final TextEditingController phone = TextEditingController();
    final TextEditingController password = TextEditingController();
    String role = 'manager';
    final Set<String> services = <String>{'inventory'};
    String? businessId;
    String? error;
    final List<Map<String, dynamic>> admins = _admins;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) setDialog) {
          final bool staff = _Roles.isStaff(role);
          final List<String> roles = _Roles.forServices(services);

          return AlertDialog(
            backgroundColor: ThemeConstants.bgMid,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text((_sw ? 'Ongeza mtumiaji' : 'Add user'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            content: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                          key: const Key('uc_new_name'),
                          controller: name,
                          style: const TextStyle(color: Colors.white),
                          decoration: _field(
                              (_sw ? 'Jina kamili' : 'Full name'),
                              icon: Icons.person_rounded)),
                      const SizedBox(height: 10),
                      TextField(
                          key: const Key('uc_new_email'),
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: _field((_sw ? 'Barua pepe' : 'Email'),
                              icon: Icons.email_rounded)),
                      const SizedBox(height: 10),
                      TextField(
                          key: const Key('uc_new_phone'),
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white),
                          decoration: _field((_sw ? 'Simu' : 'Phone'),
                              icon: Icons.phone_rounded)),
                      const SizedBox(height: 10),
                      TextField(
                          key: const Key('uc_new_password'),
                          controller: password,
                          style: const TextStyle(color: Colors.white),
                          decoration: _field(
                              (_sw
                                  ? 'Nywila (herufi 8 au zaidi)'
                                  : 'Password (8 or more characters)'),
                              icon: Icons.lock_rounded)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: Key('uc_new_role_${roles.length}'),
                        initialValue: role,
                        isExpanded: true,
                        dropdownColor: ThemeConstants.bgMid,
                        style: const TextStyle(color: Colors.white),
                        decoration: _field((_sw ? 'Wadhifa' : 'Role'),
                            icon: Icons.verified_user_rounded),
                        items: <DropdownMenuItem<String>>[
                          for (final String r in roles)
                            DropdownMenuItem<String>(
                                value: r,
                                child: Text(_Roles.label(r, _sw),
                                    style: TextStyle(color: _Roles.color(r))))
                        ],
                        onChanged: (String? v) =>
                            setDialog(() => role = v ?? role),
                      ),
                      if (role != _Roles.superAdmin) ...<Widget>[
                        const SizedBox(height: 12),
                        Text((_sw ? 'Huduma' : 'Services'),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                          for (final String s in _services)
                            FilterChip(
                              key: Key('uc_newsvc_$s'),
                              label: Text(_serviceName(s)),
                              selected: services.contains(s),
                              showCheckmark: false,
                              selectedColor: ThemeConstants.invAccent
                                  .withValues(alpha: 0.55),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.07),
                              labelStyle: const TextStyle(color: Colors.white),
                              onSelected: (bool on) => setDialog(() {
                                on ? services.add(s) : services.remove(s);
                                // A role that no longer fits the ticked services gives way to the one that fits all of them.
                                if (!_Roles.forServices(services)
                                    .contains(role)) role = 'manager';
                              }),
                            ),
                        ]),
                      ],
                      if (staff && admins.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          key: const Key('uc_new_business'),
                          initialValue: businessId,
                          isExpanded: true,
                          dropdownColor: ThemeConstants.bgMid,
                          style: const TextStyle(color: Colors.white),
                          decoration: _field(
                              (_sw
                                  ? 'Anafanya kazi kwenye biashara ya'
                                  : 'Works in the business of'),
                              icon: Icons.storefront_rounded),
                          items: <DropdownMenuItem<String?>>[
                            DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                    (_sw
                                        ? 'Bado hana biashara'
                                        : 'No business yet'),
                                    style: const TextStyle(
                                        color: Colors.white60))),
                            for (final Map<String, dynamic> a in admins)
                              DropdownMenuItem<String?>(
                                  value: _id(a),
                                  child: Text('${a['name']}',
                                      overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (String? v) =>
                              setDialog(() => businessId = v),
                        ),
                      ],
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(error!,
                                key: const Key('uc_new_error'),
                                style: const TextStyle(
                                    color: ThemeConstants.errorText,
                                    fontSize: 12))),
                    ]),
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text((_sw ? 'Ghairi' : 'Cancel'),
                      style: const TextStyle(color: Colors.white60))),
              TextButton(
                key: const Key('uc_new_save'),
                onPressed: () {
                  final String? problem = _validateNew(name.text, email.text,
                      phone.text, password.text, role, services);
                  if (problem != null) {
                    setDialog(() => error = problem);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text((_sw ? 'Unda' : 'Create'),
                    style: const TextStyle(
                        color: ThemeConstants.primaryOrange,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      ),
    );

    final Map<String, dynamic> body = <String, dynamic>{
      'name': name.text.trim(),
      'email': email.text.trim(),
      'phone_number': phone.text.trim(),
      'password': password.text,
      'password_confirmation': password.text,
      'role': role,
      'is_active': true,
      if (role != _Roles.superAdmin) 'service_types': services.toList(),
      if (businessId != null && _Roles.isStaff(role))
        'business_owner_id': businessId,
    };
    _disposeLater(<TextEditingController>[name, email, phone, password]);
    if (ok != true) return;
    if (role == _Roles.superAdmin &&
        !await _confirmSuperAdmin('${body['name']}')) return;
    await _run(() => _api.createUser(body),
        (_sw ? 'Mtumiaji ameundwa' : 'User created'));
  }

  String? _validateNew(
      final String name,
      final String email,
      final String phone,
      final String password,
      final String role,
      final Set<String> services) {
    if (name.trim().length < 2)
      return (_sw ? 'Andika jina kamili.' : 'Write the full name.');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim()))
      return (_sw ? 'Andika barua pepe sahihi.' : 'Write a valid email.');
    if (phone.trim().length < 9)
      return (_sw ? 'Andika namba ya simu.' : 'Write the phone number.');
    if (password.length < 8)
      return (_sw
          ? 'Nywila iwe na herufi 8 au zaidi.'
          : 'The password needs 8 or more characters.');
    if (role != _Roles.superAdmin && !_Roles.isOwner(role) && services.isEmpty)
      return (_sw
          ? 'Chagua angalau huduma moja.'
          : 'Choose at least one service.');

    return null;
  }
}
