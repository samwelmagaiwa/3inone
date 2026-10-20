import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';

/// Hands a finished file to the person (share sheet by default; a test passes its own).
typedef FileSaver = Future<void> Function(Uint8List bytes, String filename);

Future<void> _shareFile(final Uint8List bytes, final String filename) async {
  final Directory dir = await getTemporaryDirectory();
  final File file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(<XFile>[XFile(file.path)], subject: filename);
}

/// The salon's reports as a file to share: sales, expenses, payroll, stylists, profit and loss, and the VAT/tax report,
/// as PDF or CSV, for this month, last month or today. Owner, managers and accountants only (the server checks too).
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, this.api, this.saver, this.today});

  final SalonApi? api;
  final FileSaver? saver;
  final DateTime? today;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  String _type = 'sales';
  String _format = 'pdf';
  String _period = 'month';
  bool _busy = false;

  static const List<String> types = <String>['sales', 'expenses', 'payroll', 'stylists', 'profit-loss', 'tax', 'cashbook'];

  static String typeLabel(final String t, final bool sw) {
    switch (t) {
      case 'sales':
        return sw ? 'Mauzo' : 'Sales';
      case 'expenses':
        return sw ? 'Matumizi' : 'Expenses';
      case 'payroll':
        return sw ? 'Mishahara' : 'Payroll';
      case 'stylists':
        return sw ? 'Watumishi' : 'Stylists';
      case 'profit-loss':
        return sw ? 'Faida na hasara' : 'Profit & loss';
      case 'cashbook':
        return sw ? 'Kitabu cha pesa' : 'Cashbook';
      default:
        return sw ? 'Kodi (VAT)' : 'Tax (VAT)';
    }
  }

  (DateTime, DateTime) _range() {
    final DateTime now = widget.today ?? DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (_period == 'today') return (today, today);
    if (_period == 'last') {
      final DateTime first = DateTime(today.year, today.month - 1);
      return (first, DateTime(today.year, today.month, 0));
    }
    return (DateTime(today.year, today.month), today);
  }

  Future<void> _go() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final (DateTime, DateTime) r = _range();
    setState(() => _busy = true);
    try {
      final Uint8List bytes = await _api.exportReport(_type, format: _format, sw: sw, from: r.$1, to: r.$2);
      final String name = 'salon_${_type}_${r.$2.year}-${r.$2.month.toString().padLeft(2, '0')}-${r.$2.day.toString().padLeft(2, '0')}.$_format';
      await (widget.saver ?? _shareFile)(bytes, name);
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
      Text(sw ? 'Ripoti' : 'Report', style: const TextStyle(fontWeight: FontWeight.bold)),
      Wrap(spacing: 8, children: <Widget>[
        for (final String t in types) ChoiceChip(key: Key('exp_type_$t'), label: Text(typeLabel(t, sw)), selected: _type == t, onSelected: (_) => setState(() => _type = t)),
      ]),
      const SizedBox(height: 16),
      Text(sw ? 'Kipindi' : 'Period', style: const TextStyle(fontWeight: FontWeight.bold)),
      Wrap(spacing: 8, children: <Widget>[
        ChoiceChip(key: const Key('exp_today'), label: Text(sw ? 'Leo' : 'Today'), selected: _period == 'today', onSelected: (_) => setState(() => _period = 'today')),
        ChoiceChip(key: const Key('exp_month'), label: Text(sw ? 'Mwezi huu' : 'This month'), selected: _period == 'month', onSelected: (_) => setState(() => _period = 'month')),
        ChoiceChip(key: const Key('exp_last'), label: Text(sw ? 'Mwezi uliopita' : 'Last month'), selected: _period == 'last', onSelected: (_) => setState(() => _period = 'last')),
      ]),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[ButtonSegment<String>(value: 'pdf', label: Text('PDF')), ButtonSegment<String>(value: 'csv', label: Text('CSV'))],
        selected: <String>{_format},
        onSelectionChanged: (Set<String> s) => setState(() => _format = s.first),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(key: const Key('exp_go'), onPressed: _busy ? null : _go, icon: const Icon(Icons.ios_share), label: Text(sw ? 'Tengeneza na Shiriki' : 'Create and share')),
    ]);
  }
}
