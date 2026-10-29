// ignore_for_file: cascade_invocations
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../models/user_permissions.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/localization_service.dart';
import '../../../widgets/service_switcher_dialog.dart';
import 'dashboard/inventory_dashboard_screen.dart';
import 'credit/credit_screen.dart';
import 'assistant/assistant_screen.dart';
import 'money/money_menu_screen.dart';
import '../../../screens/settings/settings_screen.dart';
import 'settings/depot_settings_screen.dart';
import 'hubs/products_hub_screen.dart';
import 'hubs/stock_hub_screen.dart';
import 'hubs/sales_hub_screen.dart';
import 'hubs/supply_chain_hub_screen.dart';
import 'hubs/finance_reports_hub_screen.dart';
import 'notifications/approval_notifications_screen.dart';
import 'reports/profit_by_product_screen.dart';
import 'hubs/salon_finance_hub_screen.dart';
import 'salon/branch_stock_screen.dart';
import 'salon/branch_sales_screen.dart';
import 'salon/branches_screen.dart';
import 'salon/salon_input.dart';
import 'salon/equipment_screen.dart';
import 'salon/feedback_screen.dart';
import 'salon/insights_screen.dart';
import 'salon/queue_screen.dart';
import 'salon/salon_business_profile.dart';
import 'salon/offers_screens.dart';
import 'salon/salon_settings_screen.dart';
import 'hubs/salon_team_hub_screen.dart';
import 'salon/appointments_screen.dart';
import 'salon/rebook_screen.dart';
import 'salon/stylists_screen.dart';
import '../providers/depot_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/notifications_provider.dart';

/// One entry in the inventory navigation (bottom-bar pages, quick menu grid,
/// and drawer all read from the same list) so a role's visible sections stay
/// consistent everywhere instead of three independently hand-computed index
/// schemes drifting apart.
/// The assistant is for anyone who can see something; what it may read is decided by the server, per right.
bool _canAskAssistant(UserPermissions p) =>
    p.has('inv_view_products') ||
    p.has('inv_create_sales') ||
    p.has('inv_view_credit') ||
    p.has('inv_view_reports') ||
    p.has('inv_view_expenses') ||
    p.has('inv_manage_products');

class _InvMenuEntry {
  const _InvMenuEntry({
    required this.key,
    required this.icon,
    required this.color,
    required this.pageBuilder,
    this.titleKey,
    this.staticTitle,
    this.visible,
  }) : assert(titleKey != null || staticTitle != null);

  final String key;
  final String? titleKey;
  final String? staticTitle;
  final IconData icon;
  final Color color;
  final Widget Function() pageBuilder;

  /// Null means always visible (used for the four items anchored to fixed
  /// footer slots: dashboard, products, sales, settings).
  final bool Function(UserPermissions perms)? visible;

  String title(LocalizationService loc) =>
      staticTitle ?? loc.translate(titleKey!);

  bool isVisible(UserPermissions perms) => visible?.call(perms) ?? true;
}

