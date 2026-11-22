import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_governance_models.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

String dividendBaseLabel({required final bool sw, required final String base}) => base == 'average'
    ? (sw ? 'Wastani wa akiba katika kipindi' : 'Average savings over the period')
    : (sw ? 'Akiba mwisho wa kipindi' : 'Savings at the end of the period');

String dividendMethodLabel({required final bool sw, required final String method, final double? rate}) => method == 'rate'
    ? (sw ? 'Asilimia ${rate ?? ''}% ya akiba' : '${rate ?? ''}% of the savings')
    : (sw ? 'Faida inagawanywa kwa uwiano wa akiba' : 'The profit shared in proportion to savings');

String dividendStatusLabel({required final bool sw, required final String status}) => switch (status) {
      'draft' => sw ? 'Rasimu' : 'Draft',
      'posted' => sw ? 'Imelipwa kwenye akiba' : 'Credited to savings',
      'discarded' => sw ? 'Imeachwa' : 'Discarded',
      _ => status,
    };

Color dividendStatusColor(final String status) => switch (status) {
      'draft' => ThemeConstants.warningAmber,
      'posted' => ThemeConstants.successGreen,
      _ => Colors.white54,
    };

/// Dividend runs: the treasurer prepares one with the formula the group chose (every member's line shown), the chair approves and posts it.
class DividendsScreen extends StatefulWidget {
  const DividendsScreen({required this.api, required this.me, super.key});

  final GroupsApi api;
  final GroupMe me;

  @override
  State<DividendsScreen> createState() => _DividendsScreenState();
}

class _DividendsScreenState extends State<DividendsScreen> {
  List<GroupDividendRun> _runs = const <GroupDividendRun>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final List<GroupDividendRun> r = await widget.api.dividendRuns();
      if (mounted) {
        setState(() {
          _runs = r;
          _loading = false;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = readableErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(final int id) async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => DividendRunScreen(api: widget.api, me: widget.me, runId: id)));
    await _load();
  }

  Future<void> _prepare() async {
    final GroupDividendRun? run = await showModalBottomSheet<GroupDividendRun>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: _PrepareForm(api: widget.api)),
    );
    if (run != null && mounted) await _open(run.id);
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Gawio' : 'Dividends', flat: true),
      floatingActionButton: widget.me.can('prepare_dividends')
          ? FloatingActionButton.extended(
              key: const Key('grp_dividend_prepare'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _prepare,
              icon: const Icon(Icons.calculate_rounded),
              label: Text(sw ? 'Andaa gawio' : 'Prepare a dividend'),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
                  if (_error != null) GroupEmpty(_error!),
                  if (_runs.isEmpty && _error == null) GroupEmpty(sw ? 'Bado hakuna gawio.' : 'No dividends yet.'),
                  if (_runs.isNotEmpty)
                    GlowListCard(
                      dividerKey: 'grp_runs_div',
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: <Widget>[
                        for (final GroupDividendRun r in _runs)
                          ListTile(
                            key: Key('grp_run_${r.id}'),
                            onTap: () => _open(r.id),
                            title: Text('${dateLabel(r.periodFrom)} – ${dateLabel(r.periodTo)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            subtitle: Text('${tsh(r.total)} / ${tsh(r.profitPool)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            trailing: GroupPill(dividendStatusLabel(sw: sw, status: r.status), color: dividendStatusColor(r.status)),
                          ),
                      ],
                    ),
                ]),
              ),
      ),
    );
  }
}

/// One run: the formula, the total against the approved profit, and every member's line; the chair posts a draft, the treasurer may discard it.
class DividendRunScreen extends StatefulWidget {
  const DividendRunScreen({required this.api, required this.me, required this.runId, super.key});

  final GroupsApi api;
  final GroupMe me;
  final int runId;

  @override
  State<DividendRunScreen> createState() => _DividendRunScreenState();
}

