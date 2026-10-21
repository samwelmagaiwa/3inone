import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import 'salon_input.dart';

/// What clients said after a visit: the average rating, each stylist's average (owner and managers), and the feedback
/// list with open complaints first. A complaint is resolved with a note. A stylist sees only feedback about themselves.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.api});

  final SalonApi? api;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  Map<String, dynamic> _data = <String, dynamic>{};
  String? _error;
  bool _loading = true;

  Map<String, dynamic> get _summary => _data['summary'] is Map ? Map<String, dynamic>.from(_data['summary'] as Map) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[
        if (v is List)
          for (final dynamic r in v)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

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
      final Map<String, dynamic> d = await _api.feedback();
      if (!mounted) return;
      setState(() {
        _data = d;
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

  Future<void> _resolve(final Map<String, dynamic> f) async {
    final String? note = await showDialog<String>(context: context, builder: (BuildContext d) => const _NoteDialog());
    if (note == null || !mounted) return;
    try {
      await _api.resolveFeedback((f['id'] as num).toInt(), note: note);
      if (mounted) await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final Map<String, dynamic> s = _summary;
    final List<Map<String, dynamic>> byStaff = _list(s['by_staff']);

    return Scaffold(
      appBar: salonAppBar(context, sw ? 'Maoni ya wateja' : 'Client feedback'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: <Widget>[
                          _Big(key: const Key('fb_average'), value: s['average'] == null ? '-' : '${s['average']} ★', label: sw ? 'Wastani' : 'Average'),
                          _Big(value: '${s['ratings'] ?? 0}', label: sw ? 'Alama' : 'Ratings'),
                          _Big(key: const Key('fb_open'), value: '${s['open_complaints'] ?? 0}', label: sw ? 'Malalamiko wazi' : 'Open complaints'),
                        ]),
                      ),
                    ),
                    if (byStaff.isNotEmpty) ...<Widget>[
                      Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(sw ? 'Kila mtumishi' : 'By stylist', style: const TextStyle(fontWeight: FontWeight.bold))),
                      for (final Map<String, dynamic> r in byStaff)
                        ListTile(dense: true, title: Text('${r['name'] ?? ''}'), trailing: Text('${r['average']} ★  (${r['ratings']})')),
                    ],
                    Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(sw ? 'Maoni' : 'Feedback', style: const TextStyle(fontWeight: FontWeight.bold))),
                    for (final Map<String, dynamic> f in _list(_data['feedback']))
                      Card(
                        key: Key('fb_${f['id']}'),
                        color: f['kind'] == 'complaint' && f['status'] == 'new' ? Colors.red.shade50 : null,
                        child: ListTile(
                          isThreeLine: true,
                          title: Text(<String>[
                            if (f['rating'] != null) '${'★' * (f['rating'] as num).toInt()}',
                            if (f['kind'] == 'complaint') (sw ? 'Lalamiko' : 'Complaint'),
                            if ('${f['client'] ?? ''}'.isNotEmpty) '${f['client']}',
                          ].join('  ·  ')),
                          subtitle: Text(<String>[
                            if ('${f['message'] ?? ''}'.isNotEmpty) '${f['message']}',
                            if ('${f['staff_name'] ?? ''}'.isNotEmpty) '${sw ? 'Mtumishi' : 'Stylist'}: ${f['staff_name']}',
                            if ('${f['resolution'] ?? ''}'.isNotEmpty) '${sw ? 'Suluhisho' : 'Resolved'}: ${f['resolution']}',
                            '${f['at']}',
                          ].join('\n')),
                          trailing: f['kind'] == 'complaint' && f['status'] == 'new'
                              ? TextButton(key: Key('fb_resolve_${f['id']}'), onPressed: () => _resolve(f), child: Text(sw ? 'Tatua' : 'Resolve'))
                              : null,
                        ),
                      ),
                    if (_list(_data['feedback']).isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna maoni bado.' : 'No feedback yet.', textAlign: TextAlign.center)),
                  ]),
                ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(sw ? 'Tatua lalamiko' : 'Resolve complaint'),
      content: TextField(style: salonInputStyle, key: const Key('fb_note'), controller: _note, decoration: salonInput(labelText: sw ? 'Ulifanya nini? (si lazima)' : 'What was done? (optional)')),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(key: const Key('fb_resolve_save'), onPressed: () => Navigator.pop(context, _note.text.trim()), child: Text(sw ? 'Tatua' : 'Resolve')),
      ],
    );
  }
}
