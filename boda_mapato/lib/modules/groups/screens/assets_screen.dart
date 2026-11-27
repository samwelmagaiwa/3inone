import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../widgets/scrolling_chip_row.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_asset_models.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'hire_detail_screen.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_picker.dart';

/// Assets, for whoever keeps one or manages the register: the hires by stage, and the register itself.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  bool _register = false;
  String? _status = 'open';
  List<GroupHire> _hires = const <GroupHire>[];
  List<GroupAsset> _assets = const <GroupAsset>[];
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
      final (List<GroupAsset>, bool) a = await widget.api.assets();
      final List<GroupHire> h = await widget.api.hires(status: _status);
      if (mounted) {
        setState(() {
          _assets = a.$1;
          _hires = h;
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

  Future<void> _openHire(final GroupHire h) async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => HireDetailScreen(api: widget.api, me: widget.me, hire: h)));
    await _load();
    await widget.onChanged();
  }

  Future<void> _openAsset(final GroupAsset a) async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => AssetDetailScreen(api: widget.api, me: widget.me, assetId: a.id)));
    await _load();
  }

  Future<void> _addAsset() async {
    if (await showAssetForm(context, api: widget.api)) await _load();
  }

  /// Write down a hire for a member or for someone outside the group.
  Future<void> _writeHire() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final List<GroupAsset> forHire = _assets.where((final GroupAsset a) => a.forHire).toList();
    if (forHire.isEmpty) {
      ThemeConstants.showInfoSnackBar(context, sw ? 'Hakuna mali inayokodishwa.' : 'Nothing is for hire.');
      return;
    }
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: HireForm(api: widget.api, assets: forHire, forSomeone: true)),
    );
    if (sent ?? false) await _load();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool manager = widget.me.can('manage_assets');
    final List<(String?, String)> filters = <(String?, String)>[
      ('open', sw ? 'Zinaendelea' : 'In progress'),
      ('requested', hireStateLabel(sw: sw, state: 'requested')),
      ('issued', hireStateLabel(sw: sw, state: 'out')),
      ('returned', sw ? 'Zimerudi' : 'Back'),
      ('closed', hireStateLabel(sw: sw, state: 'closed')),
      (null, sw ? 'Zote' : 'All'),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _register
          ? (manager
              ? FloatingActionButton.extended(
                  key: const Key('grp_asset_add'),
                  backgroundColor: ThemeConstants.primaryOrange,
                  foregroundColor: Colors.white,
                  onPressed: _addAsset,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(sw ? 'Ongeza mali' : 'Add an asset'),
                )
              : null)
          : FloatingActionButton.extended(
              key: const Key('grp_hire_write'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _writeHire,
              icon: const Icon(Icons.edit_calendar_rounded),
              label: Text(sw ? 'Andika ukodishaji' : 'Write down a hire'),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: joinGlowCards(<Widget>[
            SegmentedButton<bool>(
              key: const Key('grp_assets_tabs'),
              segments: <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text(sw ? 'Ukodishaji' : 'Hires'), icon: const Icon(Icons.event_available_rounded)),
                ButtonSegment<bool>(value: true, label: Text(sw ? 'Daftari la mali' : 'Register'), icon: const Icon(Icons.inventory_2_rounded)),
              ],
              selected: <bool>{_register},
              onSelectionChanged: (final Set<bool> v) => setState(() => _register = v.first),
            ),
            const SizedBox(height: 10),
            if (!_register)
              ScrollingChipRow(padding: EdgeInsets.zero, children: <Widget>[
                for (final (String?, String) f in filters)
                  ScrollChoiceChip(
                    chipKey: Key('grp_hire_filter_${f.$1 ?? 'all'}'),
                    label: f.$2,
                    selected: _status == f.$1,
                    onSelected: (_) {
                      setState(() => _status = f.$1);
                      _load();
                    },
                  ),
              ]),
            const SizedBox(height: 10),
            if (_error != null) GroupEmpty(_error!),
            if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (!_loading && !_register && _hires.isEmpty && _error == null) GroupEmpty(sw ? 'Hakuna ukodishaji hapa.' : 'No hires here.'),
            if (!_loading && !_register && _hires.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_hires_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[for (final GroupHire h in _hires) HireTile(h: h, sw: sw, onTap: () => _openHire(h))],
              ),
            if (!_loading && _register && _assets.isEmpty && _error == null) GroupEmpty(sw ? 'Bado hakuna mali.' : 'No assets yet.'),
            if (!_loading && _register && _assets.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_assets_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[for (final GroupAsset a in _assets) AssetTile(a: a, sw: sw, onTap: () => _openAsset(a))],
              ),
          ]),
        ),
      ),
    );
  }
}

