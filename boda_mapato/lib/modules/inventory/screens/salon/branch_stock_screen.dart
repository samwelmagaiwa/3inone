import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import '../widgets/glow_list_card.dart';
import '../widgets/joined_sections.dart';
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
              : Column(
                  children: <Widget>[
                    // The column titles stay where they are while the goods scroll under them.
                    if (_list(_data['products']).isNotEmpty) _header(sw, branches),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: <Widget>[
                          if (SalonEmbedded.of(context)) Align(alignment: Alignment.centerRight, child: history(sw)),
                          if (_list(_data['products']).isEmpty && branches.isNotEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna bidhaa bado. Ongeza bidhaa kwenye Huduma na Bidhaa.' : 'No goods yet. Add goods in Services & Goods.', key: const Key('bs_no_goods'), textAlign: TextAlign.center)),
                          if (branches.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Ongeza tawi kwanza (menyu ya Matawi).' : 'Add a branch first (the Branches menu).', key: const Key('bs_no_branches'), textAlign: TextAlign.center)),
                          // The goods are ONE card of rows, each divided from the next by the glowing line.
                          if (_list(_data['products']).isNotEmpty)
                            GlowListCard(
                              dividerKey: 'goods_divider',
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                              children: <Widget>[for (final Map<String, dynamic> p in _list(_data['products'])) _row(p, sw, branches)],
                            ),
                        ]),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// The titles of the figures under each product: the main store, then each branch. Fixed above the scrolling list.
  Widget _header(final bool sw, final List<Map<String, dynamic>> branches) {
    Widget title(final String text, final Key key) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(text, key: key, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        );
    Widget line() => const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: SizedBox(width: SectionGlowVerticalDivider.lineWidth, child: SectionGlowVerticalDivider()));

    return Padding(
      key: const Key('bs_header'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GlowListCard(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: <Widget>[
          Row(children: <Widget>[
            title(sw ? 'Stoo kuu' : 'Main store', const Key('bs_head_main')),
            for (final Map<String, dynamic> b in branches) ...<Widget>[line(), title('${b['name']}', Key('bs_head_${b['id']}'))],
          ]),
        ],
      ),
    );
  }

  /// One product: its name, its total and the buttons on top; under it the figures, one under each title, divided by the glowing lines.
  Widget _row(final Map<String, dynamic> p, final bool sw, final List<Map<String, dynamic>> branches) {
    final Map<int, Map<String, dynamic>> held = <int, Map<String, dynamic>>{
      for (final Map<String, dynamic> b in _list(p['branches'])) if (b['branch_id'] is num) (b['branch_id'] as num).toInt(): b,
    };
    Widget cell(final Key key, final String value, {final bool low = false, final String? note}) => Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            FittedBox(fit: BoxFit.scaleDown, child: Text('${low ? '⚠ ' : ''}$value', key: key, style: TextStyle(color: low ? const Color(0xFFFFB020) : Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
            if (note != null) Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFFB020), fontSize: 10)),
          ]),
        );
    Widget line() => const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: SizedBox(width: SectionGlowVerticalDivider.lineWidth, child: SectionGlowVerticalDivider()));
    final int id = (p['id'] as num).toInt();

    return Column(
      key: Key('bs_$id'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text('${p['name']}', key: Key('bs_name_$id'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Container(
            key: Key('bs_total_$id'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: ThemeConstants.invAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.invAccent)),
            child: Text('${sw ? 'Jumla' : 'Total'} ${p['total']}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          if (widget.canMove && branches.isNotEmpty) ...<Widget>[
            IconButton(key: Key('bs_level_$id'), visualDensity: VisualDensity.compact, tooltip: sw ? 'Kiwango cha tahadhari' : 'Alert level', icon: const Icon(Icons.notifications_active_outlined), onPressed: () => _level(p)),
            IconButton(key: Key('bs_move_$id'), visualDensity: VisualDensity.compact, tooltip: sw ? 'Hamisha' : 'Move', icon: const Icon(Icons.swap_horiz), onPressed: () => _move(p)),
          ],
        ]),
        const SizedBox(height: 6),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
            cell(Key('bs_main_$id'), '${p['unallocated']}'),
            for (final Map<String, dynamic> b in branches) ...<Widget>[
              line(),
              Builder(builder: (BuildContext context) {
                final Map<String, dynamic>? h = held[(b['id'] as num).toInt()];
                final bool low = h?['low'] == true;

                return cell(Key('bs_br_${id}_${b['id']}'), '${h?['quantity'] ?? 0}', low: low, note: low && h?['min_quantity'] != null ? '${sw ? 'kiwango' : 'level'} ${h!['min_quantity']}' : null);
              }),
            ],
          ]),
        ),
        if (p['over_allocated'] == true)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(sw ? 'Matawi yana zaidi ya stoo — hesabu upya' : 'Branches hold more than the stock: recount', key: Key('bs_over_$id'), style: const TextStyle(color: Color(0xFFFFB020), fontSize: 12))),
      ],
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
                    if (_rows.isNotEmpty)
                      GlowListCard(padding: EdgeInsets.zero, children: <Widget>[
                    for (final Map<String, dynamic> t in _rows)
                      ListTile(
                        key: Key('tr_${t['id']}'),
                        title: Text('${t['product']}  ×${t['quantity']}'),
                        subtitle: Text('${t['from'] ?? store} → ${t['to'] ?? store}\n${t['at']}${'${t['by'] ?? ''}'.isEmpty ? '' : ' · ${t['by']}'}'),
                        isThreeLine: true,
                      ),
                      ]),
                    if (_rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna uhamisho bado.' : 'Nothing has been moved yet.', key: const Key('tr_empty'), textAlign: TextAlign.center)),
                  ]),
                ),
    );
  }
}
