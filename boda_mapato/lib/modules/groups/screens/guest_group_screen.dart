import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/place_picker.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_records_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

/// For someone who is NOT signed in and holds a group's invitation code: see which group it is (and who invited them), apply to join, or ask
/// to hire what the group hires out. Nothing else of the group is shown.
class GuestGroupScreen extends StatefulWidget {
  const GuestGroupScreen({super.key, this.api, this.code, this.placeSource});

  final GroupsApi? api;

  /// Where the region and district lists come from (the server's imported Tanzania locations unless a test says otherwise).
  final PlaceSource? placeSource;

  /// A code already known (from a shared message).
  final String? code;

  @override
  State<GuestGroupScreen> createState() => _GuestGroupScreenState();
}

class _GuestGroupScreenState extends State<GuestGroupScreen> {
  late final GroupsApi _api = widget.api ?? GroupsApi();
  late final TextEditingController _code = TextEditingController(text: widget.code);
  GroupPublicInfo? _info;
  String _mode = 'join';
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (_code.text.trim().length < 6) {
      setState(() => _error = sw ? 'Weka namba ya mwaliko uliyopewa.' : 'Enter the invitation code you were given.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GroupPublicInfo info = await _api.publicGroup(_code.text);
      if (mounted) {
        setState(() {
          _info = info;
          _busy = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = readableErrorMessage(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupPublicInfo? info = _info;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Jiunga na kikundi' : 'Join a group', flat: true),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: joinGlowCards(<Widget>[
          if (_done != null)
            GlowCard(children: <Widget>[
              const Center(child: Icon(Icons.check_circle_rounded, color: ThemeConstants.successGreen, size: 56)),
              Text(_done!, key: const Key('grp_guest_done'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ])
          else if (info == null)
            GlowCard(children: <Widget>[
              TextField(
                key: const Key('grp_guest_code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), LengthLimitingTextInputFormatter(12)],
                style: const TextStyle(color: Colors.white, letterSpacing: 3, fontWeight: FontWeight.w800),
                decoration: ThemeConstants.darkField(sw ? 'Namba ya mwaliko' : 'Invitation code'),
              ),
              if (_error != null) Text(_error!, key: const Key('grp_guest_error'), style: const TextStyle(color: ThemeConstants.errorText)),
              FilledButton(
                key: const Key('grp_guest_find'),
                style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                onPressed: _busy ? null : _find,
                child: Text(sw ? 'Endelea' : 'Continue'),
              ),
            ])
          else ...<Widget>[
            GlowCard(children: <Widget>[
              Text(info.group, key: const Key('grp_guest_group'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              if (info.invitedBy != null)
                Text('${sw ? 'Umealikwa na' : 'Invited by'} ${info.invitedBy}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ]),
            if (info.assets.isNotEmpty)
              SegmentedButton<String>(
                key: const Key('grp_guest_mode'),
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'join', label: Text(sw ? 'Kujiunga' : 'To join')),
                  ButtonSegment<String>(value: 'hire', label: Text(sw ? 'Kukodi' : 'To hire')),
                ],
                selected: <String>{_mode},
                onSelectionChanged: (final Set<String> v) => setState(() => _mode = v.first),
              ),
            const SizedBox(height: 12),
            if (_mode == 'join')
              _JoinForm(api: _api, code: _code.text, placeSource: widget.placeSource, onDone: (final String ref) => setState(() => _done = sw
                  ? 'Ombi lako limepokelewa (namba $ref). Kikundi kitakuelekeza kulipa ada ya kujiunga; utaidhinishwa baada ya hapo.'
                  : 'Your application is in (number $ref). The group will tell you how to pay the joining fee; you are approved after that.'))
            else
              _HireForm(api: _api, code: _code.text, info: info, onDone: (final String ref, final double amount) => setState(() => _done = sw
                  ? 'Ombi lako la kukodi limepokelewa (namba $ref, ${tsh(amount)}). Mtunzaji atakupigia kuthibitisha na kukuelekeza kulipa.'
                  : 'Your hire request is in (number $ref, ${tsh(amount)}). The keeper will call you to confirm and tell you how to pay.')),
          ],
        ])),
      ),
    );
  }
}

class _JoinForm extends StatefulWidget {
  const _JoinForm({required this.api, required this.code, required this.onDone, this.placeSource});

  final PlaceSource? placeSource;
  final GroupsApi api;
  final String code;
  final ValueChanged<String> onDone;

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _nida = TextEditingController();
  final TextEditingController _region = TextEditingController();
  final TextEditingController _district = TextEditingController();
  String? _ward;
  String? _street;
  String? _gender;
  bool _consent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _phone, _nida, _region, _district]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (_name.text.trim().length < 3 || !RegExp(r'^(0\d{9}|\+\d{9,15})$').hasMatch(_phone.text.replaceAll(' ', ''))) {
      setState(() => _error = sw ? 'Weka jina kamili na namba sahihi ya simu.' : 'Give your full name and a valid phone number.');
      return;
    }
    if (!_consent) {
      setState(() => _error = sw ? 'Kubali taarifa zako zitumike na kikundi.' : 'Agree to the group using your details.');
      return;
    }
    final bool ok = await groupConfirm(context, title: sw ? 'Tuma ombi?' : 'Send the application?', message: '${_name.text.trim()} · ${_phone.text.trim()}', yes: sw ? 'Tuma' : 'Send', tone: GroupTone.positive);
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? t(final TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      final String ref = await widget.api.publicApply(widget.code, <String, dynamic>{
        'full_name': _name.text.trim(),
        'phone': _phone.text.replaceAll(' ', ''),
        if (t(_nida) != null) 'nida': t(_nida),
        if (_gender != null) 'gender': _gender,
        if (t(_region) != null) 'region': t(_region),
        if (t(_district) != null) 'district': t(_district),
        if (_ward != null) 'ward': _ward,
        if (_street != null) 'street': _street,
        'consent': true,
      });
      widget.onDone(ref);
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
    Widget f(final TextEditingController c, final String label, {final Key? key, final TextInputType? keyboard}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(key: key, controller: c, keyboardType: keyboard, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(label)),
        );
    return GlowCard(title: sw ? 'Ombi la kujiunga' : 'Application to join', children: <Widget>[
      f(_name, sw ? 'Jina kamili' : 'Full name', key: const Key('grp_guest_name')),
      f(_phone, sw ? 'Namba ya simu' : 'Phone number', key: const Key('grp_guest_phone'), keyboard: TextInputType.phone),
      f(_nida, sw ? 'NIDA (hiari)' : 'NIDA (optional)'),
      Wrap(spacing: 8, children: <Widget>[
        for (final String g in const <String>['male', 'female'])
          ChoiceChip(label: Text(g == 'male' ? (sw ? 'Mwanaume' : 'Male') : (sw ? 'Mwanamke' : 'Female')), selected: _gender == g, onSelected: (final bool on) => setState(() => _gender = on ? g : null)),
      ]),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: PlacePicker(
          key: const Key('grp_guest_place'),
          source: widget.placeSource,
          onChanged: (final PlaceChoice c) {
            _region.text = c.region ?? '';
            _district.text = c.district ?? '';
            _ward = c.ward;
            _street = c.street;
          },
        ),
      ),
      CheckboxListTile(
        key: const Key('grp_guest_consent'),
        contentPadding: EdgeInsets.zero,
        value: _consent,
        onChanged: (final bool? v) => setState(() => _consent = v ?? false),
        title: Text(
          sw ? 'Nakubali kikundi kihifadhi na kutumia taarifa hizi kwa uanachama wangu.' : 'I agree to the group keeping and using these details for my membership.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
      if (_error != null) Text(_error!, key: const Key('grp_guest_join_error'), style: const TextStyle(color: ThemeConstants.errorText)),
      FilledButton.icon(
        key: const Key('grp_guest_join_send'),
        style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: _busy ? null : _send,
        icon: const Icon(Icons.send_rounded),
        label: Text(sw ? 'Tuma ombi' : 'Send the application'),
      ),
    ]);
  }
}

class _HireForm extends StatefulWidget {
  const _HireForm({required this.api, required this.code, required this.info, required this.onDone});

  final GroupsApi api;
  final String code;
  final GroupPublicInfo info;
  final void Function(String ref, double amount) onDone;

  @override
  State<_HireForm> createState() => _HireFormState();
}

class _HireFormState extends State<_HireForm> {
  final TextEditingController _qty = TextEditingController(text: '1');
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  late int _asset = widget.info.assets.first.$1;
  DateTime _from = DateTime.now().add(const Duration(days: 1));
  late DateTime _to = _from;
  (int, int, double)? _check;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_qty, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _refresh() async {
    try {
      final (int, int, double) c = await widget.api.publicAvailability(widget.code, _asset, _iso(_from), _iso(_to));
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
    if (_name.text.trim().length < 2 || !RegExp(r'^(0\d{9}|\+\d{9,15})$').hasMatch(_phone.text.replaceAll(' ', ''))) {
      setState(() => _error = sw ? 'Weka jina lako na namba sahihi ya simu.' : 'Give your name and a valid phone number.');
      return;
    }
    final double cost = qty * (_check?.$3 ?? 0.0) * (_check?.$2 ?? 1);
    final bool ok = await groupConfirm(context, title: sw ? 'Tuma ombi la kukodi?' : 'Send the hire request?', message: '$qty · ${dateLabel(_iso(_from))} – ${dateLabel(_iso(_to))} · ${tsh(cost)}', yes: sw ? 'Tuma' : 'Send', tone: GroupTone.positive);
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (String, double) done = await widget.api.publicHire(widget.code, <String, dynamic>{
        'asset_id': _asset,
        'quantity': qty,
        'start_date': _iso(_from),
        'end_date': _iso(_to),
        'name': _name.text.trim(),
        'phone': _phone.text.replaceAll(' ', ''),
      });
      widget.onDone(done.$1, done.$2);
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
    return GlowCard(title: sw ? 'Ombi la kukodi' : 'Hire request', children: <Widget>[
      DropdownButtonFormField<int>(
        initialValue: _asset,
        dropdownColor: ThemeConstants.bgMid,
        style: const TextStyle(color: Colors.white),
        decoration: ThemeConstants.darkField(sw ? 'Nini' : 'What'),
        items: <DropdownMenuItem<int>>[for (final (int, String, double, int) a in widget.info.assets) DropdownMenuItem<int>(value: a.$1, child: Text('${a.$2} · ${tsh(a.$3)}'))],
        onChanged: (final int? v) {
          setState(() => _asset = v ?? _asset);
          _refresh();
        },
      ),
      Row(children: <Widget>[
        Expanded(
          child: ListTile(
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
        key: const Key('grp_guest_qty'),
        controller: _qty,
        onChanged: (_) => setState(() {}),
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: Colors.white),
        decoration: ThemeConstants.darkField(sw ? 'Ngapi' : 'How many', helper: _check == null ? null : '${sw ? 'Zipo wazi' : 'Free'}: ${_check!.$1}'),
      ),
      if (_check != null && qty > 0)
        Text('${sw ? 'Gharama' : 'Cost'}: ${tsh(qty * _check!.$3 * _check!.$2)}', key: const Key('grp_guest_cost'), style: const TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      TextField(key: const Key('grp_guest_hire_name'), controller: _name, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Jina lako' : 'Your name')),
      const SizedBox(height: 10),
      TextField(key: const Key('grp_guest_hire_phone'), controller: _phone, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Simu yako' : 'Your phone')),
      if (_error != null) Text(_error!, style: const TextStyle(color: ThemeConstants.errorText)),
      FilledButton.icon(
        key: const Key('grp_guest_hire_send'),
        style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: _busy ? null : _send,
        icon: const Icon(Icons.send_rounded),
        label: Text(sw ? 'Tuma ombi' : 'Send the request'),
      ),
    ]);
  }
}