/// An asset in a list: how many, how many free today, its hire rate.
class AssetTile extends StatelessWidget {
  const AssetTile({required this.a, required this.sw, super.key, this.onTap});

  final GroupAsset a;
  final bool sw;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_asset_${a.id}'),
        onTap: onTap,
        leading: Icon(Icons.chair_alt_rounded, color: a.status == 'active' ? ThemeConstants.invAccent : Colors.white38),
        title: Text('${a.name} (${a.code})', style: TextStyle(color: a.status == 'active' ? Colors.white : Colors.white54, fontWeight: FontWeight.w700)),
        subtitle: Text(
          <String>[
            '${sw ? 'Zipo' : 'Count'} ${a.quantity}',
            '${sw ? 'Wazi leo' : 'Free today'} ${a.freeToday}',
            if (a.custodianName != null) '${sw ? 'Mtunzaji' : 'Keeper'} ${a.custodianName}',
          ].join(' · '),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: a.hireRate == null ? null : Text('${tsh(a.hireRate!)}/${sw ? 'siku' : 'day'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      );
}

/// One asset: its details, its history, and recording a change (maintenance, damage, loss, repair, a recount, retiring it).
class AssetDetailScreen extends StatefulWidget {
  const AssetDetailScreen({required this.api, required this.me, required this.assetId, super.key});

  final GroupsApi api;
  final GroupMe me;
  final int assetId;

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  GroupAsset? _a;
  List<GroupAssetEvent> _events = const <GroupAssetEvent>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (GroupAsset, List<GroupAssetEvent>, bool) got = await widget.api.asset(widget.assetId);
      if (mounted) {
        setState(() {
          _a = got.$1;
          _events = got.$2;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  Future<void> _change(final GroupAsset a) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? kind = await groupActions(context, title: a.name, actions: <GroupSheetAction>[
      GroupSheetAction(icon: Icons.edit_outlined, label: sw ? 'Badili taarifa' : 'Edit details', value: 'edit'),
      GroupSheetAction(icon: Icons.build_outlined, label: assetEventLabel(sw: sw, kind: 'maintenance'), value: 'maintenance'),
      GroupSheetAction(icon: Icons.handyman_outlined, label: assetEventLabel(sw: sw, kind: 'repair'), value: 'repair', tone: GroupTone.positive),
      GroupSheetAction(icon: Icons.broken_image_outlined, label: assetEventLabel(sw: sw, kind: 'damage'), value: 'damage', tone: GroupTone.danger),
      GroupSheetAction(icon: Icons.report_gmailerrorred_outlined, label: assetEventLabel(sw: sw, kind: 'loss'), value: 'loss', tone: GroupTone.danger),
      GroupSheetAction(icon: Icons.exposure_outlined, label: assetEventLabel(sw: sw, kind: 'adjust'), value: 'adjust'),
      if (a.status == 'active') GroupSheetAction(icon: Icons.archive_outlined, label: assetEventLabel(sw: sw, kind: 'retire'), value: 'retire', tone: GroupTone.danger),
    ]);
    if (kind == null || !mounted) return;
    if (kind == 'edit') {
      if (await showAssetForm(context, api: widget.api, asset: a)) await _load();
      return;
    }
    final Map<String, dynamic>? body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _EventDialog(kind: kind));
    if (body == null || !mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: '${assetEventLabel(sw: sw, kind: kind)}?',
      message: '${a.name}${body['quantity'] == null ? '' : ' · ${body['quantity']}'} · ${body['note']}',
      yes: sw ? 'Rekodi' : 'Record',
      tone: <String>['damage', 'loss', 'retire'].contains(kind) ? GroupTone.danger : GroupTone.positive,
    );
    if (!ok) return;
    try {
      await widget.api.assetEvent(a.id, <String, dynamic>{'kind': kind, ...body});
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imerekodiwa.' : 'Recorded.');
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupAsset? a = _a;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        a?.name ?? (sw ? 'Mali' : 'Asset'),
        flat: true,
        actions: <Widget>[
          if (a != null && widget.me.can('manage_assets')) IconButton(key: const Key('grp_asset_actions'), icon: const Icon(Icons.more_vert), onPressed: () => _change(a)),
        ],
      ),
      body: SafeArea(
        child: a == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : GroupEmpty(_error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: joinGlowCards(<Widget>[
                  GlowCard(children: <Widget>[
                    GroupDetailRow(sw ? 'Namba' : 'Code', a.code),
                    if (a.category != null) GroupDetailRow(sw ? 'Aina' : 'Category', a.category!),
                    GroupDetailRow(sw ? 'Zipo (zinazotumika)' : 'Usable count', '${a.quantity}'),
                    GroupDetailRow(sw ? 'Wazi leo' : 'Free today', '${a.freeToday}'),
                    GroupDetailRow(sw ? 'Hali' : 'Condition', conditionLabel(sw: sw, condition: a.condition)),
                    GroupDetailRow(sw ? 'Mtunzaji' : 'Keeper', a.custodianName ?? '-'),
                    GroupDetailRow(sw ? 'Kukodi' : 'Hire', a.hireRate == null ? (sw ? 'Haikodishwi' : 'Not for hire') : '${tsh(a.hireRate!)} / ${sw ? 'kimoja kwa siku' : 'each a day'}'),
                    GroupDetailRow(sw ? 'Kuchelewa' : 'Late', a.lateRate == null ? (sw ? 'Haijawekwa' : 'Not set') : '${tsh(a.lateRate!)} / ${sw ? 'kimoja kwa siku' : 'each a day'}'),
                    if (a.cost != null) GroupDetailRow(sw ? 'Thamani' : 'Value', tsh(a.cost!)),
                    if (a.location != null) GroupDetailRow(sw ? 'Mahali' : 'Kept at', a.location!),
                  ]),
                  if (_events.isNotEmpty)
                    GlowCard(title: sw ? 'Historia' : 'History', children: <Widget>[
                      for (final GroupAssetEvent e in _events)
                        Text(
                          '${dateLabel(e.at)} · ${assetEventLabel(sw: sw, kind: e.kind)}${e.quantity == null ? '' : ' (${e.quantity! > 0 ? '+' : ''}${e.quantity})'}'
                          '${e.cost == null ? '' : ' · ${tsh(e.cost!)}'}${e.note == null ? '' : ' · ${e.note}'}${e.byName == null ? '' : ' · ${e.byName}'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                    ]),
                ])),
              ),
      ),
    );
  }
}

/// The details of a change: how many (when the count moves), its cost (maintenance), and why.
class _EventDialog extends StatefulWidget {
  const _EventDialog({required this.kind});

  final String kind;

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _cost = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _direction = 'up';

  bool get _counts => const <String>['damage', 'loss', 'repair', 'adjust'].contains(widget.kind);

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _ready => _note.text.trim().length >= 3 && (!_counts || (int.tryParse(_qty.text.trim()) ?? 0) >= 1);

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      key: const Key('grp_event_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(assetEventLabel(sw: sw, kind: widget.kind), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          // As wide as the screen allows, not as narrow as the fields' hints.
          const SizedBox(width: double.maxFinite),
          if (widget.kind == 'adjust')
            Wrap(spacing: 8, children: <Widget>[
              ChoiceChip(label: Text(sw ? 'Ongeza' : 'Up'), selected: _direction == 'up', onSelected: (_) => setState(() => _direction = 'up')),
              ChoiceChip(label: Text(sw ? 'Punguza' : 'Down'), selected: _direction == 'down', onSelected: (_) => setState(() => _direction = 'down')),
            ]),
          if (_counts)
            TextField(
              key: const Key('grp_event_qty'),
              controller: _qty,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Idadi' : 'How many'),
            ),
          if (widget.kind == 'maintenance')
            TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Gharama (hiari)' : 'Cost (optional)'),
            ),
          const SizedBox(height: 10),
          TextField(key: const Key('grp_event_note'), controller: _note, onChanged: (_) => setState(() {}), maxLength: 255, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Sababu' : 'Why')),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_event_next'),
          onPressed: _ready
              ? () => Navigator.pop(context, <String, dynamic>{
                    if (_counts) 'quantity': int.parse(_qty.text.trim()),
                    if (widget.kind == 'adjust') 'direction': _direction,
                    if (double.tryParse(_cost.text.trim()) != null) 'cost': double.parse(_cost.text.trim()),
                    'note': _note.text.trim(),
                  })
              : null,
          child: Text(sw ? 'Endelea' : 'Next', style: TextStyle(color: _ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// Add an asset or change its details (the count changes only through events once it exists). Returns true when saved.
Future<bool> showAssetForm(final BuildContext context, {required final GroupsApi api, final GroupAsset? asset}) async {
  final bool? saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.bgMid,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: _AssetForm(api: api, asset: asset)),
  );
  return saved ?? false;
}

class _AssetForm extends StatefulWidget {
  const _AssetForm({required this.api, this.asset});

  final GroupsApi api;
  final GroupAsset? asset;

  @override
  State<_AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends State<_AssetForm> {
  late final TextEditingController _code = TextEditingController(text: widget.asset?.code);
  late final TextEditingController _name = TextEditingController(text: widget.asset?.name);
  late final TextEditingController _category = TextEditingController(text: widget.asset?.category);
  late final TextEditingController _qty = TextEditingController(text: widget.asset == null ? '' : '${widget.asset!.quantity}');
  late final TextEditingController _cost = TextEditingController(text: widget.asset?.cost?.toStringAsFixed(0));
  late final TextEditingController _location = TextEditingController(text: widget.asset?.location);
  late final TextEditingController _rate = TextEditingController(text: widget.asset?.hireRate?.toStringAsFixed(0));
  late final TextEditingController _late = TextEditingController(text: widget.asset?.lateRate?.toStringAsFixed(0));
  late int? _custodianId = widget.asset?.custodianId;
  late String? _custodianName = widget.asset?.custodianName;
  late bool _visible = widget.asset?.visible ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_code, _name, _category, _qty, _cost, _location, _rate, _late]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickKeeper() async {
    final GroupMember? m = await pickGroupMember(context, api: widget.api);
    if (m != null) {
      setState(() {
        _custodianId = m.id;
        _custodianName = m.fullName;
      });
    }
  }

  Widget _f(final TextEditingController c, final String label, {final Key? key, final bool number = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          inputFormatters: number ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
          style: const TextStyle(color: Colors.white),
          decoration: ThemeConstants.darkField(label),
        ),
      );

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (_code.text.trim().isEmpty || _name.text.trim().length < 2 || (widget.asset == null && (int.tryParse(_qty.text.trim()) ?? 0) < 1)) {
      setState(() => _error = sw ? 'Weka namba, jina na idadi.' : 'Give the code, the name and the count.');
      return;
    }
    final bool ok = await groupConfirm(context, title: sw ? 'Hifadhi mali?' : 'Save the asset?', message: '${_code.text.trim()} · ${_name.text.trim()}', yes: sw ? 'Hifadhi' : 'Save', tone: GroupTone.positive);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.saveAsset(<String, dynamic>{
        'code': _code.text.trim(),
        'name': _name.text.trim(),
        if (_category.text.trim().isNotEmpty) 'category': _category.text.trim(),
        if (widget.asset == null) 'quantity': int.parse(_qty.text.trim()),
        if (double.tryParse(_cost.text.trim()) != null) 'cost': double.parse(_cost.text.trim()),
        if (_location.text.trim().isNotEmpty) 'location': _location.text.trim(),
        'custodian_id': _custodianId,
        'visible': _visible,
        'hire_rate': double.tryParse(_rate.text.trim()),
        'late_rate': double.tryParse(_late.text.trim()),
      }, id: widget.asset?.id);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imehifadhiwa.' : 'Saved.');
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
          Text(widget.asset == null ? (sw ? 'Mali mpya' : 'New asset') : widget.asset!.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(color: Colors.white12, height: 24),
          _f(_code, sw ? 'Namba ya mali (mfano VT-01)' : 'Asset code (e.g. VT-01)', key: const Key('grp_asset_code')),
          _f(_name, sw ? 'Jina' : 'Name', key: const Key('grp_asset_name')),
          _f(_category, sw ? 'Aina (hiari)' : 'Category (optional)'),
          if (widget.asset == null) _f(_qty, sw ? 'Idadi' : 'How many', key: const Key('grp_asset_qty'), number: true),
          _f(_cost, sw ? 'Thamani (hiari)' : 'Value (optional)', number: true),
          _f(_location, sw ? 'Mahali inapotunzwa (siri)' : 'Where it is kept (private)'),
          _f(_rate, sw ? 'Bei ya kukodi: kimoja kwa siku (acha wazi kama haikodishwi)' : 'Hire rate: each a day (empty if not for hire)', key: const Key('grp_asset_rate'), number: true),
          _f(_late, sw ? 'Gharama ya kuchelewa: kimoja kwa usiku (hiari; tupu = bei ya kukodi)' : 'Late rate: each a night (optional; empty = the hire rate)', number: true),
          ListTile(
            key: const Key('grp_asset_keeper'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_pin_rounded, color: Colors.white54),
            title: Text(_custodianName ?? (sw ? 'Chagua mtunzaji' : 'Choose the keeper'), style: const TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: _pickKeeper,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _visible,
            onChanged: (final bool v) => setState(() => _visible = v),
            title: Text(sw ? 'Wanachama wanaiona' : 'Members see it', style: const TextStyle(color: Colors.white)),
          ),
          if (_error != null) Text(_error!, key: const Key('grp_asset_error'), style: const TextStyle(color: ThemeConstants.errorText)),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('grp_asset_save'),
            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(sw ? 'Hifadhi' : 'Save'),
          ),
        ]),
      ),
    );
  }
}

/// Ask to hire (a member for themself), or -- [forSomeone] -- write down a hire for a member or someone outside the group. Shows how many
/// are free on the chosen days and what it will cost before anything is sent.
class HireForm extends StatefulWidget {
  const HireForm({required this.api, required this.assets, super.key, this.forSomeone = false, this.asset});

