import 'package:boda_mapato/widgets/temporary_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The app's default language is Swahili, so these are the Swahili labels.
const String _title = 'Neno la siri la muda';
const String _copy = 'Nakili';
const String _copyAll = 'Nakili zote';
const String _copied = 'Imenakiliwa';
const String _done = 'Nimemaliza';

/// A page with one button that opens the dialog; records when it has been answered.
Widget _host(List<TemporaryCredential> credentials, List<String> log) => MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                await showTemporaryPasswords(context, credentials);
                log.add('closed');
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  group('temporaryPasswordOf', () {
    test('reads the generated password from an API response', () {
      expect(
        temporaryPasswordOf(<String, dynamic>{
          'status': 'success',
          'data': <String, dynamic>{'id': 'x', 'temporary_password': 'Kd7mQp2xRt'},
        }),
        'Kd7mQp2xRt',
      );
    });

    test('is null when there is nothing to hand over', () {
      expect(temporaryPasswordOf(null), isNull);
      expect(temporaryPasswordOf(<String, dynamic>{'status': 'success'}), isNull);
      expect(temporaryPasswordOf(<String, dynamic>{'data': 'text'}), isNull);
      expect(temporaryPasswordOf(<String, dynamic>{'data': <String, dynamic>{'temporary_password': null}}), isNull);
      expect(temporaryPasswordOf(<String, dynamic>{'data': <String, dynamic>{'temporary_password': ''}}), isNull);
    });
  });

  group('the dialog', () {
    testWidgets('shows the password for the person it is for, and only the button closes it', (t) async {
      final List<String> log = <String>[];
      await t.pumpWidget(_host(
        const <TemporaryCredential>[
          TemporaryCredential(name: 'Juma Driver', contact: '0755111222', password: 'Kd7mQp2xRt'),
        ],
        log,
      ));

      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      expect(find.text(_title), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('temp_password_0')), findsOneWidget);
      expect(find.text('Kd7mQp2xRt'), findsOneWidget);
      expect(find.textContaining('Juma Driver'), findsOneWidget, reason: 'it says who the password is for');

      // Tapping outside must not lose the only copy of the password.
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(log, isEmpty);

      await t.tap(find.text(_done));
      await t.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expect(log, <String>['closed']);
    });

    testWidgets('copies the password and says so', (t) async {
      String? clipboard;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await t.pumpWidget(_host(
        const <TemporaryCredential>[
          TemporaryCredential(name: 'Asha Tenant', contact: 'asha@example.test · 0712000111', password: 'Zm4nWq8cHv'),
        ],
        <String>[],
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      await t.tap(find.text(_copy));
      await t.pumpAndSettle();

      expect(clipboard, 'Asha Tenant (asha@example.test · 0712000111): Zm4nWq8cHv');
      expect(find.text(_copied), findsOneWidget);
    });

    testWidgets('lists every password of a bulk import, with who each is for', (t) async {
      await t.pumpWidget(_host(
        const <TemporaryCredential>[
          TemporaryCredential(name: 'Juma', contact: '0755111222', password: 'AAAAbbbb23'),
          TemporaryCredential(name: 'Amina', contact: '0755333444', password: 'CCCCdddd45'),
          TemporaryCredential(name: 'Said', contact: '0755555666', password: 'EEEEffff67'),
        ],
        <String>[],
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      for (int i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey<String>('temp_password_$i')), findsOneWidget);
      }
      expect(find.text('Juma · 0755111222'), findsOneWidget);
      expect(find.text('Amina · 0755333444'), findsOneWidget);
      expect(find.text(_copyAll), findsOneWidget);
    });

    testWidgets('shows nothing at all when there are no passwords', (t) async {
      final List<String> log = <String>[];
      await t.pumpWidget(_host(const <TemporaryCredential>[], log));

      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      expect(find.text(_title), findsNothing);
      expect(log, <String>['closed'], reason: 'the caller carries on straight away');
    });

    testWidgets('can be shown from a screen that has already closed itself', (t) async {
      // The add-driver sheet pops itself and THEN shows the password, so it takes the
      // navigator before it goes: the dialog must still appear and be answerable.
      final List<String> log = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (BuildContext home) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(home).push(MaterialPageRoute<void>(
                builder: (BuildContext sheet) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      final NavigatorState navigator = Navigator.of(sheet);
                      navigator.pop();
                      await showTemporaryPasswordsOn(navigator, const <TemporaryCredential>[
                        TemporaryCredential(name: 'Juma', password: 'Kd7mQp2xRt'),
                      ]);
                      log.add('answered');
                    },
                    child: const Text('save'),
                  ),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.text('save'));
      await t.pumpAndSettle();

      expect(find.text('Kd7mQp2xRt'), findsOneWidget);
      await t.tap(find.text(_done));
      await t.pumpAndSettle();
      expect(log, <String>['answered']);
    });
  });
}
