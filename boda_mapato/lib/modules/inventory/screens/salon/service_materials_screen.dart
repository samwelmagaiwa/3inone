import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/inv_product.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';

/// The goods one service uses up each time it is sold (a tube of dye for a colour, a towel pack for a wash). When the
/// service is sold they leave the shelf by themselves and what they cost goes into the profit and loss; a service is never
/// stopped because one ran out.
class ServiceMaterialsScreen extends StatefulWidget {
  const ServiceMaterialsScreen({super.key, required this.serviceId, required this.serviceName, this.api, this.goods});

  final int serviceId;
  final String serviceName;
  final SalonApi? api;

  /// The goods to choose from (the stock list); the inventory's own when null.
  final List<InvProduct>? goods;

  @override
  State<ServiceMaterialsScreen> createState() => _ServiceMaterialsScreenState();
}

class _Row {
  _Row(this.productId, this.name, this.qty);

  final int productId;
  final String name;
  int qty;
}

class _ServiceMaterialsScreenState extends State<ServiceMaterialsScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  final List<_Row> _rows = <_Row>[];
  String? _error;
  bool _loading = true;
  bool _saving = false;

  List<InvProduct> get _goods => widget.goods ?? <InvProduct>[for (final InvProduct p in context.read<InventoryProvider>().products) if (!p.isService && p.status == 'active') p];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final List<Map<String, dynamic>> got = await _api.serviceMaterials(widget.serviceId);
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(<_Row>[for (final Map<String, dynamic> m in got) _Row((m['material_product_id'] as num).toInt(), '${m['name']}', (m['quantity'] as num).toInt())]);
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

  Future<void> _add() async {
    final List<InvProduct> choices = _goods.where((InvProduct p) => !_rows.any((_Row r) => r.productId == p.id)).toList();
    final InvProduct? p = await showDialog<InvProduct>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: Text(context.read<LocalizationService>().isSwahili ? 'Chagua bidhaa' : 'Choose goods'),
        children: <Widget>[for (final InvProduct g in choices) SimpleDialogOption(key: Key('mat_pick_${g.id}'), onPressed: () => Navigator.pop(d, g), child: Text(g.name))],
      ),
    );
    if (p != null) setState(() => _rows.add(_Row(p.id, p.name, 1)));
  }

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    setState(() => _saving = true);
    try {
      await _api.saveServiceMaterials(widget.serviceId, <Map<String, dynamic>>[for (final _Row r in _rows) <String, dynamic>{'material_product_id': r.productId, 'quantity': r.qty}]);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imehifadhiwa' : 'Saved');
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Bidhaa zinazotumika: ${widget.serviceName}' : 'Goods used: ${widget.serviceName}')),
      floatingActionButton: FloatingActionButton.extended(key: const Key('mat_add'), onPressed: _add, icon: const Icon(Icons.add), label: Text(sw ? 'Ongeza bidhaa' : 'Add goods')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
                  Text(sw ? 'Kila huduma hii ikiuzwa, bidhaa hizi hutolewa kwenye stoo.' : 'Each time this service is sold, these goods leave the shelf.'),
                  const SizedBox(height: 8),
                  for (final _Row r in _rows)
                    Card(
                      key: Key('mat_${r.productId}'),
                      child: ListTile(
                        title: Text(r.name),
                        subtitle: Row(children: <Widget>[
                          IconButton(key: Key('mat_minus_${r.productId}'), icon: const Icon(Icons.remove_circle_outline), onPressed: r.qty > 1 ? () => setState(() => r.qty--) : null),
                          Text('${r.qty}', key: Key('mat_qty_${r.productId}')),
                          IconButton(key: Key('mat_plus_${r.productId}'), icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => r.qty++)),
                        ]),
                        trailing: IconButton(key: Key('mat_remove_${r.productId}'), icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _rows.remove(r))),
                      ),
                    ),
                  if (_rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna bidhaa bado.' : 'No goods yet.', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  FilledButton(key: const Key('mat_save'), onPressed: _saving ? null : _save, child: Text(sw ? 'Hifadhi' : 'Save')),
                ]),
    );
  }
}
