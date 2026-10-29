import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/inv_product.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import 'salon_input.dart';

/// Today's walk-in queue: clients who came without an appointment, in the order they arrived, with a rough wait (the time
/// of the services ahead of them). Start serving, finish, or mark that someone left; a finished client stays finished.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, this.api});

  final SalonApi? api;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  Map<String, dynamic> _data = <String, dynamic>{};
  String? _error;
  bool _loading = true;

  List<Map<String, dynamic>> get _queue => <Map<String, dynamic>>[
        if (_data['queue'] is List)
          for (final dynamic r in _data['queue'] as List)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      final InventoryProvider? inv = context.read<InventoryProvider?>();
      inv?.fetchSalonStaff();
      if (inv != null && inv.products.isEmpty) inv.fetchProducts();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> d = await _api.queue();
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

  Future<void> _add() async {
    final InventoryProvider? inv = context.read<InventoryProvider?>();
    final List<InvProduct> services = <InvProduct>[
      if (inv != null)
        for (final InvProduct p in inv.products)
          if (p.isService && p.status == 'active' && !p.isPackage) p,
    ];
    final List<Map<String, String>> staff = inv?.salonStaff ?? const <Map<String, String>>[];
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (BuildContext d) => _AddDialog(services: services, staff: staff));
    if (got == null || !mounted) return;
    await _run(() => _api.addToQueue(name: got['name'] as String, phone: got['phone'] as String?, productId: got['product_id'] as int?, staffId: got['staff_id'] as String?));
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(key: const Key('queue_add'), onPressed: _add, icon: const Icon(Icons.person_add_alt_1), label: Text(sw ? 'Mteja amefika' : 'Client arrived')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
                    Text(
                      sw ? 'Wanasubiri ${_data['waiting'] ?? 0} • wanahudumiwa ${_data['serving'] ?? 0} • wamemaliza ${_data['done'] ?? 0} • wameondoka ${_data['left'] ?? 0}' : 'Waiting ${_data['waiting'] ?? 0} • being served ${_data['serving'] ?? 0} • done ${_data['done'] ?? 0} • left ${_data['left'] ?? 0}',
                      key: const Key('queue_summary'),
                    ),
                    const SizedBox(height: 8),
                    for (final Map<String, dynamic> q in _queue) _card(q, sw),
                    if (_queue.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna anayesubiri leo.' : 'Nobody is waiting today.', textAlign: TextAlign.center)),
                  ]),
                ),
    );
  }

  Widget _card(final Map<String, dynamic> q, final bool sw) {
    final String status = '${q['status']}';
    final int id = (q['id'] as num).toInt();
    final bool open = status == 'waiting' || status == 'serving';

    return Card(
      key: Key('queue_$id'),
      child: ListTile(
        title: Text('${q['position'] != null ? '#${q['position']}  ' : ''}${q['name']}', style: TextStyle(decoration: open ? null : TextDecoration.lineThrough)),
        subtitle: Text(<String>[
          '${q['arrived_at']}',
          if ('${q['service'] ?? ''}'.isNotEmpty) '${q['service']}',
          if ('${q['staff_name'] ?? ''}'.isNotEmpty) '${q['staff_name']}',
          if (status == 'serving') (sw ? 'Anahudumiwa' : 'Being served'),
          if (status == 'waiting' && q['wait_minutes'] != null) (sw ? 'Dakika ~${q['wait_minutes']}' : '~${q['wait_minutes']} min'),
          if (status == 'done') (sw ? 'Amemaliza' : 'Done'),
          if (status == 'left') (sw ? 'Ameondoka' : 'Left'),
        ].join(' · ')),
        trailing: !open
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                if (status == 'waiting') IconButton(key: Key('queue_start_$id'), tooltip: sw ? 'Anza kumhudumia' : 'Start serving', icon: const Icon(Icons.play_arrow), onPressed: () => _run(() => _api.setQueueStatus(id, 'serving'))),
                if (status == 'serving') IconButton(key: Key('queue_done_$id'), tooltip: sw ? 'Amemaliza' : 'Done', icon: const Icon(Icons.check), onPressed: () => _run(() => _api.setQueueStatus(id, 'done'))),
                IconButton(key: Key('queue_left_$id'), tooltip: sw ? 'Ameondoka' : 'Left', icon: const Icon(Icons.exit_to_app), onPressed: () => _run(() => _api.setQueueStatus(id, 'left'))),
              ]),
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
  const _AddDialog({required this.services, required this.staff});

  final List<InvProduct> services;
  final List<Map<String, String>> staff;

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  int? _product;
  String? _staff;
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(sw ? 'Mteja amefika' : 'Client arrived'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(style: salonInputStyle, key: const Key('queue_name'), controller: _name, decoration: salonInput(labelText: sw ? 'Jina' : 'Name')),
          const SizedBox(height: 8),
          TextField(style: salonInputStyle, key: const Key('queue_phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: salonInput(labelText: sw ? 'Simu (si lazima)' : 'Phone (optional)')),
          if (widget.services.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const Key('queue_service'),
              initialValue: _product,
              isExpanded: true,
              items: <DropdownMenuItem<int>>[for (final InvProduct p in widget.services) DropdownMenuItem<int>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
              onChanged: (int? v) => setState(() => _product = v),
              decoration: salonInput(labelText: sw ? 'Huduma anayotaka' : 'Service wanted'),
            ),
          ],
          if (widget.staff.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('queue_staff'),
              initialValue: _staff,
              isExpanded: true,
              items: <DropdownMenuItem<String>>[for (final Map<String, String> s in widget.staff) DropdownMenuItem<String>(value: s['id'], child: Text(s['name'] ?? ''))],
              onChanged: (String? v) => setState(() => _staff = v),
              decoration: salonInput(labelText: sw ? 'Mhudumu (si lazima)' : 'Stylist (optional)'),
            ),
          ],
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: TextStyle(color: ThemeConstants.errorText))),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(
          key: const Key('queue_save'),
          onPressed: () {
            if (_name.text.trim().length < 2) return setState(() => _problem = sw ? 'Andika jina.' : 'Enter a name.');
            Navigator.pop(context, <String, dynamic>{'name': _name.text.trim(), 'phone': _phone.text.trim(), 'product_id': _product, 'staff_id': _staff});
          },
          child: Text(sw ? 'Weka kwenye foleni' : 'Add to queue'),
        ),
      ],
    );
  }
}
