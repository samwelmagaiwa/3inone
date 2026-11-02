import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/theme_constants.dart';
import '../services/api_service.dart';
import '../services/localization_service.dart';

/// One place in a list: the id the next level is asked with, and the name that is kept.
class PlaceOption {
  const PlaceOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// Where the person ended up: each part chosen from the imported Tanzania locations, or typed when the list has nothing for it.
class PlaceChoice {
  const PlaceChoice({this.region, this.district, this.ward, this.street});

  final String? region;
  final String? district;
  final String? ward;
  final String? street;

  static const PlaceChoice empty = PlaceChoice();
}

/// Where the lists come from. A failure to load is the same as an empty list: the person types the place.
abstract class PlaceSource {
  Future<List<PlaceOption>> regions();
  Future<List<PlaceOption>> districts(String regionId);
  Future<List<PlaceOption>> wards(String districtId);
  Future<List<PlaceOption>> streets(String wardId);
}

/// The imported locations on the server (`/locations/...`, open to everyone, so it works before anyone has an account).
class ApiPlaceSource implements PlaceSource {
  ApiPlaceSource([final ApiService? api]) : _api = api ?? ApiService();

  final ApiService _api;

  static List<PlaceOption> _options(final Map<String, dynamic> response) {
    final Object? data = response['data'];
    if (data is! List) return const <PlaceOption>[];
    return <PlaceOption>[
      for (final Object? row in data)
        if (row is Map && row['id'] != null && (row['name'] ?? '').toString().trim().isNotEmpty)
          PlaceOption(id: row['id'].toString(), name: row['name'].toString().trim()),
    ];
  }

  @override
  Future<List<PlaceOption>> regions() async => _options(await _api.getLocationsRegions());

  @override
  Future<List<PlaceOption>> districts(final String regionId) async => _options(await _api.getLocationsDistricts(regionId));

  @override
  Future<List<PlaceOption>> wards(final String districtId) async => _options(await _api.getLocationsWards(districtId));

  @override
  Future<List<PlaceOption>> streets(final String wardId) async => _options(await _api.getLocationsStreets(wardId));
}

/// What the sheet returns when the person says the place is not in the list.
class _TypeIt {
  const _TypeIt();
}

/// One level (region, district, ward, street or village): what is on offer and what was done with it.
class _Level {
  List<PlaceOption> options = const <PlaceOption>[];
  bool loading = false;
  PlaceOption? chosen;

  /// The person types this one: by choice ("not in the list"), or because the list has nothing for it.
  bool typing = false;
  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();

  /// The part as it will be kept: the chosen name, or what was typed.
  String? get value {
    if (chosen != null) return chosen!.name;
    final String typed = text.text.trim();
    return typing && typed.isNotEmpty ? typed : null;
  }

  void clear() {
    options = const <PlaceOption>[];
    loading = false;
    chosen = null;
    typing = false;
    text.clear();
  }

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

/// Region, district, ward and street or village, one under the other and each depending on the one before. Every level is chosen from the
/// imported Tanzania locations (with a search box), and when the list has nothing for a place, or the person says it is not there, the
/// level becomes a box to type in. Nothing here is ever required: a person with no data for their place is never stopped.
class PlacePicker extends StatefulWidget {
  const PlacePicker({super.key, required this.onChanged, this.source, this.decoration});

  final ValueChanged<PlaceChoice> onChanged;

  /// Replaceable so the picker can be tested without a network.
  final PlaceSource? source;

  /// How a field looks (the form it sits in decides); a dark rounded field by default.
  final InputDecoration Function(String label, IconData icon, {Widget? suffix})? decoration;