class _DividendRunScreenState extends State<DividendRunScreen> {
  GroupDividendRun? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupDividendRun r = await widget.api.dividendRun(widget.runId);
      if (mounted) setState(() => _r = r);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  Future<void> _post(final GroupDividendRun r) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Idhinisha na ulipe gawio?' : 'Approve and credit the dividend?',
      message: '${tsh(r.total)} ${sw ? 'kwa wanachama' : 'to'} ${r.lines.length}${sw ? '' : ' member(s)'}, ${sw ? 'kwenye akiba zao' : 'into their savings'}.\n'
          '${sw ? 'Haiwezi kurudiwa kwa kipindi hiki.' : 'It cannot be paid again for this period.'}',
      yes: sw ? 'Idhinisha' : 'Approve',
      tone: GroupTone.positive,
    );
    if (!ok) return;
    try {
      final GroupDividendRun done = await widget.api.postDividend(r.id);
      if (!mounted) return;
      setState(() => _r = done);
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Gawio limelipwa kwenye akiba.' : 'Dividend credited to savings.');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _discard(final GroupDividendRun r) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool ok = await groupConfirm(context, title: sw ? 'Acha rasimu hii?' : 'Discard this draft?', message: '${dateLabel(r.periodFrom)} – ${dateLabel(r.periodTo)}', yes: sw ? 'Acha' : 'Discard', tone: GroupTone.danger);
    if (!ok) return;
    try {
      final GroupDividendRun done = await widget.api.discardDividend(r.id);
      if (mounted) setState(() => _r = done);
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupDividendRun? r = _r;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Gawio' : 'Dividend', flat: true),
      body: SafeArea(
        child: r == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : GroupEmpty(_error!))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: <Widget>[
                GlowCard(children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(child: Text('${dateLabel(r.periodFrom)} – ${dateLabel(r.periodTo)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                    GroupPill(dividendStatusLabel(sw: sw, status: r.status), color: dividendStatusColor(r.status)),
                  ]),
                  GroupDetailRow(sw ? 'Msingi' : 'Base', dividendBaseLabel(sw: sw, base: r.base)),
                  GroupDetailRow(sw ? 'Njia' : 'Method', dividendMethodLabel(sw: sw, method: r.method, rate: r.rate)),
                  GroupDetailRow(sw ? 'Faida iliyoidhinishwa' : 'Approved profit', tsh(r.profitPool)),
                  GroupDetailRow(sw ? 'Jumla ya gawio' : 'Total dividend', tsh(r.total), valueColor: ThemeConstants.invAccent),
                  if (r.note != null) GroupDetailRow(sw ? 'Uamuzi' : 'Decision', r.note!),
                  if (r.preparedByName != null) GroupDetailRow(sw ? 'Imeandaliwa na' : 'Prepared by', r.preparedByName!),
                  if (r.approvedByName != null) GroupDetailRow(sw ? 'Imeidhinishwa na' : 'Approved by', r.approvedByName!),
                ]),
                if (r.lines.isNotEmpty)
                  GlowListCard(
                    dividerKey: 'grp_divlines_div',
                    children: <Widget>[
                      for (final GroupDividendLine l in r.lines)
                        Row(children: <Widget>[
                          Expanded(child: Text(l.name, style: const TextStyle(color: Colors.white))),
                          Text('${tsh(l.base)} → ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          Text(tsh(l.amount), style: const TextStyle(color: ThemeConstants.successGreen, fontWeight: FontWeight.w800)),
                        ]),
                    ],
                  ),
                const SizedBox(height: 12),
                if (r.status == 'draft' && widget.me.can('approve_dividends'))
                  FilledButton.icon(
                    key: const Key('grp_dividend_post'),
                    style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 13)),
                    onPressed: () => _post(r),
                    icon: const Icon(Icons.verified_rounded),
                    label: Text(sw ? 'Idhinisha na ulipe' : 'Approve and credit'),
                  ),
                if (r.status == 'draft' && widget.me.can('prepare_dividends')) ...<Widget>[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('grp_dividend_discard'),
                    style: OutlinedButton.styleFrom(foregroundColor: ThemeConstants.errorRed, side: const BorderSide(color: ThemeConstants.errorRed), padding: const EdgeInsets.symmetric(vertical: 13)),
                    onPressed: () => _discard(r),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(sw ? 'Acha rasimu' : 'Discard the draft'),
                  ),
                ],
              ]),
      ),
    );
  }
}

/// Prepare a run: the period, the approved profit, the base and the method (the group's own decision, written down in the note).
class _PrepareForm extends StatefulWidget {
  const _PrepareForm({required this.api});

  final GroupsApi api;

  @override
  State<_PrepareForm> createState() => _PrepareFormState();
}