List<_InvMenuEntry> _invEntries(LocalizationService loc,
        {bool salon = false}) =>
    salon
        ? _salonEntries(loc)
        : <_InvMenuEntry>[
            // 1 — always-visible landing page
            _InvMenuEntry(
              key: 'dashboard',
              titleKey: 'inventory_dashboard',
              icon: Icons.dashboard,
              color: ThemeConstants.footerBarColor,
              pageBuilder: () => const InventoryDashboardScreen(),
            ),
            // 2 — Products + Categories + Brands
            _InvMenuEntry(
              key: 'products_hub',
              titleKey: 'products',
              icon: Icons.inventory_2_outlined,
              color: ThemeConstants.primaryOrange,
              pageBuilder: () => const ProductsHubScreen(),
              visible: (UserPermissions p) => p.has('inv_view_products'),
            ),
            // 3 — Stock Levels + Stock In/Out + Batches + Counts + Write-offs
            _InvMenuEntry(
              key: 'stock_hub',
              titleKey: 'stock_levels',
              icon: Icons.track_changes_outlined,
              color: ThemeConstants.successGreen,
              pageBuilder: () => const StockHubScreen(),
              visible: (UserPermissions p) =>
                  p.has('inv_manage_stock') || p.has('inv_report_damage'),
            ),
            // 4 — Sales + Returns & Parked + Past Orders
            _InvMenuEntry(
              key: 'sales_hub',
              titleKey: 'sales',
              icon: Icons.point_of_sale_outlined,
              color: ThemeConstants.primaryGradientEnd,
              pageBuilder: () => const SalesHubScreen(),
              visible: (UserPermissions p) => p.has('inv_create_sales'),
            ),
            // 5 — Purchasing + Crates & Empties + Warehouse Expenses
            _InvMenuEntry(
              key: 'supply_chain_hub',
              titleKey: 'purchasing',
              icon: Icons.local_shipping_outlined,
              color: const Color(0xFF667eea),
              pageBuilder: () => const SupplyChainHubScreen(),
              visible: (UserPermissions p) =>
                  p.has('inv_view_purchasing') ||
                  p.has('inv_view_crates') ||
                  p.has('inv_view_expenses'),
            ),
            // 6 — Daily Cash + Reports + Alerts + Reminders
            // Visible when the user can access at least one tab inside the hub.
            // inv_view_products alone (sales_officer) does NOT trigger this —
            // they see Alerts inside the hub, but their primary entry is Sales.
            _InvMenuEntry(
              key: 'finance_hub',
              titleKey: 'reports',
              icon: Icons.bar_chart_outlined,
              color: const Color(0xFF00E5FF),
              pageBuilder: () => const FinanceReportsHubScreen(),
              visible: (UserPermissions p) =>
                  p.has('inv_view_cash') ||
                  p.has('inv_view_reports') ||
                  p.has('inv_view_reminders'),
            ),
            // 7 — Money: customers & credit, debts and the monthly report, each told in a sentence (one tile, not three)
            _InvMenuEntry(
              key: 'money_menu',
              staticTitle: loc.isSwahili ? 'Fedha na madeni' : 'Money & debts',
              icon: Icons.account_balance_wallet_outlined,
              color: ThemeConstants.warningAmber,
              pageBuilder: () => const MoneyMenuScreen(),
              visible: (UserPermissions p) => p.has('inv_view_credit') || p.has('inv_view_reports'),
            ),
            // 7e — More than one place to sell from: the branches, and the goods each one holds (the same screens as a salon's)
            _InvMenuEntry(
              key: 'branch_stock',
              staticTitle: loc.isSwahili ? 'Bidhaa kwa tawi' : 'Goods by branch',
              icon: Icons.warehouse_outlined,
              color: const Color(0xFFF97316),
              pageBuilder: () => const BranchStockScreen(),
              visible: (UserPermissions p) => p.has('inv_manage_settings') || p.has('inv_view_reports'),
            ),
            _InvMenuEntry(
              key: 'branches',
              staticTitle: loc.isSwahili ? 'Matawi' : 'Branches',
              icon: Icons.store_mall_directory_outlined,
              color: const Color(0xFF0EA5E9),
              pageBuilder: () => const BranchesScreen(),
              visible: (UserPermissions p) => p.has('inv_manage_settings'),
            ),
            _InvMenuEntry(
              key: 'branch_sales',
              staticTitle: loc.isSwahili ? 'Mauzo kwa tawi na mtu' : 'Sales by branch and person',
              icon: Icons.leaderboard_outlined,
              color: const Color(0xFF22C55E),
              pageBuilder: () => const BranchSalesScreen(),
              visible: (UserPermissions p) => p.has('inv_view_reports'),
            ),
            // 7d — Ask the business: AI answers from what this person's rights allow
            _InvMenuEntry(
              key: 'assistant',
              staticTitle: loc.isSwahili ? 'Msaidizi wa AI' : 'AI assistant',
              icon: Icons.auto_awesome,
              color: ThemeConstants.invAccent,
              pageBuilder: () => const AssistantScreen(),
              visible: _canAskAssistant,
            ),
            // 8 — Settings (standalone)
            _InvMenuEntry(
              key: 'settings',
              titleKey: 'settings',
              icon: Icons.settings_outlined,
              color: const Color(0xFF64748B),
              pageBuilder: () => const _SettingsGate(),
              visible: null,
            ),
          ];

