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
  _FakeAssistant({this.available = true, this.topics = const <String>['customers_who_owe', 'find_products'], this.fail = false});

  final bool available;
  final List<String> topics;
  final bool fail;
  final List<String> questions = <String>[];
  final List<List<Map<String, String>>> histories = <List<Map<String, String>>>[];

  @override
  Future<Map<String, dynamic>> status() async => <String, dynamic>{'available': available, 'topics': topics, 'questions_left': 20};

  @override
  Future<Map<String, dynamic>> ask(final String question, final String lang, final List<Map<String, String>> history) async {
    questions.add(question);
    histories.add(history);
    if (fail) throw Exception('The assistant could not answer now.');

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
  testWidgets('offers only the suggestions this person\'s rights open', (WidgetTester t) async {
    await _open(t, _FakeAssistant());

    expect(_k('sg_owe'), findsOneWidget);
    expect(_k('sg_low'), findsOneWidget);
    expect(_k('sg_month'), findsNothing, reason: 'no report right, no report question');
    expect(_k('sg_spend'), findsNothing);
  });

  testWidgets('a question shows the answer and the customer card with the full name, amount and days', (WidgetTester t) async {
    final _FakeAssistant api = _FakeAssistant();
    await _open(t, api);

    await t.tap(_k('sg_owe'));
    await t.pump();
    await t.pump();

    expect(api.questions, <String>['Who owes me?']);
    expect(find.text('Mama Neema Joseph owes the most.'), findsOneWidget);
    expect(find.text('Mama Neema Joseph'), findsOneWidget);
    expect(find.text('TSh 350,000'), findsOneWidget);
    expect(find.text('120 days'), findsOneWidget);

    await t.enterText(_k('assistant_input'), 'And the second one?');
    await t.tap(_k('assistant_send'));
    await t.pump();
    await t.pump();

    expect(api.histories.last.map((Map<String, String> h) => h['role']).toList(), <String>['user', 'model'], reason: 'the earlier turn goes back to the server');
  });

  testWidgets('says plainly when the assistant is off', (WidgetTester t) async {
    await _open(t, _FakeAssistant(available: false));
    expect(_k('assistant_off'), findsOneWidget);
    expect(_k('assistant_input'), findsNothing);
  });

  testWidgets('says plainly when the person has no right to anything', (WidgetTester t) async {
    await _open(t, _FakeAssistant(topics: const <String>[]));
    expect(_k('assistant_input'), findsNothing);
    expect(find.textContaining('no right to view business data'), findsOneWidget);
  });

  testWidgets('a failed question shows the server\'s plain message', (WidgetTester t) async {
    await _open(t, _FakeAssistant(fail: true));

    await t.tap(_k('sg_owe'));
    await t.pump();
    await t.pump();

    expect(find.textContaining('could not answer now'), findsOneWidget);
  });
}
