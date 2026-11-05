import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../models/login_response.dart';
import '../../../../providers/auth_provider.dart';

/// Who may see the salon's money: what the business earned and spent, and what each person is paid. Whoever holds the
/// "reports" right: the owner and the accountant by default, plus anyone the owner gave it to on the access-rights screen;
/// an ordinary stylist sees their own commission on the Stylists page and nothing else. (The server decides the same way:
/// this only decides what is shown.)
bool canSeeSalonMoney(final UserData? user) {
  if (user == null) return false;
  if (user.isSuperAdmin || user.fullAccess) return true;

  return user.access.has('inv_view_reports');
}

/// [canSeeSalonMoney] for the person signed in, where there is one (a screen built without sign-in shows no money).
bool canSeeSalonMoneyHere(final BuildContext context) {
  try {
    return canSeeSalonMoney(context.watch<AuthProvider>().user);
  } on ProviderNotFoundException {
    return false;
  }
}

/// May the person signed in see how the money came in (cash, mobile money, bank) on the dashboard? A right of its own (the cashbook's), on
/// for the owner and off for an accountant until the owner gives it. A screen built without sign-in (a test) shows it.
bool canSeeMoneyReceivedHere(final BuildContext context) {
  try {
    final UserData? user = context.watch<AuthProvider>().user;
    if (user == null) return false;

    return user.isSuperAdmin || user.fullAccess || user.access.has('inv_salon_cashbook');
  } on ProviderNotFoundException {
    return true;
  }
}

/// May the person signed in see the salon's profit (the month's report with its target)? The profit right: the owner's, given to an
/// accountant only if the owner switches it on.
bool canSeeSalonProfitHere(final BuildContext context) {
  try {
    final UserData? user = context.watch<AuthProvider>().user;
    if (user == null) return false;

    return user.isSuperAdmin || user.fullAccess || user.access.has('inv_salon_profit');
  } on ProviderNotFoundException {
    return false;
  }
}

/// The people who do the work themselves: hair stylists, nail technicians, lash and makeup artists. They see their own
/// diary and income; booking is for the reception and the owner. (The server enforces it; this decides what is shown.)
bool isStylistRole(final UserData? user) =>
    user != null && const <String>['hair_stylist', 'nail_technician', 'lash_makeup_artist'].contains(user.role.toLowerCase());

bool isStylistHere(final BuildContext context, {final bool listen = true}) {
  try {
    return isStylistRole(listen ? context.watch<AuthProvider>().user : context.read<AuthProvider>().user);
  } on ProviderNotFoundException {
    return false;
  }
}
