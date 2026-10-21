import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../screens/settings/business_profile_screen.dart';
import '../../../../services/localization_service.dart';

/// The business's own details (name, TIN, logo, address: what receipts show) from inside the salon, so the owner does not
/// have to leave for the app's settings. The owner edits; everyone else reads. A super admin belongs to no business, so
/// there is nothing to show: the page says so instead of failing.
class SalonBusinessProfilePage extends StatelessWidget {
  const SalonBusinessProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthProvider auth = context.watch<AuthProvider>();
    if (auth.user?.business == null) {
      final bool sw = context.watch<LocalizationService>().isSwahili;

      return Scaffold(
        appBar: AppBar(title: Text(sw ? 'Taarifa za biashara' : 'Business profile')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              sw ? 'Akaunti hii haina biashara yake. Taarifa za biashara zinaonekana kwa mmiliki na wafanyakazi wa saluni.' : 'This account has no business of its own. The business profile is seen by the salon\'s owner and staff.',
              key: const Key('no_business_note'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return BusinessProfileScreen(canEdit: auth.user?.isBusinessOwner ?? false, onChanged: auth.refreshUser);
  }
}
