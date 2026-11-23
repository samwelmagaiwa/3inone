import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/scrolling_chip_row.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../models/group_voting_models.dart';
import '../services/groups_api.dart';
import 'voting_common.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_picker.dart';

/// Preparing a voting (or changing a draft): an election for ONE position with its candidates, or a decision on ONE agenda; who may vote; the
/// dates; the quorum and the approval threshold; whether the ballot is secret; and what members may see while it runs. Each voting is made on
/// its own, so a leadership election is one voting for each position. Saved as a draft first; publishing asks a Yes.
class VotingFormScreen extends StatefulWidget {
  const VotingFormScreen({required this.api, super.key, this.existing});

  final GroupsApi api;

  /// A draft being changed; null to make a new voting.
  final GroupVoting? existing;

  @override
  State<VotingFormScreen> createState() => _VotingFormScreenState();
}

class _Candidate {
  _Candidate({String label = '', String description = '', this.memberId}) : label = TextEditingController(text: label), description = TextEditingController(text: description);

  final TextEditingController label;
  final TextEditingController description;
  int? memberId;

  void dispose() {
    label.dispose();
    description.dispose();
  }
}

class _VotingFormScreenState extends State<VotingFormScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title);
  late final TextEditingController _series = TextEditingController(text: widget.existing?.series);
  late final TextEditingController _position = TextEditingController(text: widget.existing?.position);
  late final TextEditingController _description = TextEditingController(text: widget.existing?.description);
  late final TextEditingController _quorum = TextEditingController(text: _num(widget.existing?.quorumPercent ?? 0));
  late final TextEditingController _threshold = TextEditingController(text: _num(widget.existing?.thresholdPercent ?? 50));
  final List<_Candidate> _candidates = <_Candidate>[];
  final List<GroupMember> _selected = <GroupMember>[];
  late String _kind = widget.existing?.kind ?? 'election';
  late String _category = widget.existing?.category ?? 'leadership';
  late String _eligibility = widget.existing?.eligibility ?? 'active';
  late bool _secret = widget.existing?.secret ?? true;
  late bool _allowChange = widget.existing?.allowChange ?? false;
  late bool _showProgress = widget.existing?.showProgress ?? true;
  late String _visibility = widget.existing?.resultsVisibility ?? 'after_close';
  late DateTime _opens = _parse(widget.existing?.opensAt) ?? DateTime.now().add(const Duration(days: 1)).copyWith(hour: 8, minute: 0, second: 0, millisecond: 0, microsecond: 0);
  late DateTime _closes = _parse(widget.existing?.closesAt) ?? DateTime.now().add(const Duration(days: 8)).copyWith(hour: 18, minute: 0, second: 0, millisecond: 0, microsecond: 0);
  bool _busy = false;
  String? _error;

  static String _num(final double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static DateTime? _parse(final String? at) => at == null ? null : DateTime.tryParse(at.replaceFirst(' ', 'T'));

  @override
  void initState() {
    super.initState();
    final GroupVoting? e = widget.existing;
    if (e != null && e.isElection) {
      for (final VotingOption o in e.options) {
        _candidates.add(_Candidate(label: o.label, description: o.description ?? '', memberId: o.memberId));
      }
    }
    if (_candidates.isEmpty) _candidates.addAll(<_Candidate>[_Candidate(), _Candidate()]);
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_title, _series, _position, _description, _quorum, _threshold]) {
      c.dispose();
    }
    for (final _Candidate c in _candidates) {
      c.dispose();
    }
    super.dispose();
  }

  String _iso(final DateTime d) {
    String two(final int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:00';
  }

  Future<DateTime?> _pick(final DateTime initial) async {
    final DateTime? day = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (day == null || !mounted) return null;
    final TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _chooseCandidate(final _Candidate c) async {
    final GroupMember? m = await pickGroupMember(context, api: widget.api);
    if (m == null) return;
    setState(() {
      c.memberId = m.id;
      if (c.label.text.trim().isEmpty) c.label.text = m.fullName;
    });
  }

  Future<void> _addVoter() async {
    final GroupMember? m = await pickGroupMember(context, api: widget.api);
    if (m != null && !_selected.any((final GroupMember s) => s.id == m.id)) setState(() => _selected.add(m));
  }

  /// What is wrong, in words, or null.
  String? _problem(final bool sw) {
    if (_title.text.trim().length < 3) return sw ? 'Andika kichwa cha kura (herufi 3 au zaidi).' : 'Give the voting a title (3 letters or more).';
    if (_kind == 'election' && _position.text.trim().length < 2) return sw ? 'Andika nafasi inayogombewa.' : 'Give the position being elected.';
    if (_kind == 'election') {
      final List<_Candidate> filled = _candidates.where((final _Candidate c) => c.label.text.trim().length >= 2).toList();
      if (filled.length < 2) return sw ? 'Weka angalau wagombea wawili.' : 'Give at least two candidates.';
      final List<int> ids = <int>[for (final _Candidate c in filled) if (c.memberId != null) c.memberId!];
      if (ids.length != ids.toSet().length) return sw ? 'Mgombea mmoja amewekwa mara mbili.' : 'A candidate is listed twice.';
    }
    if (_eligibility == 'selected' && _selected.isEmpty) return sw ? 'Chagua wanachama wanaoruhusiwa kupiga kura.' : 'Choose the members who may vote.';
    if (!_closes.isAfter(_opens)) return sw ? 'Kufunga lazima kuwe baada ya kufungua.' : 'It must close after it opens.';
    final double? q = double.tryParse(_quorum.text.trim().isEmpty ? '0' : _quorum.text.trim());
    if (q == null || q < 0 || q > 100) return sw ? 'Idadi ya chini ni 0 hadi 100.' : 'The quorum is 0 to 100.';
    final double? t = double.tryParse(_threshold.text.trim().isEmpty ? '50' : _threshold.text.trim());
    if (t == null || t < 1 || t > 100) return sw ? 'Kiwango cha kupita ni 1 hadi 100.' : 'The approval needed is 1 to 100.';
    return null;
  }

  Map<String, dynamic> _body() => <String, dynamic>{
        'kind': _kind,
        'category': _category,
        'title': _title.text.trim(),
        'series': _series.text.trim().isEmpty ? null : _series.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        if (_kind == 'election') 'position': _position.text.trim(),
        'eligibility': _eligibility,
        if (_eligibility == 'selected') 'member_ids': <int>[for (final GroupMember m in _selected) m.id],
        'quorum_percent': double.tryParse(_quorum.text.trim().isEmpty ? '0' : _quorum.text.trim()) ?? 0,
        'threshold_percent': double.tryParse(_threshold.text.trim().isEmpty ? '50' : _threshold.text.trim()) ?? 50,
        'secret': _secret,
        'allow_change': _secret ? false : _allowChange,
        'show_progress': _showProgress,
        'results_visibility': _visibility,
        'opens_at': _iso(_opens),
        'closes_at': _iso(_closes),
        if (_kind == 'election')
          'options': <Map<String, dynamic>>[
            for (final _Candidate c in _candidates)
              if (c.label.text.trim().length >= 2) <String, dynamic>{'label': c.label.text.trim(), 'description': c.description.text.trim().isEmpty ? null : c.description.text.trim(), 'member_id': c.memberId},
          ],
      };

  Future<void> _save({required final bool publish}) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? problem = _problem(sw);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (publish) {
      final bool ok = await groupConfirm(
        context,
        title: sw ? 'Hifadhi na uchapishe?' : 'Save and publish?',
        message: '${_kind == 'election' ? _position.text.trim() : _title.text.trim()}\n${sw ? 'Wapiga kura wataarifiwa. Baada ya kuchapisha haibadilishwi.' : 'The voters will be told. It cannot be edited once published.'}',
        yes: sw ? 'Chapisha' : 'Publish',
        tone: GroupTone.positive,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      GroupVoting saved = widget.existing == null ? await widget.api.createVoting(_body()) : await widget.api.updateVoting(widget.existing!.id, _body());
      if (publish) saved = await widget.api.votingAction(saved.id, 'publish');
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, publish ? (sw ? 'Kura imechapishwa.' : 'The voting is published.') : (sw ? 'Rasimu imehifadhiwa.' : 'The draft is saved.'));
      Navigator.pop(context, saved);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(e);
        });
      }
    }
  }

  Widget _field(final TextEditingController c, final String label, {final Key? key, final int maxLines = 1, final TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(key: key, controller: c, maxLines: maxLines, keyboardType: keyboard, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(label)),
      );

  Widget _when(final String label, final DateTime value, final ValueChanged<DateTime> set, final Key key) => InkWell(
        key: key,
        onTap: () async {
          final DateTime? d = await _pick(value);
          if (d != null) setState(() => set(d));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: <Widget>[
            const Icon(Icons.event_rounded, color: ThemeConstants.invAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white60))),
            Text(votingWhen(_iso(value)), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool editing = widget.existing != null;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(editing ? (sw ? 'Hariri rasimu ya kura' : 'Edit the draft') : (sw ? 'Kura mpya' : 'New voting'), flat: true),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              // The buttons first: what kind of voting, then its kind of matter.
              SegmentedButton<String>(
                key: const Key('grp_vf_kind'),
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'election', label: Text(sw ? 'Uchaguzi (nafasi moja)' : 'Election (one position)'), icon: const Icon(Icons.how_to_vote_rounded)),
                  ButtonSegment<String>(value: 'decision', label: Text(sw ? 'Ajenda' : 'Agenda'), icon: const Icon(Icons.fact_check_rounded)),
                ],
                selected: <String>{_kind},
                onSelectionChanged: (final Set<String> v) => setState(() {
                  _kind = v.first;
                  if (_kind == 'election' && _category != 'leadership') _category = 'leadership';
                }),
              ),
              const SizedBox(height: 10),
              ScrollingChipRow(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  for (final String c in votingCategories)
                    ScrollChoiceChip(chipKey: Key('grp_vf_cat_$c'), label: votingCategoryLabel(sw: sw, category: c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                ],
              ),
              const SizedBox(height: 10),
              ...joinGlowCards(<Widget>[
                GlowCard(
                  title: sw ? 'Kinachopigiwa kura' : 'What is voted on',
                  children: <Widget>[
                    _field(_title, sw ? 'Kichwa cha kura' : 'Title of the voting', key: const Key('grp_vf_title')),
                    if (_kind == 'election') _field(_position, sw ? 'Nafasi inayogombewa (mf. Mwenyekiti)' : 'Position being elected (e.g. Chairperson)', key: const Key('grp_vf_position')),
                    _field(_series, sw ? 'Kundi la kura (hiari, mf. Uchaguzi 2026)' : 'Group of votings (optional, e.g. Election 2026)', key: const Key('grp_vf_series')),
                    _field(_description, sw ? 'Maelezo na taarifa za msingi' : 'Description and background', key: const Key('grp_vf_description'), maxLines: 4),
                  ],
                ),
                if (_kind == 'election')
                  GlowCard(
                    title: sw ? 'Wagombea wa nafasi hii' : 'Candidates for this position',
                    children: <Widget>[
                      for (int i = 0; i < _candidates.length; i++)
                        Column(key: Key('grp_vf_candidate_$i'), children: <Widget>[
                          Row(children: <Widget>[
                            Expanded(child: _field(_candidates[i].label, '${sw ? 'Mgombea' : 'Candidate'} ${i + 1}')),
                            IconButton(tooltip: sw ? 'Chagua mwanachama' : 'Choose a member', onPressed: () => _chooseCandidate(_candidates[i]), icon: Icon(_candidates[i].memberId == null ? Icons.person_search_rounded : Icons.verified_user_rounded, color: _candidates[i].memberId == null ? Colors.white54 : ThemeConstants.successGreen)),
                            if (_candidates.length > 2) IconButton(tooltip: sw ? 'Ondoa' : 'Remove', onPressed: () => setState(() => _candidates.removeAt(i).dispose()), icon: const Icon(Icons.close_rounded, color: ThemeConstants.errorText)),
                          ]),
                          _field(_candidates[i].description, sw ? 'Maelezo mafupi ya mgombea (hiari)' : 'A short note about the candidate (optional)'),
                        ]),
                      TextButton.icon(key: const Key('grp_vf_add_candidate'), onPressed: () => setState(() => _candidates.add(_Candidate())), icon: const Icon(Icons.add_rounded, color: ThemeConstants.primaryOrange), label: Text(sw ? 'Ongeza mgombea' : 'Add a candidate', style: const TextStyle(color: ThemeConstants.primaryOrange))),
                    ],
                  ),
                GlowCard(
                  title: sw ? 'Wanaoruhusiwa kupiga kura' : 'Who may vote',
                  children: <Widget>[
                    SegmentedButton<String>(
                      key: const Key('grp_vf_eligibility'),
                      segments: <ButtonSegment<String>>[
                        ButtonSegment<String>(value: 'active', label: Text(sw ? 'Wanachama wote' : 'All members')),
                        ButtonSegment<String>(value: 'selected', label: Text(sw ? 'Chagua wachache' : 'Choose some')),
                      ],
                      selected: <String>{_eligibility},
                      onSelectionChanged: (final Set<String> v) => setState(() => _eligibility = v.first),
                    ),
                    if (_eligibility == 'selected')
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Wrap(spacing: 8, children: <Widget>[for (final GroupMember m in _selected) InputChip(label: Text(m.fullName), onDeleted: () => setState(() => _selected.remove(m)))]),
                        TextButton.icon(key: const Key('grp_vf_add_voter'), onPressed: _addVoter, icon: const Icon(Icons.person_add_alt_1_rounded, color: ThemeConstants.primaryOrange), label: Text(sw ? 'Ongeza mwanachama' : 'Add a member', style: const TextStyle(color: ThemeConstants.primaryOrange))),
                      ]),
                  ],
                ),
                GlowCard(
                  title: sw ? 'Tarehe na masharti' : 'Dates and rules',
                  children: <Widget>[
                    _when(sw ? 'Inafunguliwa' : 'Opens', _opens, (final DateTime d) => _opens = d, const Key('grp_vf_opens')),
                    _when(sw ? 'Inafungwa' : 'Closes', _closes, (final DateTime d) => _closes = d, const Key('grp_vf_closes')),
                    _field(_quorum, sw ? 'Idadi ya chini ya wapiga kura (%)' : 'Quorum: the least share of voters (%)', key: const Key('grp_vf_quorum'), keyboard: TextInputType.number),
                    if (_kind == 'decision') _field(_threshold, sw ? 'Kiwango cha kupita (% ya Ndiyo kati ya Ndiyo na Hapana)' : 'Approval needed (% of Approve among Approve and Reject)', key: const Key('grp_vf_threshold'), keyboard: TextInputType.number),
                  ],
                ),
                GlowCard(
                  title: sw ? 'Usiri na matokeo' : 'Privacy and results',
                  children: <Widget>[
                    SwitchListTile(key: const Key('grp_vf_secret'), contentPadding: EdgeInsets.zero, title: Text(sw ? 'Kura ya siri' : 'Secret ballot', style: const TextStyle(color: Colors.white)), subtitle: Text(sw ? 'Hakuna anayejua nani alichagua nini.' : 'Nobody can tell who chose what.', style: const TextStyle(color: Colors.white54, fontSize: 12)), value: _secret, onChanged: (final bool v) => setState(() {
                          _secret = v;
                          if (v) _allowChange = false;
                        })),
                    SwitchListTile(key: const Key('grp_vf_change'), contentPadding: EdgeInsets.zero, title: Text(sw ? 'Ruhusu kubadilisha kura' : 'Allow changing a vote', style: TextStyle(color: _secret ? Colors.white38 : Colors.white)), subtitle: Text(_secret ? (sw ? 'Haiwezekani katika kura ya siri.' : 'Not possible in a secret ballot.') : (sw ? 'Hadi kura ifungwe.' : 'Until the voting closes.'), style: const TextStyle(color: Colors.white54, fontSize: 12)), value: _allowChange, onChanged: _secret ? null : (final bool v) => setState(() => _allowChange = v)),
                    SwitchListTile(key: const Key('grp_vf_progress'), contentPadding: EdgeInsets.zero, title: Text(sw ? 'Onyesha ushiriki kwa wanachama' : 'Show participation to members', style: const TextStyle(color: Colors.white)), value: _showProgress, onChanged: (final bool v) => setState(() => _showProgress = v)),
                    Wrap(spacing: 8, children: <Widget>[
                      for (final String v in const <String>['live', 'after_close', 'after_publish'])
                        ChoiceChip(key: Key('grp_vf_vis_$v'), label: Text(switch (v) { 'live' => sw ? 'Wakati unaendelea' : 'While it runs', 'after_publish' => sw ? 'Baada ya kutangazwa' : 'When announced', _ => sw ? 'Ikifungwa' : 'When closed' }), selected: _visibility == v, onSelected: (_) => setState(() => _visibility = v)),
                    ]),
                  ],
                ),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, key: const Key('grp_vf_error'), style: const TextStyle(color: ThemeConstants.errorText))),
              Row(children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('grp_vf_save'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _busy ? null : () => _save(publish: false),
                    icon: const Icon(Icons.save_rounded),
                    label: Text(sw ? 'Hifadhi rasimu' : 'Save draft'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('grp_vf_publish'),
                    style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _busy ? null : () => _save(publish: true),
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: Text(sw ? 'Hifadhi na uchapishe' : 'Save and publish'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