/// The sections of a SALON, in the same shell: its own words, no stock-taking or purchasing, and two sections that
/// are only for a salon (how each stylist did, and the "come back" reminders). Every other section is the one
/// inventory has, so the colours, the footer and the way around are the ones people already know.
List<_InvMenuEntry> _salonEntries(LocalizationService loc) {
  final bool sw = loc.isSwahili;
  return <_InvMenuEntry>[
    _InvMenuEntry(
      key: 'dashboard',
      staticTitle: sw ? 'Dashibodi ya Saluni' : 'Salon Dashboard',
      icon: Icons.dashboard,
      color: ThemeConstants.footerBarColor,
      pageBuilder: () => const InventoryDashboardScreen(),
    ),
    _InvMenuEntry(
      key: 'products_hub',
      staticTitle: sw ? 'Huduma na Bidhaa' : 'Services & Goods',
      icon: Icons.content_cut_rounded,
      color: ThemeConstants.primaryOrange,
      pageBuilder: () => const ProductsHubScreen(),
      visible: (UserPermissions p) => p.has('inv_view_products'),
    ),
    _InvMenuEntry(
      key: 'sales_hub',
      titleKey: 'sales',
      icon: Icons.point_of_sale_outlined,
      color: ThemeConstants.primaryGradientEnd,
      pageBuilder: () => const SalesHubScreen(),
      visible: (UserPermissions p) => p.has('inv_create_sales'),
    ),
    _InvMenuEntry(
      key: 'appointments',
      staticTitle: sw ? 'Miadi' : 'Appointments',
      icon: Icons.event_available_outlined,
      color: ThemeConstants.warningAmber,
      pageBuilder: () => const AppointmentsScreen(),
      visible: (UserPermissions p) => p.has('inv_create_sales'),
    ),
    _InvMenuEntry(
      key: 'stylists',
      staticTitle: sw ? 'Wahudumu' : 'Stylists',
      icon: Icons.groups_2_outlined,
      color: ThemeConstants.successGreen,
      pageBuilder: () => const StylistsScreen(),
      visible: (UserPermissions p) =>
          p.has('inv_view_reports') || p.has('inv_create_sales'),
    ),
    _InvMenuEntry(
      key: 'rebook',
      staticTitle: sw ? 'Vikumbusho vya kurudi' : 'Come back',
      icon: Icons.event_repeat_outlined,
      color: const Color(0xFF667eea),
      pageBuilder: () => const RebookScreen(),
      visible: (UserPermissions p) => p.has('inv_create_sales'),
    ),
    _InvMenuEntry(
      key: 'finance_hub',
      titleKey: 'reports',
      icon: Icons.bar_chart_outlined,
      color: const Color(0xFF00E5FF),
      pageBuilder: () => const FinanceReportsHubScreen(),
      visible: (UserPermissions p) =>
          p.has('inv_view_cash') ||
          p.has('inv_view_reports') ||
          p.has('inv_view_reminders'),
    ),
    _InvMenuEntry(
      key: 'assistant',
      staticTitle: sw ? 'Msaidizi wa AI' : 'AI assistant',
      icon: Icons.auto_awesome,
      color: ThemeConstants.invAccent,
      pageBuilder: () => const AssistantScreen(),
      visible: _canAskAssistant,
    ),
    _InvMenuEntry(
      key: 'finance',
      staticTitle: sw ? 'Fedha' : 'Money',
      icon: Icons.account_balance_wallet_outlined,
      color: ThemeConstants.successGreen,
      pageBuilder: () => const SalonFinanceHubScreen(),
      visible: (UserPermissions p) =>
          p.has('inv_view_reports') || p.has('inv_view_expenses'),
    ),
    _InvMenuEntry(
      key: 'team',
      staticTitle: sw ? 'Timu' : 'Team',
      icon: Icons.badge_outlined,
      color: const Color(0xFF8B5CF6),
      pageBuilder: () => const SalonTeamHubScreen(),
      visible: (UserPermissions p) =>
          p.has('inv_create_sales') || p.has('inv_view_reports'),
    ),
    _InvMenuEntry(
      key: 'queue',
      staticTitle: sw ? 'Wanaosubiri' : 'Walk-ins',
      icon: Icons.groups_2_outlined,
      color: const Color(0xFF22C55E),
      pageBuilder: () => const _QueuePage(),
      visible: (UserPermissions p) => p.has('inv_create_sales'),
    ),
    _InvMenuEntry(
      key: 'insights',
      staticTitle: sw ? 'Mwenendo' : 'Insights',
      icon: Icons.insights_outlined,
      color: const Color(0xFF6366F1),
      pageBuilder: () => const InsightsScreen(),
      visible: (UserPermissions p) => p.has('inv_view_reports'),
    ),
    _InvMenuEntry(
      key: 'business',
      staticTitle: sw ? 'Taarifa za biashara' : 'Business profile',
      icon: Icons.storefront_outlined,
      color: const Color(0xFF0EA5E9),
      pageBuilder: () => const SalonBusinessProfilePage(),
      visible: (UserPermissions p) => p.has('inv_manage_settings'),
    ),
    _InvMenuEntry(
      key: 'offers',
      staticTitle: sw ? 'Kuponi na ujumbe' : 'Offers & texts',
      icon: Icons.campaign_outlined,
      color: const Color(0xFFEC4899),
      pageBuilder: () => const OffersHubScreen(),
      visible: (UserPermissions p) => p.has('inv_manage_settings'),
    ),
    _InvMenuEntry(
      key: 'salon_settings',
      staticTitle: sw ? 'Mipangilio ya saluni' : 'Salon settings',
      icon: Icons.tune_outlined,
      color: const Color(0xFF64748B),
      pageBuilder: () => const SalonSettingsScreen(),
      visible: (UserPermissions p) => p.has('inv_manage_settings'),
    ),
    _InvMenuEntry(
      key: 'feedback',
      staticTitle: sw ? 'Maoni ya wateja' : 'Feedback',
      icon: Icons.reviews_outlined,
      color: const Color(0xFFF59E0B),
      pageBuilder: () => const FeedbackScreen(),
      visible: (UserPermissions p) =>
          p.has('inv_create_sales') || p.has('inv_view_reports'),
    ),
    _InvMenuEntry(
      key: 'equipment',
      staticTitle: sw ? 'Vifaa' : 'Equipment',
      icon: Icons.handyman_outlined,
      color: const Color(0xFF14B8A6),
      pageBuilder: () => const EquipmentScreen(),
      visible: (UserPermissions p) =>
          p.has('inv_manage_settings') || p.has('inv_view_reports'),
    ),
    _InvMenuEntry(
      key: 'branch_stock',
      staticTitle: sw ? 'Bidhaa kwa tawi' : 'Goods by branch',
      icon: Icons.warehouse_outlined,
      color: const Color(0xFFF97316),
      pageBuilder: () => const BranchStockScreen(),
      visible: (UserPermissions p) =>
          p.has('inv_manage_settings') || p.has('inv_view_reports'),
    ),
    _InvMenuEntry(
      key: 'branches',
      staticTitle: sw ? 'Matawi' : 'Branches',
      icon: Icons.store_mall_directory_outlined,
      color: const Color(0xFF0EA5E9),
      pageBuilder: () => const BranchesScreen(),
      visible: (UserPermissions p) => p.has('inv_manage_settings'),
    ),
    _InvMenuEntry(
      key: 'credit',
      staticTitle: sw ? 'Wateja na Madeni' : 'Clients & Credit',
      icon: Icons.credit_card_outlined,
      color: const Color(0xFF20B8CE),
      pageBuilder: () => const CreditScreen(),
      visible: (UserPermissions p) => p.has('inv_view_credit'),
    ),
    _InvMenuEntry(
      key: 'settings',
      titleKey: 'settings',
      icon: Icons.settings_outlined,
      color: const Color(0xFF64748B),
      pageBuilder: () => const _SettingsGate(),
      visible: null,
    ),
  ];
}

