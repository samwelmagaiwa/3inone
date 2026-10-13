import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../../services/inventory_export_service.dart';
import '../widgets/inventory_widgets.dart';

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
  }

  Future<void> _load() async {
    await context.read<DepotProvider>().fetchReports();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final DepotProvider depot = context.watch<DepotProvider>();
    final bool crates = depot.capabilities.useCrates;
    final List<InvReportMeta> rows = crates
        ? depot.reports
        : depot.reports.where((InvReportMeta r) => r.key != 'crates_position').toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : RefreshIndicator(
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
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220.w,
                          mainAxisSpacing: 8.h,
                          crossAxisSpacing: 8.w,
                          mainAxisExtent: 80.h,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (_, int i) => _ReportTile(
                          report: rows[i],
                          icon:
                              _icons[rows[i].key] ?? Icons.description_outlined,
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
