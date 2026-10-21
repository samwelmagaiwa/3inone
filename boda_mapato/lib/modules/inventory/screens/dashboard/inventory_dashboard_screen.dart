// ignore_for_file: directives_ordering
import 'dart:async';
import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/responsive_helper.dart';
import '../../models/inv_sale.dart';
import '../../providers/inventory_provider.dart';
import '../credit/credit_screen.dart';
import '../hubs/finance_reports_hub_screen.dart';
import '../hubs/products_hub_screen.dart';
import '../hubs/sales_hub_screen.dart';
import '../hubs/stock_hub_screen.dart';
import '../hubs/supply_chain_hub_screen.dart';
import '../../../../widgets/month_selector.dart';
import '../reports/profit_by_product_screen.dart';
import '../salon/salon_access.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import '../../../../services/api_service.dart';
import '../salon/salon_overview_card.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/profit_by_product_table.dart';

/// Inventory dashboard styled to match the Transport (Modern) dashboard:
/// hero balance card, glass stat cards, month strip + line chart.
class InventoryDashboardScreen extends StatefulWidget {
  const InventoryDashboardScreen({super.key, this.salonApi});

  /// The salon's server calls (a fake in tests); used for the list of branches in the period sheet.
  final SalonApi? salonApi;

  @override
  State<InventoryDashboardScreen> createState() =>
      _InventoryDashboardScreenState();
}

enum _DateFilter { today, week, month, year, custom }

