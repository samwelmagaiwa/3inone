import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../screens/settings/business_profile_screen.dart';

/// The business's own details (name, TIN, logo, address: what receipts show) from inside the salon, so the owner does not
/// have to leave for the app's settings. The owner edits; everyone else reads.
class SalonBusinessProfilePage extends StatelessWidget {
  const SalonBusinessProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthProvider auth = context.watch<AuthProvider>();

    return BusinessProfileScreen(canEdit: auth.user?.isBusinessOwner ?? false, onChanged: auth.refreshUser);
  }
}