  @override
  State<PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<PlacePicker> {
  static const List<IconData> _icons = <IconData>[Icons.map_outlined, Icons.location_city_outlined, Icons.holiday_village_outlined, Icons.signpost_outlined];

  final List<_Level> _levels = List<_Level>.generate(4, (_) => _Level());
  final List<int> _generation = List<int>.filled(4, 0);
  late final PlaceSource _source = widget.source ?? ApiPlaceSource();

  LocalizationService get _loc => LocalizationService.instance;

  List<String> get _labels => <String>[_loc.translate('place_region'), _loc.translate('place_district'), _loc.translate('place_ward'), _loc.translate('place_street')];

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  @override
  void dispose() {
    for (final _Level l in _levels) {
      l.dispose();
    }
    super.dispose();
  }

  PlaceChoice get _choice => PlaceChoice(region: _levels[0].value, district: _levels[1].value, ward: _levels[2].value, street: _levels[3].value);

  void _notify() => widget.onChanged(_choice);

  bool _enabled(final int level) => level == 0 || _levels[level - 1].value != null;

  Future<List<PlaceOption>> _fetch(final int level) {
    switch (level) {
      case 0:
        return _source.regions();
      case 1:
        return _source.districts(_levels[0].chosen!.id);
      case 2:
        return _source.wards(_levels[1].chosen!.id);
      default:
        return _source.streets(_levels[2].chosen!.id);
    }
  }

  /// Asks for what is on offer at [level] (its parent was chosen from a list). An empty answer, or a failure, turns the level into a box
  /// to type in.
  Future<void> _load(final int level) async {
    final _Level l = _levels[level];
    final int generation = ++_generation[level];
    setState(() {
      l.loading = true;
      l.options = const <PlaceOption>[];
      l.typing = false;
    });
    List<PlaceOption> list = const <PlaceOption>[];
    try {
      list = await _fetch(level);
    } on Exception {
      // no list: the person types the place
    }
    if (!mounted || generation != _generation[level]) return;
    setState(() {
      l.options = list;
      l.loading = false;
      if (list.isEmpty) l.typing = true;
    });
  }

  /// Everything under [level] starts again (its parent changed).
  void _resetBelow(final int level) {
    for (int i = level + 1; i < _levels.length; i++) {
      _generation[i]++;
      _levels[i].clear();
    }
  }

  /// What a level under a parent the person typed looks like: a box to type in (there is no list to ask for).
  void _typeBelowIf(final int level) {
    if (level + 1 < _levels.length) _levels[level + 1].typing = true;
  }

  void _choose(final int level, final PlaceOption option) {
    setState(() {
      final _Level l = _levels[level];
      l.chosen = option;
      l.typing = false;
      l.text.clear();
      _resetBelow(level);
    });
    if (level + 1 < _levels.length) _load(level + 1);
    _notify();
  }

  void _startTyping(final int level) {
    setState(() {
      final _Level l = _levels[level];
      l.chosen = null;
      l.typing = true;
      l.text.clear();
      _resetBelow(level);
      _typeBelowIf(level);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _levels[level].focus.requestFocus());
    _notify();
  }

  void _typed(final int level) {
    setState(() {
      _resetBelow(level);
      _typeBelowIf(level);
    });
    _notify();
  }

  void _backToList(final int level) {
    setState(() {
      final _Level l = _levels[level];
      l.typing = false;
      l.text.clear();
      _resetBelow(level);
    });
    _notify();
  }

  Future<void> _openSheet(final int level) async {
    final Object? picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20.r))),
      builder: (final BuildContext _) => _PlaceSheet(title: _labels[level], options: _levels[level].options),
    );
    if (!mounted || picked == null) return;
    if (picked is PlaceOption) {
      _choose(level, picked);
    } else {
      _startTyping(level);
    }
  }

