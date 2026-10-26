import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/assistant_api.dart';
import '../money/money_style.dart';

/// Ask the business a question. The server only answers from what this person is allowed to see, so the suggestions shown are
/// the ones their rights open; the records an answer is based on (customer names, amounts, days) are shown under it exactly as
/// stored, so nothing important depends on the AI's wording.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.api});

  final AssistantApi? api;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _Turn {
  _Turn(this.mine, this.text, [this.cards = const <Map<String, dynamic>>[], this.failed = false]);

  final bool mine;
  final String text;
  final List<Map<String, dynamic>> cards;
  final bool failed;
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

  List<String> get _topics => <String>[
        if (_status['topics'] is List) for (final dynamic t in _status['topics'] as List) '$t',
      ];

  /// Earlier turns for the server (it keeps none itself), without failed ones.
  List<Map<String, String>> _history() => <Map<String, String>>[
        for (final _Turn t in _turns)
          if (!t.failed) <String, String>{'role': t.mine ? 'user' : 'model', 'text': t.text},
      ];

  Future<void> _send([final String? preset]) async {
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
      final Map<String, dynamic> r = await _api.ask(q, sw ? 'sw' : 'en', history);
      if (!mounted) return;
      setState(() {
        _turns.add(_Turn(false, '${r['answer'] ?? ''}', <Map<String, dynamic>>[
          if (r['cards'] is List) for (final dynamic c in r['cards'] as List) if (c is Map) Map<String, dynamic>.from(c),
        ]));
        _status = <String, dynamic>{..._status, 'questions_left': r['questions_left']};
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _turns.add(_Turn(false, readableErrorMessage(e), const <Map<String, dynamic>>[], true)));
    }
    if (mounted) setState(() => _sending = false);
    _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  /// Questions offered as one tap, only for what this person's rights open.
  List<(String, String)> _suggestions(final bool sw) {
    final List<String> t = _topics;

    return <(String, String)>[
      if (t.contains('customers_who_owe')) (sw ? 'Nani ananidai?' : 'Who owes me?', 'sg_owe'),
      if (t.contains('business_report')) (sw ? 'Biashara inaendeleaje mwezi huu?' : 'How is the business this month?', 'sg_month'),
      if (t.contains('find_products')) (sw ? 'Bidhaa gani zinaisha?' : 'Which goods are running low?', 'sg_low'),
      if (t.contains('recent_sales')) (sw ? 'Mauzo ya wiki hii' : 'Sales this week', 'sg_sales'),
      if (t.contains('expenses_summary')) (sw ? 'Matumizi ya mwezi huu' : 'Spending this month', 'sg_spend'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool on = _status['available'] == true;

    return Scaffold(
      appBar: AppBar(title: Text(sw ? 'Msaidizi wa AI' : 'AI assistant')),
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
    final List<(String, String)> ideas = _suggestions(sw);
    final int left = (_status['questions_left'] is num) ? (_status['questions_left'] as num).toInt() : 0;

    return Column(children: <Widget>[
      Expanded(
        child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: <Widget>[
          if (_turns.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Text(
                _topics.isEmpty
                    ? (sw ? 'Akaunti yako haina ruhusa ya kuona data ya biashara, kwa hiyo msaidizi hana cha kujibu.' : 'Your account has no right to view business data, so the assistant has nothing to answer.')
                    : (sw ? 'Uliza kuhusu biashara yako: wateja, madeni, bidhaa, mauzo na matumizi. Nitajibu kulingana na ruhusa zako tu.' : 'Ask about your business: customers, debts, goods, sales and spending. I answer only from what your own rights allow.'),
                style: kMoneyCaption.copyWith(color: Colors.white70, fontSize: 14),
              ),
            ),
          if (_turns.isEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final (String, String) s in ideas) ActionChip(key: Key(s.$2), label: Text(s.$1), onPressed: _sending ? null : () => _send(s.$1)),
            ]),
          for (int i = 0; i < _turns.length; i++) _bubble(_turns[i], i),
          if (_sending) const Padding(padding: EdgeInsets.all(12), child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
        ]),
      ),
      if (_topics.isNotEmpty) _inputBar(sw, left),
    ]);
  }

  Widget _bubble(final _Turn t, final int i) {
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
                decoration: InputDecoration(hintText: sw ? 'Andika swali lako...' : 'Type your question...', counterText: ''),
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
