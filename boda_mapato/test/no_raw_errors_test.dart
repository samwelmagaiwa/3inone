import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An error shown to a person must be plain words in the chosen language: "Could not load the drivers: Token has
/// expired", never "Exception: Login failed: Exception: ... / ...". `readableErrorMessage` (utils/server_message.dart)
/// does that, and banners, ApiException and translateWith already apply it. This catches the places that would
/// bypass all three: an error turned into text by hand and put on a screen.
void main() {
  final RegExp errorVar = RegExp(r'\b(?:e|err|error|ex|exception)\b');

  // Lines of code (not comments), with the files they are in.
  Iterable<MapEntry<String, List<String>>> sources() sync* {
    for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) {
        continue;
      }
      final String code = f.readAsStringSync().replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      yield MapEntry<String, List<String>>(f.path.replaceAll('\\', '/'), code.split('\n'));
    }
  }

  bool isLogging(String line) => RegExp(r'debugPrint|\bprint\(|Log\.|\blog\(|developer\.log').hasMatch(line);

  test('no screen shows an error object turned into text by hand', () {
    final List<String> found = <String>[];
    final RegExp toastWithToString = RegExp(
      r'(?:showErrorSnackBar|showInfoSnackBar|showWarningSnackBar|showSuccessSnackBar|_showErrorSnackBar|_showSnackBar|_showError|_showSnack)\([^;]*\b(?:e|err|error|ex)\.toString\(\)',
    );
    final RegExp handMadeStrip = RegExp(r"""\.(?:replaceAll|replaceFirst)\(\s*(?:RegExp\(r?['"]\^?\(?(?:Api)?\)?\??Exception|['"](?:Exception|ApiException))""");
    final RegExp errorField = RegExp(r'(?:[Ee]rror\w*|[Mm]essage|errorMsg)\s*=\s*(?:e|err|error|ex)\.toString\(\)\s*;');

    for (final MapEntry<String, List<String>> file in sources()) {
      if (file.key.endsWith('utils/server_message.dart')) {
        continue; // this is where the cleaning is done
      }
      for (int i = 0; i < file.value.length; i++) {
        final String line = file.value[i];
        if (isLogging(line) || line.contains('readableErrorMessage')) {
          continue;
        }
        if (toastWithToString.hasMatch(line) || handMadeStrip.hasMatch(line) || errorField.hasMatch(line)) {
          found.add('${file.key}:${i + 1}  ${line.trim()}');
        }
      }
    }
    expect(found, isEmpty, reason: 'use readableErrorMessage(e) instead:\n${found.join('\n')}');
  });

  test('no message is built by writing the error straight into a sentence', () {
    final List<String> found = <String>[];
    // "Failed to load: $e" / "Error: ${e}" on a line that is an error message (not a log line, not an endpoint "$e")
    final RegExp sentenceWithError = RegExp(r"""['"][^'"\n]*(?:Failed|failed|Imeshindikana|Hitilafu|Error|error|Could not|could not)[^'"\n]*\$\{?(?:e|err|error|ex)\}?(?![A-Za-z_\.(\[])""");
    for (final MapEntry<String, List<String>> file in sources()) {
      for (int i = 0; i < file.value.length; i++) {
        final String line = file.value[i];
        if (isLogging(line) || line.contains('readableErrorMessage') || !errorVar.hasMatch(line)) {
          continue;
        }
        if (sentenceWithError.hasMatch(line)) {
          found.add('${file.key}:${i + 1}  ${line.trim()}');
        }
      }
    }
    expect(found, isEmpty, reason: 'put the error through readableErrorMessage(e) or translateWith:\n${found.join('\n')}');
  });
}
