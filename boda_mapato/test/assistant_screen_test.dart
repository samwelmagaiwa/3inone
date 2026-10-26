import 'package:boda_mapato/modules/inventory/screens/assistant/assistant_screen.dart';
import 'package:boda_mapato/modules/inventory/services/assistant_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The AI assistant screen: what it offers follows the person's rights, answers show the records (full customer names, amounts)
/// under the text, earlier turns go back to the server, and a server refusal is shown plainly.
class _FakeAssistant extends AssistantApi {
  _FakeAssistant({this.available = true, this.suggestions = _defaults, this.failTimes = 0});

  static const List<Map<String, dynamic>> _defaults = <Map<String, dynamic>>[
    <String, dynamic>{'id': 'sg_owe', 'en': 'Who owes me?', 'sw': 'Nani ananidai?', 'tool': 'customers_who_owe'},
    <String, dynamic>{'id': 'sg_low', 'en': 'Which goods are running low?', 'sw': 'Bidhaa gani zinaisha?', 'tool': 'find_products'},
    <String, dynamic>{'id': 'hg_sale', 'en': 'How do I record a sale?', 'sw': 'Ninarekodije mauzo?', 'tool': null},
  ];

  final bool available;
  final List<Map<String, dynamic>> suggestions;
  int failTimes;
  final List<String> questions = <String>[];
  final List<String?> topics = <String?>[];
  final List<List<Map<String, String>>> histories = <List<Map<String, String>>>[];

  @override
  Future<Map<String, dynamic>> status() async => <String, dynamic>{'available': available, 'suggestions': suggestions, 'services': <String>['inventory'], 'questions_left': 20};

  @override
  Future<Map<String, dynamic>> ask(final String question, final String lang, final List<Map<String, String>> history, {final String? topic}) async {
    questions.add(question);
    topics.add(topic);
    histories.add(history);
    if (failTimes > 0) {
      failTimes--;
      throw Exception('The assistant could not answer now.');
    }

    return <String, dynamic>{
      'answer': 'Mama Neema Joseph owes the most.',
      'cards': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'rows',
          'title': 'Owe the business',
          'rows': <Map<String, dynamic>>[
            <String, dynamic>{'title': 'Mama Neema Joseph', 'value': 'TSh 350,000', 'note': '120 days'},
          ],
        },
      ],
      'questions_left': 19,
    };
  }
}

Future<void> _open(WidgetTester t, AssistantApi api, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: MaterialApp(home: AssistantScreen(api: api)),
    ),
  );
  await t.pump();
  await t.pump();
}

Finder _k(String k) => find.byKey(Key(k));

void main() {
  testWidgets('welcomes a new user and groups the questions: about the business, and how to use the app', (WidgetTester t) async {
    await _open(t, _FakeAssistant());

    expect(_k('assistant_welcome'), findsOneWidget);
    expect(find.text('About my business'), findsOneWidget);
    expect(find.text('How do I...?'), findsOneWidget);
    expect(_k('sg_owe'), findsOneWidget);
    expect(_k('hg_sale'), findsOneWidget);
    expect(_k('sg_month'), findsNothing, reason: 'the server offers only what the rights of this person open');
  });

  testWidgets('shows the questions in Swahili when the app is in Swahili', (WidgetTester t) async {
    await _open(t, _FakeAssistant(), sw: true);

    expect(find.text('Nani ananidai?'), findsOneWidget);
    expect(find.text('Jinsi ya kutumia programu'), findsOneWidget);
  });

  testWidgets('a tapped question goes with its id, shows the answer and the customer card with full name, amount and days', (WidgetTester t) async {
    final _FakeAssistant api = _FakeAssistant();
    await _open(t, api);

    await t.tap(_k('sg_owe'));
    await t.pump();
    await t.pump();

    expect(api.questions, <String>['Who owes me?']);
    expect(api.topics, <String?>['sg_owe'], reason: 'the id lets the server answer in one fast call');
    expect(find.text('Mama Neema Joseph owes the most.'), findsOneWidget);
    expect(find.text('Mama Neema Joseph'), findsOneWidget);
    expect(find.text('TSh 350,000'), findsOneWidget);
    expect(find.text('120 days'), findsOneWidget);
    expect(_k('assistant_quick'), findsOneWidget, reason: 'the next question is one tap away');

    await t.enterText(_k('assistant_input'), 'And the second one?');
    await t.tap(_k('assistant_send'));
    await t.pump();
    await t.pump();

    expect(api.topics.last, isNull, reason: 'a typed question is free-form');
    expect(api.histories.last.map((Map<String, String> h) => h['role']).toList(), <String>['user', 'model'], reason: 'the earlier turn goes back to the server');
  });

  testWidgets('a new conversation clears the chat', (WidgetTester t) async {
    await _open(t, _FakeAssistant());
    await t.tap(_k('sg_owe'));
    await t.pump();
    await t.pump();
    expect(_k('turn_0'), findsOneWidget);

    await t.tap(_k('assistant_new'));
    await t.pump();

    expect(_k('turn_0'), findsNothing);
    expect(_k('assistant_welcome'), findsOneWidget);
  });

  testWidgets('says plainly when the assistant is off', (WidgetTester t) async {
    await _open(t, _FakeAssistant(available: false));
    expect(_k('assistant_off'), findsOneWidget);
    expect(_k('assistant_input'), findsNothing);
  });

  testWidgets('a person with no business rights is still offered how-to help', (WidgetTester t) async {
    await _open(t, _FakeAssistant(suggestions: const <Map<String, dynamic>>[
      <String, dynamic>{'id': 'hg_start', 'en': 'What can I do in this app?', 'sw': 'x', 'tool': null},
    ]));

    expect(find.textContaining('cannot view business data'), findsOneWidget);
    expect(find.text('About my business'), findsNothing);
    expect(_k('hg_start'), findsOneWidget);
    expect(_k('assistant_input'), findsOneWidget);
  });

  testWidgets('a failed question shows a plain message and Try again asks it again without a duplicate', (WidgetTester t) async {
    final _FakeAssistant api = _FakeAssistant(failTimes: 1);
    await _open(t, api);

    await t.tap(_k('sg_owe'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('could not answer now'), findsOneWidget);

    await t.tap(_k('assistant_retry'));
    await t.pump();
    await t.pump();

    expect(api.questions, <String>['Who owes me?', 'Who owes me?']);
    expect(api.topics, <String?>['sg_owe', 'sg_owe']);
    expect(find.textContaining('could not answer now'), findsNothing);
    expect(find.descendant(of: _k('turn_0'), matching: find.text('Who owes me?')), findsOneWidget);
    expect(_k('turn_2'), findsNothing, reason: 'one question and one answer, not a duplicate');
    expect(find.text('Mama Neema Joseph owes the most.'), findsOneWidget);
  });
}
