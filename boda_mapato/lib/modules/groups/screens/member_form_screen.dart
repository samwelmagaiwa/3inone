import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/place_picker.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_picker.dart';

/// Register a person or change their details. A new person is an APPLICATION (waits for payments and approval), unless whoever approves
/// members enters them as someone who was ALREADY a member before the group used the app. Returns the saved file.
class MemberFormScreen extends StatefulWidget {
  const MemberFormScreen({required this.api, required this.me, super.key, this.member, this.placeSource});

  /// Where the region, district, ward and street lists come from (the server's imported Tanzania locations unless a test says otherwise).
  final PlaceSource? placeSource;

  final GroupsApi api;
  final GroupMe me;

  /// Given when changing someone; null to register.
  final GroupMember? member;

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.member?.fullName);
  late final TextEditingController _phone = TextEditingController(text: widget.member?.phone);
  late final TextEditingController _altPhone = TextEditingController(text: widget.member?.altPhone);
  late final TextEditingController _email = TextEditingController(text: widget.member?.email);
  final TextEditingController _nida = TextEditingController();
  late final TextEditingController _region = TextEditingController(text: widget.member?.region);
  late final TextEditingController _district = TextEditingController(text: widget.member?.district);
  late final TextEditingController _ward = TextEditingController(text: widget.member?.ward);
  late final TextEditingController _street = TextEditingController(text: widget.member?.street);
  late final TextEditingController _occupation = TextEditingController(text: widget.member?.occupation);
  final TextEditingController _number = TextEditingController();
  late String? _gender = widget.member?.gender;
  late DateTime? _born = widget.member?.dateOfBirth == null ? null : DateTime.tryParse(widget.member!.dateOfBirth!);
  late int? _referrerId = widget.member?.referrerId;
  late String? _referrerName = widget.member?.referrerName;
  bool _existing = false;
  bool _founding = false;
  DateTime? _joined;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.member != null;

  static final RegExp _phoneRule = RegExp(r'^(0\d{9}|\+\d{9,15})$');

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _phone, _altPhone, _email, _nida, _region, _district, _ward, _street, _occupation, _number]) {
      c.dispose();
    }
    super.dispose();
  }

  String _day(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<DateTime?> _pickDate(final DateTime? initial, {required final DateTime first}) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: first,
        lastDate: DateTime.now(),
      );

  Future<void> _pickReferrer() async {
    final GroupMember? picked = await pickGroupMember(context, api: widget.api, exceptId: widget.member?.id);
    if (picked != null) {
      setState(() {
        _referrerId = picked.id;
        _referrerName = picked.fullName;
      });
    }
  }

  Map<String, dynamic> _body() {
    String? t(final TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return <String, dynamic>{
      'full_name': _name.text.trim(),
      'phone': _phone.text.replaceAll(' ', ''),
      'alt_phone': t(_altPhone)?.replaceAll(' ', ''),
      'email': t(_email),
      // A NIDA that was not typed again is left as it is.
      if (_nida.text.trim().isNotEmpty) 'nida': _nida.text.trim(),
      'date_of_birth': _born == null ? null : _day(_born!),
      'gender': _gender,
      'region': t(_region),
      'district': t(_district),
      'ward': t(_ward),
      'street': t(_street),
      'occupation': t(_occupation),
      'referrer_id': _referrerId,
      if (!_editing && _existing) ...<String, dynamic>{
        'existing': true,
        'founding': _founding,
        if (_number.text.trim().isNotEmpty) 'member_number': _number.text.trim(),
        if (_joined != null) 'joined_on': _day(_joined!),
      },
    };
  }

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!(_form.currentState?.validate() ?? false)) return;
    if (!_editing) {
      final bool ok = await groupConfirm(
        context,
        title: _existing ? (sw ? 'Weka mwanachama aliyekuwepo?' : 'Enter this existing member?') : (sw ? 'Rekodi ombi la uanachama?' : 'Record this application?'),
        message: _existing
            ? (sw ? '${_name.text.trim()} atakuwa mwanachama hai mara moja.' : '${_name.text.trim()} becomes an active member at once.')
            : (sw ? '${_name.text.trim()} atasubiri malipo ya kujiunga na idhini.' : '${_name.text.trim()} waits for the joining payments and approval.'),
        yes: sw ? 'Hifadhi' : 'Save',
        tone: GroupTone.positive,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GroupMemberFile saved = _editing ? await widget.api.updateMember(widget.member!.id, _body()) : await widget.api.createMember(_body());
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imehifadhiwa.' : 'Saved.');
      Navigator.pop(context, saved);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  Widget _field(final TextEditingController c, final String label, {final String? Function(String?)? validator, final TextInputType? keyboard, final Key? key, final int? maxLength}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          key: key,
          controller: c,
          validator: validator,
          keyboardType: keyboard,
          maxLength: maxLength,
          style: const TextStyle(color: Colors.white),
          decoration: ThemeConstants.darkField(label),
        ),
      );

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool mayEnterExisting = !_editing && widget.me.can('approve_members');
    String? required(final String? v) => (v ?? '').trim().length < 3 ? (sw ? 'Andika jina kamili.' : 'Write the full name.') : null;
    String? phone(final String? v) => _phoneRule.hasMatch((v ?? '').replaceAll(' ', '')) ? null : (sw ? 'Namba si sahihi (mfano 0712345678).' : 'Not a valid number (e.g. 0712345678).');
    String? optionalPhone(final String? v) => (v ?? '').trim().isEmpty ? null : phone(v);

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_editing ? (sw ? 'Badili taarifa' : 'Edit details') : (sw ? 'Mwanachama mpya' : 'New member'), flat: true),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: joinGlowCards(<Widget>[
              GlowCard(
                title: sw ? 'Utambulisho' : 'Identity',
                children: <Widget>[
                  _field(_name, sw ? 'Jina kamili' : 'Full name', validator: required, key: const Key('grp_f_name'), maxLength: 150),
                  _field(_nida, widget.member?.nida == null ? 'NIDA' : '${sw ? 'NIDA (acha wazi isibadilike)' : 'NIDA (leave empty to keep)'} ${widget.member!.nida}',
                      key: const Key('grp_f_nida'), maxLength: 40),
                  Row(children: <Widget>[
                    Expanded(
                      child: Wrap(spacing: 8, children: <Widget>[
                        for (final String g in const <String>['male', 'female'])
                          ChoiceChip(
                            label: Text(g == 'male' ? (sw ? 'Mwanaume' : 'Male') : (sw ? 'Mwanamke' : 'Female')),
                            selected: _gender == g,
                            onSelected: (final bool on) => setState(() => _gender = on ? g : null),
                          ),
                      ]),
                    ),
                  ]),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cake_outlined, color: Colors.white54),
                    title: Text(sw ? 'Tarehe ya kuzaliwa' : 'Date of birth', style: const TextStyle(color: Colors.white70)),
                    trailing: Text(_born == null ? '-' : _day(_born!), style: const TextStyle(color: Colors.white)),
                    onTap: () async {
                      final DateTime? d = await _pickDate(_born ?? DateTime(1990), first: DateTime(1920));
                      if (d != null) setState(() => _born = d);
                    },
                  ),
                ],
              ),
              GlowCard(
                title: sw ? 'Mawasiliano na makazi' : 'Contact and address',
                children: <Widget>[
                  _field(_phone, sw ? 'Namba ya simu' : 'Phone number', validator: phone, keyboard: TextInputType.phone, key: const Key('grp_f_phone')),
                  _field(_altPhone, sw ? 'Namba nyingine (hiari)' : 'Other number (optional)', validator: optionalPhone, keyboard: TextInputType.phone),
                  _field(_email, sw ? 'Barua pepe (hiari)' : 'Email (optional)', keyboard: TextInputType.emailAddress),
                  // Region, district, ward and street: chosen from the imported Tanzania locations (typed only when the list has nothing).
                  if (_editing && <String?>[_region.text, _district.text, _ward.text, _street.text].any((final String? s) => (s ?? '').trim().isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${sw ? 'Makazi ya sasa' : 'Current address'}: ${<String>[_street.text, _ward.text, _district.text, _region.text].where((final String s) => s.trim().isNotEmpty).join(', ')}',
                        key: const Key('grp_f_address_now'),
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PlacePicker(
                      key: const Key('grp_f_place'),
                      source: widget.placeSource,
                      onChanged: (final PlaceChoice c) {
                        // Nothing chosen yet leaves the address as it was.
                        if (c.region == null) return;
                        _region.text = c.region ?? '';
                        _district.text = c.district ?? '';
                        _ward.text = c.ward ?? '';
                        _street.text = c.street ?? '';
                      },
                    ),
                  ),
                  _field(_occupation, sw ? 'Kazi' : 'Occupation'),
                ],
              ),
              GlowCard(
                title: sw ? 'Aliyemleta' : 'Referred by',
                children: <Widget>[
                  ListTile(
                    key: const Key('grp_f_referrer'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_tree_outlined, color: Colors.white54),
                    title: Text(_referrerName ?? (sw ? 'Chagua mwanachama' : 'Choose a member'), style: const TextStyle(color: Colors.white)),
                    trailing: _referrerId == null
                        ? const Icon(Icons.chevron_right, color: Colors.white38)
                        : IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54),
                            onPressed: () => setState(() {
                              _referrerId = null;
                              _referrerName = null;
                            }),
                          ),
                    onTap: _pickReferrer,
                  ),
                ],
              ),
              if (mayEnterExisting)
                GlowCard(
                  title: sw ? 'Uanachama' : 'Membership',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('grp_f_existing'),
                      contentPadding: EdgeInsets.zero,
                      value: _existing,
                      onChanged: (final bool v) => setState(() => _existing = v),
                      title: Text(sw ? 'Alikuwa mwanachama tayari' : 'Was already a member', style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        sw ? 'Anakuwa hai mara moja, bila ombi.' : 'Active at once, without an application.',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ),
                    if (_existing) ...<Widget>[
                      _field(_number, sw ? 'Namba ya uanachama (acha wazi itolewe)' : 'Member number (leave empty to give one)', maxLength: 30),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined, color: Colors.white54),
                        title: Text(sw ? 'Tarehe ya kujiunga' : 'Joined on', style: const TextStyle(color: Colors.white70)),
                        trailing: Text(_joined == null ? (sw ? 'Leo' : 'Today') : _day(_joined!), style: const TextStyle(color: Colors.white)),
                        onTap: () async {
                          final DateTime? d = await _pickDate(_joined, first: DateTime(1990));
                          if (d != null) setState(() => _joined = d);
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _founding,
                        onChanged: (final bool v) => setState(() => _founding = v),
                        title: Text(sw ? 'Mwanzilishi wa kikundi' : 'Founding member', style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, key: const Key('grp_f_error'), style: const TextStyle(color: ThemeConstants.errorText))),
              FilledButton.icon(
                key: const Key('grp_f_save'),
                style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _save,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
                label: Text(sw ? 'Hifadhi' : 'Save'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
