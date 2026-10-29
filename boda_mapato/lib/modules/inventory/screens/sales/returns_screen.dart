import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../widgets/inventory_widgets.dart';

/// Area 5 — returns and cancellations awaiting approval, and parked sales.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<DepotProvider>().returns.isEmpty &&
        context.read<DepotProvider>().parkedSales.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final DepotProvider depot = context.read<DepotProvider>();
    await Future.wait<void>(<Future<void>>[
      depot.fetchReturns(),
      depot.fetchParkedSales(),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    if (_loading) {
      return const Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        body: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }

    return InvTabScaffold(
      title: '',
      tabs: <String>[
        loc.translate('returns'),
        loc.translate('parked_sales'),
      ],
      views: <Widget>[
        _ReturnsTab(onRefresh: _load),
        _ParkedTab(onRefresh: _load),
      ],
    );
  }
}

class _ReturnsTab extends StatelessWidget {
  const _ReturnsTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvSaleReturn> rows = context.watch<DepotProvider>().returns;
    final AuthProvider auth = context.read<AuthProvider>();
    // Matches the backend gate on POST inventory/returns/{id}/decide
    // (inv_manage_sales) -- this used to check inv_manage_stock, which
    // could show the button to someone the API would then 403, or hide it
    // from someone who legitimately holds inv_manage_sales without
    // inv_manage_stock. fromUser (not fromRole) also honours a per-user
    // explicit grant, not just the role default.
    final bool canApprove = UserPermissions.fromUser(
      userRole: auth.user?.role ?? 'viewer',
      explicitGrants: auth.user?.permissions,
    ).has('inv_manage_sales');

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: 60.h),
                InvEmptyState(
                  icon: Icons.assignment_return_outlined,
                  message: loc.translate('no_returns'),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
              itemCount: rows.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (BuildContext context, int i) => _ReturnCard(
                saleReturn: rows[i],
                canApprove: canApprove,
                onDecide: (bool approve) async {
                  await context
                      .read<DepotProvider>()
                      .decideReturn(rows[i].id, approve: approve);
                  await onRefresh();
                },
              ),
            ),
    );
  }
}

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({
    required this.saleReturn,
    required this.canApprove,
    required this.onDecide,
  });

  final InvSaleReturn saleReturn;
  final bool canApprove;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final (Color color, String label) = switch (saleReturn.status) {
      'approved' => (ThemeConstants.successGreen, loc.translate('approved')),
      'rejected' => (ThemeConstants.errorRed, loc.translate('rejected')),
      _ => (ThemeConstants.warningAmber, loc.translate('pending')),
    };

    return Container(
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AutoSizeText(
                  '${loc.translate(saleReturn.type)} · ${saleReturn.saleNumber}',
                  maxLines: 1,
                  minFontSize: 10,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 8.w),
              InvBadge(label: label, color: color),
            ],
          ),
          SizedBox(height: 6.h),
          InvKeyValueWrap(entries: <String, String>{
            loc.translate('amount'):
                'TSH ${saleReturn.amount.toStringAsFixed(0)}',
            loc.translate('reference'): saleReturn.reference,
            if (saleReturn.reason.isNotEmpty)
              loc.translate('reason'): saleReturn.reason,
          }),
          if (canApprove && saleReturn.isPending) ...<Widget>[
            SizedBox(height: 10.h),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: ThemeConstants.errorRed),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: () => onDecide(false),
                    child: AutoSizeText(
                      loc.translate('reject'),
                      maxLines: 1,
                      minFontSize: 9,
                      style: const TextStyle(color: ThemeConstants.errorText),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.successGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: () => onDecide(true),
                    child: AutoSizeText(
                      loc.translate('approve'),
                      maxLines: 1,
                      minFontSize: 9,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ParkedTab extends StatelessWidget {
  const _ParkedTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvParkedSale> rows = context.watch<DepotProvider>().parkedSales;

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: 60.h),
                InvEmptyState(
                  icon: Icons.pause_circle_outline,
                  message: loc.translate('no_parked_sales'),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
              itemCount: rows.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (BuildContext context, int i) {
                final InvParkedSale p = rows[i];

                return Container(
                  decoration: ThemeConstants.glassCardDecoration,
                  padding: EdgeInsets.all(12.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: AutoSizeText(
                              p.reference,
                              maxLines: 1,
                              minFontSize: 10,
                              overflow: TextOverflow.ellipsis,
                              style: ThemeConstants.bodyStyle
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          InvBadge(
                            label: 'TSH ${p.total.toStringAsFixed(0)}',
                            color: ThemeConstants.primaryCyan,
                          ),
                        ],
                      ),
                      SizedBox(height: 6.h),
                      InvKeyValueWrap(entries: <String, String>{
                        if (p.customerName.isNotEmpty)
                          loc.translate('customer'): p.customerName,
                        loc.translate('date'):
                            '${p.createdAt.day}/${p.createdAt.month}/${p.createdAt.year}',
                        if (p.parkedByName.isNotEmpty)
                          loc.translate('staff'): p.parkedByName,
                      }),
                      SizedBox(height: 10.h),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                              ),
                              onPressed: () async {
                                await context
                                    .read<DepotProvider>()
                                    .discardParkedSale(p.id);
                                await onRefresh();
                              },
                              child: AutoSizeText(
                                loc.translate('discard'),
                                maxLines: 1,
                                minFontSize: 9,
                                style: ThemeConstants.captionStyle,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ThemeConstants.primaryOrange,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                              ),
                              onPressed: () async {
                                await context
                                    .read<DepotProvider>()
                                    .resumeParkedSale(p.id);
                                await onRefresh();
                              },
                              child: AutoSizeText(
                                loc.translate('resume'),
                                maxLines: 1,
                                minFontSize: 9,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
