import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/api_service.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../../services/inventory_export_service.dart';
import '../widgets/inventory_widgets.dart';
import '../salon/salon_mode.dart';

/// Area 11 — the 12 standard reports. One list, one viewer: every report
/// arrives in the same shape, so a single table renders all of them.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = false;

  static const Map<String, IconData> _icons = <String, IconData>{
    'daily_sales': Icons.today_outlined,
    'sales_detail': Icons.receipt_long_outlined,
    'product_profitability': Icons.trending_up_rounded,
    'stock_valuation': Icons.savings_outlined,
    'stock_movements': Icons.swap_vert_outlined,
    'stock_count_variance': Icons.fact_check_outlined,
    'damages': Icons.report_problem_outlined,
    'debtors_ageing': Icons.hourglass_bottom_outlined,
    'collections': Icons.payments_outlined,
    'crates_position': Icons.inbox_outlined,
    'purchases': Icons.local_shipping_outlined,
    'cash_reconciliation': Icons.point_of_sale_outlined,
  };

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<DepotProvider>().reports.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _readLocal();
  }

  /// What this phone remembers when the server could not keep the choice (an older server): one list per person and service.
  Set<String> _local = <String>{};
  String get _localKey =>
      'hidden_reports_${context.read<AuthProvider>().user?.id ?? ''}_${ApiService.activeService ?? 'inventory'}';

  Future<void> _readLocal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(
        () => _local = (prefs.getStringList(_localKey) ?? <String>[]).toSet());
  }

  Future<void> _load() async {
    await context.read<DepotProvider>().fetchReports();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  /// The business's own choice when the server keeps it (it then holds for every phone); else this phone's.
  Set<String> _hiddenKeys(Map<String, String> settings) =>
      settings.containsKey('hidden_reports')
          ? (settings['hidden_reports'] ?? '')
              .split(',')
              .map((String k) => k.trim())
              .where((String k) => k.isNotEmpty)
              .toSet()
          : _local;

  /// The owner picks which reports this business sees; the choice is saved with the business's settings.
  Future<void> _customize(
      List<InvReportMeta> applicable, Set<String> hidden) async {
    final DepotProvider depot = context.read<DepotProvider>();
    final Set<String> picked = <String>{...hidden};
    final bool? save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.primaryBlue,
      builder: (BuildContext sheet) => StatefulBuilder(
        builder: (BuildContext _, StateSetter set) {
          final LocalizationService loc = LocalizationService.instance;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 4.h),
                  child: Text(
                      loc.isSwahili
                          ? 'Chagua ripoti zinazoonekana'
                          : 'Choose the reports you see',
                      style: ThemeConstants.bodyStyle
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Text(
                      loc.isSwahili
                          ? 'Zilizozimwa hazitaonekana kwa wafanyakazi wote wa biashara hii.'
                          : 'Switched-off reports are hidden for everyone in this business.',
                      style: ThemeConstants.bodyStyle
                          .copyWith(fontSize: 12.sp, color: Colors.white70)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final InvReportMeta r in applicable)
                        SwitchListTile(
                          value: !picked.contains(r.key),
                          onChanged: (bool on) => set(() =>
                              on ? picked.remove(r.key) : picked.add(r.key)),
                          title: Text(
                            loc.translate('report_${r.key}') ==
                                    'report_${r.key}'
                                ? r.title
                                : loc.translate('report_${r.key}'),
                            style: ThemeConstants.bodyStyle,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheet, true),
                        child: Text(loc.translate('save'))),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (save != true) return;
    final List<String> chosen = picked.toList()..sort();
    final String localKey = _localKey; // read now: the screen may be gone after the server answers
    final bool ok = await depot
        .saveSettings(<String, String>{'hidden_reports': chosen.join(',')});
    final bool sw = LocalizationService.instance.isSwahili;
    if (ok && depot.settings.containsKey('hidden_reports')) {
      // kept by the server: every phone of the business has it
      if (mounted)
        ThemeConstants.showInfoSnackBar(
            context,
            sw
                ? 'Imehifadhiwa kwa biashara nzima.'
                : 'Saved for the whole business.');
      return;
    }
    // The server could not keep it (an older server does not know this setting): keep it on this phone so the choice is not lost.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(localKey, chosen);
    if (!mounted) return;
    setState(() => _local = chosen.toSet());
    ThemeConstants.showInfoSnackBar(
        context,
        sw
            ? 'Imehifadhiwa kwenye simu hii tu. Seva ikisasishwa, itahifadhiwa kwa biashara nzima.'
            : 'Saved on this phone only. Once the server is updated it can be saved for the whole business.');
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final DepotProvider depot = context.watch<DepotProvider>();
    final bool crates = depot.capabilities.useCrates;
    // A salon reports on sales, clients' debts, cash and what its services and goods earn: not on stock, purchases or crates.
    const Set<String> shopOnly = <String>{
      'stock_valuation',
      'stock_movements',
      'stock_count_variance',
      'damages',
      'purchases',
      'crates_position'
    };
    final bool salon = isSalonMode(context);
    // What applies to this kind of business, then what its owner chose to hide (a business setting, so every
    // phone of the business shows the same list).
    final List<InvReportMeta> applicable = depot.reports
        .where((InvReportMeta r) => salon
            ? !shopOnly.contains(r.key)
            : (crates || r.key != 'crates_position'))
        .toList(growable: false);
    final Set<String> hidden = _hiddenKeys(depot.settings);
    final List<InvReportMeta> rows = applicable
        .where((InvReportMeta r) => !hidden.contains(r.key))
        .toList(growable: false);
    final bool canConfigure = context.select<AuthProvider, bool>(
        (AuthProvider a) => a.permissions.has('inv_manage_settings'));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : Column(
                children: <Widget>[
                  if (canConfigure && applicable.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 12.w, top: 8.h),
                        child: ElevatedButton.icon(
                          key: const Key('choose_reports_button'),
                          onPressed: () => _customize(applicable, hidden),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ThemeConstants.primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.w, vertical: 10.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24.r),
                              side: const BorderSide(color: Colors.white38),
                            ),
                          ),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: Text(
                              loc.isSwahili
                                  ? 'Chagua ripoti'
                                  : 'Choose reports',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      backgroundColor: Colors.white,
                      color: ThemeConstants.primaryBlue,
                      child: rows.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: <Widget>[
                                SizedBox(height: 70.h),
                                InvEmptyState(
                                  icon: Icons.bar_chart_outlined,
                                  message: loc.translate('no_reports'),
                                ),
                              ],
                            )
                          : GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              padding: EdgeInsets.all(12.w),
                              // A fixed aspect ratio makes tiles too short on a
                              // narrow screen; pin the height instead so the tile
                              // always has room for its two-line title.
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220.w,
                                mainAxisSpacing: 8.h,
                                crossAxisSpacing: 8.w,
                                mainAxisExtent: 80.h,
                              ),
                              itemCount: rows.length,
                              itemBuilder: (_, int i) => _ReportTile(
                                report: rows[i],
                                icon: _icons[rows[i].key] ??
                                    Icons.description_outlined,
                                onTap: () => Navigator.push<void>(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => ReportViewerScreen(
                                      reportKey: rows[i].key,
                                      title: rows[i].title,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.icon,
    required this.onTap,
  });

  final InvReportMeta report;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final translatedTitle = loc.translate('report_${report.key}');
    // Fallback: if key not found the service returns the key itself; use backend title then.
    final title = (translatedTitle == 'report_${report.key}')
        ? report.title
        : translatedTitle;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Container(
              width: 28.w,
              height: 28.w,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(icon, color: Colors.white, size: 15.sp),
            ),
            Flexible(
              child: AutoSizeText(
                title,
                maxLines: 2,
                minFontSize: 9,
                overflow: TextOverflow.ellipsis,
                style: ThemeConstants.bodyStyle
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs one report over a date range and renders it as a scrollable table.
class ReportViewerScreen extends StatefulWidget {
  const ReportViewerScreen({
    required this.reportKey,
    required this.title,
    super.key,
  });

  final String reportKey;
  final String title;

  @override
  State<ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends State<ReportViewerScreen> {
  InvReport? _report;
  bool _loading = true;
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    final InvReport? r = await context
        .read<DepotProvider>()
        .runReport(widget.reportKey, from: _from, to: _to);
    if (mounted) {
      setState(() {
        _report = r;
        _loading = false;
      });
    }
  }

  static final NumberFormat _numberFmt = NumberFormat('#,##0.##');

  String _cell(dynamic value) {
    if (value == null) {
      return '—';
    }
    // Backend numeric columns arrive as real num when PHP computed them
    // (e.g. a Collection::sum() total) but as numeric STRINGS when they
    // come straight off a raw SQL aggregate like SUM(...) -- MySQL/PDO
    // returns those unquoted-looking values as strings (e.g. "14640000.00").
    // Parse either shape the same way so rows and totals format identically
    // instead of one being a clean number and the other falling through to
    // raw, undertrimmed text.
    final num? n = value is num ? value : num.tryParse(value.toString());
    if (n != null) {
      return _numberFmt.format(n);
    }
    final String text = value.toString();
    // Trim ISO timestamps down to the date.
    return text.length > 10 && text.contains('T')
        ? text.split('T').first
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InvReport? r = _report;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: AutoSizeText(
          () {
            final t = loc.translate('report_${widget.reportKey}');
            return (t == 'report_${widget.reportKey}') ? widget.title : t;
          }(),
          maxLines: 1,
          minFontSize: 12,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeConstants.textPrimary,
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: loc.translate('date_range'),
            icon: const Icon(Icons.date_range, color: Colors.white70),
            onPressed: _pickRange,
          ),
          IconButton(
            tooltip: loc.translate('export_pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined,
                color: Colors.white70),
            onPressed: _report == null ? null : () => _export(pdf: true),
          ),
          IconButton(
            tooltip: loc.translate('export_excel'),
            icon: const Icon(Icons.grid_on_outlined, color: Colors.white70),
            onPressed: _report == null ? null : () => _export(pdf: false),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : r == null
                ? InvEmptyState(
                    icon: Icons.error_outline,
                    message: loc.translate('report_failed'),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
                        child: Container(
                          decoration: ThemeConstants.glassCardDecoration,
                          padding: EdgeInsets.all(10.w),
                          child: InvKeyValueWrap(entries: <String, String>{
                            loc.translate('period'): '${r.from} → ${r.to}',
                            loc.translate('rows'): '${r.rows.length}',
                            ...r.meta.map((String k, dynamic v) => MapEntry(
                                  k.replaceAll('_', ' '),
                                  _cell(v),
                                )),
                          }),
                        ),
                      ),
                      Expanded(
                        child: r.isEmpty
                            ? InvEmptyState(
                                icon: Icons.inbox_outlined,
                                message: loc.translate('no_data_for_period'),
                              )
                            : Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8.w),
                                child: InvDataTable(
                                  columns: r.columns
                                      .map((InvReportColumn c) => c.label)
                                      .toList(),
                                  rows: r.rows
                                      .map((Map<String, dynamic> row) => r
                                          .columns
                                          .map((InvReportColumn c) =>
                                              _cell(row[c.field]))
                                          .toList())
                                      .toList(),
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  static const InventoryExportService _exportService = InventoryExportService();

  Future<void> _export({required bool pdf}) async {
    final LocalizationService loc = LocalizationService.instance;
    final InvReport? report = _report;
    if (report == null) return;

    try {
      final File file = pdf
          ? await _exportService.reportToPdf(report)
          : await _exportService.reportToExcel(report);
      if (!mounted) return;
      await _exportService.shareFile(file, subject: report.title);
    } on Exception {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(
            context, loc.translate('export_failed'));
      }
    }
  }

  Future<void> _pickRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 1),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    await _run();
  }
}