/// What the Settings button opens: the business settings for whoever may change them, and for everyone else (a sales
/// officer, say) their own account page (language, password, sign out). The button is always there, so it never lands
/// on another section.
class _SettingsGate extends StatelessWidget {
  const _SettingsGate();

  @override
  Widget build(BuildContext context) {
    final bool manage = context.select<AuthProvider, bool>((AuthProvider a) => a.permissions.has('inv_manage_settings'));

    return manage ? const DepotSettingsScreen() : const SettingsScreen();
  }
}

/// The five buttons of the inventory footer, left to right.
abstract final class InvFooterSlot {
  static const int dashboard = 0;
  static const int products = 1;
  static const int menu = 2;
  static const int sales = 3;
  static const int settings = 4;
}

/// The page of the home a footer button opens, or null when the button opens no page of its own (the menu) or
/// the business has no such section.
int? _pageForSlot(int slot, List<_InvMenuEntry> visible) {
  int indexOf(String key) =>
      visible.indexWhere((_InvMenuEntry e) => e.key == key);
  switch (slot) {
    case InvFooterSlot.dashboard:
      return 0;
    case InvFooterSlot.products:
      final int p = indexOf('products_hub');
      return p >= 0 ? p : null;
    case InvFooterSlot.sales:
      final int s = indexOf('sales_hub');
      return s >= 0 ? s : null;
    case InvFooterSlot.settings:
      final int st = indexOf('settings');
      return st >= 0 ? st : visible.length - 1;
    default:
      return null;
  }
}

