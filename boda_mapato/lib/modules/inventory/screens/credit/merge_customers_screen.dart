import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_customer_debt.dart';
import '../../providers/depot_provider.dart';
import '../widgets/inv_action_button.dart';

/// Customers that look like one person saved more than once: in each group the owner picks the one to keep, and the others are merged
/// onto it (their sales, debts and payments move; they go to the Trash). The customer account then shows everything in one place.
class MergeCustomersScreen extends StatefulWidget {
  const MergeCustomersScreen({super.key});

  @override
  State<MergeCustomersScreen> createState() => _MergeCustomersScreenState();
}

class _MergeCustomersScreenState extends State<MergeCustomersScreen> {
  /// The chosen customer to keep, by the first customer id of each group (the group's identity while the list changes).
  final Map<int, int> _keep = <int, int>{};
  final Set<int> _busy = <int>{};

  static String _tsh(final double v) => 'TSH ${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (final Match m) => ',')}';

  int _key(final DuplicateGroup g) => g.customers.map((DuplicateCustomer c) => c.id).reduce((int a, int b) => a < b ? a : b);

  Future<void> _merge(final DuplicateGroup group) async {
    final LocalizationService loc = LocalizationService.instance;
    final int key = _key(group);
    final DuplicateCustomer keep = group.customers.firstWhere((DuplicateCustomer c) => c.id == (_keep[key] ?? group.suggested.id));
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(loc.translate('dup_title')),
        content: Text(loc.translate('dup_confirm').replaceAll('{keep}', keep.name)),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.translate('cancel'))),
          FilledButton(key: const ValueKey<String>('merge_confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(loc.translate('dup_merge'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _busy.add(key));
    final DepotProvider depot = context.read<DepotProvider>();
    String? error;
    for (final DuplicateCustomer other in group.customers.where((DuplicateCustomer c) => c.id != keep.id)) {
      error = await depot.mergeCustomers(keepId: keep.id, dropId: other.id);
      if (error != null) break;
    }
    if (!mounted) return;
    setState(() => _busy.remove(key));
    if (error != null) {
      ThemeConstants.showErrorSnackBar(context, error);
    } else {
      ThemeConstants.showSuccessSnackBar(context, loc.translate('dup_done'));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<DuplicateGroup> groups = context.watch<DepotProvider>().duplicateGroups;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: Text(loc.translate('dup_title'), style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 19.sp, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: groups.isEmpty
            ? Center(child: Text(loc.translate('dup_none'), key: const ValueKey<String>('merge_none'), style: ThemeConstants.captionStyle))
            : ListView(
                padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 24.h),
                children: <Widget>[
                  Padding(padding: EdgeInsets.only(bottom: 10.h), child: Text(loc.translate('dup_intro'), style: ThemeConstants.captionStyle)),
                  for (final DuplicateGroup g in groups) _group(loc, g),
                ],
              ),
      ),
    );
  }

  Widget _group(final LocalizationService loc, final DuplicateGroup g) {
    final int key = _key(g);
    final int chosen = g.customers.any((DuplicateCustomer c) => c.id == _keep[key]) ? _keep[key]! : g.suggested.id;
    return Container(
      key: ValueKey<String>('merge_group_$key'),
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(color: ThemeConstants.invFill, borderRadius: BorderRadius.circular(14.r), border: Border.all(color: ThemeConstants.invBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final DuplicateCustomer c in g.customers)
            InkWell(
              key: ValueKey<String>('merge_pick_${c.id}'),
              borderRadius: BorderRadius.circular(10.r),
              onTap: () => setState(() => _keep[key] = c.id),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6.h),
                child: Row(
                  children: <Widget>[
                    Icon(c.id == chosen ? Icons.radio_button_checked : Icons.radio_button_off, color: c.id == chosen ? ThemeConstants.successGreen : Colors.white54, size: 20.sp),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            <String>[
                              if (c.phone.isNotEmpty) c.phone,
                              loc.translate('dup_sales').replaceAll('{n}', '${c.sales}'),
                              if (c.owes > 0) '${loc.translate('dup_owes')} ${_tsh(c.owes)}',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ThemeConstants.captionStyle,
                          ),
                        ],
                      ),
                    ),
                    if (c.id == chosen) Text(loc.translate('dup_keep'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.successGreen, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          SizedBox(height: 6.h),
          InvActionButton(
            key: ValueKey<String>('merge_go_$key'),
            label: loc.translate('dup_merge'),
            icon: Icons.merge_type_rounded,
            color: ThemeConstants.successGreen,
            arrow: false,
            onPressed: _busy.contains(key) ? null : () => _merge(g),
          ),
        ],
      ),
    );
  }
}
