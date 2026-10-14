import 'package:boda_mapato/models/sms_sender.dart';
import 'package:boda_mapato/screens/admin/sms_senders_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/widgets/pending_registrations_count.dart';
import 'package:boda_mapato/widgets/pending_sms_senders_count.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

SmsSenderEntry _entry(
  String id,
  String name, {
  SmsSenderInfo sender = const SmsSenderInfo(),
  String owner = 'Asha Owner',
  String phone = '0743519100',
  String tin = '123-456-789',
}) =>
    SmsSenderEntry(id: id, name: name, sender: sender, ownerName: owner, ownerPhone: phone, tin: tin);

class _FakeSource implements SmsSendersDataSource {
  _FakeSource(this.entries);

  List<SmsSenderEntry> entries;
  String platformSender = 'PLATFORM';
  bool delivering = true;
  int pageSize = 50;
  Object? saveError;
  SmsSenderTestResult testResult = const SmsSenderTestResult(outcome: 'accepted', senderId: 'MAMAASHA');

  final List<({String status, String? query, int page})> loads = <({String status, String? query, int page})>[];
  final List<({String id, SmsSenderEdit edit})> saves = <({String id, SmsSenderEdit edit})>[];
  final List<({String id, String? phone, String? senderId, String? apiKey, String? apiSecret})> tests =
      <({String id, String? phone, String? senderId, String? apiKey, String? apiSecret})>[];

  @override
  Future<SmsSenderPage> load({String status = 'all', String? query, int page = 1, int perPage = 50}) async {
    loads.add((status: status, query: query, page: page));
    final String q = (query ?? '').trim().toLowerCase();
    final List<SmsSenderEntry> matching = entries.where((SmsSenderEntry e) {
      final bool byStatus = switch (status) {
        'all' => true,
        'attention' => e.sender.needsAttention,
        _ => e.sender.status == status,
      };
      final bool byQuery = q.isEmpty || <String>[e.name, e.ownerName, e.tin, e.sender.senderId ?? ''].any((String t) => t.toLowerCase().contains(q));
      return byStatus && byQuery;
    }).toList();
    final int from = (page - 1) * pageSize;
    final List<SmsSenderEntry> slice = matching.skip(from).take(pageSize).toList();
    int count(bool Function(SmsSenderEntry) test) => entries.where(test).length;
    return SmsSenderPage(
      items: slice,
      counts: <String, int>{
        'total': entries.length,
        'none': count((SmsSenderEntry e) => e.sender.status == 'none'),
        'pending': count((SmsSenderEntry e) => e.sender.status == 'pending'),
        'approved': count((SmsSenderEntry e) => e.sender.status == 'approved'),
        'rejected': count((SmsSenderEntry e) => e.sender.status == 'rejected'),
        'attention': count((SmsSenderEntry e) => e.sender.needsAttention),
      },
      platformSender: platformSender,
      smsDelivering: delivering,
      page: page,
      hasMore: from + pageSize < matching.length,
    );
  }

  @override
  Future<SmsSenderEntry> save(String businessId, SmsSenderEdit edit) async {
    if (saveError != null) throw saveError!;
    saves.add((id: businessId, edit: edit));
    final SmsSenderEntry old = entries.firstWhere((SmsSenderEntry e) => e.id == businessId);
    final bool has = edit.senderId.trim().isNotEmpty;
    final bool keyStays = !edit.clearCredentials && has && (old.sender.hasApiKey || edit.apiKey.trim().isNotEmpty);
    final SmsSenderEntry updated = SmsSenderEntry(
      id: old.id,
      name: old.name,
      tin: old.tin,
      ownerName: old.ownerName,
      ownerPhone: old.ownerPhone,
      sender: SmsSenderInfo(
        senderId: has ? edit.senderId.trim() : null,
        displayName: edit.displayName.trim().isEmpty ? null : edit.displayName.trim(),
        status: has ? edit.status : 'none',
        note: edit.note.trim().isEmpty ? null : edit.note.trim(),
        hasApiKey: keyStays,
        hasApiSecret: keyStays && (old.sender.hasApiSecret || edit.apiSecret.trim().isNotEmpty),
        apiKeyHint: keyStays ? '****1234' : null,
        fallbackPlatform: edit.fallbackPlatform ?? (keyStays ? false : true),
      ),
    );
    entries = <SmsSenderEntry>[for (final SmsSenderEntry e in entries) e.id == businessId ? updated : e];
    return updated;
  }

