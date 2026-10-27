import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import 'salon_input.dart';
import 'salon_text.dart';
import '../widgets/inventory_widgets.dart';

/// The salon's equipment: what it owns and cost, whether it works, when it is next due for a service, and each service or
/// repair with what it cost (that cost goes into the expenses once). Overdue and soon-due things stand out.
class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({super.key, this.api});

  final SalonApi? api;

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  Map<String, dynamic> _data = <String, dynamic>{};
  String? _error;
  bool _loading = true;

  List<Map<String, dynamic>> get _items => <Map<String, dynamic>>[
        if (_data['equipment'] is List)
          for (final dynamic r in _data['equipment'] as List)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  Map<String, dynamic> get _totals => _data['totals'] is Map ? Map<String, dynamic>.from(_data['totals'] as Map) : <String, dynamic>{};

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
      final Map<String, dynamic> d = await _api.equipment();
      if (!mounted) return;
      setState(() {
        _data = d;
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

  Future<void> _run(final Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _edit([final Map<String, dynamic>? e]) async {
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (BuildContext d) => _EquipmentDialog(item: e));
    if (got == null || !mounted) return;
    await _run(() => _api.saveEquipment(got, id: e == null ? null : (e['id'] as num).toInt()));
  }

  Future<void> _log(final Map<String, dynamic> e) async {
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (BuildContext d) => const _LogDialog());
    if (got == null || !mounted) return;
    await _run(() => _api.addEquipmentLog((e['id'] as num).toInt(), got));
  }

  Future<void> _history(final Map<String, dynamic> e) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    try {
      final List<Map<String, dynamic>> logs = await _api.equipmentLogs((e['id'] as num).toInt());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext d) => AlertDialog(
          title: Text('${e['name']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: logs.isEmpty
                ? Text(sw ? 'Hakuna huduma iliyorekodiwa.' : 'No service recorded yet.', key: const Key('eq_history_empty'))
                : ListView(shrinkWrap: true, children: <Widget>[
                    for (final Map<String, dynamic> l in logs)
                      ListTile(
                        dense: true,
                        title: Text('${l['done_on']} · ${l['kind'] == 'repair' ? (sw ? 'Ukarabati' : 'Repair') : (sw ? 'Huduma' : 'Service')}'),
                        subtitle: Text('${l['description']}'),
                        trailing: ((l['cost'] as num?) ?? 0) > 0 ? Text(tsh(l['cost'] as num)) : null,
                      ),
                  ]),
          ),
          actions: <Widget>[TextButton(onPressed: () => Navigator.pop(d), child: Text(sw ? 'Funga' : 'Close'))],
        ),
      );
    } on Exception catch (err) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(err));
    }
  }

  Future<void> _open(final Map<String, dynamic> e) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(key: const Key('eq_log'), leading: const Icon(Icons.build_outlined), title: Text(sw ? 'Weka huduma / ukarabati' : 'Record a service / repair'), onTap: () => Navigator.pop(c, 'log')),
          ListTile(key: const Key('eq_history'), leading: const Icon(Icons.history), title: Text(sw ? 'Historia ya huduma' : 'Service history'), onTap: () => Navigator.pop(c, 'history')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: Text(sw ? 'Badili' : 'Edit'), onTap: () => Navigator.pop(c, 'edit')),
          if (e['status'] != 'retired') ListTile(key: const Key('eq_retire'), leading: const Icon(Icons.archive_outlined), title: Text(sw ? 'Ondoa kwenye matumizi' : 'Retire'), onTap: () => Navigator.pop(c, 'retire')),
          ListTile(leading: const Icon(Icons.delete_outline), title: Text(sw ? 'Futa' : 'Delete'), onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    final int id = (e['id'] as num).toInt();
    if (pick == 'log') await _log(e);
    if (pick == 'history') await _history(e);
    if (pick == 'edit') await _edit(e);
    if (pick == 'retire') await _run(() => _api.saveEquipment(<String, dynamic>{'status': 'retired'}, id: id));
    if (pick == 'delete') await _run(() => _api.deleteEquipment(id));
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Scaffold(
      appBar: salonAppBar(context, sw ? 'Vifaa vya saluni' : 'Equipment'),
      floatingActionButton: FloatingActionButton.extended(key: const Key('eq_add'), onPressed: _edit, icon: const Icon(Icons.add), label: Text(sw ? 'Ongeza kifaa' : 'Add equipment')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(spacing: 24, runSpacing: 8, children: <Widget>[
                          _Stat(label: sw ? 'Vifaa' : 'Items', value: '${_totals['count'] ?? 0}'),
                          _Stat(label: sw ? 'Thamani' : 'Value', value: tsh((_totals['value'] as num?) ?? 0)),
                          _Stat(label: sw ? 'Vinatengenezwa' : 'In repair', value: '${_totals['in_repair'] ?? 0}'),
                          _Stat(label: sw ? 'Vinahitaji huduma' : 'Need a service', value: '${_totals['needs_attention'] ?? 0}'),
                        ]),
                      ),
                    ),
                    for (final Map<String, dynamic> e in _items)
                      Card(
                        key: Key('eq_${e['id']}'),
                        child: ListTile(
                          onTap: () => _open(e),
                          title: Text('${e['name']}', style: TextStyle(decoration: e['status'] == 'retired' ? TextDecoration.lineThrough : null)),
                          subtitle: Text(<String>[
                            if ('${e['kind'] ?? ''}'.isNotEmpty) '${e['kind']}',
                            if (e['status'] == 'repair') (sw ? 'Linatengenezwa' : 'In repair'),
                            if (e['status'] == 'retired') (sw ? 'Halitumiki' : 'Retired'),
                            if (e['next_service_on'] != null) '${sw ? 'Huduma' : 'Service'}: ${e['next_service_on']}',
                            if (((e['spent_on_upkeep'] as num?) ?? 0) > 0) '${sw ? 'Matunzo' : 'Upkeep'}: ${tsh(e['spent_on_upkeep'] as num)}',
                          ].join(' · ')),
                          trailing: e['overdue'] == true
                              ? Chip(label: Text(sw ? 'Imepita' : 'Overdue'), backgroundColor: Colors.red.shade100)
                              : e['due_soon'] == true
                                  ? Chip(label: Text(sw ? 'Karibu' : 'Due soon'), backgroundColor: Colors.orange.shade100)
                                  : null,
                        ),
                      ),
                    if (_items.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna kifaa bado.' : 'No equipment yet.', textAlign: TextAlign.center)),
                  ]),
                ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}

