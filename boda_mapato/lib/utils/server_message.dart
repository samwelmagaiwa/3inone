import '../services/localization_service.dart';

/// What a person should read when something the server said (or a failed request) has to be shown.
///
/// The server writes some of its messages in both languages, Swahili first: "Usajili wako ... / Your
/// registration ...". Dart wraps errors as "Exception: Login failed: Exception: <message>". Neither belongs
/// on a screen: this takes the wrappers off and keeps only the half in the language chosen in the app.
String readableServerMessage(final String raw) {
  String text = raw.trim();

  // "Exception: Login failed: Exception: the real message" -> "the real message"
  final RegExp wrapper = RegExp(r'^(?:Exception|Error|AuthHttpException|ApiException)\s*:\s*|^Login failed\s*:\s*', caseSensitive: false);
  while (wrapper.hasMatch(text)) {
    text = text.replaceFirst(wrapper, '').trim();
  }

  // "Swahili text / English text" -> the one that is read in the chosen language
  final int slash = text.indexOf(' / ');
  if (slash > 0 && slash == text.lastIndexOf(' / ')) {
    final String swahili = text.substring(0, slash).trim();
    final String english = text.substring(slash + 3).trim();
    // The server writes a sentence, then " / ", then the same sentence in English, so the first half ends
    // like a sentence. "Credit / Debt" or "Paid / Total" are plain text and stay as they are.
    if (swahili.length >= 8 && english.length >= 8 && RegExp(r'[.!?]$').hasMatch(swahili)) {
      return LocalizationService.instance.isSwahili ? swahili : english;
    }
  }

  return text;
}

/// [readableServerMessage] for anything that was thrown. A request that never reached the server (no internet,
/// a timeout) gets the plain "could not reach the server" sentence instead of a technical dump.
String readableErrorMessage(final Object error) {
  final String kind = error.runtimeType.toString();
  if (kind.contains('SocketException') ||
      kind.contains('TimeoutException') ||
      kind.contains('ClientException') ||
      kind.contains('HandshakeException')) {
    return LocalizationService.instance.translate('could_not_reach_the_server_check');
  }

  return readableServerMessage(error.toString());
}