  final GroupsApi api;
  final List<GroupAsset> assets;
  final bool forSomeone;
  final GroupAsset? asset;

  @override
  State<HireForm> createState() => _HireFormState();
}

class _HireFormState extends State<HireForm> {
  final TextEditingController _qty = TextEditingController(text: '1');
  final TextEditingController _purpose = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  late GroupAsset _asset = widget.asset ?? widget.assets.first;
  late DateTime _from = DateTime.now().add(const Duration(days: 1));
  late DateTime _to = _from;
  GroupMember? _member;
  (int, int, double?)? _check;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_qty, _purpose, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _refresh() async {
    try {
      final (int, int, double?) c = await widget.api.availability(_asset.id, _iso(_from), _iso(_to));
      if (mounted) setState(() => _check = c);
    } on Exception {
      if (mounted) setState(() => _check = null);
    }
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final int qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (qty < 1 || (_check != null && qty > _check!.$1)) {
      setState(() => _error = sw ? 'Zipo ${_check?.$1 ?? 0} tu kwa siku hizo.' : 'Only ${_check?.$1 ?? 0} are free on those days.');
      return;
    }
    if (widget.forSomeone && _member == null && (_name.text.trim().length < 2 || _phone.text.trim().length < 10)) {
      setState(() => _error = sw ? 'Chagua mwanachama, au andika jina na simu ya anayekodi.' : 'Choose a member, or write the hirer’s name and phone.');
      return;
    }
    final double cost = qty * (_check?.$3 ?? _asset.hireRate ?? 0.0) * (_check?.$2 ?? 1);
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Tuma ombi la kukodi?' : 'Send the hire request?',
      message: '$qty × ${_asset.name} · ${dateLabel(_iso(_from))} – ${dateLabel(_iso(_to))} · ${tsh(cost)}.\n'
          '${sw ? 'Mtunzaji atathibitisha kwamba vipo.' : 'The keeper confirms they are there.'}',
      yes: sw ? 'Tuma' : 'Send',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Map<String, dynamic> body = <String, dynamic>{
      'asset_id': _asset.id,
      'quantity': qty,
      'start_date': _iso(_from),
      'end_date': _iso(_to),
      if (_purpose.text.trim().isNotEmpty) 'purpose': _purpose.text.trim(),
      if (widget.forSomeone && _member != null) 'member_id': _member!.id,
      if (widget.forSomeone && _member == null) ...<String, dynamic>{'customer_name': _name.text.trim(), 'customer_phone': _phone.text.replaceAll(' ', '')},
    };
    try {
      if (widget.forSomeone) {
        await widget.api.askHireFor(body);
      } else {
        await widget.api.askHire(body);
      }
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
    final int qty = int.tryParse(_qty.text.trim()) ?? 0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(widget.forSomeone ? (sw ? 'Andika ukodishaji' : 'Write down a hire') : (sw ? 'Omba kukodi' : 'Ask to hire'),
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(color: Colors.white12, height: 24),
          DropdownButtonFormField<int>(
            key: const Key('grp_hireform_asset'),
            initialValue: _asset.id,
            dropdownColor: ThemeConstants.bgMid,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Nini' : 'What'),
            items: <DropdownMenuItem<int>>[for (final GroupAsset a in widget.assets) DropdownMenuItem<int>(value: a.id, child: Text('${a.name} · ${tsh(a.hireRate ?? 0)}'))],
            onChanged: (final int? id) {
              setState(() => _asset = widget.assets.firstWhere((final GroupAsset a) => a.id == id));
              _refresh();
            },
          ),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Expanded(
              child: ListTile(
                key: const Key('grp_hireform_from'),
                contentPadding: EdgeInsets.zero,
                title: Text(sw ? 'Kuanzia' : 'From', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                subtitle: Text(dateLabel(_iso(_from)), style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  final DateTime now = DateTime.now();
                  final DateTime? d = await showDatePicker(context: context, initialDate: _from, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)));
                  if (d != null) {
                    setState(() {
                      _from = d;
                      if (_to.isBefore(d)) _to = d;
                    });
                    await _refresh();
                  }
                },
              ),
            ),
            Expanded(
              child: ListTile(
                key: const Key('grp_hireform_to'),
                contentPadding: EdgeInsets.zero,
                title: Text(sw ? 'Hadi' : 'To', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                subtitle: Text(dateLabel(_iso(_to)), style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  final DateTime? d = await showDatePicker(context: context, initialDate: _to, firstDate: _from, lastDate: _from.add(const Duration(days: 365)));
                  if (d != null) {
                    setState(() => _to = d);
                    await _refresh();
                  }
                },
              ),
            ),
          ]),
          TextField(
            key: const Key('grp_hireform_qty'),
            controller: _qty,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Ngapi' : 'How many', helper: _check == null ? null : '${sw ? 'Zipo wazi' : 'Free'}: ${_check!.$1} · ${_check!.$2} ${sw ? 'siku' : 'day(s)'}'),
          ),
          if (_check != null && qty > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('${sw ? 'Gharama' : 'Cost'}: $qty × ${tsh(_check!.$3 ?? 0)} × ${_check!.$2} = ${tsh(qty * (_check!.$3 ?? 0) * _check!.$2)}',
                  key: const Key('grp_hireform_cost'), style: const TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w700)),
            ),
          TextField(controller: _purpose, maxLength: 255, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Kwa ajili ya (hiari)' : 'For (optional)')),
          if (widget.forSomeone) ...<Widget>[
            ListTile(
              key: const Key('grp_hireform_member'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_search_rounded, color: Colors.white54),
              title: Text(_member?.fullName ?? (sw ? 'Mwanachama (au acha, kwa asiye mwanachama)' : 'A member (or leave it, for someone outside)'), style: const TextStyle(color: Colors.white)),
              onTap: () async {
                final GroupMember? m = await pickGroupMember(context, api: widget.api);
                if (m != null) setState(() => _member = m);
              },
            ),
            if (_member == null) ...<Widget>[
              TextField(key: const Key('grp_hireform_name'), controller: _name, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Jina la anayekodi' : "Hirer's name")),
              const SizedBox(height: 10),
              TextField(key: const Key('grp_hireform_phone'), controller: _phone, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Simu ya anayekodi' : "Hirer's phone")),
            ],
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('grp_hireform_error'), style: const TextStyle(color: ThemeConstants.errorText))),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('grp_hireform_send'),
            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(sw ? 'Tuma' : 'Send'),
          ),
        ]),
      ),
    );
  }
}

