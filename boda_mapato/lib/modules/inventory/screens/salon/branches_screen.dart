import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/api_service.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../../../widgets/place_picker.dart';
import '../../services/salon_api.dart';
import '../widgets/branch_form_dialog.dart';
import 'salon_input.dart';
import '../widgets/glow_list_card.dart';

/// The business's branches (a salon's, a shop's or a depot's). Choosing one makes every figure, list and new record on the phone
/// that branch's; "All branches" goes back to the whole business. The owner and managers add, rename and switch branches off.
/// A business with one branch never needs this page.
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key, this.api, this.manage = true, this.service, this.placeSource});

  /// Where the location lists come from (the server's; a test brings its own).
  final PlaceSource? placeSource;

  final SalonApi? api;

  /// Which service's branches these are ('inventory', 'salon', 'transport', 'rental'); null = the shop or salon now open.
  final String? service;

  /// The owner and managers change the list; everyone else only chooses.
  final bool manage;

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  String get _service => widget.service ?? ApiService.activeService ?? 'inventory';
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
        ApiService.clearBranch();
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
    final BranchForm? got = await showDialog<BranchForm>(context: context, builder: (BuildContext d) => BranchFormDialog(branch: b, placeSource: widget.placeSource));
    if (got == null || !mounted) return;
    await _run(() => _api.saveBranch(id: b?.id, name: got.name, address: got.address, phone: got.phone, region: got.region, district: got.district, ward: got.ward, street: got.street));
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
    setState(() {
      ApiService.chooseBranch(id, id == null ? null : _rows.where((SalonBranchInfo b) => b.id == id).map((SalonBranchInfo b) => b.name).firstOrNull, service: _service);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final int? chosen = ApiService.activeBranch;

    return Scaffold(
      appBar: salonAppBar(context, sw ? 'Matawi' : 'Branches'),
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
                    GlowListCard(
                      dividerKey: 'branch_divider',
                      padding: EdgeInsets.zero,
                      children: <Widget>[
                    RadioListTile<int?>(
                      key: const Key('branch_all'),
                      value: null,
                      groupValue: chosen,
                      onChanged: _choose,
                      title: Text(sw ? 'Matawi yote' : 'All branches'),
                      subtitle: Text(sw ? 'Hesabu za biashara nzima' : 'The whole business\'s figures'),
                    ),
                    for (final SalonBranchInfo b in _rows)
                      ListTile(
                        key: Key('branch_${b.id}'),
                        leading: Radio<int?>(value: b.id, groupValue: chosen, onChanged: b.active ? _choose : null),
                        title: Text(b.name, style: TextStyle(color: b.active ? null : Colors.grey)),
                        subtitle: Text(<String>[if (b.placeLine.isNotEmpty) b.placeLine, if (b.address.isNotEmpty) b.address, if (!b.active) (sw ? 'Limezimwa' : 'Switched off')].join(' · ')),
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
                      ],
                    ),
                    if (_rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(sw ? 'Hakuna tawi bado. Biashara yenye tawi moja haihitaji kuongeza.' : 'No branches yet. A business with one branch does not need any.', textAlign: TextAlign.center),
                      ),
                  ]),
                ),
    );
  }
}