class _PrepareFormState extends State<_PrepareForm> {
  final TextEditingController _pool = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime _from = DateTime(DateTime.now().year);
  DateTime _to = DateTime.now();
  String _base = 'closing';
  String _method = 'rate';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pool.dispose();
    _rate.dispose();
    _note.dispose();
    super.dispose();
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double? pool = double.tryParse(_pool.text.trim());
    final double? rate = double.tryParse(_rate.text.trim());
    if (pool == null || pool < 1 || (_method == 'rate' && (rate == null || rate <= 0)) || _note.text.trim().length < 3) {
      setState(() => _error = sw ? 'Jaza faida iliyoidhinishwa, asilimia (kama ni kwa asilimia) na uamuzi.' : 'Fill in the approved profit, the rate (for a rate) and the decision.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GroupDividendRun run = await widget.api.prepareDividend(<String, dynamic>{
        'period_from': _iso(_from),
        'period_to': _iso(_to),
        'profit_pool': pool,
        'base': _base,
        'method': _method,
        if (_method == 'rate') 'rate': rate,
        'note': _note.text.trim(),
      });
      if (mounted) Navigator.pop(context, run);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    Widget date(final String label, final DateTime value, final ValueChanged<DateTime> set, final Key key) => Expanded(
          child: ListTile(
            key: key,
            contentPadding: EdgeInsets.zero,
            title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            subtitle: Text(dateLabel(_iso(value)), style: const TextStyle(color: Colors.white)),
            onTap: () async {
              final DateTime? d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2015), lastDate: DateTime.now());
              if (d != null) setState(() => set(d));
            },
          ),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(sw ? 'Andaa gawio' : 'Prepare a dividend', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(color: Colors.white12, height: 24),
          Row(children: <Widget>[
            date(sw ? 'Kuanzia' : 'From', _from, (final DateTime d) => _from = d, const Key('grp_div_from')),
            date(sw ? 'Hadi' : 'To', _to, (final DateTime d) => _to = d, const Key('grp_div_to')),
          ]),
          TextField(
            key: const Key('grp_div_pool'),
            controller: _pool,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(
              sw ? 'Faida iliyoidhinishwa kugawanywa' : 'Approved profit to share',
              helper: sw ? 'Baada ya matumizi na akiba ya kikundi, kama kikao kilivyoamua.' : 'After expenses and reserves, as the meeting decided.',
            ),
          ),
          const SizedBox(height: 10),
          Text(sw ? 'Msingi' : 'Base', style: const TextStyle(color: Colors.white70)),
          Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
            for (final String b in const <String>['closing', 'average'])
              ChoiceChip(key: Key('grp_div_base_$b'), label: Text(dividendBaseLabel(sw: sw, base: b)), selected: _base == b, onSelected: (_) => setState(() => _base = b)),
          ]),
          const SizedBox(height: 10),
          Text(sw ? 'Njia' : 'Method', style: const TextStyle(color: Colors.white70)),
          Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
            ChoiceChip(key: const Key('grp_div_method_rate'), label: Text(sw ? 'Asilimia ya akiba' : 'A % of savings'), selected: _method == 'rate', onSelected: (_) => setState(() => _method = 'rate')),
            ChoiceChip(key: const Key('grp_div_method_share'), label: Text(sw ? 'Gawanya faida yote' : 'Share out the profit'), selected: _method == 'share', onSelected: (_) => setState(() => _method = 'share')),
          ]),
          if (_method == 'rate') ...<Widget>[
            const SizedBox(height: 10),
            TextField(
              key: const Key('grp_div_rate'),
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Asilimia (%)' : 'Rate (%)'),
            ),
          ],
          const SizedBox(height: 10),
          TextField(key: const Key('grp_div_note'), controller: _note, maxLength: 255, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Uamuzi wa kikao (mfano: Mkutano Mkuu 2026)' : "The meeting's decision (e.g. AGM 2026)")),
          if (_error != null) Text(_error!, key: const Key('grp_div_error'), style: const TextStyle(color: ThemeConstants.errorText)),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('grp_div_send'),
            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.calculate_rounded),
            label: Text(sw ? 'Hesabu (rasimu)' : 'Work it out (draft)'),
          ),
        ]),
      ),
    );
  }
}

/// The member's own dividends.
class MyDividendsScreen extends StatefulWidget {
  const MyDividendsScreen({required this.api, super.key});

  final GroupsApi api;

  @override
  State<MyDividendsScreen> createState() => _MyDividendsScreenState();
}

class _MyDividendsScreenState extends State<MyDividendsScreen> {
  List<GroupMyDividend>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final List<GroupMyDividend> r = await widget.api.myDividends();
        if (mounted) setState(() => _rows = r);
      } on Exception catch (e) {
        if (mounted) setState(() => _error = readableErrorMessage(e));
      }
    });
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<GroupMyDividend>? rows = _rows;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Gawio langu' : 'My dividends', flat: true),
      body: SafeArea(
        child: rows == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : GroupEmpty(_error!))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: <Widget>[
                if (rows.isEmpty) GroupEmpty(sw ? 'Bado hujapata gawio.' : 'No dividends yet.'),
                if (rows.isNotEmpty)
                  GlowListCard(
                    dividerKey: 'grp_mydiv_div',
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    children: <Widget>[
                      for (final GroupMyDividend d in rows)
                        ListTile(
                          title: Text('${dateLabel(d.periodFrom)} – ${dateLabel(d.periodTo)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          subtitle: Text('${dividendMethodLabel(sw: sw, method: d.method, rate: d.rate)} · ${sw ? 'msingi' : 'base'} ${tsh(d.myBase)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                          trailing: Text(tsh(d.amount), style: const TextStyle(color: ThemeConstants.successGreen, fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
              ]),
      ),
    );
  }
}