class InventoryHome extends StatefulWidget {
  const InventoryHome({super.key, this.initialIndex = 0, this.salon = false});
  final int initialIndex;

  /// Open as a SALON: the same screens and the same engine, with the salon's sections (see [_salonEntries]).
  final bool salon;

  /// For a screen opened on top of the inventory home (the product form): what its footer buttons do. They bring
  /// the home back to the front, on the section the button stands for, exactly as the home's own footer would.
  /// (Without a home underneath, one is opened.)
  static void goToFooterSlot(BuildContext context, int slot) {
    final _InventoryHomeState? home = _InventoryHomeState._active;
    final NavigatorState navigator = Navigator.of(context);
    if (home != null && home.mounted) {
      final Route<dynamic>? homeRoute = ModalRoute.of(home.context);
      navigator.popUntil((Route<dynamic> r) => r == homeRoute || r.isFirst);
      home._onFooterSlot(slot);
      return;
    }
    final LocalizationService loc = LocalizationService.instance;
    final UserPermissions perms = context.read<AuthProvider>().permissions;
    // The home to bring back is the same kind as the one this screen was opened from (a salon's, or inventory's).
    final bool salon = context.read<InventoryProvider>().salonMode;
    final int? page = _pageForSlot(
        slot,
        _invEntries(loc, salon: salon)
            .where((_InvMenuEntry e) => e.isVisible(perms))
            .toList());
    navigator.pushReplacement(
      MaterialPageRoute<void>(
          builder: (_) => InventoryHome(initialIndex: page ?? 0, salon: salon)),
    );
  }

  @override
  State<InventoryHome> createState() => _InventoryHomeState();
}

class _InventoryHomeState extends State<InventoryHome> {
  int _index = 0;

  /// The sections that have been opened. A section is built (and so starts loading its data) the first time it is
  /// opened, then kept: opening the home used to build all eight at once, and with them about thirty requests, most
  /// for screens nobody was looking at.
  final Set<int> _opened = <int>{};

  /// The home that is on screen, for [InventoryHome.goToFooterSlot].
  static _InventoryHomeState? _active;

  @override
  void dispose() {
    if (_active == this) _active = null;
    super.dispose();
  }

  /// What a tap on a footer button does.
  void _onFooterSlot(int slot) {
    final LocalizationService loc = LocalizationService.instance;
    final List<_InvMenuEntry> visible = _invEntries(loc, salon: widget.salon)
        .where((_InvMenuEntry e) => e.isVisible(_perms(context)))
        .toList();
    if (slot == InvFooterSlot.menu) {
      _openQuickMenu(context); // All sections grid
      return;
    }
    final int? page = _pageForSlot(slot, visible);
    if (page != null) setState(() => _index = page);
  }

