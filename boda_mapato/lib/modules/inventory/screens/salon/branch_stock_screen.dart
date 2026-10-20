import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import 'salon_input.dart';

/// Where the goods are: for each product the whole stock, what each branch holds and what is still in the main store.
/// The owner, managers and the stock manager move goods between them. A sale in a branch takes from that branch first.
class BranchStockScreen extends StatefulWidget {
  const BranchStockScreen({super.key, this.api, this.canMove = true});

  final SalonApi? api;

  /// Only the owner, managers and the stock manager move goods (the server checks too).
  final bool canMove;

  @override
  State<BranchStockScreen> createState() => _BranchStockScreenState();
}

class _BranchStockScreenState extends State<BranchStockScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  Map<String, dynamic> _data = <String, dynamic>{};
  String? _error;
  bool _loading = true;

  List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[
        if (v is List)
          for (final dynamic r in v)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

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
      final Map<String, dynamic> d = await _api.branchStock();
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

  Future<void> _move(final Map<String, dynamic> product) async {
    final List<Map<String, dynamic>> branches = _list(_data['branches']);
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (BuildContext d) => _MoveDialog(product: product, branches: branches));
    if (got == null || !mounted) return;
    try {
      await _api.transferBranchStock(productId: (product['id'] as num).toInt(), fromBranchId: got['from'] as int?, toBranchId: got['to'] as int?, quantity: got['qty'] as int);
      if (mounted) await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<Map<String, dynamic>> branches = _list(_data['branches']);

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Bidhaa kwa tawi' : 'Goods by branch')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    if (branches.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Ongeza tawi kwanza (menyu ya Matawi).' : 'Add a branch first (the Branches menu).', key: const Key('bs_no_branches'), textAlign: TextAlign.center)),
                    for (final Map<String, dynamic> p in _list(_data['products']))
                      Card(
                        key: Key('bs_${p['id']}'),
                        child: ListTile(
                          title: Text('${p['name']}  ·  ${p['total']}'),
                          subtitle: Text(<String>[
                            '${sw ? 'Stoo kuu' : 'Main store'} ${p['unallocated']}',
                            for (final Map<String, dynamic> b in _list(p['branches'])) '${b['name']} ${b['quantity']}',
                            if (p['over_allocated'] == true) (sw ? 'Matawi yana zaidi ya stoo — hesabu upya' : 'Branches hold more than the stock: recount'),
                          ].join(' · ')),
                          isThreeLine: _list(p['branches']).length > 1,
                          trailing: widget.canMove && branches.isNotEmpty ? IconButton(key: Key('bs_move_${p['id']}'), tooltip: sw ? 'Hamisha' : 'Move', icon: const Icon(Icons.swap_horiz), onPressed: () => _move(p)) : null,
                        ),
                      ),
                  ]),
                ),
    );
  }
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.product, required this.branches});

  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> branches;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  final TextEditingController _qty = TextEditingController();
  // 0 = the main store, otherwise a branch id
  int _from = 0;
  int _to = 0;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.branches.isNotEmpty) _to = (widget.branches.first['id'] as num).toInt();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<int>> _items(final bool sw) => <DropdownMenuItem<int>>[
        DropdownMenuItem<int>(value: 0, child: Text(sw ? 'Stoo kuu' : 'Main store')),
        for (final Map<String, dynamic> b in widget.branches) DropdownMenuItem<int>(value: (b['id'] as num).toInt(), child: Text('${b['name']}')),
      ];

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text('${widget.product['name']}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          DropdownButtonFormField<int>(key: const Key('bs_from'), initialValue: _from, items: _items(sw), onChanged: (int? v) => setState(() => _from = v ?? 0), decoration: salonInput(labelText: sw ? 'Kutoka' : 'From')),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(key: const Key('bs_to'), initialValue: _to, items: _items(sw), onChanged: (int? v) => setState(() => _to = v ?? 0), decoration: salonInput(labelText: sw ? 'Kwenda' : 'To')),
          const SizedBox(height: 8),
          TextField(style: salonInputStyle, key: const Key('bs_qty'), controller: _qty, keyboardType: TextInputType.number, decoration: salonInput(labelText: sw ? 'Idadi' : 'Quantity')),
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: const TextStyle(color: Colors.red))),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(
          key: const Key('bs_save'),
          onPressed: () {
            final int? q = int.tryParse(_qty.text.trim());
            if (_from == _to) return setState(() => _problem = sw ? 'Chagua mahali tofauti.' : 'Choose a different place.');
            if (q == null || q < 1) return setState(() => _problem = sw ? 'Weka idadi.' : 'Enter a quantity.');
            Navigator.pop(context, <String, dynamic>{'from': _from == 0 ? null : _from, 'to': _to == 0 ? null : _to, 'qty': q});
          },
          child: Text(sw ? 'Hamisha' : 'Move'),
        ),
      ],
    );
  }
}
