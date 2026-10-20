import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'client_history_screen.dart';
import 'salon_text.dart';

/// "Come back" reminders. The owner switches them on, says after how many weeks a client is texted by default (a
/// service can have its own number on its form), and sees who is due now and whether they were texted. The text
/// itself goes out every morning from the server.
class RebookScreen extends StatefulWidget {
  const RebookScreen({super.key, this.api});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  @override
  State<RebookScreen> createState() => _RebookScreenState();
}

class _RebookScreenState extends State<RebookScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();

  RebookOverview? _overview;
  String? _error;
  bool _loading = true;
  bool _saving = false;

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
      final RebookOverview o = await _api.rebookOverview();
      if (!mounted) return;
      setState(() {
        _overview = o;
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

  Future<void> _save({bool? enabled, int? weeks}) async {
    final RebookOverview? current = _overview;
    if (current == null || _saving) return;
    setState(() {
      _saving = true;
      // shown at once; undone below if the server says no
      _overview = RebookOverview(settings: current.settings.copyWith(enabled: enabled, weeks: weeks), clients: current.clients);
    });
    try {
      final RebookSettings saved = await _api.saveRebookSettings(enabled: enabled, weeks: weeks);
      if (!mounted) return;
      setState(() {
        _overview = RebookOverview(settings: saved, clients: current.clients);
        _saving = false;
      });
      // switching it on or changing the wait changes who is due
      if (enabled != null || weeks != null) await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _overview = current;
        _saving = false;
      });
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Material(
      color: ThemeConstants.primaryBlue,
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
    );
  }

  List<Widget> _body(bool sw) {
    if (_loading && _overview == null) {
      return <Widget>[SizedBox(height: 120.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];
    }
    if (_error != null && _overview == null) {
      return <Widget>[
        SizedBox(height: 60.h),
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(
          child: TextButton(
            key: const ValueKey<String>('rebook_retry'),
            onPressed: _load,
            child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)),
          ),
        ),
      ];
    }

    final RebookOverview overview = _overview!;
    final RebookSettings s = overview.settings;

    return <Widget>[
      _settingsCard(s, sw),
      SizedBox(height: 14.h),
      Text(
        sw ? 'Wanaotakiwa kurudi sasa (${overview.clients.length})' : 'Due to come back now (${overview.clients.length})',
        key: const ValueKey<String>('rebook_due_title'),
        style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 8.h),
      if (overview.clients.isEmpty)
        InvEmptyState(
          icon: Icons.event_available_outlined,
          message: sw ? 'Hakuna mteja anayetakiwa kurudi leo.' : 'No client is due to come back today.',
        )
      else
        for (final RebookClient c in overview.clients) ...<Widget>[
          _ClientCard(client: c, remindersOn: s.enabled, sw: sw),
          SizedBox(height: 8.h),
        ],
    ];
  }

  Widget _settingsCard(RebookSettings s, bool sw) => Container(
        key: const ValueKey<String>('rebook_settings_card'),
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.notifications_active_outlined, color: ThemeConstants.invAccent, size: 22.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    sw ? 'Vikumbusho vya kurudi' : '"Come back" reminders',
                    style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Switch(
                  key: const ValueKey<String>('rebook_switch'),
                  value: s.enabled,
                  onChanged: _saving ? null : (bool v) => _save(enabled: v),
                  activeThumbColor: Colors.white,
                  activeTrackColor: ThemeConstants.invAccent,
                ),
              ],
            ),
            SizedBox(height: 6.h),
            Text(
              sw
                  ? 'Mteja akishahudumiwa, atatumiwa ujumbe wa kumkaribisha tena baada ya idadi ya wiki uliyoweka. Kila huduma inaweza kuwa na idadi yake kwenye fomu ya huduma. Kila ziara hutumiwa ujumbe mara moja.'
                  : 'After a client has been served, they get a text inviting them back after the number of weeks you set. Each service can have its own number on its form. Each visit is texted once.',
              style: ThemeConstants.captionStyle,
            ),
            SizedBox(height: 10.h),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    sw ? 'Wiki za kawaida kabla ya kumkumbusha' : 'Usual wait before the reminder',
                    style: ThemeConstants.bodyStyle,
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('rebook_weeks_minus'),
                  onPressed: _saving || s.weeks <= 1 ? null : () => _save(weeks: s.weeks - 1),
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                ),
                SizedBox(
                  width: 78.w,
                  child: Text(
                    weeksLabel(sw: sw, weeks: s.weeks),
                    key: const ValueKey<String>('rebook_weeks_value'),
                    textAlign: TextAlign.center,
                    style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('rebook_weeks_plus'),
                  onPressed: _saving || s.weeks >= s.maxWeeks ? null : () => _save(weeks: s.weeks + 1),
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                ),
              ],
            ),
            if (!s.enabled)
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: Text(
                  sw ? 'Vimezimwa: hakuna ujumbe unaotumwa.' : 'Switched off: no text is sent.',
                  key: const ValueKey<String>('rebook_off_note'),
                  style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.warningAmber),
                ),
              ),
          ],
        ),
      );
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.remindersOn, required this.sw});

  final RebookClient client;
  final bool remindersOn;
  final bool sw;

  (String, Color) _status() {
    if (!client.canText) {
      return client.skipReason == 'opted_out'
          ? (sw ? 'Amekataa ujumbe' : 'Opted out', ThemeConstants.warningAmber)
          : (sw ? 'Hana namba ya simu' : 'No phone number', ThemeConstants.warningAmber);
    }
    if (client.sent) return (sw ? 'Ametumiwa' : 'Texted', ThemeConstants.successGreen);
    if (!remindersOn) return (sw ? 'Vimezimwa' : 'Off', Colors.white54);
    return (sw ? 'Atatumiwa' : 'Will be texted', ThemeConstants.primaryCyan);
  }

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = _status();

    return InkWell(
      key: ValueKey<String>('rebook_client_${client.customerId}'),
      borderRadius: BorderRadius.circular(20.r),
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => ClientHistoryScreen(customerId: client.customerId, name: client.name)),
      ),
      child: Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(client.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
                SizedBox(width: 8.w),
                InvBadge(label: label, color: color),
              ],
            ),
            SizedBox(height: 4.h),
            Text(client.phone.isEmpty ? '—' : client.phone, style: ThemeConstants.captionStyle),
            SizedBox(height: 6.h),
            Text(
              '${client.service.isEmpty ? (sw ? 'Huduma' : 'Service') : client.service} • ${dayLabel(client.visitOn)} • ${weeksAgo(sw: sw, weeks: client.weeksWaited)}',
              style: ThemeConstants.captionStyle.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
