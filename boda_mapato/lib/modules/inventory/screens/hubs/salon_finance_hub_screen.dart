import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_permissions.dart';
import '../../../../services/localization_service.dart';
import '../salon/cashbook_screen.dart';
import '../salon/export_screen.dart';
import '../salon/payroll_screen.dart';
import '../salon/profit_loss_screen.dart';
import '../salon/salon_expenses_screen.dart';
import '../widgets/inventory_widgets.dart';

/// The salon's money in one place: profit and loss, what was spent, and what staff are paid. (Daily cash is in Reports.)
/// Only people allowed to see reports or expenses get this section, and the server checks again on every call.
class SalonFinanceHubScreen extends StatelessWidget {
  const SalonFinanceHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return InvTabScaffold(
      title: '',
      tabs: <String>[
        sw ? 'Faida na hasara' : 'Profit & loss',
        sw ? 'Matumizi' : 'Expenses',
        sw ? 'Mishahara' : 'Payroll',
        sw ? 'Kitabu cha pesa' : 'Cashbook',
        sw ? 'Hamisha' : 'Export',
      ],
      views: const <Widget>[
        ProfitLossScreen(),
        SalonExpensesScreen(),
        PayrollScreen(),
        CashbookScreen(),
        ExportScreen(),
      ],
      tabPermissions: <bool Function(UserPermissions)?>[
        (UserPermissions p) => p.has('inv_view_reports'),
        (UserPermissions p) => p.has('inv_view_expenses'),
        (UserPermissions p) => p.has('inv_view_reports'),
        (UserPermissions p) => p.has('inv_view_reports'),
        (UserPermissions p) => p.has('inv_view_reports'),
      ],
    );
  }
}
