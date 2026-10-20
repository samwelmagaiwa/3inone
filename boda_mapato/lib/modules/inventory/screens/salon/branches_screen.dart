import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/api_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import 'salon_input.dart';

/// The salon's branches. Choosing one makes every figure, list and new record on the phone that branch's; "All branches"
/// goes back to the whole salon. The owner and managers add, rename and switch branches off. A salon with one branch
/// never needs this page.
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key, this.api, this.manage = true});

  final SalonApi? api;

  /// The owner and managers change the list; everyone else only chooses.
  final bool manage;

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  List<SalonBranchInfo> _rows = <SalonBranchInfo>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<SalonBranchInfo> rows = await _api.branches();
      if (!mounted) return;
      // A branch switched off since it was chosen no longer filters anything.
      if (ApiService.activeBranch != null && !rows.any((SalonBranchInfo b) => b.id == ApiService.activeBranch && b.active)) {
        ApiService.activeBranch = null;
      }
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _edit([final SalonBranchInfo? b]) async {
    final (String, String)? got = await showDialog<(String, String)>(context: context, builder: (BuildContext d) => _BranchDialog(branch: b));
    if (got == null || got.$1.isEmpty || !mounted) return;
    await _run(() => _api.saveBranch(id: b?.id, name: got.$1, address: got.$2));
  }

  Future<void> _run(final Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  void _choose(final int? id) {
    setState(() => ApiService.activeBranch = id);
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final int? chosen = ApiService.activeBranch;

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Matawi' : 'Branches')),
      floatingActionButton: widget.manage
          ? FloatingActionButton.extended(key: const Key('branch_add'), onPressed: _edit, icon: const Icon(Icons.add), label: Text(sw ? 'Ongeza tawi' : 'Add branch'))
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    RadioListTile<int?>(
                      key: const Key('branch_all'),
                      value: null,
                      groupValue: chosen,
                      onChanged: _choose,
                      title: Text(sw ? 'Matawi yote' : 'All branches'),
                      subtitle: Text(sw ? 'Hesabu za saluni nzima' : 'The whole salon\'s figures'),
                    ),
                    for (final SalonBranchInfo b in _rows)
                      ListTile(
                        key: Key('branch_${b.id}'),
                        leading: Radio<int?>(value: b.id, groupValue: chosen, onChanged: b.active ? _choose : null),
                        title: Text(b.name, style: TextStyle(color: b.active ? null : Colors.grey)),
                        subtitle: Text(<String>[if (b.address.isNotEmpty) b.address, if (!b.active) (sw ? 'Limezimwa' : 'Switched off')].join(' · ')),
                        onTap: b.active ? () => _choose(b.id) : null,
                        trailing: widget.manage
                            ? PopupMenuButton<String>(
                                key: Key('branch_menu_${b.id}'),
                                onSelected: (String v) {
                                  if (v == 'edit') _edit(b);
                                  if (v == 'toggle') _run(() => _api.saveBranch(id: b.id, name: b.name, active: !b.active));
                                  if (v == 'delete') _run(() => _api.deleteBranch(b.id));
                                },
                                itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(value: 'edit', child: Text(sw ? 'Badili' : 'Edit')),
                                  PopupMenuItem<String>(value: 'toggle', child: Text(b.active ? (sw ? 'Zima' : 'Switch off') : (sw ? 'Washa' : 'Switch on'))),
                                  PopupMenuItem<String>(value: 'delete', child: Text(sw ? 'Futa' : 'Delete')),
                                ],
                              )
                            : null,
                      ),
                    if (_rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(sw ? 'Hakuna tawi bado. Saluni yenye tawi moja haihitaji kuongeza.' : 'No branches yet. A salon with one branch does not need any.', textAlign: TextAlign.center),
                      ),
                  ]),
                ),
    );
  }
}

/// Name and address of a branch. It owns its controllers so they outlive the dialog's closing animation.
class _BranchDialog extends StatefulWidget {
  const _BranchDialog({this.branch});

  final SalonBranchInfo? branch;

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.branch?.name ?? '');
  late final TextEditingController _address = TextEditingController(text: widget.branch?.address ?? '');

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(widget.branch == null ? (sw ? 'Tawi jipya' : 'New branch') : (sw ? 'Badili tawi' : 'Edit branch')),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        TextField(style: salonInputStyle, key: const Key('branch_name'), controller: _name, decoration: salonInput(labelText: sw ? 'Jina la tawi' : 'Branch name')),
        TextField(style: salonInputStyle, key: const Key('branch_address'), controller: _address, decoration: salonInput(labelText: sw ? 'Mahali' : 'Address')),
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(key: const Key('branch_save'), onPressed: () => Navigator.pop(context, (_name.text.trim(), _address.text.trim())), child: Text(sw ? 'Hifadhi' : 'Save')),
      ],
    );
  }
}
