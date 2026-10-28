import 'package:flutter/material.dart';

import '../modules/inventory/models/salon_models.dart';
import '../modules/inventory/services/salon_api.dart';
import '../services/api_service.dart';
import '../services/localization_service.dart';
import '../services/service_branch_api.dart';

/// "Which branch does this belong to?" on a form for a driver, a vehicle or a property. It shows nothing for a business with
/// no branch (nobody is asked a question that has no answer); otherwise a list of the active branches plus "No branch".
/// A new record starts on the branch being looked at, an old one on its own. [onChanged] gets the branch id, or null.
class BranchPickerField extends StatefulWidget {
  const BranchPickerField({super.key, required this.service, required this.onChanged, this.initialId, this.decoration, this.api});

  final String service;
  final int? initialId;
  final ValueChanged<int?> onChanged;

  /// The look of the surrounding form's fields.
  final InputDecoration? decoration;

  /// A fake in tests.
  final SalonApi? api;

  @override
  State<BranchPickerField> createState() => _BranchPickerFieldState();
}

class _BranchPickerFieldState extends State<BranchPickerField> {
  List<SalonBranchInfo> _branches = <SalonBranchInfo>[];
  int? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialId ?? (ApiService.activeBranchService == widget.service ? ApiService.activeBranch : null);
    // the form's value is the starting one even when the person never touches the field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onChanged(_value);
      _load();
    });
  }

  Future<void> _load() async {
    try {
      final List<SalonBranchInfo> rows = await (widget.api ?? ServiceBranchApi(widget.service)).branches();
      if (!mounted) return;
      setState(() {
        _branches = rows.where((SalonBranchInfo b) => b.active || b.id == widget.initialId).toList(growable: false);
        if (_value != null && !_branches.any((SalonBranchInfo b) => b.id == _value)) _value = null;
      });
      widget.onChanged(_value);
    } on Exception {
      // no list (not allowed, or offline): the field simply stays out of the way
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_branches.isEmpty) return const SizedBox.shrink();
    final bool sw = LocalizationService.instance.isSwahili;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        key: const Key('branch_picker'),
        initialValue: _value,
        isExpanded: true,
        dropdownColor: const Color(0xFF1B3A4B),
        style: const TextStyle(color: Colors.white),
        decoration: (widget.decoration ??
                InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  labelStyle: const TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                ))
            .copyWith(
          labelText: sw ? 'Tawi' : 'Branch',
          prefixIcon: const Icon(Icons.store_mall_directory_outlined),
        ),
        items: <DropdownMenuItem<int?>>[
          DropdownMenuItem<int?>(value: null, child: Text(sw ? 'Hakuna tawi' : 'No branch')),
          for (final SalonBranchInfo b in _branches) DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
        ],
        onChanged: (int? v) {
          setState(() => _value = v);
          widget.onChanged(v);
        },
      ),
    );
  }
}
