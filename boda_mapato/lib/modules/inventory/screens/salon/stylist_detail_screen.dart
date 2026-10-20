import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_text.dart';

/// Every service behind one stylist's total: when, for whom, what it was worth, the discount it carried, what is left,
/// what the stylist earns on it and how it was paid. The owner opens it from the Stylists page; a stylist sees only
/// their own. (Revenue, commission and cash handed over are three different figures: this page is the first two.)
class StylistDetailScreen extends StatefulWidget {
  const StylistDetailScreen({super.key, required this.title, required this.staffId, required this.from, required this.to, this.api});

  /// The name shown at the top while the page loads.
  final String title;

  /// The stylist's account id; null = the services nobody was named for.
  final String? staffId;
  final DateTime from;
  final DateTime to;

  /// The server calls (a fake in tests).
  final SalonApi? api;

  @override
  State<StylistDetailScreen> createState() => _StylistDetailScreenState();
}

class _StylistDetailScreenState extends State<StylistDetailScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();

  StylistPage? _page;
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
      final StylistPage page = await _api.stylistPage(widget.staffId, from: widget.from, to: widget.to);
      if (!mounted) return;
      setState(() {
        _page = page;
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

    return ThemeConstants.buildScaffold(
      title: widget.title,
      body: RefreshIndicator(
        onRefresh: _load,
        backgroundColor: Colors.white,
        color: ThemeConstants.primaryBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
          children: _body(sw),
        ),
      ),
    );
  }

  List<Widget> _body(bool sw) {
    if (_loading && _page == null) {
      return <Widget>[SizedBox(height: 120.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];
    }
    if (_error != null && _page == null) {
      return <Widget>[
        SizedBox(height: 60.h),
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(
          child: TextButton(
            key: const ValueKey<String>('stylist_page_retry'),
            onPressed: _load,
            child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)),
          ),
        ),
      ];
    }

    final StylistPage page = _page!;

    return <Widget>[
      Text(
        '${dayLabel(page.from)} – ${dayLabel(page.to)}',
        key: const ValueKey<String>('stylist_page_period'),
        style: ThemeConstants.captionStyle,
      ),
      SizedBox(height: 8.h),
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Mapato halisi' : 'Net revenue', value: tsh(page.net), icon: Icons.payments_outlined, accent: ThemeConstants.successGreen)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Kamisheni' : 'Commission', value: tsh(page.commission), icon: Icons.percent_rounded, accent: ThemeConstants.warningAmber)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Huduma' : 'Services', value: '${page.services}', icon: Icons.content_cut_rounded)),
        ],
      ),
      if (page.discount > 0) ...<Widget>[
        SizedBox(height: 6.h),
        Text(
          sw ? 'Thamani ${tsh(page.value)} – punguzo ${tsh(page.discount)}' : 'Worth ${tsh(page.value)} – discount ${tsh(page.discount)}',
          key: const ValueKey<String>('stylist_page_discount'),
          style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.warningAmber),
        ),
      ],
      SizedBox(height: 12.h),
      if (page.lines.isEmpty)
        InvEmptyState(icon: Icons.content_cut_rounded, message: sw ? 'Hakuna huduma kwa kipindi hiki.' : 'No services in this period.')
      else
        for (int i = 0; i < page.lines.length; i++) ...<Widget>[
          _LineCard(index: i, line: page.lines[i], sw: sw),
          SizedBox(height: 8.h),
        ],
    ];
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.index, required this.line, required this.sw});

  final int index;
  final StylistLine line;
  final bool sw;

  (String, Color) _status() {
    switch (line.paymentStatus) {
      case 'paid':
        return (sw ? 'Imelipwa' : 'Paid', ThemeConstants.successGreen);
      case 'partial':
        return (sw ? 'Sehemu' : 'Part paid', ThemeConstants.warningAmber);
      default:
        return (sw ? 'Deni' : 'Owing', ThemeConstants.errorRed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (String status, Color color) = _status();
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Container(
      key: ValueKey<String>('stylist_line_$index'),
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('${dayLabel(line.date)} ${hm(line.date)} • ${line.number}', style: ThemeConstants.captionStyle)),
              InvBadge(label: status, color: color),
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            line.qty > 1 ? '${line.service} × ${line.qty}' : line.service,
            style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(line.client ?? (sw ? 'Mteja wa kawaida (hakutajwa)' : 'Walk-in client'), style: ThemeConstants.captionStyle),
          SizedBox(height: 6.h),
          Row(
            children: <Widget>[
              Expanded(child: Text(line.discount > 0 ? '${tsh(line.value)} − ${tsh(line.discount)}' : tsh(line.value), style: ThemeConstants.captionStyle.copyWith(color: Colors.white70))),
              Text(tsh(line.net), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, color: ThemeConstants.invAccent)),
            ],
          ),
          if (line.discountReason != null)
            Text(sw ? 'Punguzo: ${line.discountReason}' : 'Discount: ${line.discountReason}', style: ThemeConstants.captionStyle.copyWith(fontStyle: FontStyle.italic)),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 4.h,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final String m in line.methods) InvBadge(label: channelLabel(sw: sw, channel: m), color: ThemeConstants.primaryCyan),
              if (line.commission > 0) Text(sw ? 'Kamisheni ${tsh(line.commission)}' : 'Commission ${tsh(line.commission)}', style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.warningAmber)),
            ],
          ),
        ],
      ),
    );
  }
}
