import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_loan_models.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/amount_dialogs.dart';
import 'widgets/groups_ui.dart';

/// Welfare for the officers: the requests by stage; the chair approves (with the amount) or turns down, the treasurer pays an approved one.
/// Nobody decides or pays their own request (the server refuses it too).
class WelfareScreen extends StatefulWidget {
  const WelfareScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<WelfareScreen> createState() => _WelfareScreenState();
}

class _WelfareScreenState extends State<WelfareScreen> {
  String? _status = 'submitted';
  List<GroupBenefitRequest> _rows = const <GroupBenefitRequest>[];
  List<GroupBenefitType> _types = const <GroupBenefitType>[];
  bool _loading = true;
  String? _error;

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
      final List<GroupBenefitRequest> rows = await widget.api.benefits(status: _status);
      final List<GroupBenefitType> types = await widget.api.benefitTypes();
      if (mounted) {
        setState(() {
          _rows = rows;
          _types = types;
          _loading = false;
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

  Future<void> _done(final String text) async {
    if (!mounted) return;
    ThemeConstants.showSuccessSnackBar(context, text);
    await _load();
    await widget.onChanged();
  }

  Future<void> _act(final GroupBenefitRequest r) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final GroupMe me = widget.me;
    final bool mine = me.member?.id == r.memberId;
    final String? picked = await groupActions(context, title: '${r.memberName ?? ''} · ${r.typeName ?? ''}', actions: <GroupSheetAction>[
      if (!mine && r.state == 'submitted' && me.can('approve_benefits')) ...<GroupSheetAction>[
        GroupSheetAction(icon: Icons.verified_rounded, label: sw ? 'Idhinisha' : 'Approve', value: 'approve', tone: GroupTone.positive),
        GroupSheetAction(icon: Icons.block_rounded, label: sw ? 'Kataa' : 'Turn down', value: 'reject', tone: GroupTone.danger),
      ],
      if (!mine && r.state == 'approved' && me.can('record_payouts')) GroupSheetAction(icon: Icons.payments_rounded, label: sw ? 'Lipa' : 'Pay', value: 'pay', tone: GroupTone.positive),
    ]);
    if (picked == null || !mounted) return;
    try {
      switch (picked) {
        case 'approve':
          final double usual = _types.where((final GroupBenefitType t) => t.id == r.typeId).firstOrNull?.amount ?? r.amountRequested ?? 0;
          final (double, String)? got = await showDialog<(double, String)>(
            context: context,
            builder: (_) => AmountNoteDialog(title: sw ? 'Kiasi cha msaada' : 'Amount of help', amount: usual > 0 ? usual : (r.amountRequested ?? 0), max: 1000000000),
          );
          if (got == null || !mounted) return;
          final bool ok = await groupConfirm(context, title: sw ? 'Idhinisha msaada?' : 'Approve the help?', message: '${r.memberName ?? ''} · ${r.beneficiary}: ${tsh(got.$1)}', yes: sw ? 'Idhinisha' : 'Approve', tone: GroupTone.positive);
          if (!ok) return;
          await widget.api.decideBenefit(r.id, approve: true, amount: got.$1);
          await _done(sw ? 'Msaada umeidhinishwa.' : 'Help approved.');
        case 'reject':
          final String? reason = await groupReason(context, title: sw ? 'Kataa msaada' : 'Turn the request down', message: '${r.memberName ?? ''} · ${r.typeName ?? ''}', yes: sw ? 'Kataa' : 'Turn down');
          if (reason == null) return;
          await widget.api.decideBenefit(r.id, approve: false, note: reason);
          await _done(sw ? 'Ombi limekataliwa.' : 'Request turned down.');
        case 'pay':
          final (String, String)? how = await showDialog<(String, String)>(context: context, builder: (_) => const PayOutDialog());
          if (how == null || !mounted) return;
          final bool ok = await groupConfirm(
            context,
            title: sw ? 'Lipa msaada?' : 'Pay the help?',
            message: '${r.memberName ?? ''}: ${tsh(r.amountApproved ?? 0)} · ${methodLabel(sw: sw, method: how.$1)}.\n'
                '${sw ? 'Utahesabiwa kulipwa baada ya mtu mwingine kuthibitisha.' : 'It counts as paid once someone else verifies it.'}',
            yes: sw ? 'Lipa' : 'Pay',
            tone: GroupTone.danger,
          );
          if (!ok) return;
          await widget.api.payBenefit(r.id, method: how.$1, reference: how.$2);
          await _done(sw ? 'Imerekodiwa; inasubiri uthibitisho.' : 'Recorded; waiting for verification.');
      }
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<(String?, String)> filters = <(String?, String)>[
      ('submitted', benefitStateLabel(sw: sw, state: 'submitted')),
      ('approved', benefitStateLabel(sw: sw, state: 'approved')),
      ('rejected', benefitStateLabel(sw: sw, state: 'rejected')),
      (null, sw ? 'Yote' : 'All'),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: <Widget>[
              for (final (String?, String) f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('grp_welfare_filter_${f.$1 ?? 'all'}'),
                    label: Text(f.$2),
                    selected: _status == f.$1,
                    onSelected: (_) {
                      setState(() => _status = f.$1);
                      _load();
                    },
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          if (_error != null) GroupEmpty(_error!),
          if (!_loading && _error == null && _rows.isEmpty) GroupEmpty(sw ? 'Hakuna ombi hapa.' : 'No requests here.'),
          if (_rows.isNotEmpty)
            GlowListCard(
              dividerKey: 'grp_welfare_div',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: <Widget>[for (final GroupBenefitRequest r in _rows) BenefitTile(r: r, sw: sw, showMember: true, onTap: () => _act(r))],
            ),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}

/// A welfare request in a list.
class BenefitTile extends StatelessWidget {
  const BenefitTile({required this.r, required this.sw, super.key, this.showMember = false, this.onTap});

  final GroupBenefitRequest r;
  final bool sw;
  final bool showMember;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_benefit_${r.id}'),
        onTap: onTap,
        title: Text('${showMember ? '${r.memberName ?? ''} · ' : ''}${r.typeName ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(
          <String>[
            '${r.beneficiary} (${benefitRelationshipLabel(sw: sw, relationship: r.relationship)})',
            dateLabel(r.eventDate),
            if (r.amountApproved != null) tsh(r.amountApproved!) else if (r.amountRequested != null) '${sw ? 'Ameomba' : 'Asked'} ${tsh(r.amountRequested!)}',
            if (r.description != null) r.description!,
            if (r.decisionNote != null) r.decisionNote!,
          ].join(' · '),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: GroupPill(benefitStateLabel(sw: sw, state: r.state), color: benefitStateColor(r.state)),
      );
}

/// The member's own welfare requests and the form to ask for help.
class MyWelfareScreen extends StatefulWidget {
  const MyWelfareScreen({required this.api, super.key});

  final GroupsApi api;

  @override
  State<MyWelfareScreen> createState() => _MyWelfareScreenState();
}

class _MyWelfareScreenState extends State<MyWelfareScreen> {
  List<GroupBenefitRequest> _rows = const <GroupBenefitRequest>[];
  List<GroupBenefitType> _types = const <GroupBenefitType>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final List<GroupBenefitRequest> rows = await widget.api.myBenefits();
      final List<GroupBenefitType> types = await widget.api.benefitTypes();
      if (mounted) {
        setState(() {
          _rows = rows;
          _types = types.where((final GroupBenefitType t) => t.active).toList();
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

  Future<void> _ask() async {
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: _AskForm(api: widget.api, types: _types)),
    );
    if (sent ?? false) await _load();
  }

  Future<void> _cancel(final GroupBenefitRequest r) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (r.state != 'submitted') return;
    final bool ok = await groupConfirm(context, title: sw ? 'Ondoa ombi?' : 'Withdraw the request?', message: '${r.typeName ?? ''} · ${r.beneficiary}', yes: sw ? 'Ondoa' : 'Withdraw', tone: GroupTone.danger);
    if (!ok) return;
    try {
      await widget.api.cancelBenefit(r.id);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Ombi limeondolewa.' : 'Request withdrawn.');
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Msaada (ustawi)' : 'Welfare', flat: true),
      floatingActionButton: _types.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('grp_welfare_ask'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _ask,
              icon: const Icon(Icons.volunteer_activism_rounded),
              label: Text(sw ? 'Omba msaada' : 'Ask for help'),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: <Widget>[
                    if (_error != null) GroupEmpty(_error!),
                    if (_types.isEmpty && _error == null) GroupEmpty(sw ? 'Kikundi bado hakijaweka aina za msaada.' : 'The group has not set up any kind of help yet.'),
                    if (_rows.isEmpty && _types.isNotEmpty) GroupEmpty(sw ? 'Bado hujaomba msaada.' : 'No requests yet.'),
                    if (_rows.isNotEmpty)
                      GlowListCard(
                        dividerKey: 'grp_mywelfare_div',
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        children: <Widget>[for (final GroupBenefitRequest r in _rows) BenefitTile(r: r, sw: sw, onTap: () => _cancel(r))],
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _AskForm extends StatefulWidget {
  const _AskForm({required this.api, required this.types});

  final GroupsApi api;
  final List<GroupBenefitType> types;

  @override
  State<_AskForm> createState() => _AskFormState();
}

class _AskFormState extends State<_AskForm> {
  final TextEditingController _beneficiary = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  late int _type = widget.types.first.id;
  String _relationship = 'self';
  DateTime _on = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _beneficiary.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (_beneficiary.text.trim().length < 2) {
      setState(() => _error = sw ? 'Andika jina la anayehusika.' : 'Write who it is for.');
      return;
    }
    final GroupBenefitType type = widget.types.firstWhere((final GroupBenefitType t) => t.id == _type);
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Tuma ombi la msaada?' : 'Send the request?',
      message: '${type.name} · ${_beneficiary.text.trim()} · ${dateLabel(_iso(_on))}',
      yes: sw ? 'Tuma' : 'Send',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.applyBenefit(<String, dynamic>{
        'type_id': _type,
        'beneficiary': _beneficiary.text.trim(),
        'relationship': _relationship,
        'event_date': _iso(_on),
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
        if (double.tryParse(_amount.text.trim()) != null) 'amount': double.parse(_amount.text.trim()),
      });
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Ombi limetumwa.' : 'Request sent.');
      Navigator.pop(context, true);
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(sw ? 'Omba msaada' : 'Ask for help', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(color: Colors.white12, height: 24),
          DropdownButtonFormField<int>(
            key: const Key('grp_ask_type'),
            initialValue: _type,
            dropdownColor: ThemeConstants.bgMid,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Aina ya msaada' : 'Kind of help'),
            items: <DropdownMenuItem<int>>[for (final GroupBenefitType t in widget.types) DropdownMenuItem<int>(value: t.id, child: Text(t.name))],
            onChanged: (final int? v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 10),
          TextField(key: const Key('grp_ask_beneficiary'), controller: _beneficiary, maxLength: 150, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Anayehusika (jina)' : 'Who it is for (name)')),
          DropdownButtonFormField<String>(
            initialValue: _relationship,
            dropdownColor: ThemeConstants.bgMid,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Uhusiano' : 'Relationship'),
            items: <DropdownMenuItem<String>>[for (final String r in benefitRelationships) DropdownMenuItem<String>(value: r, child: Text(benefitRelationshipLabel(sw: sw, relationship: r)))],
            onChanged: (final String? v) => setState(() => _relationship = v ?? 'self'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined, color: Colors.white54),
            title: Text(sw ? 'Tarehe ya tukio' : 'Date of the event', style: const TextStyle(color: Colors.white70)),
            trailing: Text(dateLabel(_iso(_on)), style: const TextStyle(color: Colors.white)),
            onTap: () async {
              final DateTime now = DateTime.now();
              final DateTime? d = await showDatePicker(context: context, initialDate: _on, firstDate: DateTime(now.year - 1), lastDate: now.add(const Duration(days: 60)));
              if (d != null) setState(() => _on = d);
            },
          ),
          TextField(
            controller: _description,
            maxLines: 3,
            minLines: 1,
            maxLength: 2000,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Maelezo (wanaoamua tu ndio wanaona)' : 'Details (only those who decide see them)'),
          ),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Kiasi unachoomba (hiari)' : 'Amount asked (optional)'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('grp_ask_error'), style: const TextStyle(color: ThemeConstants.errorText))),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('grp_ask_send'),
            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(sw ? 'Tuma ombi' : 'Send the request'),
          ),
        ]),
      ),
    );
  }
}

/// The kinds of welfare help the group gives, and their usual amount.
class BenefitTypesScreen extends StatefulWidget {
  const BenefitTypesScreen({required this.api, super.key});

  final GroupsApi api;

  @override
  State<BenefitTypesScreen> createState() => _BenefitTypesScreenState();
}

class _BenefitTypesScreenState extends State<BenefitTypesScreen> {
  List<GroupBenefitType> _types = const <GroupBenefitType>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final List<GroupBenefitType> t = await widget.api.benefitTypes();
      if (mounted) {
        setState(() {
          _types = t;
          _loading = false;
        });
      }
    } on Exception {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([final GroupBenefitType? t]) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final Map<String, dynamic>? body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _TypeDialog(type: t));
    if (body == null || !mounted) return;
    try {
      await widget.api.saveBenefitType(body, id: t?.id);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imehifadhiwa.' : 'Saved.');
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Aina za msaada' : 'Kinds of help', flat: true),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('grp_btype_add'),
        backgroundColor: ThemeConstants.primaryOrange,
        foregroundColor: Colors.white,
        onPressed: _edit,
        icon: const Icon(Icons.add_rounded),
        label: Text(sw ? 'Ongeza' : 'Add'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
                if (_types.isEmpty) GroupEmpty(sw ? 'Bado hakuna. Mfano: Msiba, Ugonjwa, Sherehe.' : 'None yet. For example: Bereavement, Illness, Celebration.'),
                if (_types.isNotEmpty)
                  GlowListCard(
                    dividerKey: 'grp_btype_div',
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    children: <Widget>[
                      for (final GroupBenefitType t in _types)
                        ListTile(
                          key: Key('grp_btype_${t.id}'),
                          onTap: () => _edit(t),
                          title: Text(t.name, style: TextStyle(color: t.active ? Colors.white : Colors.white54, fontWeight: FontWeight.w700)),
                          subtitle: t.description == null ? null : Text(t.description!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                          trailing: Text(t.amount == null ? (sw ? 'Kwa uamuzi' : 'Case by case') : tsh(t.amount!), style: const TextStyle(color: Colors.white)),
                        ),
                    ],
                  ),
              ]),
      ),
    );
  }
}

class _TypeDialog extends StatefulWidget {
  const _TypeDialog({this.type});

  final GroupBenefitType? type;

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.type?.name);
  late final TextEditingController _amount = TextEditingController(text: widget.type?.amount?.toStringAsFixed(0) ?? '');
  late bool _active = widget.type?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool ready = _name.text.trim().length >= 2;
    return AlertDialog(
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.type == null ? (sw ? 'Aina mpya ya msaada' : 'New kind of help') : widget.type!.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        TextField(key: const Key('grp_btype_name'), controller: _name, onChanged: (_) => setState(() {}), style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Jina (mfano: Msiba)' : 'Name (e.g. Bereavement)')),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: const TextStyle(color: Colors.white),
          decoration: ThemeConstants.darkField(sw ? 'Kiasi cha kawaida (hiari)' : 'Usual amount (optional)'),
        ),
        if (widget.type != null)
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (final bool v) => setState(() => _active = v), title: Text(sw ? 'Inatumika' : 'In use', style: const TextStyle(color: Colors.white))),
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_btype_save'),
          onPressed: ready
              ? () => Navigator.pop(context, <String, dynamic>{'name': _name.text.trim(), 'amount': double.tryParse(_amount.text.trim()), 'active': _active})
              : null,
          child: Text(sw ? 'Hifadhi' : 'Save', style: TextStyle(color: ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
