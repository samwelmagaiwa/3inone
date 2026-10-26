import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/assistant_api.dart';
import '../money/money_style.dart';

/// Ask the business a question, or ask how to do something in the app. Made for people new to apps: a short welcome, tap-to-ask
/// questions (split into "about my business" and "how do I...?"), plain answers, and the records behind an answer (full names,
/// amounts, days) shown under it exactly as stored, so nothing important depends on the AI's wording. The server decides what this
/// person may read, and which questions to offer, from their rights and their business's services.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.api});

  final AssistantApi? api;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _Turn {
  _Turn(this.mine, this.text, {this.cards = const <Map<String, dynamic>>[], this.failed = false, this.retry});

  final bool mine;
  final String text;
  final List<Map<String, dynamic>> cards;
  final bool failed;

  /// What to send again when a question failed: the question and the suggestion id it came from, if any.
  final (String, String?)? retry;
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final AssistantApi _api = widget.api ?? AssistantApi();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Turn> _turns = <_Turn>[];
  Map<String, dynamic> _status = <String, dynamic>{};
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final Map<String, dynamic> s = await _api.status();
      if (mounted) setState(() => _status = s);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _suggestions => <Map<String, dynamic>>[
        if (_status['suggestions'] is List)
          for (final dynamic s in _status['suggestions'] as List)
            if (s is Map) Map<String, dynamic>.from(s),
      ];

  /// Earlier turns for the server (it keeps none itself), without failed ones.
  List<Map<String, String>> _history() => <Map<String, String>>[
        for (final _Turn t in _turns)
          if (!t.failed) <String, String>{'role': t.mine ? 'user' : 'model', 'text': t.text},
      ];

  Future<void> _send([final String? preset, final String? topic]) async {
    final String q = (preset ?? _input.text).trim();
    if (q.length < 2 || _sending) return;
    final bool sw = LocalizationService.instance.isSwahili;
    final List<Map<String, String>> history = _history();
    setState(() {
      _turns.add(_Turn(true, q));
      _sending = true;
      _input.clear();
    });
    _toEnd();
    try {
      final Map<String, dynamic> r = await _api.ask(q, sw ? 'sw' : 'en', history, topic: topic);
      if (!mounted) return;
      setState(() {
        _turns.add(_Turn(false, '${r['answer'] ?? ''}', cards: <Map<String, dynamic>>[
          if (r['cards'] is List) for (final dynamic c in r['cards'] as List) if (c is Map) Map<String, dynamic>.from(c),
        ]));
        _status = <String, dynamic>{..._status, 'questions_left': r['questions_left']};
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _turns.add(_Turn(false, readableErrorMessage(e), failed: true, retry: (q, topic))));
    }
    if (mounted) setState(() => _sending = false);
    _toEnd();
  }

  /// Try a failed question again: the failed answer and the question above it are dropped first, so the conversation stays clean.
  void _retry(final _Turn failed) {
    final (String, String?)? again = failed.retry;
    if (again == null || _sending) return;
    setState(() {
      _turns.remove(failed);
      if (_turns.isNotEmpty && _turns.last.mine) _turns.removeLast();
    });
    _send(again.$1, again.$2);
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool on = _status['available'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(sw ? 'Msaidizi wa AI' : 'AI assistant'),
        actions: <Widget>[
          if (_turns.isNotEmpty)
            IconButton(key: const Key('assistant_new'), tooltip: sw ? 'Mazungumzo mapya' : 'New conversation', icon: const Icon(Icons.add_comment_outlined), onPressed: _sending ? null : () => setState(_turns.clear)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : !on
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(key: const Key('assistant_off'), sw ? 'Msaidizi wa AI haujawashwa kwenye seva hii. Mwombe msimamizi wa mfumo.' : 'The AI assistant is not switched on for this server. Ask your system administrator.', textAlign: TextAlign.center)))
                  : _chat(sw),
    );
  }

  Widget _chat(final bool sw) {
    final int left = (_status['questions_left'] is num) ? (_status['questions_left'] as num).toInt() : 0;

    return Column(children: <Widget>[
      Expanded(
        child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: <Widget>[
          if (_turns.isEmpty) _welcome(sw),
          for (int i = 0; i < _turns.length; i++) _bubble(_turns[i], i, sw),
          if (_sending) _thinking(sw),
        ]),
      ),
      if (_turns.isNotEmpty && !_sending && _suggestions.isNotEmpty) _quickRow(sw),
      _inputBar(sw, left),
    ]);
  }

  /// The first thing a new user sees: what this is, and questions to tap, in two groups so it is clear what each is for.
  Widget _welcome(final bool sw) {
    final List<Map<String, dynamic>> about = _suggestions.where((Map<String, dynamic> s) => s['tool'] != null).toList();
    final List<Map<String, dynamic>> howTo = _suggestions.where((Map<String, dynamic> s) => s['tool'] == null).toList();

    Widget group(final String title, final List<Map<String, dynamic>> items) => items.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[for (final Map<String, dynamic> s in items) _chip(s, sw)]),
          ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Container(
        key: const Key('assistant_welcome'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: ThemeConstants.invAccent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Icon(Icons.auto_awesome, color: ThemeConstants.invAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              about.isEmpty
                  ? (sw ? 'Akaunti yako haina ruhusa ya kuona data ya biashara, lakini bado unaweza kuniuliza jinsi ya kutumia programu.' : 'Your account cannot view business data, but you can still ask me how to use the app.')
                  : (sw ? 'Karibu! Naweza kukuambia hali ya biashara yako na kukuonyesha jinsi ya kutumia programu hatua kwa hatua. Gusa swali hapa chini au andika lako mwenyewe.' : 'Welcome! I can tell you how your business is doing and show you, step by step, how to use the app. Tap a question below or type your own.'),
              style: const TextStyle(color: Colors.white, height: 1.35),
            ),
          ),
        ]),
      ),
      group(sw ? 'Kuhusu biashara yangu' : 'About my business', about),
      group(sw ? 'Jinsi ya kutumia programu' : 'How do I...?', howTo),
    ]);
  }

  Widget _chip(final Map<String, dynamic> s, final bool sw) {
    final String text = '${sw ? s['sw'] : s['en']}';

    return ActionChip(key: Key('${s['id']}'), label: Text(text), onPressed: _sending ? null : () => _send(text, '${s['id']}'));
  }

  /// After the first answer: the same questions as a swipeable row, so the next question is one tap away.
  Widget _quickRow(final bool sw) => SizedBox(
        height: 46,
        child: ListView(
          key: const Key('assistant_quick'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          children: <Widget>[for (final Map<String, dynamic> s in _suggestions) Padding(padding: const EdgeInsets.only(right: 8), child: _chip(s, sw))],
        ),
      );

  Widget _thinking(final bool sw) => Padding(
        key: const Key('assistant_thinking'),
        padding: const EdgeInsets.all(12),
        child: Row(children: <Widget>[
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(sw ? 'Naangalia rekodi zako...' : 'Looking at your records...', style: kMoneyCaption.copyWith(fontSize: 13)),
        ]),
      );

  Widget _bubble(final _Turn t, final int i, final bool sw) {
    final Color tint = t.mine ? ThemeConstants.invAccent : (t.failed ? ThemeConstants.errorRed : Colors.white);

    return Align(
      alignment: t.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        child: Container(
          key: Key('turn_$i'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: tint.withValues(alpha: t.mine ? 0.28 : 0.10), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            SelectableText(t.text, style: const TextStyle(color: Colors.white, height: 1.35)),
            for (final Map<String, dynamic> c in t.cards) _card(c),
            if (t.failed && t.retry != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: TextButton.icon(key: const Key('assistant_retry'), onPressed: _sending ? null : () => _retry(t), icon: const Icon(Icons.refresh, size: 18), label: Text(sw ? 'Jaribu tena' : 'Try again'))),
          ]),
        ),
      ),
    );
  }

  /// The records behind an answer, as stored: a title (the customer, product or kind of spending), a value, and a note.
  Widget _card(final Map<String, dynamic> c) {
    final List<dynamic> rows = c['rows'] is List ? c['rows'] as List : <dynamic>[];

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('${c['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 6),
        for (final dynamic r in rows)
          if (r is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${r['title'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    if ('${r['note'] ?? ''}'.isNotEmpty) Text('${r['note']}', style: kMoneyCaption),
                  ]),
                ),
                const SizedBox(width: 8),
                Text('${r['value'] ?? ''}', style: const TextStyle(color: Colors.white70)),
              ]),
            ),
      ]),
    );
  }

  Widget _inputBar(final bool sw, final int left) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('assistant_input'),
                controller: _input,
                enabled: !_sending && left > 0,
                maxLength: 600,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(hintText: sw ? 'Andika swali lako hapa...' : 'Type your question here...', counterText: ''),
              ),
            ),
            IconButton(key: const Key('assistant_send'), icon: const Icon(Icons.send_rounded), color: ThemeConstants.invAccent, onPressed: _sending || left <= 0 ? null : () => _send()),
          ]),
          Text(
            left <= 0
                ? (sw ? 'Umefikia kikomo cha maswali ya leo.' : 'You have used today\'s questions.')
                : (sw ? 'AI inaweza kukosea; thibitisha namba muhimu. Maswali yaliyobaki leo: $left' : 'AI can make mistakes; check important numbers. Questions left today: $left'),
            style: kMoneyCaption,
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}
