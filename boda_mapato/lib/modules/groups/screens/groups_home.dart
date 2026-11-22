import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/service_switcher_dialog.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'assets_screen.dart';
import 'community_screen.dart';
import 'contributions_screen.dart';
import 'group_dashboard_screen.dart';
import 'group_more_screen.dart';
import 'loans_screen.dart';
import 'members_screen.dart';
import 'payments_screen.dart';
import 'projects_screen.dart';
import 'welfare_screen.dart';

/// A section of the Groups service: shown only to whoever may open it (the server decides the rights; this only follows them).
class _Section {
  const _Section({required this.key, required this.icon, required this.label, required this.build});

  final String key;
  final IconData icon;
  /// The section's name in the language chosen.
  final String Function({required bool sw}) label;
  final Widget Function(GroupMe me, Future<void> Function() reload, void Function(String key) open) build;

  String title({required final bool sw}) => label(sw: sw);
}

/// The Groups (Vikundi) service: the same frame as the shop and the salon -- the header with the ⋮ menu, the page in the dark teal, the pill
/// footer -- holding the sections the signed-in person may open: Home (everyone), Members, Payments and More (by office).
class GroupsHome extends StatefulWidget {
  const GroupsHome({super.key, this.api});

  final GroupsApi? api;

  @override
  State<GroupsHome> createState() => _GroupsHomeState();
}

class _GroupsHomeState extends State<GroupsHome> {
  late final GroupsApi _api = widget.api ?? GroupsApi();
  GroupMe? _me;
  String? _error;
  String _current = 'home';

  /// The sections opened so far: only those are built (a section loads its data the first time it is opened, then keeps it).
  final Set<String> _opened = <String>{'home'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupMe me = await _api.me();
      if (!mounted) return;
      setState(() {
        _me = me;
        _error = null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = readableErrorMessage(e));
    }
  }

  List<_Section> _sections(final GroupMe me) => <_Section>[
        _Section(
          key: 'home',
          icon: Icons.dashboard_rounded,
          label: ({required final bool sw}) => sw ? 'Mwanzo' : 'Home',
          build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => GroupDashboardScreen(me: m, api: _api, onChanged: reload, onOpen: open),
        ),
        _Section(
          key: 'community',
          icon: Icons.forum_rounded,
          label: ({required final bool sw}) => sw ? 'Vikao' : 'Meetings',
          build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => CommunityScreen(me: m, api: _api, onChanged: reload),
        ),
        if (me.can('view_members'))
          _Section(
            key: 'members',
            icon: Icons.groups_rounded,
            label: ({required final bool sw}) => sw ? 'Wanachama' : 'Members',
            build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => MembersScreen(me: m, api: _api, onChanged: reload),
          ),
        if (me.seesContributions)
          _Section(
            key: 'contributions',
            icon: Icons.savings_rounded,
            label: ({required final bool sw}) => sw ? 'Michango' : 'Contributions',
            build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => ContributionsScreen(me: m, api: _api, onChanged: reload),
          ),
        if (me.can('view_loans'))
          _Section(
            key: 'loans',
            icon: Icons.request_quote_rounded,
            label: ({required final bool sw}) => sw ? 'Mikopo' : 'Loans',
            build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => LoansScreen(me: m, api: _api, onChanged: reload),
          ),
        if (me.can('view_benefits'))
          _Section(
            key: 'welfare',
            icon: Icons.volunteer_activism_rounded,
            label: ({required final bool sw}) => sw ? 'Msaada' : 'Welfare',
            build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => WelfareScreen(me: m, api: _api, onChanged: reload),
          ),
        if (me.member != null || me.can('view_projects'))
          _Section(
            key: 'projects',
            icon: Icons.business_center_rounded,
            label: ({required final bool sw}) => sw ? 'Miradi' : 'Projects',
            build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => ProjectsScreen(me: m, api: _api, onChanged: reload),
          ),
        if (me.keepsAssets || me.can('manage_assets'))
          _Section(
            key: 'assets',
            icon: Icons.chair_alt_rounded,
            label: ({required final bool sw}) => sw ? 'Mali' : 'Assets',
            build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => AssetsScreen(me: m, api: _api, onChanged: reload),
          ),
        if (me.seesPayments)
          _Section(
            key: 'payments',
            icon: Icons.account_balance_wallet_rounded,
            label: ({required final bool sw}) => sw ? 'Malipo' : 'Payments',
            build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => PaymentsScreen(me: m, api: _api, onChanged: reload),
          ),
        if (me.can('manage_settings') || me.can('view_audit') || me.can('view_members'))
          _Section(
            key: 'more',
            icon: Icons.tune_rounded,
            label: ({required final bool sw}) => sw ? 'Zaidi' : 'More',
            build: (GroupMe m, Future<void> Function() reload, void Function(String) open) => GroupMoreScreen(me: m, api: _api, onChanged: reload),
          ),
      ];

  void _open(final String key) => setState(() {
        _current = key;
        _opened.add(key);
      });

