import 'package:flutter/material.dart';

import '../constants/theme_constants.dart';
import '../modules/inventory/screens/salon/branches_screen.dart';
import '../modules/inventory/services/salon_api.dart';
import '../services/api_service.dart';
import '../services/localization_service.dart';
import '../services/service_branch_api.dart';

/// "Branch: All branches" on a dashboard. Tapping opens the branches of that service to look at one (every figure and list
/// on the phone then follows it) or to add and change them. [onChanged] runs when the person comes back, so the page can
/// read its figures again.
class BranchFilterButton extends StatefulWidget {
  const BranchFilterButton({super.key, required this.service, required this.onChanged, this.api});

  /// 'transport' or 'rental' (the shop and the salon have their own sheet on the inventory dashboard).
  final String service;
  final VoidCallback onChanged;

  /// A fake in tests.
  final SalonApi? api;

  @override
  State<BranchFilterButton> createState() => _BranchFilterButtonState();
}

class _BranchFilterButtonState extends State<BranchFilterButton> {
  /// The name shown only while the chosen branch is this service's.
  String? get _name => ApiService.activeBranch != null && ApiService.activeBranchService == widget.service ? ApiService.activeBranchName : null;

  Future<void> _open() async {
    final int? before = ApiService.activeBranch;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext _) => BranchesScreen(api: widget.api ?? ServiceBranchApi(widget.service), service: widget.service)),
    );
    if (!mounted) return;
    setState(() {});
    if (before != ApiService.activeBranch) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = LocalizationService.instance.isSwahili;
    final String label = _name ?? (sw ? 'Matawi yote' : 'All branches');

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: ActionChip(
          key: const Key('branch_filter_button'),
          avatar: const Icon(Icons.store_mall_directory_outlined, size: 18, color: Colors.white70),
          label: Text('${sw ? 'Tawi' : 'Branch'}: $label', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
          backgroundColor: _name == null ? Colors.white.withOpacity(0.08) : ThemeConstants.primaryBlue.withOpacity(0.45),
          side: const BorderSide(color: Colors.white24),
          onPressed: _open,
        ),
      ),
    );
  }
}