/// The member's side: what can be hired, asking, and their own hires.
class MyHiresScreen extends StatefulWidget {
  const MyHiresScreen({required this.api, required this.me, super.key});

  final GroupsApi api;
  final GroupMe me;

  @override
  State<MyHiresScreen> createState() => _MyHiresScreenState();
}

class _MyHiresScreenState extends State<MyHiresScreen> {
  List<GroupAsset> _assets = const <GroupAsset>[];
  List<GroupHire> _mine = const <GroupHire>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (List<GroupAsset>, bool) a = await widget.api.assets();
      final List<GroupHire> mine = await widget.api.myHires();
      if (mounted) {
        setState(() {
          _assets = a.$1.where((final GroupAsset x) => x.forHire).toList();
          _mine = mine;
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

  Future<void> _ask(final GroupAsset a) async {
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: HireForm(api: widget.api, assets: _assets, asset: a)),
    );
    if (sent ?? false) await _load();
  }

  Future<void> _open(final GroupHire h) async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => HireDetailScreen(api: widget.api, me: widget.me, hire: h)));
    await _load();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Kukodi mali ya kikundi' : 'Hire from the group', flat: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: joinGlowCards(<Widget>[
                  if (_error != null) GroupEmpty(_error!),
                  if (_assets.isEmpty && _error == null) GroupEmpty(sw ? 'Hakuna kinachokodishwa kwa sasa.' : 'Nothing is for hire now.'),
                  if (_assets.isNotEmpty)
                    GlowListCard(
                      dividerKey: 'grp_forhire_div',
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: <Widget>[for (final GroupAsset a in _assets) AssetTile(a: a, sw: sw, onTap: () => _ask(a))],
                    ),
                  if (_mine.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    GlowListCard(
                      dividerKey: 'grp_myhires_div',
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: <Widget>[for (final GroupHire h in _mine) HireTile(h: h, sw: sw, onTap: () => _open(h))],
                    ),
                  ],
                ])),
              ),
      ),
    );
  }
}
