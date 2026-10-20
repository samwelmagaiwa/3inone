import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../../models/login_response.dart';
import '../../../../providers/auth_provider.dart';

/// Who may see the salon's money: what the business earned and spent, and what each person is paid. The owner, a
/// manager and an accountant; an ordinary stylist sees their own commission on the Stylists page and nothing else.
/// (The server checks the same thing: this only decides what is shown.)
bool canSeeSalonMoney(final UserData? user) {
  if (user == null) return false;
  if (user.isSuperAdmin) return true;

  return const <String>['admin', 'administrator', 'manager', 'accountant'].contains(user.role.toLowerCase());
}

/// [canSeeSalonMoney] for the person signed in, where there is one (a screen built without sign-in shows no money).
bool canSeeSalonMoneyHere(final BuildContext context) {
  try {
    return canSeeSalonMoney(context.watch<AuthProvider>().user);
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