  Future<void> _logout() async {
    await Provider.of<AuthProvider>(context, listen: false).logout();
    if (mounted) await Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> r) => false);
  }

  Future<void> _showMenu(final List<_Section> sections, final bool sw) async {
    final String? picked = await showDialog<String>(
      context: context,
      builder: (final BuildContext ctx) => Dialog(
        key: const Key('grp_menu'),
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
        child: Container(
          decoration: BoxDecoration(
            color: ThemeConstants.primaryBlue.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: Colors.white24),
          ),
          padding: EdgeInsets.all(12.w),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 12.h,
            crossAxisSpacing: 12.w,
            childAspectRatio: 0.95,
            children: <Widget>[
              for (final _Section s in sections) _GridItem(icon: s.icon, label: s.title(sw: sw), color: ThemeConstants.invAccent, onTap: () => Navigator.pop(ctx, s.key)),
              _GridItem(
                icon: Icons.sync_alt,
                label: LocalizationService.instance.translate('switch_service'),
                color: ThemeConstants.primaryOrange,
                onTap: () => Navigator.pop(ctx, '__switch'),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == '__switch') {
      await showDialog<void>(context: context, builder: (_) => const ServiceSwitcherDialog());
      return;
    }
    _open(picked);
  }

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final bool sw = loc.isSwahili;
    final GroupMe? me = _me;
    final List<_Section> sections = me == null ? const <_Section>[] : _sections(me);
    final _Section? current = sections.where((_Section s) => s.key == _current).firstOrNull ?? sections.firstOrNull;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        current?.title(sw: sw) ?? (sw ? 'Vikundi' : 'Groups'),
        flat: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: 20.sp),
          tooltip: loc.translate('back'),
          onPressed: () {
            if (current != null && current.key != 'home') {
              _open('home');
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/select-service');
            }
          },
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            key: const Key('grp_more_menu'),
            icon: Icon(Icons.more_vert, size: 22.sp),
            tooltip: sw ? 'Zaidi' : 'More',
            onSelected: (final String v) {
              switch (v) {
                case 'menu':
                  _showMenu(sections, sw);
                case 'services':
                  Navigator.pushReplacementNamed(context, '/select-service');
                case 'language':
                  loc.changeLanguage(sw ? 'en' : 'sw');
                case 'logout':
                  _logout();
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'menu',
                child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.menu), title: Text(loc.translate('menu'))),
              ),
              PopupMenuItem<String>(
                value: 'services',
                child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.apps), title: Text(loc.translate('select_service'))),
              ),
              PopupMenuItem<String>(
                key: const Key('grp_menu_language'),
                value: 'language',
                child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.translate), title: Text(sw ? 'Switch to English' : 'Badili kuwa Kiswahili')),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.logout), title: Text(loc.translate('logout'))),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: me == null
            ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                        Text(_error!, key: const Key('grp_load_error'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: ThemeConstants.primaryOrange))),
                      ]),
                    ),
                  ))
            : IndexedStack(
                index: sections.indexOf(current!),
                children: <Widget>[
                  for (final _Section s in sections)
                    KeyedSubtree(
                      key: ValueKey<String>('grp_section_${s.key}'),
                      child: _opened.contains(s.key) || s.key == current.key ? s.build(me, _load, _open) : const SizedBox.shrink(),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: me == null
          ? null
          : _GroupsFooter(
              sections: sections,
              current: current?.key ?? 'home',
              sw: sw,
              onTap: _open,
              onMenu: () => _showMenu(sections, sw),
            ),
    );
  }
}

/// The pill footer of the shop and the salon, with the sections this person has and the menu in the middle.
class _GroupsFooter extends StatelessWidget {
  const _GroupsFooter({required this.sections, required this.current, required this.sw, required this.onTap, required this.onMenu});

  final List<_Section> sections;
  final String current;
  final bool sw;
  final ValueChanged<String> onTap;
  final VoidCallback onMenu;

  @override
  Widget build(final BuildContext context) {
    const List<String> priority = <String>['home', 'payments', 'loans', 'contributions', 'members', 'community', 'assets', 'welfare', 'projects', 'more'];
    final List<_Section> shown = (List<_Section>.of(sections)..sort((final _Section a, final _Section b) => priority.indexOf(a.key).compareTo(priority.indexOf(b.key))))
        .take(4)
        .toList();
    final List<Widget> buttons = <Widget>[
      for (final _Section s in shown)
        _FooterButton(key: Key('grp_footer_${s.key}'), selected: s.key == current, icon: s.icon, label: s.title(sw: sw), onTap: () => onTap(s.key)),
    ];
    buttons.insert(
      buttons.length >= 2 ? 2 : buttons.length,
      _FooterButton(key: const Key('grp_footer_menu'), selected: false, icon: Icons.grid_view_rounded, label: LocalizationService.instance.translate('menu'), onTap: onMenu),
    );
    return ColoredBox(
      color: ThemeConstants.footerBarColor,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(vertical: 8.h),
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: ThemeConstants.footerBarColor,
            borderRadius: BorderRadius.circular(28.r),
            boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(mainAxisAlignment: buttons.length > 2 ? MainAxisAlignment.spaceBetween : MainAxisAlignment.spaceEvenly, children: buttons),
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({required this.selected, required this.icon, required this.label, required this.onTap, super.key});

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final Color bg = ThemeConstants.primaryBlue.withValues(alpha: selected ? 0.35 : 0.22);
    return Flexible(
      child: InkResponse(
        onTap: onTap,
        radius: 28.r,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 64.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(width: 42.w, height: 42.w, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 21.sp)),
              SizedBox(height: 3.h),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: selected ? 1 : 0.85), fontSize: 10.sp, fontWeight: selected ? FontWeight.w800 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridItem extends StatelessWidget {
  const _GridItem({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Icon(icon, color: Colors.white, size: 24.sp),
            ),
            SizedBox(height: 4.h),
            Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle),
          ],
        ),
      );
}
