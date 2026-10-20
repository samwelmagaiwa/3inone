import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/inv_sale.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import 'salon_text.dart';

/// At the till: a voucher code, the chosen client's loyalty points, and (for a service the client has a package for) a
/// switch to take the visit from the package. It shows nothing a salon does not use (no points, no packages, no
/// voucher typed) beyond the voucher box. The server checks all of it again when the sale is saved.
class SalonPerksCard extends StatefulWidget {
  const SalonPerksCard({super.key, this.api});

  final SalonApi? api;

  @override
  State<SalonPerksCard> createState() => _SalonPerksCardState();
}

class _SalonPerksCardState extends State<SalonPerksCard> {
  late final SalonApi _api = widget.api ?? SalonApi();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _points = TextEditingController();

  int? _loadedFor;
  Map<String, dynamic> _loyalty = <String, dynamic>{};
  List<Map<String, dynamic>> _packages = <Map<String, dynamic>>[];
  double? _previewedAt;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _points.dispose();
    super.dispose();
  }

  Future<void> _loadClient(final int? id) async {
    _loadedFor = id;
    if (id == null) {
      setState(() {
        _loyalty = <String, dynamic>{};
        _packages = <Map<String, dynamic>>[];
        _points.clear();
      });
      return;
    }
    try {
      final Map<String, dynamic> loyalty = await _api.clientLoyalty(id);
      final List<Map<String, dynamic>> packages = await _api.clientPackages(id);
      if (!mounted || _loadedFor != id) return;
      setState(() {
        _loyalty = loyalty;
        _packages = packages.where((Map<String, dynamic> p) => p['usable'] == true).toList();
        _points.clear();
      });
    } on Exception {
      // Perks are optional: the sale goes on without them.
      if (mounted && _loadedFor == id) {
        setState(() {
          _loyalty = <String, dynamic>{};
          _packages = <Map<String, dynamic>>[];
        });
      }
    }
  }

  Future<void> _apply(final InventoryProvider inv) async {
    final String code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final double off = await _api.voucherDiscount(code, inv.cartSubtotal);
      inv.setVoucher(code, off);
      _previewedAt = inv.cartSubtotal;
    } on Exception catch (e) {
      inv.clearVoucher();
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The lines changed after the voucher was checked: ask again so the discount still matches what the server works out.
  Future<void> _refresh(final InventoryProvider inv) async {
    _previewedAt = inv.cartSubtotal;
    try {
      inv.setVoucher(inv.voucherCode, await _api.voucherDiscount(inv.voucherCode, inv.cartSubtotal));
    } on Exception {
      inv.clearVoucher();
    }
  }

  void _usePoints(final InventoryProvider inv) {
    final int have = (_loyalty['balance'] as num?)?.toInt() ?? 0;
    final int value = (_loyalty['value'] as num?)?.toInt() ?? 0;
    final int asked = int.tryParse(_points.text.trim()) ?? 0;
    final int pts = asked > have ? have : (asked < 0 ? 0 : asked);
    inv.setRedeemPoints(pts, value);
    if (asked != pts) _points.text = '$pts';
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final InventoryProvider inv = context.watch<InventoryProvider>();

    if (_loadedFor != inv.selectedCustomerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loadedFor != inv.selectedCustomerId) _loadClient(inv.selectedCustomerId);
      });
    }
    if (inv.voucherCode.isNotEmpty && _previewedAt != inv.cartSubtotal && !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && inv.voucherCode.isNotEmpty && _previewedAt != inv.cartSubtotal) _refresh(inv);
      });
    }

    final bool pointsOn = _loyalty['on'] == true && inv.selectedCustomerId != null;
    final int balance = (_loyalty['balance'] as num?)?.toInt() ?? 0;
    final List<InvSaleItem> serviceLines = inv.cart.where((InvSaleItem l) => l.isService && (l.packageId != null || _packageFor(l) != null)).toList();

    return Container(
      key: const ValueKey<String>('salon_perks_card'),
      decoration: ThemeConstants.invCardDecoration,
      padding: const EdgeInsets.all(12),
      // Material so the package switches can paint their ink on the card's coloured background.
      child: Material(
        color: Colors.transparent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(sw ? 'Kuponi, pointi na vifurushi' : 'Voucher, points and packages', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (inv.voucherCode.isEmpty)
          Row(children: <Widget>[
            Expanded(child: TextField(key: const Key('salon_voucher'), controller: _code, textCapitalization: TextCapitalization.characters, decoration: ThemeConstants.invInputDecoration(sw ? 'Msimbo wa kuponi' : 'Voucher code'), style: ThemeConstants.bodyStyle)),
            const SizedBox(width: 8),
            FilledButton(key: const Key('salon_voucher_apply'), onPressed: _busy ? null : () => _apply(inv), child: Text(sw ? 'Tumia' : 'Apply')),
          ])
        else
          Row(children: <Widget>[
            Expanded(child: Text('${inv.voucherCode}: -${tsh(inv.voucherOff)}', key: const Key('salon_voucher_applied'), style: ThemeConstants.bodyStyle)),
            TextButton(
              key: const Key('salon_voucher_clear'),
              onPressed: () {
                inv.clearVoucher();
                _code.clear();
              },
              child: Text(sw ? 'Ondoa' : 'Remove'),
            ),
          ]),
        if (pointsOn) ...<Widget>[
          const SizedBox(height: 10),
          Text(sw ? 'Pointi za mteja: $balance (thamani ${tsh(balance * ((_loyalty['value'] as num?) ?? 0))})' : 'Client points: $balance (worth ${tsh(balance * ((_loyalty['value'] as num?) ?? 0))})', key: const Key('salon_points_balance'), style: ThemeConstants.captionStyle),
          if (balance > 0)
            Row(children: <Widget>[
              Expanded(child: TextField(key: const Key('salon_points'), controller: _points, keyboardType: TextInputType.number, decoration: ThemeConstants.invInputDecoration(sw ? 'Pointi za kutumia' : 'Points to use'), style: ThemeConstants.bodyStyle)),
              const SizedBox(width: 8),
              FilledButton(key: const Key('salon_points_apply'), onPressed: () => _usePoints(inv), child: Text(sw ? 'Tumia' : 'Use')),
            ]),
          if (inv.pointsUsed > 0) Text('-${tsh(inv.pointsOff)}', key: const Key('salon_points_off'), style: ThemeConstants.bodyStyle),
        ],
        if (serviceLines.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          for (final InvSaleItem l in serviceLines)
            SwitchListTile(
              key: Key('salon_pkg_${l.productId}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(sw ? 'Tumia kifurushi: ${l.name}' : 'Use a package for ${l.name}'),
              subtitle: Text(_packageFor(l) == null ? '' : '${_packageFor(l)!['name']} · ${_packageFor(l)!['sessions_left']} ${sw ? 'zimebaki' : 'left'}'),
              value: l.packageId != null,
              onChanged: (bool on) {
                final Map<String, dynamic>? p = _packageFor(l);
                if (on && p != null && l.qty > ((p['sessions_left'] as num?)?.toInt() ?? 0)) {
                  ThemeConstants.showErrorSnackBar(context, sw ? 'Kifurushi hakina vikao vya kutosha.' : 'The package does not have enough visits left.');
                  return;
                }
                inv.setLinePackage(l, on ? (p?['id'] as num?)?.toInt() : null);
              },
            ),
        ],
      ]),
      ),
    );
  }

  Map<String, dynamic>? _packageFor(final InvSaleItem l) {
    for (final Map<String, dynamic> p in _packages) {
      if ((p['service_product_id'] as num?)?.toInt() == l.productId) return p;
    }
    // A line already on a package keeps its switch even if the list reloaded.
    return null;
  }
}
