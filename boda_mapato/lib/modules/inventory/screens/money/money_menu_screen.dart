import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../credit/credit_screen.dart';
import 'debts_screen.dart';
import '../trash/trash_screen.dart';
import 'monthly_report_screen.dart';

/// One place for the owner's money: who owes the business, what the business owes, and how the month went. Each choice says in a
/// sentence what it is for, so someone who has never kept books knows where to go.
class MoneyMenuScreen extends StatelessWidget {
  const MoneyMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final UserPermissions perms = context.watch<AuthProvider>().permissions;

    final List<Widget> cards = <Widget>[
      if (perms.has('inv_view_credit'))
        _MoneyCard(
          key: const ValueKey<String>('money_credit'),
          icon: Icons.credit_card_outlined,
          color: const Color(0xFF20B8CE),
          title: sw ? 'Wateja na mikopo' : 'Customers & credit',
          text: sw ? 'Nani anadaiwa, kupokea malipo, na ripoti ya kila mteja (wiki, mwezi au mwaka).' : 'Who owes you, taking payments, and a report for each customer (week, month or year).',
          open: () => Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => ThemeConstants.buildScaffold(title: sw ? 'Wateja na mikopo' : 'Customers & credit', body: const CreditScreen())),
          ),
        ),
      if (perms.has('inv_view_credit'))
        _MoneyCard(
          key: const ValueKey<String>('money_debts'),
          icon: Icons.account_balance_wallet_outlined,
          color: ThemeConstants.warningAmber,
          title: sw ? 'Madeni' : 'Debts',
          text: sw ? 'Madeni unayodai (hata ya zamani) na madeni unayodaiwa, sehemu moja.' : 'What people owe you (even from before the app) and what you owe, in one place.',
          open: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const DebtsScreen())),
        ),
      if (perms.has('inv_view_reports'))
        _MoneyCard(
          key: const ValueKey<String>('money_monthly'),
          icon: Icons.insights_outlined,
          color: const Color(0xFF8B5CF6),
          title: sw ? 'Ripoti ya mwezi' : 'Monthly report',
          text: sw ? 'Faida, bidhaa zilizopo, mtaji, lengo lako, ulinganisho na mwezi uliopita, na wapi uboreshe.' : 'Profit, stock, capital, your target, how you did against last month, and where to improve.',
          open: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const MonthlyReportScreen())),
        ),
      // The Trash: only the owner and the admins (the server checks again).
      if (perms.has('inv_manage_settings'))
        _MoneyCard(
          key: const ValueKey<String>('money_trash'),
          icon: Icons.delete_outline,
          color: Colors.white70,
          title: sw ? 'Takataka (vilivyofutwa)' : 'Trash (deleted)',
          text: sw ? 'Matumizi, wateja, madeni na bidhaa ulivyofuta. Virudishe au vifute kabisa.' : 'Expenses, customers, debts and products you deleted. Restore them, or delete them for good.',
          open: () => Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => ThemeConstants.buildScaffold(title: sw ? 'Takataka' : 'Trash', body: const TrashScreen())),
          ),
        ),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(bottom: 10.h),
          child: Text(sw ? 'Chagua unachotaka kuona' : 'Choose what you want to see', style: ThemeConstants.captionStyle),
        ),
        for (final Widget c in cards) ...<Widget>[c, SizedBox(height: 10.h)],
      ],
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({super.key, required this.icon, required this.color, required this.title, required this.text, required this.open});

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20.r),
        onTap: open,
        child: Container(
          decoration: ThemeConstants.glassCardDecoration,
          padding: EdgeInsets.all(14.w),
          child: Row(
            children: <Widget>[
              Container(
                width: 46.w,
                height: 46.w,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, fontSize: 16.sp)),
                    SizedBox(height: 3.h),
                    Text(text, style: ThemeConstants.captionStyle),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white70, size: 24.sp),
            ],
          ),
        ),
      );
}
