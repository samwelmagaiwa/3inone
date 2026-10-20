import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'client_extras.dart';
import 'salon_text.dart';

/// A client's page: how often they come, what they spend and like, when they are due back, what to remember about
/// them (hair type, allergies) and whether they may be texted.
class ClientHistoryScreen extends StatefulWidget {
  const ClientHistoryScreen({super.key, required this.customerId, required this.name, this.api, this.picker});

  final int customerId;

  /// Shown in the title while the page loads.
  final String name;

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// Chooses a photo (the gallery; a test passes its own).
  final PhotoPicker? picker;

  @override
  State<ClientHistoryScreen> createState() => _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends State<ClientHistoryScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  final TextEditingController _notes = TextEditingController();

  ClientHistory? _history;
  String? _error;
  bool _loading = true;
  bool _savingNotes = false;
  bool _savingSms = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ClientHistory h = await _api.clientHistory(widget.customerId);
      if (!mounted) return;
      setState(() {
        _history = h;
        _notes.text = h.notes ?? '';
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

  Future<void> _saveNotes() async {
    setState(() => _savingNotes = true);
    try {
      await _api.saveClient(widget.customerId, notes: _notes.text.trim());
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('saved'));
    } on Exception catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  Future<void> _setSmsOptOut(bool optOut) async {
    final ClientHistory? h = _history;
    if (h == null || _savingSms) return;
    setState(() => _savingSms = true);
    try {
      await _api.saveClient(widget.customerId, smsOptOut: optOut);
      if (!mounted) return;
      setState(() => _history = h.copyWith(smsOptOut: optOut));
    } on Exception catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _savingSms = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_history?.name ?? widget.name),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          backgroundColor: Colors.white,
          color: ThemeConstants.primaryBlue,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
            children: _body(sw),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(bool sw) {
    if (_loading && _history == null) {
      return <Widget>[SizedBox(height: 120.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];
    }
    if (_error != null && _history == null) {
      return <Widget>[
        SizedBox(height: 60.h),
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(
          child: TextButton(
            key: const ValueKey<String>('client_retry'),
            onPressed: _load,
            child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)),
          ),
        ),
      ];
    }

    final ClientHistory h = _history!;
    final NextVisit? next = h.nextVisit;

    return <Widget>[
      Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Row(
          children: <Widget>[
            Icon(Icons.person_outline, color: ThemeConstants.invAccent, size: 26.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(h.name, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                  Text(h.phone.isEmpty ? '—' : h.phone, style: ThemeConstants.captionStyle),
                ],
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 10.h),
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Ziara' : 'Visits', value: '${h.visitCount}', icon: Icons.event_available_outlined)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Jumla aliyotumia' : 'Total spent', value: tsh(h.totalSpent), icon: Icons.payments_outlined, accent: ThemeConstants.successGreen)),
        ],
      ),
      SizedBox(height: 8.h),
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Mara ya mwisho' : 'Last visit', value: h.lastVisitOn == null ? '—' : dayLabel(h.lastVisitOn!), icon: Icons.history)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Anachopenda' : 'Favourite', value: h.favouriteService ?? '—', icon: Icons.favorite_border)),
        ],
      ),
      if (next != null) ...<Widget>[
        SizedBox(height: 10.h),
        Container(
          key: const ValueKey<String>('client_next_visit'),
          decoration: ThemeConstants.glassCardDecoration,
          padding: EdgeInsets.all(12.w),
          child: Row(
            children: <Widget>[
              Icon(Icons.event_repeat_outlined, color: ThemeConstants.primaryCyan, size: 22.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  sw
                      ? 'Anatakiwa kurudi ${dayLabel(next.dueOn)} (${weeksLabel(sw: true, weeks: next.ruleWeeks)} baada ya ${next.service.isEmpty ? 'huduma' : next.service})'
                      : 'Due back ${dayLabel(next.dueOn)} (${weeksLabel(sw: false, weeks: next.ruleWeeks)} after ${next.service.isEmpty ? 'the service' : next.service})',
                  style: ThemeConstants.bodyStyle,
                ),
              ),
            ],
          ),
        ),
      ],
      SizedBox(height: 10.h),
      Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                sw ? 'Hapati ujumbe wa kurudi' : 'Do not text "come back" reminders',
                style: ThemeConstants.bodyStyle,
              ),
            ),
            Switch(
              key: const ValueKey<String>('client_sms_opt_out'),
              value: h.smsOptOut,
              onChanged: _savingSms ? null : _setSmsOptOut,
              activeThumbColor: Colors.white,
              activeTrackColor: ThemeConstants.warningAmber,
            ),
          ],
        ),
      ),
      SizedBox(height: 10.h),
      InvTextField(
        controller: _notes,
        label: sw ? 'Maelezo kuhusu mteja' : 'Notes about this client',
        hint: sw ? 'mfano: ngozi ina mzio wa rangi ya amonia' : 'e.g. allergic to ammonia dye',
        maxLines: 3,
        isOptional: false,
      ),
      SizedBox(height: 8.h),
      InvPrimaryButton(
        key: const ValueKey<String>('client_save_notes'),
        busy: _savingNotes,
        onPressed: _saveNotes,
        label: sw ? 'Hifadhi maelezo' : 'Save notes',
      ),
      SizedBox(height: 14.h),
      ClientExtras(key: ValueKey<int>(h.id), history: h, api: _api, picker: widget.picker),
      SizedBox(height: 14.h),
      Text(sw ? 'Ziara za nyuma' : 'Past visits', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(height: 8.h),
      if (h.visits.isEmpty)
        InvEmptyState(icon: Icons.receipt_long_outlined, message: sw ? 'Bado hajawahi kununua.' : 'Nothing bought yet.')
      else
        for (final ClientVisit v in h.visits) ...<Widget>[
          _VisitCard(visit: v, sw: sw),
          SizedBox(height: 8.h),
        ],
    ];
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit, required this.sw});

  final ClientVisit visit;
  final bool sw;

  @override
  Widget build(BuildContext context) => Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text('${dayLabel(visit.date)} • ${visit.number}', style: ThemeConstants.captionStyle)),
                Text(tsh(visit.total), style: TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w700, fontSize: 13.sp)),
              ],
            ),
            SizedBox(height: 6.h),
            for (final ClientVisitItem i in visit.items)
              Padding(
                padding: EdgeInsets.only(bottom: 2.h),
                child: Text(
                  '${i.qty > 1 ? '${i.qty} × ' : ''}${i.name}${i.isService && (i.staffName ?? '').isNotEmpty ? ' — ${i.staffName}' : ''}',
                  style: ThemeConstants.bodyStyle,
                ),
              ),
          ],
        ),
      );
}
