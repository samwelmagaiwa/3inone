import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../widgets/place_picker.dart';
import '../../models/salon_models.dart';
import '../salon/salon_input.dart';

/// What the branch form hands back. For a branch being changed, a place part that is null was not touched (the server keeps it).
class BranchForm {
  const BranchForm({required this.name, this.region, this.district, this.ward, this.street, this.address = '', this.phone = ''});

  final String name;
  final String? region;
  final String? district;
  final String? ward;
  final String? street;

  /// The free part: the building, the landmark ("near the market").
  final String address;
  final String phone;
}

/// The popup that makes (or changes) a branch with its whole place: the name, then region, district, ward and street or village chosen
/// from the imported Tanzania locations (typed when the list has nothing for a place), then the address and a phone number. A new branch
/// needs every part of the place, chosen or typed; a branch being changed keeps its place unless a new one is chosen.
class BranchFormDialog extends StatefulWidget {
  const BranchFormDialog({super.key, this.branch, this.placeSource});

  /// The branch being changed (null for a new one).
  final SalonBranchInfo? branch;

  /// Where the location lists come from (the server's; a test brings its own).
  final PlaceSource? placeSource;

  @override
  State<BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<BranchFormDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.branch?.name ?? '');
  late final TextEditingController _address = TextEditingController(text: widget.branch?.address ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.branch?.phone ?? '');
  PlaceChoice _place = PlaceChoice.empty;
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _editing => widget.branch != null;

  static bool _filled(final String? v) => (v ?? '').trim().isNotEmpty;

  /// Is any part of a new place chosen or typed?
  bool get _placeTouched => <String?>[_place.region, _place.district, _place.ward, _place.street].any(_filled);

  bool get _placeComplete => <String?>[_place.region, _place.district, _place.ward, _place.street].every(_filled);

  /// What is wrong with the place, or null. A new branch needs all four; a changed one needs all four only if a new place was started.
  String? _placeError(final bool sw) {
    if (_editing && !_placeTouched) return null;
    if (_placeComplete) return null;

    return sw ? 'Chagua au andika mkoa, wilaya, kata na mtaa/kijiji vyote.' : 'Choose or type the region, district, ward and street or village: all four.';
  }

  String? _nameError(final bool sw) => _name.text.trim().length >= 2 ? null : (sw ? 'Andika jina la tawi.' : 'Write the branch name.');

  void _save(final bool sw) {
    setState(() => _tried = true);
    if (_nameError(sw) != null || _placeError(sw) != null) return;
    final bool newPlace = _placeTouched;
    Navigator.pop(
      context,
      BranchForm(
        name: _name.text.trim(),
        region: newPlace ? _place.region!.trim() : null,
        district: newPlace ? _place.district!.trim() : null,
        ward: newPlace ? _place.ward!.trim() : null,
        street: newPlace ? _place.street!.trim() : null,
        address: _address.text.trim(),
        phone: _phone.text.trim(),
      ),
    );
  }

  InputDecoration _decoration(final String label, final IconData icon, {final Widget? suffix}) =>
      salonInput(labelText: label).copyWith(prefixIcon: Icon(icon, color: ThemeConstants.invAccent, size: 20), suffixIcon: suffix);

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final String? nameError = _tried ? _nameError(sw) : null;
    final String? placeError = _tried ? _placeError(sw) : null;
    final SalonBranchInfo? b = widget.branch;
    final String current = b == null ? '' : <String>[b.street, b.ward, b.district, b.region].where((String s) => s.isNotEmpty).join(', ');

    return AlertDialog(
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(_editing ? (sw ? 'Badili tawi' : 'Edit branch') : (sw ? 'Tawi jipya' : 'New branch'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            TextField(
              key: const Key('branch_name'),
              controller: _name,
              style: salonInputStyle,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: _decoration(sw ? 'Jina la tawi' : 'Branch name', Icons.storefront_outlined).copyWith(errorText: nameError),
            ),
            const SizedBox(height: 14),
            Text(sw ? 'Mahali lilipo tawi' : 'Where the branch is', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            if (_editing && current.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(sw ? 'Sasa: $current. Chagua mahali papya ukitaka kubadili.' : 'Now: $current. Choose a new place to change it.', key: const Key('branch_current_place'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            // region, district, ward, street or village: chosen from the imported locations, or typed when the list has nothing
            PlacePicker(source: widget.placeSource, onChanged: (final PlaceChoice c) => setState(() => _place = c), decoration: _decoration),
            if (placeError != null) Padding(padding: const EdgeInsets.only(top: 2, bottom: 4), child: Text(placeError, key: const Key('branch_place_error'), style: const TextStyle(color: ThemeConstants.errorText, fontSize: 12))),
            const SizedBox(height: 8),
            TextField(key: const Key('branch_address'), controller: _address, style: salonInputStyle, decoration: _decoration(sw ? 'Anuani (jengo, karibu na ...)' : 'Address (building, near ...)', Icons.place_outlined)),
            const SizedBox(height: 10),
            TextField(key: const Key('branch_phone'), controller: _phone, style: salonInputStyle, keyboardType: TextInputType.phone, decoration: _decoration(sw ? 'Simu ya tawi (hiari)' : 'Branch phone (optional)', Icons.phone_outlined)),
          ]),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(key: const Key('branch_save'), onPressed: () => _save(sw), child: Text(sw ? 'Hifadhi' : 'Save')),
      ],
    );
  }
}