final RegExp _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

class _EquipmentDialog extends StatefulWidget {
  const _EquipmentDialog({this.item});

  final Map<String, dynamic>? item;

  @override
  State<_EquipmentDialog> createState() => _EquipmentDialogState();
}

class _EquipmentDialogState extends State<_EquipmentDialog> {
  late final TextEditingController _name = TextEditingController(text: '${widget.item?['name'] ?? ''}');
  late final TextEditingController _kind = TextEditingController(text: '${widget.item?['kind'] ?? ''}');
  late final TextEditingController _cost = TextEditingController(text: widget.item == null ? '' : '${(widget.item!['cost'] as num?)?.round() ?? ''}');
  late final TextEditingController _next = TextEditingController(text: '${widget.item?['next_service_on'] ?? ''}');
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _kind.dispose();
    _cost.dispose();
    _next.dispose();
    super.dispose();
  }

  void _save(final bool sw) {
    final String next = _next.text.trim();
    if (_name.text.trim().length < 2) return setState(() => _problem = sw ? 'Andika jina.' : 'Enter a name.');
    if (next.isNotEmpty && !_dayPattern.hasMatch(next)) return setState(() => _problem = sw ? 'Tarehe iwe mwaka-mwezi-siku, mfano 2026-12-31.' : 'Date as year-month-day, e.g. 2026-12-31.');
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'kind': _kind.text.trim(),
      'cost': double.tryParse(_cost.text.replaceAll(',', '').trim()) ?? 0,
      'next_service_on': next.isEmpty ? null : next,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(widget.item == null ? (sw ? 'Kifaa kipya' : 'New equipment') : (sw ? 'Badili kifaa' : 'Edit equipment')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(style: salonInputStyle, key: const Key('eq_name'), controller: _name, decoration: salonInput(labelText: sw ? 'Jina' : 'Name')),
          TextField(style: salonInputStyle, controller: _kind, decoration: salonInput(labelText: sw ? 'Aina (kiyoyozi, dryer…)' : 'Kind (dryer, chair…)')),
          TextField(style: salonInputStyle, key: const Key('eq_cost'), controller: _cost, keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[ThousandsFormatter()], decoration: salonInput(labelText: sw ? 'Gharama' : 'Cost')),
          TextField(style: salonInputStyle, key: const Key('eq_next'), controller: _next, decoration: salonInput(labelText: sw ? 'Huduma ijayo (YYYY-MM-DD)' : 'Next service (YYYY-MM-DD)')),
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: const TextStyle(color: Colors.red))),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(key: const Key('eq_save'), onPressed: () => _save(sw), child: Text(sw ? 'Hifadhi' : 'Save')),
      ],
    );
  }
}

class _LogDialog extends StatefulWidget {
  const _LogDialog();

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  final TextEditingController _what = TextEditingController();
  final TextEditingController _cost = TextEditingController();
  String _kind = 'maintenance';
  String? _problem;

  @override
  void dispose() {
    _what.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(sw ? 'Huduma / ukarabati' : 'Service / repair'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'maintenance', label: Text(sw ? 'Huduma' : 'Service')),
              ButtonSegment<String>(value: 'repair', label: Text(sw ? 'Ukarabati' : 'Repair')),
            ],
            selected: <String>{_kind},
            onSelectionChanged: (Set<String> s) => setState(() => _kind = s.first),
          ),
          TextField(style: salonInputStyle, key: const Key('log_what'), controller: _what, decoration: salonInput(labelText: sw ? 'Ilifanyika nini' : 'What was done')),
          TextField(style: salonInputStyle, key: const Key('log_cost'), controller: _cost, keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[ThousandsFormatter()], decoration: salonInput(labelText: sw ? 'Gharama (huingia kwenye matumizi)' : 'Cost (goes into expenses)')),
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: const TextStyle(color: Colors.red))),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(
          key: const Key('log_save'),
          onPressed: () {
            if (_what.text.trim().length < 3) return setState(() => _problem = sw ? 'Eleza kilichofanyika.' : 'Say what was done.');
            Navigator.pop(context, <String, dynamic>{
              'kind': _kind,
              'description': _what.text.trim(),
              'cost': double.tryParse(_cost.text.replaceAll(',', '').trim()) ?? 0,
              // After a repair it works again.
              'status': 'working',
            });
          },
          child: Text(sw ? 'Hifadhi' : 'Save'),
        ),
      ],
    );
  }
}
