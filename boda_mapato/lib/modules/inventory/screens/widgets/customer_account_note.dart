import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_customer_debt.dart';
import '../../providers/depot_provider.dart';
import 'customer_debt_card.dart';

/// Under the customer on the till: what they already owe (old debt, new debt and the total) and what this sale on credit adds, so the
/// owner sees the whole account before agreeing to more credit. Nothing shows for a customer who owes nothing and a sale that is paid.
class CustomerAccountNote extends StatefulWidget {
  const CustomerAccountNote({super.key, required this.customerId, required this.thisSale});

  final int customerId;

  /// The part of the sale being made that will be owed (0 for none).
  final double thisSale;

  @override
  State<CustomerAccountNote> createState() => _CustomerAccountNoteState();
}

class _CustomerAccountNoteState extends State<CustomerAccountNote> {
  CustomerDebtSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(final CustomerAccountNote old) {
    super.didUpdateWidget(old);
    if (old.customerId != widget.customerId) {
      _summary = null;
      _load();
    }
  }

  Future<void> _load() async {
    final int id = widget.customerId;
    final CustomerDebtSummary? s = await context.read<DepotProvider>().fetchCustomerDebtSummary(id);
    if (mounted && id == widget.customerId) setState(() => _summary = s);
  }

  @override
  Widget build(final BuildContext context) {
    final CustomerDebtSummary? s = _summary;
    if (s == null || (!s.hasAny && widget.thisSale <= 0)) return const SizedBox.shrink();

    return Padding(
      key: const ValueKey<String>('customer_account_note'),
      padding: EdgeInsets.only(top: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(LocalizationService.instance.translate('cd_account_title'), style: ThemeConstants.captionStyle.copyWith(color: Colors.white70, fontWeight: FontWeight.w700)),
          SizedBox(height: 4.h),
          CustomerDebtCard(summary: s, thisSale: widget.thisSale),
        ],
      ),
    );
  }
}
