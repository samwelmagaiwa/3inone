import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import 'salon_input.dart';

/// The salon's switches in one place: texts to clients (reminders, birthday offer, feedback link, come-back), the
/// evening summary to the owner, the cancel/deposit window, the online booking page and the loyalty points. Each
/// switch saves at once; text fields save with their button.
class SalonSettingsScreen extends StatefulWidget {
  const SalonSettingsScreen({super.key, this.api});

  final SalonApi? api;

  @override
  State<SalonSettingsScreen> createState() => _SalonSettingsScreenState();
}

class _SalonSettingsScreenState extends State<SalonSettingsScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  Map<String, dynamic> _s = <String, dynamic>{};
  Map<String, dynamic> _loyalty = <String, dynamic>{};
  final TextEditingController _birthdayText = TextEditingController();
  final TextEditingController _slug = TextEditingController();
  final TextEditingController _cancel = TextEditingController();
  final TextEditingController _per = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _referral = TextEditingController();
  String? _error;
  bool _loading = true;

  /// The server this app talks to may not know the loyalty page yet (a newer app on an older server): the rest still works.
  bool _loyaltyKnown = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_birthdayText, _slug, _cancel, _per, _value, _referral]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill() {
    _birthdayText.text = '${_s['birthday_text'] ?? ''}';
    _slug.text = '${_s['booking_slug'] ?? ''}';
    _cancel.text = '${_s['cancel_hours'] ?? 0}';
    _per.text = '${_loyalty['per'] ?? ''}';
    _value.text = '${_loyalty['value'] ?? ''}';
    _referral.text = '${_loyalty['referral'] ?? ''}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> s = await _api.salonSettingsMap();
      Map<String, dynamic> l = <String, dynamic>{};
      bool known = true;
      try {
        l = await _api.loyaltySettings();
      } on Exception {
        known = false;
      }
      if (!mounted) return;
      setState(() {
        _s = s;
        _loyalty = l;
        _loyaltyKnown = known;
        _fill();
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

  Future<void> _save(final Map<String, dynamic> body, {final bool loyalty = false}) async {
    try {
      final Map<String, dynamic> got = loyalty ? await _api.saveLoyaltySettings(body) : await _api.saveSalonSettingsMap(body);
      if (!mounted) return;
      setState(() {
        if (loyalty) {
          _loyalty = got.isEmpty ? <String, dynamic>{..._loyalty, ...body} : got;
        } else {
          _s = got.isEmpty ? <String, dynamic>{..._s, ...body} : got;
        }
        _fill();
      });
      ThemeConstants.showSuccessSnackBar(context, context.read<LocalizationService>().isSwahili ? 'Imehifadhiwa' : 'Saved');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _presets() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    try {
      final Map<String, dynamic> r = await _api.addCategoryPresets();
      if (!mounted) return;
      final int added = (r['added'] is List) ? (r['added'] as List).length : 0;
      ThemeConstants.showSuccessSnackBar(context, added == 0 ? (sw ? 'Makundi yote yapo tayari.' : 'All the categories are already there.') : (sw ? 'Makundi $added yameongezwa.' : '$added categories added.'));
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Widget _switch(final String key, final String field, final String title, final String sub) => SwitchListTile(
        key: Key(key),
        value: _s[field] == true || _s[field] == 1,
        title: Text(title),
        subtitle: Text(sub),
        onChanged: (bool v) => _save(<String, dynamic>{field: v}),
      );

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final String? url = _s['booking_url'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Mipangilio ya saluni' : 'Salon settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                  _head(sw ? 'Ujumbe kwa wateja' : 'Texts to clients'),
                  _switch('set_rebook', 'rebook_enabled', sw ? 'Vikumbusho vya kurudi' : 'Come-back reminders', sw ? 'Mteja anakumbushwa baada ya muda' : 'Clients are reminded after a while'),
                  _switch('set_reminders', 'appointment_reminders', sw ? 'Kikumbusho cha miadi' : 'Appointment reminders', sw ? 'Siku moja kabla' : 'The day before'),
                  _switch('set_feedback', 'feedback_sms', sw ? 'Ombi la maoni' : 'Ask for feedback', sw ? 'Ujumbe wenye kiungo baada ya kuhudumiwa' : 'A text with a link after a visit'),
                  _switch('set_birthday', 'birthday_offer', sw ? 'Zawadi ya siku ya kuzaliwa' : 'Birthday offer', sw ? 'Ujumbe siku ya kuzaliwa' : 'A text on their birthday'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: <Widget>[
                      Expanded(child: TextField(style: salonInputStyle, key: const Key('set_birthday_text'), controller: _birthdayText, maxLength: 160, decoration: salonInput(labelText: sw ? 'Maneno ya zawadi' : 'Offer wording'))),
                      TextButton(key: const Key('set_birthday_save'), onPressed: () => _save(<String, dynamic>{'birthday_text': _birthdayText.text.trim()}), child: Text(sw ? 'Hifadhi' : 'Save')),
                    ]),
                  ),
                  _head(sw ? 'Mmiliki' : 'Owner'),
                  _switch('set_summary', 'daily_summary', sw ? 'Muhtasari wa jioni' : 'Evening summary', sw ? 'Ujumbe wa jinsi siku ilivyokwenda' : 'A text on how the day went'),
                  _head(sw ? 'Miadi na amana' : 'Appointments and deposits'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: <Widget>[
                      Expanded(
                        child: TextField(style: salonInputStyle, 
                          key: const Key('set_cancel'),
                          controller: _cancel,
                          keyboardType: TextInputType.number,
                          decoration: salonInput(labelText: sw ? 'Saa za mwisho kughairi bila kupoteza amana' : 'Hours before which a client can cancel and keep the deposit'),
                        ),
                      ),
                      TextButton(key: const Key('set_cancel_save'), onPressed: () => _save(<String, dynamic>{'cancel_hours': int.tryParse(_cancel.text.trim()) ?? 0}), child: Text(sw ? 'Hifadhi' : 'Save')),
                    ]),
                  ),
                  _head(sw ? 'Kuweka miadi mtandaoni' : 'Online booking'),
                  _switch('set_online', 'online_booking', sw ? 'Wateja waweke miadi wenyewe' : 'Let clients book themselves', sw ? 'Ukurasa wa mtandaoni wa saluni yako' : 'A web page for your salon'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: <Widget>[
                      Expanded(child: TextField(style: salonInputStyle, key: const Key('set_slug'), controller: _slug, decoration: salonInput(labelText: sw ? 'Anwani (herufi ndogo, namba, -)' : 'Address (lowercase, numbers, -)'))),
                      TextButton(key: const Key('set_slug_save'), onPressed: () => _save(<String, dynamic>{'booking_slug': _slug.text.trim().toLowerCase()}), child: Text(sw ? 'Hifadhi' : 'Save')),
                    ]),
                  ),
                  if (url != null)
                    ListTile(
                      key: const Key('set_url'),
                      title: Text(url),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (context.mounted) ThemeConstants.showSuccessSnackBar(context, sw ? 'Kiungo kimenakiliwa' : 'Link copied');
                        },
                      ),
                    ),
                  _head(sw ? 'Makundi ya huduma' : 'Service categories'),
                  ListTile(
                    key: const Key('set_presets'),
                    leading: const Icon(Icons.category_outlined),
                    title: Text(sw ? 'Weka makundi ya kawaida ya saluni' : 'Add the standard salon categories'),
                    subtitle: Text(sw ? 'Nywele, kusuka, rangi, kucha, make-up, kope, ngozi, masaji, kinyozi… (yaliyopo hayarudiwi)' : 'Hair, braiding, colour, nails, makeup, lashes, skin, massage, barber… (existing ones are not repeated)'),
                    onTap: _presets,
                  ),
                  if (_loyaltyKnown) ...<Widget>[
                  _head(sw ? 'Pointi za uaminifu' : 'Loyalty points'),
                  SwitchListTile(
                    key: const Key('set_loyalty'),
                    value: _loyalty['on'] == true,
                    title: Text(sw ? 'Wateja wapate pointi' : 'Clients earn points'),
                    onChanged: (bool v) => _save(<String, dynamic>{'on': v}, loyalty: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(children: <Widget>[
                      TextField(style: salonInputStyle, key: const Key('set_per'), controller: _per, keyboardType: TextInputType.number, decoration: salonInput(labelText: sw ? 'TSh ngapi kwa pointi 1' : 'TSh spent for 1 point')),
                      TextField(style: salonInputStyle, key: const Key('set_value'), controller: _value, keyboardType: TextInputType.number, decoration: salonInput(labelText: sw ? 'TSh inayopunguzwa kwa pointi 1' : 'TSh off for 1 point used')),
                      TextField(style: salonInputStyle, key: const Key('set_referral'), controller: _referral, keyboardType: TextInputType.number, decoration: salonInput(labelText: sw ? 'Pointi za anayemleta mteja' : 'Points for bringing a client')),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('set_loyalty_save'),
                          onPressed: () => _save(<String, dynamic>{
                            'per': int.tryParse(_per.text.trim()) ?? 1,
                            'value': int.tryParse(_value.text.trim()) ?? 0,
                            'referral': int.tryParse(_referral.text.trim()) ?? 0,
                          }, loyalty: true),
                          child: Text(sw ? 'Hifadhi pointi' : 'Save points'),
                        ),
                      ),
                    ]),
                  ),
                  ],
                ]),
    );
  }

  Widget _head(final String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)));
}
