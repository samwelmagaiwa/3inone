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

  Widget history(final bool sw) => IconButton(
        key: const Key('bs_history'),
        tooltip: sw ? 'Historia ya uhamisho' : 'Moves so far',
        icon: const Icon(Icons.history),
        onPressed: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => BranchTransfersScreen(api: _api))),
      );

  Future<void> _level(final Map<String, dynamic> product) async {
    final List<Map<String, dynamic>> branches = _list(_data['branches']);
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (BuildContext d) => _LevelDialog(product: product, branches: branches));
    if (got == null || !mounted) return;
    try {
      await _api.setBranchLevel(productId: (product['id'] as num).toInt(), branchId: got['branch'] as int, minQuantity: got['min'] as int?);
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
      appBar: salonAppBar(context, sw ? 'Bidhaa kwa tawi' : 'Goods by branch', actions: <Widget>[history(sw)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    if (SalonEmbedded.of(context)) Align(alignment: Alignment.centerRight, child: history(sw)),
                    if (_list(_data['products']).isEmpty && branches.isNotEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna bidhaa bado. Ongeza bidhaa kwenye Huduma na Bidhaa.' : 'No goods yet. Add goods in Services & Goods.', key: const Key('bs_no_goods'), textAlign: TextAlign.center)),
                    if (branches.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Ongeza tawi kwanza (menyu ya Matawi).' : 'Add a branch first (the Branches menu).', key: const Key('bs_no_branches'), textAlign: TextAlign.center)),
                    for (final Map<String, dynamic> p in _list(_data['products']))
                      Card(
                        key: Key('bs_${p['id']}'),
                        child: ListTile(
                          title: Text('${p['name']}  ·  ${p['total']}'),
                          subtitle: Text(<String>[
                            '${sw ? 'Stoo kuu' : 'Main store'} ${p['unallocated']}',
                            for (final Map<String, dynamic> b in _list(p['branches'])) '${b['low'] == true ? '⚠ ' : ''}${b['name']} ${b['quantity']}${b['min_quantity'] == null ? '' : ' (${sw ? 'kiwango' : 'level'} ${b['min_quantity']})'}',
                            if (p['over_allocated'] == true) (sw ? 'Matawi yana zaidi ya stoo — hesabu upya' : 'Branches hold more than the stock: recount'),
                          ].join(' · ')),
                          isThreeLine: _list(p['branches']).length > 1,
                          trailing: widget.canMove && branches.isNotEmpty
                              ? Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                                  IconButton(key: Key('bs_level_${p['id']}'), tooltip: sw ? 'Kiwango cha tahadhari' : 'Alert level', icon: const Icon(Icons.notifications_active_outlined), onPressed: () => _level(p)),
                                  IconButton(key: Key('bs_move_${p['id']}'), tooltip: sw ? 'Hamisha' : 'Move', icon: const Icon(Icons.swap_horiz), onPressed: () => _move(p)),
                                ])
                              : null,
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
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: TextStyle(color: ThemeConstants.errorText))),
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

/// When a branch is told a product is running low: a number (or empty for no alert), per branch.
class _LevelDialog extends StatefulWidget {
  const _LevelDialog({required this.product, required this.branches});

  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> branches;

  @override
  State<_LevelDialog> createState() => _LevelDialogState();
}

class _LevelDialogState extends State<_LevelDialog> {
  late int _branch = (widget.branches.first['id'] as num).toInt();
  late final TextEditingController _min = TextEditingController(text: _current());
  String? _problem;

  String _current() {
    final List<dynamic> list = widget.product['branches'] is List ? widget.product['branches'] as List : <dynamic>[];
    for (final dynamic b in list) {
      if (b is Map && (b['branch_id'] as num?)?.toInt() == _branch && b['min_quantity'] != null) return '${b['min_quantity']}';
    }

    return '';
  }

  @override
  void dispose() {
    _min.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(sw ? 'Tahadhari ya bidhaa kuisha: ${widget.product['name']}' : 'Running-low alert: ${widget.product['name']}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          DropdownButtonFormField<int>(
            key: const Key('lv_branch'),
            initialValue: _branch,
            items: <DropdownMenuItem<int>>[for (final Map<String, dynamic> b in widget.branches) DropdownMenuItem<int>(value: (b['id'] as num).toInt(), child: Text('${b['name']}'))],
            onChanged: (int? v) => setState(() {
              _branch = v ?? _branch;
              _min.text = _current();
            }),
            decoration: salonInput(labelText: sw ? 'Tawi' : 'Branch'),
          ),
          const SizedBox(height: 8),
          TextField(style: salonInputStyle, key: const Key('lv_min'), controller: _min, keyboardType: TextInputType.number, decoration: salonInput(labelText: sw ? 'Niambie ikibaki (acha wazi = bila tahadhari)' : 'Tell me when this many are left (empty = no alert)')),
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: TextStyle(color: ThemeConstants.errorText))),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(
          key: const Key('lv_save'),
          onPressed: () {
            final String t = _min.text.trim();
            final int? m = t.isEmpty ? null : int.tryParse(t);
            if (t.isNotEmpty && (m == null || m < 0)) return setState(() => _problem = sw ? 'Weka namba 0 au zaidi.' : 'Enter a number, 0 or more.');
            Navigator.pop(context, <String, dynamic>{'branch': _branch, 'min': m});
          },
          child: Text(sw ? 'Hifadhi' : 'Save'),
        ),
      ],
    );
  }
}

/// Every move of goods between the main store and branches, newest first: what, how many, from where to where, who, when.
class BranchTransfersScreen extends StatefulWidget {
  const BranchTransfersScreen({super.key, this.api});

  final SalonApi? api;

  @override
  State<BranchTransfersScreen> createState() => _BranchTransfersScreenState();
}

class _BranchTransfersScreenState extends State<BranchTransfersScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
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
      final List<Map<String, dynamic>> r = await _api.branchTransfers();
      if (!mounted) return;
      setState(() {
        _rows = r;
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

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final String store = sw ? 'Stoo kuu' : 'Main store';

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Historia ya uhamisho' : 'Moves so far')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    for (final Map<String, dynamic> t in _rows)
                      ListTile(
                        key: Key('tr_${t['id']}'),
                        title: Text('${t['product']}  ×${t['quantity']}'),
                        subtitle: Text('${t['from'] ?? store} → ${t['to'] ?? store}\n${t['at']}${'${t['by'] ?? ''}'.isEmpty ? '' : ' · ${t['by']}'}'),
                        isThreeLine: true,
                      ),
                    if (_rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna uhamisho bado.' : 'Nothing has been moved yet.', key: const Key('tr_empty'), textAlign: TextAlign.center)),
                  ]),
                ),
    );
  }
}
