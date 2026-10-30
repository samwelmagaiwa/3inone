import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/trash_api.dart';
import '../salon/salon_text.dart';
import '../widgets/inventory_widgets.dart';

/// The Trash: what the owner or an admin deleted. Deleting only moves a record here (it stops counting in the lists, the totals and the
/// reports); here it can be restored exactly as it was, or removed for good (refused when it has history the business must keep). Cancelled
/// sales are listed too, for the record: they cannot be restored because their goods and payments were reversed.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, this.api, this.initialType = 'expenses'});

  /// The server calls (a fake in tests).
  final TrashApi? api;

  /// Which kind is open first.
  final String initialType;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  late final TrashApi _api = widget.api ?? TrashApi();

  static const List<String> _types = <String>['expenses', 'customers', 'debts', 'products', 'sales'];

  late String _type = widget.initialType;
  final List<TrashItem> _items = <TrashItem>[];
  Map<String, int> _counts = <String, int>{};
  int _page = 1;
  int _lastPage = 1;
  bool _loading = true;
  bool _more = false;
  String? _error;
  int _generation = 0;
  final Set<int> _busy = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _label(String type, bool sw) {
    switch (type) {
      case 'expenses':
        return sw ? 'Matumizi' : 'Expenses';
      case 'customers':
        return sw ? 'Wateja' : 'Customers';
      case 'debts':
        return sw ? 'Madeni' : 'Debts';
      case 'products':
        return sw ? 'Bidhaa na huduma' : 'Products & services';
      default:
        return sw ? 'Mauzo yaliyofutwa' : 'Cancelled sales';
    }
  }

  Future<void> _load() async {
    final int mine = ++_generation;
    final String type = _type;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final TrashPage page = await _api.list(type: type);
      if (!mounted || mine != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _counts = page.counts;
        _page = page.page;
        _lastPage = page.lastPage;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted || mine != _generation) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _showMore() async {
    if (_more) return;
    final int mine = _generation;
    setState(() => _more = true);
    try {
      final TrashPage next = await _api.list(type: _type, page: _page + 1);
      if (!mounted || mine != _generation) return;
      setState(() {
        _items.addAll(next.items);
        _counts = next.counts;
        _page = next.page;
        _lastPage = next.lastPage;
        _more = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _more = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _restore(TrashItem item, bool sw, {String? sku}) async {
    setState(() => _busy.add(item.id));
    try {
      await _api.restore(item.type, item.id, sku: sku);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? '"${item.title}" imerudishwa.' : '"${item.title}" was restored.');
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      final String message = readableErrorMessage(e);
      // A product whose SKU was taken meanwhile: ask for a new one and try again.
      if (item.type == 'products' && message.toLowerCase().contains('sku')) {
        final String? fresh = await _askSku(message, sw);
        if (fresh != null && fresh.trim().isNotEmpty && mounted) {
          setState(() => _busy.remove(item.id));
          await _restore(item, sw, sku: fresh);
          return;
        }
      } else {
        ThemeConstants.showErrorSnackBar(context, message);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<String?> _askSku(String message, bool sw) {
    final TextEditingController c = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        title: Text(sw ? 'Weka SKU mpya' : 'Give it a new SKU', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, style: ThemeConstants.captionStyle),
            SizedBox(height: 10.h),
            TextField(key: const ValueKey<String>('trash_new_sku'), controller: c, style: ThemeConstants.bodyStyle, decoration: ThemeConstants.invInputDecoration(sw ? 'SKU mpya' : 'New SKU')),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white70))),
          FilledButton(key: const ValueKey<String>('trash_new_sku_ok'), onPressed: () => Navigator.pop(ctx, c.text), child: Text(sw ? 'Rudisha' : 'Restore')),
        ],
      ),
    );
  }

  Future<void> _remove(TrashItem item, bool sw) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        title: Text(sw ? 'Futa kabisa?' : 'Delete for good?', style: const TextStyle(color: Colors.white)),
        content: Text(
          sw ? '"${item.title}" itaondolewa kabisa na haiwezi kurudishwa.' : '"${item.title}" will be removed for good and cannot be brought back.',
          style: ThemeConstants.captionStyle,
        ),
        actions: <Widget>[
          TextButton(key: const ValueKey<String>('trash_remove_no'), onPressed: () => Navigator.pop(ctx, false), child: Text(sw ? 'Hapana' : 'Keep it', style: const TextStyle(color: Colors.white70))),
          TextButton(key: const ValueKey<String>('trash_remove_yes'), onPressed: () => Navigator.pop(ctx, true), child: Text(sw ? 'Futa kabisa' : 'Delete for good', style: const TextStyle(color: ThemeConstants.errorText, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _busy.add(item.id));
    try {
      await _api.remove(item.type, item.id);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imefutwa kabisa.' : 'Removed for good.');
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return RefreshIndicator(
      onRefresh: _load,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
        children: <Widget>[
          Container(
            key: const ValueKey<String>('trash_intro'),
            decoration: ThemeConstants.glassCardDecoration,
            padding: EdgeInsets.all(12.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.delete_outline, color: Colors.white70, size: 20.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    sw
                        ? 'Vitu ulivyofuta vinakaa hapa. Havihesabiwi kwenye ripoti zako. Unaweza kuvirudisha kama vilivyokuwa, au kuvifuta kabisa.'
                        : 'What you deleted stays here. It does not count in your reports. You can bring it back exactly as it was, or delete it for good.',
                    style: ThemeConstants.captionStyle,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          InvFilterChips<String>(
            value: _type,
            options: <String, String>{for (final String t in _types) t: '${_label(t, sw)}${(_counts[t] ?? 0) > 0 ? ' (${_counts[t]})' : ''}'},
            onSelected: (String t) {
              if (t == _type) return;
              setState(() => _type = t);
              _load();
            },
          ),
          SizedBox(height: 12.h),
          ..._body(sw),
        ],
      ),
    );
  }

  List<Widget> _body(bool sw) {
    if (_loading && _items.isEmpty) {
      return <Widget>[SizedBox(height: 90.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];
    }
    if (_error != null && _items.isEmpty) {
      return <Widget>[
        SizedBox(height: 30.h),
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('trash_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ];
    }
    if (_items.isEmpty) {
      return <Widget>[
        InvEmptyState(
          icon: Icons.delete_outline,
          message: _type == 'sales' ? (sw ? 'Hakuna mauzo yaliyofutwa.' : 'No sale has been cancelled.') : (sw ? 'Hakuna kilichofutwa hapa.' : 'Nothing deleted here.'),
        ),
      ];
    }

    return <Widget>[
      if (_type == 'sales')
        Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: Text(
            sw ? 'Mauzo yaliyofutwa hubaki kwa kumbukumbu. Hayarudishwi kwa sababu bidhaa na malipo yalirudishwa.' : 'Cancelled sales are kept for the record. They cannot be restored because their goods and payments were reversed.',
            key: const ValueKey<String>('trash_sales_note'),
            style: ThemeConstants.captionStyle,
          ),
        ),
      for (final TrashItem item in _items) ...<Widget>[_card(item, sw), SizedBox(height: 8.h)],
      if (_page < _lastPage)
        Center(
          child: TextButton(
            key: const ValueKey<String>('trash_more'),
            onPressed: _more ? null : _showMore,
            child: Text(_more ? (sw ? 'Inapakia…' : 'Loading…') : (sw ? 'Onyesha zaidi' : 'Show more'), style: const TextStyle(color: Colors.white)),
          ),
        ),
    ];
  }

  Widget _card(TrashItem item, bool sw) {
    final bool busy = _busy.contains(item.id);
    final String when = item.deletedAt == null ? '' : dayLabel(item.deletedAt!.toLocal());

    return Container(
      key: ValueKey<String>('trash_item_${item.type}_${item.id}'),
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800))),
              if (item.amount != null) ...<Widget>[SizedBox(width: 8.w), Text(tsh(item.amount!), style: TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w800, fontSize: 14.sp))],
            ],
          ),
          if (item.subtitle.isNotEmpty) Padding(padding: EdgeInsets.only(top: 2.h), child: Text(item.subtitle, style: ThemeConstants.captionStyle)),
          SizedBox(height: 4.h),
          Text(
            <String>[
              if (item.type == 'sales') (sw ? 'Yalifutwa' : 'Cancelled') else (sw ? 'Ilifutwa' : 'Deleted'),
              if (when.isNotEmpty) when,
              if (item.deletedBy != null) (sw ? 'na ${item.deletedBy}' : 'by ${item.deletedBy}'),
            ].join(' · '),
            style: ThemeConstants.captionStyle,
          ),
          if (item.reason != null) Padding(padding: EdgeInsets.only(top: 2.h), child: Text('${sw ? 'Sababu' : 'Reason'}: ${item.reason}', style: ThemeConstants.captionStyle.copyWith(fontStyle: FontStyle.italic))),
          if (item.canRestore || item.canRemove) ...<Widget>[
            SizedBox(height: 10.h),
            Row(
              children: <Widget>[
                if (item.canRestore)
                  Expanded(
                    child: FilledButton.icon(
                      key: ValueKey<String>('trash_restore_${item.id}'),
                      style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen),
                      onPressed: busy ? null : () => _restore(item, sw),
                      icon: const Icon(Icons.restore, size: 18, color: Colors.white),
                      label: Text(sw ? 'Rudisha' : 'Restore', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
                if (item.canRestore && item.canRemove) SizedBox(width: 8.w),
                if (item.canRemove)
                  Expanded(
                    child: OutlinedButton.icon(
                      key: ValueKey<String>('trash_remove_${item.id}'),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: ThemeConstants.errorText.withValues(alpha: 0.7))),
                      onPressed: busy ? null : () => _remove(item, sw),
                      icon: const Icon(Icons.delete_forever_outlined, size: 18, color: ThemeConstants.errorText),
                      label: Text(sw ? 'Futa kabisa' : 'Delete for good', style: const TextStyle(color: ThemeConstants.errorText, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