  @override
  void initState() {
    super.initState();
    _active = this;
    _index = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationsProvider>().refreshUnreadCount();
      // What this business's inventory is set up to do (crates or not, which price the till uses ...).
      final InventoryProvider inv = context.read<InventoryProvider>();
      // Which service's books every request below is about: say it FIRST, so the settings come from this service,
      // and forget what the depot provider holds from another service or account (settings, crates, debts ...).
      // The screens opened on top of this home (the product form) also need to know whether it is a salon's.
      inv.setSalonMode(widget.salon);
      context.read<DepotProvider>().resetForNewContext();
      inv.fetchCapabilities().then((_) => _askKindIfUnset());
      if (widget.salon) inv.fetchSalonStaff();
    });
  }

  static bool _kindAsked = false;

  /// A business that never said what kind it is (retail, wholesale, mixed or depot) still works, but is spoken to in general
  /// words and shows everything a depot would. Its owner is asked once per session to choose, so the app can show only what suits.
  Future<void> _askKindIfUnset() async {
    if (!mounted || widget.salon || _kindAsked) return;
    final InventoryProvider inv = context.read<InventoryProvider>();
    if (inv.capabilities.kindChosen) return;
    if (!(context.read<AuthProvider>().user?.isBusinessOwner ?? false)) return;
    _kindAsked = true;
    final bool sw = LocalizationService.instance.isSwahili;
    final bool? choose = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: Text(sw ? 'Biashara yako ni ya aina gani?' : 'What kind of business is this?'),
        content: Text(sw
            ? 'Chagua aina (rejareja, jumla, mchanganyiko au depo) ili programu ionyeshe vitu vinavyokufaa tu.'
            : 'Choose a kind (retail, wholesale, mixed or depot) so the app shows only what suits your business.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(sw ? 'Baadaye' : 'Later')),
          FilledButton(key: const Key('choose_kind_now'), onPressed: () => Navigator.pop(d, true), child: Text(sw ? 'Chagua sasa' : 'Choose now')),
        ],
      ),
    );
    if (choose == true && mounted) {
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext _) => const DepotSettingsScreen()));
      if (mounted) await context.read<InventoryProvider>().fetchCapabilities();
    }
  }

  /// Returns effective permissions for this user.
  /// When the server returned effective_permissions (role defaults ∪ explicit
  /// grants already merged), use those directly via fromUser so the role is
  /// still tracked for admin-bypass logic. Local role defaults fill the gap
  /// when the server omits the resolved list (older API, cached login).
  UserPermissions _perms(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    if (user == null) return UserPermissions.empty();
    return UserPermissions.fromUser(
      userRole: user.role,
      // user.permissions now holds effective_permissions from the server
      // (role defaults ∪ explicit grants), or null if the server hasn't
      // sent it yet — fromUser handles both cases correctly.
      explicitGrants: user.permissions,
    );
  }

  Future<void> _openQuickMenu(BuildContext context) async {
    final loc = LocalizationService.instance;
    final perms = _perms(context);
    final List<_InvMenuEntry> visible = _invEntries(loc, salon: widget.salon)
        .where((e) => e.isVisible(perms))
        .toList();

    // Build the same navigation items as the drawer, but as a 3-column grid.
    final List<_GridNavItem> items = <_GridNavItem>[
      for (int i = 0; i < visible.length; i++)
        _GridNavItem(
          label: visible[i].title(loc),
          icon: visible[i].icon,
          color: visible[i].color.withOpacity(0.85),
          onTap: () {
            setState(() => _index = i);
            Navigator.of(context).pop();
          },
        ),
    ];

    // "Faida kwa Bidhaa": the whole product profit table (the dashboard shows only the
    // first rows of it). Same permission as the table on the dashboard. It opens its own
    // screen on top rather than switching a tab, so it is not in the bottom bar or drawer.
    if (perms.has('inv_view_reports')) {
      items.add(_GridNavItem(
        label: widget.salon
            ? (loc.isSwahili
                ? 'Faida ya Huduma na Bidhaa'
                : 'Services & Goods Profit')
            : loc.translate('profit_margins_title'),
        icon: Icons.trending_up_rounded,
        color: ThemeConstants.successGreen.withOpacity(0.85),
        onTap: () {
          final NavigatorState navigator = Navigator.of(context);
          navigator.pop(); // close the menu
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const ProfitByProductScreen(),
            ),
          );
        },
      ));
    }

    // Add Switch Service to quick menu
    items.add(_GridNavItem(
      label: loc.translate('switch_service'),
      icon: Icons.sync_alt,
      color: ThemeConstants.primaryBlue.withOpacity(0.85),
      onTap: () {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (context) => const ServiceSwitcherDialog(),
        );
      },
    ));

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeConstants.primaryBlue.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: Colors.white24),
            ),
            padding: EdgeInsets.all(12.w),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12.h,
                  crossAxisSpacing: 12.w,
                  childAspectRatio: 0.95,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  return InkWell(
                    onTap: it.onTap,
                    borderRadius: BorderRadius.circular(12.r),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48.w,
                          height: 48.w,
                          decoration: BoxDecoration(
                            color: it.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child:
                              Icon(it.icon, color: Colors.white, size: 24.sp),
                        ),
                        SizedBox(height: 4.h),
                        AutoSizeText(
                          it.label,
                          style: ThemeConstants.bodyStyle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          minFontSize: 9,
                          stepGranularity: 0.5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// The sections, with only the ones that have been opened actually built.
  Widget _buildPages(List<Widget> pages) {
    final int current = _index.clamp(0, pages.length - 1);
    _opened.add(current);
    return IndexedStack(
      index: current,
      children: <Widget>[
        for (int i = 0; i < pages.length; i++)
          _opened.contains(i) ? pages[i] : const SizedBox.shrink(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    final perms = _perms(context);
    final List<_InvMenuEntry> visible = _invEntries(loc, salon: widget.salon)
        .where((e) => e.isVisible(perms))
        .toList();

    final pages = visible
        .map((e) => SalonEmbedded(child: e.pageBuilder()))
        .toList(growable: false);
    final titles = visible.map((e) => e.title(loc)).toList(growable: false);
    final int salesIndex = visible.indexWhere((e) => e.key == 'sales_hub');
    final int settingsIndex = visible.indexWhere((e) => e.key == 'settings');

    final int productsIndex =
        visible.indexWhere((e) => e.key == 'products_hub');

    // The sections a person sees can be fewer than when this page was last chosen (another account, fewer
    // permissions): never point past the end of the list.
    if (_index >= visible.length)
      _index = visible.isEmpty ? 0 : visible.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: ThemeConstants.buildAppBar(
        titles[_index],
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: 20.sp),
          tooltip: loc.translate('back'),
          onPressed: () {
            if (_index > 0) {
              setState(() => _index = 0);
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/select-service');
            }
          },
        ),
        actions: [
          Consumer<NotificationsProvider>(
            builder: (BuildContext context, NotificationsProvider n, __) =>
                Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                IconButton(
                  icon: Icon(Icons.notifications_outlined, size: 22.sp),
                  tooltip: loc.translate('notifications'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ApprovalNotificationsScreen(),
                    ),
                  ),
                ),
                if (n.unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: ThemeConstants.errorRed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        n.unreadCount > 9 ? '9+' : '${n.unreadCount}',
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: const Key('header_ai_assistant'),
            icon: Icon(Icons.auto_awesome, size: 22.sp),
            tooltip: loc.isSwahili ? 'Msaidizi wa AI' : 'AI assistant',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AssistantScreen()),
            ),
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu, size: 20.sp),
              tooltip: loc.translate('menu'),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.apps, size: 20.sp),
            tooltip: loc.translate('select_service'),
            onPressed: () =>
                Navigator.pushReplacementNamed(context, '/select-service'),
          ),
        ],
      ),
      drawer: _InventoryDrawer(
        index: _index,
        salon: widget.salon,
        onSelected: (i) {
          setState(() => _index = i);
          Navigator.pop(context);
        },
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(color: ThemeConstants.primaryBlue),
        child: SafeArea(
          child: _buildPages(pages),
        ),
      ),
      bottomNavigationBar: InventoryFooter(
        salon: widget.salon,
        index: _index,
        salesIndex: salesIndex,
        productsIndex: productsIndex >= 0 ? productsIndex : 1,
        settingsIndex: settingsIndex >= 0 ? settingsIndex : pages.length - 1,
        onTap: _onFooterSlot,
      ),
    );
  }
}