class _InventoryDashboardScreenState extends State<InventoryDashboardScreen>
    with TickerProviderStateMixin {
  static const Color primaryBlue = ThemeConstants.primaryBlue;
  static const Color cardColor = ThemeConstants.cardColor;
  static const Color textPrimary = ThemeConstants.textPrimary;
  static const Color textSecondary = ThemeConstants.textSecondary;

  late final AnimationController _chartAnimationController;
  late final Animation<double> _chartAnimation;

  int _selectedMonth = DateTime.now().month;
  bool _chartLoading = false;

  // ── Date filter state ─────────────────────────────────────────────────────
  _DateFilter _filter = _DateFilter.today;
  DateTime? _customStart;
  DateTime? _customEnd;

  /// Short month names (Jan ... Dec) in the language chosen in the app.
  static List<String> get months => List<String>.generate(
      12, (int i) => LocalizationService.instance.translate('month_short_${i + 1}'));

  @override
  void initState() {
    super.initState();
    _chartAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _chartAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _chartAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _chartAnimationController.forward();
        _loadChartForMonth(_selectedMonth);
      }
    });
    // InventoryProvider.bootstrap() (which fetches this) runs once at
    // provider-construction time in main.dart -- that can fire before the
    // auth token is loaded, silently leaving the officer list empty until a
    // manual pull-to-refresh. Fetching it again here, once the dashboard is
    // actually mounted (which only happens post-login), guarantees the
    // filter has data the first time it's opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final AuthProvider auth = context.read<AuthProvider>();
      final String role = auth.user?.role ?? '';
      final bool privileged = role == 'admin' || role == 'super_admin' ||
          role == 'manager' || role == 'administrator';
      if (privileged) {
        context.read<InventoryProvider>().fetchSalesOfficers();
      }
    });
  }

  Future<void> _loadChartForMonth(int month) async {
    if (!mounted) return;
    setState(() => _chartLoading = true);
    await Provider.of<InventoryProvider>(context, listen: false)
        .fetchMonthlyChart(DateTime.now().year, month);
    if (!mounted) return;
    setState(() => _chartLoading = false);
    _chartAnimationController
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _chartAnimationController.dispose();
    super.dispose();
  }

  bool _isPrivilegedViewer(BuildContext context) {
    final String role = context.read<AuthProvider>().user?.role ?? '';
    return role == 'admin' || role == 'super_admin' || role == 'manager' ||
        role == 'administrator';
  }

  /// Compact icon button (top-right, next to the date filter) that opens a
  /// menu of sales officers -- picking one scopes the whole dashboard
  /// (KPIs, chart, sales list) to that officer's data only; "All officers"
  /// clears it back to the business-wide view. Only shown to privileged
  /// roles; a sales_officer viewer never sees this since the backend
  /// already locks them to their own data regardless.
  Widget _buildOfficerFilterChip(BuildContext context, LocalizationService loc) {
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final officers = inv.salesOfficers;
    final selectedId = inv.selectedOfficerId;
    final selectedName = selectedId == null
        ? null
        : officers.firstWhere(
            (o) => (o['id'] as String?) == selectedId,
            orElse: () => const {},
          )['name'] as String?;

    // PopupMenuButton<T> can't use `null` as a real item value: Flutter's
    // PopupMenuButtonState treats a null result from the menu route as
    // "dismissed without selecting" (same as tapping outside to close it)
    // and calls onCanceled instead of onSelected -- so tapping "All
    // Officers" (value: null) never actually fired the reset. Use a
    // sentinel string instead and map it back to null here.
    const String allOfficersValue = '__all_officers__';
    return PopupMenuButton<String>(
      tooltip: loc.translate('filter_by_officer'),
      onSelected: (id) =>
          inv.setSelectedOfficer(id == allOfficersValue ? null : id),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: allOfficersValue,
          child: Text(loc.translate('all_officers')),
        ),
        const PopupMenuDivider(),
        ...officers.map((o) => PopupMenuItem<String>(
              value: o['id'] as String,
              child: Text('${o['name']}'),
            )),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selectedId == null
              ? Colors.white.withOpacity(0.12)
              : Colors.cyanAccent.withOpacity(0.20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selectedId == null ? Colors.white24 : Colors.cyanAccent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.person_search_rounded, color: Colors.white, size: 14),
            if (selectedName != null) ...[
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 70),
                child: Text(selectedName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final InventoryProvider inv =
        Provider.of<InventoryProvider>(context, listen: false);
    await inv.bootstrap();
    if (!mounted) {
      return;
    }
    _chartAnimationController.reset();
    unawaited(_chartAnimationController.forward());
  }

  @override
  Widget build(BuildContext context) {
    ResponsiveHelper.init(context);
    // watch — rebuilds automatically when language toggles
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final auth = context.read<AuthProvider>();
    final user = auth.user;

    // ── Resolve effective permissions once ────────────────────────────────────
    final perms = user == null
        ? UserPermissions.empty()
        : UserPermissions.fromUser(
            userRole: user.role ?? '',
            explicitGrants: user.permissions,
          );

    final bool canViewProducts = perms.has('inv_view_products');
    final bool canCreateSales  = perms.has('inv_create_sales');
    final bool canViewReports  = perms.has('inv_view_reports');
    final bool canViewStock    = perms.has('inv_manage_stock');
    final bool canViewCash     = perms.has('inv_view_cash');
    final bool canViewCredit   = perms.has('inv_view_credit');
    final bool canViewCrates   = perms.has('inv_view_crates');
    final bool canViewExpenses = perms.has('inv_view_expenses');
    final bool canViewPurchasing = perms.has('inv_view_purchasing');

    // Show a greeting banner for non-admin roles so the dashboard feels
    // personally relevant rather than a generic data wall.
    final String role = user?.role ?? '';
    final bool isPrivileged =
        role == 'admin' || role == 'super_admin' || role == 'administrator';

    return RefreshIndicator(
      onRefresh: _refresh,
      backgroundColor: Colors.white,
      color: primaryBlue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Role-branded greeting for non-admin staff
              if (!isPrivileged)
                _buildRoleWelcome(loc, user?.name ?? '', role, perms),
              if (!isPrivileged) ResponsiveHelper.verticalSpace(2),

              // Leo card
              if (canCreateSales) _buildSalesTopCard(loc, inv),
              // Tiny gap then insight cards (Fedha / Credit / Matumizi)
              if (canCreateSales && (canViewCash || canViewCredit || canViewExpenses))
                const SizedBox(height: 4),
              if (canViewCash || canViewCredit || canViewExpenses)
                _buildInsightRow(
                  loc, inv,
                  canViewCash: canViewCash,
                  canViewCredit: canViewCredit,
                  canViewCrates: canViewCrates,
                  canViewExpenses: canViewExpenses,
                  canViewPurchasing: canViewPurchasing,
                  canViewStock: canViewStock,
                ),
              // Tiny gap then Bidhaa + low stock
              if (canViewProducts) const SizedBox(height: 4),
              if (canViewProducts) _buildProductStatsRow(loc, inv),
              if (canViewProducts) const SizedBox(height: 4),

              // Joined scrollable sections (valuation / products list / chart)
              _buildJoinedSections(
                loc, inv,
                canViewReports: canViewReports,
                canViewProducts: canViewProducts,
                canViewSalesChart: canCreateSales,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Role greeting banner ────────────────────────────────────────────────────
  Widget _buildRoleWelcome(
    LocalizationService loc,
    String name,
    String role,
    UserPermissions perms,
  ) {
    final String roleLabel = _roleDisplay(role);
    final List<_QuickChip> chips = _quickChipsFor(loc, perms);

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white70, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${loc.translate('welcome')}, $name 👋',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: ResponsiveHelper.bodyL,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        roleLabel,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: ResponsiveHelper.bodyS,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.cyanAccent.withOpacity(0.4), width: 1),
                  ),
                  child: Text(
                    roleLabel,
                    style: TextStyle(
                      color: Colors.cyanAccent.shade200,
                      fontSize: ResponsiveHelper.bodyS,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: chips
                    .map((c) => _quickChipWidget(context, c))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _roleDisplay(String role) {
    switch (role.toLowerCase()) {
      case 'sales_officer': return LocalizationService.instance.translate('sales_officer');
      case 'manager':       return LocalizationService.instance.translate('manager');
      case 'operator':      return LocalizationService.instance.translate('operator');
      case 'viewer':        return LocalizationService.instance.translate('viewer');
      case 'hair_stylist':
      case 'nail_technician':
      case 'lash_makeup_artist':
      case 'accountant':
        return LocalizationService.instance.translate(role.toLowerCase());
      default:              return role.replaceAll('_', ' ');
    }
  }

  List<_QuickChip> _quickChipsFor(LocalizationService loc, UserPermissions perms) {
    final chips = <_QuickChip>[];
    if (perms.has('inv_create_sales'))   { chips.add(_QuickChip(loc.translate('sell'),      Icons.point_of_sale_rounded,          (_) => const SalesHubScreen())); }
    if (perms.has('inv_view_products'))  { chips.add(_QuickChip(loc.translate('products'),   Icons.inventory_2_outlined,           (_) => const ProductsHubScreen())); }
    if (perms.has('inv_view_reminders')) { chips.add(_QuickChip(loc.translate('reminders'),  Icons.notifications_outlined,         (_) => const FinanceReportsHubScreen())); }
    if (perms.has('inv_view_cash'))      { chips.add(_QuickChip(loc.translate('cash'),        Icons.account_balance_wallet_outlined, (_) => const FinanceReportsHubScreen())); }
    if (perms.has('inv_view_credit'))    { chips.add(_QuickChip(loc.translate('credit'),      Icons.people_outline_rounded,         (_) => const CreditScreen())); }
    if (perms.has('inv_view_expenses'))  { chips.add(_QuickChip(loc.translate('expenses'),    Icons.receipt_outlined,               (_) => const SupplyChainHubScreen())); }
    if (perms.has('inv_manage_stock'))   { chips.add(_QuickChip(loc.translate('stock'),       Icons.layers_outlined,                (_) => const StockHubScreen())); }
    return chips.take(5).toList();
  }

  Widget _quickChipWidget(BuildContext context, _QuickChip chip) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: chip.builder),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: Colors.white.withOpacity(0.18), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(chip.icon, color: Colors.white70, size: 14),
            const SizedBox(width: 5),
            Text(
              chip.label,
              style: TextStyle(
                color: textPrimary,
                fontSize: ResponsiveHelper.bodyS,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Insight row: cash / credit / crates / expenses quick glance ─────────────
  Widget _buildInsightRow(
    LocalizationService loc,
    InventoryProvider inv, {
    required bool canViewCash,
    required bool canViewCredit,
    required bool canViewCrates,
    required bool canViewExpenses,
    required bool canViewPurchasing,
    required bool canViewStock,
  }) {
    final tiles = <Widget>[];
    if (canViewCash) {
      tiles.add(_insightTile(
        Icons.account_balance_wallet_outlined,
        Colors.greenAccent.shade400,
        loc.translate('cash'),
        'TSH ${_formatCurrency(inv.cashToday)}',
      ));
    }
    if (canViewCredit) {
      tiles.add(_insightTile(
        Icons.people_outline_rounded,
        Colors.lightBlueAccent.shade200,
        loc.translate('credit'),
        'TSH ${_formatCurrency(inv.creditOutstanding)}',
      ));
    }
    if (canViewExpenses) {
      tiles.add(_insightTile(
        Icons.receipt_outlined,
        Colors.orangeAccent.shade200,
        loc.translate('expenses'),
        'TSH ${_formatCurrency(inv.expensesToday)}',
      ));
    }
    if (tiles.isEmpty) return const SizedBox.shrink();

    return Row(
      children: tiles.asMap().entries.map((e) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: e.key == 0 ? 0 : 4),
            child: e.value,
          ),
        );
      }).toList(),
    );
  }

  Widget _insightTile(
      IconData icon, Color color, String label, String value) =>
      _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(children: <Widget>[
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: textSecondary,
                          fontSize: ResponsiveHelper.bodyS)),
                ),
              ]),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(
                        color: textPrimary,
                        fontSize: ResponsiveHelper.bodyM,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );

  Widget _buildGlassCard({required Widget child}) {
    const radius = 20.0;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(radius),
        // Outer glow border using gradient
        border: Border.all(
          color: Colors.transparent,
          width: 0,
        ),
        boxShadow: <BoxShadow>[
          // Cyan top-edge glow
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.35),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, -1),
          ),
          // Cyan side glow
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.20),
            blurRadius: 20,
            spreadRadius: 2,
            offset: Offset.zero,
          ),
          // Strong primaryBlue bottom shadow
          BoxShadow(
            color: primaryBlue.withOpacity(1.0),
            blurRadius: 28,
            spreadRadius: 8,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: primaryBlue.withOpacity(0.90),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: Colors.cyanAccent.withOpacity(0.42),
            width: 1.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: child,
        ),
      ),
    );
  }

  // ── Filter helpers ────────────────────────────────────────────────────────

  String _filterLabel(LocalizationService loc) {
    switch (_filter) {
      case _DateFilter.today:   return loc.translate('today');
      case _DateFilter.week:    return loc.translate('this_week');
      case _DateFilter.month:   return loc.translate('this_month');
      case _DateFilter.year:    return loc.translate('this_year');
      case _DateFilter.custom:
        if (_customStart != null && _customEnd != null) {
          final s = _customStart!;
          final e = _customEnd!;
          return '${s.day}/${s.month} – ${e.day}/${e.month}';
        }
        return loc.translate('custom_range');
    }
  }

  DateTimeRange _filterRange() {
    final now = DateTime.now();
    switch (_filter) {
      case _DateFilter.today:
        final start = DateTime(now.year, now.month, now.day);
        return DateTimeRange(start: start, end: now);
      case _DateFilter.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
            start: DateTime(start.year, start.month, start.day), end: now);
      case _DateFilter.month:
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1), end: now);
      case _DateFilter.year:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case _DateFilter.custom:
        return DateTimeRange(
            start: _customStart ?? DateTime(now.year, now.month, 1),
            end: _customEnd ?? now);
    }
  }

  List<InvSale> _filteredSales(InventoryProvider inv) {
    final range = _filterRange();
    return inv.sales.where((s) =>
        !s.createdAt.isBefore(range.start) &&
        !s.createdAt.isAfter(range.end)).toList();
  }

  double _filteredTotal(InventoryProvider inv) =>
      _filteredSales(inv).fold(0, (sum, s) => sum + s.total);

  double _filteredProfit(InventoryProvider inv) =>
      _filteredSales(inv).fold(0,
          (sum, s) => sum + s.items.fold(0.0, (a, i) => a + i.profit));

  int _filteredSalesCount(InventoryProvider inv) => _filteredSales(inv).length;

  Future<void> _showFilterSheet() async {
    // A salon with branches can also look at one branch (everything on this page then follows it).
    List<Map<String, dynamic>> branches = <Map<String, dynamic>>[];
    if (context.read<InventoryProvider>().salonMode) {
      try {
        branches = <Map<String, dynamic>>[
          for (final SalonBranchInfo b in await (widget.salonApi ?? SalonApi()).branches())
            if (b.active) <String, dynamic>{'id': b.id, 'name': b.name},
        ];
      } on Exception {
        branches = <Map<String, dynamic>>[];
      }
      if (!mounted) return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        current: _filter,
        customStart: _customStart,
        customEnd: _customEnd,
        branches: branches,
        branchId: ApiService.activeBranch,
        onBranch: (int? id, String? name) {
          if (id == ApiService.activeBranch) return;
          ApiService.activeBranch = id;
          ApiService.activeBranchName = name;
          _refresh();
        },
        onSelect: (f, start, end) {
          setState(() {
            _filter = f;
            _customStart = start;
            _customEnd = end;
          });
        },
      ),
    );
  }

  // ── Combined top sales card with date filter ─────────────────────────────
  Widget _buildSalesTopCard(LocalizationService loc, InventoryProvider inv) =>
      _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Header row: [Leo] [===progress bar===] [% label] [Chuja]
              Builder(builder: (_) {
                final now = DateTime.now();
                final todayStart = DateTime(now.year, now.month, now.day);
                final yest = todayStart.subtract(const Duration(days: 1));
                final todayTotal = _filteredTotal(inv);
                final yesterdayTotal = inv.sales
                    .where((s) =>
                        !s.createdAt.isBefore(yest) &&
                        s.createdAt.isBefore(todayStart))
                    .fold(0.0, (sum, s) => sum + s.total);
                final pct = yesterdayTotal == 0
                    ? (todayTotal > 0 ? 1.0 : 0.0)
                    : (todayTotal / yesterdayTotal).clamp(0.0, 1.0);
                final isAhead = todayTotal >= yesterdayTotal;
                final barColor = isAhead
                    ? Colors.greenAccent.shade400
                    : Colors.orangeAccent.shade200;
                final pctLabel = yesterdayTotal == 0
                    ? (todayTotal > 0 ? '↑' : '0%')
                    : '${isAhead ? '↑' : '↓'} ${(pct * 100).toStringAsFixed(0)}%';
                return Row(
                  children: <Widget>[
                    const Icon(Icons.bar_chart_rounded, color: Colors.white54, size: 15),
                    const SizedBox(width: 6),
                    Text(_filterLabel(loc),
                        style: TextStyle(
                            color: textSecondary,
                            fontSize: ResponsiveHelper.bodyS,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5)),
                    const SizedBox(width: 8),
                    // Progress bar fills the space between label and % text
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 3,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(pctLabel,
                        style: TextStyle(
                            color: barColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    if (_isPrivilegedViewer(context)) ...[
                      _buildOfficerFilterChip(context, loc),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: _showFilterSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.tune_rounded, color: Colors.white, size: 14),
                            const SizedBox(width: 5),
                            Text(loc.translate('filter_btn'), style: const TextStyle(color: Colors.white,
                                fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 10),
              // Mauzo / Idadi / Faida
              Row(
                children: <Widget>[
                  Expanded(
                    child: _salesMiniTile(
                      label: loc.translate('sales'),
                      value: 'TSH ${_formatCurrency(_filteredTotal(inv))}',
                      icon: Icons.receipt_long_rounded,
                      iconColor: Colors.lightBlueAccent.shade200,
                      divider: true,
                    ),
                  ),
                  Expanded(
                    child: _salesMiniTile(
                      label: loc.translate('sales_count'),
                      value: '${_filteredSalesCount(inv)}',
                      icon: Icons.shopping_cart_rounded,
                      iconColor: Colors.greenAccent.shade200,
                      divider: true,
                    ),
                  ),
                  Expanded(
                    child: _salesMiniTile(
                      label: loc.translate('profit'),
                      value: 'TSH ${_formatCurrency(_filteredProfit(inv))}',
                      icon: Icons.trending_up_rounded,
                      iconColor: Colors.amber.shade300,
                      divider: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _salesMiniTile({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required bool divider,
  }) =>
      Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[
                  Icon(icon, color: iconColor, size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textSecondary,
                            fontSize: ResponsiveHelper.bodyS,
                            fontWeight: FontWeight.w500)),
                  ),
                ]),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          color: textPrimary,
                          fontSize: ResponsiveHelper.bodyM,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          if (divider)
            Container(
              width: 1, height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white.withOpacity(0.15),
            ),
        ],
      );

  // Compact insight tile used inside the Leo card
  Widget _insightInlineTile(
    IconData icon, Color color, String label, String value, {required bool divider}) =>
      Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[
                  Icon(icon, color: color, size: 13),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textSecondary,
                            fontSize: ResponsiveHelper.bodyS)),
                  ),
                ]),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          color: textPrimary,
                          fontSize: ResponsiveHelper.bodyM,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          if (divider)
            Container(
              width: 1, height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white.withOpacity(0.15),
            ),
        ],
      );

  // ── Products + low-stock row ──────────────────────────────────────────────
  Widget _buildProductStatsRow(LocalizationService loc, InventoryProvider inv) {
    final int totalProducts = inv.products.length;
    final int lowStock = inv.lowStockCount;
    final int inStock = math.max(0, totalProducts - lowStock);

    return Row(
      children: <Widget>[
        Expanded(
          child: _insightTile(
            Icons.inventory_2_outlined,
            Colors.cyanAccent.shade400,
            inv.salonMode ? (loc.isSwahili ? 'Huduma na Bidhaa' : 'Services & Goods') : loc.translate('products'),
            inv.salonMode
                ? '${inv.products.where((p) => p.isService).length} ${loc.isSwahili ? 'huduma' : 'services'}  •  ${inv.products.where((p) => !p.isService).length} ${loc.isSwahili ? 'bidhaa' : 'goods'}'
                : '$totalProducts  •  ${loc.translate('active')} $inStock',
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _insightTile(
            Icons.warning_amber_rounded,
            lowStock == 0 ? Colors.greenAccent.shade400 : Colors.orangeAccent.shade200,
            inv.salonMode ? (loc.isSwahili ? 'Bidhaa zinazoisha' : 'Goods running low') : loc.translate('low_stock_alerts'),
            '$lowStock ${loc.translate('items')}',
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(LocalizationService loc, InventoryProvider inv) {
    final Size size = MediaQuery.of(context).size;
    final bool isShort = size.height < 700;

    double cardHeight = size.height * (isShort ? 0.11 : 0.14);
    cardHeight = cardHeight.clamp(100.0, 130.0);

    final double avatarSide = (size.width * 0.10).clamp(32.0, 42.0);
    final double gapLarge = isShort ? 6.0 : 8.0;
    final double gapMid = isShort ? 4.0 : 6.0;
    final double gapSmall = isShort ? 3.0 : 4.0;

    return SizedBox(
      height: cardHeight,
      child: _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: avatarSide,
                    height: avatarSide,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(avatarSide / 2),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 4),
                  const Icon(Icons.more_horiz, color: textSecondary),
                ],
              ),
              SizedBox(height: gapLarge),
              SizedBox(height: gapMid),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'TSH ${_formatCurrency(_monthSalesTotal(inv))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: isShort
                          ? (ResponsiveHelper.h2 * 0.9)
                          : ResponsiveHelper.h2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: gapSmall),
                    child: Text(
                      loc.translate('total_sales'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: isShort
                            ? (ResponsiveHelper.bodyL * 0.95)
                            : ResponsiveHelper.bodyL,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCards(LocalizationService loc, InventoryProvider inv) {
    final int totalProducts = inv.products.length;
    final int lowStock = inv.lowStockCount;
    final int inStock = math.max(0, totalProducts - lowStock);

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _buildStatCard(
                loc.translate('total_sales_today'),
                'TSH ${_formatCurrency(inv.totalSalesToday)}',
                '',
                Icons.today,
                true,
              ),
            ),
            ResponsiveHelper.horizontalSpace(4),
            Expanded(
              child: _buildStatCard(
                loc.translate('profit'),
                'TSH ${_formatCurrency(inv.profitToday)}',
                '',
                Icons.trending_up_rounded,
                true,
              ),
            ),
          ],
        ),
        ResponsiveHelper.verticalSpace(2),
        _buildStatCard(
          loc.translate('sales'),
          'TSH ${_formatCurrency(_monthSalesTotal(inv))}',
          '',
          Icons.calendar_month,
          false,
        ),
        ResponsiveHelper.verticalSpace(2),
        Row(
          children: <Widget>[
            Expanded(
              child: _buildStatCard(
                loc.translate('products'),
                '$totalProducts',
                '${loc.translate('active')} $inStock/$totalProducts',
                Icons.inventory_2_outlined,
                true,
              ),
            ),
            ResponsiveHelper.horizontalSpace(4),
            Expanded(
              child: _buildStatCard(
                loc.translate('low_stock_alerts'),
                '$lowStock',
                loc.translate('items'),
                Icons.warning_amber_rounded,
                lowStock == 0,
              ),
            ),
            ResponsiveHelper.horizontalSpace(4),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String change,
    IconData icon,
    bool isPositive,
  ) =>
      _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    icon,
                    color: textSecondary,
                    size: ResponsiveHelper.iconSizeM,
                  ),
                  const Spacer(),
                  Icon(
                    Icons.more_vert,
                    color: textSecondary,
                    size: ResponsiveHelper.iconSizeS,
                  ),
                ],
              ),
              ResponsiveHelper.verticalSpace(1.5),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: ResponsiveHelper.bodyS,
                  fontWeight: FontWeight.w500,
                ),
              ),
              ResponsiveHelper.verticalSpace(0.5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: ResponsiveHelper.bodyL,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ResponsiveHelper.verticalSpace(0.5),
              Text(
                change,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      isPositive ? Colors.green.shade300 : Colors.red.shade300,
                  fontSize: ResponsiveHelper.bodyS,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildChartSection(LocalizationService loc, InventoryProvider inv) =>
      _buildGlassCard(child: _buildChartSectionContent(loc, inv));

  Widget _buildChartSectionContent(LocalizationService loc, InventoryProvider inv) =>
      Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildMonthSelector(),
              const SizedBox(height: 24),
              SizedBox(
                height: MediaQuery.of(context).size.height < 700 ? 200 : 240,
                child: _chartLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white54, strokeWidth: 2))
                    : AnimatedBuilder(
                  animation: _chartAnimation,
                  builder: (BuildContext context, Widget? child) {
                    final List<double> points = _monthDailyTotals(inv);
                    if (points.isEmpty || points.every((v) => v == 0)) {
                      return Center(
                        child: Text(
                          loc.translate('no_chart_data'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    final List<String> labels = _monthDayLabels();
                    final double dataMax = points.reduce(math.max);
                    final double displayMax =
                        _niceCeilValue((dataMax <= 0 ? 1 : dataMax) * 1.1);
                    final double interval =
                        math.max(1, _niceStep(displayMax / 5));
                    final String maxLabel = _formatShort(displayMax);
                    final double reserved =
                        (maxLabel.length * 8 + 12).clamp(44, 72).toDouble();

                    return LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (points.length - 1).toDouble(),
                        minY: 0,
                        maxY: displayMax,
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: interval,
                          getDrawingHorizontalLine: (double value) => FlLine(
                            color: Colors.white.withOpacity(0.15),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: reserved,
                              interval: interval,
                              getTitlesWidget: (double value, meta) => Text(
                                _formatShort(value),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 1,
                              reservedSize: 40,
                              getTitlesWidget: (double value, meta) {
                                final int i = value.toInt();
                                if (i < 0 || i >= labels.length) {
                                  return const SizedBox.shrink();
                                }
                                final double width =
                                    MediaQuery.of(context).size.width - 40;
                                const double approxLabelWidth = 22;
                                final int step = labels.isEmpty
                                    ? 1
                                    : (labels.length * approxLabelWidth / width)
                                        .ceil()
                                        .clamp(1, 6);
                                if (i % step != 0) {
                                  return const SizedBox.shrink();
                                }
                                return Transform.rotate(
                                  angle: -math.pi / 6,
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      labels[i],
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(),
                          topTitles: const AxisTitles(),
                        ),
                        lineTouchData: LineTouchData(
                          handleBuiltInTouches: false,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (List<LineBarSpot> touchedSpots) =>
                                touchedSpots.map((LineBarSpot barSpot) {
                              final int i = barSpot.x.toInt();
                              final String label = (i >= 0 && i < labels.length)
                                  ? labels[i]
                                  : '';
                              return LineTooltipItem(
                                '$label\nTSH ${_formatCurrency(barSpot.y)}',
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: <LineChartBarData>[
                          LineChartBarData(
                            spots: points
                                .asMap()
                                .entries
                                .map(
                                  (MapEntry<int, double> e) => FlSpot(
                                    e.key.toDouble(),
                                    e.value * _chartAnimation.value,
                                  ),
                                )
                                .toList(),
                            isCurved: true,
                            color: Colors.white,
                            barWidth: 3,
                            dotData: FlDotData(
                              getDotPainter: (FlSpot spot, double percent,
                                      LineChartBarData bar, int index) =>
                                  FlDotCirclePainter(
                                radius: 3,
                                color: Colors.white,
                                strokeColor: Colors.white,
                              ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: <Color>[
                                  Colors.white.withOpacity(0.3),
                                  Colors.white.withOpacity(0.05),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );

  // Opens on the current month (scrolled into view); earlier months are a swipe away.
  Widget _buildMonthSelector() => MonthSelector(
        months: months,
        selectedMonth: _selectedMonth,
        selectedColor: textPrimary,
        unselectedColor: textSecondary,
        onSelected: (int month) {
          setState(() => _selectedMonth = month);
          _loadChartForMonth(month);
        },
      );

  // Divider between joined sections
  Widget _sectionDivider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          height: 2.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Colors.transparent,
                Colors.cyanAccent.withOpacity(0.5),
                Colors.white.withOpacity(0.7),
                Colors.cyanAccent.withOpacity(0.5),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
                offset: Offset.zero,
              ),
              BoxShadow(
                color: primaryBlue.withOpacity(1.0),
                blurRadius: 20,
                spreadRadius: 8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      );

  Widget _buildJoinedSections(
    LocalizationService loc,
    InventoryProvider inv, {
    bool canViewReports = false,
    bool canViewProducts = true,
    bool canViewSalesChart = true,
  }) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: <BoxShadow>[
            // Cyan top-edge glow — matches other cards
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.35),
              blurRadius: 14,
              spreadRadius: 0,
              offset: const Offset(0, -1),
            ),
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.20),
              blurRadius: 20,
              spreadRadius: 2,
              offset: Offset.zero,
            ),
            BoxShadow(
              color: primaryBlue.withOpacity(1.0),
              blurRadius: 28,
              spreadRadius: 8,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.42),
              width: 1.8,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // The value of the stock on the shelves is a shop's figure: a salon sells time, not shelves.
                // A salon's owner sees the business at a glance instead: takings, profit, bookings, who and what earns most.
                if (inv.salonMode && canSeeSalonMoneyHere(context)) ...<Widget>[SalonOverviewCard(key: ValueKey<int?>(ApiService.activeBranch)), _sectionDivider()],
                if (canViewReports && !inv.salonMode) _buildInventoryValuationContent(loc, inv),
                if (canViewReports && !inv.salonMode) _sectionDivider(),
                if (canViewProducts) _buildProductsOverviewContent(loc, inv),
                if (canViewProducts && canViewSalesChart) _sectionDivider(),
                if (canViewSalesChart) _buildChartSectionContent(loc, inv),
              ],
            ),
          ),
        ),
      );

  Widget _buildInventoryValuation(
    LocalizationService loc,
    InventoryProvider inv,
  ) =>
      _buildGlassCard(child: _buildInventoryValuationContent(loc, inv));

  Widget _buildInventoryValuationContent(
    LocalizationService loc,
    InventoryProvider inv,
  ) {
    final double totalCost = inv.totalInventoryCost;
    final double totalRevenue = inv.totalInventoryRevenue;
    final double totalProfit = inv.totalInventoryExpectedProfit;
    final int totalProducts = inv.products.length;
    final int totalUnits = inv.products.fold<int>(0, (s, p) => s + p.quantity);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.assessment_outlined,
                    color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.translate('inv_valuation_title'),
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: ResponsiveHelper.bodyL,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    LocalizationService.instance.translateWith('products_units', <Object?>[totalProducts, totalUnits]),
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: ResponsiveHelper.bodyS,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Aggregate stat tiles — same compact design as Bidhaa/insight cards
            Row(
              children: <Widget>[
                Expanded(
                  child: _insightTile(
                    Icons.shopping_cart_outlined,
                    Colors.amber.shade300,
                    loc.translate('cost'),
                    'TZS ${formatAmount(totalCost)}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _insightTile(
                    Icons.storefront_outlined,
                    Colors.lightBlueAccent.shade200,
                    loc.translate('revenue'),
                    'TZS ${formatAmount(totalRevenue)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Profit banner — same border/shadow style as the glass cards
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.35),
                    blurRadius: 14,
                    spreadRadius: 0,
                    offset: const Offset(0, -1),
                  ),
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.20),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: Offset.zero,
                  ),
                  BoxShadow(
                    color: primaryBlue.withOpacity(1.0),
                    blurRadius: 28,
                    spreadRadius: 8,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.cyanAccent.withOpacity(0.42),
                    width: 1.8,
                  ),
                ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.trending_up,
                            color: Colors.greenAccent.shade400, size: 20),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${loc.translate('expected_profit')}:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: ResponsiveHelper.bodyS,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TZS ${formatAmount(totalProfit)}',
                    style: TextStyle(
                      color: Colors.greenAccent.shade400,
                      fontSize: ResponsiveHelper.bodyL,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ),
            const SizedBox(height: 14),
            // Per-product breakdown table — sorted by qty desc (top sellers first)
            // Flexible, so a narrow phone or a large system font shortens the text instead of
            // overflowing the row.
            Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    loc.translate('profit_margins_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: ResponsiveHelper.bodyM,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    loc.translate('top_products_sorted'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: ResponsiveHelper.bodyS,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // The same table the full "Faida kwa Bidhaa" screen shows. The dashboard lists the
            // first rows only and points to that screen for the rest.
            ProfitByProductTable(
              products: rankedForProfit(inv.products),
              limit: kProfitDashboardRows,
            ),
            // Live only when there are more products than fit above; otherwise muted.
            ProfitSeeAllButton(
              total: inv.products.length,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProfitByProductScreen(),
                ),
              ),
            ),
          ],
        ),
      );
  }

  Widget _valuationTile(
      String label, String value, Color color, IconData icon) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              color.withOpacity(0.18),
              color.withOpacity(0.07),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4), width: 1.2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withOpacity(0.30),
              blurRadius: 16,
              spreadRadius: 1,
              offset: Offset.zero,
            ),
            BoxShadow(
              color: primaryBlue.withOpacity(0.95),
              blurRadius: 20,
              spreadRadius: 6,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: textSecondary,
                fontSize: ResponsiveHelper.bodyS,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: ResponsiveHelper.bodyL,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildProductsOverview(
    LocalizationService loc,
    InventoryProvider inv,
  ) =>
      _buildGlassCard(child: _buildProductsOverviewContent(loc, inv));

  Widget _buildProductsOverviewContent(
    LocalizationService loc,
    InventoryProvider inv,
  ) =>
      Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                inv.salonMode ? (loc.isSwahili ? 'Muhtasari wa Huduma' : 'Services Overview') : loc.translate('products_overview'),
                style: TextStyle(
                  color: textPrimary,
                  fontSize: ResponsiveHelper.bodyL,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ResponsiveHelper.verticalSpace(1.5),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 6,
                    child: Text(
                      inv.salonMode ? (loc.isSwahili ? 'Huduma' : 'Service') : loc.translate('product'),
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: ResponsiveHelper.bodyS,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      inv.salonMode ? (loc.isSwahili ? 'Muda' : 'Time') : loc.translate('stock'),
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: ResponsiveHelper.bodyS,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      loc.translate('sale'),
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: ResponsiveHelper.bodyS,
                      ),
                    ),
                  ),
                ],
              ),
              ResponsiveHelper.verticalSpace(1),
              if ((inv.salonMode ? inv.products.where((p) => p.isService) : inv.products).isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    loc.translate('no_data'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              else
                // A salon's overview lists its services (with how long each takes), in the same table.
                ...(inv.salonMode ? inv.products.where((p) => p.isService) : inv.products).take(5).map(
                      (p) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              flex: 6,
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 28.w,
                                    height: 28.w,
                                    decoration: const BoxDecoration(
                                      color: Colors.white24,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      p.isService ? Icons.content_cut_rounded : Icons.inventory_2_outlined,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Expanded(
                                    child: AutoSizeText(
                                      p.name,
                                      maxLines: 1,
                                      minFontSize: 10,
                                      style: const TextStyle(
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                p.isService ? (p.durationMinutes == null ? '—' : '${p.durationMinutes} min') : '${p.quantity}',
                                style: const TextStyle(color: textPrimary),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: AutoSizeText(
                                'TSH ${_formatCurrency(p.sellingPrice)}',
                                maxLines: 1,
                                minFontSize: 10,
                                style: const TextStyle(color: textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        );

  // ---- data helpers -------------------------------------------------------

  List<InvSale> _salesForSelectedMonth(InventoryProvider inv) {
    final int year = DateTime.now().year;
    return inv.sales
        .where((InvSale s) =>
            s.createdAt.year == year && s.createdAt.month == _selectedMonth)
        .toList();
  }

  double _monthSalesTotal(InventoryProvider inv) => _salesForSelectedMonth(inv)
      .fold<double>(0, (double sum, InvSale s) => sum + s.total);

  int get _daysInSelectedMonth =>
      DateTime(DateTime.now().year, _selectedMonth + 1, 0).day;

  List<double> _monthDailyTotals(InventoryProvider inv) {
    // Prefer backend-aggregated monthly chart data (complete, no pagination gaps)
    final cached = inv.cachedMonthlyChart(DateTime.now().year, _selectedMonth);
    if (cached != null && cached.isNotEmpty) return cached;
    // Fallback: derive from whatever sales are in memory (may be incomplete)
    final List<double> totals = List<double>.filled(_daysInSelectedMonth, 0);
    for (final InvSale s in _salesForSelectedMonth(inv)) {
      final int i = s.createdAt.day - 1;
      if (i >= 0 && i < totals.length) {
        totals[i] += s.total;
      }
    }
    return totals;
  }

  List<String> _monthDayLabels() =>
      List<String>.generate(_daysInSelectedMonth, (int i) => '${i + 1}');

  String _formatCurrency(num amount) {
    final double value = amount.toDouble();
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }

  String _formatShort(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).round()}K';
    }
    return value.round().toString();
  }

  double _niceStep(double raw) {
    if (raw <= 0) {
      return 1;
    }
    final double magnitude =
        math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final double residual = raw / magnitude;
    if (residual <= 1) {
      return magnitude;
    }
    if (residual <= 2) {
      return 2 * magnitude;
    }
    if (residual <= 5) {
      return 5 * magnitude;
    }
    return 10 * magnitude;
  }

  double _niceCeilValue(double raw) {
    final double step = _niceStep(raw / 5);
    return (raw / step).ceil() * step;
  }
}

// ── Quick-chip data model ─────────────────────────────────────────────────────
class _QuickChip {
  const _QuickChip(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

// ── Date filter bottom sheet ──────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.current,
    required this.onSelect,
    this.customStart,
    this.customEnd,
    this.branches = const <Map<String, dynamic>>[],
    this.branchId,
    this.onBranch,
  });
  final _DateFilter current;
  final DateTime? customStart;
  final DateTime? customEnd;
  final void Function(_DateFilter, DateTime?, DateTime?) onSelect;

  /// The salon's branches to choose from (empty = no branch choice), the one chosen now, and what to do when it changes.
  final List<Map<String, dynamic>> branches;
  final int? branchId;
  final void Function(int? id, String? name)? onBranch;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _DateFilter _selected;
  DateTime? _start;
  DateTime? _end;

  static const _optionFilters = <({_DateFilter filter, String key, IconData icon})>[
    (filter: _DateFilter.today,  key: 'today',        icon: Icons.today_rounded),
    (filter: _DateFilter.week,   key: 'this_week',    icon: Icons.view_week_rounded),
    (filter: _DateFilter.month,  key: 'this_month',   icon: Icons.calendar_month_rounded),
    (filter: _DateFilter.year,   key: 'this_year',    icon: Icons.calendar_today_rounded),
    (filter: _DateFilter.custom, key: 'custom_range', icon: Icons.date_range_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    _start = widget.customStart;
    _end = widget.customEnd;
    _branch = widget.branchId;
  }

  int? _branch;

  Widget _branchTile(final String label, final int? id, final String keyName) {
    final bool active = _branch == id;

    return GestureDetector(
      key: Key(keyName),
      onTap: () => setState(() => _branch = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: active ? ThemeConstants.primaryBlue.withOpacity(0.35) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? ThemeConstants.primaryBlue : Colors.white12, width: active ? 1.5 : 1),
        ),
        child: Row(children: <Widget>[
          Icon(Icons.store_mall_directory_outlined, color: active ? Colors.white : Colors.white54, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 14, fontWeight: active ? FontWeight.w700 : FontWeight.w400))),
          if (active) const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        ]),
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: (_start != null && _end != null)
          ? DateTimeRange(start: _start!, end: _end!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 6)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: ThemeConstants.primaryBlue,
            onPrimary: Colors.white,
            surface: Color(0xFF1E3A5F),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _start = picked.start; _end = picked.end; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A2E45),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Drag handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(loc.translate('choose_period'),
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 16),
          // Option tiles
          ..._optionFilters.map((opt) {
            final bool active = _selected == opt.filter;
            final bool isCustom = opt.filter == _DateFilter.custom;
            final String label = loc.translate(opt.key);
            return GestureDetector(
              onTap: () async {
                setState(() => _selected = opt.filter);
                if (isCustom) await _pickCustomRange();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: active
                      ? ThemeConstants.primaryBlue.withOpacity(0.35)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? ThemeConstants.primaryBlue : Colors.white12,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(opt.icon,
                        color: active ? Colors.white : Colors.white54, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isCustom && _start != null && _end != null
                            ? '$label  ${_start!.day}/${_start!.month}/${_start!.year} – ${_end!.day}/${_end!.month}/${_end!.year}'
                            : label,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (active)
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 18),
                  ],
                ),
              ),
            );
          }),
          if (widget.branches.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(LocalizationService.instance.isSwahili ? 'Tawi' : 'Branch', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _branchTile(LocalizationService.instance.isSwahili ? 'Matawi yote' : 'All branches', null, 'filter_branch_all'),
            for (final Map<String, dynamic> br in widget.branches) _branchTile('${br['name']}', (br['id'] as num).toInt(), 'filter_branch_${br['id']}'),
          ],
          const SizedBox(height: 8),
          // Apply button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeConstants.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                if (widget.onBranch != null) {
                  String? name;
                  for (final Map<String, dynamic> br in widget.branches) {
                    if ((br['id'] as num).toInt() == _branch) name = '${br['name']}';
                  }
                  widget.onBranch!(_branch, name);
                }
                widget.onSelect(_selected, _start, _end);
                Navigator.of(context).pop();
              },
              child: Text(loc.translate('apply'), style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