  InputDecoration _decoration(final String label, final IconData icon, {final Widget? suffix}) {
    final InputDecoration Function(String, IconData, {Widget? suffix})? custom = widget.decoration;
    if (custom != null) return custom(label, icon, suffix: suffix);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white54, fontSize: 13.sp),
      prefixIcon: Icon(icon, color: ThemeConstants.primaryCyan, size: 20.sp),
      prefixIconConstraints: BoxConstraints(minWidth: 40.w, minHeight: 40.h),
      suffixIcon: suffix,
      suffixIconConstraints: BoxConstraints(minWidth: 34.w, minHeight: 34.h),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: Colors.white12)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: Colors.white10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: const BorderSide(color: ThemeConstants.primaryCyan)),
    );
  }

  Widget _field(final int level) {
    final _Level l = _levels[level];
    final bool enabled = _enabled(level);
    final String label = _labels[level];

    if (l.typing) {
      return TextFormField(
        key: ValueKey<String>('place_text_$level'),
        controller: l.text,
        focusNode: l.focus,
        enabled: enabled,
        style: const TextStyle(color: Colors.white),
        onChanged: (_) => _typed(level),
        decoration: _decoration(label, _icons[level], suffix: l.options.isEmpty
            ? null
            : IconButton(
                key: ValueKey<String>('place_list_$level'),
                tooltip: _loc.translate('place_choose_from_list'),
                icon: Icon(Icons.list_alt_rounded, color: Colors.white54, size: 20.sp),
                onPressed: () => _backToList(level),
              )),
      );
    }

    final String hint = !enabled ? _loc.translateWith('place_parent_first', <Object?>[_labels[level - 1].toLowerCase()]) : _loc.translate('place_choose');
    return InkWell(
      key: ValueKey<String>('place_select_$level'),
      borderRadius: BorderRadius.circular(12.r),
      onTap: enabled && !l.loading ? () => _openSheet(level) : null,
      child: InputDecorator(
        isEmpty: l.chosen == null,
        decoration: _decoration(label, _icons[level], suffix: l.loading
            ? Padding(padding: EdgeInsets.all(14.w), child: SizedBox(width: 16.w, height: 16.w, child: const CircularProgressIndicator(strokeWidth: 2)))
            : Icon(Icons.arrow_drop_down, color: enabled ? Colors.white54 : Colors.white24)).copyWith(
          enabled: enabled,
          hintText: hint,
          hintMaxLines: 1,
          hintStyle: TextStyle(color: enabled ? Colors.white30 : Colors.white24, fontSize: 12.sp),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
        child: Text(
          l.chosen?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: enabled ? Colors.white : Colors.white38, fontSize: 15.sp),
        ),
      ),
    );
  }

  /// Two fields side by side (one under the other on a very narrow screen).
  Widget _pair(final int a, final int b) {
    return LayoutBuilder(
      builder: (final BuildContext context, final BoxConstraints box) {
        if (box.maxWidth < 300) {
          return Column(children: <Widget>[_field(a), SizedBox(height: 14.h), _field(b)]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[Expanded(child: _field(a)), SizedBox(width: 12.w), Expanded(child: _field(b))],
        );
      },
    );
  }

  @override
  Widget build(final BuildContext context) {
    return Column(
      children: <Widget>[
        _pair(0, 1),
        SizedBox(height: 14.h),
        _pair(2, 3),
      ],
    );
  }
}

/// The list of one level, with a search box and the way out for a place that is not in it.
class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet({required this.title, required this.options});

  final String title;
  final List<PlaceOption> options;

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  final TextEditingController _query = TextEditingController();

  LocalizationService get _loc => LocalizationService.instance;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final String q = _query.text.trim().toLowerCase();
    final List<PlaceOption> shown = q.isEmpty ? widget.options : widget.options.where((final PlaceOption o) => o.name.toLowerCase().contains(q)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: <Widget>[
            SizedBox(height: 10.h),
            Container(width: 40.w, height: 4.h, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4.r))),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 8.h),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.title, style: TextStyle(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.w700)),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: TextField(
                key: const ValueKey<String>('place_search'),
                controller: _query,
                autofocus: false,
                style: const TextStyle(color: Colors.white),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _loc.translate('place_search'),
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                ),
              ),
            ),
            ListTile(
              key: const ValueKey<String>('place_type_it'),
              leading: const Icon(Icons.edit_outlined, color: ThemeConstants.primaryCyan),
              title: Text(_loc.translate('place_type_instead'), style: const TextStyle(color: ThemeConstants.primaryCyan, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(context).pop(const _TypeIt()),
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(_loc.translate('place_no_match'), style: const TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (final BuildContext context, final int i) => ListTile(
                        key: ValueKey<String>('place_option_${shown[i].id}'),
                        title: Text(shown[i].name, style: const TextStyle(color: Colors.white)),
                        onTap: () => Navigator.of(context).pop(shown[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