/// The pill-shaped bar at the bottom of the inventory: dashboard, products, all sections, sales, settings.
/// A screen opened on top of the home (the product form) shows the same bar, with [index] / [productsIndex] saying
/// which button to light up.
class InventoryFooter extends StatelessWidget {
  const InventoryFooter({
    super.key,
    required this.index,
    required this.onTap,
    this.salesIndex = 3,
    this.productsIndex = 1,
    this.settingsIndex = 7,
    this.salon = false,
  });
  final int index;

  /// A salon's second button opens its services, not products.
  final bool salon;
  final int salesIndex;
  final int productsIndex;
  final int settingsIndex;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    // Visual pill-like bar with 5 icons as in the mock
    return ColoredBox(
      color: ThemeConstants
          .footerBarColor, // unify background color under the curved bar
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28.r),
          child: Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(vertical: 8.h),
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: ThemeConstants
                  .footerBarColor, // same color as outer background
              borderRadius: BorderRadius.circular(28.r),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Dashboard
                _FooterIcon(
                  selected: index == 0,
                  icon: Icons.bar_chart_rounded,
                  label: LocalizationService.instance.translate('dashboard'),
                  onTap: () => onTap(0),
                ),
                // Products hub
                _FooterIcon(
                  selected: index == productsIndex,
                  icon: Icons.inventory_2_rounded,
                  label: LocalizationService.instance
                      .translate(salon ? 'footer_services' : 'products'),
                  onTap: () => onTap(1),
                ),
                // Quick menu (all sections)
                _FooterIcon(
                  selected: false,
                  icon: Icons.grid_view_rounded,
                  label: LocalizationService.instance.translate('menu'),
                  onTap: () => onTap(2),
                ),
                // Sales
                _FooterIcon(
                  selected: index == salesIndex,
                  icon: Icons.point_of_sale_rounded,
                  label: LocalizationService.instance.translate('sales'),
                  onTap: () => onTap(3),
                ),
                // Settings
                _FooterIcon(
                  selected: index == settingsIndex,
                  icon: Icons.settings_rounded,
                  label: LocalizationService.instance.translate('settings'),
                  onTap: () => onTap(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterIcon extends StatelessWidget {
  const _FooterIcon(
      {required this.selected,
      required this.icon,
      required this.onTap,
      required this.label});
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  @override
  Widget build(BuildContext context) {
    // Blue-toned background circles for icons (to match requested style)
    final Color bg = selected
        ? ThemeConstants.primaryBlue.withOpacity(0.35)
        : ThemeConstants.primaryBlue.withOpacity(0.22);
    // Flexible: on a very narrow screen the five buttons share the width instead of overflowing.
    return Flexible(
      child: InkResponse(
        onTap: onTap,
        radius: 28.r,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 64.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 21.sp),
              ),
              SizedBox(height: 3.h),
              // The name of what the button opens, so nobody has to guess from the picture.
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: selected ? 1 : 0.85),
                    fontSize: 10.sp,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridNavItem {
  _GridNavItem(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _InventoryDrawer extends StatelessWidget {
  const _InventoryDrawer(
      {required this.index, required this.onSelected, this.salon = false});
  final int index;
  final bool salon;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final perms = context.select<AuthProvider, UserPermissions>(
        (AuthProvider a) => a.permissions);
    final List<_InvMenuEntry> visible = _invEntries(loc, salon: salon)
        .where((e) => e.isVisible(perms))
        .toList();

    return Drawer(
      backgroundColor: ThemeConstants.primaryBlue,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  for (int i = 0; i < visible.length; i++)
                    ListTile(
                      leading: Icon(visible[i].icon,
                          color: Colors.white, size: 22.sp),
                      title: Text(visible[i].title(loc),
                          style: ThemeConstants.bodyStyle),
                      selected: index == i,
                      selectedTileColor: Colors.white10,
                      onTap: () => onSelected(i),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: Icon(Icons.sync_alt, color: Colors.white, size: 22.sp),
                title: Text(loc.translate('switch_service'),
                    style: ThemeConstants.bodyStyle),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (context) => const ServiceSwitcherDialog(),
                  );
                },
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: Icon(Icons.logout, color: Colors.white, size: 22.sp),
                title: Text(loc.translate('logout'),
                    style: ThemeConstants.bodyStyle),
                onTap: () async {
                  final auth =
                      Provider.of<AuthProvider>(context, listen: false);
                  await auth.logout();
                  if (context.mounted) {
                    await Navigator.of(context)
                        .pushNamedAndRemoveUntil('/', (r) => false);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The walk-in queue as a page of its own (the screen itself is only a body).
class _QueuePage extends StatelessWidget {
  const _QueuePage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: salonAppBar(
            context,
            context.watch<LocalizationService>().isSwahili
                ? 'Wanaosubiri'
                : 'Walk-ins'),
        body: const QueueScreen(),
      );
}
