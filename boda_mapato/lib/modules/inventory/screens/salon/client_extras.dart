import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';

/// Chooses a photo: its bytes and file name, or null when nothing was chosen.
typedef PhotoPicker = Future<(Uint8List, String)?> Function();

Future<(Uint8List, String)?> pickFromGallery() async {
  final XFile? f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
  if (f == null) return null;

  return (await f.readAsBytes(), f.name);
}

final RegExp _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// What a client page adds for a salon: new or returning, loyalty points, birthday and what they like (hairstyle,
/// colour, nails, allergies), their packages, and photos of styles kept with their consent.
class ClientExtras extends StatefulWidget {
  const ClientExtras({super.key, required this.history, required this.api, this.picker});

  final ClientHistory history;
  final SalonApi api;
  final PhotoPicker? picker;

  @override
  State<ClientExtras> createState() => _ClientExtrasState();
}

class _ClientExtrasState extends State<ClientExtras> {
  late final TextEditingController _birthday = TextEditingController(text: widget.history.birthday ?? '');
  late final Map<String, TextEditingController> _prefs = <String, TextEditingController>{
    for (final String k in _keys) k: TextEditingController(text: widget.history.preferences[k] ?? ''),
  };
  static const List<String> _keys = <String>['hairstyle', 'colour', 'nails', 'allergies'];

  List<Map<String, dynamic>> _packages = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _photos = <Map<String, dynamic>>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLists());
  }

  @override
  void dispose() {
    _birthday.dispose();
    for (final TextEditingController c in _prefs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    try {
      final List<Map<String, dynamic>> packages = await widget.api.clientPackages(widget.history.id);
      final List<Map<String, dynamic>> photos = await widget.api.clientPhotos(widget.history.id);
      if (!mounted) return;
      setState(() {
        _packages = packages;
        _photos = photos;
      });
    } on Exception {
      // Optional extras: the client page works without them.
    }
  }

  Future<void> _save(final bool sw) async {
    final String b = _birthday.text.trim();
    if (b.isNotEmpty && !_day.hasMatch(b)) {
      return ThemeConstants.showErrorSnackBar(context, sw ? 'Tarehe iwe mwaka-mwezi-siku, mfano 1995-03-21.' : 'Date as year-month-day, e.g. 1995-03-21.');
    }
    setState(() => _saving = true);
    try {
      await widget.api.saveClient(widget.history.id, birthday: b, preferences: <String, String>{for (final String k in _keys) k: _prefs[k]!.text.trim()});
      if (mounted) ThemeConstants.showSuccessSnackBar(context, sw ? 'Imehifadhiwa' : 'Saved');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPhoto(final bool sw) async {
    final (Uint8List, String)? got = await (widget.picker ?? pickFromGallery)();
    if (got == null || !mounted) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: Text(sw ? 'Idhini ya mteja' : 'Client consent'),
        content: Text(sw ? 'Je, mteja amekubali picha hii ihifadhiwe?' : 'Has the client agreed to this photo being kept?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(sw ? 'Hapana' : 'No')),
          FilledButton(key: const Key('photo_consent'), onPressed: () => Navigator.pop(d, true), child: Text(sw ? 'Ndiyo, amekubali' : 'Yes, agreed')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.uploadClientPhoto(widget.history.id, got.$1, got.$2);
      await _loadLists();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _removePhoto(final Map<String, dynamic> p) async {
    try {
      await widget.api.deleteClientPhoto((p['id'] as num).toInt());
      await _loadLists();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final ClientHistory h = widget.history;
    final Map<String, String> labels = <String, String>{
      'hairstyle': sw ? 'Mtindo wa nywele' : 'Hairstyle',
      'colour': sw ? 'Rangi' : 'Colour',
      'nails': sw ? 'Kucha' : 'Nails',
      'allergies': sw ? 'Mzio (allergies)' : 'Allergies',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Wrap(spacing: 8, children: <Widget>[
            if (h.isReturning != null)
              Chip(key: const Key('client_kind'), label: Text(h.isReturning! ? (sw ? 'Mteja anayerudi' : 'Returning client') : (sw ? 'Mteja mpya' : 'New client'))),
            if (h.loyaltyPoints != null) Chip(key: const Key('client_points'), label: Text(sw ? 'Pointi: ${h.loyaltyPoints}' : 'Points: ${h.loyaltyPoints}')),
            if ((h.referredByName ?? '').isNotEmpty) Chip(label: Text(sw ? 'Alileta: ${h.referredByName}' : 'Brought by ${h.referredByName}')),
          ]),
          TextField(key: const Key('client_birthday'), controller: _birthday, decoration: InputDecoration(labelText: sw ? 'Siku ya kuzaliwa (YYYY-MM-DD)' : 'Birthday (YYYY-MM-DD)')),
          for (final String k in _keys) TextField(key: Key('client_pref_$k'), controller: _prefs[k], maxLength: k == 'allergies' ? 200 : 160, decoration: InputDecoration(labelText: labels[k], counterText: '')),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(key: const Key('client_profile_save'), onPressed: _saving ? null : () => _save(sw), child: Text(sw ? 'Hifadhi' : 'Save')),
          ),
          if (_packages.isNotEmpty) ...<Widget>[
            Text(sw ? 'Vifurushi' : 'Packages', style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final Map<String, dynamic> p in _packages)
              ListTile(
                key: Key('client_package_${p['id']}'),
                dense: true,
                title: Text('${p['name']}'),
                subtitle: Text(<String>[
                  '${p['service_name'] ?? ''}',
                  if (p['expires_on'] != null) '${sw ? 'Mwisho' : 'Expires'} ${p['expires_on']}',
                  if (p['usable'] != true) (p['expired'] == true ? (sw ? 'Imeisha muda' : 'Expired') : (sw ? 'Imekwisha' : 'Used up')),
                ].where((String s) => s.isNotEmpty).join(' · ')),
                trailing: Text('${p['sessions_left']}/${p['sessions_total']}'),
              ),
          ],
          Row(children: <Widget>[
            Expanded(child: Text(sw ? 'Picha za mitindo' : 'Style photos', style: const TextStyle(fontWeight: FontWeight.bold))),
            IconButton(key: const Key('client_photo_add'), tooltip: sw ? 'Ongeza picha' : 'Add photo', icon: const Icon(Icons.add_a_photo_outlined), onPressed: () => _addPhoto(sw)),
          ]),
          if (_photos.isEmpty)
            Text(sw ? 'Hakuna picha bado.' : 'No photos yet.')
          else
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final Map<String, dynamic> p in _photos)
                GestureDetector(
                  key: Key('client_photo_${p['id']}'),
                  onLongPress: () => _removePhoto(p),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network('${p['url']}', width: 90, height: 90, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 90, height: 90, child: Icon(Icons.image_not_supported_outlined)))),
                ),
            ]),
        ]),
      ),
    );
  }
}