  @override
  Future<SmsSenderTestResult> test(String businessId, {String? phone, String? senderId, String? apiKey, String? apiSecret}) async {
    tests.add((id: businessId, phone: phone, senderId: senderId, apiKey: apiKey, apiSecret: apiSecret));
    return testResult;
  }
}

Widget _host(_FakeSource source, {Future<void> Function(String)? onShare}) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: SmsSendersScreen(dataSource: source, onShare: onShare)),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

String _text(WidgetTester t, String key) => (t.widget(_key(key)) as Text).data!;

String _fieldText(WidgetTester t, String key) => t.widget<TextField>(_key(key)).controller!.text;

Future<void> _openCard(WidgetTester t, String businessName) async {
  await t.tap(find.text(businessName));
  await t.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester t, String key) async {
  await t.ensureVisible(_key(key));
  await t.pumpAndSettle();
}

List<SmsSenderEntry> _sample() => <SmsSenderEntry>[
      _entry('1', 'Bravo Shop', sender: const SmsSenderInfo(senderId: 'BRAVOSHOP', status: 'pending'), owner: 'Baraka Mushi', phone: '0711000111'),
      _entry('2', 'Delta Traders', sender: const SmsSenderInfo(senderId: 'DELTATRD', status: 'approved', needsAttention: true, lastError: 'Kilakona haikukubali jina la mtumaji "DELTATRD". Ujumbe HAUKUTUMWA. / Kilakona did not accept the sender name "DELTATRD". The text was NOT sent.', sentCount: 12, ownCount: 9, hasApiKey: true, apiKeyHint: '****5555', fallbackPlatform: false)),
      _entry('3', 'Charlie Mart', sender: const SmsSenderInfo(senderId: 'CHARLIEMRT', displayName: 'Charlie', status: 'approved', sentCount: 40, ownCount: 40)),
      _entry('4', 'Echo Ltd', sender: const SmsSenderInfo(senderId: 'ECHOLTD', status: 'rejected', note: 'Too generic')),
      _entry('5', 'Alpha Homes'),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => LocalizationService.instance.changeLanguage('sw'));

  group('the list', () {
    testWidgets('shows every business with its owner, sender name, status and what it sent', (t) async {
      _tall(t);
      await t.pumpWidget(_host(_FakeSource(_sample())));
      await t.pumpAndSettle();

      for (final String name in <String>['Bravo Shop', 'Delta Traders', 'Charlie Mart', 'Echo Ltd', 'Alpha Homes']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Baraka Mushi  ·  0711000111'), findsOneWidget);
      expect(_text(t, 'sender_name_1'), 'BRAVOSHOP');
      expect(_text(t, 'sender_name_3'), 'CHARLIEMRT');
      expect(find.text('“Charlie”'), findsOneWidget, reason: 'the short name used inside the text');
      expect(find.text('Inasubiri'), findsOneWidget);
      expect(find.text('Inahitaji kuangaliwa'), findsWidgets);
      expect(find.text('Imeidhinishwa'), findsOneWidget);
      expect(find.text('Imekataliwa'), findsOneWidget);
      expect(find.text('Haijawekwa'), findsWidgets);
      expect(find.text('akaunti yake'), findsOneWidget, reason: 'Delta has its own account');
      expect(find.textContaining('Zimetumwa: 40 · kwa jina lake: 40'), findsOneWidget);
      expect(_text(t, 'sender_error_2'), 'Kilakona haikukubali jina la mtumaji "DELTATRD". Ujumbe HAUKUTUMWA.', reason: 'one language: the one the app is in');
      expect(find.text('Too generic'), findsOneWidget);
      expect(find.textContaining('Bado hana jina la SMS'), findsOneWidget);
    });

    testWidgets('the chips show the counts and filter the list', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      expect(find.text('Zote (5)'), findsOneWidget);
      expect(find.text('Zinasubiri (1)'), findsOneWidget);
      expect(find.text('Zinahitaji kuangaliwa (1)'), findsOneWidget);
      expect(find.text('Zimeidhinishwa (2)'), findsOneWidget);
      expect(find.text('Zimekataliwa (1)'), findsOneWidget);
      expect(find.text('Hazijawekwa (1)'), findsOneWidget);

      await t.tap(_key('filter_pending'));
      await t.pumpAndSettle();
      expect(source.loads.last.status, 'pending');
      expect(find.text('Bravo Shop'), findsOneWidget);
      expect(find.text('Delta Traders'), findsNothing);

      await t.tap(_key('filter_attention'));
      await t.pumpAndSettle();
      expect(find.text('Delta Traders'), findsOneWidget);
      expect(find.text('Bravo Shop'), findsNothing);
    });

    testWidgets('on a phone the chips show that more are hidden, and choosing one slides the row on', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      expect(_key('chips_more_after'), findsOneWidget, reason: 'there are chips off the right edge');
      expect(_key('chips_more_before'), findsNothing);
      final double firstAt = t.getRect(_key('filter_all')).left;

      // choosing a chip that is on screen slides the row so the next ones come into view
      await t.tap(_key('filter_pending'));
      await t.pumpAndSettle();
      expect(source.loads.last.status, 'pending');
      expect(t.getRect(_key('filter_all')).left, lessThan(firstAt), reason: 'the row moved');
      expect(_key('chips_more_before'), findsOneWidget);

      // keep going to the end of the row: the last chip is whole and nothing is hidden after it
      for (int i = 0; i < 30 && _key('chips_more_after').evaluate().isNotEmpty; i++) {
        await t.tap(_key('chips_more_after'));
        await t.pumpAndSettle();
      }
      expect(_key('chips_more_after'), findsNothing);
      expect(t.getRect(_key('filter_none')).right, lessThanOrEqualTo(360));

      await t.tap(_key('filter_none'));
      await t.pumpAndSettle();
      expect(source.loads.last.status, 'none');
      expect(find.text('Alpha Homes'), findsOneWidget);
    });

    testWidgets('searching asks the server and an empty answer says so', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      await t.enterText(_key('senders_search'), 'charliemrt');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(source.loads.last.query, 'charliemrt');
      expect(find.text('Charlie Mart'), findsOneWidget);
      expect(find.text('Bravo Shop'), findsNothing);

      await t.enterText(_key('senders_search'), 'nothing like this');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(_key('senders_empty'), findsOneWidget);
    });

    testWidgets('a long list is loaded in pages', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(<SmsSenderEntry>[for (int i = 1; i <= 5; i++) _entry('$i', 'Business $i')])..pageSize = 3;
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      expect(find.text('Business 3'), findsOneWidget);
      expect(find.text('Business 4'), findsNothing);
      await _scrollTo(t, 'load_more');
      await t.tap(_key('load_more'));
      await t.pumpAndSettle();

      expect(source.loads.last.page, 2);
      expect(find.text('Business 5'), findsOneWidget);
      expect(find.text('Business 1'), findsOneWidget, reason: 'the first page is still there');
      expect(_key('load_more'), findsNothing);
    });

    testWidgets('it says what the others fall back to, and warns when no real SMS is on', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample())..delivering = false;
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      expect(_text(t, 'platform_sender_note'), contains('PLATFORM'));
      expect(_text(t, 'not_delivering_note'), contains('SMS imezimwa'));

      source.delivering = true;
      await _scrollTo(t, 'filter_none');
      await t.tap(_key('filter_none'));
      await t.pumpAndSettle();
      expect(_key('not_delivering_note'), findsNothing);
    });

    testWidgets('a failed load shows the reason and a retry', (t) async {
      _tall(t);
      final _ThrowingSource source = _ThrowingSource();
      await t.pumpWidget(ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ScreenUtilInit(designSize: const Size(800, 2400), builder: (_, __) => MaterialApp(home: SmsSendersScreen(dataSource: source))),
      ));
      await t.pumpAndSettle();

      expect(find.text('Server error'), findsOneWidget);
      source.fail = false;
      await t.tap(find.text('Jaribu tena'));
      await t.pumpAndSettle();
      expect(find.text('Alpha Homes'), findsOneWidget);
    });
  });

  group('setting a name', () {
    testWidgets('a name just approved by the provider is entered with its API key and saved as approved', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();

      await _openCard(t, 'Alpha Homes');
      expect(find.text('Hali'), findsOneWidget);
      expect(t.widget<ChoiceChip>(_key('status_approved')).selected, isTrue, reason: 'entered after approval, so it starts as approved');

      await t.enterText(_key('sender_id_field'), 'ALPHAHOMES');
      await t.enterText(_key('display_name_field'), 'Alpha');
      await t.enterText(_key('api_key_field'), 'KEY-ALPHA-1234');
      await t.enterText(_key('api_secret_field'), 'SECRET-ALPHA');
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();

      final SmsSenderEdit edit = source.saves.single.edit;
      expect(source.saves.single.id, '5');
      expect(edit.toJson(), <String, dynamic>{
        'sender_id': 'ALPHAHOMES',
        'display_name': 'Alpha',
        'note': '',
        'status': 'approved',
        'api_key': 'KEY-ALPHA-1234',
        'api_secret': 'SECRET-ALPHA',
      }, reason: 'and the server decides what happens if its account fails, unless this is touched');
      expect(_key('save_sender'), findsNothing, reason: 'the sheet closed');
      expect(_text(t, 'sender_name_5'), 'ALPHAHOMES');
      expect(find.text('akaunti yake'), findsNWidgets(2));
    });

    testWidgets('the key is hidden while typed and can be shown', (t) async {
      _tall(t);
      await t.pumpWidget(_host(_FakeSource(_sample())));
      await t.pumpAndSettle();
      await _openCard(t, 'Alpha Homes');

      expect(t.widget<TextField>(_key('api_key_field')).obscureText, isTrue);
      expect(t.widget<TextField>(_key('api_secret_field')).obscureText, isTrue);
      await _scrollTo(t, 'toggle_secrets');
      await t.tap(_key('toggle_secrets'));
      await t.pump();
      expect(t.widget<TextField>(_key('api_key_field')).obscureText, isFalse);
    });

    testWidgets('a saved key is never shown, only that it exists and its last four characters', (t) async {
      _tall(t);
      await t.pumpWidget(_host(_FakeSource(_sample())));
      await t.pumpAndSettle();
      await _openCard(t, 'Delta Traders');

      expect(_fieldText(t, 'api_key_field'), '', reason: 'the field is empty: the server never sends the key');
      expect(t.widget<TextField>(_key('api_key_field')).decoration!.hintText, contains('****5555'));
      expect(_key('remove_key'), findsOneWidget);
      expect(_key('sheet_attention'), findsOneWidget);
    });

    testWidgets('saving without typing a key sends none, so the saved one stays', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Delta Traders');

      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();

      final Map<String, dynamic> json = source.saves.single.edit.toJson();
      expect(json.containsKey('api_key'), isFalse);
      expect(json.containsKey('api_secret'), isFalse);
      expect(json.containsKey('clear_credentials'), isFalse);
      expect(source.entries.firstWhere((SmsSenderEntry e) => e.id == '2').sender.hasApiKey, isTrue);
    });

    testWidgets('the fallback switch appears with an account of its own and is only sent when touched', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Alpha Homes');

      expect(_key('fallback_switch'), findsNothing, reason: 'no key, no account of its own');
      await t.enterText(_key('sender_id_field'), 'ALPHAHOMES');
      await t.enterText(_key('api_key_field'), 'KEY-ALPHA-1234');
      await t.pump();
      await _scrollTo(t, 'fallback_switch');
      expect(t.widget<SwitchListTile>(_key('fallback_switch')).value, isFalse, reason: 'the platform credit is not spent unless allowed');
      expect(find.textContaining('hautumii salio lako'), findsOneWidget);

      await t.tap(_key('fallback_switch'));
      await t.pump();
      expect(find.textContaining('salio la jukwaa lako'), findsOneWidget);
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();

      expect(source.saves.single.edit.toJson()['fallback_platform'], isTrue);
    });

    testWidgets('removing the key asks first and then sends only that', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Delta Traders');

      await _scrollTo(t, 'remove_key');
      await t.tap(_key('remove_key'));
      await t.pumpAndSettle();
      expect(source.saves, isEmpty, reason: 'not before the question is answered');
      await t.tap(_key('confirm_remove_key'));
      await t.pumpAndSettle();

      final Map<String, dynamic> json = source.saves.single.edit.toJson();
      expect(json['clear_credentials'], isTrue);
      expect(json.containsKey('api_key'), isFalse);
      expect(json['sender_id'], 'DELTATRD', reason: 'the name stays');
      expect(source.entries.firstWhere((SmsSenderEntry e) => e.id == '2').sender.hasApiKey, isFalse);
    });

    testWidgets('saying no to the question keeps the key', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Delta Traders');

      await _scrollTo(t, 'remove_key');
      await t.tap(_key('remove_key'));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Ghairi')));
      await t.pumpAndSettle();

      expect(source.saves, isEmpty);
      expect(_key('save_sender'), findsOneWidget, reason: 'still on the sheet');
      expect(source.entries.firstWhere((SmsSenderEntry e) => e.id == '2').sender.hasApiKey, isTrue);
    });

    testWidgets('a waiting name is approved with one tap on Approved and Save', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Bravo Shop');

      expect(find.textContaining('Mteja ameomba jina hili'), findsOneWidget);
      expect(_fieldText(t, 'sender_id_field'), 'BRAVOSHOP');
      expect(t.widget<ChoiceChip>(_key('status_pending')).selected, isTrue);
      await t.tap(_key('status_approved'));
      await t.pump();
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();

      expect(source.saves.single.edit.status, 'approved');
      expect(find.text('Zinasubiri (0)'), findsOneWidget, reason: 'the counts follow');
    });

    testWidgets('rejecting asks for a reason that the customer is told', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Bravo Shop');

      expect(_key('note_field'), findsNothing);
      await t.tap(_key('status_rejected'));
      await t.pump();
      await t.enterText(_key('note_field'), 'Not accepted by the network');
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();

      expect(source.saves.single.edit.status, 'rejected');
      expect(source.saves.single.edit.note, 'Not accepted by the network');
    });

    testWidgets('clearing the name clears the business and sends no status', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Charlie Mart');

      await t.enterText(_key('sender_id_field'), '');
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();

      expect(source.saves.single.edit.toJson().containsKey('status'), isFalse);
      expect(source.entries.firstWhere((SmsSenderEntry e) => e.id == '3').sender.status, 'none');
    });

    testWidgets('a name that cannot work, or a key without a name, is refused before anything is sent', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Alpha Homes');

      await t.enterText(_key('sender_id_field'), 'AB');
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();
      expect(find.textContaining('herufi 3 hadi 11'), findsWidgets);

      await t.enterText(_key('sender_id_field'), '');
      await t.enterText(_key('api_key_field'), 'KEY-ONLY');
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();
      expect(_text(t, 'sender_error'), contains('Weka jina la mtumaji pamoja na API key'));

      await t.enterText(_key('sender_id_field'), 'ALPHAHOMES');
      await t.enterText(_key('api_key_field'), '');
      await t.enterText(_key('api_secret_field'), 'SECRET-ONLY');
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();
      expect(_text(t, 'sender_error'), contains('Weka API key pamoja na secret'));

      expect(source.saves, isEmpty);
    });

    testWidgets('the field takes only letters and digits', (t) async {
      _tall(t);
      await t.pumpWidget(_host(_FakeSource(_sample())));
      await t.pumpAndSettle();
      await _openCard(t, 'Alpha Homes');

      await t.enterText(_key('sender_id_field'), 'MAMA ASHA-1!');
      expect(_fieldText(t, 'sender_id_field'), 'MAMAASHA1');
    });

    testWidgets('a refusal from the server is shown and the sheet stays open with what was typed', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample())..saveError = Exception('Jina hili tayari linatumiwa na biashara nyingine.');
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Alpha Homes');

      await t.enterText(_key('sender_id_field'), 'BRAVOSHOP');
      await _scrollTo(t, 'save_sender');
      await t.tap(_key('save_sender'));
      await t.pumpAndSettle();

      expect(_text(t, 'sender_error'), 'Jina hili tayari linatumiwa na biashara nyingine.');
      expect(_fieldText(t, 'sender_id_field'), 'BRAVOSHOP');
    });
  });

  group('trying a name', () {
    testWidgets('sends what is typed on the page, before it is saved, and says what happened', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Alpha Homes');

      await t.enterText(_key('sender_id_field'), 'ALPHAHOMES');
      await t.enterText(_key('api_key_field'), 'KEY-TYPED');
      await t.enterText(_key('api_secret_field'), 'SECRET-TYPED');
      await t.enterText(_key('test_phone'), '0755111222');
      await _scrollTo(t, 'send_test');
      await t.tap(_key('send_test'));
      await t.pumpAndSettle();

      expect(source.tests.single, (id: '5', phone: '0755111222', senderId: 'ALPHAHOMES', apiKey: 'KEY-TYPED', apiSecret: 'SECRET-TYPED'));
      expect(source.saves, isEmpty, reason: 'a test saves nothing');
      expect(find.descendant(of: _key('test_result'), matching: find.textContaining('Kilakona imekubali')), findsOneWidget);
      expect(find.descendant(of: _key('test_result'), matching: find.textContaining('0755111222')), findsOneWidget);
    });

    testWidgets('says so when the provider refuses, is silent, or no real SMS is on', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Bravo Shop');
      await _scrollTo(t, 'send_test');

      for (final (String outcome, String expected) in <(String, String)>[
        ('refused', 'Kilakona imekataa jina hili au API key'),
        ('no_answer', 'Hakuna jibu kutoka Kilakona'),
        ('not_delivering', 'SMS imezimwa kwenye seva'),
      ]) {
        source.testResult = SmsSenderTestResult(outcome: outcome, senderId: 'BRAVOSHOP');
        await t.tap(_key('send_test'));
        await t.pumpAndSettle();
        expect(find.descendant(of: _key('test_result'), matching: find.textContaining(expected)), findsOneWidget, reason: outcome);
      }
    });

    testWidgets('needs a usable name first', (t) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source));
      await t.pumpAndSettle();
      await _openCard(t, 'Alpha Homes');

      await _scrollTo(t, 'send_test');
      await t.tap(_key('send_test'));
      await t.pumpAndSettle();

      expect(source.tests, isEmpty);
      expect(_key('sender_error'), findsOneWidget);
    });
  });

  group('taking it to the provider', () {
    testWidgets('copy puts the name, business, TIN and owner on the clipboard', (t) async {
      _tall(t);
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await t.pumpWidget(_host(_FakeSource(_sample())));
      await t.pumpAndSettle();
      await _openCard(t, 'Bravo Shop');
      await _scrollTo(t, 'copy_details');
      await t.tap(_key('copy_details'));
      await t.pump();

      expect(copied, 'BRAVOSHOP | Bravo Shop | 123-456-789 | Baraka Mushi | 0711000111');
      expect(find.text('Imenakiliwa'), findsOneWidget);
    });

    testWidgets('the share button lists the names that are waiting and is off when none is', (t) async {
      _tall(t);
      String? shared;
      final _FakeSource source = _FakeSource(_sample());
      await t.pumpWidget(_host(source, onShare: (String text) async => shared = text));
      await t.pumpAndSettle();

      await t.tap(_key('share_pending'));
      await t.pumpAndSettle();
      expect(shared, 'SENDER ID | BUSINESS | TIN | OWNER | OWNER PHONE\nBRAVOSHOP | Bravo Shop | 123-456-789 | Baraka Mushi | 0711000111');

      source.entries = source.entries.where((SmsSenderEntry e) => !e.sender.isPending).toList();
      await _scrollTo(t, 'filter_none');
      await t.tap(_key('filter_none'));
      await t.pumpAndSettle();
      expect(t.widget<IconButton>(_key('share_pending')).onPressed, isNull);
    });

    test('the registration list holds only waiting names', () {
      expect(smsSenderRegistrationList(_sample()), startsWith('SENDER ID | BUSINESS'));
      expect(smsSenderRegistrationList(_sample()).split('\n'), hasLength(2));
      expect(smsSenderRegistrationList(<SmsSenderEntry>[_entry('5', 'Alpha Homes')]), '');
      expect(
        smsSenderRegistrationList(<SmsSenderEntry>[_entry('6', 'No Tin', sender: const SmsSenderInfo(senderId: 'notin', status: 'pending'), tin: '', owner: '', phone: '')]),
        'SENDER ID | BUSINESS | TIN | OWNER | OWNER PHONE\nNOTIN | No Tin | - | - | -',
      );
    });
  });

  group('the waiting count', () {
    testWidgets('shows how many names wait, and nothing when none does or the count is unknown', (t) async {
      final _FakeSource source = _FakeSource(_sample());
      int? seen;
      await t.pumpWidget(MaterialApp(home: PendingSmsSendersCount(source: source, builder: (BuildContext c, int? n) {
        seen = n;
        return CountBadge(count: n);
      })));
      await t.pumpAndSettle();

      expect(seen, 1);
      expect(find.text('1'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(MaterialApp(home: PendingSmsSendersCount(source: _ThrowingSource(), builder: (BuildContext c, int? n) {
        seen = n;
        return CountBadge(count: n);
      })));
      await t.pumpAndSettle();
      expect(seen, isNull);
      expect(find.byKey(const ValueKey<String>('count_badge')), findsNothing);
    });
  });

  group('one language at a time', () {
    // Words of one language that must not appear in the other. Names, "Sender ID", "API key", "TIN" and "Kilakona"
    // are the same in both and are left out.
    const Set<String> swahili = <String>{
      'zote', 'zinasubiri', 'imeidhinishwa', 'inasubiri', 'imekataliwa', 'hazijawekwa', 'hifadhi', 'tuma', 'jaribio', 'biashara',
      'mteja', 'hali', 'ondoa', 'pakia', 'tafuta', 'akaunti', 'ujumbe', 'namba', 'simu', 'sababu', 'jina', 'weka', 'ikiachwa',
      'wazi', 'imehifadhiwa', 'andika', 'mpya', 'kubadilisha', 'nakili', 'imenakiliwa', 'ghairi', 'bado', 'gusa', 'kuliweka', 'imezimwa',
    };
    const Set<String> english = <String>{
      'all', 'waiting', 'approved', 'rejected', 'save', 'send', 'test', 'business', 'customer', 'status', 'remove', 'load', 'search',
      'account', 'text', 'texts', 'number', 'phone', 'reason', 'name', 'enter', 'optional', 'empty', 'saved', 'type', 'replace',
      'copy', 'copied', 'cancel', 'tap', 'own', 'owner', 'sent', 'under', 'left', 'used', 'switched', 'server',
    };

    Set<String> wordsOf(WidgetTester t) {
      final List<String> texts = <String>[
        for (final Text w in t.widgetList<Text>(find.byType(Text))) w.data ?? '',
        for (final TextField f in t.widgetList<TextField>(find.byType(TextField))) ...<String>[
          f.decoration?.labelText ?? '',
          f.decoration?.hintText ?? '',
          f.decoration?.helperText ?? '',
        ],
        for (final SwitchListTile s in t.widgetList<SwitchListTile>(find.byType(SwitchListTile))) ...<String>[
          if (s.title is Text) (s.title! as Text).data ?? '',
          if (s.subtitle is Text) (s.subtitle! as Text).data ?? '',
        ],
      ];
      // names a business is called are data, not words of the app
      const Set<String> data = <String>{'bravo', 'shop', 'delta', 'traders', 'charlie', 'mart', 'echo', 'ltd', 'alpha', 'homes', 'asha', 'owner', 'baraka', 'mushi', 'platform' /* the fixture's own sender name */};
      return <String>{
        for (final String s in texts) ...RegExp(r'[a-z]+').allMatches(s.toLowerCase()).map((RegExpMatch m) => m.group(0)!),
      }.difference(data);
    }

    for (final String language in <String>['sw', 'en']) {
      testWidgets('the list and the sheet use $language only', (t) async {
        _tall(t);
        await LocalizationService.instance.changeLanguage(language);
        final Set<String> foreign = language == 'en' ? swahili : english;
        final _FakeSource source = _FakeSource(_sample())..delivering = false;
        await t.pumpWidget(_host(source));
        await t.pumpAndSettle();

        expect(wordsOf(t).intersection(foreign), isEmpty, reason: '$language list shows ${wordsOf(t).intersection(foreign)}');

        for (final String business in <String>['Bravo Shop', 'Delta Traders', 'Alpha Homes', 'Echo Ltd']) {
          await _openCard(t, business);
          await _scrollTo(t, 'send_test');
          await t.tap(_key('send_test'));
          await t.pumpAndSettle();
          final Set<String> leaked = wordsOf(t).intersection(foreign);
          expect(leaked, isEmpty, reason: '$language sheet of $business shows $leaked');
          await t.tap(find.byType(ModalBarrier).last, warnIfMissed: false);
          await t.pumpAndSettle();
          if (_key('save_sender').evaluate().isNotEmpty) {
            await t.binding.handlePopRoute();
            await t.pumpAndSettle();
          }
        }
      });
    }
  });
}

class _ThrowingSource extends _FakeSource {
  _ThrowingSource() : super(<SmsSenderEntry>[_entry('5', 'Alpha Homes')]);

  bool fail = true;

  @override
  Future<SmsSenderPage> load({String status = 'all', String? query, int page = 1, int perPage = 50}) async {
    if (fail) throw Exception('Server error');
    return super.load(status: status, query: query, page: page, perPage: perPage);
  }
}
