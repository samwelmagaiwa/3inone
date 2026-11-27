import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../widgets/scrolling_chip_row.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'payment_form.dart';
import 'promise_form.dart';
import 'statement_screen.dart';
import 'widgets/groups_ui.dart';

/// Contributions: the kinds the group asks for (and calling a month or an event), then who owes what -- owing, overdue, paid, excused --
/// and the promises made. From a line: record the member's payment, a promise, or excuse them (udhuru), each only for whoever may.
class ContributionsScreen extends StatefulWidget {
  const ContributionsScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<ContributionsScreen> createState() => _ContributionsScreenState();
}

class _ContributionsScreenState extends State<ContributionsScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _state = 'owing';
  List<GroupContributionType> _types = const <GroupContributionType>[];
  final List<GroupObligation> _rows = <GroupObligation>[];
  List<GroupPromise> _promises = const <GroupPromise>[];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({final bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<GroupContributionType> types = more ? _types : await widget.api.contributionTypes();
      final int page = more ? _page + 1 : 1;
      if (_state == 'promises') {
        final List<GroupPromise> promises = await widget.api.promises();
        if (!mounted) return;
        setState(() {
          _types = types;
          _promises = promises;
          _rows.clear();
          _hasMore = false;
          _loading = false;
        });
        return;
      }
      final GroupObligationPage got = await widget.api.obligations(state: _state, query: _search.text, page: page);
      if (!mounted) return;
      setState(() {
        _types = types;
        if (!more) _rows.clear();
        _rows.addAll(got.obligations);
        _page = page;
        _hasMore = got.hasMore;
        _loading = false;
      });
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = readableErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _changed(final String done) async {
    if (!mounted) return;
    ThemeConstants.showSuccessSnackBar(context, done);
    await _load();
    await widget.onChanged();
  }

  // ------------------------------------------------------------------ the kinds of contribution

  Future<void> _editType([final GroupContributionType? t]) async {
    final Map<String, dynamic>? body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _TypeDialog(type: t));
    if (body == null || !mounted) return;
    final bool sw = context.read<LocalizationService>().isSwahili;
    try {
      await widget.api.saveContributionType(body, id: t?.id);
      await _changed(sw ? 'Mchango umehifadhiwa.' : 'Contribution saved.');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _typeActions(final GroupContributionType t) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? picked = await groupActions(context, title: t.name, actions: <GroupSheetAction>[
      if (t.active) GroupSheetAction(icon: Icons.campaign_rounded, label: sw ? 'Itisha mchango' : 'Call it', value: 'raise', tone: GroupTone.positive),
      GroupSheetAction(icon: Icons.edit_outlined, label: sw ? 'Badili' : 'Edit', value: 'edit'),
    ]);
    if (picked == 'edit') await _editType(t);
    if (picked == 'raise') await _raise(t);
  }

  Future<void> _raise(final GroupContributionType t) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final Map<String, String>? call = await showDialog<Map<String, String>>(context: context, builder: (_) => _RaiseDialog(type: t));
    if (call == null || !mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Itisha mchango?' : 'Call this contribution?',
      message: '${t.name}: ${tsh(t.amount)} ${sw ? 'kwa kila mwanachama hai' : 'from every active member'}'
          '${call['month'] != null ? ' · ${call['month']}' : ''}${call['due_date'] != null ? ' · ${dateLabel(call['due_date'])}' : ''}${call['label'] != null ? ' · ${call['label']}' : ''}.',
      yes: sw ? 'Itisha' : 'Call it',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    try {
      final int n = await widget.api.raiseContribution(t.id, month: call['month'], dueDate: call['due_date'], label: call['label']);
      await _changed(sw ? 'Wanachama $n wanadaiwa mchango huu.' : '$n member(s) now owe it.');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  // ------------------------------------------------------------------ a line someone owes

  Future<void> _lineActions(final GroupObligation o) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final GroupMe me = widget.me;
    final bool mine = me.member?.id == o.memberId;
    final String? picked = await groupActions(context, title: '${o.memberName ?? ''} · ${o.title}', actions: <GroupSheetAction>[
      if (o.owing && me.can('record_payments'))
        GroupSheetAction(icon: Icons.payments_outlined, label: sw ? 'Rekodi malipo' : 'Record a payment', value: 'pay', tone: GroupTone.positive),
      if (o.owing && me.can('record_payments')) GroupSheetAction(icon: Icons.handshake_outlined, label: sw ? 'Weka ahadi' : 'Record a promise', value: 'promise'),
      if (o.owing && me.can('grant_exemptions') && !mine) GroupSheetAction(icon: Icons.volunteer_activism_outlined, label: sw ? 'Toa udhuru' : 'Excuse (udhuru)', value: 'exempt', tone: GroupTone.danger),
      GroupSheetAction(icon: Icons.receipt_long_outlined, label: sw ? 'Taarifa ya fedha' : 'Statement', value: 'statement'),
    ]);
    if (picked == null || !mounted) return;
    final GroupMember member = GroupMember(id: o.memberId, fullName: o.memberName ?? '', phone: '', status: 'active', memberNumber: o.memberNumber);
    switch (picked) {
      case 'pay':
        if (await showPaymentForm(context, api: widget.api, me: me, member: member, owing: <GroupObligation>[o], obligation: o)) await _load();
      case 'promise':
        if (await showPromiseForm(context, api: widget.api, owing: <GroupObligation>[o], memberId: o.memberId, memberName: o.memberName, obligation: o)) await _load();
      case 'exempt':
        final String? reason = await groupReason(
          context,
          title: sw ? 'Toa udhuru' : 'Excuse this member',
          message: '${o.memberName ?? ''} · ${o.title} · ${tsh(o.remaining)}. ${sw ? 'Hatadaiwa tena kiasi hiki. Andika sababu.' : 'They will no longer owe it. Write the reason.'}',
          yes: sw ? 'Toa udhuru' : 'Excuse',
        );
        if (reason == null) return;
        try {
          await widget.api.exempt(o.id, reason);
          await _changed(sw ? 'Udhuru umetolewa.' : 'Member excused.');
        } on Exception catch (e) {
          if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
        }
      case 'statement':
        await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => GroupStatementScreen(api: widget.api, memberId: o.memberId, memberName: o.memberName)));
    }
  }

  Future<void> _promiseActions(final GroupPromise p) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!widget.me.can('record_payments') || p.state == 'kept') return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Ondoa ahadi?' : 'Withdraw this promise?',
      message: '${p.memberName ?? ''}: ${tsh(p.amount)} · ${dateLabel(p.promisedOn)}',
      yes: sw ? 'Ondoa' : 'Withdraw',
      tone: GroupTone.danger,
    );
    if (!ok) return;
    try {
      await widget.api.cancelPromise(p.id);
      await _changed(sw ? 'Ahadi imeondolewa.' : 'Promise withdrawn.');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool mayManage = widget.me.can('manage_contributions');
    final List<(String, String)> filters = <(String, String)>[
      ('owing', sw ? 'Wanadaiwa' : 'Owing'),
      ('overdue', sw ? 'Imepita muda' : 'Overdue'),
      ('paid', sw ? 'Imelipwa' : 'Paid'),
      ('exempt', sw ? 'Udhuru' : 'Excused'),
      ('promises', sw ? 'Ahadi' : 'Promises'),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: mayManage
          ? FloatingActionButton.extended(
              key: const Key('grp_type_add'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _editType,
              icon: const Icon(Icons.add_rounded),
              label: Text(sw ? 'Mchango mpya' : 'New contribution'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: joinGlowCards(<Widget>[
            ScrollingChipRow(padding: EdgeInsets.zero, children: <Widget>[
                for (final (String, String) f in filters)
                  ScrollChoiceChip(chipKey: Key('grp_obl_filter_${f.$1}'),
                      label: f.$2,
                      selected: _state == f.$1,
                      onSelected: (_) {
                        setState(() => _state = f.$1);
                        _load();
                      },
                    ),
              ]),
            const SizedBox(height: 8),
            if (_state != 'promises')
              TextField(
                key: const Key('grp_obl_search'),
                controller: _search,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), _load);
                },
                style: const TextStyle(color: Colors.white),
                decoration: ThemeConstants.darkField(sw ? 'Tafuta jina au namba' : 'Search name or number', prefix: const Icon(Icons.search, color: Colors.white54)),
              ),
            const SizedBox(height: 10),
            if (_types.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_types_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[
                  for (final GroupContributionType t in _types)
                    ListTile(
                      key: Key('grp_type_${t.id}'),
                      onTap: mayManage ? () => _typeActions(t) : null,
                      leading: Icon(Icons.savings_outlined, color: t.active ? ThemeConstants.invAccent : Colors.white38),
                      title: Text(t.name, style: TextStyle(color: t.active ? Colors.white : Colors.white54, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${frequencyLabel(sw: sw, frequency: t.frequency, dueDay: t.dueDay)}${t.mandatory ? '' : (sw ? ' · hiari' : ' · optional')}${t.active ? '' : (sw ? ' · imesimamishwa' : ' · switched off')}',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      trailing: Text(tsh(t.amount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            if (_error != null) GroupEmpty(_error!),
            if (!_loading && _error == null && _state != 'promises' && _rows.isEmpty)
              GroupEmpty(_types.isEmpty ? (sw ? 'Bado hakuna mchango. Ongeza mchango wa kwanza.' : 'No contribution yet. Add the first one.') : (sw ? 'Hakuna hapa.' : 'Nothing here.')),
            if (!_loading && _error == null && _state == 'promises' && _promises.isEmpty) GroupEmpty(sw ? 'Hakuna ahadi.' : 'No promises.'),
            if (_rows.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_obl_div',
                children: <Widget>[for (final GroupObligation o in _rows) ObligationLine(o: o, sw: sw, showMember: true, onTap: () => _lineActions(o))],
              ),
            if (_state == 'promises' && _promises.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_prom_div',
                children: <Widget>[for (final GroupPromise p in _promises) PromiseLine(p: p, sw: sw, showMember: true, onTap: () => _promiseActions(p))],
              ),
            if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_hasMore && !_loading)
              TextButton(
                onPressed: () => _load(more: true),
                child: Text(LocalizationService.instance.translate('list_show_more'), style: const TextStyle(color: ThemeConstants.primaryOrange)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Add or change a kind of contribution.
class _TypeDialog extends StatefulWidget {
  const _TypeDialog({this.type});

  final GroupContributionType? type;

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.type?.name);
  late final TextEditingController _amount = TextEditingController(text: widget.type == null ? '' : widget.type!.amount.toStringAsFixed(0));
  late final TextEditingController _day = TextEditingController(text: '${widget.type?.dueDay ?? 5}');
  late String _frequency = widget.type?.frequency ?? 'monthly';
  late bool _mandatory = widget.type?.mandatory ?? true;
  late bool _active = widget.type?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  bool get _ready =>
      _name.text.trim().length >= 2 &&
      (double.tryParse(_amount.text.trim()) ?? 0) >= 1 &&
      (_frequency != 'monthly' || ((int.tryParse(_day.text.trim()) ?? 0) >= 1 && (int.tryParse(_day.text.trim()) ?? 0) <= 31));

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      key: const Key('grp_type_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.type == null ? (sw ? 'Mchango mpya' : 'New contribution') : widget.type!.name,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          // As wide as the screen allows, not as narrow as the fields' hints.
          const SizedBox(width: double.maxFinite),
          TextField(
            key: const Key('grp_type_name'),
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Jina (mfano: JAMII)' : 'Name (e.g. JAMII)'),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('grp_type_amount'),
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Kiasi kwa kila mwanachama' : 'Amount per member'),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: <Widget>[
            for (final String f in contributionFrequencies)
              ChoiceChip(
                key: Key('grp_type_freq_$f'),
                label: Text(frequencyLabel(sw: sw, frequency: f)),
                selected: _frequency == f,
                onSelected: (_) => setState(() => _frequency = f),
              ),
          ]),
          if (_frequency == 'monthly') ...<Widget>[
            const SizedBox(height: 10),
            TextField(
              key: const Key('grp_type_day'),
              controller: _day,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Tarehe ya kulipa kila mwezi (1-31)' : 'Day of the month it is due (1-31)'),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _mandatory,
            onChanged: (final bool v) => setState(() => _mandatory = v),
            title: Text(sw ? 'Ni lazima' : 'Mandatory', style: const TextStyle(color: Colors.white)),
          ),
          if (widget.type != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (final bool v) => setState(() => _active = v),
              title: Text(sw ? 'Unaendelea' : 'Running', style: const TextStyle(color: Colors.white)),
            ),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_type_save'),
          onPressed: _ready
              ? () => Navigator.pop(context, <String, dynamic>{
                    'name': _name.text.trim(),
                    'amount': double.parse(_amount.text.trim()),
                    'frequency': _frequency,
                    if (_frequency == 'monthly') 'due_day': int.parse(_day.text.trim()),
                    'mandatory': _mandatory,
                    'active': _active,
                    'starts_on': widget.type?.startsOn,
                  })
              : null,
          child: Text(sw ? 'Hifadhi' : 'Save', style: TextStyle(color: _ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// When a call is for: a month (monthly), or a due date (once), plus what it is for (an event).
class _RaiseDialog extends StatefulWidget {
  const _RaiseDialog({required this.type});

  final GroupContributionType type;

  @override
  State<_RaiseDialog> createState() => _RaiseDialogState();
}

class _RaiseDialogState extends State<_RaiseDialog> {
  final TextEditingController _label = TextEditingController();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _due = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool monthly = widget.type.frequency == 'monthly';
    final bool event = widget.type.frequency == 'event';
    final bool ready = !event || _label.text.trim().length >= 3;
    final String month = '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      key: const Key('grp_raise_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('${sw ? 'Itisha' : 'Call'} ${widget.type.name}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        // As wide as the screen allows, not as narrow as the fields' hints.
        const SizedBox(width: double.maxFinite),
        if (monthly)
          Row(children: <Widget>[
            IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white70), onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
            Expanded(child: Text(month, key: const Key('grp_raise_month'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white70), onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
          ])
        else ...<Widget>[
          if (event)
            TextField(
              key: const Key('grp_raise_label'),
              controller: _label,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Ni kwa ajili ya (mfano: harusi ya Juma)' : "What for (e.g. Juma's wedding)"),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined, color: Colors.white54),
            title: Text(sw ? 'Mwisho wa kulipa' : 'Due by', style: const TextStyle(color: Colors.white70)),
            trailing: Text(dateLabel(_iso(_due)), style: const TextStyle(color: Colors.white)),
            onTap: () async {
              final DateTime now = DateTime.now();
              final DateTime? d = await showDatePicker(context: context, initialDate: _due, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 2));
              if (d != null) setState(() => _due = d);
            },
          ),
        ],
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_raise_next'),
          onPressed: ready
              ? () => Navigator.pop(context, <String, String>{
                    if (monthly) 'month': month,
                    if (!monthly) 'due_date': _iso(_due),
                    if (event) 'label': _label.text.trim(),
                  })
              : null,
          child: Text(sw ? 'Endelea' : 'Next', style: TextStyle(color: ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
